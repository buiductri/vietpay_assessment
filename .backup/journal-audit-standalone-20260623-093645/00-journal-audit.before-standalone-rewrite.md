# 00 Journal audit: thought flaws and improvement pointers

Source reviewed: `2-assessment-report/00-journal.md`

This file consolidates and supersedes:

- `00-journal-fact-check-deep-dive.md`
- `00-journal-thought-coverage-audit.md`

The goal is not to rewrite the journal. The goal is to identify which parts of the thought process are already strong, which parts need precision, which assumptions need caveats, and where to study next before finalizing the assessment.

## Verdict scale

- **Already covered**: the journal already contains the thought. No correction needed.
- **Mostly covered, sharpen wording**: the thought is directionally right, but final wording needs technical precision.
- **Partly covered, add caveat**: the thought exists, but the final deliverable needs a missing caveat.
- **Missing**: the thought was not in the journal and should be added.
- **Real correction**: the thought is technically wrong or too risky as written.

## Executive summary

Your journal is stronger than the first fact-check implied. You already covered many important instincts:

- You explicitly treated the performance analysis as blind guesses, not final conclusions.
- You identified missing DDL and missing query plans as blockers.
- You recognized that aggregate queries can be slow even when the returned row count is small.
- You proposed pre-aggregation before over-indexing.
- You separated customer-facing wallet lookup indexes from all-wallet monthly reporting indexes.
- You leaned toward partitioning for the monthly query.
- You knew PostgreSQL MVCC changes the SQL Server mental model.
- You planned to validate schema and performance with generated data or experiments.
- You understood expand-contract zero-downtime deployment at a high level.
- You flagged `settlement_batch_id` business meaning as an assumption.
- You framed MongoDB and Neo4j around tool-fit, not trend.
- You separated technical observability from business observability.

The actual flaws are narrower:

1. **Index-only scan mechanism**: it depends on the visibility map all-visible bit, not just clean pages or fillfactor.
2. **PostgreSQL clustered index wording**: PostgreSQL has no SQL Server style maintained clustered index, but it does have `CLUSTER` as a one-time physical rewrite.
3. **Settlement report timestamp**: `created_at` may not equal settlement month. Settlement reports often use `settled_at` or `settlement_batches.closed_at`.
4. **`settlement_batch_id NOT NULL`**: global NOT NULL may be domain-wrong if pending, failed, or processing transactions exist.
5. **Currency grouping**: removing `currency` from `GROUP BY` is safe only if the schema enforces one currency per wallet.
6. **Capped collections**: useful as a defense-in-depth guardrail for short-lived logs, but not immutable audit storage.
7. **MongoDB HA statement**: MongoDB replica sets are a strength, but "most RDBMSs lack HA" is too broad.
8. **Neo4j architecture**: correct use case, but final answer must state it is a derived read model, not the authoritative ledger.

## Fast action list before final submission

1. Add `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)` as the validation method for performance claims.
2. Rephrase PostgreSQL index-only scan around MVCC visibility and visibility map.
3. Rephrase clustered-index comparison to mention `CLUSTER` but reject relying on it.
4. Present `(wallet_id, created_at)` as a customer-facing index, not the main settlement aggregate index.
5. Use partial covering indexes and partitioning as the main index discussion.
6. Add `created_at` vs `settled_at` caveat to settlement reporting.
7. Add conditional `settlement_batch_id` constraint option for real domain correctness.
8. Keep `currency` in aggregation unless wallet currency is enforced by schema.
9. Reframe capped collections as limited mutation guardrails, not immutable audit storage.
10. State Neo4j and MongoDB are derived or auxiliary stores. PostgreSQL remains authoritative for money.

## 1. Assessment framing and uncertainty

### Original thought

> Let's make some blind guesses here.

> There is no DDL provided, so we cannot pinpoint whether the table has indexes or not.

### Verdict

**Already covered**.

You correctly marked the performance analysis as hypothesis-driven. That is good assessment behavior. You did not pretend to know the production cause without DDL or query plan.

### Improvement pointer

Make the uncertainty explicit in the final answer:

> Without DDL, table statistics, and `EXPLAIN (ANALYZE, BUFFERS)`, I cannot assert the root cause. I can list likely causes and show how to validate each one.

Add likely PostgreSQL-specific causes:

