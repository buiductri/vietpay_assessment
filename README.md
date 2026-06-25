# VietPay DBA Assessment: Report

The design and SQL deliverable for the VietPay Enterprise Database Architect take-home. This
is a design exercise (SQL, diagrams, design notes), not a running application. The reasoning is
captured step by step in the journal; the documents below are extracted from it.

## Where things are

| What | Where |
|---|---|
| Domain language, invariants, status machine | [CONTEXT.md](CONTEXT.md) |
| Architecture Decision Records | [docs/adr/](docs/adr/) ([index](docs/adr/README.md)) |
| ER diagram (the audited model) | [docs/ERD.md](docs/ERD.md), [docs/ERD.html](docs/ERD.html) |
| Task 1 DDL (12-step up/down runner + smoke test) | [src/ddl/](src/ddl/) ([README](src/ddl/README.md)) |
| Task 4 Layer 3 audit (MongoDB) design | [docs/audit-l3-mongodb.md](docs/audit-l3-mongodb.md) |
| Design journal (reasoning, step by step) | [00-journal.md](00-journal.md) |
| Candidate background and how AI was used | [00-introduction.md](00-introduction.md) |

## Tasks and status

| Task | Deliverable | Status |
|---|---|---|
| 1 - Relational core model | DDL + ER diagram + design notes | Done (`docs/ERD.md`, `src/ddl/`); live-DB run pending |
| 2 - Query & performance | Optimised query + index/partition strategy | In progress |
| 3 - Zero-downtime migration | Expand-contract scripts + rollback | In progress |
| 4 - Polyglot modelling | MongoDB audit log + Neo4j fraud graph | MongoDB design done; Neo4j in progress |
| 5 - Observability | Grafana dashboard spec + alert thresholds | In progress |
| 6 - ADR | Architecture Decision Records | Decided set in `docs/adr/`; forward-looking ones to author |

## Artifact status (per the /dev workflow)

The `/dev` workflow expects a standard artifact set, with "produce each or justify N/A". For a
design and SQL deliverable:

- **Produced**: `CONTEXT.md`, `docs/adr/*`, `docs/ERD.md` (+ HTML), `src/ddl/` (with its own
  README and `test/smoke_test.sql`), `docs/audit-l3-mongodb.md`.
- **N/A** (no application code): `Dockerfile`, `compose.yaml`, `docs/USAGE.md`,
  `docs/ERRORS.md`, an application test suite, and `evals/` (no AI/LLM feature ships here).
  A report-level `AGENTS.md` is also N/A: the container-level `AGENTS.md` already steers the
  workspace and there is no service to run. A separate `docs/IMPLEMENTATION-PLAN.md` is N/A
  because `00-journal.md` already serves as the step-by-step spec and plan.
- **Deferred / in progress**: Tasks 2, 3, 5, and the Neo4j half of Task 4, plus the
  forward-looking ADRs (cross-service consistency model, data contracts) listed in
  `docs/adr/README.md`.

## A note on authorship

The journal separates the candidate's reasoning from AI-assisted contributions inline (human
feedback blocks vs `<ai>` markers). The extracted documents keep that separable: `CONTEXT.md`
records standards and encoding choices as consensus decisions with trade-offs, and each ADR
carries a "Provenance" line stating what is the candidate's own reasoning and what AI research
surfaced.
