-- ============================================================================
-- VietPay core ledger | initial 03 (down): drop exchange_rates lookup
-- Reverses: 03_exchange_rate.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- `transactions` (step 06) references this table; reverse-order teardown drops
-- that step first.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS exchange_rates;
