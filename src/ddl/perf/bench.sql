-- ============================================================================
-- VietPay | Task 2 (query & performance): reproducible benchmark
-- Source of truth: ../../../00-journal.md section 3 ; docs/query-performance.md
-- ============================================================================
-- Builds a THROWAWAY `bench` schema with two variants of the entries table --
-- (A) flat/unpartitioned and (C) monthly RANGE-partitioned -- holding identical
-- rows, then runs EXPLAIN (ANALYZE, BUFFERS) for the settlement report on each
-- so the plan change is observed, not asserted.  Read-path only (no triggers /
-- FKs): we are measuring the SELECT plan, not the write constraints.
--
-- Run:   psql "$DATABASE_URL" -f bench.sql
-- Clean: DROP SCHEMA bench CASCADE;   (left in place at the end for inspection)
--
-- Seeds ~2M transactions -> ~4M entries (a few M, not the full 50M, to keep
-- seeding fast; the plan SHAPES and pruning behaviour are identical and scale).
-- ============================================================================
\set ON_ERROR_STOP on
\timing on
\pset pager off
\set n_txn 2000000
\set ms '2025-06-01 00:00:00+00'
\set me '2025-07-01 00:00:00+00'

DROP SCHEMA IF EXISTS bench CASCADE;
CREATE SCHEMA bench;

-- ---- header -----------------------------------------------------------------
CREATE TABLE bench.transactions (
    transaction_id uuid PRIMARY KEY,
    status         text        NOT NULL,
    created_at     timestamptz NOT NULL
);
INSERT INTO bench.transactions (transaction_id, status, created_at)
SELECT md5('txn:'||i)::uuid,
       CASE WHEN (i*2654435761)::bigint % 100 < 85 THEN 'SETTLED'
            WHEN (i*2654435761)::bigint % 100 < 95 THEN 'PENDING' ELSE 'REVERSED' END,
       timestamptz '2024-07-01 00:00:00+00'
         + ((i % 24)         || ' months')::interval
         + ((i * 37 % 28)    || ' days')::interval
         + ((i * 131 % 86400)|| ' seconds')::interval
FROM generate_series(1, :n_txn) g(i);

-- ---- entries: (A) flat baseline ---------------------------------------------
CREATE TABLE bench.entries_flat (
    entry_id uuid NOT NULL, transaction_id uuid NOT NULL, wallet_id uuid NOT NULL,
    type text NOT NULL, amount numeric(19,4) NOT NULL, currency char(3) NOT NULL,
    created_at timestamptz NOT NULL, PRIMARY KEY (entry_id)
);
INSERT INTO bench.entries_flat
SELECT md5('e:'||t.transaction_id::text||':'||leg.k)::uuid, t.transaction_id,
       md5('w:'|| (abs(hashtext(t.transaction_id::text||leg.salt)) % 200000)::text)::uuid,
       leg.typ, ((abs(hashtext(t.transaction_id::text)) % 1000000)/100.0 + 1)::numeric(19,4),
       (ARRAY['USD','VND','EUR'])[1 + abs(hashtext(t.transaction_id::text)) % 3], t.created_at
FROM bench.transactions t
CROSS JOIN LATERAL (VALUES (1,'DEBIT','d'),(2,'CREDIT','c')) leg(k,typ,salt);

-- ---- entries: (C) monthly RANGE-partitioned ---------------------------------
CREATE TABLE bench.entries_part (
    entry_id uuid NOT NULL, transaction_id uuid NOT NULL, wallet_id uuid NOT NULL,
    type text NOT NULL, amount numeric(19,4) NOT NULL, currency char(3) NOT NULL,
    created_at timestamptz NOT NULL, PRIMARY KEY (entry_id, created_at)
) PARTITION BY RANGE (created_at);
DO $$
DECLARE m date := date '2024-07-01';
BEGIN
    WHILE m < date '2026-10-01' LOOP
        EXECUTE format('CREATE TABLE bench.entries_p_%s PARTITION OF bench.entries_part FOR VALUES FROM (%L) TO (%L);',
                       to_char(m,'YYYYMM'), m, (m + interval '1 month')::date);
        m := (m + interval '1 month')::date;
    END LOOP;
    EXECUTE 'CREATE TABLE bench.entries_p_default PARTITION OF bench.entries_part DEFAULT;';
END $$;
INSERT INTO bench.entries_part SELECT * FROM bench.entries_flat;

-- ---- indexes ----------------------------------------------------------------
-- baseline (mirror initial/06 + 07 as shipped before tuning)
CREATE INDEX ix_txn_created    ON bench.transactions (created_at);
CREATE INDEX ix_flat_txn       ON bench.entries_flat (transaction_id);
CREATE INDEX ix_flat_wallet    ON bench.entries_flat (wallet_id, created_at DESC);
CREATE INDEX ix_part_txn       ON bench.entries_part (transaction_id);
CREATE INDEX ix_part_wallet    ON bench.entries_part (wallet_id, created_at DESC);
-- tuned: the covering partial header index (initial/06's new index)
CREATE INDEX ix_txn_settled_cov ON bench.transactions (created_at)
    INCLUDE (transaction_id) WHERE status = 'SETTLED';

ANALYZE bench.transactions; ANALYZE bench.entries_flat; ANALYZE bench.entries_part;
VACUUM (ANALYZE) bench.transactions;   -- set the visibility map for index-only scans

\echo '################ BEFORE: flat baseline (range on entries.created_at only) ################'
EXPLAIN (ANALYZE, BUFFERS, TIMING ON)
SELECT e.wallet_id, e.currency, SUM(e.amount)
FROM bench.entries_flat e JOIN bench.transactions t ON t.transaction_id = e.transaction_id
WHERE t.status = 'SETTLED' AND e.created_at >= :'ms' AND e.created_at < :'me'
GROUP BY e.wallet_id, e.currency;

\echo '################ AFTER: partitioned + covering partial header index (both-sided predicate) ################'
EXPLAIN (ANALYZE, BUFFERS, TIMING ON)
SELECT e.wallet_id, e.currency, SUM(e.amount)
FROM bench.entries_part e JOIN bench.transactions t ON t.transaction_id = e.transaction_id
WHERE t.status = 'SETTLED'
  AND e.created_at >= :'ms' AND e.created_at < :'me'
  AND t.created_at >= :'ms' AND t.created_at < :'me'
GROUP BY e.wallet_id, e.currency;

\echo '################ index / table sizes ################'
SELECT indexrelid::regclass AS index, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
WHERE c.relnamespace = 'bench'::regnamespace AND c.relname IN ('transactions','entries_flat')
ORDER BY pg_relation_size(indexrelid) DESC;
\echo '(leaving schema `bench` in place; DROP SCHEMA bench CASCADE; to remove)'
