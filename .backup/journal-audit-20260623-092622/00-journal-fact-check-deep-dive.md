# 00 Journal fact-check deep dive

Source reviewed: `2-assessment-report/00-journal.md`

Goal: identify thoughts that are wrong, risky, or too imprecise for the assessment, then give a study path to correct them.

## Research used

Local research:

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
- `0-research/neo4j-graph-fintech/08-modeling-operations-tradeoffs.md`
- `/home/coder/research/postgresql/03-storage-engine.md`
- `/home/coder/research/postgresql/04-mvcc-transactions-isolation.md`
- `/home/coder/research/postgresql/07-indexing.md`
- `/home/coder/research/postgresql/10-ha-failover-pooling.md`
- `/home/coder/research/postgresql/11-partitioning-sharding-scaling.md`

Extra official docs checked for MongoDB capped collections and replica sets:

- MongoDB Manual, Capped Collections: `https://www.mongodb.com/docs/manual/core/capped-collections/`
- MongoDB Manual, Replication: `https://www.mongodb.com/docs/manual/replication/`
- MongoDB Manual, Time Series Collections: `https://www.mongodb.com/docs/manual/core/timeseries-collections/`

## TL;DR corrections

| Severity | Thought to revisit | Correction |
|---|---|---|
| Partly valid but overstated | Capped collections add a storage-level guard against some accidental mutations | They can be better than permissions alone for preventing some accidental deletes or size-changing updates, depending on MongoDB version and operation. But they are fixed-size circular buffers that overwrite old documents, allow or at least document updates, cannot be written in transactions, cannot be sharded, and are not compliance-grade immutable audit storage. |
| Wrong or too broad | `settlement_batch_id` can safely be NOT NULL for all transactions | In a real payment lifecycle, pending, failed, or processing transactions usually have no settlement batch yet. Either make it nullable with a conditional constraint for settled rows, or place it on a settled/settlement table. |
| Misleading | PostgreSQL index-only scan works if pages are clean via fillfactor and vacuum | The direct requirement is the visibility map all-visible bit, set by VACUUM and cleared by DML. Fillfactor helps HOT updates and bloat control, but does not itself make a page all-visible. |
| Misleading | PostgreSQL index scans fetch the heap to get the latest value | They fetch the heap to check MVCC visibility. Under MVCC, the visible version is snapshot-dependent and may not be the latest committed version. |
| Needs nuance | PostgreSQL has no clustered index, so clustered-index strategy is impossible | PostgreSQL has no SQL Server style automatically maintained clustered index. It does have a `CLUSTER` command that physically rewrites a table by an index once, but later writes do not preserve that order. All normal PostgreSQL indexes are secondary. |
| Needs nuance | `IX(wallet_id, created_at)` is a candidate for the all-wallet monthly settlement query | That index is good for one-wallet history lookups, not for scanning all wallets in a month. For the assessment query, lead with `created_at`, use a partial index on settled rows, use monthly partitioning, or use a rollup. |
| Needs nuance | `Partition(created_at) & IX(wallet_id)` can skip sort entirely | It can only skip sort if the chosen scan returns rows ordered by all grouping keys, for example `(wallet_id, currency)`, and the planner actually chooses GroupAggregate. It is not guaranteed and must be proven with `EXPLAIN (ANALYZE, BUFFERS)`. |
| Risky | Dropping `currency` from `GROUP BY` because currency belongs to wallet | Amounts across currencies cannot be summed. You may group by wallet only if the schema enforces one currency per wallet and you join or derive currency from wallet. Otherwise keep `currency` in the group key. |
| Important missing nuance | Settlement report uses `created_at` | Real settlement reporting often uses `settled_at` or `settlement_batch` closing time, not transaction creation time. If the assessment query uses `created_at`, call it out as the given query shape, not necessarily the ideal domain model. |
| Needs nuance | MongoDB has built-in HA, most RDBMSs miss this | MongoDB replica sets do provide built-in replication and automatic elections. PostgreSQL core ships replication primitives but no built-in failover manager. The broad claim about most RDBMSs is too sweeping. |
| Needs nuance | Neo4j is good for relationship/fraud detection | Correct, but only as a derived read model. The authoritative ledger stays in PostgreSQL. Watch for supernodes, CDC lag, Enterprise feature cost, and data privacy controls. |

