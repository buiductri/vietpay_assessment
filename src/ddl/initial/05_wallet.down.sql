-- ============================================================================
-- VietPay core ledger | initial 05 (down): drop wallets
-- Reverses: 05_wallet.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- `entries` (step 07) references wallets via the composite FK; reverse-order
-- teardown drops that first.  Dropping the table also drops idx_wallets_account
-- and the wallets_id_currency_uq constraint.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS wallets;