- Full table scan due to missing or unusable index.
- One-month scan still aggregating around 2 million rows.
- Hash aggregate or sort spilling to disk because `work_mem` is too low.
- Table or index bloat from MVCC.
- Stale statistics.
- Heap fetches defeating index-only scans.
- Low cache hit ratio or high random I/O.

Study:

- `0-research/vp-assessment-dba/05-postgres-performance.md`
- `/home/coder/research/postgresql/14-performance-observability.md`

## 2. Row-count inference

### Original thought

> The transaction table has 50 million rows and receives an additional 2 million rows per month. So we have about 24 months of data in the table.

### Verdict

**Mostly covered, sharpen wording**.

50 million divided by 2 million is 25 months, not 24. But your approximation is fine if volume varies or the table did not start from zero.

### Improvement pointer

Use a range:

> At roughly 2M rows/month, 50M rows represents about 24 to 25 months of history, depending on growth variance and initial data.

This avoids an easy arithmetic nitpick.

## 3. Pre-aggregation and reporting tables

### Original thought

> For historical data, the number rarely changes, so it is safe to pre-aggregate the result beforehand and save it into a set of reporting tables. We can then redirect the query to those tables.

### Verdict

**Already covered**.

This is one of the strongest parts of the thought process. It correctly identifies that reporting workloads often need rollups instead of repeatedly scanning base transactions.

### Improvement pointer

In the final answer, add operational details:

- Use a summary table or materialized view for monthly totals.
- Refresh by batch or incrementally after settlement closes.
- Treat rollups as reporting projections, not authoritative balances.
- If using `REFRESH MATERIALIZED VIEW CONCURRENTLY`, mention it requires a unique index.

Example:

```sql
CREATE MATERIALIZED VIEW mv_monthly_settlement AS
SELECT date_trunc('month', created_at) AS month,
       wallet_id,
       currency,
       SUM(amount) AS total_amount
FROM transactions
WHERE status = 'SETTLED'
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX mv_monthly_settlement_uq
ON mv_monthly_settlement (month, wallet_id, currency);
```

Study:

- `0-research/vp-assessment-dba/05-postgres-performance.md`

## 4. Hot/live vs archive thinking

### Original thought

> In our previous system, we split the table into 2 physical ones. The first is a hot/live transaction table... The second is an archived transaction table...

> Partition(created_at) & IX(wallet_id) : This is the best pattern...

### Verdict

**Partly covered, add caveat**.

You already made the important bridge from live/archive thinking to partitioning. The final answer should make the PostgreSQL-native implementation explicit.

### Flaw to avoid

Do not present manual live/archive tables as the primary PostgreSQL design unless there is a reason partitioning cannot be used. Manual split tables create query routing and consistency overhead that declarative partitioning already solves.

### Improvement pointer

Say:

> In PostgreSQL, I would implement the hot/archive boundary with monthly range partitions. Current partitions stay hot, older partitions become read-mostly, and old partitions can be detached, archived, or indexed differently.

Add caveats:

- Unique and primary keys on partitioned tables must include the partition key because PostgreSQL has no global indexes.
- Too many partitions increase planning time and per-session memory.
- Queries without the partition key cannot prune and may scan all partitions.
- Parent statistics may need manual `ANALYZE`.

Study:

- `/home/coder/research/postgresql/11-partitioning-sharding-scaling.md`

## 5. PostgreSQL MVCC model

### Original thought

> This model does not modify tuples in place; it instead creates a new tuple and updates the pointer to it.

### Verdict

**Mostly covered, sharpen wording**.

The direction is right. PostgreSQL UPDATE creates a new tuple version and marks the old one obsolete for later snapshots. The imprecision is "updates the pointer". In normal updates, indexes usually get new entries. HOT updates are the special case where index entries can keep pointing to a root line pointer and follow a heap chain.

### Improvement pointer

Use this wording:

> PostgreSQL UPDATE creates a new heap tuple version and marks the old version obsolete using MVCC metadata. Visibility is decided by `xmin`, `xmax`, snapshots, and commit status. Dead tuples remain until vacuum or page pruning, so vacuum and bloat management matter for performance.

Study:

- `/home/coder/research/postgresql/03-storage-engine.md`
- `/home/coder/research/postgresql/04-mvcc-transactions-isolation.md`

## 6. Clustered index comparison

