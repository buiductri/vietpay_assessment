# 00 Journal thought coverage audit

Source reviewed: `2-assessment-report/00-journal.md`
Previous fact-check reviewed: `2-assessment-report/00-journal-fact-check-deep-dive.md`

Purpose: re-check whether each previous fact-check point was truly missing, already covered, or only needed sharper wording.

## Verdict scale

- **Already covered**: your journal already had the thought. Previous note should not be treated as a correction.
- **Mostly covered, sharpen wording**: your thought was directionally right, but needs more precise technical wording.
- **Partly covered, add caveat**: your thought was present, but the final answer should add a missing caveat.
- **Missing**: the thought was not in the journal.
- **Overstated in previous fact-check**: my previous note treated it too strongly as wrong or missing.

## Summary

You were right to push back. Several earlier notes were additions or precision improvements, not true corrections. Your journal already covered many of the core instincts:

- You already treated the performance section as blind guesses, not final claims.
- You already identified pre-aggregation as a likely reporting fix.
- You already separated customer-facing wallet lookup indexes from all-wallet monthly reporting.
- You already preferred partitioning for the settlement query.
- You already flagged the `settlement_batch_id` business meaning as an assumption.
- You already approached Neo4j as a knowledge gap that needed research.
- You already covered observability at a high level.

The genuinely problematic or under-precise parts are narrower:

1. Capped collections: useful guardrail, but not immutable audit storage.
2. Index-only scan mechanics: visibility map, not just clean pages or fillfactor.
3. `created_at` vs `settled_at`: domain nuance not covered.
4. `settlement_batch_id NOT NULL`: global NOT NULL might be domain-wrong unless task explicitly forces it.
5. PostgreSQL clustered index wording: no SQL Server style clustered index, but PostgreSQL has `CLUSTER` as a one-time reorder.
6. Currency aggregation: your design instinct is right, but the final query should rely on schema enforcement, not `MIN(currency)` as a substitute for grouping.

## Point-by-point audit

### 1. Row-count inference and performance causes

Previous fact-check point: 50 million rows at 2 million/month is about 25 months, and slow query could be caused by more than full-table scan.

Coverage verdict: **Mostly covered, sharpen wording**.

Your journal already says:

> Let's make some blind guesses here:

and:

> There is no DDL provided, so we cannot pinpoint whether the table has indexes or not.

and:

> One of the biggest performance killers is a table scan without using an index...

and:

> The query is an aggregate query... the query always needs to scan 2 million rows...

So you were not claiming certainty. You were explicitly doing assumption-driven diagnosis.

What still needs adding:

- Other PostgreSQL-specific causes: stale stats, hash aggregate spilling, bloat, weak vacuum, low cache hit, random heap fetches.
- 50M / 2M = 25, not 24, unless volume varied or initial rows existed.

Better final wording:

> Assuming roughly stable growth, 50M rows at 2M/month means about 24 to 25 months of data. Without DDL and `EXPLAIN`, this is only a hypothesis. Candidate causes include full scan, aggregate over millions of rows, stale statistics, bloat, heap fetches, or sort/hash aggregate spill.

### 2. Pre-aggregation and reporting tables

Previous fact-check point: use rollups/materialized views for repeated settlement reporting.

Coverage verdict: **Already covered**.

Your journal already says:

> For historical data, the number rarely changes, so it is safe to pre-aggregate the result beforehand and save it into a set of reporting tables. We can then redirect the query to those tables.

This is exactly the right instinct. The fact-check should have treated this as a confirmed strength, not a missing point.

What to add only if writing the final answer:

- Mention materialized views or summary tables.
- Mention refresh strategy and eventual consistency.
- Mention `REFRESH MATERIALIZED VIEW CONCURRENTLY` needs a unique index if using materialized views.

### 3. Hot/live vs archive split

Previous fact-check point: in PostgreSQL, prefer declarative partitioning over manual live/archive split.

Coverage verdict: **Partly covered, add caveat**.

Your journal already says:

> In our previous system, we split the table into 2 physical ones. The first is a hot/live transaction table... The second is an archived transaction table...

and later:

> Partition(created_at) & IX(wallet_id) : This is the best pattern...

So you already made the bridge from live/archive thinking to partitioning. The missing part is not the concept, but the PostgreSQL-native implementation detail.

Better final wording:

> In PostgreSQL, I would implement the hot/archive boundary with range partitions first, not separate unrelated tables. Current partitions stay hot; older partitions become read-mostly and can be detached, archived, vacuumed, or indexed differently.

Add caveats:

