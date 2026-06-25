-- ============================================================================
-- VietPay | Task 2 (query & performance): the optimised settlement report
-- Source of truth: ../../../00-journal.md section 3 ; docs/query-performance.md
-- Target: PostgreSQL 14+ . Supporting objects live in the baseline:
--   - entries range-partitioned monthly on created_at  (initial/07)
--   - idx_transactions_settled_created  covering partial index  (initial/06)
-- ============================================================================
-- The assessment's report was written for ONE flat table:
--
--   SELECT wallet_id, currency, SUM(amount) FROM transactions
--   WHERE status='SETTLED' AND created_at >= :m_start AND created_at < :m_end
--   GROUP BY wallet_id, currency;
--
-- This design normalised that table into a ledger: the money columns
-- (wallet_id, amount, currency, created_at) live on the immutable, partitioned
-- `entries`; the mutable `status` lives on the `transactions` header.  So the
-- report becomes a JOIN.  `entries.created_at` is the entry's POSTING time (the
-- faithful meaning of the original single timestamp); `status='SETTLED'` is a
-- current-state filter on the header.  (The business question "settled DURING
-- month M" -- if settlement lags across a month boundary -- is out of scope here;
-- there is no settled_at column.  See journal section 3.)
-- ----------------------------------------------------------------------------

-- :m_start / :m_end are the month bounds, e.g.
--   \set m_start '2026-03-01 00:00:00+00'
--   \set m_end   '2026-04-01 00:00:00+00'

-- ---- OPTIMISED FORM (use this) ----------------------------------------------
-- The created_at range is pushed onto BOTH sides.  This relies on POSTING-TIME
-- EQUALITY: now()/transaction_timestamp() is constant within a transaction, so a
-- header and its entries written in one posting with default created_at get the
-- SAME value (not just the same month).  It is an ASSUMPTION, not a schema
-- constraint -- it would break if an app set created_at on one table but not the
-- other, or backfilled.  The redundant predicate lets each side restrict alone:
--   * entries  -> PARTITION PRUNING to the one month partition;
--   * transactions -> INDEX-ONLY scan of idx_transactions_settled_created
--                     (settled rows only, created_at key, transaction_id payload).
SELECT e.wallet_id, e.currency, SUM(e.amount) AS settled_total
FROM entries e
JOIN transactions t ON t.transaction_id = e.transaction_id
WHERE t.status = 'SETTLED'
  AND e.created_at >= :'m_start' AND e.created_at < :'m_end'
  AND t.created_at >= :'m_start' AND t.created_at < :'m_end'   -- redundant (posting-time equality); enables header index seek
GROUP BY e.wallet_id, e.currency;

-- Notes:
--  * SUM(e.amount) is the literal translation of the original query: a GROSS
--    total of the settled entries' magnitudes per wallet/currency.  A NET
--    movement would be SUM(CASE WHEN e.type='CREDIT' THEN e.amount ELSE -e.amount END)
--    (that is the balance_audit view's expression); the partition/index strategy
--    is identical either way.
--  * The report is a heavy GROUP BY over ~100k+ groups.  Give the reporting role
--    a larger work_mem so the aggregate stays in memory instead of spilling:
--        SET work_mem = '128MB';   -- per session/role for the reporting path
--  * For FROZEN historical months, prefer the pre-aggregated rollup
--    (summary_rollup.sql) -- a single PK range scan instead of this live join.
