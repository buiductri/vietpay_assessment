# Core ledger DDL and deployment (Task 1)

The relational core model from [`docs/ERD.md`](../../docs/ERD.md), delivered as
an **ordered, individually reversible initial deployment** plus a small
orchestrator. This is the SQL half of Task 1 (the written integrity/indexing
notes live in the report body); the ER diagram is `docs/ERD.md` / `docs/ERD.html`.

`docs/ERD.md` is the source of truth. Where it records a decision (with `[^ai]` /
`[^air]` markers and the journal changelog), the DDL follows it. The ERD entities
are named in the singular (conceptual); the physical **tables are plural**
(`accounts`, `wallets`, `transactions`, `entries`, `currencies`,
`exchange_rates`, `idempotency_keys`, `audit_logs`), a naming standard.

## Layout

```
src/ddl/
  deploy.sh                 orchestrator (psql-based migration runner)
  initial/                  the ONE-TIME baseline schema, as NN_name.up.sql + .down.sql
    01_extensions_and_roles 02_currency        03_exchange_rate
    04_account              05_wallet          06_transaction
    07_entry                08_idempotency_key  09_audit_log
    10_integrity_zero_sum   11_immutability     12_reconciliation_view
  test/
    smoke_test.sql          executable integrity spec (run after `up`)
```

`initial/` holds the one-time schema creation. Later **incremental** changes
(e.g. the Task 3 expand-contract migration) belong in their own separate phase,
tracked under their own keys; this runner owns only `initial/`. Each step is
**idempotent** (`IF NOT EXISTS`, `CREATE OR REPLACE`, drop-then-create for the
constraint trigger) and **reversible** (a matching `.down.sql`).

## Deployment state: accidental re-deploy is safe

The runner records applied steps in a `schema_migrations` table
(`step`, `checksum`, `applied_at`, `applied_by`). On `up`:

- a step already recorded is **skipped** (not re-run);
- each applied step stores an **md5 checksum** of its `.up.sql`. If a step that
  was already applied has since **changed on disk**, `up` **refuses** to proceed.
  You must ship a new migration rather than silently mutate an applied one;
- step + bookkeeping row are written in **one transaction**, so a mid-step
  failure rolls the whole step back and leaves the tracker untouched.

State keys are namespaced by phase (`initial/07_entry`), so a future migration
phase never collides with the baseline.

## Deploy

No secrets live in the scripts. Point the runner at a database with
`DATABASE_URL` or the standard libpq `PG*` variables, then:

```bash
export DATABASE_URL="postgres://user:pass@host:5432/vietpay"

./deploy.sh up          # apply all steps 01 -> 12
./deploy.sh status      # applied / pending / changed-since-apply
./deploy.sh verify      # assert every expected object exists
./deploy.sh test        # run the smoke test (integrity spec)

./deploy.sh down-to 06  # roll back to just after step 06
./deploy.sh down        # full teardown (12 -> 01)
./deploy.sh redo 10     # revert + re-apply one step while iterating
./deploy.sh bundle      # print the whole schema as one SQL stream
```

`up-to N` / `down-to N` take a step number (`07`), prefix, or full name
(`07_entry`).

> **Target: PostgreSQL 14+** (tested against 17). `gen_random_uuid()` is used
> from core (v13+).
>
> **Privilege note:** creating `vietpay_app` needs `CREATEROLE`/superuser. If the
> deploying role lacks it, role creation and the privilege REVOKE/GRANT steps
> **degrade gracefully** (skipped with a NOTICE) and the rest of the schema still
> deploys. Immutability is still enforced by the deny **trigger** meanwhile;
> provision `vietpay_app` out-of-band and re-run steps 11 and 12 to apply REVOKE.

## What the schema enforces (by construction, not by hope)

| Guarantee | Mechanism | Where |
|---|---|---|
| **Zero-sum, per currency** | `DEFERRABLE INITIALLY DEFERRED` constraint trigger: every currency in a transaction must have `SUM(DEBIT)=SUM(CREDIT)` at COMMIT | step 10 |
| **Currency consistency** | composite FK `entries (wallet_id, currency)` -> `wallets`, both columns `NOT NULL`; wallet carries `UNIQUE (wallet_id, currency)` | steps 05, 07 |
| **Idempotency** | `UNIQUE (caller_id, key)`; app claims it with `INSERT ... ON CONFLICT DO NOTHING` inside the posting transaction | step 08 |
| **Immutability** | `REVOKE UPDATE/DELETE/TRUNCATE` from the app role **+** a defence-in-depth deny trigger, on both `entries` and `audit_logs` | step 11 |
| **Positive amounts** | `CHECK (amount > 0)`; direction is in `entries.type` | step 07 |
| **Derived balance** | `wallets.balance` is a cache; `balance_audit` / `balance_audit_drift` reconcile it against `SUM(entries)` | steps 05, 12 |
| **Least privilege** | `vietpay_app` is granted only what each table needs; no DELETE on financial history | steps 11, 12 |

The cross-currency case is the worked example from the ERD: a transfer where the
recipient gets 1 USD for 27,000 VND is **two balanced single-currency legs**
bridged through the platform FX-position wallets, in one transaction. The FX
rate is pinned by `transactions.exchange_rate_id` and never enters the balance
check. `test/smoke_test.sql` posts exactly this and asserts it is accepted.

## Recorded design choices (not correctness claims)

Per the journal, these are **standards decisions**, equally correct alternatives
exist, and they are chosen for this design, not asserted as the only right way:

- **Plural table names** (`accounts`, `entries`, ...) vs the singular ERD entity
  names; columns stay singular (`transaction_id`, `wallet_id`).
- **Direction in `type`, positive `amount`** (journal T3) rather than a signed
  amount. A signed amount with a `CHECK` is equally valid.
- **`TEXT` + `CHECK` list** for enumerated values (`accounts.type`, `status`,
  `kind`, `entries.type`) rather than native `ENUM`. `transactions.type` is left
  as open `TEXT` because its vocabulary is spec-dependent.
- **Idempotency without Brandur `recovery_point`/`locked_at`** (journal T6):
  for a single atomic posting they add nothing; only `expires_at` is kept.

## Task 2 (query & performance) in the baseline

`entries` is created **monthly `RANGE (created_at)` partitioned** in
`initial/07_entry.up.sql`, with the physical PK `(entry_id, created_at)`, a
`create_entries_partition()` helper, a deterministic window of month partitions,
and a DEFAULT. The header carries a covering partial index for the settlement
report (`idx_transactions_settled_created`, `initial/06_transaction.up.sql`).
Journal section 3 folds these structural changes into the baseline rather than a
separate phase (greenfield/empty case); the **query-level** Task 2 artifacts (the
optimised report, the frozen-month rollup, and the reproducible benchmark) live
in [`../perf/`](../perf/).

> Converting an **already-populated** `entries` table to partitioned online (not
> the greenfield `CREATE` here) is a separate online migration, deliberately
> deferred. See journal section 3.
```
