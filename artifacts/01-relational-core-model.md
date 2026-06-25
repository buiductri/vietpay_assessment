# Task 1: Relational core model

> Generated: 2026-06-25 | Axis: Relational core model | Primary sources: journal section 2, `docs/ERD.md`, `CONTEXT.md`, `src/ddl/`

This axis reorganizes the existing Task 1 material: the candidate's entity reasoning from the journal, the AI ERD expansion/audit changelog, and the generated DDL. Owned text is verbatim; AI work is marked and pointed at its committed deliverable.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content. This mirrors the journal's own human / `<ai>` split.

## TL;DR

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 2.1*

"But this transaction is not a real double-ledger transaction because it's double entries. So this **transaction** should be an **entry** in our model. So we expand the above **transaction** into 2 entities: **transaction** and **entry**. Each **transaction** has 2 **entries**, 1 `CREDIT` (+amount) and 1 `DEBIT` (-amount) that have a total sum of 0."

---

## Key Findings

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the candidate's own words, verbatim quotes from journal section 2.1*

- "Only a zero-sum transaction will COMMIT, so that our business requirement will be ensured."
- "create multiple wallets that stay true to their currency. In this case, the above example will have to include at least 4 wallets: A1_VND, FX_VND (house exchange wallet), FX_USD, A2_USD."
- "by enforcing unique on the key, we reject those requests that have an idempotency key already registered in the entity, and also map the request with the successful transaction."
- "I personally don't want to use a trigger for auditing because it will duplicate the load on our main database, and we don't have information in case of ROLLBACK ... So I will let the application handle the audit log".
- "Use fixed length number to represent money value, avoid floating point ... NUMERIC(19,4) for money value"; "ID will use UUID".

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *the audit pass, full changelog in `docs/ERD.md` and journal section 2.1*

- Closed the Task 1 "audit trail" gap with a Layer 2 in-Postgres `audit_log` (committed non-ledger state changes), keeping the rolled-back-attempt audit at Layer 3 (MongoDB).
- Tightened zero-sum to **per currency** (a currency-blind total can be fooled by cross-cancelling imbalances), and enforced currency consistency by a composite FK `entries (wallet_id, currency) -> wallets`.
- Generated the PostgreSQL DDL (eight entities + two reconciliation views + constraint/immutability triggers + least-privilege role), validated live on PostgreSQL 17.2.

---

## Detailed Analysis

### Entities: explore and reasoning

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 2.1 "Explore and reasoning"*

We start with the `transactions` table as the starting point:

```
transactions(id, wallet_id, type, amount, currency, status, created_at)
```

A **transaction** targets a **wallet**, has attributes: _type_ (`DEBIT`, `CREDIT`), _amount_, _currency_, _status_ (`SETTLED`), _created\_at_.
But this transaction is not a real double-ledger transaction because it's double entries. So this **transaction** should be an **entry** in our model. So we expand the above **transaction** into 2 entities: **transaction** and **entry**. Each **transaction** has 2 **entries**, 1 `CREDIT` (+amount) and 1 `DEBIT` (-amount) that have a total sum of 0.

```
[Transaction] ------- [Entry (CREDIT +)] --- [Wallet]
                 |--- [Entry (DEBIT  -)] --- [Wallet]
```

To enforce the zero-sum requirement of the double-entry ledger, we can have a trigger that checks for mismatch of newly added entries, or simply just query and check within a transaction. Any DB transaction that failed the check must be ROLLBACK. Only a zero-sum transaction will COMMIT, so that our business requirement will be ensured. The DB transaction also covers other business requirements like sufficient balance, whitelist, blacklist, etc.

From an **entry** point of view, the value of a **transaction** must be fixed and tied with the _currency_. In the case of a transaction between a VND wallet (A1) and a USD wallet (A2), the value is dependent on the exchange rate VND/USD and subject to changes. So we must derive a way to solve this. There are 2 solutions:
 - (1) decide a base currency and convert all transaction value into the base currency. This solution works well in a customer assets system but not in our case of a payment platform.
 - (2) create multiple wallets that stay true to their currency. In this case, the above example will have to include at least 4 wallets: A1_VND, FX_VND (house exchange wallet), FX_USD, A2_USD. The transaction then has 4 entries: (E1/2) transfer VND amount from A1_VND to FX_VND, (E3/4) transfer USD amount from FX_USD to A2_USD. This way the zero-sum requirement will be kept.

I will go with option (2), so we have multiple **wallets** that a **transaction** with appropriate currency will target and an **account** will have multiple **wallets** that serve for multiple currencies. We also can use this pattern to have holding wallets, which are for transfers that are being processed by external processes.

