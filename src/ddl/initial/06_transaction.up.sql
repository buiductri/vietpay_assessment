-- ============================================================================
-- VietPay core ledger | initial 06 (up): transactions (journal header)
-- Source of truth: docs/ERD.md  ("transaction" entity)
-- One-time baseline. Idempotent. Reverse: 06_transaction.down.sql
-- Target: PostgreSQL 14+   Depends on: 03 exchange_rates
-- ============================================================================
-- The journal header that groups the entries which must balance.  Carries the
-- business classification (`type`), lifecycle (`status`), and the link to the
-- rate used when a movement crosses currencies (`exchange_rate_id`).
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- `type` is an open, spec-dependent vocabulary (ERD: "transfer, exchange,
    -- fee, ...").  Left as free TEXT deliberately rather than inventing a closed
    -- CHECK list; pin it with a CHECK once the business set is finalised.
    type              TEXT        NOT NULL,
    -- `status` IS a closed, approved set: PENDING, SETTLED, REVERSED (journal T4).
    -- An earlier draft sketched a fuller PROCESSING/FAILED machine; those states
    -- were dropped when entry lifecycle was consolidated onto transaction.status.
    status            TEXT        NOT NULL DEFAULT 'PENDING'
        CONSTRAINT transactions_status_ck CHECK (status IN ('PENDING', 'SETTLED', 'REVERSED')),
    -- the exact point-in-time rate record used; immutable, so the rate is pinned
    -- and a retry is deterministic.  Set only for exchange transactions.
    exchange_rate_id  UUID,
    description       TEXT,
    extra_info        JSONB,                              -- multi-currency legs, system fee, exchange value, ...
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(), -- commit time
    CONSTRAINT transactions_exchange_rate_fk
        FOREIGN KEY (exchange_rate_id) REFERENCES exchange_rates (exchange_rate_id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_transactions_created ON transactions (created_at);
CREATE INDEX IF NOT EXISTS idx_transactions_exchange_rate
    ON transactions (exchange_rate_id) WHERE exchange_rate_id IS NOT NULL;

-- Settlement-report support (Task 2, query & performance).  The report joins the
-- partitioned `entries` back to this header to filter `status = 'SETTLED'`.  This
-- COVERING PARTIAL index lets that side run as an INDEX-ONLY scan: it indexes
-- only SETTLED rows (the ~85% that the report wants), keyed by `created_at` for
-- the month range, and carries `transaction_id` as the join key as an INCLUDE
-- payload -- so the planner gets both columns from the index with zero heap
-- fetches.  Empirically (journal section 3) this removes the header's heap-fetch cost
-- entirely.  Partial, so PENDING/REVERSED rows never enter it (smaller, and not
-- touched on insert until a row settles).
CREATE INDEX IF NOT EXISTS idx_transactions_settled_created
    ON transactions (created_at) INCLUDE (transaction_id)
    WHERE status = 'SETTLED';

COMMENT ON TABLE  transactions        IS 'Journal header grouping the entries that must balance per currency.';
COMMENT ON COLUMN transactions.status IS 'PENDING, SETTLED, REVERSED (REVERSED is reached by posting a reversing transaction, never by mutation).';
