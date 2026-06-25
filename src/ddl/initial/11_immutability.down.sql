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

DROP FUNCTION IF EXISTS deny_mutation();
