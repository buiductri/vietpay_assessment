# Task 5: Observability

> Generated: 2026-06-25 | Axis: Observability (Grafana dashboard + alerts) | Primary sources: journal section 1.2 and 6, `docs/observability.md`

This axis reorganizes the existing Task 5 material. The candidate's own reasoning is his first-impression observability note (section 1.2) and the T10 plan to turn balance reconciliation into an alert; the dashboard, SLOs, and alert table are the AI expansion of that, marked accordingly.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content. This mirrors the journal's own human / `<ai>` split.

## TL;DR

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 1.2 and 6*

"For the monitoring aspect, we must approach it from 2 aspects: technical and business." "My own observability reasoning is the first-impression note in Section 1.2 ... plus the T10 plan to build the balance reconciliation into alerting. This Section 6 is **AI-composed**: I had the AI expand that earlier reasoning into the dashboard, SLOs, and alert table". "I am very familiar with Grafana and the monitoring philosophy carries over from my SQL Server time".

---

## Key Findings

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the candidate's own words, verbatim quotes from journal section 1.2 and 6*

- "we start with basic metrics for all DBMSs: CPU, memory, I/O, internal logs (for PostgreSQL: WAL logs), locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs."
- "For the business side, we need to monitor query and procedure duration, especially around core business flows."
- "plus the T10 plan to build the balance reconciliation into alerting." (the underlying reconciliation rule was the AI-added T10 integrity rule from Task 1.)

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *the expansion, full deliverable in `docs/observability.md`*

- A two-layer dashboard (integrity over technical): the `balance_audit_drift` view as the headline integrity alert, plus a system-wide per-currency zero-sum cross-check.
- Settlement lag read off the `PENDING -> SETTLED` state machine; design-specific signals (partition runway, replication-slot retained WAL, XID wraparound).
- Integrity kept as a hard invariant (drift must be 0), not a percentile SLO; thresholds are starting points pending a baseline.

---

## Detailed Analysis

### The candidate's first-impression observability note

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 1.2 "Observability"*

For the monitoring aspect, we must approach it from 2 aspects: technical and business.

For the technical side, all basic metrics related to PostgreSQL and its performance need to be captured. So we start with basic metrics for all DBMSs: CPU, memory, I/O, internal logs (for PostgreSQL: WAL logs), locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs.

For the business side, we need to monitor query and procedure duration, especially around core business flows. But for this aspect, we don't have much context, so this needs more thought later.

### How the candidate frames the split for this task

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 6*

My own observability reasoning is the first-impression note in Section 1.2 (the technical-vs-business split, and the metric list: CPU, memory, I/O, WAL, locking/waiting, connections, cache hits/misses, index utilization, then the PG-specific vacuum, dead tuples, and transaction IDs), plus the T10 plan to build the balance reconciliation into alerting. This Section 6 is **AI-composed**: I had the AI expand that earlier reasoning into the dashboard, SLOs, and alert table, both here and in the deliverable doc. Same separation as Task 2: my thinking is the earlier reasoning, the extracted write-up is the AI's.

### The AI expansion: dashboard, SLOs, alerts

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 6; full deliverable in `docs/observability.md`*

This section realizes the author's Section 1.2 observability note and the T10 reconciliation plan.

- **Two-layer framing (from Section 1.2): business / integrity over technical.** For a payments ledger "is the ledger correct?" outranks "is the box healthy?", so the integrity layer sits on top. The integrity metrics need no new instrumentation; they read guarantees the schema already exposes. The headline is the author's **T10 reconciliation rule**: `balance_audit_drift` is already a view in the DDL, so the most important alert in the system (cached balance drifted from `SUM(entries)`) is a row count off that view. Paired with a system-wide per-currency zero-sum cross-check.

- **Settlement lag mapped onto the design's state machine.** A transaction is born `PENDING` and flips to `SETTLED`, so settlement lag is the age of the oldest still-`PENDING` row and the pending backlog size, both queryable off `transactions.status` + `created_at`. This is a business outage the engine cannot see: the database can look healthy while customer money is stuck in flight.

- **Design-specific "why" entries**: the monthly **partition runway** (next month's `entries` partition must exist, and the DEFAULT partition must stay empty), the **replication-slot retained WAL** footgun (a stalled slot pins WAL until the primary's disk fills and writes stop), and **transaction-ID wraparound**. The lock / long-transaction row is also the live signal to watch during a Task 3 expand-contract migration window.

- **Thresholds and the hard-invariant distinction.** Numbers are starting points: a threshold picked before real traffic is a guess, so the durable content of each alert is the **consequence** in the "why" column, not the digit. Integrity is kept as a **hard invariant** (drift must be 0, per-currency sum must be 0), not a percentile SLO with an error budget; "99.9% of balances reconcile" is the wrong sentence for a ledger.

- **Derived stores.** MongoDB and Neo4j get one signal each (replica-set health, projection staleness). They are rebuildable from the ledger, so they never page the way the system of record does.

Deliverable: [`docs/observability.md`](sources/05-observability/observability.md), the dashboard layout, the SLI/SLO list with the reasoning per metric, and the consolidated alert table (threshold, page-vs-ticket severity, and the consequence behind each), marked AI-composed at its head.

### Selected alert thresholds (from the deliverable)

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *excerpt from `docs/observability.md`; thresholds are starting points pending a baseline*

| Signal | Threshold (starting point) | Severity | Why (the consequence) |
|---|---|---|---|
| `balance_audit_drift` rows | any > 0 | PAGE | Cached balance no longer matches the ledger. Correctness incident, money shown wrong. |
| System-wide per-currency sum of entries | any != 0 | PAGE | The double-entry invariant itself is broken. |
| Oldest `PENDING` transaction age | > 15 min, climbing | PAGE | Settlement pipeline stalled; customer funds stuck in flight. |
| Next-month `entries` partition missing | absent within N days of month end | PAGE | Next month's inserts will fail or misroute. |
| Replication-slot retained WAL / `pg_wal` free | retained WAL high, or `pg_wal` free < 20% | PAGE | Stalled slot pins WAL, primary disk fills, full write outage. |
| Wraparound age `age(datfrozenxid)` | beyond a safe ceiling well below 2^31 | PAGE | Autovacuum behind on freezing; risk of a forced read-only shutdown. |

> **Human direction (Bùi Đức Trí):** My own reasoning for this task is the Section 1.2 observability note and the T10 plan to turn balance reconciliation into an alert; treat this Section 6 and `docs/observability.md` as the AI expansion of that, marked accordingly. I am very familiar with Grafana and the monitoring philosophy carries over from my SQL Server time; the PostgreSQL-specific metric names and catalog views are named by intent and source, not asserted from memory, the same honesty I held in every PG section.

## Open Questions

*Deferred item, from journal section 1.2. The candidate's verbatim is quoted.*

- The business side needs more context: "we don't have much context, so this needs more thought later." Concrete thresholds are starting points to be tuned once Prometheus has a week or two of real-traffic history.

## Sources

[1] Design journal, section 1.2 (observability note) and 6, verbatim - (local: sources/journal/00-journal.md)
[2] Task 5 observability deliverable: dashboard, SLIs/SLOs, alert table, AI-composed - (local: sources/05-observability/observability.md)