### Original thought

> There are no clustered indexes in PostgreSQL either. So we cannot use a clustered index strategy here.

### Verdict

**Mostly covered, sharpen wording**.

The SQL Server comparison is basically correct, but a PostgreSQL reviewer may object because PostgreSQL has the `CLUSTER` command.

### Flaw to avoid

Do not say PostgreSQL has no clustering feature at all.

### Improvement pointer

Say:

> PostgreSQL does not have SQL Server style automatically maintained clustered indexes. It has `CLUSTER`, which rewrites a table once according to an index, but later writes do not preserve that order. Therefore I should not rely on clustered-index strategy for this workload.

Study:

- `/home/coder/research/postgresql/07-indexing.md`
- `/home/coder/research/postgresql/03-storage-engine.md`

## 7. Index scans, visibility, fillfactor, and index-only scans

### Original thought

> Because multiple records of a tuple can exist, an index must fetch the data page to ensure it has the latest data value. This can be mitigated by ensuring the page is clean via fillfactor and the vacuum process. If we can ensure the page is clean, PostgreSQL can use an index-only scan to speed up the query.

### Verdict

**Real correction**.

Your direction is right: PostgreSQL may need heap visits due to MVCC, and vacuum matters. The exact mechanism is wrong.

### Flaw

The heap fetch is not to ensure the "latest" value. It is to check whether the tuple version is visible to the current snapshot. Under MVCC, the visible row might not be the latest committed row.

Fillfactor is also not what enables index-only scans. Fillfactor helps HOT updates and bloat control. Index-only scan depends on the visibility map.

### Improvement pointer

Use this wording:

> PostgreSQL indexes do not by themselves prove tuple visibility. A normal index scan may fetch heap pages to check MVCC visibility. A covering B-tree index can become an index-only scan only when all referenced columns are in the index and the heap page is marked all-visible in the visibility map. VACUUM maintains that visibility map. Fillfactor helps HOT updates and bloat control, but does not directly enable index-only scan.

Validation:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT wallet_id, currency, SUM(amount)
FROM transactions
WHERE status = 'SETTLED'
  AND created_at >= :month_start
  AND created_at < :month_end
GROUP BY wallet_id, currency;
```

Study:

- `/home/coder/research/postgresql/03-storage-engine.md`, Visibility Map and HOT sections.
- `/home/coder/research/postgresql/07-indexing.md`, Index-only scans section.
- `0-research/vp-assessment-dba/05-postgres-performance.md`.

## 8. `status` selectivity and partial indexes

### Original thought

> We can argue that the status is mostly settled if we account for 1 month. So indexing status has limited benefit here.

### Verdict

**Already covered**.

This is correct for a standalone `status` index.

### Improvement pointer

Add the partial-index caveat:

> A standalone status index is weak if most rows are settled, but a partial index `WHERE status = 'SETTLED'` can still be useful because it excludes non-settled rows and reduces index size.

Example:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

## 9. `(wallet_id, created_at)` index

### Original thought

> This pattern works for customer-facing dashboards, because queries for customers always have wallet_id...

> But our query here focuses on summary by month for all wallets, so it will be hard for the planner to emit a plan that can utilize this index pattern.

### Verdict

**Already covered**.

The previous fact-check was too harsh here. You already made the key distinction.

### Improvement pointer

In the final answer, present this index as a rejected or secondary pattern:

> `(wallet_id, created_at)` is useful for wallet history and customer dashboards. It is not the main solution for the all-wallet monthly settlement aggregate because that query has no wallet predicate.

## 10. `(created_at) INCLUDE (...)` index

### Original thought

> This pattern focuses on the chronological order of transactions. This is an audit-centric pattern. But for our reporting query, this index will cover the exact number of records needed for the query...

### Verdict

**Mostly covered, sharpen recommendation**.

You understood the trade-off. Add two improvements:

- Make it partial with `WHERE status = 'SETTLED'`.
- Treat it as a candidate to validate, not guaranteed best.

### Improvement pointer

Example candidate:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

But add:

> For a single monthly partition, a sequential scan plus `HashAggregate` may still beat an index scan. The right answer must be proven with `EXPLAIN (ANALYZE, BUFFERS)`.

## 11. Partition by date plus wallet index

### Original thought

> Partition(created_at) & IX(wallet_id) : This is the best pattern because a range query by month will only touch the needed partition... + pre-order on wallet_id to skip sorting entirely.

### Verdict

**Partly covered, add caveat**.

The partitioning part is strong. The "skip sorting entirely" part needs qualification.

### Flaw

An index on `wallet_id` only skips sorting if the input order matches the grouping keys and the planner chooses a sorted aggregation path. If the query groups by `(wallet_id, currency)`, then the order needs to include `currency`, unless `currency` is functionally dependent on `wallet_id` and the planner can use that fact.

### Improvement pointer

Say:

> Partitioning by month guarantees partition pruning for the date range. A local index ordered by `(wallet_id, currency)` may allow GroupAggregate without an explicit sort, but this is plan-dependent and must be verified. The main guaranteed win is pruning to one partition and using smaller local indexes.

## 12. Currency and grouping

### Original thought

> If currency is an attribute of wallet, we should not add it to group_by, instead we should use an aggregate in SELECT because for 1 wallet, currency is the same. But if we have multiple currencies in a wallet, the key here is composite and it makes the query harder.

### Verdict

**Mostly covered, sharpen wording**.

You saw the correct modeling fork. The risky part is using an aggregate on `currency` without explicitly enforcing one currency per wallet.

### Flaw

`MIN(currency)` or `MAX(currency)` can hide data corruption if a wallet accidentally has multiple currencies. Money must never be summed across currencies.

### Improvement pointer

Say:

> I will model each wallet as single-currency and enforce that invariant in the schema. Then grouping by wallet is safe and currency can be joined from `wallets`. If that invariant is not enforced, keep `currency` in the `GROUP BY`.

Schema pointer:

```sql
ALTER TABLE wallets
  ADD CONSTRAINT wallets_id_currency_uq UNIQUE (id, currency);

