# Task 5 - Observability: Grafana dashboard and alerts

> **Authorship.** This document is **AI-composed**. The candidate's own reasoning is the
> first-impression observability note in [`00-journal.md` section 1.2](../00-journal.md) (the
> technical-vs-business split and the metric list) and the T10 plan to turn the balance
> reconciliation into an alert; the journal's [section 6](../00-journal.md) records this expansion,
> also AI-composed. From that reasoning the AI built the framing below: the two-layer (integrity vs
> technical) dashboard, the `balance_audit_drift` view (the T10 rule) as the headline integrity
> alert, settlement lag read off the `PENDING -> SETTLED` state machine, the design-specific signals
> (partition runway, slot-retained WAL), the "integrity is a hard invariant, not a percentile SLO"
> position, and the SLI/SLO list and alert table. This is the same separation as Task 2: the
> candidate's reasoning in the journal, the extracted write-up marked AI-authored here. PostgreSQL
> specifics (exporter metric names, catalog views, wraparound) are named by intent and source
> (`postgres_exporter`, `node_exporter`, `pg_stat_statements`, the PG docs), not asserted from
> memory, consistent with how the candidate flagged his PG gaps throughout. The candidate is, by
> his own account, very familiar with Grafana, so the monitoring philosophy carries over from his
> SQL Server experience.

The write-up below is in the first person for readability, but per the authorship note above it is
AI-composed from the candidate's section 1.2 reasoning, not the candidate's own prose.

The monitoring philosophy: watch the engine, but watch the business correctness harder, baseline
before you set a number, and make every page actionable. Where the signal is PostgreSQL-specific
(exact exporter metric names, the catalog views, wraparound), name what is wanted and where it
would be read (`postgres_exporter`, `node_exporter`, `pg_stat_statements`, and the PG docs) rather
than assume the metric names. The collection stack assumed is the standard one: exporters into
Prometheus, Grafana on top.

I split the dashboard into two layers, the same split I made in the journal: a **business /
integrity** layer (is the ledger correct and is money moving?) and a **technical** layer (is
the engine healthy?). For a payments ledger the integrity layer is the one I care about most,
and the good news is that most of it falls straight out of the design we already built, so I
am not inventing new instrumentation, I am putting a panel on guarantees the schema already
exposes.

PostgreSQL is the system of record. MongoDB (Layer 3 audit) and Neo4j (the fraud graph) are
derived, rebuildable stores, so they get one shared signal each (replica-set health for Mongo,
projection staleness for Neo4j) and nothing more. This dashboard is about the ledger.

## Dashboard layout

- **Row 0 - Integrity (the fintech row).** Balance drift, system-wide zero-sum, reversal rate.
- **Row 1 - Settlement (business throughput).** Pending backlog and oldest pending age, postings/sec.
- **Row 2 - Latency.** Posting commit latency and settlement-report latency, both as percentiles.
- **Row 3 - Throughput & errors.** Commits/sec, rollbacks/sec and the rollback ratio, deadlocks.
- **Row 4 - Locks & long transactions.** Blocked sessions, longest lock wait, idle-in-transaction age.
- **Row 5 - Replication.** Replica replay lag (time and bytes), and replication-slot retained WAL.
- **Row 6 - Capacity.** Disk and WAL free, connections vs max, cache hit ratio, autovacuum / dead
  tuples, and transaction-ID wraparound age.

## SLIs, SLOs, and why each one

I treat integrity as a **hard invariant**, not a percentile target. "99.9% of balances
reconcile" is the wrong sentence for a ledger; the right number is zero discrepancies, and any
nonzero is an incident. Everything else (latency, freshness, availability) is a normal SLO with
a target I would tune against an observed baseline.

### Integrity (hard invariant, no error budget)

- **Balance drift:** number of rows in the `balance_audit_drift` view (cached `wallets.balance`
  vs `SUM(entries)`). This is the T10 reconciliation rule from the design made operational. A
  scheduled job reads the view and exports the row count. **Target: 0.** Any nonzero row means
  we are showing a balance that the ledger does not back, which is the worst class of bug in
  this domain.
- **System-wide zero-sum:** per currency, `SUM(amount WHERE CREDIT) - SUM(amount WHERE DEBIT)`
  across the whole ledger. **Target: 0 per currency.** The per-transaction trigger already
  guarantees this on the write path; this panel is the global cross-check that nothing (a bad
  backfill, a manual fix, a bug) broke it after the fact.

### Settlement lag (business freshness)

In our model a transaction is born `PENDING` and flips to `SETTLED`. "Settlement lag" is
therefore the age of the oldest still-`PENDING` transaction and the size of the pending backlog,
both trivially queryable off `transactions.status` + `created_at`.

