# 0007. Audit is three layers; Layer 2 in Postgres, Layer 3 in MongoDB; no trigger audit

- Status: Accepted
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

The assessment asks for an audit trail in the relational core. A common reflex is a database trigger that copies every change into an audit table. But a trigger fires inside the transaction, so it sees nothing useful on a rollback (a denied or failed attempt leaves no record), and it doubles write load on the main database. Compliance audit is also broader than transactions: it covers state changes to all entities (wallet freeze, KYC tier, limit change) and access/attempt activity.

## Decision

Model audit as three layers:

- **Layer 1**: the ledger entries themselves, immutable and append-only, are their own audit.
- **Layer 2**: an in-Postgres `audit_log` of **committed** state changes to non-ledger entities, written in the same transaction as the change (so it is always consistent with committed state and correctly disappears if the change rolls back). It audits all entities through a polymorphic `(entity_type, entity_id)` pair, so it is a **detached** entity with no drawn foreign-key relationships.
- **Layer 3**: an append-only **MongoDB** activity log for attempts, denials, replays, and access. This is where rolled-back-attempt information lives, and it doubles as the Task 4 MongoDB use case.

No general-purpose trigger audit.

## Consequences

- Rolled-back attempts are captured by the application into Layer 3, not lost inside a trigger.
- Audit is polyglot: Postgres for committed non-ledger changes, MongoDB for the activity stream. The two are linked by a `request_id`.
- `audit_log` is drawn detached (it relates to every entity, so a single line would mislead and lines to all would clutter the diagram).
- The Layer 3 MongoDB collection type (capped sized large, time-series, or regular plus TTL) is left open in `docs/audit-l3-mongodb.md`, pending a sizing and retention decision.

## Alternatives considered

- **Trigger-based audit**: no information on rollback, and extra load on the primary; rejected for the attempt layer.
- **Single-store audit (Postgres JSONB only)**: loses MongoDB's fit for high-volume, schema-volatile, immutable activity logs (capped collections); rejected for Layer 3.

## Provenance

The decision to keep audit out of triggers and at the application level is mine, from section 2.1. AI research (`0-research/double-entry-ledger/06-audit-layers.md`) supplied the explicit three-layer framing. The `audit_log` detachment and the direction to keep exploring a large capped collection for Layer 3 are my own calls.