## 1. Row-count inference and performance cause

### Journal thought

> The transaction table has 50 million rows and receives an additional 2 million rows per month. So we have about 24 months of data in the table.

### Verdict

Mostly fine, but imprecise.

If the table started empty and grew linearly at exactly 2 million rows/month, 50 million rows implies about 25 months, not 24. In practice, this is close enough because production tables rarely start from zero and monthly volume can vary.

### More important correction

Do not assume the slow query is only caused by scanning 50 million rows. The slow path could be any combination of:

- Full table scan due to missing or unusable index.
- Scanning one month but still aggregating 2 million rows.
- Hash aggregate or sort spilling to disk because `work_mem` is too low.
- Table or index bloat from MVCC and weak vacuum.
- Stale statistics causing a bad plan.
- Low cache hit ratio or random I/O from heap fetches.

### Dive deeper

Run this validation story in the final answer:

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

- `Seq Scan` vs `Index Scan` vs `Index Only Scan`.
- Partition pruning to only the target month.
- `HashAggregate` memory usage and spills.
- `Sort Method: external merge` or temporary file usage.
- Buffer reads before and after.

Study: `0-research/vp-assessment-dba/05-postgres-performance.md` and `/home/coder/research/postgresql/14-performance-observability.md`.

## 2. PostgreSQL MVCC and clustered indexes

### Journal thought

> There are no clustered indexes in PostgreSQL either. So we cannot use a clustered index strategy here.

### Verdict

Mostly true, but phrase it more precisely.

PostgreSQL does not have SQL Server style clustered indexes where the table is continuously maintained in index key order. PostgreSQL indexes are secondary structures pointing to heap tuple IDs. However, PostgreSQL does have a `CLUSTER` command that rewrites a table physically according to an index. That order is not maintained after later inserts and updates.

### Better wording

Use this in the assessment:

> PostgreSQL has no automatically maintained clustered index like SQL Server. It can physically rewrite a table with `CLUSTER`, but that is a one-time reordering operation. For this workload, prefer declarative partitioning, BRIN or B-tree indexes, vacuum discipline, and rollups instead of relying on heap order.

### Why it matters

If you say "PostgreSQL has no cluster index" without mentioning `CLUSTER`, a reviewer may see it as incomplete PostgreSQL knowledge. The correct contrast is not "no clustering exists", it is "no clustered-index storage engine like SQL Server".

Study: `/home/coder/research/postgresql/07-indexing.md` and `/home/coder/research/postgresql/03-storage-engine.md`.

## 3. Index scans, visibility, fillfactor, and index-only scans

### Journal thought

> PostgreSQL index scans must fetch the data page to ensure it has the latest data value. This can be mitigated by ensuring the page is clean via fillfactor and the vacuum process. If we can ensure the page is clean, PostgreSQL can use an index-only scan.

### Verdict

The direction is right, but the mechanism is wrong enough to fix.

### Correct mechanism

PostgreSQL indexes are not MVCC-aware. A normal index tuple points to a heap tuple version. The executor often visits the heap to check whether that tuple version is visible to the current snapshot. It is not simply looking for the "latest" value, because under MVCC a query might need an older visible row version.

Index-only scan is possible only when:

1. The index access method supports index-only scans, B-tree does.
2. Every referenced column is available in the index key or `INCLUDE` payload.
3. The heap page is marked all-visible in the visibility map.

VACUUM sets all-visible bits. Any insert, update, or delete clears them for the affected page. Fillfactor is useful, but for a different reason: it reserves space for HOT updates, reducing index churn and bloat. It does not directly mark a page all-visible.

