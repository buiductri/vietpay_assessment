# Task 2: Query & performance (SQL artifacts)

The settlement report optimised for the 50M-row workload. The reasoning is in
[`00-journal.md` section 3](../../../00-journal.md); the AI-authored query-plan
walk-through, with the real `EXPLAIN` output, is
[`docs/query-performance.md`](../../../docs/query-performance.md).

| File | What |
|---|---|
| `settlement_query.sql` | The optimised report (primary deliverable). The join over the partitioned `entries` and the header, with the redundant `created_at` predicate that lets both sides restrict. |
| `summary_rollup.sql` | The complementary layer: a per-`(month, wallet, currency)` rollup + `refresh_wallet_monthly_settlement()` for **frozen** historical months (a PK range scan instead of the live join). Optional, not in the baseline deploy chain. |
| `bench.sql` | Reproducible benchmark: seeds ~4M entries, builds a flat vs monthly-partitioned variant, runs `EXPLAIN (ANALYZE, BUFFERS)` before/after, prints index sizes. |

## The supporting schema (lives in the baseline, `initial/`)

The two structural changes the report needs are part of the Task 1 baseline, not
a separate phase (journal section 3 folds them in):

- **`entries` is range-partitioned monthly on `created_at`**, in `initial/07_entry.up.sql`.
  A one-month report prunes to a single partition.
- **`idx_transactions_settled_created`**, a covering partial index
  `transactions (created_at) INCLUDE (transaction_id) WHERE status='SETTLED'`,
  `initial/06_transaction.up.sql`. Turns the header side into an index-only scan.

## Headline result (4M-row bench, PG 17.2)

| | shared-buffer reads | exec |
|---|--:|--:|
| flat baseline | ~68,300 | ~1,180 ms |
| partitioned + covering index | ~2,570 | ~477 ms |
| frozen month via rollup | ~1,170 | ~40 ms |

~26x fewer shared-buffer reads from the structural change (partition pruning +
index-only header), measured at a matched reporting `work_mem` so neither
aggregate spills. At the server's default 4 MB `work_mem` the tuned plan's
`GROUP BY` spills (~540 ms, ~6,400 temp blocks), so counting all I/O the win is
~7.6x; the data-access reduction is the same either way. The rollup makes a frozen
month near-free. Reproduce with `psql "$DATABASE_URL" -f bench.sql`.

> Converting an *already-populated* `entries` table to partitioned online (rather
> than the greenfield `CREATE` here) is a separate migration, deliberately
> deferred, see journal section 3.