- Too many partitions hurt planning.
- Unique constraints must include partition key.
- Queries without partition key lose pruning.

### 4. PostgreSQL MVCC model

Previous fact-check point: your MVCC explanation was broad but not exact.

Coverage verdict: **Mostly covered, sharpen wording**.

Your journal already says:

> This model does not modify tuples in place; it instead creates a new tuple and updates the pointer to it.

That is directionally right. PostgreSQL UPDATE creates a new tuple version and marks the old version with `xmax`; `ctid` links to the newer version. Your simplified wording is acceptable for a journal.

What to sharpen:

- PostgreSQL does not update a generic "pointer" in the index for normal updates. Index entries usually point to tuple IDs. HOT updates can keep index entries pointing at a root line pointer with a HOT chain.
- Dead tuples remain until vacuum or page pruning.

Better final wording:

> PostgreSQL UPDATE creates a new heap tuple version and marks the old version obsolete for later snapshots. Visibility is decided by `xmin`, `xmax`, snapshots, and commit status. This creates dead tuples and makes vacuum central to performance.

### 5. Clustered indexes

Previous fact-check point: PostgreSQL has no SQL Server style clustered index, but has `CLUSTER`.

Coverage verdict: **Mostly covered, sharpen wording**.

Your journal says:

> There are no clustered indexes in PostgreSQL either. So we cannot use a clustered index strategy here.

This is mostly right in the SQL Server comparison. The only issue is wording. A PostgreSQL reviewer may object because PostgreSQL has a `CLUSTER` command.

Better final wording:

> PostgreSQL does not have SQL Server style automatically maintained clustered indexes. It has `CLUSTER`, which rewrites the table once according to an index, but later writes do not preserve that physical order. Therefore, I should not rely on a clustered-index strategy for this workload.

### 6. Index scan and index-only scan mechanics

Previous fact-check point: index-only scans depend on the visibility map, not just fillfactor or clean pages.

Coverage verdict: **Partly covered, real precision correction**.

Your journal says:

> Because multiple records of a tuple can exist, an index must fetch the data page to ensure it has the latest data value.

and:

> This can be mitigated by ensuring the page is clean via fillfactor and the vacuum process.

and:

> PostgreSQL can use an index-only scan to speed up the query.

Your direction is right: PostgreSQL may need heap visits due to MVCC, and vacuum matters. But the exact reason is not "latest data value". It is MVCC visibility for the current snapshot. Also, fillfactor is not what makes index-only scan valid.

Better final wording:

> PostgreSQL indexes are not enough by themselves to prove tuple visibility. A normal index scan may fetch heap pages to check MVCC visibility. A covering B-tree index can become an index-only scan only when all referenced columns are in the index and the heap page is marked all-visible in the visibility map. VACUUM maintains that visibility map. Fillfactor helps HOT updates and bloat control, but does not directly enable index-only scan.

This is a real correction, not just an addition.

### 7. `status` selectivity

Previous fact-check point: low-cardinality status may not be useful alone.

Coverage verdict: **Already covered**.

Your journal says:

> We can argue that the status is mostly settled if we account for 1 month. So indexing status has limited benefit here.

Correct. The only thing to add is that a partial index on settled rows can still be useful even if `status` alone is low-cardinality.

Better final wording:

> A standalone status index is weak if most rows are settled, but a partial index `WHERE status = 'SETTLED'` can still be useful because it removes non-settled rows from the index and reduces index size.

### 8. `IX(wallet_id, created_at)` for the settlement query

Previous fact-check point: `wallet_id, created_at` is not the main all-wallet monthly settlement index.

Coverage verdict: **Already covered, previous fact-check was too harsh**.

Your journal already says:

> This pattern works for customer-facing dashboards, because queries for customers always have wallet_id...

and:

> But our query here focuses on summary by month for all wallets, so it will be hard for the planner to emit a plan that can utilize this index pattern.

That is exactly the correction. You had already made it.

What still needs adding:

- Do not present it as an equal candidate for the assessment query. Present it as a rejected or secondary index for a different access pattern.

Better final wording:

> `(wallet_id, created_at)` is useful for customer-facing wallet history, but it is not the main solution for the all-wallet monthly settlement aggregate because the query has no wallet predicate.

### 9. `IX(created_at) INCLUDE (...)`

Previous fact-check point: a partial covering index on `created_at` may be a good candidate.

Coverage verdict: **Mostly covered, sharpen recommendation**.

Your journal says:

> This pattern focuses on the chronological order of transactions. This is an audit-centric pattern.

and:

> For our reporting query, this index will cover the exact number of records needed for the query...

