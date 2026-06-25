-- ============================================================================
-- VietPay core ledger | initial 07 (up): entries (double-entry lines)
-- Source of truth: docs/ERD.md  ("entry" entity; currency-consistency rule)
-- One-time baseline. Idempotent. Reverse: 07_entry.down.sql
-- Target: PostgreSQL 14+   Depends on: 05 wallets, 06 transactions
-- ============================================================================
-- The double-entry line: one DEBIT or one CREDIT against one wallet.  An
-- immutable, append-only fact (immutability enforced in step 11).  `amount` is
-- a POSITIVE magnitude; direction lives in `type`.  This (positive amount +
-- direction-in-type) is a recorded STANDARDS choice, not a correctness fix:
-- a signed amount with a CHECK is equally correct.  See journal T3.
--
-- PARTITIONING (Task 2, query & performance): `entries` is the hot, fast-growing
-- table (~2M new rows/month) the settlement report scans.  It is range
-- partitioned MONTHLY on `created_at`, so a one-month report touches only that
-- month's partition (partition pruning) instead of the whole 50M-row heap.
-- PostgreSQL requires the partition key in every unique constraint, so the PK is
-- the composite `(entry_id, created_at)`.  Safe here: `entry_id` is a UUID and
-- nothing FKs into `entries` (it is a leaf), so it never needs to be unique on
-- its own.  This was journal section 2.2's deferred "logical model"; journal section 3 folds
-- it into the baseline (the empty greenfield case), and notes that converting an
-- existing populated table is a separate online migration (Task-3-style).
--
-- CURRENCY CONSISTENCY: the composite FK `(wallet_id, currency)` -> wallets
-- guarantees an entry's currency equals its wallet's.  Both columns are
-- NOT NULL because under the default MATCH SIMPLE a NULL in either would skip
-- the check entirely.
-- ----------------------------------------------------------------------------

-- Partition factory: create one monthly partition, idempotently.  Used below
-- for the baseline window and by ops/automation (pg_partman or a scheduled job)
-- to roll new months forward.  It also (re)attaches the append-only TRUNCATE
-- guard, because statement-level triggers on the partitioned parent are NOT
-- cloned to partitions (see step 11); the guard is skipped until deny_mutation()
-- exists (step 11), which is why the baseline window is hardened there instead.
CREATE OR REPLACE FUNCTION create_entries_partition(p_month date)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    start_date date := date_trunc('month', p_month)::date;
    end_date   date := (date_trunc('month', p_month) + interval '1 month')::date;
    part_name  text := format('entries_p%s', to_char(start_date, 'YYYYMM'));
BEGIN
    IF to_regclass('public.' || part_name) IS NULL THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF entries FOR VALUES FROM (%L) TO (%L)',
            part_name, start_date, end_date);
    END IF;
    IF to_regprocedure('deny_mutation()') IS NOT NULL THEN
        EXECUTE format('DROP TRIGGER IF EXISTS trg_entries_no_truncate ON %I', part_name);
        EXECUTE format(
            'CREATE TRIGGER trg_entries_no_truncate BEFORE TRUNCATE ON %I '
            'FOR EACH STATEMENT EXECUTE FUNCTION deny_mutation()', part_name);
    END IF;
END;
$$;

COMMENT ON FUNCTION create_entries_partition(date) IS
    'Idempotently create the monthly entries partition covering p_month (+ re-attach the TRUNCATE guard once it exists).';

CREATE TABLE IF NOT EXISTS entries (
    entry_id        UUID          NOT NULL DEFAULT gen_random_uuid(),
    transaction_id  UUID          NOT NULL,
    wallet_id       UUID          NOT NULL,
    type            TEXT          NOT NULL
        CONSTRAINT entries_type_ck   CHECK (type IN ('DEBIT', 'CREDIT')),
    amount          NUMERIC(19,4) NOT NULL
        CONSTRAINT entries_amount_ck CHECK (amount > 0),   -- positive magnitude; direction is in `type`
    currency        CHAR(3)       NOT NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    -- composite PK: the partition key (created_at) must be part of every unique
    -- constraint on a partitioned table.
    CONSTRAINT entries_pkey PRIMARY KEY (entry_id, created_at),
    CONSTRAINT entries_transaction_fk
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id) ON DELETE RESTRICT,
    CONSTRAINT entries_wallet_currency_fk
        FOREIGN KEY (wallet_id, currency) REFERENCES wallets (wallet_id, currency) ON DELETE RESTRICT
) PARTITION BY RANGE (created_at);

-- Baseline monthly partitions.  A deterministic window (fixed anchors, so the
-- file's checksum is stable) wide enough to cover ~24 months of history, the
-- current month, and near-future inserts.  Production automates rolling
-- creation of new months ahead of time (call create_entries_partition(), or
-- pg_partman); this baseline just bootstraps the window.
DO $$
DECLARE m date := date '2024-01-01';
BEGIN
    WHILE m < date '2027-01-01' LOOP
        PERFORM create_entries_partition(m);
        m := (m + interval '1 month')::date;
    END LOOP;
END $$;

-- DEFAULT partition: a safety net so an insert outside the provisioned window is
-- never rejected (it just loses pruning until a real month partition is added).
DO $$
BEGIN
    IF to_regclass('public.entries_pdefault') IS NULL THEN
        CREATE TABLE entries_pdefault PARTITION OF entries DEFAULT;
    END IF;
END $$;

-- Local indexes (partitioned indexes: cloned to every partition, current and
-- future).  These serve OTHER workloads, not the settlement report -- that
-- query needs no entries index, partition pruning + a one-month seq scan is
-- optimal (journal section 3).  `transaction_id` supports the FK/join back to the
-- header; `(wallet_id, created_at DESC)` supports per-wallet statement/dashboard
-- reads.
CREATE INDEX IF NOT EXISTS idx_entries_transaction ON entries (transaction_id);
CREATE INDEX IF NOT EXISTS idx_entries_wallet      ON entries (wallet_id, created_at DESC);

COMMENT ON TABLE  entries        IS 'Immutable double-entry lines; one DEBIT or CREDIT against one wallet. Range-partitioned monthly on created_at (Task 2).';
COMMENT ON COLUMN entries.amount IS 'NUMERIC(19,4), always > 0; direction is carried in `type` (standards choice, journal T3).';
COMMENT ON CONSTRAINT entries_wallet_currency_fk ON entries IS 'Currency consistency: entry.currency must equal its wallet.currency.';