### Better wording

> PostgreSQL may still visit the heap during an index scan to verify MVCC visibility. A covering index can become an index-only scan when the visibility map says the heap page is all-visible. VACUUM is what maintains those bits; fillfactor mainly improves HOT-update chances and reduces bloat.

### Dive deeper

For old, read-only monthly partitions, run:

```sql
VACUUM (ANALYZE) transactions_2026_05;
EXPLAIN (ANALYZE, BUFFERS)
SELECT wallet_id, currency, SUM(amount)
FROM transactions_2026_05
WHERE status = 'SETTLED'
GROUP BY wallet_id, currency;
```

Then compare heap fetches before and after vacuum.

Study:

- `/home/coder/research/postgresql/03-storage-engine.md`, Visibility Map and HOT sections.
- `/home/coder/research/postgresql/07-indexing.md`, Index-only scans section.
- `0-research/vp-assessment-dba/05-postgres-performance.md`, Covering indexes and index-only scans.

## 4. Settlement-query index strategy

### Journal thought

> Usually, index strategy follows exact, sort, scan priority. Status is mostly settled, so indexing status has limited benefit. Candidate indexes include `IX(wallet_id, created_at) INCLUDE (...)`, `IX(created_at) INCLUDE (...)`, and partition by `created_at` plus `IX(wallet_id)`.

### Verdict

Good instincts, but some recommendations need correction.

### What is correct

- Low-cardinality `status` alone is usually a weak index.
- A monthly range predicate on `created_at` is central.
- Pre-aggregation is often the real fix for repeated reporting.
- Partitioning by `created_at` is strong for this query shape.

### What is risky

`IX(wallet_id, created_at)` is not a good primary index for the all-wallet monthly settlement query. It is excellent for a customer dashboard that asks for one wallet over a date range:

```sql
WHERE wallet_id = :wallet_id
  AND created_at >= :start
  AND created_at < :end
```

But the assessment query has no `wallet_id` predicate. With many wallets, an index led by `wallet_id` is not naturally selective for "all rows in this month".

### Better candidate indexes

For an unpartitioned table:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

For a partitioned table, use a parent index so each partition gets a local index:

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

If a monthly partition is already selected and you want sorted input for grouping, test this variant on the partition:

```sql
CREATE INDEX idx_tx_settled_group_cover
ON transactions_2026_06 (wallet_id, currency)
INCLUDE (amount)
WHERE status = 'SETTLED';
```

But do not claim it will always be faster. For 2 million rows, a sequential scan on one partition plus `HashAggregate` may beat an ordered index scan. The correct answer is to propose candidates and validate with `EXPLAIN (ANALYZE, BUFFERS)`.

### Better final answer shape

1. Partition by month on `created_at` or `settled_at`, depending on report semantics.
2. Add a partial covering index for `status = 'SETTLED'` and the time range.
3. Add a BRIN index on `created_at` if the table is append-heavy and huge.
4. Use a materialized view or summary table for repeated monthly statements.
5. Validate with query plans, buffer reads, aggregate memory, and write overhead.

Study: `0-research/vp-assessment-dba/05-postgres-performance.md` and `/home/coder/research/postgresql/07-indexing.md`.

## 5. Partitioning vs live/archive physical split

### Journal thought

> In SQL Server, split hot/live transactions and archived transactions into two physical tables. Apply the same insight to PostgreSQL.

### Verdict

The idea is useful, but in PostgreSQL the first-choice shape should be declarative partitioning, not manual live/archive table splits.

### Correction

Use monthly range partitions as the native hot/cold boundary:

- Current and previous month partitions are hot.
- Older partitions are read-mostly, vacuumed, and become good index-only-scan candidates.
- Retention or archiving can use `DETACH PARTITION`, `DROP TABLE`, `COPY`, or backup workflows.
- Each partition has smaller local indexes.