and:

> wallet_id will then be useless in the key and will need to be sorted anyway...

This is good. You understood the trade-off.

What to add:

- Make it partial: `WHERE status = 'SETTLED'`.
- Use `INCLUDE (wallet_id, currency, amount)` for covering.
- Validate with `EXPLAIN`, because a partition scan plus hash aggregate may still win.

Better final wording:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

### 10. Partition by `created_at` plus wallet index

Previous fact-check point: it does not always skip sort entirely.

Coverage verdict: **Partly covered, add caveat**.

Your journal says:

> This is the best pattern because a range query by month will only touch the needed partition, including the index...

Correct.

Your journal also says:

> pre-order on wallet_id to skip sorting entirely.

This is the part that needs caveat. It only skips sort if the input order matches the grouping keys and the planner chooses a sorted aggregation path. If the query groups by `(wallet_id, currency)`, an index on just `wallet_id` may not fully satisfy grouping order unless currency is functionally dependent on wallet or included in the order.

Better final wording:

> Partitioning by month guarantees partition pruning for the date range. A local index ordered by `(wallet_id, currency)` may allow GroupAggregate without an explicit sort, but this is plan-dependent and must be verified. The main guaranteed win is pruning to one partition and smaller local indexes.

### 11. Currency and grouping

Previous fact-check point: do not drop `currency` unless schema proves one wallet has one currency.

Coverage verdict: **Mostly covered, sharpen wording**.

Your journal says:

> If currency is an attribute of wallet, we should not add it to group_by...

and:

> But if we have multiple currencies in a wallet, the key here is composite and it makes the query harder.

and:

> I will lean toward keeping currency as an attribute.

So you already saw the modeling fork. The only risky phrase is:

> instead we should use an aggregate in SELECT

That can hide a data integrity problem unless the schema enforces one currency per wallet.

Better final wording:

> I will model wallet as single-currency and enforce `(wallet_id, currency)` consistency with a composite FK. Then grouping by wallet is safe and currency can be joined from `wallets`. If that invariant is not enforced, keep `currency` in `GROUP BY`.

### 12. Pre-aggregation as stronger solution than indexes

Previous fact-check point: use monthly rollups.

Coverage verdict: **Already covered**.

Your journal says:

> This is the main reason why we usually have different summary tables that pre-aggregate by year/month/day/hour for reporting purposes. I will lean into this solution more than using the index.

This is good and should be kept.

What to add:

- Rollups are for reporting, not authoritative balances.
- Refresh can be batch, incremental, or materialized view depending on freshness needs.

### 13. Need data and `EXPLAIN`

Previous fact-check point: validate with query plans and data.

Coverage verdict: **Already covered**.

Your journal says:

> This requires data to experiment with.

and:

> Also needs thorough testing.

and:

> we need to test if index-only scan works or not

