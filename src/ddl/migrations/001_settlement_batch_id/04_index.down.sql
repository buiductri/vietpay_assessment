-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | INDEX (down)
-- Reverses 04_index.up.sql. Idempotent.
-- Table: entries (PARTITIONED)
-- ----------------------------------------------------------------------------
-- Dropping the parent partitioned index drops its attached leaf indexes too, so
-- one DROP is enough.  A partitioned index cannot be dropped CONCURRENTLY, but
-- DROP INDEX on it takes only a brief lock (it is metadata plus dropping the leaf
-- indexes).  Any leftover detached/INVALID leaf indexes from a failed run are
-- swept by name afterwards.
-- SAFE to run with --single-transaction.
-- ============================================================================

DROP INDEX IF EXISTS idx_entries_settlement_batch;

-- Sweep any orphaned leaf indexes (e.g. built but never attached, or left by a
-- failed CIC).  Scoped by OID to indexes ON entries' partitions, so a same-named
-- index in another schema is never touched.
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT ic.relname
          FROM pg_index x
          JOIN pg_class ic ON ic.oid = x.indexrelid
         WHERE ic.relname LIKE '%\_sbid_idx'
           AND x.indrelid IN (SELECT inhrelid FROM pg_inherits WHERE inhparent = 'entries'::regclass)
    LOOP
        EXECUTE format('DROP INDEX IF EXISTS %I', r.relname);
    END LOOP;
END $$;