```
[Account] ------- [Wallet (USD)]
             |--- [Wallet Holding (USD)]
             |--- [Wallet (VND)]
             |--- [Wallet Holding (VND)]
```

For idempotent keys, the point of having them is to prevent duplication handling of a transaction, which means it always guarantees that a transaction request is only handled once. If a service accidentally retries or sends the same transaction request, the transaction is not duplicated. We can integrate this by having the **idempotency_key** entity that tracks the unique idempotency key, by enforcing unique on the key, we reject those requests that have an idempotency key already registered in the entity, and also map the request with the successful transaction. The idempotent key registration will be included in the DB transaction, so only a successful DB transaction will commit and the idempotent key will exist after COMMIT.

```
[Idempotency Key] ------ [Transaction]
```

For audit logging, I personally don't want to use a trigger for auditing because it will duplicate the load on our main database, and we don't have information in case of ROLLBACK because the trigger will handle inside the transaction and being rolled back too. So I will let the application handle the audit log, which sends the log with request idempotent key, transaction id, and if the DB rolls back, we still have information about that too. We can then offload the audit to an appropriate DBMS like MongoDB or just another PostgreSQL instance. There might be DBMS level that record audit, we need to have research on this.

After research, it seems like we don't have a clear answer on the compliance aspect, so we will introduce both trigger audit and external audit as a separate section for our final delivery. And as AI suggests in research, audit is not just recording transactions, it's for all other modifications on all of our entities.

There are some edge cases that I am thinking about:
- External process that holds the transaction in between state. This is where the holding wallet comes from, but the more I think about it, the more unclear it becomes to be integrated into our core system. This problem needs a more thorough analysis so I will skip them, there is no time. We just accept that the higher level transaction will be managed elsewhere, then if that transaction is invalid and needs to roll back, we add a new transaction to move money from holding back to the original wallet.

### Expanding the ERD: attributes and data-type standards

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 2.1 "Expand the base ERD to have more information"*

My core ERD only has base relationships, now we need to expand them to serve as real business mapping. Trivial fields like created_at, updated_at, etc. will not be mentioned unless necessary.

Since the ERD suggests we design datatype too, here are some rules that need to be followed:
- Use fixed length number to represent money value, avoid floating point; usually 4 decimal number is enough so we can use NUMERIC(19,4) for money value
- ID will use UUID, we can design it as fixed CHAR(n) or TEXT but since no specification, we keep UUID.

---

*The per-entity attribute lists the candidate wrote for account, wallet, transaction, entry, idempotency_key, exchange_rate, and currency are in journal section 2.1 and are realized in [`docs/ERD.md`](sources/01-relational-core-model/ERD.md).*

