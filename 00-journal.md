This file serves as a detailed step-by-step journal of what I have done to resolve the assessment.

## 1. Assessment Analysis

### 1.1 Business Domain and Tech Stack

The assessment asks us to design a core data layer for fintech payments. This raises 2 issues for me: (1) I do not have experience with fintech and its terminology, and (2) the main tech stack is PostgreSQL, which we are studying, and it is not my main experience stack.

To cover our weaknesses here, we will utilize AI to help with the missing pieces. Then we will apply our previous knowledge about customer asset systems to resolve the given problem.

### 1.2. First impression

#### The transaction table
The transaction table has 50 million rows and receives an additional 2 million rows per month.

So we have about 24 months of data in the table. The context mentions that the query on the table is slow in production. Let's make some blind guesses here:
- There is no DDL provided, so we cannot pinpoint whether the table has indexes or not. For a production table, it should have indexes, so we need to guess which indexes are applied here.
- One of the biggest performance killers is a table scan without using an index, so if the query scans 50 million rows and then filters for 2 million rows to compute, this can be the problem.
- The query is an aggregate query, which means even though the number of rows returned is small (in this case the number of wallets), the query always needs to scan 2 million rows in order to compute the final result.

If this were SQL Server, we would have some solutions that could resolve the issue:
- The point of the query is to calculate the statement for all wallets that have been settled in a month. For historical data, the number rarely changes, so it is safe to pre-aggregate the result beforehand and save it into a set of reporting tables. We can then redirect the query to those tables.
- 24 months of data is very large, and should not be treated the same. In our previous system, we split the table into 2 physical ones. The first is a hot/live transaction table, prone to updates and with a large amount of DML. The second is an archived transaction table, where we move data if the data is older than a specified amount. Depending on the load, the time varies from 3 days to 1 or 2 months. For this example, we can safely serve a few million rows. And for the running month and previous month calculation, let's make it 2 months. The other 22 months will be saved inside an archived table for easier maintenance and tuning. (the live table and archived table have different index strategies). This also helps reduce our backup size on the main database, which is very important.

But we will use PostgreSQL for our assessment, so the insights above can be applied, but must be adjusted to adapt to PostgreSQL.

One of the biggest differences between SQL Server and PostgreSQL is the MVCC model of PostgreSQL. This model does not modify tuples in place; it instead creates a new tuple and updates the pointer to it. Because of this, there are no clustered indexes in PostgreSQL either. So we cannot use a clustered index strategy here.

PostgreSQL index scans also have a different mechanism here. Because multiple records of a tuple can exist, an index must fetch the data page to ensure it has the latest data value. This can be mitigated by ensuring the page is clean via fillfactor and the vacuum process. If we can ensure the page is clean, PostgreSQL can use an index-only scan to speed up the query.

The query pattern is an exact match on status and a range scan on created_at. Usually, index strategy follows exact, sort, scan priority. But in this case, we can argue that the status is mostly settled if we account for 1 month. So indexing status has limited benefit here. We also have group by wallet_id, which is sorting heavy. And finally, we have currency, which is a design problem. If currency is an attribute of wallet, we should not add it to group_by, instead we should use an aggregate in SELECT because for 1 wallet, currency is the same. But if we have multiple currencies in a wallet, the key here is composite and it makes the query harder. This will reflect in my core design later. I will lean toward keeping currency as an attribute.

So if we must use an index to improve our query, here are some options (the INCLUDE is optional, we need to test if index-only scan works or not):
- IX(wallet_id, created_at) INCLUDE (status, amount, currency) : This pattern works for customer-facing dashboards, because queries for customers always have wallet_id, so reporting every month is a trivial scan. But our query here focuses on summary by month for all wallets, so it will be hard for the planner to emit a plan that can utilize this index pattern. We can rewrite by selecting unique wallet_id, then joining with transactions to force the plan. But because PostgreSQL planning will focus on column statistics, the result might vary. In SQL Server, we have another problem where this query is a nested loop, which is a performance killer in some cases (not sure how the query plan in PostgreSQL will treat this).
- IX(created_at) INCLUDE (wallet_id, status, amount, currency) : This pattern focuses on the chronological order of transactions. This is an audit-centric pattern. But for our reporting query, this index will cover the exact number of records needed for the query, but wallet_id will then be useless in the key and will need to be sorted anyway, which is costly. I will refrain from using this unless necessary because the cost-benefit might not be good here. This also needs thorough testing. The reason wallet_id is not put in the index key is because created_at has seconds/milliseconds accuracy, so it always needs to be sorted again for group by. This is the main reason why we usually have different summary tables that pre-aggregate by year/month/day/hour for reporting purposes. I will lean into this solution more than using the index.
- Partition(created_at) & IX(wallet_id) : This is the best pattern because a range query by month will only touch the needed partition, including the index, so we can have the best of both worlds here: range query for only needed tuples + pre-order on wallet_id to skip sorting entirely. This also enables further management best practices using partitions.