Manual archive tables are still possible, but they create query routing and consistency issues that declarative partitions already solve.

### Caveats to mention

- Unique constraints on partitioned tables must include the partition key because PostgreSQL has no global indexes.
- Too many partitions hurt planning time and per-session memory.
- Queries without the partition key cannot prune partitions and may be slower than a normal table.
- Autovacuum analyzes leaf partitions but parent statistics may need manual `ANALYZE`.

Study: `/home/coder/research/postgresql/11-partitioning-sharding-scaling.md`.

## 6. Currency, wallet design, and `GROUP BY currency`

### Journal thought

> If currency is an attribute of wallet, we should not add it to `GROUP BY`, instead use aggregate on SELECT because for 1 wallet, currency is the same. If multiple currencies in a wallet, the key is composite.

### Verdict

The design instinct is good, but the query advice is risky.

### Correct model

A wallet should usually be single-currency. A customer account can own many wallets, one per currency. The schema should enforce this:

```sql
CREATE TABLE wallets (
  id UUID PRIMARY KEY,
  account_id UUID NOT NULL,
  currency CHAR(3) NOT NULL
);

ALTER TABLE wallets
  ADD CONSTRAINT wallets_id_currency_uq UNIQUE (id, currency);

ALTER TABLE ledger_entries
  ADD CONSTRAINT ledger_entries_wallet_currency_fk
  FOREIGN KEY (wallet_id, currency)
  REFERENCES wallets (id, currency);
```

### Query correction

Do not sum money across currencies. If the transaction table stores `currency`, grouping by `(wallet_id, currency)` is safe and explicit:

```sql
GROUP BY wallet_id, currency
```

If the schema proves `wallet_id -> currency`, you can group by `wallet_id` and join to `wallets` to display currency:

```sql
SELECT t.wallet_id, w.currency, SUM(t.amount)
FROM transactions t
JOIN wallets w ON w.id = t.wallet_id
WHERE t.status = 'SETTLED'
  AND t.created_at >= :month_start
  AND t.created_at < :month_end
GROUP BY t.wallet_id, w.currency;
```

Using `MIN(currency)` or `MAX(currency)` is acceptable only as a defensive assertion if the schema already guarantees one currency per wallet. Without that guarantee, it can hide data corruption.

Study: `0-research/vp-assessment-dba/01-fintech-payments-domain.md`, `0-research/vp-assessment-dba/02-double-entry-ledger-money.md`, and `0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`.

## 7. `created_at` vs `settled_at` for settlement reports

### Journal thought

> The point of the query is to calculate the statement of all wallets that have been settled in a month. The query filters by `created_at`.

### Verdict

Potential domain mismatch.

### Correction

In payments, transaction creation and settlement are different lifecycle moments:

- `created_at`: when the internal transaction was created.
- `authorized_at`: when an external authorization was approved.
- `captured_at`: when the merchant/platform captured the payment.
- `settled_at`: when external funds settlement is confirmed.
- `settlement_batch_id`: the external or internal batch used for reconciliation.

If the business question is "transactions created in June that are settled", `created_at` is correct.

If the business question is "June settlement statement", use `settled_at` or join through `settlement_batches.closed_at`.

### Better final answer shape

Say this explicitly:

> The given query filters by `created_at`, so I optimize that query shape. In the domain model I would also store `settled_at` and `settlement_batch_id`, because reconciliation and settlement reports often group by settlement date or batch rather than creation date.

Study: `0-research/vp-assessment-dba/01-fintech-payments-domain.md`.

## 8. `settlement_batch_id NOT NULL` and zero-downtime migration

### Journal thought

> The task introduces a new NOT NULL column, `settlement_batch_id`, and it needs to be updated live. The column name is just an example, so I can safely skip the business aspect.

### Verdict

Good for deployment mechanics, risky for domain correctness.

### Why risky

If `transactions` contains pending, processing, failed, and reversed rows, many rows legitimately do not have a settlement batch. Making `settlement_batch_id` NOT NULL globally can force fake values, which corrupts the model.

