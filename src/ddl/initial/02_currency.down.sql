-- ============================================================================
-- VietPay core ledger | initial 02 (down): drop currencies lookup
-- Reverses: 02_currency.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- exchange_rates (step 03) references this table; reverse-order teardown drops
-- that first.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS currencies;