ALTER TABLE ledger_entries
  ADD CONSTRAINT ledger_entries_wallet_currency_fk
  FOREIGN KEY (wallet_id, currency)
  REFERENCES wallets (id, currency);
```

Study:

- `0-research/vp-assessment-dba/01-fintech-payments-domain.md`
- `0-research/vp-assessment-dba/02-double-entry-ledger-money.md`
- `0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`

## 13. `created_at` vs `settled_at`

### Original thought

> The point of the query is to calculate the statement for all wallets that have been settled in a month.

and the query pattern is filtered on `created_at`.

### Verdict

**Missing, real domain caveat**.

Following the given query is fine. But the domain statement "settled in a month" usually refers to settlement time or settlement batch, not creation time.

### Flaw

If the business asks for a June settlement statement, `created_at` can be wrong. A transaction created on May 31 may settle in June. A transaction created in June may settle in July.

### Improvement pointer

Say:

> I optimize the query as given, using `created_at`. In the domain model, I would also store `settled_at` and `settlement_batch_id`, because settlement reports and reconciliation usually group by settlement date or settlement batch, not always by transaction creation date.

Study:

- `0-research/vp-assessment-dba/01-fintech-payments-domain.md`

## 14. Double-entry ledger

### Original thought

> I can recognize most of the terms here, except the double-entry ledger. So I will use AI to run research on this topic...

### Verdict

**Missing in journal, but intentionally deferred**.

This is not a flaw in the journal. You explicitly marked it as a knowledge gap.

### Improvement pointer

After research, the final answer must not treat `transactions` as the ledger. Use this shape:

- `accounts` or `wallets`: balance containers.
- `ledger_transactions`: event or journal header.
- `ledger_entries`: immutable debit/credit lines.
- `idempotency_keys`: retry safety.
- `audit_trail`: non-monetary state changes.

Core invariant:

```text
SUM(signed ledger entries) = 0 per ledger transaction
```

Study:

- `0-research/double-entry-ledger/02-ledger-vs-transactions.md`
- `0-research/double-entry-ledger/03-schema-design.md`
- `0-research/double-entry-ledger/05-integrity-guarantees.md`

## 15. Executable DDL and validation

### Original thought

> SQL files also need to be executable so we can validate the schema.

> If we have time, we can use AI to generate a generator service that mimics the backend so we can have data in these tables for validation.

### Verdict

**Already covered**.

Good thought. Keep it.

### Improvement pointer

In final deliverables, add a minimal validation plan:

- Run DDL in a clean PostgreSQL database.
- Insert valid and invalid ledger postings.
- Verify invalid postings fail.
- Generate sample transactions for query-plan testing.
- Run `EXPLAIN (ANALYZE, BUFFERS)` before and after indexes or partitioning.

## 16. `settlement_batch_id NOT NULL`

### Original thought

> Actually, the column name is just an example, so I can assume this task only cares about deployment planning.

> This needs extra collaboration with the application side, so we might need another plan in case the above assumption is wrong.

### Verdict

**Partly covered, add concrete domain caveat**.

You already flagged the assumption. The final answer needs to show what the alternate plan is.

### Flaw

A global `NOT NULL` can be domain-wrong if the table contains pending, processing, or failed transactions that do not have a settlement batch yet.

### Improvement pointer

Say:

> If the assessment truly requires `settlement_batch_id NOT NULL`, I will show the zero-downtime path. In a real payment model, I would first validate whether every transaction can have a batch. Pending or failed rows may need `settlement_batch_id` nullable with a conditional constraint.

Conditional constraint:

```sql
ALTER TABLE transactions
  ADD CONSTRAINT tx_settled_requires_batch
  CHECK (status <> 'SETTLED' OR settlement_batch_id IS NOT NULL) NOT VALID;