### Better schema constraint

If only settled transactions require a batch:

```sql
ALTER TABLE transactions
  ADD CONSTRAINT tx_settled_requires_batch
  CHECK (status <> 'SETTLED' OR settlement_batch_id IS NOT NULL) NOT VALID;
```

Then validate later:

```sql
ALTER TABLE transactions VALIDATE CONSTRAINT tx_settled_requires_batch;
```

If non-settled transactions must not have a batch yet:

```sql
ALTER TABLE transactions
  ADD CONSTRAINT tx_batch_matches_settlement_state
  CHECK (
    (status = 'SETTLED' AND settlement_batch_id IS NOT NULL)
    OR
    (status <> 'SETTLED' AND settlement_batch_id IS NULL)
  ) NOT VALID;
```

That second version may be too strict if reversed transactions preserve the original settlement reference, so confirm the lifecycle first.

### Deployment mechanics that are correct

Your 3-stage approach is right:

1. Expand: add nullable column with no default.
2. Deploy app: dual-write new rows.
3. Backfill old rows in batches.
4. Add `NOT VALID` constraint, validate, then promote.
5. Contract old code paths later.

### PostgreSQL details to include

- `ALTER TABLE` usually takes `ACCESS EXCLUSIVE`; keep strong-lock operations brief.
- Adding a nullable column with no default is fast.
- Volatile defaults can rewrite the table.
- `SET NOT NULL` scans the table unless a validated `CHECK (col IS NOT NULL)` already proves it.
- `CREATE INDEX CONCURRENTLY` cannot run inside a transaction and can leave an invalid index after failure.
- Batched backfill avoids long transactions, lock pile-ups, and dead tuple bloat.

Study: `0-research/vp-assessment-dba/06-postgres-migration-concurrency.md`.

## 9. Double-entry ledger vs `transactions` table

### Journal thought

> The goal is to expand the entry point at the transactions table and deliver a full schema. I need to understand double-entry ledger.

### Verdict

Correct, but the final design must avoid treating `transactions` as the ledger.

### Correction

A transaction row is the business event. Ledger entries are the accounting consequences. One transaction produces two or more ledger entries. The invariant is per transaction or per journal entry:

```text
SUM(signed ledger entries) = 0
```

The schema should have at least:

- `accounts` or `wallets`: named balance containers.
- `ledger_transactions`: event header.
- `ledger_entries`: immutable lines, two or more per event.
- `idempotency_keys`: retry safety.
- `audit_trail`: non-monetary state changes.

### Pending state warning

A simple `status` column is not always enough for money state. Payment ledgers often represent pending money with structural accounts, for example:

- `settled`
- `pending_credit`
- `pending_debit`
- `suspense`

This makes available balance and reconciliation explicit instead of hiding it in status logic.

Study: `0-research/double-entry-ledger/02-ledger-vs-transactions.md`, `0-research/double-entry-ledger/03-schema-design.md`, and `0-research/double-entry-ledger/05-integrity-guarantees.md`.

## 10. MongoDB capped collections and audit storage

### Journal thought

> MongoDB has capped collection that forbids all updates on the collection, even root account cannot modify the data unless dropping and repopulating data, so storing audit in MongoDB has this advantage too.

### Verdict

Partly valid, but the wording must be narrower.

Your core point is fair: a capped collection can add a storage-level guardrail against some accidental mutation paths. That is stronger than relying only on permissions, because broad permissions are easy to misconfigure.

### Correction

Do not phrase it as "capped collections forbid all updates" or "even root cannot modify the data".

The more accurate claim is:

> Capped collections can reduce accidental tampering because MongoDB restricts some operations on them. Older MongoDB docs explicitly say you cannot delete individual documents from a capped collection, and size-changing updates fail. This is useful as defense-in-depth beyond permissions, but capped collections are not immutable audit storage because they are fixed-size circular buffers that overwrite old documents when full, updates are still a documented operation, and an admin can still drop or recreate the collection.

