-- ============================================================================
-- VietPay ledger | migration 001 settlement_batch_id | EXPAND (up)
-- Source of truth: docs/ERD.md ("entry" entity), CONTEXT.md ("Settlement Batch")
-- Idempotent. Reverse: 01_expand.down.sql
-- Target: PostgreSQL 14+ (validated on 17.2).  Table: entries (PARTITIONED)
-- ----------------------------------------------------------------------------
-- WHY THIS TABLE: the assessment's original 50M-row `transactions(id, wallet_id,
-- type, amount, currency, status, created_at)` is what Task 1 split into a
-- `transaction` header plus `entry` lines; the 50M rows live in `entries`
-- (journal sec.3: "the query on 'transactions' ... is now entries").  So the
-- live large table named in Task 3 is `entries`.
--
-- `entries` is RANGE-partitioned monthly on created_at (initial/07, Task 2), so
-- every operation here is on the partitioned parent and cascades to all
-- partitions.  ADD COLUMN on the parent is metadata only and propagates to every
-- partition (validated: 37 partitions picked up the column).
--
-- ADD a NULLABLE column with no default: the tolerant ("expand") shape that BOTH
-- the current app (ignores the column) and the next dual-writing app accept.  The
-- NOT NULL promotion is deferred to step 05, after every row has a value, so we
-- never scan/rewrite 50M rows under an exclusive lock.
--
-- NO FOREIGN KEY here, on purpose: a partitioned table REJECTS a `NOT VALID`
-- foreign key ("cannot add NOT VALID foreign key on partitioned table"), so the
-- online "add NOT VALID then VALIDATE" path is not available.  Referential
-- integrity to settlement_batches is handled out of band (see README, "Foreign
-- key on a partitioned table"); large partitioned fact tables also commonly omit
-- the DB-level FK for exactly these operational reasons.
--
-- LOCK PROFILE: ADD COLUMN takes a brief ACCESS EXCLUSIVE lock on the parent (and
-- briefly on each partition).  Instant once granted, but under load the grant can
-- queue behind a long statement and then block everything behind it, so it is
-- taken under a short lock_timeout with a bounded retry.  The immutability
-- trigger is BEFORE UPDATE/DELETE; it does NOT fire on DDL, so ADD COLUMN needs
-- no special handling.  SAFE to run with --single-transaction.
-- ============================================================================

-- Parent table the new column points at (no DB-level FK; see header).  A
-- settlement batch groups the entries cleared together in one settlement cycle.
CREATE TABLE IF NOT EXISTS settlement_batches (
    settlement_batch_id UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    status              TEXT        NOT NULL DEFAULT 'OPEN'
        CONSTRAINT settlement_batches_status_ck CHECK (status IN ('OPEN', 'CLOSED', 'SETTLED')),
    description         TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sentinel batch: historical (pre-migration) entries were never assigned to a
-- real batch, so they are backfilled to point here.  The honest placeholder that
-- lets the column reach NOT NULL without inventing per-row business data (the
-- column's business meaning is out of scope, journal).  Fixed UUID so the
-- backfill value and any re-run are deterministic.
INSERT INTO settlement_batches (settlement_batch_id, status, description)
VALUES ('00000000-0000-0000-0000-000000000000', 'SETTLED',
        'Pre-migration legacy backfill sentinel (Task 3 expand-contract).')
ON CONFLICT (settlement_batch_id) DO NOTHING;

-- ADD COLUMN, NULLABLE, no default.  Bounded lock_timeout + retry so a brief
-- ACCESS EXCLUSIVE lock cannot pile up behind a long-running statement.
DO $$
DECLARE attempts int := 0;
BEGIN
    LOOP
        BEGIN
            SET LOCAL lock_timeout = '3s';
            ALTER TABLE entries ADD COLUMN IF NOT EXISTS settlement_batch_id UUID;
            EXIT;
        EXCEPTION WHEN lock_not_available THEN
            attempts := attempts + 1;
            IF attempts >= 5 THEN RAISE; END IF;
            RAISE NOTICE 'ADD COLUMN: lock busy, retry % of 5 after 2s', attempts;
            PERFORM pg_sleep(2);
        END;
    END LOOP;
END $$;

COMMENT ON COLUMN entries.settlement_batch_id IS
    'Settlement batch this entry cleared in. Added NULLABLE by the Task 3 expand-contract migration; promoted to NOT NULL in step 05.';
