# 00 Journal audit report

Source reviewed: `2-assessment-report/00-journal.md`

This is a standalone audit of the reasoning in the journal. It identifies where the thought process is already strong, where wording should be tightened, where domain assumptions are risky, and what to study before finalizing the assessment.

## Audit method

This report is self-contained. Each finding combines three things in one place:

1. **Audit concern**: the possible flaw, weak assumption, or technical issue being checked.
2. **Journal evidence**: the relevant journal quote showing whether the thought was already covered.
3. **Improvement pointer**: the correction, caveat, or deeper study path needed before final submission.

The report intentionally separates true flaws from thoughts that were already present but needed sharper wording. This prevents valid journal reasoning from being counted as missing while still preserving the technical corrections.

## Purpose

The goal is not to rewrite the journal. The goal is to help turn the journal into a stronger final assessment by answering these questions:

1. Which thoughts are already correct and should be kept?
2. Which thoughts are directionally right but technically imprecise?
3. Which assumptions may become wrong in a real fintech payment model?
4. Which topics need deeper study before final submission?
5. What exact wording, SQL snippets, or validation steps can improve the final answer?

## Verdict labels

- **Strength**: already good reasoning. Keep it.
- **Precision fix**: concept is right, but wording should be more exact.
- **Domain caveat**: technically possible, but business meaning may change the answer.
- **Risk**: likely to be challenged by a reviewer if left as written.
- **Gap**: not yet developed in the journal, usually because it was marked as a research TODO.

## Research base

Local research used for this audit:

- `0-research/vp-assessment-dba/01-fintech-payments-domain.md`
- `0-research/vp-assessment-dba/02-double-entry-ledger-money.md`
- `0-research/vp-assessment-dba/03-compliance-audit-immutability.md`
- `0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`
- `0-research/vp-assessment-dba/05-postgres-performance.md`
- `0-research/vp-assessment-dba/06-postgres-migration-concurrency.md`
- `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`
- `0-research/vp-assessment-dba/08-observability-architecture-adr.md`
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

## Executive assessment

The journal is a good thinking artifact. It is honest about uncertainty, separates guesses from facts, and correctly identifies several high leverage solutions. The main problem is not the overall direction. The main problem is a small set of imprecise technical claims and domain assumptions that should be tightened before final submission.

### What is already strong

- You explicitly label the performance analysis as blind guesses.
- You correctly treat missing DDL and missing query plan as blockers.
- You recognize that an aggregate query can be expensive even if it returns few rows.
- You propose pre-aggregation instead of trying to solve everything with indexes.
- You distinguish customer-facing wallet queries from all-wallet monthly reporting.
- You prefer partitioning for the monthly query shape.
- You understand that PostgreSQL MVCC invalidates some SQL Server mental models.
- You plan to validate DDL and performance with executable SQL and generated data.
- You understand expand-contract migration at a high level.
- You explicitly flag `settlement_batch_id` business meaning as an assumption.
- You frame MongoDB and Neo4j as tool-fit choices, not trend choices.
- You separate technical observability from business observability.

### Highest priority fixes

| Priority | Area | Problem | Fix |
|---|---|---|---|
| 1 | PostgreSQL index-only scan | Wording says heap fetch is for latest value and fillfactor makes pages clean | Use MVCC visibility and visibility map wording. |
| 2 | Settlement reporting | Query uses `created_at`, but business settlement month may mean `settled_at` or batch close time | State that you optimize the given query, while domain model should include `settled_at` and `settlement_batch_id`. |
| 3 | `settlement_batch_id NOT NULL` | Global NOT NULL may be wrong for pending or failed rows | Show conditional constraint option for settled rows. |
| 4 | Currency aggregation | Aggregating currency in SELECT can hide invalid mixed-currency rows | Keep `currency` in `GROUP BY` unless one currency per wallet is enforced. |
| 5 | Capped collections | Original wording overclaims immutability | Present capped collections as limited defense-in-depth for short-lived logs, not compliance audit storage. |
| 6 | Clustered index wording | PostgreSQL does have `CLUSTER` | Say no SQL Server style maintained clustered index, but `CLUSTER` exists as one-time physical rewrite. |
| 7 | Neo4j architecture | Correct use case but missing authority boundary | State Neo4j is a derived, eventually consistent graph read model. |