Version nuance:

- MongoDB 4.4 docs explicitly state: "You cannot delete documents from a capped collection. To remove all documents from a collection, use `drop()` and recreate the capped collection."
- MongoDB 5.0 docs state that if an update or replacement changes document size, the operation fails.
- MongoDB 6.0 docs still discuss planning indexes if you update documents in a capped collection.
- Current MongoDB docs say to avoid updating data in a capped collection because updates can expand data beyond the allocated space and cause unexpected behavior.

So capped collections are not a full immutable store. They are a limited guardrail.

### Why this matters

For compliance-grade audit storage, the biggest problem is retention: capped collections overwrite old records once they hit their size limit. That makes them unsuitable as the sole audit trail. They may be acceptable for short-lived operational logs, not for legally retained financial audit history.

### Better MongoDB positioning

Use this framing instead:

- Capped collections are useful for fixed-size, insertion-order operational logs or tails where automatic rollover is desired.
- They provide defense-in-depth against some accidental delete or document-growth update paths, which is better than permissions alone.
- They are not tamper-proof: an admin can drop the collection, change operational settings, or write new records until old records roll off.
- They are not retention-safe: old documents are overwritten by design.
- For audit/compliance, prefer PostgreSQL immutable ledger entries, trigger-based `audit_trail` with `REVOKE UPDATE, DELETE`, backups, retention policy, and WORM/object-lock storage if required.

Use MongoDB in the assessment for:

- Raw webhook payload capture.
- Provider-specific event documents with variable schema.
- Replay/debug support where the authoritative money ledger remains in PostgreSQL.
- Time-series metrics or event streams when the data model fits MongoDB time-series collection constraints.

Study: `0-research/vp-assessment-dba/03-compliance-audit-immutability.md` and `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`.

## 11. MongoDB HA, BSON, and time-series nuance

### Journal thought

> MongoDB has a built-in HA solution, which most RDBMSs miss.

### Verdict

Directionally true for MongoDB, too broad for RDBMSs.

### Correction

MongoDB replica sets provide replication and automatic elections. That is a strong operational advantage compared with PostgreSQL core, which ships replication primitives but deliberately leaves failure detection, election, fencing, and client routing to external tools like Patroni, repmgr, pg_auto_failover, pgpool-II, or managed cloud services.

But do not say "most RDBMSs miss". Some RDBMS products and managed services have integrated HA. A safer claim:

> MongoDB replica sets make replication and automatic failover part of the standard deployment model. PostgreSQL core requires assembling HA with external components or using a managed service.

### BSON nuance

BSON is a good reason to choose MongoDB for document-shaped data, especially update-heavy or provider-variable documents. But do not oversell it as universally more efficient than PostgreSQL JSONB. PostgreSQL JSONB may be the better choice when:

- You need one ACID transaction with the ledger.
- You need relational constraints.
- You do not want a second datastore.
- The document is not update-heavy.

Study: `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md` and `/home/coder/research/postgresql/10-ha-failover-pooling.md`.

## 12. Neo4j as graph store

### Journal thought

> Neo4j is best for graph problems such as relationship or fraud detection.

### Verdict

Correct, but add operational caveats.

### Correction

Neo4j is a strong fit for variable-depth relationship questions:

- Fraud rings.
- Shared device/card/phone/email identity clusters.
- Money mule paths.
- AML transaction-path tracing.
- Beneficial ownership and KYC entity resolution.

But in the architecture, it should be a derived read model fed from PostgreSQL and KYC/event data. It must not be the system of record for money or balances.

### Caveats to show seniority

- CDC lag means the graph is eventually consistent.
- Authoritative decisions should confirm against PostgreSQL.
- Supernodes can destroy performance, for example a very high-volume merchant, country, bank, or currency node with hundreds of thousands of relationships.
- Model by query first. Do not turn every low-cardinality attribute into a node.
- Neo4j Enterprise or Aura may be required for HA, online backup, fine-grained access control, and production-grade security.