#### Core model

The goal for this assessment is to expand from the transactions table as the entry point and deliver a full schema for the payment domain. This is a new domain for me, so I need to study to get the correct business understanding before continuing.

I can recognize most of the terms here, except the **double-entry ledger**. So I will use AI to run research on this topic so that we can have a deep understanding of this entity to design the best schema for it.

Delivery artifacts for this task are ERD and DDL in SQL format. I already have a way to visualize the ERD with the help of AI, so I will reuse it. SQL files also need to be executable so we can validate the schema. If we have time, we can use AI to generate a generator service that mimics the backend so we can have data in these tables for validation.

We already did a bit of the extra reasoning requirement when analyzing the transaction table; we can bring that over here.

#### Query & performance

Because we don't have much experience in PostgreSQL, the analysis in this section needs extra work so that I can understand how PostgreSQL planning works. This requires data to experiment with. We only have 2 days left, so we need to work fast here. AI can help, but I am not sure we can get it done in time, so we need to have some delivery artifacts first; deep analysis comes later.

#### Zero-downtime migration

This task introduces a new NOT NULL column, `settlement_batch_id`, and it needs to be updated live. The goal is to have zero-downtime deployment. Actually, the column name is just an example, so I can assume this task only cares about deployment planning. So I can safely skip the business aspect of the column and focus on deployment steps only.

With the above assumption in mind, the task becomes creating a base script for deployment and some basic business requirements for the value (because NOT NULL), so that we can populate data (backfill) for this new column.

Live deployment with zero downtime needs extra care around the internal workings of PostgreSQL. Some of the most important items are: locking, long-running queries, vacuum process, fillfactor, transaction commits and rollbacks.

Like always, we need to control the state of deployment via each step. MongoDB is a bit easier since the schema is flexible. PostgreSQL needs extra care in DDL, so keep that in mind.

One of the items we need to explain is the application point of view. The deployment step needs extra care so it does not break the old version of the application. Usually, I want database deployment to be as independent as possible. So the best way is to have a 3-stage deployment: (1) introduce the new column without a constraint; (2) deploy the application that will populate data into the new column without showing new changes yet (this can be a transitioning version or a feature flag that is turned off; I prefer the second); (3) backfill data and enforce the constraint before turning on the feature flag (or deploying the final application). This needs extra collaboration with the application side, so we might need another plan in case the above assumption is wrong.

#### Polyglot modelling

The task is to expand data modelling into other DBMSs. I have experience in MongoDB, so that part is easy. Neo4j needs some understanding of graph theory, which I lack a bit. But the core concept is still the same: the best tool for the job.

For MongoDB, its strongest points are the dynamic schema approach and document-centric design. With its self-developed physical data representation, BSON, MongoDB makes good use of document storage and the aggregation framework. One other strong point that most people miss is that MongoDB has a built-in HA solution, which most RDBMSs lack, so it is not only about the data modeling aspect; some administrative considerations must be assessed too, but this is outside of the task, so I will skip it. Most people use MongoDB to store logs only. This is understandable because logs are very schema-volatile, so the flexible schema approach is best used here. Also for auditing purposes, compliance usually requires the underlying data to be immutable. MongoDB has capped collections that forbid all updates on the collection. Even the root account cannot modify the data without dropping and repopulating data, so storing audit data in MongoDB has this advantage too. The latest MongoDB has time series collections and clustered collections, so if we have data that requires these features, we can consider using MongoDB.

For Neo4j, the best use for it is, of course, graph problems such as relationship mapping or fraud detection. I lack some basic knowledge about real-world graph problems, so I need to run some research for it too.

#### Observability

For the monitoring aspect, we must approach it from 2 aspects: technical and business.

