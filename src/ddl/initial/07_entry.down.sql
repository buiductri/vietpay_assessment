-- ============================================================================
-- VietPay core ledger | initial 07 (down): drop entries
-- Reverses: 07_entry.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- The zero-sum trigger (step 10) and immutability triggers (step 11) are
-- attached to `entries`; DROP TABLE cascade-drops them.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS entries;
