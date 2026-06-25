-- ============================================================================
-- VietPay core ledger | initial 09 (down): drop audit_logs
-- Reverses: 09_audit_log.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- The immutability trigger (step 11) is attached to audit_logs; DROP TABLE
-- cascade-drops it.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS audit_logs;
