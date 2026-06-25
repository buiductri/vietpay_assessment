# 0002. Zero-sum is enforced per currency, by a deferred constraint trigger

- Status: Accepted
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

Double-entry requires each transaction's entries to balance. The naive rule is a single global sum over all entries of a transaction. With multiple currencies in one transaction (FX, see ADR 0004), a global, currency-blind total can be fooled: an imbalance in one currency can cross-cancel an imbalance in another and still net to zero. Example: a 2-entry transaction with a 27,000 VND debit and a 27,000 USD credit nets to a balanced global total but leaks roughly 27,000x of value.

## Decision

Enforce the balance **per currency**: within each currency of a transaction, `SUM(amount WHERE type=DEBIT) = SUM(amount WHERE type=CREDIT)`. Enforce it in the database, not the application, via a `DEFERRABLE INITIALLY DEFERRED` constraint trigger that fires at COMMIT. Deferring to commit lets a valid multi-leg FX transfer be built up mid-transaction without tripping the check on an intermediate state.

## Consequences

- The check is strictly stronger than a global sum and cannot be fooled by cross-currency cancellation.
- A transaction that fails the check is rolled back; the invariant holds "by construction, not by hope".
- The trigger is deferred, so application code may insert the entries in any order within the transaction.
- A negative test that forces the trigger to fire (via `SET CONSTRAINTS ... IMMEDIATE`) is part of the DDL smoke test.

## Alternatives considered

- **Global signed sum**: simpler, but foolable across currencies (above).
- **Application-level assertion only**: correct only as long as every writer remembers to do it; not by construction.

## Provenance

Zero-sum was in my original model from the start. The specific per-currency cross-cancellation failure mode and the worked example were surfaced by AI research (`0-research/double-entry-ledger/07-multi-currency.md`) and a review discussion; I adopted per-currency as the rule and the deferred-trigger mechanism.
