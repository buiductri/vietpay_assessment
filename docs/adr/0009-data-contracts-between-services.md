# 0009. Data contracts between services

- Status: Proposed (placeholder, to author)
- Date: TBD
- Deciders: Bùi Đức Trí

## Context

Task 6 asks how services exchange data and how those contracts evolve without breaking
consumers. Existing decisions that touch this: the Layer 3 MongoDB audit stream linked by
`request_id` (ADR 0007), and the expand-contract migration discipline (Task 3). This ADR would
set the contract and versioning standard between services.

## Decision

To be decided. **Placeholder, not yet argued.**

## Open questions to resolve

- Schema ownership: which service owns the canonical shape of a `transaction`, an `entry`, an
  audit event?
- Transport: synchronous service calls vs an asynchronous outbox / change-data-capture event
  stream (and where each is appropriate)?
- Versioning and evolution: how are breaking vs non-breaking changes handled, reusing the
  expand-contract discipline from Task 3?
- Serialization and a schema registry: is one needed, and which?

## Provenance

Deferred in the journal (design write-up, microservices aspect). To be authored.
