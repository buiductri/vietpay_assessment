-- ============================================================================
-- VietPay core ledger | initial 04 (down): drop accounts
-- Reverses: 04_account.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- `wallets` (step 05) references this table; reverse-order teardown drops that
-- first.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS accounts;