For the technical side, all basic metrics related to PostgreSQL and its performance need to be captured. So we start with basic metrics for all DBMSs: CPU, memory, I/O, internal logs (for PostgreSQL: WAL logs), locking/waiting, connections, cache hits/misses, and index utilization. Then focus on PostgreSQL-specific metrics: vacuum, dead tuples, and transaction IDs.

For the business side, we need to monitor query and procedure duration, especially around core business flows. But for this aspect, we don't have much context, so this needs more thought later.

#### Design write-up

Our analysis can cover most of the ADR here, but the task requires some more thought about standards and the microservices aspect, so I need to cover them too.

#### Tools

- I am very familiar with MongoDB and Grafana.
- I am not as familiar with PostgreSQL and Neo4j since I have not had the chance to actually maintain those services in production yet, but I have some knowledge about them; so I need to study more.
- About Flyway and Liquibase, I have no idea, so my approach will be ad hoc scripts first, then have AI do some search for me about these systems to see if I can grasp the gist of these systems or not.

### 1.3. Journal audit / feedback

The audit shows my lack of knowledge of PostgreSQL. This is good, it gives me a pointer on how to address my gap here. Most of the clarification is for things I already know or awareness of what I lack. Some of it is kind of a misunderstanding because my thought wording is not clear enough, not that I do not know about that part, but I kind of forgot to include it in the thought. It's good to know how to clarify the thought. The final part is what the AI already assumes, like settlement; I will ignore this because of my lack of domain knowledge and stick to the technical aspect of the task. Lack of knowledge is not a bad thing; relying on AI for what I don't know is bad.

## 2. Core design

### 2.1 Entities

#### Explore and reasoning

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


#### Generate ERD

I will use AI to draw ERD for me based on above reasoning.

<ai>
The ERD lives in two forms:

- [`docs/ERD.md`](./docs/ERD.md) - Mermaid diagram, entity tables, and the integrity rules from this reasoning (renders on GitHub).
- [`docs/ERD.html`](./docs/ERD.html) - standalone, offline visual artifact (open in a browser).

It draws exactly the entities reasoned through above: account, wallet (including holding wallets), transaction, entry, and idempotency key, plus the zero-sum and idempotency rules. FX uses multiple currency-pure wallets and house exchange wallets, and audit stays at the application/MongoDB level, so neither adds an entity here.
</ai>

#### Expand the base ERD to have more information

My core ERD only has base relationships, now we need to expand them to serve as real business mapping. Trivial fields like created_at, updated_at, etc. will not be mentioned unless necessary.

Since the ERD suggests we design datatype too, here are some rules that need to be followed:
- Use fixed length number to represent money value, avoid floating point; usually 4 decimal number is enough so we can use NUMERIC(19,4) for money value
- ID will use UUID, we can design it as fixed CHAR(n) or TEXT but since no specification, we keep UUID.

##### **Account**: 
- name
- type (customer, system)
- status (active, closed)
- other references or attributes depend on specification
- trivial fields

##### **Wallet**:
- name
- balance: this field is calculated within transaction, but never source of truth
- status (active, closed)
- trivial fields

##### **Transaction**:
- type: enum based on specification (transfer, exchange, fee, etc.)
- status: (running, pending, completed, etc.)
- exchange_id: this field can link to an exchange rate table that tracks rate every day (e.g. OANDA)
- created_at: time commit transaction
- description:
- extra_info: detailed info (like in multiple currency transaction, system fee, exchange value, etc.), json format

##### **Entry**:

##### **Idempotency Key**
- caller_id: the id of request initial entity, like customer account or system account
- request_id: the api request id, this is different from idempotency key

##### **Exchange Rate**
This is an extra entity that holds the exchange rate of a date/time. The schema might vary between providers. But I will use OANDA as a reference:
- exchange_rate_id
- exchange_date
- base_currency/base_currency_id
- currency/currency_id
- rate

##### **Currency**
- currency_id
- name
- code

#### ERD AI expansion and auditing

<ai>
After the Section 2.1 base ERD, I had the AI expand and audit the model against the
fintech research (the `0-research/double-entry-ledger` and `0-research/vp-assessment-dba`
axes) and against the assessment task itself. Every change was listed and approved one by
one before being applied. This subsection is the changelog, so my original Section 2.1
work stays visible next to each AI change.

**Markers** used in `docs/ERD.md` (footnotes) and `docs/ERD.html` (colour + badge):

- **AI-added** (`[^ai]`, violet `AI+` badge): a new entity, column, relationship, or rule
  that was not in my Section 2.1 work.
