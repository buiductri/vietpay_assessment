# Take Home Assessment (Database)
# Enterprise Database Architect — Fintech

## Objective

Design the core data layer for a fintech payments platform. This role is architecture- and design-led, so this is a **design and SQL exercise, not an application build**. We want to see how you model financial data, reason about performance, migrate live systems safely, and choose the right store for each job. The deliverable is a Git repository containing SQL scripts, migration files, diagrams, and written design notes.

## Provided Context

Assume a payments platform with a transactions table that already holds roughly 50 million rows and grows by ~2 million per month. A simplified starting point:

```
transactions(id, wallet_id, type, amount, currency, status, created_at)
```

A common reporting query is slow in production:

```sql
SELECT wallet_id, currency, SUM(amount) FROM transactions
WHERE status = 'SETTLED' AND created_at >= :month_start AND created_at < :month_end
GROUP BY wallet_id, currency;
```

---

## Tasks

### 1) Relational core model

- Design a normalised PostgreSQL schema for a wallet/payments domain with: accounts/wallets, a **double-entry ledger**, transactions, **idempotency keys**, and an **audit trail**.
- Deliver the DDL as SQL files, plus an ER diagram (image or text).
- Explain your integrity guarantees: how the ledger always balances, how a duplicate request cannot post twice, and your indexing strategy with reasons.

### 2) Query & performance

- Optimise the provided settlement query for the 50M-row table. Provide the improved query and the supporting indexes and/or **partitioning** strategy.
- Explain how you validate the improvement (what the query plan should change), and the cost of your index (write overhead, size).

### 3) Zero-downtime migration

- Provide a concrete **expand-contract** migration to add a NOT NULL column (e.g., `settlement_batch_id`) to the live 50M-row transactions table, under real production load.
- Give the ordered steps and the migration scripts: backfill, dual-write window, constraint promotion, and **rollback at each phase**.
- Scripts must be idempotent and reversible. State exactly when the application reads the old vs new shape.

### 4) Polyglot modelling

- **MongoDB:** model one use case where a document store fits better than relational (e.g., raw webhook/event payloads or an append-only audit event log). Justify it over a Postgres JSONB column.
- **Neo4j:** model a relationship use case (e.g., a merchant referral network or fraud-ring detection), with the graph model and 1–2 Cypher queries. Justify why this is genuinely a graph problem.

### 5) Observability

- Define the key metrics and SLOs you would put on a **Grafana** dashboard for this fintech database: latency, throughput, replication lag, lock contention, settlement lag, capacity.
- State the alerts you would set and their thresholds, and why.

### 6) Design write-up (ADR)

- A short architecture decision record covering: modelling standards, strong vs eventual consistency choices, and how you define **data contracts between microservices** so schema changes don't silently break consumers.

---

## Recommended Tools

| Area | Recommended |
|---|---|
| Relational | PostgreSQL (MySQL acceptable) |
| Document | MongoDB |
| Graph | Neo4j (Cypher) |
| Migrations | Flyway or Liquibase |
| Observability | Grafana (+ Prometheus or equivalent) |
| Deliverable | Git repo: SQL files, migration scripts, .md design notes, diagrams |

---

## What We Evaluate

- **Fintech data correctness** — double-entry integrity, idempotent posting, audit and reconciliation trails enforced by the schema, not by hope.
- **Performance reasoning** — the right index/partition for the workload, and the ability to read a query plan.
- **Safe change** — a migration that is genuinely zero-downtime and reversible, with rollback at every step.
- **Right tool for the job** — relational vs document vs graph chosen with clear justification, not by trend.
- **Written communication** — this role is documentation-heavy; clarity of your notes matters as much as the SQL.

---

## Timeline & Submission

**Deadline:** You have 3 days (72 hours) to complete this task, starting from the moment you received this email.

**Version control:** Please provide frequent, descriptive commit messages that reflect your reasoning. We value the development process, not just the final files.

**Submission:** Reply to this email thread with a link to your public GitHub repository before the deadline. Include a top-level README that indexes your deliverables for each task.

*You don't need to build a running application. Realistic, well-reasoned designs with working SQL and clear written justification are exactly what we're looking for.*
