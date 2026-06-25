-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | RESTORE IMMUTABILITY (up)
-- Reverse: 03_restore_immutability.down.sql.  Idempotent.
-- Table: entries (PARTITIONED)
-- ----------------------------------------------------------------------------
-- Re-enables the deny trigger that step 02 disabled, on the parent AND every
-- partition.  This is a STANDALONE, MANDATORY, idempotent step (not the
-- happy-path tail of the backfill) precisely so an aborted backfill cannot
-- silently leave `entries` writable.  Run it the moment the backfill completes.
--
-- It then VERIFIES that NO copy of the trigger is left disabled, because
-- `deploy.sh verify` only checks the trigger EXISTS on the parent, not that it
-- (and every partition clone) is ENABLED -- a left-disabled partition clone would
-- otherwise pass verification unnoticed.
-- SAFE to run with --single-transaction.
-- ============================================================================

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

-- Assert immutability is back ON everywhere.  tgenabled 'D' = disabled.
-- Scope by OID (the entries parent + its partitions from pg_inherits), NOT by
-- relname, so a same-named table in another schema cannot skew the count.
DO $$
DECLARE
    disabled int;
    present  int;
BEGIN
    SELECT count(*) FILTER (WHERE t.tgenabled = 'D'),
           count(*)
      INTO disabled, present
      FROM pg_trigger t
     WHERE t.tgname = 'trg_entries_immutable'
       AND t.tgrelid IN (
            SELECT 'entries'::regclass
            UNION ALL
            SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'entries'::regclass
       );

    IF present = 0 THEN
        RAISE EXCEPTION 'trg_entries_immutable not found on entries -- immutability is MISSING';
    ELSIF disabled > 0 THEN
        RAISE EXCEPTION 'trg_entries_immutable still DISABLED on % relation(s) -- entries unprotected', disabled;
    END IF;
    RAISE NOTICE 'immutability restored: trg_entries_immutable enabled on all % relations (parent + partitions)', present;
END $$;
