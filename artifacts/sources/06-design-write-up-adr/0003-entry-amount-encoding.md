# 0003. Entry amount is a positive magnitude with direction in `type` (a standards choice)

- Status: Accepted (modelling standard)
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

An entry's value can be encoded at least three ways: (a) a signed `amount` (credits negative); (b) a signed `amount` plus a `CHECK` that ties sign to `type`; (c) a positive `amount` with direction held only in `type` (`DEBIT`/`CREDIT`).

This was initially raised as if (c) were a *safety* fix over (a). It is not. A constraint such as `CHECK ((type='CREDIT' AND amount>0) OR (type='DEBIT' AND amount<0))` makes the signed model just as safe. All three encodings are equally correct; which is "better" depends on team consensus and coding standards, not on objective correctness.

## Decision

Use encoding (c): `amount` is a positive magnitude with `CHECK (amount > 0)`, and direction lives only in `type`. This is recorded as a **standards decision** for this design, not a bug fix.

## Consequences

- Every `entry.amount` is positive; the per-currency zero-sum (ADR 0002) compares `SUM` over `DEBIT` against `SUM` over `CREDIT` rather than summing signed values to zero.
- Aggregations branch on `type`; a report that wants a signed view derives it.
- If a future team standard prefers signed amounts, the change is mechanical and the `CHECK` above keeps it safe; nothing else in the design depends on the encoding.

## Provenance

Mine. The point that a `CHECK` makes the signed encoding equally safe, so this is a consensus/standards decision rather than a correctness fix, is my own argument; it corrected an overstated "safety" framing during the model audit.