### ERD generation and the AI expansion/audit

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` blocks in journal section 2.1; full model in `docs/ERD.md`*

The ERD lives in two forms: [`docs/ERD.md`](sources/01-relational-core-model/ERD.md) (Mermaid diagram, entity tables, and the integrity rules) and `docs/ERD.html` (standalone visual artifact). It draws exactly the entities reasoned through above: account, wallet (including holding wallets), transaction, entry, and idempotency key, plus the zero-sum and idempotency rules.

After the base ERD, the AI expanded and audited the model against the fintech research and the assessment task. Every change was listed and approved one by one. In `docs/ERD.md` (footnotes) and `docs/ERD.html` (colour + badge) the markers are **AI-added** (`[^ai]`, violet `AI+`) and **AI-revised** (`[^air]`, violet `AI~`). The changelog (journal section 2.1) covers: T1 the Layer 2 `audit_log`; T2 per-currency zero-sum; T3 positive-amount encoding; T4 dropping `entry.status` and adding immutability; T5 the chart of accounts; T6 idempotency scoped to `(caller_id, key)`; T7 the FX-rate pinning; T8 currency consistency by composite FK; T9 the partitioning physical note; T10 the reconciliation rule. Several of these were corrected or reframed by the candidate's feedback, recorded verbatim below.

### Candidate feedback on the AI audit (owned, the human side of the split)

> **Human feedback (Bùi Đức Trí), on T3:** A `CHECK` constraint can already prevent the `type`/sign disagreement in the signed model, for example `CHECK ((type='CREDIT' AND amount>0) OR (type='DEBIT' AND amount<0))`. So T3 is **not** a safety fix: all three encodings (signed only; signed + CHECK; positive amount + `type`) are equally correct. Which one is "better" depends on team consensus and coding standards, not on objective correctness. I chose (c) for this design, and it should be recorded as a standards decision, not a bug fix.

> **Human feedback (Bùi Đức Trí), on T5:** An account holds both a normal wallet and a holding wallet (per currency); the holding wallet temporarily holds that account's balance while an external flow processes it. So "holding" is a wallet-level kind, not an account-level role, and a platform `SUSPENSE` account is the wrong abstraction here. The account role and the regular/holding distinction are orthogonal: role on `account.type`, spendable-vs-held on `wallet.kind`.

> **Human feedback (Bùi Đức Trí), on T6:** If the idempotency key is claimed inside the business transaction, a rollback releases it, and PostgreSQL crash-recovery rolls back any uncommitted transaction on restart, so a crash leaves no partial state. For a single atomic posting there is therefore no in-between state to recover, and `recovery_point`/`locked_at` have no role. They are valid only for a different design, a multi-step transaction whose steps commit separately (with non-rollback-able external calls between them), which is out of scope here and a separate redesign per the business flow. `expires_at` is worth keeping for a cleanup/watchdog process.

> **Human feedback (Bùi Đức Trí), on T7:** `exchange_rate_id` references the exact rate record at a point in time, not the latest rate, so the reference already pins the rate. The exchange value (amount x rate) is derivable from that record, i.e. duplicated, so I deliberately keep it in `extra_info` rather than as a normalized column. No typed `fx_rate` column is needed.

> **Human feedback (Bùi Đức Trí), on T9:** Keep the ERD logical first, but note what is going on. Surfaced the trade-off: a composite PK `(entry_id, created_at)` no longer makes `entry_id` unique on its own (the same id could repeat across partitions), and a plain secondary index on `wallet_id` does not need `created_at` (only UNIQUE/PK must include the partition key).

> **Human feedback (Bùi Đức Trí):** `audit_log` audits all entities, so a single drawn line to `transaction` is misleading (it reads as if it only relates to transactions), and drawing a line to every entity makes the ERD messy. Detach it: show it as a standalone entity with no relationship lines.

### DDL generation and deployment

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 2.2; deliverable in `src/ddl/`*

From the audited `docs/ERD.md` I generated the PostgreSQL DDL and packaged it as a one-time, rollbackable deployment under `src/ddl/`. The schema is the eight ERD entities (`currencies`, `exchange_rates`, `accounts`, `wallets`, `transactions`, `entries`, `idempotency_keys`, `audit_logs`) plus two reconciliation views, the per-currency zero-sum constraint trigger, the immutability triggers, and a least-privilege application role. Each guarantee is enforced by the schema, not by the application: per-currency zero-sum by a `DEFERRABLE INITIALLY DEFERRED` constraint trigger; currency consistency by the composite FK `entries (wallet_id, currency) -> wallets` against its `UNIQUE (wallet_id, currency)` target; idempotency by `UNIQUE (caller_id, key)`; immutability by `REVOKE` plus a deny trigger on `entries` and `audit_logs`; and the derived `wallets.balance` reconciled against `SUM(entries)` by the `balance_audit` view.

Structure: `src/ddl/initial/` holds twelve ordered steps, each an `NN_name.up.sql` with a matching `.down.sql`; `deploy.sh` is a small psql runner; `test/smoke_test.sql` is an executable spec that posts a balanced transfer and the four-entry FX bridge, then asserts the unbalanced, duplicate, immutable, currency-mismatch, and non-positive cases are all rejected. The scripts were authored against PostgreSQL 14+, validated offline with the real PostgreSQL parser (pglast), then run live against a provided PostgreSQL 17.2. The full lifecycle up -> verify -> test -> down -> re-up passes.

> **Human direction (Bùi Đức Trí):** Table names are plural (`accounts`, `entries`, ...), while the ERD keeps the singular entity names; this is a naming standard, not a correctness change. The one-time baseline lives in its own `initial/` folder, kept separate from later incremental deployment steps. A deployment-state table is required so that an accidental redeploy cannot break anything. The scripts were written first; PostgreSQL and a client were provided afterward to test them.

## Open Questions

*Deferred items, summarized from journal section 2.1 and `docs/ERD.md`. The candidate's verbatim is quoted.*

- The holding-wallet / external-process edge case: "This problem needs a more thorough analysis so I will skip them, there is no time." In-flight money is handled by per-account holding wallets; a fuller in-between-state model is deferred.
- Normalizing the `currency` string on `wallet`/`entry` onto the `currency` lookup is deferred (`docs/ERD.md`).

## Sources

[1] Design journal, section 2 (candidate's reasoning + interleaved AI changelog), verbatim - (local: sources/journal/00-journal.md)
[2] ER diagram, the audited model with AI+/AI~ markers - (local: sources/01-relational-core-model/ERD.md)
[3] Domain glossary, invariants, status machine - (local: sources/journal/CONTEXT.md)
[4] Task 1 DDL: 12-step up/down runner, smoke test - `src/ddl/` (repo)
