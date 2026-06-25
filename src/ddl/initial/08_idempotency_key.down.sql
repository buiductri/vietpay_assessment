-- ============================================================================
-- VietPay core ledger | initial 08 (down): drop idempotency_keys
-- Reverses: 08_idempotency_key.up.sql   Idempotent.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS idempotency_keys;
