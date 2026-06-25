# Task 2: Query and Performance: the settlement report

> Generated: 2026-06-25 | Axis: Query and performance | Primary sources: journal section 1.2 and 3, `docs/query-performance.md`, `src/ddl/perf/`

This axis reorganizes the existing Task 2 material. Nothing here is new analysis: the candidate's reasoning is lifted verbatim from the design journal, and the AI-authored query-plan study is the committed `docs/query-performance.md`. Each block below is tagged with who wrote it.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content (the empirical plan analysis and any composed summary). This mirrors the journal's own human / `<ai>` split.

## TL;DR

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 3 and 3.2*

"The direction was there, but I do not have extensive PostgreSQL experience yet, so my own contribution to this section is the reasoning and the DDL changes for partitioning. The deep query-plan analysis is AI-generated." "So the report is now a JOIN of `entries` to `transactions`. ... That leaves exactly two honest options: optimise the join, or redirect to a pre-aggregated summary table. I wanted both, as I already hinted in Section 1.2."

---

## Key Findings

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the candidate's own words, verbatim quotes from journal section 1.2 and 3*

- "Partition(created_at) & IX(wallet_id) : This is the best pattern because a range query by month will only touch the needed partition, including the index, so we can have the best of both worlds here: range query for only needed tuples + pre-order on wallet_id to skip sorting entirely."
- "The three index options I sketched in Section 1.2 are **stale**. They all assumed those columns sat on one table. After the split they do not hold unchanged, so I rebuilt the index thinking from the join".
- "The optimised join is the primary deliverable; a summary table is the complementary layer for the cold historical months that never change."
- "`transactions` stays unpartitioned but indexed, because it is an FK target ... `entries` is safe to partition precisely because it is a leaf (nothing references it)."

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *headline numbers, `docs/query-performance.md` (real `EXPLAIN (ANALYZE, BUFFERS)` on PostgreSQL 17.2)*

- Flat baseline to partitioned + covering index: shared-buffer reads about 68,300 to about 2,570 (about 26x fewer), execution about 1,183 ms to about 477 ms.
- The plan flips on two markers: the entries scan prunes to one monthly partition, and the header side becomes an `Index Only Scan` with `Heap Fetches: 0`.
- Index cost: the covering partial index is about 66 MB at this scale and indexes only the about 85% SETTLED rows.

---

## Detailed Analysis

### The query has to change: the entry split turned it into a join

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 3.1*

In Section 1.2 the query lived on one flat `transactions` table, so `status`, `wallet_id`, `amount`, `currency`, and `created_at` were all on one row. Task 1 split that: the money columns moved to `entries` (immutable, append-only, the table I want to partition), and `status` stayed on the `transactions` header (mutable, it flips `PENDING -> SETTLED` later). So the report is now a JOIN of `entries` to `transactions`.

Two consequences I had to face honestly:

- The three index options I sketched in Section 1.2 are **stale**. They all assumed those columns sat on one table. After the split they do not hold unchanged, so I rebuilt the index thinking from the join rather than porting them over.
- I cannot dodge the join by denormalizing `status` back onto `entries`. Entries are immutable (`REVOKE UPDATE` plus a deny trigger), and a transaction settles *after* its entries are written (the smoke test posts entries while the transaction is still `PENDING`). So a mutable `status` cannot live on an immutable row. That leaves exactly two honest options: optimise the join, or redirect to a pre-aggregated summary table. I wanted both, as I already hinted in Section 1.2.

### Decisions (grill session)

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 3.2*

I had the AI grill me on the open forks before building. What I settled:

- **Both solutions.** The optimised join is the primary deliverable; a summary table is the complementary layer for the cold historical months that never change. The assessment asks to "provide the improved query and the supporting indexes and/or partitioning strategy", so the query optimised in place is the thing it wants; the summary table is the second layer.
- **Posting-month semantics.** The window filters `entries.created_at` (posting time), which is the faithful reading of the original single-timestamp query. "Settled *during* month M" (when settlement lags across a month boundary) is a different question; we do not even have a `settled_at` column, and the business meaning of the window is out of scope. This is a tuning exercise.
- **Partition only `entries`, by modifying the initial script.** Not a separate expansion phase. `transactions` stays unpartitioned but indexed, because it is an FK target (`entries`, `audit_logs`, `idempotency_keys` all reference `transactions(transaction_id)`); partitioning it would force its PK to `(transaction_id, created_at)` and break those FKs. `entries` is safe to partition precisely because it is a leaf (nothing references it). The online conversion of an already-populated table is the "expansion" I deferred: it needs more reasoning and is a Task-3-style migration, not this.
- **Empirical, AI-authored.** Seed a few million rows in a throwaway schema on the provided PostgreSQL 17.2 and read the real plans. The write-up is AI's.

### The DDL changes

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 3.3*

What changed in the baseline (the empty/greenfield case):

- **`initial/07_entry`**: `entries` is now `PARTITION BY RANGE (created_at)` with the composite PK `(entry_id, created_at)` (PostgreSQL requires the partition key in the PK). A `create_entries_partition()` helper builds one month idempotently; the baseline calls it over a deterministic window plus a DEFAULT partition safety net. The existing local indexes are kept (they serve joins and per-wallet dashboards, not the report, which needs no entries index).
- **`initial/06_transaction`**: added a covering partial index `transactions (created_at) INCLUDE (transaction_id) WHERE status = 'SETTLED'`. The benchmark showed this turns the header side of the join into an index-only scan with zero heap fetches.
- **`initial/11_immutability`**: partitioning opened a subtle gap. Row-level UPDATE/DELETE deny triggers clone to partitions automatically, but the statement-level TRUNCATE trigger only sits on the parent, so a direct `TRUNCATE entries_pYYYYMM` would slip past it. The app role can never TRUNCATE (no privilege, and partitions grant it nothing), so the guarantee holds, but I closed the defence-in-depth gap by attaching the TRUNCATE guard to every partition (and the helper attaches it to future ones).

