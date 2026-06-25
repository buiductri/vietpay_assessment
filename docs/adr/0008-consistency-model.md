# 0008. Strong vs eventual consistency across microservices

- Status: Proposed (placeholder, to author)
- Date: TBD
- Deciders: Bùi Đức Trí

## Context

Task 6 asks for a position on consistency across the platform's services. The ledger core
(posting, per-currency zero-sum, idempotency) is strongly consistent by construction inside one
PostgreSQL transaction (ADR 0001, 0002, 0006). The open question is which cross-service flows
must stay strongly consistent, which can tolerate eventual consistency, and where the
boundaries sit.

## Decision

To be decided. **Placeholder, not yet argued.**

## Open questions to resolve

- Which read paths may serve from a read replica, and what replication-lag bound is acceptable
  (e.g. customer balance display vs a posting-time balance check)?
- Where does a flow cross a transaction boundary that breaks single-transaction atomicity (for
  example settlement, external bank calls), and how is consistency recovered there (saga,
  outbox, compensating transaction)?
- How does the holding-wallet / external-flow edge case from the journal (section 2.1) fit this
  boundary, and does it reopen the idempotency-lifecycle question deferred in ADR 0006?

## Provenance

Deferred in the journal ("the task requires some more thought about ... the microservices
aspect"). To be authored from my own analysis.
