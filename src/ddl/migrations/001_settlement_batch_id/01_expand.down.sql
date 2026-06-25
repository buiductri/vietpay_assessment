-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | EXPAND (down)
-- Reverses 01_expand.up.sql. Idempotent.  Table: entries (PARTITIONED)
-- ----------------------------------------------------------------------------
-- DROP COLUMN on the partitioned parent cascades to all partitions.
--
-- ROLLBACK ASYMMETRY (read before running): dropping the column is always safe
-- for OLD readers, but if step 05's NOT NULL is still in place a non-writing
-- (rolled-back) app version will fail its INSERTs.  Correct order to fully
-- unwind is 05.down (DROP NOT NULL) -> 04.down -> 03.down (re-disable) ... or
-- simply 03 (leave immutability ON) -> 02.down -> 01.down.  See README.
-- SAFE to run with --single-transaction.
-- ============================================================================

DO $$
DECLARE attempts int := 0;
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '3s';
            ALTER TABLE entries DROP COLUMN IF EXISTS settlement_batch_id;
            EXIT;
        EXCEPTION WHEN lock_not_available THEN
            attempts := attempts + 1;
            IF attempts >= 5 THEN RAISE; END IF;
            RAISE NOTICE 'DROP COLUMN: lock busy, retry % of 5 after 2s', attempts;
            PERFORM pg_sleep(2);
        END;
    END LOOP;
END $$;

-- Parent table last.
DROP TABLE IF EXISTS settlement_batches;
