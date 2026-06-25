# CONTEXT: VietPay Core Payments Ledger

Canonical domain terms, invariants, and aliases for the core payments ledger as
**actually designed** in this report (the audited model in `docs/ERD.md`, reasoned
through in `00-journal.md`). This supersedes the early domain-research glossary in
`../1-assessment/CONTEXT.md`, which was written before the ERD audit and still describes
encodings this design did not adopt (global signed zero-sum, plain-FK currency). Keep this
current; it regresses fast.

> This file describes the **chosen** design. Where an alternative encoding is equally valid
> and was simply not selected, it is recorded under "Flagged ambiguities (resolved)" as a
> standards decision, not under "Aliases to avoid".

---

## Domain Terms

| Term | Precise Definition |
|---|---|
| **Account** | A chart-of-accounts bucket that owns wallets. Its `type` gives its ledger role (`CUSTOMER`, `PLATFORM_FLOAT`, `PLATFORM_REVENUE`, `MERCHANT_PAYABLE`, `FX_POSITION`). Holds no balance directly. KYC/tier attributes are left to spec and not modelled. |
| **Wallet** | A single-currency balance container under one account. `kind` is `regular` (spendable) or `holding` (held while an external flow settles). An account holds many wallets (one per currency, plus holding). |
| **Transaction** | The journal header that groups the entries which must balance. Carries `type` (transfer, exchange, fee, ...), lifecycle `status`, an optional pinned FX rate, and `extra_info`. Never modified after posting; an undo is a new reversing transaction. |
| **Entry** | A single debit or credit line against one wallet. An immutable, append-only fact. `amount` is a positive magnitude; direction lives in `type` (`DEBIT` or `CREDIT`). Carries no lifecycle status of its own. |
| **Double-entry, per currency** | Every transaction's entries balance **within each currency**: `SUM(amount WHERE type=DEBIT) = SUM(amount WHERE type=CREDIT)` per currency. A same-currency move is one balanced pair; a cross-currency move is two balanced pairs bridged by an FX rate. |
| **Idempotency Key** | A client-supplied token scoped to a caller. `UNIQUE (caller_id, key)` guarantees a re-submitted request posts no duplicate; the original transaction is returned instead. Claimed inside the posting transaction. |
| **Posting** | Writing the transaction, its entries, and the idempotency-key claim atomically in one DB transaction. Either fully posted or not at all. |
| **Holding wallet** | A wallet of `kind = holding` that temporarily holds an account's balance while an external flow processes it. In-flight money lives here, per account and per currency, not in a central suspense account. |
| **Chart of accounts** | The set of platform-owned account roles (`PLATFORM_FLOAT` for real bank cash, `PLATFORM_REVENUE` for fees, `MERCHANT_PAYABLE` for funds owed out, `FX_POSITION` for the FX desk) that let a fee, top-up, or FX leg balance against a customer account. |
| **FX bridge** | A cross-currency transfer routed as two single-currency balanced legs through the platform's `FX_POSITION` wallets (`FX_VND`, `FX_USD`), in one transaction under one idempotency key. The rate never enters the balance check. |
| **Exchange Rate** | An immutable, point-in-time rate for a date and currency pair (OANDA-style). A transaction references the exact record by `exchange_rate_id`, so the rate is pinned and a retry is deterministic. |
| **Settlement** | The downstream clearing step that finalises funds movement with an external network or bank. A transaction moves `PENDING -> SETTLED`. |
| **Settlement Batch** | A group of transactions settled together in one clearing cycle (`settlement_batch_id`). A Task 3 (zero-downtime migration) concern, deliberately not in the core ERD. |
| **Audit Trail** | The three-layer record of changes. Layer 1 is the ledger entries (immutable, their own audit). Layer 2 is an in-Postgres `audit_log` of committed non-ledger state changes. Layer 3 is a MongoDB append-only activity log (attempts, denials, access). |
| **Derived balance** | `wallet.balance` is a cache computed from the entries inside the transaction. It is **never** the source of truth; the entries are. A scheduled `balance_audit` reconciles it. |

---

## Aliases to Avoid