Study: `0-research/vp-assessment-dba/07-polyglot-mongo-neo4j.md`, `0-research/neo4j-graph-fintech/07-production-case-studies.md`, and `0-research/neo4j-graph-fintech/08-modeling-operations-tradeoffs.md`.

## 13. Observability thoughts

### Journal thought

> Monitor CPU, memory, I/O, WAL logs, locking/waiting, connections, cache hit/miss, index utilization, vacuum, dead tuples, transaction id, query/procedure duration.

### Verdict

Good baseline, but incomplete for the assessment.

### Add these specifics

Technical SLIs and alerts:

- `pg_up` for liveness.
- `pg_stat_database_xact_commit` and rollback rate for throughput and failure rate.
- `pg_stat_statements` for query latency and top slow queries.
- `pg_stat_database_blks_hit / (blks_hit + blks_read)` for cache hit ratio.
- `pg_stat_replication` lag for read replicas and failover risk.
- `pg_locks` and `pg_stat_activity.wait_event` for lock contention.
- Deadlocks via `pg_stat_database_deadlocks`.
- Connections vs `max_connections`.
- Disk growth and table/index bloat.
- Autovacuum lag, dead tuples, freeze age, and transaction ID wraparound risk.
- WAL generation rate and checkpoint pressure.

Business SLIs:

- Settlement lag, created-to-settled latency.
- Reconciliation mismatch count and amount.
- Duplicate idempotency-key attempts.
- Failed or reversed transaction rate.
- Backfill progress and null count during migration.

SLO framing:

- Define SLI, SLO, and alert on error-budget burn, not every metric spike.
- Separate page-now alerts from business-hours capacity alerts.

Study: `0-research/vp-assessment-dba/08-observability-architecture-adr.md`.

## Final recommended changes before submitting the assessment

1. Replace the capped-collection audit claim. It is the clearest incorrect statement.
2. Add the `created_at` vs `settled_at` distinction for settlement reports.
3. Clarify `settlement_batch_id NOT NULL`: global NOT NULL may be wrong if pending rows exist.
4. Rewrite the index section around partitioning, partial covering index, BRIN, and rollups. Treat `wallet_id, created_at` as a customer-dashboard index, not the main all-wallet settlement index.
5. Clarify index-only scan mechanics: visibility map, not just "clean pages".
6. Clarify PostgreSQL clustered-index wording: no SQL Server style clustered indexes, but `CLUSTER` exists.
7. Keep currency in the aggregation unless the schema proves one wallet has exactly one currency.
8. Make Neo4j clearly derived and eventually consistent, never authoritative for money.
9. Add `EXPLAIN (ANALYZE, BUFFERS)` as the validation method for every performance claim.

## Minimal corrected snippets to reuse

### Query optimization snippet

```sql
CREATE INDEX idx_tx_settled_month_cover
ON transactions (created_at)
INCLUDE (wallet_id, currency, amount)
WHERE status = 'SETTLED';
```

### Partitioning snippet

```sql
CREATE TABLE transactions (
  id BIGINT GENERATED ALWAYS AS IDENTITY,
  wallet_id UUID NOT NULL,
  amount NUMERIC(19,4) NOT NULL,
  currency CHAR(3) NOT NULL,
  status TEXT NOT NULL,
  created_at timestamptz NOT NULL,
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

### Fast validation before NOT NULL promotion

```sql
ALTER TABLE transactions
  ADD CONSTRAINT transactions_sbid_not_null
  CHECK (settlement_batch_id IS NOT NULL) NOT VALID;

ALTER TABLE transactions VALIDATE CONSTRAINT transactions_sbid_not_null;
ALTER TABLE transactions ALTER COLUMN settlement_batch_id SET NOT NULL;
```

Use this only if the business rule really says every row must have a batch.
