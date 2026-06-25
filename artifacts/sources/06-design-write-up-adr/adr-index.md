# Architecture Decision Records

Decisions for the VietPay core payments ledger, extracted from the design journal
(`../../00-journal.md`) and the audited model (`../ERD.md`). Each record is one decision.

These are authored in my own voice as the candidate (Bùi Đức Trí). Where AI-assisted research
surfaced a fact, a gap, or a technique, the "Provenance" section of that ADR says so, so my own
reasoning stays separable from the AI's contribution.

## Accepted

| # | Decision |
|---|---|
| [0001](0001-double-entry-ledger-source-of-truth.md) | Double-entry ledger is the source of truth; wallet balance is derived |
| [0002](0002-per-currency-zero-sum.md) | Zero-sum enforced per currency, by a deferred constraint trigger |
| [0003](0003-entry-amount-encoding.md) | Entry amount is a positive magnitude with direction in `type` (standards choice) |
| [0004](0004-fx-currency-pure-wallets.md) | Cross-currency transfers use currency-pure wallets and house FX wallets |
| [0005](0005-currency-consistency-composite-fk.md) | Entry/wallet currency consistency by composite foreign key |
| [0006](0006-idempotency-caller-key.md) | Idempotency scoped to `(caller_id, key)` on a single-atomic-posting assumption |
| [0007](0007-three-layer-audit-polyglot.md) | Three-layer audit; Layer 2 in Postgres, Layer 3 in MongoDB; no trigger audit |

## Proposed (placeholders, to author)

These decisions the assessment (Task 6) calls for are not yet made; the journal flags them as
needing more thought. Each has a placeholder ADR (Status: Proposed) that frames the open
question and the trade-offs, so the gap is explicit and ready to fill in later. **None is
decided.**

| # | Open decision |
|---|---|
| [0008](0008-consistency-model.md) | Strong vs eventual consistency across microservices |
| [0009](0009-data-contracts-between-services.md) | Data contracts between services (ownership, transport, versioning) |
| [0010](0010-text-check-vs-enum.md) | TEXT + CHECK vs native ENUM for status/type columns (DDL standard) |