| Avoid | Use Instead | Reason |
|---|---|---|
| "balance table" | `wallet` (derived balance) or the `entry` rows | "balance table" implies a mutable running total; the source of truth is the ledger entries |
| `float` / `double` for money | `NUMERIC(19,4)` (rates `NUMERIC(19,8)`) | floating-point arithmetic is non-deterministic for financial sums |
| "transaction log" | `audit_log` (Layer 2) or the Layer 3 activity log | "log" implies infrastructure logs; the audit trail is a first-class financial record |
| "payment" (overloaded) | `transaction` (ledger event) or `transfer` (business action) | "payment" conflates the business intent with the accounting record |
| "suspense account" | a per-account **holding wallet** | in-flight money is held per account/currency, not in one central suspense account |
| global / currency-blind zero-sum | **per-currency** zero-sum | a currency-blind total can net to balanced while individual currencies are imbalanced and cross-cancel |
| "the latest FX rate" | the **pinned** `exchange_rate_id` record | the transaction references an exact point-in-time rate, not whatever is current |

Note: signed `amount` (credits negative) is **not** listed here. It is a valid encoding that
this design did not choose; see "Flagged ambiguities (resolved)".

---

## Relationships

- An **Account** owns many **Wallets** (1 : N), one per currency plus holding.
- A **Transaction** has two or more **Entries** that balance (1 : 2..N).
- A **Wallet** is targeted by many **Entries** (1 : N); the link is a composite
  `(wallet_id, currency)` foreign key, so an entry's currency must match its wallet's.
- An **Idempotency Key** maps to at most one **Transaction** (1 : 0..1).
- An **Exchange Rate** is referenced by exchange **Transactions** (1 : 0..N); non-exchange
  transactions reference none.
- A **Currency** is the base and the quote of many **Exchange Rates** (1 : N each).
- **audit_log** is a detached entity: it audits all entities through the polymorphic
  `(entity_type, entity_id)` pair, which is not a drawable foreign key, so it has no
  relationship lines.

---

## Key Invariants

These must be enforced by the schema, not by application hope ("by construction, not by hope").

1. **Zero-sum, per currency.** Within each currency of a transaction,
   `SUM(amount WHERE type=DEBIT) = SUM(amount WHERE type=CREDIT)`. Enforced by a
   `DEFERRABLE INITIALLY DEFERRED` constraint trigger that fires at COMMIT (so a valid
   multi-leg FX transfer can be built up mid-transaction), inside the posting transaction.

2. **Idempotency.** A `(caller_id, key)` pair maps to at most one transaction
   (`UNIQUE (caller_id, key)`). The key is claimed inside the business transaction, so a
   rollback releases it. A duplicate request is rejected and mapped to the original.

3. **Immutability of entries.** `entry` rows are append-only: `REVOKE UPDATE, DELETE` from
   the app role. A correction is a new reversing transaction (`status = REVERSED`), never an
   edit or delete. The entries are themselves the lifecycle audit.

4. **Atomicity of posting.** The transaction, its entries, and the idempotency-key claim are
   written in one DB transaction. Partial posts are impossible by construction.

5. **Currency consistency.** An entry's currency must equal its wallet's. Enforced by
   construction: `wallet` carries `UNIQUE (wallet_id, currency)` and `entry` has a composite
   FK `(wallet_id, currency) -> wallet`, both columns `NOT NULL` (a NULL would bypass a
   composite FK under the default `MATCH SIMPLE`).

6. **Derived balance and reconciliation.** `wallet.balance` is a cache, never the source of
   truth. A scheduled `balance_audit` compares it against `SUM(entries)` per wallet and
   alerts on any nonzero discrepancy (detailed in Task 5, observability).

7. **Money and ids.** Money is `NUMERIC(19,4)` (no floating point); rates are `NUMERIC(19,8)`;
   ids are `UUID`.

8. **Partition alignment (physical, Task 2).** `entry` is range-partitioned monthly on
   `created_at`. Queries should carry a `created_at` predicate to get partition pruning; the
   physical PK becomes `(entry_id, created_at)`. The ERD stays logical (PK `entry_id`); the
   partitioning detail lives in Task 2.

---

## Status State Machine

```
PENDING ──► SETTLED
   │
   └──────► REVERSED
```

