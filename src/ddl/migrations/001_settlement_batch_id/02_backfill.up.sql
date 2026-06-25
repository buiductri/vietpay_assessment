-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | BACKFILL (up)
-- Reverse: 02_backfill.down.sql.  Idempotent and RESUMABLE.
-- Table: entries (PARTITIONED, monthly RANGE on created_at)
-- ----------------------------------------------------------------------------
-- Fills settlement_batch_id on the HISTORICAL rows (the rows the dual-write app
-- never touched), PARTITION BY PARTITION, in small committed batches.  Only rows
-- still NULL are touched, so a re-run continues where a previous run stopped and
-- a row already written by the live app is left alone.
--
-- ORDER: run AFTER the dual-write app deploy is live and verified (new rows are
-- already non-NULL), and BEFORE step 05 (NOT NULL promotion).
--
-- WHY PARTITION BY PARTITION: `ctid` is unique only WITHIN one table, so a single
-- `... WHERE ctid IN (SELECT ctid FROM entries ...)` over the partitioned parent
-- is unsafe (the same ctid exists in several partitions).  Iterating each leaf
-- partition keeps ctid batching correct, updates the partition directly (no tuple
-- routing), and is the partitioning PAYOFF: old months are static, so each
-- partition backfills with far less contention and could be parallelised.
--
-- *** IMMUTABILITY: entries is append-only ***
-- `entries` carries the two-layer immutability guard from initial/11:
--   (a) REVOKE UPDATE from vietpay_app          (privilege layer)
--   (b) trg_entries_immutable deny trigger, which fires for EVERY role, owner
--       included (a trigger is universal; REVOKE only binds the role it names),
--       and is cloned onto every partition.
-- A NOT NULL backfill must UPDATE every historical row, so this migration, run by
-- the OWNER/DBA (never vietpay_app), DISABLES trg_entries_immutable on the parent
-- AND on every partition for the backfill window.  That is the audited,
-- intentional act the trigger's own comment sanctions.  The PRIVILEGE layer (a)
-- still holds throughout, so the APPLICATION still cannot rewrite history during
-- the window -- the payoff of the two-layer design.  The trigger is left DISABLED
-- at the end of this file ON PURPOSE; step 03 re-enables it as its own mandatory,
-- idempotent step, so an aborted backfill cannot silently leave entries writable.
--   (We disable on parent AND each partition explicitly: on PG 15+ disabling the
--    parent already cascades, but on PG 14 it does NOT, so the loop is
--    version-safe.  `SET session_replication_role = replica` would be simpler but
--    needs superuser, which the migration role does not have here.)
--
-- The zero-sum trigger (trg_entries_balanced) is AFTER **INSERT** only
-- (initial/10), so the backfill UPDATE does NOT fire it -- no balance re-check
-- overhead and nothing to disable.  We touch only settlement_batch_id, never
-- amount, so balances are unaffected anyway.
--
-- *** DO NOT run with --single-transaction ***  the procedure COMMITs each batch.
-- Run as:  psql -f 02_backfill.up.sql
-- ============================================================================

-- Lift the immutability deny trigger for the backfill window: parent + every
-- partition.  Idempotent (DISABLE on an already-disabled trigger is a no-op).
DO $$
DECLARE part regclass;
BEGIN
    EXECUTE 'ALTER TABLE entries DISABLE TRIGGER trg_entries_immutable';
    FOR part IN
        SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'entries'::regclass
    LOOP
        EXECUTE format('ALTER TABLE %s DISABLE TRIGGER trg_entries_immutable', part);
    END LOOP;
END $$;

-- A lock_timeout means a single batch waited too long on a row lock; the backfill
-- is resumable, so just re-run.  SET (not LOCAL) so it survives the per-batch
-- COMMITs below.  Cold historical rows have ~no contention, so this rarely fires.
SET lock_timeout = '10s';

-- Batched, committed, resumable, partition-by-partition backfill.
CREATE OR REPLACE PROCEDURE backfill_settlement_batch_id(
    batch_size int     DEFAULT 10000,
    sleep_secs numeric DEFAULT 0.1,
    sentinel   uuid    DEFAULT '00000000-0000-0000-0000-000000000000'
)
LANGUAGE plpgsql
AS $$
DECLARE
    parts   regclass[];
    part    regclass;
    touched bigint;
    total   bigint := 0;
BEGIN
    -- Snapshot the partition list into an array FIRST: committing inside a FOR
    -- loop that is still iterating a query cursor is not allowed, but FOREACH
    -- over an array holds no portal, so per-batch COMMIT is fine.
    SELECT array_agg(inhrelid::regclass ORDER BY inhrelid::regclass::text)
      INTO parts
      FROM pg_inherits WHERE inhparent = 'entries'::regclass;

    -- Fall back to the table itself if entries is NOT partitioned, so this never
    -- silently no-ops on an unexpected shape (ctid is unique within a single
    -- table, so the same batching is correct there too).
    IF parts IS NULL THEN
        parts := ARRAY['entries'::regclass];
        RAISE NOTICE 'entries has no partitions; backfilling the table directly';
    END IF;

    FOREACH part IN ARRAY parts LOOP
        LOOP
            EXECUTE format(
                'UPDATE %s SET settlement_batch_id = $1
                  WHERE ctid IN (SELECT ctid FROM %s WHERE settlement_batch_id IS NULL LIMIT $2)',
                part, part)
            USING sentinel, batch_size;
            GET DIAGNOSTICS touched = ROW_COUNT;
            EXIT WHEN touched = 0;
            total := total + touched;
            COMMIT;                       -- release row locks + advance WAL per batch
            PERFORM pg_sleep(sleep_secs);  -- throttle so replicas + autovacuum keep up
        END LOOP;
        RAISE NOTICE 'backfill: % done (running total % rows)', part, total;
    END LOOP;
    RAISE NOTICE 'backfill complete: % rows filled this run', total;
END;
$$;

CALL backfill_settlement_batch_id();

-- NOTE: trg_entries_immutable is still DISABLED here. Step 03 MUST run next.
