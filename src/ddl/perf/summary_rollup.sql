-- ============================================================================
-- VietPay | Task 2 (query & performance): settlement rollup (complementary)
-- Source of truth: ../../../00-journal.md section 3
-- Target: PostgreSQL 14+ . Idempotent. Optional add-on, NOT in the initial/
-- baseline deploy chain -- apply it where the reporting workload runs.
-- ============================================================================
-- The SECOND layer of the strategy.  The live partitioned join
-- (settlement_query.sql) always serves the current/hot month accurately.  But a
-- FROZEN historical month never changes, so re-running the join for every report
-- of (say) 2024-09 is wasted work.  This table pre-aggregates the report once
-- per (posting) month; thereafter a cold-month report is a single PK range scan.
--
-- Like wallets.balance, this is a DERIVED cache, never the source of truth: the
-- entries remain authoritative, and refresh_wallet_monthly_settlement() can
-- recompute any month to reconcile.  Keyed on posting month (e.created_at),
-- matching the live query.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS wallet_monthly_settlement (
    month         date          NOT NULL,        -- first day of the posting month
    wallet_id     uuid          NOT NULL,
    currency      char(3)       NOT NULL,
    settled_total numeric(19,4) NOT NULL,         -- SUM(amount) of that month's settled entries
    entry_count   bigint        NOT NULL,
    refreshed_at  timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT wallet_monthly_settlement_pkey PRIMARY KEY (month, wallet_id, currency)
);

COMMENT ON TABLE wallet_monthly_settlement IS
    'Derived per-(month,wallet,currency) settlement rollup for frozen months; cache, not source of truth. Refresh via refresh_wallet_monthly_settlement().';

-- Recompute one month from the authoritative ledger (delete-then-insert, so it
-- is idempotent and also repairs a month if a late REVERSED changed it).
CREATE OR REPLACE FUNCTION refresh_wallet_monthly_settlement(p_month date)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    start_date date := date_trunc('month', p_month)::date;
    end_date   date := (date_trunc('month', p_month) + interval '1 month')::date;
    n bigint;
BEGIN
    DELETE FROM wallet_monthly_settlement WHERE month = start_date;
    INSERT INTO wallet_monthly_settlement (month, wallet_id, currency, settled_total, entry_count)
    SELECT start_date, e.wallet_id, e.currency, SUM(e.amount), count(*)
    FROM entries e
    JOIN transactions t ON t.transaction_id = e.transaction_id
    WHERE t.status = 'SETTLED'
      AND e.created_at >= start_date AND e.created_at < end_date
    GROUP BY e.wallet_id, e.currency;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END;
$$;

COMMENT ON FUNCTION refresh_wallet_monthly_settlement(date) IS
    'Recompute the settlement rollup for the month containing p_month from the ledger (idempotent).';

-- ---- usage ------------------------------------------------------------------
-- Schedule, just after a month closes (and once more after the late-settlement
-- window), e.g. from cron/pg_cron:
--     SELECT refresh_wallet_monthly_settlement(date '2026-02-01');
--
-- Cold-month report (trivial PK range scan; no join, no aggregate, no spill):
--     SELECT wallet_id, currency, settled_total
--     FROM wallet_monthly_settlement WHERE month = date '2026-02-01';
--
-- Routing rule for the application: month < current month -> read the rollup;
-- current month -> run settlement_query.sql live.  (A MATERIALIZED VIEW is the
-- alternative, but it refreshes wholesale; a per-month table lets each frozen
-- month be computed exactly once and reconciled independently.)
