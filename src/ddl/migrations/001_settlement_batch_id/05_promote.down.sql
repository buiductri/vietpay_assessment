-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | PROMOTE (down)
-- Reverses 05_promote.up.sql. Idempotent.  Table: entries (PARTITIONED)
-- ----------------------------------------------------------------------------
-- Relaxes the column back to NULLABLE (recurses to every partition).  This is the
-- rollback that MATTERS: it is what lets a rolled-back (non-writing) app version
-- INSERT again, so it must run BEFORE the app is reverted past the dual-write
-- version (rollback asymmetry).  Fast metadata change under a brief AEL.
-- SAFE to run with --single-transaction.
-- ============================================================================

DO $$
DECLARE attempts int := 0;
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '3s';
            ALTER TABLE entries ALTER COLUMN settlement_batch_id DROP NOT NULL;
            EXIT;
        EXCEPTION WHEN lock_not_available THEN
            attempts := attempts + 1;
            IF attempts >= 5 THEN RAISE; END IF;
            RAISE NOTICE 'DROP NOT NULL: lock busy, retry % of 5 after 2s', attempts;
            PERFORM pg_sleep(2);
        END;
    END LOOP;
END $$;

-- Drop the helper CHECK if a previous PROMOTE left it in place.
ALTER TABLE entries DROP CONSTRAINT IF EXISTS entries_sbid_not_null;
