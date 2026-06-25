-- ============================================================================
-- VietPay core ledger | initial 10 (down): drop zero-sum invariant
-- Reverses: 10_integrity_zero_sum.up.sql   Idempotent.
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_entries_balanced ON entries;
DROP FUNCTION IF EXISTS assert_transaction_balanced();