- **Oldest pending age** and **pending backlog count.** SLO (starting point): 99% of
  transactions reach `SETTLED` within 15 minutes, oldest pending stays under that band. The
  number is a placeholder until I see the real settlement cadence; the point is that a climbing
  oldest-pending age means customers' money is stuck in flight, and that is a business outage
  even while the database looks perfectly healthy.

### Latency

- **Posting commit latency** (the hot OLTP write path: post a balanced transaction). Percentiles
  p50/p95/p99, from app-side timing around `BEGIN..COMMIT` and cross-checked against
  `pg_stat_statements` for the posting statements. SLO (starting point): **p99 < 150 ms.** This
  is the path a user waits on.
- **Settlement-report latency** (the Task 2 query). SLO: **p99 < 2 s for the current month**
  (the live join); cold months served by the rollup should be tens of milliseconds. Kept on a
  separate panel because it is reporting, not the customer-facing write path, so it gets a
  gentler threshold and a ticket, not a page.

### Throughput

- **Commits/sec** (`xact_commit` rate) and **entries inserted/sec**: the headline business
  throughput, and the baseline that makes every other "spike vs normal" alert meaningful.
- **Rollbacks/sec and rollback ratio** (`xact_rollback`). Some rollbacks are legitimate business
  rejections (insufficient funds, a failed zero-sum check). A *step change* in the ratio is the
  signal: it usually means contention, a deploy gone wrong, or an app bug hammering the ledger.

### Replication lag

Replicas carry the reporting/read traffic, so their lag is a freshness signal, not just an HA one.

- **Replica replay lag** in time and bytes (`pg_wal_lsn_diff` between the primary LSN and the
  replica replay LSN; I would confirm the exact exporter fields). SLO: **replay lag < 10 s**, so
  a report read off a replica is acceptably fresh.
- **Replication-slot retained WAL.** This is the PostgreSQL footgun I most want on the wall: a
  stalled or dropped replica leaves its slot pinning WAL on the primary, `pg_wal` grows without
  bound, and the **primary's disk fills and the whole ledger stops writing**. So this is a
  replication metric that is really a capacity time-bomb, and it pages.

### Lock contention

The ledger posts concurrently, and the contention points are the shared rows: the hot
`wallets` balance update and the deferred per-currency zero-sum constraint trigger.

- **Blocked sessions** and **longest lock wait** (from `pg_locks` joined to `pg_stat_activity`).
- **Deadlocks/sec** (`pg_stat_database.deadlocks`): a low steady rate is tolerable, a rising
  rate means the concurrency design needs attention.
- **Idle-in-transaction and longest-transaction age.** A long open transaction holds locks and,
  worse, pins the vacuum horizon so dead tuples cannot be cleaned, which feeds bloat and
  wraparound. I alert on transaction age, not just lock waits.
- This is also the panel I watch live during a Task 3 expand-contract migration: those steps
  take brief `ACCESS EXCLUSIVE` locks under a short `lock_timeout`, and this row tells me
  immediately if one is queuing behind a long statement.

### Capacity

- **Disk and WAL free** (data volume and `pg_wal` volume), with growth rate and a projected
  days-to-full. Entries grow about 2M rows/month; partitioning keeps each month manageable and
  lets us `DETACH`/archive old ones, but disk is still the hard wall.
- **Partition runway (specific to this design).** Two checks the monthly partitioning makes
  necessary: the **next month's `entries` partition must exist** before the month rolls over, and
  the **DEFAULT partition row count must stay 0**. If next month's partition is missing, inserts
  dated into it fail or fall into DEFAULT; rows landing in DEFAULT mean a partition is missing
  and pruning/perf silently degrades. Both are cheap to query and both page.
- **Connections vs `max_connections`.** Saturation: once we run out, new connections are refused,
  which is an outage. Alert at 80%; the real fix is a pooler (PgBouncer).
- **Cache hit ratio** (`blks_hit / (blks_hit + blks_read)`). A sustained drop means the working
  set outgrew RAM and latency is about to follow.
- **Autovacuum health: dead tuples and last-autovacuum age** on the churny tables (`wallets`,
  updated on every balance change, and the `transactions` header). `entries` is append-only so
  it bloats little, but the header and balance tables do.
- **Transaction-ID / MultiXact wraparound age** (`age(datfrozenxid)`). The classic PostgreSQL
  time-bomb: if autovacuum falls behind freezing, the database forces itself read-only to protect
  the data. This must alert *well* before the 2^31 wall, not near it.

