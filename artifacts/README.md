# VietPay DBA Assessment: Briefing Pack

**A research-format reorganization of the VietPay Enterprise Database Architect take-home, by its six tasks, with the candidate's reasoning kept verbatim and every AI-assisted contribution marked.**

This pack adds no new analysis. It re-presents the design journal (`00-journal.md`) and the committed documentation, rebucketed into one document per assessment task, in the `/research` skill format. The same human / `<ai>` split the journal uses is carried through here as OWNED and AI-GENERATED pills.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content, including the synthesis below.

## Research Files

| File | Task | Description |
| --- | --- | --- |
| [00-introduction.md](./00-introduction.md) | Overview | Candidate background, method, and the authorship model |
| [01-relational-core-model.md](./01-relational-core-model.md) | Task 1 | Double-entry ledger, entities, ERD audit, DDL |
| [02-query-and-performance.md](./02-query-and-performance.md) | Task 2 | Settlement-report join, partitioning, covering index, query plans |
| [03-zero-downtime-migration.md](./03-zero-downtime-migration.md) | Task 3 | Expand-contract `settlement_batch_id NOT NULL` with per-phase rollback |
| [04-polyglot-modelling.md](./04-polyglot-modelling.md) | Task 4 | MongoDB Layer 3 audit (owned) + Neo4j fraud graph (AI-composed) |
| [05-observability.md](./05-observability.md) | Task 5 | Two-layer Grafana dashboard, SLOs, alert thresholds |
| [06-design-write-up-adr.md](./06-design-write-up-adr.md) | Task 6 | ADR set, consistency model, data contracts |

## Tasks and status

*Status as recorded in the report `README.md` (a structural index, not authored prose).*

| Task | Deliverable | Status |
|---|---|---|
| 1 - Relational core model | DDL + ER diagram + design notes | Done; validated live on PG 17.2 |
| 2 - Query & performance | Optimised query + index/partition strategy | Done; plan analysis AI-authored |
| 3 - Zero-downtime migration | Expand-contract scripts + rollback | Done; validated end to end on PG 17.2 |
| 4 - Polyglot modelling | MongoDB audit log + Neo4j fraud graph | MongoDB done; Neo4j model AI-composed from research |
| 5 - Observability | Grafana dashboard spec + alert thresholds | Done |
| 6 - ADR | Architecture Decision Records | 0001-0007 accepted; 0008-0010 framed as Proposed |

## Cross-Axis Synthesis

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *synthesis composed for this pack from the candidate's recurring threads across the journal*

Five threads run across all six tasks, all traceable to the candidate's own reasoning:

- **One source of truth, everything else derived.** The relational ledger entries are authoritative; `wallet.balance` (Task 1), the summary rollup (Task 2), the MongoDB and Neo4j stores (Task 4) are all rebuildable projections, never the financial source of truth. The same sentence appears in his Task 4 human direction and the Task 1 ADR 0001.
- **Enforce by construction, not by hope.** Per-currency zero-sum, currency consistency, idempotency, and immutability are all schema-level guarantees (Task 1), and the observability layer (Task 5) just puts a panel on the guarantees the schema already exposes (the T10 reconciliation rule).
- **Honesty about the PostgreSQL gap.** The candidate flags throughout that PostgreSQL is not his main stack; AI fills the PG-specific mechanics, and he marks those parts rather than claim them. This is why the deep query-plan analysis (Task 2), the migration internals (Task 3), and the metric names (Task 5) are AI-marked.
- **Best tool for the job, proven not assumed.** Task 4 insists on a litmus that the fraud ring is genuinely a graph problem, and names the boundary where JSONB (not MongoDB) or Postgres (not Neo4j) is the right call.
- **The entry split propagates.** Mapping the assessment's flat `transactions` onto `transaction` + `entry` (Task 1) is what turns the report into a join (Task 2) and places the migration on `entries` (Task 3); the tasks are not independent.

## Local Sources

The pack is self-contained. Primary sources are copied under [`./sources/`](./sources/): the design journal, introduction, and `CONTEXT.md` under `sources/journal/`, and each task's canonical deliverable doc under `sources/{axis}/`. SQL trees (`src/ddl/`, `src/mongo/`) are referenced by repo path rather than copied.

_Reorganized: 2026-06-25. Source material: the committed `00-journal.md` and `docs/` of this report._
