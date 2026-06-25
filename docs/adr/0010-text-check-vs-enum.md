# 0010. TEXT + CHECK vs native ENUM for status/type columns

- Status: Proposed (placeholder, to author)
- Date: TBD
- Deciders: Bùi Đức Trí

## Context

The DDL in `src/ddl/` encodes the closed-vocabulary status and type columns (`account.type`,
`wallet.kind`, `transaction.status`, `entry.type`) as `TEXT` with `CHECK` constraints rather
than native PostgreSQL `ENUM` types. (`transaction.type` is the deliberate exception: its
vocabulary is spec-dependent, so it is left as open `TEXT` with no `CHECK` for now, which is
also why it is the natural candidate for the lookup-table option below.) This is a modelling
standard already applied in the implementation but not yet argued in the journal. Like the
entry-amount encoding (ADR 0003), it is a consensus / standards choice, not a correctness one:
both can be made safe.

## Decision

To be decided: ratify the existing `TEXT + CHECK` standard, or revise it. **Placeholder, not yet
argued.**

## Open questions / trade-offs to weigh

- **Native `ENUM`**: compact, ordered, type-safe and reusable; but evolution is awkward
  (`ALTER TYPE ... ADD VALUE` has transactional limits on older versions, and removing a value
  is hard).
- **`TEXT + CHECK`** (current): trivial to evolve (drop and recreate the `CHECK`), readable,
  no special type; but no type-level reuse and validation lives only in the constraint.
- **Lookup table**: a third option for a high-churn vocabulary (e.g. `transaction.type`),
  trading a join for easy data-driven changes.

## Provenance

A DDL-level standards choice, framed alongside ADR 0003. Already applied in `src/ddl/`; this ADR
would ratify or revise it. To be authored.