- **AI-revised** (`[^air]`, violet `AI~` badge): an existing field or rule of mine whose
  value or wording was changed. The original is recorded in this changelog.

The ERD files carry only the model plus those markers; the rationale and any replaced
original values live here.

##### Changelog

**T1 - Add the Layer 2 `audit_log` entity** *(AI-added)* - source:
`0-research/double-entry-ledger/06-audit-layers.md`

- Task 1 requires "an audit trail" inside the relational core model. My Section 2.1
  deferred all audit to the application / MongoDB level, so the relational schema had no
  audit table at all. This closes that gap.
- Audit is three layers (doc 06). **Layer 1** is the ledger entries themselves (already
  modelled, immutable, their own audit). **Layer 2** is an in-Postgres `audit_log` for
  committed state changes to *non-ledger* entities (wallet freeze, KYC tier, limit
  changes), written in the same transaction as the change. **Layer 3** is the
  attempts/denials/access activity log, which stays out-of-band.
- This does **not** reverse my decision to keep audit out of triggers and at the
  application/MongoDB level. The in-DB `audit_log` records only committed state changes;
  the rolled-back-attempt audit I argued for remains the Layer 3 MongoDB event log,
  modelled in a separate file (it doubles as the Task 4 MongoDB use case), not in this ERD.

**T2 - Zero-sum invariant is per currency** *(AI-revised + AI-added example)* - source:
`0-research/double-entry-ledger/07-multi-currency.md`

- My original Section 2.1 rule read: "Each transaction's entries sum to zero (one CREDIT
  +amount, one DEBIT -amount, or more for FX)."
- Revised to: within each currency, `SUM(amount WHERE type=DEBIT) = SUM(amount WHERE
  type=CREDIT)`.
- Why per currency (corrected after discussion): a valid 4-entry FX transfer in the bridge
  model *does* sum to zero globally, so the point is not that valid transactions fail a
  global check. The point is that a currency-blind total can be fooled: a per-currency
  imbalance in one currency can cross-cancel an imbalance in another and still net to a
  balanced global total (for example a 2-entry 27,000 VND debit vs 27,000 USD credit passes
  a global check but leaks roughly 27,000x value). The per-currency check is strictly
  stronger and cannot be fooled this way, which is the "by construction, not by hope" bar.
- This aligns with my own FX choice (section 2.1, option 2: currency-pure wallets plus
  house FX wallets). I also added a 4-entry FX-bridge worked example to `docs/ERD.md`.

**T3 - Entry direction: positive `amount`, direction in `type` (option c)** *(AI-revised)* -
source: `0-research/double-entry-ledger/03-schema-design.md`

- My original `entry.amount` note read: "signed: + for CREDIT, - for DEBIT".
- Revised to: `amount` is a positive magnitude with `CHECK (amount > 0)`; direction lives
  only in the `type` column. T2's per-currency wording is unchanged by this.
</ai>

> **Human feedback (Bùi Đức Trí), on T3:** A `CHECK` constraint can already prevent the
> `type`/sign disagreement in the signed model, for example
> `CHECK ((type='CREDIT' AND amount>0) OR (type='DEBIT' AND amount<0))`. So T3 is **not** a
> safety fix: all three encodings (signed only; signed + CHECK; positive amount + `type`)
> are equally correct. Which one is "better" depends on team consensus and coding
> standards, not on objective correctness. I chose (c) for this design, and it should be
> recorded as a standards decision, not a bug fix.

<ai>
**T4 - Drop `entry.status`; lifecycle on `transaction.status`; entries immutable**
*(AI-revised + AI-added rule)* - source:
`0-research/double-entry-ledger/06-audit-layers.md`, `05-integrity-guarantees.md`

- My Section 2.1 had a `status` on both `transaction` ("running/pending/completed") and
  `entry` ("SETTLED") - redundant, and with two different vocabularies that can drift.
- Dropped `entry.status`: an entry is an immutable fact, not something with its own
  lifecycle. Lifecycle now lives only on `transaction.status`, formalized to
  `PENDING`/`SETTLED`/`REVERSED` (the vocabulary is a spec choice; this set was approved).
- Added an immutability rule: `entry` is append-only (`REVOKE UPDATE, DELETE`); an undo is
  a new reversing transaction (`REVERSED`), never an edit or delete. The entries are
  themselves the lifecycle audit, which is why no per-entry status is needed.

