-- ============================================================================
-- VietPay core ledger | initial 07 (down): drop entries
-- Reverses: 07_entry.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- `entries` is partitioned: DROP TABLE cascade-drops every monthly partition
-- (and the DEFAULT) plus their indexes.  The zero-sum trigger (step 10) and
-- immutability triggers (step 11) attached to `entries` go with it.  The
-- partition factory function is dropped too.
-- ----------------------------------------------------------------------------

DROP TABLE    IF EXISTS entries;
DROP FUNCTION IF EXISTS create_entries_partition(date);