```

Only use full `NOT NULL` if the business rule truly says every row must have a batch.

## 17. Zero-downtime migration phases

### Original thought

> The best way is to have a 3-stage deployment: (1) introduce the new column without a constraint; (2) deploy the application that will populate data into the new column...; (3) backfill data and enforce the constraint...

### Verdict

**Already covered**.

This part is strong. The previous fact-check only adds PostgreSQL-specific details.

### Improvement pointer

Add these implementation details:

- Add nullable column with no default.
- Backfill in batches, committing each batch.
- Use `NOT VALID` then `VALIDATE CONSTRAINT`.
- Promote to `NOT NULL` only after a validated check proves no nulls.
- Build new indexes with `CREATE INDEX CONCURRENTLY` when needed.
- `CREATE INDEX CONCURRENTLY` cannot run inside a transaction.
- Use `lock_timeout` to avoid sitting in a dangerous lock queue.

Fast validation pattern if full `NOT NULL` is actually required:

```sql
ALTER TABLE transactions
  ADD CONSTRAINT transactions_sbid_not_null
  CHECK (settlement_batch_id IS NOT NULL) NOT VALID;

ALTER TABLE transactions VALIDATE CONSTRAINT transactions_sbid_not_null;
ALTER TABLE transactions ALTER COLUMN settlement_batch_id SET NOT NULL;
```

Study:

- `0-research/vp-assessment-dba/06-postgres-migration-concurrency.md`

## 18. PostgreSQL locking and deployment concerns

### Original thought

> Some of the most important items are: locking, long-running queries, vacuum process, fillfactor, transaction commits and rollbacks.

### Verdict

**Already covered at high level**.

### Improvement pointer

Add exact lock names in the final answer:

- `ACCESS EXCLUSIVE`: strongest table lock, many `ALTER TABLE` forms use it briefly.
- `SHARE UPDATE EXCLUSIVE`: used by `VALIDATE CONSTRAINT` and `CREATE INDEX CONCURRENTLY` phases.
- `ROW EXCLUSIVE`: normal DML.

Also mention:

- Long transactions hold old snapshots and delay vacuum cleanup.
- Backfill should be batched to avoid bloat and lock pile-ups.
- Rollback should be phase-specific.

## 19. MongoDB document model

### Original thought

> For MongoDB, its strongest points are the dynamic schema approach and document-centric design.

> Most people use MongoDB to store logs only. This is understandable because logs are very schema-volatile...

### Verdict

**Partly covered**.

The direction is right. The final answer should choose a more precise MongoDB use case than generic logs.

### Improvement pointer

Best assessment use case:

> Store raw webhook and provider event payloads in MongoDB, because each provider sends different and evolving JSON shapes, and these documents are usually written whole, replayed whole, and rarely joined.

Use MongoDB for:

- Raw webhook payload capture.
- Provider-specific event JSON.
- Replay and debugging.
- Time-series metrics or event streams where MongoDB time-series collections fit.

Do not use MongoDB as the authoritative ledger. Keep the ledger in PostgreSQL.

Study:

- `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`

## 20. MongoDB capped collections

### Original thought

> MongoDB has capped collections that forbid all updates on the collection. Even the root account cannot modify the data without dropping and repopulating data, so storing audit data in MongoDB has this advantage too.

### Verdict

**Partly covered, but wording needs precision**.

Your clarified intent is valid:

> This is not full-proof protection. It is a storage-level guardrail beyond permissions. Even with broad permission, delete or some update paths return errors.

That is a good defense-in-depth argument. But the original sentence overclaims.

### Flaw

- Capped collections do not "forbid all updates" in the broad sense. MongoDB docs discuss updates on capped collections.
- Size-changing updates fail, but not every update is categorically forbidden.
- Older MongoDB docs explicitly say individual deletes are not allowed, but an admin can still drop or recreate the collection.
- Capped collections overwrite old documents when full. That makes them bad as the sole compliance audit store.

### Improvement pointer

Use this wording:

> Capped collections can provide a storage-level guardrail for short-lived append-style logs: individual document deletion and size-changing updates are restricted, so accidental mutation is harder even if permissions are too broad. This is defense-in-depth, not immutable storage. Because capped collections are fixed-size circular buffers that overwrite old records, they are not suitable as the sole compliance audit trail.

Better architecture:

- Use PostgreSQL immutable ledger entries for authoritative money movement.
- Use PostgreSQL trigger-based `audit_trail` for non-monetary state changes.
- Use strict `REVOKE UPDATE, DELETE`, backups, retention policy, and WORM/object-lock storage if needed.
- Use capped collections only for short-lived operational logs where rollover is desired.

Study:

- `0-research/vp-assessment-dba/03-compliance-audit-immutability.md`
- `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`

## 21. MongoDB HA statement

### Original thought

> MongoDB has a built-in HA solution, which most RDBMSs lack...

### Verdict

**Partly covered, add caveat**.

The MongoDB part is right. Replica sets make replication and automatic elections a standard deployment model. The "most RDBMSs" comparison is too broad.

### Improvement pointer

Say:

> MongoDB replica sets make replication and automatic failover part of the standard deployment model. PostgreSQL core provides replication primitives but relies on external HA tooling or managed services for failure detection, election, fencing, and routing.

Study:

- `/home/coder/research/postgresql/10-ha-failover-pooling.md`

## 22. MongoDB time-series and clustered collections

### Original thought

> The latest MongoDB has time series collections and clustered collections, so if we have data that requires these features, we can consider using MongoDB.

### Verdict

**Already covered at high level, add caveat**.

### Improvement pointer

If using this in the final answer, add:

- Time-series collections are good for measurement-like data with a time field and metadata field.
- They have update restrictions, so they are not a general mutable document pattern.
- Use them for metrics, rate snapshots, settlement event streams, or operational telemetry, not authoritative ledger entries.

## 23. Neo4j graph fit

### Original thought

> The best use for it is, of course, graph problems such as relationship mapping or fraud detection.

### Verdict

**Partly covered**.

Correct core idea. Missing final-architecture caveats.

### Improvement pointer

Say:

> Neo4j is a derived graph read model for fraud, AML, KYC relationship traversal, and entity resolution. PostgreSQL remains the authoritative ledger and balance source.

Add caveats:

- CDC lag makes the graph eventually consistent.
- Authoritative decisions should confirm against PostgreSQL.
- Supernodes can hurt performance, for example a high-volume merchant, bank, country, or currency node.
- Model by query first. Do not turn every low-cardinality attribute into a node.
- Production Neo4j HA, backup, fine-grained access control, and CDC may require Enterprise or Aura.

Study:

- `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`
- `0-research/neo4j-graph-fintech/07-production-case-studies.md`
- `0-research/neo4j-graph-fintech/08-modeling-operations-tradeoffs.md`

## 24. Observability

### Original thought

> For the monitoring aspect, we must approach it from 2 aspects: technical and business.

> CPU, memory, I/O, internal logs, locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs.

### Verdict

**Already covered at high level, add concrete metric names**.

### Improvement pointer

Technical metrics:

- `pg_up` for liveness.
- `pg_stat_database_xact_commit` and rollback rate for throughput and failure rate.
- `pg_stat_statements` for query latency and top slow queries.
- `pg_stat_database_blks_hit / (blks_hit + blks_read)` for cache hit ratio.
- `pg_stat_replication` lag for replicas.
- `pg_locks` and `pg_stat_activity.wait_event` for lock contention.
- `pg_stat_database_deadlocks` for deadlocks.
- Connections vs `max_connections`.
- Disk growth, table/index bloat, WAL generation, checkpoint pressure.
- Autovacuum lag, dead tuples, freeze age, transaction ID wraparound risk.

Business metrics:

- Settlement lag.
- Reconciliation mismatch count and amount.
- Duplicate idempotency-key attempts.
- Failed or reversed transaction rate.
- Backfill progress and null count during migration.

SLO framing:

- Define SLI, SLO, and error budget.
- Alert on sustained error-budget burn, not every spike.
- Separate page-now alerts from business-hours capacity warnings.

Study:

- `0-research/vp-assessment-dba/08-observability-architecture-adr.md`

## 25. ADRs, microservices, and data contracts

### Original thought

> The task requires some more thought about standards and the microservices aspect so I need to cover them too.

### Verdict

**Partly covered, intentionally deferred**.

This is not a missing thought. It is a TODO. The final answer needs the details.

### Improvement pointer

Add:

- ADR template: title, status, context, decision, consequences.
- Strong consistency for ledger posting, idempotency, and zero-sum entries.
- Eventual consistency for reporting rollups, MongoDB payload store, Neo4j graph, and other read models.
- Data contracts with backward, forward, or full compatibility rules.
- Transactional outbox plus CDC for reliable cross-service events.
- Saga pattern for cross-service workflows that cannot share one ACID transaction.

Study:

- `0-research/vp-assessment-dba/08-observability-architecture-adr.md`

## 26. Flyway and Liquibase

### Original thought

> About Flyway and Liquibase, I have no idea, so my approach will be ad hoc scripts first, then have AI do some search...

### Verdict

**Already covered as a knowledge gap**.

The journal is honest. In the final deliverable, do not present ad hoc scripts as the production plan.

### Improvement pointer

Say:

> I would first validate raw SQL scripts, then package them as ordered Flyway or Liquibase migrations with idempotent guards, rollback notes, and non-transactional migration handling for `CREATE INDEX CONCURRENTLY`.

## Consolidated flaw matrix

| Area | Coverage | Flaw or risk | Improvement |
|---|---|---|---|
| Performance root cause | Mostly covered | Could over-focus on table scan | Add stats, bloat, spill, heap-fetch causes and verify with `EXPLAIN`. |
| Row count | Mostly covered | 50M / 2M is 25, not 24 | Say 24 to 25 months. |
| Pre-aggregation | Already covered | None | Add refresh and consistency details. |
| Live/archive | Partly covered | Manual split less native in PostgreSQL | Use range partitions as hot/cold boundary. |
| MVCC | Mostly covered | "updates pointer" is simplified | Use tuple-version and visibility wording. |
| Clustered index | Mostly covered | Ignores PostgreSQL `CLUSTER` command | Say no SQL Server style maintained clustered index. |
| Index-only scan | Real correction | Uses "latest value" and fillfactor wording | Use visibility map and MVCC visibility wording. |
| Status index | Already covered | Missing partial-index nuance | Add `WHERE status = 'SETTLED'` partial index. |
| Wallet/date index | Already covered | Could be seen as equal candidate | Mark as customer-dashboard index, not settlement aggregate index. |
| Date covering index | Mostly covered | Missing partial index and validation | Add partial covering index and `EXPLAIN` caveat. |
| Partition plus wallet index | Partly covered | Sort skip not guaranteed | Say plan-dependent, use `(wallet_id, currency)` if needed. |
| Currency | Mostly covered | Aggregate on currency can hide drift | Enforce wallet currency or keep `currency` in `GROUP BY`. |
| Settlement timestamp | Missing | `created_at` may not mean settlement month | Add `settled_at` or batch close time caveat. |
| Double-entry ledger | Deferred | Not yet designed in journal | Use ledger header plus immutable entries and zero-sum invariant. |
| Settlement batch NOT NULL | Partly covered | Global NOT NULL may be domain-wrong | Add conditional constraint option. |
| Zero downtime | Already covered | Missing PostgreSQL implementation details | Add `NOT VALID`, `VALIDATE`, batched backfill, concurrent index caveats. |
| MongoDB documents | Partly covered | Use case too generic | Use raw webhooks/provider events as primary fit. |
| Capped collections | Partly covered | Overclaims immutability | Present as limited guardrail, not audit store. |
| MongoDB HA | Partly covered | RDBMS comparison too broad | Compare MongoDB replica sets to PostgreSQL core plus external HA. |
| Neo4j | Partly covered | Missing derived-store caveat | State graph is derived and eventually consistent. |
| Observability | Already covered at high level | Missing metric names and SLOs | Add concrete PostgreSQL metrics and business SLIs. |
| ADR/microservices | Deferred | Needs details | Add ADR, data contracts, outbox, sagas. |
| Flyway/Liquibase | Deferred | Ad hoc is not final production plan | Package validated SQL in migration tooling. |

## Reusable snippets

### Query validation

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT wallet_id, currency, SUM(amount)
FROM transactions
WHERE status = 'SETTLED'
  AND created_at >= :month_start
  AND created_at <  :month_end
GROUP BY wallet_id, currency;
```