- The vocabulary is `{PENDING, SETTLED, REVERSED}` (a spec choice). The earlier
  `PROCESSING` / `FAILED` states were dropped when entry lifecycle was consolidated onto
  `transaction.status`.
- `REVERSED` is reached by **posting a new reversing transaction**, not by mutating the
  original. `SETTLED` is terminal.
- An `entry` has no status of its own; lifecycle lives only on `transaction.status`.

---

## Flagged ambiguities (resolved)

Terms or choices that were ambiguous and have a recorded resolution. Several were settled by
the candidate's (Bùi Đức Trí) own argument and are standards decisions, not correctness fixes.

- **`amount` sign (encoding).** Signed amount (credits negative), signed amount + a `CHECK`,
  and positive magnitude + direction in `type` are **all equally correct**: a `CHECK` such as
  `((type='CREDIT' AND amount>0) OR (type='DEBIT' AND amount<0))` makes the signed model just
  as safe. This design chose **positive magnitude + `type`** as a standards decision (team
  consensus / coding standard), not because the alternatives are unsafe.
- **Account role vs wallet kind.** "Holding" is a wallet-level `kind`, not an account-level
  role; the account `role` (customer, FX desk, ...) lives on `account.type`. The two are
  orthogonal. A platform `SUSPENSE` account was rejected as the wrong abstraction.
- **Zero-sum scope.** Resolved to **per currency** rather than a global signed total: a
  currency-blind check can be fooled when an imbalance in one currency cross-cancels an
  imbalance in another. Per-currency is strictly stronger.
- **Idempotency lifecycle fields.** Brandur-style `recovery_point` / `locked_at` /
  `response_*` were rejected for this design: for a single atomic posting the key is claimed
  in the transaction, rollback releases it, and crash-recovery rolls back any uncommitted
  transaction, so there is no in-between state to recover. They apply only to a multi-step
  flow that commits steps separately (out of scope). Only `expires_at` is kept (operational).
- **Exchange value storage.** The exchange value (`amount x rate`) is derivable from the
  pinned `exchange_rate_id` record, so it is deliberately kept denormalized in `extra_info`
  rather than as a typed `fx_rate` column.
- **Audit placement.** DB triggers were rejected for the rolled-back-attempt audit (a trigger
  sees no information on rollback and doubles load on the main DB). Committed non-ledger
  changes go to the in-Postgres Layer 2 `audit_log` (written in the same transaction);
  attempts / denials / access go to the Layer 3 MongoDB activity log.

---

## Example dialogue

> **Dev:** A customer sends 1 USD worth of VND to another customer. Is that one transaction
> with one cross-currency **entry**?
>
> **Domain expert:** No. It is one **transaction** with four **entries**, two balanced legs.
> The VND leg debits the sender's VND **wallet** and credits the platform `FX_VND`
> **holding/FX wallet**; the USD leg debits `FX_USD` and credits the receiver's USD wallet.
> Each currency balances on its own. The **exchange rate** is pinned on the transaction and
> never enters the balance check.
>
> **Dev:** And if the sender's app retries the request?
>
> **Domain expert:** The retry carries the same `(caller_id, key)`, so it is rejected and
> mapped to the original transaction. Nothing posts twice.

---

## Scope of This Deliverable

This repo is a **design and SQL exercise** (assessment deliverable), not a running application.

| Task | Deliverable | Where |
|---|---|---|
| 1 - Relational core model | DDL SQL + ER diagram + design notes | `docs/ERD.md`, `src/ddl/` |
| 2 - Query & performance | Optimised query + index/partition strategy | (in progress) |
| 3 - Zero-downtime migration | Expand-contract migration scripts + rollback | (in progress) |
| 4 - Polyglot modelling | MongoDB audit log + Neo4j fraud graph | `docs/audit-l3-mongodb.md` (Mongo), Neo4j (in progress) |
| 5 - Observability | Grafana dashboard spec + alert thresholds | (in progress) |
| 6 - ADR | Architecture Decision Records | `docs/adr/` |

N/A artifacts (design exercise, no application code): `Dockerfile`, `compose.yaml`,
`docs/USAGE.md`, `docs/ERRORS.md`, application test suites, evals (no AI/LLM feature). The
DDL ships with its own `src/ddl/README.md` and `src/ddl/test/smoke_test.sql`.