## Audit coverage summary

This table states the concern being checked, whether the journal already covered it, and what this report recommends. It keeps the correction and the coverage judgment together in this file.

| Audit concern | Coverage in journal | Report action |
|---|---|---|
| Performance claims may be overconfident without DDL or plans | Covered. The journal calls them blind guesses and notes missing DDL. | Keep the uncertainty, add `EXPLAIN (ANALYZE, BUFFERS)`. |
| 50M rows at 2M/month implies 25 months, not 24 | Mostly covered. The estimate is close but imprecise. | Say 24 to 25 months. |
| Slow query may have causes beyond table scan | Partly covered. Table scan and aggregate cost are covered. | Add stale stats, bloat, spills, heap fetches, cache behavior. |
| Pre-aggregation may be the right reporting solution | Covered strongly. The journal already proposes reporting tables. | Keep it, add refresh and consistency details. |
| Manual live/archive split may be less native in PostgreSQL | Partly covered. The journal later proposes partitioning. | Present partitions as the PostgreSQL hot/cold implementation. |
| MVCC wording may be too simplified | Mostly covered. Tuple versioning is identified. | Replace pointer wording with tuple-version and visibility wording. |
| PostgreSQL clustered-index claim may be challenged | Mostly covered. SQL Server contrast is right. | Mention `CLUSTER` exists but is not maintained like SQL Server clustered index. |
| Index-only scan explanation may be wrong | Partly covered but technically wrong in mechanism. | Use visibility map and MVCC visibility wording. |
| `status` index may be low value | Covered. Low selectivity is already noted. | Add partial index nuance for `WHERE status = 'SETTLED'`. |
| `(wallet_id, created_at)` may not fit all-wallet settlement report | Covered. The journal already says it fits customer-facing queries instead. | Present it as secondary or rejected for this report query. |
| `(created_at) INCLUDE (...)` needs sharper recommendation | Mostly covered. Trade-off is identified. | Make it a partial covering index and validate with plans. |
| Partition plus wallet index may not always skip sort | Partly covered. Partitioning benefit is correct. | Make sort-skip plan-dependent and include grouping key order caveat. |
| Removing `currency` from `GROUP BY` can be unsafe | Mostly covered. The modeling fork is identified. | Require schema-enforced one currency per wallet, else group by currency. |
| Settlement month may not equal `created_at` month | Missing. The journal follows the given query shape. | Add `settled_at` and settlement batch date caveat. |
| Double-entry ledger is not yet designed | Gap intentionally identified. | Add ledger transactions, entries, zero-sum invariant, idempotency. |
| Executable DDL validation is needed | Covered. The journal already says SQL must be executable. | Add concrete validation cases. |
| `settlement_batch_id NOT NULL` may be domain-wrong | Partly covered. The journal flags business assumption risk. | Add conditional constraint option for settled rows. |
| Zero-downtime phases may need PostgreSQL mechanics | Covered at high level. | Add `NOT VALID`, `VALIDATE`, batched backfill, concurrent index caveats. |
| Locking concerns may need exact names | Covered at high level. | Add lock modes and long-transaction vacuum impact. |
| MongoDB use case is too generic | Partly covered. Dynamic schema and logs are identified. | Use raw webhook/provider event payloads as the cleanest fit. |
| Capped collections are overclaimed as immutable | Partly covered with valid intent, but original wording is risky. | Present as limited defense-in-depth for short-lived logs, not audit storage. |
| MongoDB HA comparison is too broad | Partly covered. MongoDB replica-set strength is valid. | Compare to PostgreSQL core plus external HA tooling, not all RDBMSs. |
| MongoDB time-series mention needs constraints | Covered at high level. | Add update restrictions and measurement-data fit if used. |
| Neo4j graph fit needs authority boundary | Partly covered. Fraud and relationship fit is identified. | State Neo4j is derived and eventually consistent. |
| Observability needs concrete metrics | Covered at high level. | Add metric names, business SLIs, SLO framing. |
| ADR and microservices details are undeveloped | Gap intentionally identified. | Add ADR template, contracts, outbox, saga, consistency model. |
| Flyway/Liquibase is a knowledge gap | Gap intentionally identified. | Validate raw SQL, then package in migration tooling. |