**T5 - Chart of accounts on `account.type`; `wallet.kind` kept** *(AI-revised)* - source:
`0-research/double-entry-ledger/03-schema-design.md`, `07-multi-currency.md`

- Expanded `account.type` from `customer`/`system` to the chart of accounts: `CUSTOMER`,
  `PLATFORM_FLOAT`, `PLATFORM_REVENUE`, `MERCHANT_PAYABLE`, `FX_POSITION`. The platform
  accounts are what let a fee, a top-up, or an FX leg balance.
- I first proposed putting this role on `wallet` (`wallet.account_type`) and dropped it
  after the human feedback below: the name collided with the `account` entity, and holding
  is a wallet-level concept that cannot live at account level.
- `wallet.kind` (`regular`/`holding`) kept as-is; no role column on wallet. `SUSPENSE` was
  dropped from the chart of accounts because in-flight money is handled by per-account
  holding wallets, not a central suspense account.
</ai>

> **Human feedback (Bùi Đức Trí), on T5:** An account holds both a normal wallet and a
> holding wallet (per currency); the holding wallet temporarily holds that account's
> balance while an external flow processes it. So "holding" is a wallet-level kind, not an
> account-level role, and a platform `SUSPENSE` account is the wrong abstraction here. The
> account role and the regular/holding distinction are orthogonal: role on `account.type`,
> spendable-vs-held on `wallet.kind`.

<ai>
**T6 - Idempotency scoped to `(caller_id, key)`; lifecycle fields dropped; `expires_at`
kept** *(AI-revised + AI-added field)* - source:
`0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`

- Changed the unique constraint from a global `key` to `UNIQUE (caller_id, key)`:
  client-supplied keys are only unique per caller, so dedup must be scoped per caller.
- I initially proposed Brandur-style lifecycle fields (`recovery_point`, `locked_at`,
  `response_code`/`response_body`) and dropped them after the human feedback below: for a
  single atomic posting they add nothing.
- Kept only `expires_at`, a retention marker so a cleanup/watchdog job can sweep keys past
  the retry window and keep the table bounded. Operational, not correctness.
- Edge case (noted in `docs/ERD.md` too): a multi-step flow whose steps commit separately,
  with non-rollback-able external calls between them, *would* need the lifecycle state. It
  is out of scope here; if required we redesign or extend the structure per the
  business-flow consensus.
</ai>

> **Human feedback (Bùi Đức Trí), on T6:** If the idempotency key is claimed inside the
> business transaction, a rollback releases it, and PostgreSQL crash-recovery rolls back any
> uncommitted transaction on restart, so a crash leaves no partial state. For a single atomic
> posting there is therefore no in-between state to recover, and `recovery_point`/`locked_at`
> have no role. They are valid only for a different design, a multi-step transaction whose
> steps commit separately (with non-rollback-able external calls between them), which is out
> of scope here and a separate redesign per the business flow. `expires_at` is worth keeping
> for a cleanup/watchdog process.

<ai>
**T7 - FX rate: `exchange_id` -> `exchange_rate_id` (typo fix); pinning documented**
*(typo fix + note clarification, no design change, no AI marker)* - source:
`0-research/double-entry-ledger/07-multi-currency.md`

- Renamed `transaction.exchange_id` to `exchange_rate_id` to match the referenced PK
  (`exchange_rate.exchange_rate_id`). This was a typo, not a design change, so no marker.
- Sharpened the note: the FK points to the exact point-in-time rate record, which is
  immutable, so the rate is pinned and a retry is deterministic.