### Partial covering index

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

### Partitioned transaction table shape

```sql
CREATE TABLE transactions (
  id BIGINT GENERATED ALWAYS AS IDENTITY,
  wallet_id UUID NOT NULL,
  amount NUMERIC(19,4) NOT NULL,
  currency CHAR(3) NOT NULL,
  status TEXT NOT NULL,
  created_at timestamptz NOT NULL,
  settled_at timestamptz,
  settlement_batch_id UUID,
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
```

### Conditional settlement-batch constraint

```sql
ALTER TABLE transactions
  ADD CONSTRAINT tx_settled_requires_batch
  CHECK (status <> 'SETTLED' OR settlement_batch_id IS NOT NULL) NOT VALID;
```

### Fast NOT NULL promotion when global NOT NULL is truly required

```sql
ALTER TABLE transactions
  ADD CONSTRAINT transactions_sbid_not_null
  CHECK (settlement_batch_id IS NOT NULL) NOT VALID;

ALTER TABLE transactions VALIDATE CONSTRAINT transactions_sbid_not_null;
ALTER TABLE transactions ALTER COLUMN settlement_batch_id SET NOT NULL;
```

Use this only if the business rule really says every row must have a batch.

### Wallet currency enforcement

```sql
ALTER TABLE wallets
  ADD CONSTRAINT wallets_id_currency_uq UNIQUE (id, currency);

ALTER TABLE ledger_entries
  ADD CONSTRAINT ledger_entries_wallet_currency_fk
  FOREIGN KEY (wallet_id, currency)
  REFERENCES wallets (id, currency);
```

