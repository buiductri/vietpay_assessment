-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | BACKFILL (down)
-- Reverses 02_backfill.up.sql. Idempotent.  Table: entries (PARTITIONED)
-- ----------------------------------------------------------------------------
-- Drops the backfill procedure and, as a safety net, RE-ENABLES the immutability
-- deny trigger on parent + every partition (in case this down runs after an
-- aborted backfill that left it disabled; step 03 is the normal forward
-- re-enable).  The backfilled sentinel value is harmless and is removed wholesale
-- by 01.down (DROP COLUMN); un-filling rows is only valid while the column is
-- still NULLABLE (before step 05) and is left commented.
-- SAFE to run with --single-transaction.
-- ============================================================================

DROP PROCEDURE IF EXISTS backfill_settlement_batch_id(int, numeric, uuid);

-- Restore immutability if a partial run left the deny trigger disabled.
DO $$
DECLARE part regclass;
BEGIN
    EXECUTE 'ALTER TABLE entries ENABLE TRIGGER trg_entries_immutable';
    FOR part IN
        SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'entries'::regclass
    LOOP
        EXECUTE format('ALTER TABLE %s ENABLE TRIGGER trg_entries_immutable', part);
    END LOOP;
END $$;

-- Optional un-fill (ONLY valid before step 05 SET NOT NULL; it is itself an
-- UPDATE on entries, so it needs the deny trigger disabled around it):
--   (disable trigger on parent+partitions as in 02_backfill.up.sql)
--   UPDATE entries SET settlement_batch_id = NULL
--    WHERE settlement_batch_id = '00000000-0000-0000-0000-000000000000';
--   (re-enable trigger as above)
