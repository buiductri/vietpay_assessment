-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | INDEX (up)
-- Reverse: 04_index.down.sql.  Idempotent.
-- Table: entries (PARTITIONED, monthly RANGE on created_at)
-- ----------------------------------------------------------------------------
-- Builds an index on the new column, online, AFTER the backfill (so the 50M
-- backfill UPDATEs do not churn the index).
--
-- WHY NOT `CREATE INDEX CONCURRENTLY ON entries (...)`: that is REJECTED on a
-- partitioned parent ("cannot create index on partitioned table entries
-- concurrently").  A plain `CREATE INDEX ON entries (...)` would work but takes a
-- SHARE lock on the parent and builds every partition's index while blocking
-- writes -- not zero-downtime.  The online pattern for a partitioned table:
--   1. CREATE INDEX ON ONLY entries (...)   -- parent-only stub, INVALID, instant
--   2. per partition: CREATE INDEX CONCURRENTLY on the leaf (online, no blocking)
--   3. ALTER INDEX <parent> ATTACH PARTITION <leaf index> for each leaf
--   4. once every partition is attached, the parent index flips to VALID
--      automatically.
--
-- *** DO NOT run with --single-transaction ***  CREATE INDEX CONCURRENTLY may not
-- run inside a transaction block, and the per-partition statements below are
-- emitted with psql \gexec so each runs in its own transaction.  CIC is not
-- atomic: a cancelled run leaves an INVALID leaf index, so we drop any invalid
-- leftover first, then rebuild.  Run as:  psql -f 04_index.up.sql
-- ============================================================================

-- 1. Parent stub index, parent only.  INVALID until all partitions are attached.
--    Metadata only, brief lock.  IF NOT EXISTS makes re-run a no-op.
CREATE INDEX IF NOT EXISTS idx_entries_settlement_batch
    ON ONLY entries (settlement_batch_id);

-- Drop any INVALID leftover leaf index from a previous failed CIC, so the next
-- step can rebuild it cleanly.  Scoped by OID (indexes ON entries' partitions),
-- not by relname, so it cannot touch a same-named index in another schema.
SELECT format('DROP INDEX IF EXISTS %I', ic.relname)
  FROM pg_index x
  JOIN pg_class ic ON ic.oid = x.indexrelid
 WHERE NOT x.indisvalid
   AND ic.relname LIKE '%\_sbid_idx'
   AND x.indrelid IN (SELECT inhrelid FROM pg_inherits WHERE inhparent = 'entries'::regclass)
\gexec

-- 2. Build the leaf index CONCURRENTLY on every partition (each its own txn via
--    \gexec).  IF NOT EXISTS skips partitions already built.
SELECT format('CREATE INDEX CONCURRENTLY IF NOT EXISTS %I ON %s (settlement_batch_id)',
              c.relname || '_sbid_idx', c.oid::regclass)
  FROM pg_inherits i
  JOIN pg_class c ON c.oid = i.inhrelid
 WHERE i.inhparent = 'entries'::regclass
 ORDER BY c.relname
\gexec

-- 3. Attach each leaf index to the parent stub (idempotent: skip leaves whose
--    index is already attached to the parent index).  When the last one attaches,
--    idx_entries_settlement_batch becomes VALID automatically.
SELECT format('ALTER INDEX idx_entries_settlement_batch ATTACH PARTITION %I',
              c.relname || '_sbid_idx')
  FROM pg_inherits i
  JOIN pg_class c ON c.oid = i.inhrelid
 WHERE i.inhparent = 'entries'::regclass
   AND NOT EXISTS (
        SELECT 1
          FROM pg_inherits pi
          JOIN pg_class ic ON ic.oid = pi.inhrelid
         WHERE pi.inhparent = 'idx_entries_settlement_batch'::regclass
           AND ic.relname = c.relname || '_sbid_idx')
 ORDER BY c.relname
\gexec

-- Report whether the parent index is now valid (all partitions attached).
DO $$
DECLARE ok boolean;
BEGIN
    SELECT indisvalid INTO ok
      FROM pg_index WHERE indexrelid = 'idx_entries_settlement_batch'::regclass;
    IF ok THEN
        RAISE NOTICE 'idx_entries_settlement_batch is VALID (all partitions attached)';
    ELSE
        RAISE WARNING 'idx_entries_settlement_batch still INVALID -- some partition index is missing/unattached; re-run this file';
    END IF;
END $$;