This is already present. The final answer only needs to name the concrete tool:

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
```

### 14. Double-entry ledger knowledge gap

Previous fact-check point: do not treat `transactions` as the ledger.

Coverage verdict: **Missing in journal, but intentionally deferred**.

Your journal says:

> I can recognize most of the terms here, except the double-entry ledger. So I will use AI to run research...

So this was not supposed to be complete yet. The fact-check should not frame this as a flaw in the thought process. It is an explicit research TODO.

What the final answer must include after research:

- `transactions` or `ledger_transactions` as event headers.
- `ledger_entries` as immutable debit/credit lines.
- Per-transaction zero-sum invariant.
- Idempotency table.
- Reversing transactions for correction.

### 15. ERD and executable DDL validation

Previous fact-check point: schema should be executable and validated.

Coverage verdict: **Already covered**.

Your journal says:

> SQL files also need to be executable so we can validate the schema.

and:

> If we have time, we can use AI to generate a generator service that mimics the backend so we can have data in these tables for validation.

This is good.

### 16. `created_at` vs `settled_at`

Previous fact-check point: settlement reporting may need settlement timestamp or batch time.

Coverage verdict: **Missing, real domain caveat**.

Your journal consistently follows the assessment query shape, which filters `created_at`. That is fine for query optimization. But if you describe it as "statement of all wallets that have been settled in a month", the domain might require `settled_at` or `settlement_batches.closed_at`, not `created_at`.

Better final wording:

> I optimize the query as given, using `created_at`. In the domain model, I would also store `settled_at` and `settlement_batch_id`, because settlement reports and reconciliation usually group by settlement date or batch, not always by transaction creation date.

### 17. `settlement_batch_id NOT NULL`

Previous fact-check point: global NOT NULL may be wrong if pending or failed transactions exist.

Coverage verdict: **Partly covered, previous fact-check was too harsh**.

Your journal says:

> Actually, the column name is just an example, so I can assume this task only cares about deployment planning.

and:

> This needs extra collaboration with the application side, so we might need another plan in case the above assumption is wrong.

So you already flagged it as an assumption. The missing thing is the concrete domain caveat.

Better final wording:

> If the assessment truly requires `settlement_batch_id NOT NULL`, I will show the zero-downtime path. In a real payment model, I would first validate whether every transaction can have a batch. Pending or failed rows may need `settlement_batch_id` nullable with a conditional constraint: `status <> 'SETTLED' OR settlement_batch_id IS NOT NULL`.

### 18. Zero-downtime deployment phases

Previous fact-check point: expand-contract with dual-write, backfill, validate, enforce.

Coverage verdict: **Already covered**.

Your journal says:

> the best way is to have a 3-stage deployment: (1) introduce the new column without a constraint; (2) deploy the application that will populate data into the new column...; (3) backfill data and enforce the constraint...

This is correct. The previous fact-check only added PostgreSQL-specific implementation details:

- `NOT VALID` check.
- `VALIDATE CONSTRAINT`.
- `SET NOT NULL` after validated check.
- `CREATE INDEX CONCURRENTLY` caveats.
- Batched backfill.

So mark this as already strong, not missing.

### 19. PostgreSQL locking and internal deployment concerns

Previous fact-check point: mention locks, long transactions, vacuum, rollback.

Coverage verdict: **Already covered at high level**.

Your journal says:

> Some of the most important items are: locking, long-running queries, vacuum process, fillfactor, transaction commits and rollbacks.

Correct. Add lock names in final answer if needed:

- `ACCESS EXCLUSIVE` for many `ALTER TABLE` forms.
- `SHARE UPDATE EXCLUSIVE` for `VALIDATE CONSTRAINT`.
- `ROW EXCLUSIVE` for normal DML.

### 20. MongoDB dynamic schema and document-centric fit

Previous fact-check point: MongoDB fit for raw webhook/event payloads, not universal audit store.

Coverage verdict: **Partly covered**.

Your journal says:

> For MongoDB, its strongest points are the dynamic schema approach and document-centric design.

and:

> Most people use MongoDB to store logs only. This is understandable because logs are very schema-volatile...

Good. The missing part is a sharper workload choice:

- Raw webhook payloads.
- Provider-specific event JSON.
- Replay/debug storage.
- Time-series metrics.

Also, avoid saying logs only. MongoDB can do much more, but for this assessment, raw event capture is the cleanest justification.

### 21. MongoDB capped collections

Previous fact-check point: capped collections are not immutable audit storage.

Coverage verdict: **Partly covered, my previous wording was overstated, your intent is valid but wording needs precision**.

Your journal says:

> MongoDB has capped collections that forbid all updates on the collection. Even the root account cannot modify the data without dropping and repopulating data, so storing audit data in MongoDB has this advantage too.

Your intended point, clarified later, is:

> This is not full-proof protection. It is a storage-level guardrail beyond permissions. Even with broad permission, delete or some update paths return errors.

That is a valid defense-in-depth argument.

But the original sentence is still too strong:

- It says "forbid all updates", but MongoDB docs discuss updates on capped collections.
- Size-changing updates fail, but not every update is categorically forbidden.
- Older docs explicitly say individual deletes are not allowed; current docs emphasize restrictions and rollover behavior.
- Root or admin can still drop/recreate the collection.
- Capped collections overwrite old documents when full, which is bad for compliance retention.

Better final wording:

> Capped collections can provide a storage-level guardrail for short-lived append-style logs: individual document deletion and size-changing updates are restricted, so accidental mutation is harder even if permissions are too broad. This is defense-in-depth, not immutable storage. Because capped collections are fixed-size circular buffers that overwrite old records, they are not suitable as the sole compliance audit trail.

### 22. MongoDB HA

Previous fact-check point: broad RDBMS comparison was too sweeping.

Coverage verdict: **Partly covered, add caveat**.

Your journal says:

> MongoDB has a built-in HA solution, which most RDBMSs lack...

The MongoDB part is right: replica sets are a native standard mechanism with elections. The broad "most RDBMSs" claim is risky.

Better final wording:

> MongoDB replica sets make replication and automatic failover part of the standard deployment model. PostgreSQL core provides replication primitives but relies on external HA tooling or managed services for failure detection, election, fencing, and routing.

### 23. MongoDB time-series and clustered collections

Previous fact-check point: mention time-series constraints.

Coverage verdict: **Already covered at high level, add caveat**.

Your journal says:

> The latest MongoDB has time series collections and clustered collections, so if we have data that requires these features, we can consider using MongoDB.

This is fine. Add only if final answer needs depth:

- Time-series collections restrict updates.
- Good for measurements/events with time and metadata fields.
- Do not use them as generic mutable documents.

### 24. Neo4j graph fit

Previous fact-check point: Neo4j should be derived, not authoritative.

Coverage verdict: **Partly covered**.

Your journal says:

> Neo4j needs some understanding of graph theory, which I lack a bit. But the core concept is still the same: the best tool for the job.

and:

> the best use for it is... graph problems such as relationship mapping or fraud detection.

Correct. Missing final-architecture caveat:

> Neo4j is a derived graph read model for fraud/AML/KYC traversal. PostgreSQL remains the authoritative ledger.

Also add supernode and CDC lag caveats if writing a senior answer.

### 25. Observability metrics

Previous fact-check point: add specific metrics and SLO framing.

Coverage verdict: **Already covered at high level, add concrete metric names**.

Your journal says:

> For the monitoring aspect, we must approach it from 2 aspects: technical and business.

and:

> CPU, memory, I/O, internal logs, locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs.

This is a solid high-level outline. It just needs concrete names and business SLIs:

- `pg_stat_statements` latency.
- `pg_stat_database_xact_commit` throughput.
- `pg_stat_replication` lag.
- `pg_locks` waiters.
- `pg_stat_database_deadlocks`.
- Settlement lag.
- Reconciliation mismatch count and amount.

### 26. ADR and microservices

Previous fact-check point: use ADRs, consistency choices, data contracts.

Coverage verdict: **Partly covered, intentionally deferred**.

Your journal says:

> task requires some more thought about standards and the microservices aspect so I need to cover them too.

So it was not missing from the thought process; it was a TODO.

Final answer should add:

- ADR template: context, decision, consequences.
- Strong consistency for ledger posting.
- Eventual consistency for read models and Neo4j/MongoDB projections.
- Data contracts and schema compatibility.
- Outbox pattern for reliable events.

### 27. Flyway and Liquibase

Previous fact-check point: migration tooling should not be ad hoc only.

Coverage verdict: **Already covered as a knowledge gap**.

Your journal says:

> About Flyway and Liquibase, I have no idea, so my approach will be ad hoc scripts first, then have AI do some search...

This is honest and appropriate for a journal. In the final deliverable, avoid saying the production approach is ad hoc. Say:

> I would package these scripts as ordered Flyway or Liquibase migrations after validating the raw SQL.

## Corrected meta-assessment of your thought process

Your thought process is stronger than my first fact-check implied.

### What you already did well

- You separated assumptions from facts.
- You identified lack of DDL as a blocker.
- You recognized aggregate queries can be slow even with small result sets.
- You proposed pre-aggregation before over-indexing.
- You knew customer-facing indexes and reporting indexes are different.
- You preferred partitioning for the monthly query.
- You knew PostgreSQL MVCC changes the SQL Server mental model.
- You planned to validate with data and testing.
- You understood expand-contract deployment at a high level.
- You explicitly flagged business assumptions around `settlement_batch_id`.
- You framed MongoDB and Neo4j around tool-fit, not trend.
- You separated technical and business observability.

### What actually needs correction

- Capped collection immutability wording.
- Index-only scan mechanism.
- Clustered index wording.
- Settlement timestamp semantics.
- Conditional `settlement_batch_id` domain rule.
- Currency grouping must be backed by schema enforcement.

### What only needs more depth, not correction

- Query plans and `EXPLAIN` validation.
- Materialized rollups.
- Partitioning caveats.
- Double-entry ledger schema.
- MongoDB vs Postgres JSONB trade-off.
- Neo4j operational caveats.
- Observability metric names and SLO thresholds.
- ADR and microservice data contracts.

## Recommended update to the previous fact-check file

If keeping `00-journal-fact-check-deep-dive.md`, adjust the tone from "wrong" to these categories:

- **Already identified in journal**: pre-aggregation, wallet index mismatch, partitioning, need for testing, zero-downtime phases, observability categories.
- **Precision correction**: MVCC/index-only scan, clustered index, capped collection wording.
- **Domain caveat**: `created_at` vs `settled_at`, `settlement_batch_id NOT NULL`, currency grouping.
- **Research TODO**: double-entry ledger, Neo4j graph modeling, Flyway/Liquibase.
