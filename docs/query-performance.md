# Task 2: Query & performance: settlement report

> **Authorship.** This document is **AI-authored** (the candidate, Bùi Đức Trí,
> directed the strategy and the decisions in [`00-journal.md` section 3](../00-journal.md);
> the query-plan walk-through here was generated for study and to satisfy the
> rubric's *"ability to read a query plan."*). All numbers are real `EXPLAIN
> (ANALYZE, BUFFERS)` output from PostgreSQL 17.2 against the
> [`src/ddl/perf/bench.sql`](../src/ddl/perf/bench.sql) harness (~2M transactions
> / 4M entries). Reproduce with `psql "$DATABASE_URL" -f src/ddl/perf/bench.sql`.

## 1. The query, after normalisation

The assessment's report assumed one flat table:

```sql
SELECT wallet_id, currency, SUM(amount) FROM transactions
WHERE status = 'SETTLED' AND created_at >= :m_start AND created_at < :m_end
GROUP BY wallet_id, currency;
```

This design split that table into a ledger (Task 1): the money columns
(`wallet_id`, `amount`, `currency`, `created_at`) moved to the immutable
`entries`; the mutable `status` stayed on the `transactions` header. The report
is therefore a **join**:

```sql
SELECT e.wallet_id, e.currency, SUM(e.amount) AS settled_total
FROM entries e
JOIN transactions t ON t.transaction_id = e.transaction_id
WHERE t.status = 'SETTLED'
  AND e.created_at >= :m_start AND e.created_at < :m_end
  AND t.created_at >= :m_start AND t.created_at < :m_end   -- redundant; see section 2
GROUP BY e.wallet_id, e.currency;
```

`entries.created_at` is the entry's **posting** time (the faithful meaning of the
original single timestamp). `status='SETTLED'` is a current-state filter on the
header. `SUM(e.amount)` is the literal gross translation; a net movement would be
`SUM(CASE WHEN type='CREDIT' THEN amount ELSE -amount END)`, the same plan either way.

> The candidate's earlier index sketch (journal section 1.2) was written for the *flat*
> table, where `status`, `wallet_id`, `amount`, and `created_at` shared one row.
> After the split those options no longer apply unchanged; the strategy below is
> rebuilt for the join.

## 2. The strategy: three moves

1. **Partition `entries` monthly by `created_at` (RANGE).** A one-month report
   prunes to a single partition instead of scanning the whole 50M-row heap. This
   is the dominant win, and it is what the immutable, append-only, time-ordered
   `entries` table is naturally suited to.
2. **A covering partial index on the header:**
   `transactions (created_at) INCLUDE (transaction_id) WHERE status='SETTLED'`.
   The join needs only `transaction_id` (to match) and the `SETTLED`+month
   restriction from the header. This index supplies both from the index alone,
   an **index-only scan**, no heap fetch, and indexes only the ~85 % SETTLED rows.
3. **Push the `created_at` range onto the header too** (the redundant predicate).
   This relies on **posting-time equality**: `now()` / `transaction_timestamp()`
   is constant within a transaction, so a header and its entries inserted in one
   posting with default `created_at` get the *same* value, not merely the same
   month. The predicate lets the header side *seek the month* via the index
   instead of scanning all 2M rows; without it the planner cannot derive the
   header range from the join. This equality is an **assumption, not a schema
   constraint**: it holds for normal posting, but would break if an application
   set `created_at` on one table and not the other, or backfilled history with a
   different timestamp. The benchmark confirms the rewrite is result-preserving:
   the flat form and the partitioned form return the identical 124,739 groups.

`entries` needs **no** new index for this query: a pruned one-month partition is
small, and a sequential scan of it feeding the hash join is optimal. The existing
local indexes (`transaction_id`, `wallet_id`) serve other workloads.

## 3. Reading the plans: before vs after

### BEFORE: flat table, range on `entries.created_at` only

```
Finalize GroupAggregate                          Execution Time: 1183 ms
  Buffers: shared hit=11837 read=56439                       (~68,300 buffers ~533 MB)
  -> Parallel Hash Join  (Hash Cond: t.transaction_id = e.transaction_id)
       -> Parallel Seq Scan on transactions t   Buffers: hit=11599 read=3216
            Filter: status = 'SETTLED'           Rows Removed by Filter: 100000   (scans ALL 2M)
       -> Parallel Seq Scan on entries_flat e   Buffers: read=53223
            Filter: created_at >= ... AND < ...      Rows Removed by Filter: 1,277,778 (x3 ~3.8M)
```

Two full scans: the entries heap (4M rows, 3.8M thrown away by the date filter
for lack of pruning) and the transactions heap (all 2M, to find `SETTLED`).

### AFTER: partitioned `entries` + covering partial header index, both-sided predicate

Shown with the reporting `work_mem` raised so the aggregate stays in memory, the
same regime as the BEFORE run (whose sort also fit in memory). This keeps the
buffer comparison like-for-like; the default-`work_mem` spill is the "remaining
cost" below.

```
Finalize HashAggregate                           Execution Time: 477 ms
  Buffers: shared hit=2467 read=105   (~2,572 buffers ~20 MB, no temp)
  -> Parallel Hash Join  (Hash Cond: e.transaction_id = t.transaction_id)
       -> Parallel Seq Scan on entries_p202506 e          Buffers: hit=2222   (ONE partition)
            Filter: created_at >= ... AND < ...
       -> Parallel Index Only Scan using ix_txn_settled_cov on transactions t
            Index Cond: created_at >= ... AND < ...  Heap Fetches: 0    Buffers: hit=245 read=105
```

What changed, and why it matters:

| | before | after |
|---|---|---|
| entries access | seq scan of all 4M rows (`read=53,223`) | one partition (`hit=2,222`), **partition pruning** |
| header access | seq scan of all 2M rows (`read=3,216`+`hit=11,599`) | index-only scan, **`Heap Fetches: 0`** (`~350`) |
| shared-buffer reads (both no-spill) | **~68,300** | **~2,570** (~26x fewer) |
| execution | ~1,183 ms | ~477 ms |

On the live (empty) schema the plan shape is confirmed too: only
`entries_p202603` appears (the other 36 partitions are pruned away) and the
header is read via `Index Only Scan using idx_transactions_settled_created`.

### The remaining cost: aggregate spill, not the scan

Once the scans are tiny, the leftover cost is the `GROUP BY` over ~125k groups.
At the server's default 4 MB `work_mem` the tuned plan's `HashAggregate` **spills
to disk** (`Batches: 21 ... Disk Usage: 11904kB`, ~6,400 temp blocks, execution
~540 ms). That is why the AFTER run above is shown with `work_mem` raised:

```
SET work_mem = '128MB';
  -> Finalize HashAggregate  Batches: 1  Memory Usage: 63505kB   (no temp, ~477 ms)
```

Two honest points. First, this is a session/role knob for the reporting path, not
a schema change, and it is orthogonal to the ~26x **scan** reduction (the spill is
in the aggregate, after the join). Second, the comparison is fair only at a
matched `work_mem`: the BEFORE plan's sort-based aggregate already fit in 4 MB
(`quicksort Memory: 3932kB`, no temp), so at the default the tuned plan spills
where the baseline did not. Counting *all* block I/O at the default 4 MB the win
is ~7.6x (~68,300 -> ~9,000); at a reporting `work_mem` where neither spills it is
the ~26x shared-buffer figure above. Either way the data-access reduction
(pruning + index-only header) is real; `work_mem` only decides whether the
aggregate stays in memory.

## 4. Validating the improvement: what the plan *should* show

The improvement is real iff the plan flips on these specific markers (all
verified above):

1. **Partition pruning**: a single `entries_pYYYYMM` node, not an `Append` /
   `Seq Scan` over the whole table. `Rows Removed by Filter` on the entries scan
   should drop to ~0.
2. **Index-only header access**: `Index Only Scan using ix_txn_settled_cov`
   with **`Heap Fetches: 0`** (needs the visibility map set, i.e. a vacuumed/
   steady-state table), not a seq scan or a bitmap heap scan.
3. **Shared-buffer reads**: the honest, hardware-independent metric. With the
   aggregate kept in memory on both sides (matched `work_mem`), shared-buffer
   reads drop ~26x (wall-clock compresses less on a fast, cache-warm box). At 50M
   rows the untuned plan's reads grow with the whole table; the tuned plan's grow
   only with one month + one index range.

## 5. Cost of the indexes

Index sizes from the 4M-row bench (`pg_relation_size`):

| index | size | note |
|---|--:|---|
| `ix_txn_settled_cov` (the new covering partial) | 66 MB | only the 85 % SETTLED rows; carries `transaction_id` as payload |
| `ix_txn_created` (general `created_at`) | 28 MB | kept for non-settlement date queries |
| `entries` local indexes (`txn`, `wallet`) | 95 / 155 MB | pre-existing; serve joins / dashboards, **not** this report |

**Write overhead.** Every `entries` insert maintains its local indexes
(unchanged by partitioning: an insert touches only the target partition's
indexes, which are *smaller* per-partition B-trees, so index maintenance does not
degrade as history grows). The new header index is **partial**, so a `PENDING`
or `REVERSED` row never enters it; a row joins the index only when it becomes
`SETTLED` (the `PENDING -> SETTLED` update), keeping it ~15 % smaller than a full
index and concentrating its churn at settlement time. Measured: a 1M-row bulk
insert into the header took ~5.6 s with no index versus ~9.1 s with this covering
partial index present (~3.5 us/row of extra maintenance; the index covered 850k
of the 1M rows, the 85 % SETTLED). That is its standalone cost against a no-index
table; as a *marginal* cost on a header that already maintains a PK and a
`created_at` index it is proportionally smaller, and real posting inserts one row
per transaction, not in bulk.

**Partitioning's operational dividend.** Beyond pruning: a flat 50M-row table is
one ~800 MB heap + monolithic indexes; the partitioned table is ~24 independent
~36 MB units. Old months can be `DETACH`ed (the candidate's hot/archive idea from
section 1.2), `VACUUM`/reindex run per-partition, and a closed month is read-mostly so
its pages stay clean for index-only scans.

## 6. Complementary layer: rollup for frozen months

A frozen historical month never changes, so re-running the live join for every
report of it is wasted work. [`summary_rollup.sql`](../src/ddl/perf/summary_rollup.sql)
pre-aggregates per `(month, wallet, currency)` once the month closes:

- refresh (one month, from the ledger): **~2.9 s** for ~125k rows, run once;
- cold-month report: **~40 ms**, a PK range scan, no join, no aggregate, no spill.

Routing: current month -> live partitioned query; `month < current` -> the rollup.
It is a derived cache (like `wallets.balance`), never the source of truth; the
entries remain authoritative and any month can be recomputed to reconcile.

## 7. Scope

- **Online conversion deferred.** PostgreSQL cannot convert a populated plain
  table to partitioned in place; doing it on a live 50M-row table is a separate
  online migration (create the partitioned parent, backfill, attach, swap,
  Task-3-style expand/contract). The baseline here creates `entries` partitioned
  from the start (the greenfield/empty case); the live conversion is called out
  as needing its own plan (journal section 3).
- **Posting-month semantics.** The window filters `entries.created_at` (posting
  time). "Settled *during* month M" (when settlement lags across a month
  boundary) is a different question, out of scope here: there is no `settled_at`
  column.