Validated end to end on the provided PostgreSQL 17.2: a full `down-to 05` then `up` redeploy, `verify`, and the smoke test all pass against the partitioned `entries`; the `now()`-dated inserts route into the right partition; and the deferred per-currency zero-sum constraint trigger still fires on the partitions.

### The complementary summary rollup

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 3.4*

`src/ddl/perf/summary_rollup.sql` adds `wallet_monthly_settlement`, a per-`(month, wallet, currency)` rollup, with `refresh_wallet_monthly_settlement()` to recompute one month from the ledger. A frozen month never changes, so it is computed once after the month closes; thereafter a cold-month report is a single PK range scan instead of the live join. Routing: current month uses the live query, earlier months read the rollup. Like `wallets.balance`, it is a derived cache, never the source of truth.

### Empirical performance analysis

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 3.4; full walk-through in `docs/query-performance.md`*

Full plan walk-through with the real `EXPLAIN (ANALYZE, BUFFERS)` output is in [`docs/query-performance.md`](sources/02-query-and-performance/query-performance.md); the reproducible harness is `src/ddl/perf/bench.sql`. Headline, on a ~4M-entry seed on PostgreSQL 17.2:

- **Flat baseline -> partitioned + covering index:** shared-buffer reads ~68,300 -> ~2,570 (about 26x fewer, both at a reporting `work_mem` so neither aggregate spills), execution ~1,183 ms -> ~477 ms. The plan flips on two markers: the entries scan prunes to one monthly partition (53,223 -> 2,222 buffers), and the header side becomes an `Index Only Scan` on the new covering partial index with `Heap Fetches: 0` (the ~14k-buffer heap fetch disappears). The rewrite is result-preserving: flat and partitioned both return the identical 124,739 groups.
- **The redundant `t.created_at` predicate matters:** without it the planner cannot restrict the header to the month, so it scans all 2M transactions for `status='SETTLED'`. Pushing it on (safe: entry and header share the posting commit time) lets the header seek the index.
- **Remaining cost is the aggregate, not the scan:** the `GROUP BY` over ~125k groups spills at the server's default 4 MB `work_mem` (~540 ms, ~6,400 temp blocks); a higher reporting `work_mem` removes the spill (no schema change). So counting all I/O at the default it is ~7.6x; at a matched `work_mem` where neither side spills it is the ~26x shared-buffer-reads figure. The data-access win (pruning + index-only header) is real either way.
- **Index cost:** the covering partial index is ~66 MB at this scale and indexes only the ~85% SETTLED rows; a PENDING/REVERSED row enters it only when it settles. Measured write overhead: a 1M-row bulk header insert went ~5.6 s -> ~9.1 s with the index present (~3.5 us/row; a marginal cost on top of the existing PK + created_at index, and posting is one row at a time). Partitioning also makes per-partition B-trees smaller and old months cheap to `DETACH`/`VACUUM` (the hot/archive idea from Section 1.2).
- **Summary rollup:** ~2.9 s to refresh one month once; thereafter a cold-month report is ~40 ms (a PK range scan), versus ~540 ms for the live join.

The committed query, after normalisation, and the supporting index:

```sql
SELECT e.wallet_id, e.currency, SUM(e.amount) AS settled_total
FROM entries e
JOIN transactions t ON t.transaction_id = e.transaction_id
WHERE t.status = 'SETTLED'
  AND e.created_at >= :m_start AND e.created_at < :m_end
  AND t.created_at >= :m_start AND t.created_at < :m_end   -- redundant; lets the header seek the index
GROUP BY e.wallet_id, e.currency;
```

---

### Human direction

> **Human direction (Bùi Đức Trí):** Keep it simple: target only `entries`, and modify the initial script rather than building a separate expansion phase. The online conversion of a populated table is deferred; it needs more reasoning. I want both the optimised join and the summary table introduced here. And make it clear that the deep performance analysis is the AI's work, not my own.

## Open Questions

*Deferred items, summarized from journal section 3 and `docs/query-performance.md` section 7.*

- **Online conversion deferred.** PostgreSQL cannot convert a populated plain table to partitioned in place; doing it on a live 50M-row table is a separate online migration (create the partitioned parent, backfill, attach, swap, Task-3-style expand/contract). The baseline here creates `entries` partitioned from the start; the live conversion needs its own plan.
- **Posting-month semantics.** The window filters `entries.created_at` (posting time). "Settled *during* month M" is a different question, out of scope here: there is no `settled_at` column.

## Sources

[1] Design journal, section 1.2 and 3 (candidate's reasoning, verbatim) - (local: sources/journal/00-journal.md)
[2] Task 2 query-plan analysis, AI-authored - (local: sources/02-query-and-performance/query-performance.md)
[3] Task 2 SQL: optimised query, rollup, benchmark - `src/ddl/perf/` (repo)
[4] Partitioning DDL - `src/ddl/initial/07_entry.up.sql`, covering index `src/ddl/initial/06_transaction.up.sql` (repo)