## Detailed findings

## 1. Assumption discipline and missing validation

### Journal evidence

> Let's make some blind guesses here:

> There is no DDL provided, so we cannot pinpoint whether the table has indexes or not.

### Verdict

**Strength**.

You correctly avoid overclaiming. This is the right posture when DDL, statistics, and query plans are missing.

### Improvement pointer

In the final assessment, make validation explicit instead of leaving it implied:

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT wallet_id, currency, SUM(amount)
FROM transactions
WHERE status = 'SETTLED'
  AND created_at >= :month_start
  AND created_at <  :month_end
GROUP BY wallet_id, currency;
```

Look for:

- `Seq Scan`, `Index Scan`, `Bitmap Heap Scan`, or `Index Only Scan`.
- Whether only the target partition is scanned.
- `HashAggregate` memory usage and spill behavior.
- `Sort Method: external merge` if sorting spills to disk.
- Heap fetches during index-only scan attempts.
- Buffer reads and hits before and after changes.

Study:

- `0-research/vp-assessment-dba/05-postgres-performance.md`
- `/home/coder/research/postgresql/14-performance-observability.md`

## 2. Row-count inference

### Journal evidence

> The transaction table has 50 million rows and receives an additional 2 million rows per month.

> So we have about 24 months of data in the table.

### Verdict

**Precision fix**.

50 million divided by 2 million is 25 months. Your estimate is close enough if volume varies, but the exact arithmetic can be challenged.

### Improvement pointer

Use this wording:

> At roughly 2M rows/month, 50M rows represents about 24 to 25 months of history, depending on growth variance and initial data.

## 3. Performance cause analysis

### Journal evidence

> One of the biggest performance killers is a table scan without using an index...

> The query is an aggregate query... the query always needs to scan 2 million rows...

### Verdict

**Strength, add depth**.

You already identify two major causes:

- Full scan from missing or unusable index.
- Aggregate over millions of rows even with a small result set.

### Missing depth

Add PostgreSQL-specific causes in final answer:

- Stale statistics causing a bad plan.
- Hash aggregate or sort spill due to low `work_mem`.
- MVCC bloat increasing pages scanned.
- Index bloat increasing index scan cost.
- Heap fetches defeating index-only scan.
- Poor cache hit ratio or high random I/O.
- Long-running transactions delaying vacuum cleanup.

This turns the answer from guesswork into a testable diagnostic plan.

## 4. Pre-aggregation and reporting tables

### Journal evidence

> For historical data, the number rarely changes, so it is safe to pre-aggregate the result beforehand and save it into a set of reporting tables. We can then redirect the query to those tables.

> This is the main reason why we usually have different summary tables that pre-aggregate by year/month/day/hour for reporting purposes. I will lean into this solution more than using the index.

### Verdict

**Strength**.

This is one of the best parts of the journal. Repeated monthly settlement reporting is often better served by rollups than repeated base-table aggregation.

### Improvement pointer

In final answer, add operational detail:

- Rollups are reporting projections, not authoritative balances.
- Refresh after settlement batch close or on a schedule.
- Materialized views need a unique index for concurrent refresh.
- Summary tables can be incrementally maintained if freshness matters.

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

## 5. Hot/live vs archive thinking

### Journal evidence

> In our previous system, we split the table into 2 physical ones. The first is a hot/live transaction table... The second is an archived transaction table...

Context: "previous system" here means the prior SQL Server/customer asset system experience used as an analogy in the journal, not the VietPay assessment database.

> Partition(created_at) & IX(wallet_id) : This is the best pattern...

### Verdict

**Strength, add PostgreSQL caveat**.

The hot/cold data instinct is good. You also already translate it toward partitioning later.

### Risk

If final answer emphasizes manual live/archive tables too much, PostgreSQL reviewers may expect declarative partitioning first.

### Improvement pointer

Say:

> In PostgreSQL, I would implement the hot/archive boundary with monthly range partitions. Current partitions stay hot; older partitions become read-mostly and can be detached, archived, vacuumed, or indexed differently.

Mention these caveats:

- Unique and primary keys on partitioned tables must include the partition key.
- PostgreSQL has no global indexes for partitioned tables.
- Too many partitions increase planning time and memory.
- Queries without the partition key cannot prune.
- Parent statistics may need manual `ANALYZE`.

Study:

- `/home/coder/research/postgresql/11-partitioning-sharding-scaling.md`

## 6. PostgreSQL MVCC model

### Journal evidence

> This model does not modify tuples in place; it instead creates a new tuple and updates the pointer to it.

### Verdict

**Precision fix**.

Directionally right, but final wording should be more exact.

### Risk

"Updates the pointer" is too vague. In normal updates, PostgreSQL creates a new tuple version and index entries usually point to tuple IDs. HOT updates are the special case where index entries can keep pointing at a root line pointer and follow a heap chain.

### Improvement pointer

Use this wording:

> PostgreSQL UPDATE creates a new heap tuple version and marks the old version obsolete using MVCC metadata. Visibility is decided by `xmin`, `xmax`, snapshots, and commit status. Dead tuples remain until vacuum or page pruning, so vacuum and bloat management matter for performance.

Study:

- `/home/coder/research/postgresql/03-storage-engine.md`
- `/home/coder/research/postgresql/04-mvcc-transactions-isolation.md`

## 7. Clustered index comparison

### Journal evidence

> There are no clustered indexes in PostgreSQL either. So we cannot use a clustered index strategy here.

### Verdict

**Precision fix**.

The SQL Server comparison is basically right, but PostgreSQL has the `CLUSTER` command.

### Risk

A reviewer may mark "no clustered indexes" as incomplete PostgreSQL knowledge if `CLUSTER` is not acknowledged.

### Improvement pointer

Say:

> PostgreSQL does not have SQL Server style automatically maintained clustered indexes. It has `CLUSTER`, which rewrites a table once according to an index, but later writes do not preserve that physical order. Therefore I should not rely on clustered-index strategy for this workload.

Study:

- `/home/coder/research/postgresql/07-indexing.md`
- `/home/coder/research/postgresql/03-storage-engine.md`

## 8. Index scans, visibility, fillfactor, and index-only scans

### Journal evidence

> Because multiple records of a tuple can exist, an index must fetch the data page to ensure it has the latest data value.

> This can be mitigated by ensuring the page is clean via fillfactor and the vacuum process.

> If we can ensure the page is clean, PostgreSQL can use an index-only scan to speed up the query.

### Verdict

**Real correction**.

Your direction is right: MVCC can force heap visits, and vacuum matters. The exact mechanism is wrong.

### Flaw

Heap fetch is not for the latest value. It is for MVCC visibility. Under MVCC, a query may need an older visible tuple version, not the latest committed version.

Fillfactor does not directly enable index-only scans. Fillfactor reserves page space to improve HOT update chances and reduce bloat. Index-only scans depend on the visibility map all-visible bit.

### Improvement pointer

Use this wording:

> PostgreSQL indexes do not by themselves prove tuple visibility. A normal index scan may fetch heap pages to check MVCC visibility. A covering B-tree index can become an index-only scan only when all referenced columns are in the index and the heap page is marked all-visible in the visibility map. VACUUM maintains that visibility map. Fillfactor helps HOT updates and bloat control, but does not directly enable index-only scan.

Study:

- `/home/coder/research/postgresql/03-storage-engine.md`, Visibility Map and HOT sections.
- `/home/coder/research/postgresql/07-indexing.md`, Index-only scans section.
- `0-research/vp-assessment-dba/05-postgres-performance.md`.

## 9. Status selectivity and partial indexes

### Journal evidence

> We can argue that the status is mostly settled if we account for 1 month. So indexing status has limited benefit here.

### Verdict

**Strength, add nuance**.

A standalone `status` index is weak if most rows are settled. That is correct.

### Improvement pointer

Add this nuance:

> A standalone status index is weak if most rows are settled, but a partial index `WHERE status = 'SETTLED'` can still be useful because it excludes non-settled rows and reduces index size.

Example:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

## 10. `(wallet_id, created_at)` index

### Journal evidence

> This pattern works for customer-facing dashboards, because queries for customers always have wallet_id...

> But our query here focuses on summary by month for all wallets, so it will be hard for the planner to emit a plan that can utilize this index pattern.

### Verdict

**Strength**.

This was already covered in the journal. You correctly distinguish customer access patterns from all-wallet reporting.

### Improvement pointer

In the final answer, present this as a secondary or rejected candidate:

> `(wallet_id, created_at)` is useful for wallet history and customer dashboards. It is not the main solution for the all-wallet monthly settlement aggregate because that query has no wallet predicate.

## 11. `(created_at) INCLUDE (...)` index

### Journal evidence

> This pattern focuses on the chronological order of transactions. This is an audit-centric pattern.

> For our reporting query, this index will cover the exact number of records needed for the query...

> wallet_id will then be useless in the key and will need to be sorted anyway...

### Verdict

**Strength, sharpen recommendation**.

You understood the trade-off. Add partial-index and validation details.

### Improvement pointer

Use this candidate:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

Add this caveat:

> For a single monthly partition, a sequential scan plus `HashAggregate` may still beat an index scan. The right answer must be proven with `EXPLAIN (ANALYZE, BUFFERS)`.

## 12. Partition by date plus wallet index

### Journal evidence

> Partition(created_at) & IX(wallet_id) : This is the best pattern because a range query by month will only touch the needed partition... + pre-order on wallet_id to skip sorting entirely.

### Verdict

**Domain and planner caveat**.

The partitioning part is strong. The sort-skip claim needs qualification.

### Risk

An index on `wallet_id` only skips sorting if the input order matches the grouping keys and the planner chooses a sorted aggregation path. If the query groups by `(wallet_id, currency)`, then the order should include `currency`, unless `currency` is functionally dependent on `wallet_id` and the planner can use that fact.

### Improvement pointer

Say:

> Partitioning by month guarantees partition pruning for the date range. A local index ordered by `(wallet_id, currency)` may allow GroupAggregate without an explicit sort, but this is plan-dependent and must be verified. The main guaranteed win is pruning to one partition and using smaller local indexes.

## 13. Currency and grouping

### Journal evidence

> If currency is an attribute of wallet, we should not add it to group_by, instead we should use an aggregate in SELECT because for 1 wallet, currency is the same.

> But if we have multiple currencies in a wallet, the key here is composite and it makes the query harder.

### Verdict

**Precision fix**.

You saw the correct modeling fork. The final wording must attach it to schema enforcement.

### Risk

Using `MIN(currency)` or `MAX(currency)` can hide invalid mixed-currency data. Money must not be summed across currencies unless the schema proves those rows are same-currency.

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

## 14. `created_at` vs `settled_at`

### Journal evidence

> The point of the query is to calculate the statement for all wallets that have been settled in a month.

The query pattern discussed uses `created_at`.

### Verdict

**Missing domain caveat**.

Following the given query is fine. But the business phrase "settled in a month" usually refers to settlement time or settlement batch, not creation time.

### Risk

A transaction created on May 31 can settle in June. A transaction created in June can settle in July. A settlement report based only on `created_at` may be wrong for reconciliation.

### Improvement pointer

Say:

> I optimize the query as given, using `created_at`. In the domain model, I would also store `settled_at` and `settlement_batch_id`, because settlement reports and reconciliation usually group by settlement date or settlement batch, not always by transaction creation date.

Study:

- `0-research/vp-assessment-dba/01-fintech-payments-domain.md`

## 15. Double-entry ledger

### Journal evidence

> I can recognize most of the terms here, except the double-entry ledger. So I will use AI to run research on this topic...

### Verdict

**Gap, intentionally deferred**.

This is not a flaw in the journal. You explicitly marked it as a knowledge gap. The final assessment must fill it.

### Improvement pointer

The final schema should avoid treating `transactions` as the ledger. Use this shape:

- `accounts` or `wallets`: balance containers.
- `ledger_transactions`: event or journal header.
- `ledger_entries`: immutable debit and credit lines.
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

## 16. Executable DDL and validation

### Journal evidence

> SQL files also need to be executable so we can validate the schema.

> If we have time, we can use AI to generate a generator service that mimics the backend so we can have data in these tables for validation.

### Verdict

**Strength**.

This is good. Keep it.

### Improvement pointer

Add a minimal validation plan:

- Run DDL in a clean PostgreSQL database.
- Insert valid ledger postings.
- Insert invalid ledger postings and verify they fail.
- Generate sample transactions for query-plan testing.
- Run `EXPLAIN (ANALYZE, BUFFERS)` before and after indexes or partitioning.

## 17. `settlement_batch_id NOT NULL`

### Journal evidence

> Actually, the column name is just an example, so I can assume this task only cares about deployment planning.

> This needs extra collaboration with the application side so we might need another plan in case the above assumption is wrong.

### Verdict

**Domain caveat**.

You already flagged the assumption. The final answer needs the concrete alternate plan.

### Risk

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

## 18. Zero-downtime migration phases

### Journal evidence

> The best way is to have a 3-stage deployment: (1) introduce the new column without a constraint; (2) deploy the application that will populate data into the new column...; (3) backfill data and enforce the constraint...

### Verdict

**Strength, add PostgreSQL details**.

The expand-contract idea is already strong. Add concrete PostgreSQL mechanics.

### Improvement pointer

Add these details:

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

## 19. PostgreSQL locking and deployment concerns

### Journal evidence

> Some of the most important items are: locking, long-running queries, vacuum process, fillfactor, transaction commits and rollbacks.

### Verdict

**Strength, add exact terms**.

### Improvement pointer

Add exact lock names:

- `ACCESS EXCLUSIVE`: strongest table lock, many `ALTER TABLE` forms use it briefly.
- `SHARE UPDATE EXCLUSIVE`: used by `VALIDATE CONSTRAINT` and parts of `CREATE INDEX CONCURRENTLY`.
- `ROW EXCLUSIVE`: normal DML.

Also mention:

- Long transactions hold old snapshots and delay vacuum cleanup.
- Backfill should be batched to avoid bloat and lock pile-ups.
- Rollback should be phase-specific.

## 20. MongoDB document model

### Journal evidence

> For MongoDB, its strongest points are the dynamic schema approach and document-centric design.

> Most people use MongoDB to store logs only. This is understandable because logs are very schema-volatile...

### Verdict

**Strength, sharpen use case**.

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

## 21. MongoDB capped collections

### Journal evidence

> MongoDB has capped collections that forbid all updates on the collection. Even the root account cannot modify the data without dropping and repopulating data, so storing audit data in MongoDB has this advantage too.

### Verdict

**Risk, but with valid core intent**.

Your clarified intent is valid:

> This is not foolproof protection. It is a storage-level guardrail beyond permissions. Even with broad permission, delete or some update paths return errors.

That is a good defense-in-depth argument. The original sentence overclaims.

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
- Use strict `REVOKE UPDATE, DELETE`, backups, retention policy, and WORM or object-lock storage if needed.
- Use capped collections only for short-lived operational logs where rollover is desired.

Study:

- `0-research/vp-assessment-dba/03-compliance-audit-immutability.md`
- `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`

## 22. MongoDB HA statement

### Journal evidence

> MongoDB has a built-in HA solution, which most RDBMSs lack...

### Verdict

**Precision fix**.

The MongoDB part is right. Replica sets make replication and automatic elections part of the standard deployment model. The comparison with most RDBMSs is too broad.

### Improvement pointer

Say:

> MongoDB replica sets make replication and automatic failover part of the standard deployment model. PostgreSQL core provides replication primitives but relies on external HA tooling or managed services for failure detection, election, fencing, and routing.

Study:

- `/home/coder/research/postgresql/10-ha-failover-pooling.md`

## 23. MongoDB time-series and clustered collections

### Journal evidence

> The latest MongoDB has time series collections and clustered collections, so if we have data that requires these features, we can consider using MongoDB.

### Verdict

**Strength, add caveat if used**.

### Improvement pointer

If using this in the final answer, add:

- Time-series collections are good for measurement-like data with a time field and metadata field.
- They have update restrictions, so they are not a general mutable document pattern.
- Use them for metrics, rate snapshots, settlement event streams, or operational telemetry, not authoritative ledger entries.

## 24. Neo4j graph fit

### Journal evidence

> The best use for it is, of course, graph problems such as relationship mapping or fraud detection.

### Verdict

**Strength, add architecture boundary**.

Correct core idea. The final answer needs authority and consistency caveats.

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

## 25. Observability

### Journal evidence

> For the monitoring aspect, we must approach it from 2 aspects: technical and business.

> CPU, memory, I/O, internal logs, locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs.

### Verdict

**Strength, add concrete metric names**.

The high level split is good. The final answer needs exact metrics and SLO framing.

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

## 26. ADRs, microservices, and data contracts

### Journal evidence

> The task requires some more thought about standards and the microservices aspect so I need to cover them too.

### Verdict

**Gap, intentionally deferred**.

This is not a failure of the journal. It is a TODO. The final answer needs the details.

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

## 27. Flyway and Liquibase

### Journal evidence

> About Flyway and Liquibase, I have no idea, so my approach will be ad hoc scripts first, then have AI do some search...

### Verdict

**Gap, intentionally identified**.

The journal is honest. In the final deliverable, avoid presenting ad hoc scripts as the production plan.

### Improvement pointer

Say:

> I would first validate raw SQL scripts, then package them as ordered Flyway or Liquibase migrations with idempotent guards, rollback notes, and non-transactional migration handling for `CREATE INDEX CONCURRENTLY`.

## Consolidated flaw matrix

| Area | Verdict | Flaw or risk | Improvement |
|---|---|---|---|
| Assumptions | Strength | None | Keep saying claims need DDL and `EXPLAIN`. |
| Row count | Precision fix | 50M / 2M is 25, not 24 | Say 24 to 25 months. |
| Performance causes | Strength, add depth | May understate stats, bloat, spills | Add PostgreSQL-specific causes. |
| Pre-aggregation | Strength | None | Add refresh and consistency details. |
| Live/archive | Strength, add caveat | Manual split less native in PostgreSQL | Use partitions as hot/cold boundary. |
| MVCC | Precision fix | "updates pointer" is simplified | Use tuple-version and visibility wording. |
| Clustered index | Precision fix | Ignores `CLUSTER` | Say no SQL Server style maintained clustered index. |
| Index-only scan | Real correction | Uses latest-value and fillfactor explanation | Use MVCC visibility and visibility map. |
| Status index | Strength, add nuance | Standalone status index weak, but partial index useful | Add `WHERE status = 'SETTLED'`. |
| Wallet/date index | Strength | Could be misread as equal candidate | Mark as customer-dashboard index. |
| Date covering index | Strength, sharpen | Missing partial index and validation | Add partial covering index and `EXPLAIN`. |
| Partition plus wallet index | Domain and planner caveat | Sort skip not guaranteed | Make it plan-dependent. |
| Currency | Precision fix | Aggregate currency can hide drift | Enforce wallet currency or group by currency. |
| Settlement timestamp | Missing caveat | `created_at` may not mean settlement month | Add `settled_at` and batch date caveat. |
| Double-entry ledger | Gap | Not yet designed in journal | Add ledger header, entries, zero-sum invariant. |
| Settlement batch NOT NULL | Domain caveat | Global NOT NULL may be wrong | Add conditional constraint option. |
| Zero downtime | Strength, add detail | Missing exact PostgreSQL operations | Add `NOT VALID`, `VALIDATE`, batched backfill. |
| MongoDB documents | Strength, sharpen | Use case too generic | Use raw webhooks/provider events. |
| Capped collections | Risk | Overclaims immutability | Present as limited guardrail, not audit store. |
| MongoDB HA | Precision fix | RDBMS comparison too broad | Compare MongoDB replica sets to PostgreSQL core plus HA tooling. |
| Neo4j | Strength, add boundary | Missing derived-store caveat | State graph is derived and eventually consistent. |
| Observability | Strength, add detail | Missing metric names and SLOs | Add PostgreSQL metrics and business SLIs. |
| ADR/microservices | Gap | Needs details | Add ADR, data contracts, outbox, sagas. |
| Flyway/Liquibase | Gap | Ad hoc is not final plan | Package validated SQL in migration tooling. |

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
