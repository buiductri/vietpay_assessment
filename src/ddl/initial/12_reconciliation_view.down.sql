-- ============================================================================
-- VietPay core ledger | initial 12 (down): drop reconciliation views
-- Reverses: 12_reconciliation_view.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- Grants on the base tables disappear when those tables are dropped in later
-- (reverse-order) steps, so only the views need explicit removal here.
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS balance_audit_drift;
DROP VIEW IF EXISTS balance_audit;
