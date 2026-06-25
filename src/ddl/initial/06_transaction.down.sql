-- ============================================================================
-- VietPay core ledger | initial 06 (down): drop transactions
-- Reverses: 06_transaction.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- `entries`, `idempotency_keys`, and `audit_logs` reference transactions;
-- reverse-order teardown drops those first.  Dropping the table drops its
-- indexes too.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS transactions;