## Alerts

Thresholds below are **starting points pending a baseline**. I want to be honest that a number
picked before you have seen normal traffic is a guess; the durable part of each alert is the
**consequence in the "why" column**, not the digit, and I would tighten or loosen the digit once
Prometheus has a week or two of history. Severity is **PAGE** (wake someone now) vs **TICKET**
(handle in business hours).

| Signal | Threshold (starting point) | Severity | Why (the consequence) |
|---|---|---|---|
| `balance_audit_drift` rows | any > 0 | PAGE | Cached balance no longer matches the ledger. Correctness incident, money shown wrong. |
| System-wide per-currency sum of entries | any != 0 | PAGE | The double-entry invariant itself is broken. |
| Oldest `PENDING` transaction age | > 15 min, paging if it keeps climbing | PAGE | Settlement pipeline stalled; customer funds stuck in flight. |
| Pending backlog count | sustained above normal band | TICKET | Settlement throughput not keeping up with intake. |
| Reversal rate | step change vs baseline | TICKET (PAGE if large) | Business anomaly: a bad batch or upstream defect. |
| Next-month `entries` partition missing | absent within N days of month end | PAGE | Next month's inserts will fail or misroute. |
| Rows in `entries` DEFAULT partition | any > 0 | PAGE | A month partition is missing; data misrouted, pruning/perf degraded. |
| Posting commit latency p99 | > 150 ms for 5 min | PAGE | User-facing write path degraded (SLO burn). |
| Settlement-report p99 | > 2 s sustained | TICKET | Reporting degraded; not the customer write path. |
| Rollback ratio | step change vs baseline | TICKET (PAGE on a sharp jump) | Failed postings: contention, deploy regression, or app bug. |
| Deadlocks/sec | rising above baseline | TICKET | Concurrency design issue on hot wallets. |
| Blocked sessions / longest lock wait | wait > 30 s, or blocked count spikes | PAGE in business/peak hours | Contention stalling postings; the live signal during a migration window. |
| Idle-in-transaction / longest xact age | > 5 min | TICKET (PAGE if > 30 min) | Holds locks and pins the vacuum horizon, feeding bloat and wraparound. |
| Replica replay lag (time) | > 10 s | TICKET (PAGE if > 60 s or growing unbounded) | Stale reporting reads; failover risk. |
| Replication-slot retained WAL / `pg_wal` free | retained WAL high, or `pg_wal` free < 20% | PAGE | Stalled slot pins WAL, primary disk fills, full write outage. |
| Connections vs `max_connections` | > 80% | TICKET (PAGE at ~95%) | Saturation; refused connections are an outage. Needs a pooler. |
| Disk free / projected days-to-full | < 20% free or < 14 days projected | TICKET (PAGE < 10% or < 3 days) | The ledger cannot write when the disk is full. |
| Wraparound age `age(datfrozenxid)` | beyond a safe ceiling well below 2^31 | PAGE | Autovacuum behind on freezing; risk of a forced read-only shutdown. |
| Cache hit ratio | sustained below baseline (~99%) | TICKET | Working set outgrew RAM; latency regression incoming. |
| Dead tuples / last-autovacuum age (`wallets`, `transactions`) | dead-tuple ratio high or autovacuum not running | TICKET | Bloat from balance-update churn, slow scans. |
| CPU / IO wait / run queue (node_exporter) | high utilisation **and** saturation | TICKET (PAGE if pegged) | Resource exhaustion on the primary. |
| MongoDB / Neo4j: replica-set unhealthy or projection staleness | secondary down, or graph lag beyond its rebuild window | TICKET | Derived stores; rebuildable from the ledger, so they never page like the ledger does. |

## Alerting philosophy (why it is shaped this way)

- **Page on integrity and on the customer-facing write path; ticket on capacity trends.** A
  balance discrepancy or a stalled settlement queue is someone-wakes-up. A disk slowly trending
  toward full, or cache hit ratio drifting, is a ticket with days of runway. Mixing those two
  severities is how you train people to ignore the pager.
- **Baseline first, then alert on deviation.** Most of the "spike vs normal" alerts above are
  deliberately written against a baseline rather than an absolute number, because on a fresh
  system I do not yet know what normal commits/sec or rollback ratio looks like.
- **Every page must be actionable.** If there is nothing the on-call can do about it at 3am, it
  is a dashboard panel, not an alert.
- **Catch the slow-moving killers early.** Wraparound age, slot-retained WAL, and disk
  days-to-full all destroy you with plenty of warning if you watch them, and take you completely
  down if you do not. They get generous lead-time thresholds on purpose.