## Research pointers

Primary local research:

- `0-research/vp-assessment-dba/01-fintech-payments-domain.md`
- `0-research/vp-assessment-dba/02-double-entry-ledger-money.md`
- `0-research/vp-assessment-dba/03-compliance-audit-immutability.md`
- `0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`
- `0-research/vp-assessment-dba/05-postgres-performance.md`
- `0-research/vp-assessment-dba/06-postgres-migration-concurrency.md`
- `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`
- `0-research/vp-assessment-dba/08-observability-architecture-adr.md`

Deep dives:

- `0-research/double-entry-ledger/02-ledger-vs-transactions.md`
- `0-research/double-entry-ledger/03-schema-design.md`
- `0-research/double-entry-ledger/05-integrity-guarantees.md`
- `0-research/neo4j-graph-fintech/07-production-case-studies.md`
- `0-research/neo4j-graph-fintech/08-modeling-operations-tradeoffs.md`
- `/home/coder/research/postgresql/03-storage-engine.md`
- `/home/coder/research/postgresql/04-mvcc-transactions-isolation.md`
- `/home/coder/research/postgresql/07-indexing.md`
- `/home/coder/research/postgresql/10-ha-failover-pooling.md`
- `/home/coder/research/postgresql/11-partitioning-sharding-scaling.md`
- `/home/coder/research/postgresql/14-performance-observability.md`

Official MongoDB docs checked for capped collection nuance:

- `https://www.mongodb.com/docs/manual/core/capped-collections/`
- `https://www.mongodb.com/docs/manual/replication/`
- `https://www.mongodb.com/docs/manual/core/timeseries-collections/`