- Dropped my earlier proposals (a typed `fx_rate` column; reframing the FK as a mere "rate
  source"). Both were wrong, see the human feedback below; the exchange value stays in
  `extra_info` as intentional denormalization.
</ai>

> **Human feedback (Bùi Đức Trí), on T7:** `exchange_rate_id` references the exact rate
> record at a point in time, not the latest rate, so the reference already pins the rate.
> The exchange value (amount x rate) is derivable from that record, i.e. duplicated, so I
> deliberately keep it in `extra_info` rather than as a normalized column. No typed
> `fx_rate` column is needed.

<ai>
**T8 - Currency consistency by composite FK** *(AI-added)* - source:
`0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`

- Gap: nothing stopped an `entry.currency` from differing from its wallet's, even though a
  wallet is single-currency.
- Chose option A (keep `entry.currency` for the per-currency check and partition/query, and
  as an immutable record) over option B (drop it and join to wallet). Enforced consistency
  by construction: `wallet` gets `UNIQUE (wallet_id, currency)`, and `entry` gets a composite
  FK `(wallet_id, currency)` -> `wallet`.
- Because `wallet_id` is the wallet PK (one currency per wallet), the composite FK makes a
  mismatched currency impossible. Caveat recorded: both entry FK columns are `NOT NULL`, or
  the default `MATCH SIMPLE` would skip the check on a NULL.

**T9 - Entry partitioning kept logical in the ERD, with a physical note** *(AI-added note)* -
source: `0-research/double-entry-ledger/03-schema-design.md`

- Decision (human, below): keep the ERD logical with `entry` PK = `entry_id`, and add a note
  documenting the physical consequence rather than changing the PK here. The partitioning
  detail itself stays in Task 2.
- Note added to `docs/ERD.md`: under monthly range partitioning on `created_at`, the physical
  PK becomes `(entry_id, created_at)` (PostgreSQL requires the partition key in the PK), so
  `entry_id` is then unique only with `created_at`. Safe here: `entry_id` is a UUID and
  nothing FKs into `entry`. Non-unique secondary indexes (e.g. `wallet_id`) need no
  `created_at`.
</ai>

> **Human feedback (Bùi Đức Trí), on T9:** Keep the ERD logical first, but note what is going
> on. Surfaced the trade-off: a composite PK `(entry_id, created_at)` no longer makes
> `entry_id` unique on its own (the same id could repeat across partitions), and a plain
> secondary index on `wallet_id` does not need `created_at` (only UNIQUE/PK must include the
> partition key).

<ai>
**T10 - Reconciliation rule for the cached balance** *(AI-added rule)* - source:
`0-research/double-entry-ledger/05-integrity-guarantees.md`

- Added one integrity rule: a scheduled `balance_audit` compares each wallet's cached
  `balance` against `SUM(entries)` for that wallet and alerts on any nonzero discrepancy.
  This makes "balance is never the source of truth" operationally verifiable.
- Rule only, no schema change. The author plans to develop the detailed checks and alerting
  further later (Task 5, observability).
</ai>

<ai>
**L3 audit file - `docs/audit-l3-mongodb.md` created** *(AI-drafted deliverable)* - source:
`0-research/double-entry-ledger/06-audit-layers.md`

- Realizes the plan that the Layer 3 activity audit (attempts, denials, replays, access) is a
  MongoDB append-only event log in a separate file (see T1). It also serves as the Task 4
  MongoDB use case, justified over a Postgres JSONB column.
- Collection type is left as an open decision in the file, presenting all three options
  (A: capped sized huge + resizable; B: time-series + insert/find-only role; C: regular +
  role + TTL), to revisit later. Verified facts that shaped it: the oplog's minimum-retention
  (`oplogMinRetentionHours`) is oplog-only and does not apply to user capped collections;
  capped collections are resizable via `collMod` in 6.0+ (growth preserves data) but serialize
  writes and cannot be sharded.
</ai>

> **Human feedback (Bùi Đức Trí), on the L3 collection type:** Try to keep the capped-collection
> approach by sizing it extremely large, and check whether the oplog's minimum-retention-time
> idea can be applied here. Outcome (verified against the MongoDB manual): the huge + resizable
> sizing is viable and mitigates overwrite, but the oplog min-retention feature is oplog-only, so
> a user capped collection has no built-in time floor. Decision deferred; all options were written
> to the file for now.

<ai>
**Audit_log detached from relationships** *(AI-revised, per human direction)* - source:
`0-research/double-entry-ledger/06-audit-layers.md`

- Removed the drawn `transaction -> audit_log` relationship from `docs/ERD.md` and
  `docs/ERD.html`: the Mermaid relationship line, the SVG connector and its labels, and the
  relationships-table rows.
- `audit_log` is now a detached entity. It audits all entities through the polymorphic
  `(entity_type, entity_id)` pair (not a drawable FK); `transaction_id` stays as an optional
  operation pointer but is no longer drawn as a relationship.
</ai>

> **Human feedback (Bùi Đức Trí):** `audit_log` audits all entities, so a single drawn line to
> `transaction` is misleading (it reads as if it only relates to transactions), and drawing a line
> to every entity makes the ERD messy. Detach it: show it as a standalone entity with no
> relationship lines.
