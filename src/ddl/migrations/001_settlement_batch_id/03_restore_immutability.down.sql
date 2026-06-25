-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | RESTORE IMMUTABILITY (down)
-- Reverses 03_restore_immutability.up.sql. Idempotent.  Table: entries
-- ----------------------------------------------------------------------------
-- Re-disables the deny trigger (parent + every partition).  Only meaningful when
-- rolling back to RESUME the backfill; otherwise prefer to keep immutability ON.
-- SAFE to run with --single-transaction.
-- ============================================================================

DO $$
DECLARE part regclass;
BEGIN
    EXECUTE 'ALTER TABLE entries DISABLE TRIGGER trg_entries_immutable';
    FOR part IN
        SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'entries'::regclass
    LOOP
        EXECUTE format('ALTER TABLE %s DISABLE TRIGGER trg_entries_immutable', part);
    END LOOP;
END $$;
