-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | PROMOTE (up)
-- Reverse: 05_promote.down.sql.  Idempotent.
-- Table: entries (PARTITIONED, monthly RANGE on created_at)
-- ----------------------------------------------------------------------------
-- Makes settlement_batch_id NOT NULL WITHOUT a blocking full-table scan and
-- WITHOUT blocking concurrent reads/writes.
--
-- The naive `ALTER COLUMN ... SET NOT NULL` takes ACCESS EXCLUSIVE and scans all
-- 50M rows (every partition) to prove no NULLs -- that scan is the outage.  The
-- PG 12+ avoidance, which recurses correctly across the partitioned table:
--   1. ADD CONSTRAINT ... CHECK (col IS NOT NULL) NOT VALID  -- instant, brief AEL,
--                                                               recurses to partitions
--   2. VALIDATE CONSTRAINT                                   -- SHARE UPDATE EXCLUSIVE:
--                                                               scans, reads + writes continue
--   3. ALTER COLUMN ... SET NOT NULL                         -- FAST: the planner trusts the
--                                                               validated CHECK and skips the scan
--                                                               on the parent and each partition
--   4. drop the now-redundant CHECK (SET NOT NULL subsumes it)
--
-- ORDER: run only AFTER step 02 backfill is complete AND step 03 re-enabled the
-- immutability trigger.  SET NOT NULL is DDL, so the deny trigger does not affect
-- it; this step writes no rows.
-- SAFE to run with --single-transaction (on a very large table you may prefer the
-- VALIDATE in its own transaction).
-- ============================================================================

-- 1. NOT VALID NOT-NULL check: guards new rows instantly, leaves old rows
--    unscanned.  Skipped if the column is already NOT NULL (re-run) or the check
--    already exists.
DO $$
DECLARE col_notnull boolean;
BEGIN
    SELECT a.attnotnull INTO col_notnull
      FROM pg_attribute a
     WHERE a.attrelid = 'entries'::regclass
       AND a.attname  = 'settlement_batch_id'
       AND NOT a.attisdropped;

    IF col_notnull THEN
        RAISE NOTICE 'settlement_batch_id already NOT NULL; promotion already done';
    ELSIF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'entries_sbid_not_null' AND conrelid = 'entries'::regclass
    ) THEN
        EXECUTE 'ALTER TABLE entries
                   ADD CONSTRAINT entries_sbid_not_null
                   CHECK (settlement_batch_id IS NOT NULL) NOT VALID';
    END IF;
END $$;

-- 2. VALIDATE the NOT-NULL check (only if present and not yet validated).
--    SHARE UPDATE EXCLUSIVE: concurrent reads and writes keep running.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'entries_sbid_not_null'
          AND conrelid = 'entries'::regclass
          AND NOT convalidated
    ) THEN
        EXECUTE 'ALTER TABLE entries VALIDATE CONSTRAINT entries_sbid_not_null';
    END IF;
END $$;

-- 3. SET NOT NULL: fast in PG 12+ because the validated CHECK lets it skip the
--    scan on the parent and every partition.  Brief ACCESS EXCLUSIVE under a
--    bounded lock_timeout + retry.  No-op if already NOT NULL, so re-run is safe.
DO $$
DECLARE attempts int := 0;
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '3s';
            ALTER TABLE entries ALTER COLUMN settlement_batch_id SET NOT NULL;
            EXIT;
        EXCEPTION WHEN lock_not_available THEN
            attempts := attempts + 1;
            IF attempts >= 5 THEN RAISE; END IF;
            RAISE NOTICE 'SET NOT NULL: lock busy, retry % of 5 after 2s', attempts;
            PERFORM pg_sleep(2);
        END;
    END LOOP;
END $$;

-- 4. The explicit NOT-NULL CHECK is now redundant with the column's NOT NULL.
ALTER TABLE entries DROP CONSTRAINT IF EXISTS entries_sbid_not_null;
