-- ============================================================================
-- VietPay core ledger | initial 11 (down): drop immutability enforcement
-- Reverses: 11_immutability.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- Drops the triggers and the shared function.  Privilege grants are not
-- restored here: in a teardown the tables themselves are dropped next (steps 09,
-- 07), which removes their grants.  To re-open mutation WITHOUT tearing down,
-- a superuser can re-grant manually.
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_entries_immutable       ON entries;
DROP TRIGGER IF EXISTS trg_entries_no_truncate     ON entries;
DROP TRIGGER IF EXISTS trg_audit_logs_immutable    ON audit_logs;
DROP TRIGGER IF EXISTS trg_audit_logs_no_truncate  ON audit_logs;

-- per-partition TRUNCATE guards attached in 11 (up); drop them too so a
-- `redo 11` without tearing down entries leaves no orphaned triggers.
DO $$
DECLARE part regclass;
BEGIN
    IF to_regclass('public.entries') IS NOT NULL THEN
        FOR part IN
            SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'entries'::regclass
        LOOP
            EXECUTE format('DROP TRIGGER IF EXISTS trg_entries_no_truncate ON %s', part);
        END LOOP;
    END IF;
END $$;

DROP FUNCTION IF EXISTS deny_mutation();
