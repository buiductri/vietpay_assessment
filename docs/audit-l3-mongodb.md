# Layer 3 Activity Audit: a MongoDB Append-Only Event Log

> **AI-drafted deliverable.** This file realizes the author's plan, "L3 will be a MongoDB-style audit
> on another file" (see `../00-journal.md`, "ERD AI expansion and auditing", item T1), and builds on
> the author's own reasoning that audit data suits MongoDB (immutability via capped collections,
> schema-volatile logs; see the journal, section 2.1 and the introduction). It also doubles as the
> **Task 4 (polyglot / MongoDB)** use case, justified over a Postgres JSONB column.
> Source: `0-research/double-entry-ledger/06-audit-layers.md`.

## Where this fits: the three-layer audit model

"Audit" in a payments platform is not one thing. It is three concerns with opposite transactionality
requirements:

| Layer | Records | Store | In the business txn? | Survives rollback? |
|---|---|---|---|---|
| **L1 ledger** | money that actually moved | Postgres `entry` (immutable) | yes (required) | no (correct) |
| **L2 state-change** | committed non-ledger entity mutations | Postgres `audit_log` | yes | no |
| **L3 activity** | attempts, denials, replays, access | **MongoDB (this file)** | **no (out-of-band)** | **yes** |

The ERD (`ERD.md`) already models L1 (the immutable `entry` rows are their own audit) and L2
(`audit_log`). L3 is deliberately **not** a Postgres table: it must record events that the business
transaction *rolls back* (a denied transfer, an insufficient-funds attempt). An in-transaction row
cannot survive the rollback that erases the work, so the record of the attempt would vanish with it.
The attempt, including the denial, is exactly what AML, fraud, and access review care about, so it has
to live outside the business transaction.

## Why MongoDB over a Postgres JSONB column (Task 4)

A Postgres `JSONB` column would technically work. The reason not to is that it puts a high-volume,
schema-volatile, immutable, separately-retained audit stream **inside the same OLTP database that
serves the ledger**:

- **Workload isolation.** L3 is append-heavy and high-volume (every request, every denial, every access).
  Co-locating it with the ledger makes it compete for the ledger's I/O and buffer cache. A separate
  store keeps that write traffic off the hot transactional path.
- **Schema volatility.** Each `event_type` carries a different shape (an early validation reject has no
  `operation_id`; an `ACCESS` event has no `intent.amount`). A document store models heterogeneous,
  evolving events natively. With JSONB you get flexibility too, but you are effectively running a
  document store inside Postgres, and you couple the audit's schema evolution to ledger migrations.
- **Independent retention lifecycle.** AML retention is often multi-year, while the ledger's hot data is
  partitioned and pruned on a different schedule. Separating the stores lets each follow its own
  retention and archival policy.
- **Purpose-built immutability and time-series storage** (below), plus MongoDB's built-in replica-set HA,
  which the author notes as an underrated fit for an append-only log.

**When JSONB *would* be the right call:** low volume, a stable shape, and a need to join the audit row
to ledger rows in one transaction. That is not L3: it is high-volume, schema-volatile, and must be
written out-of-band. So this is a genuine "right tool for the job" split, not MongoDB by default.

## The event document

One collection, `activity_audit`. One document per event. Append-only; never updated.

```jsonc
{
  "event_id":        "f1c2...-uuid",       // unique per event
  "event_type":      "OPERATION_OUTCOME",  // see the set below
  "ts":              "2026-06-24T10:03:00.123Z",
  "meta": {                                // time-series grouping key (see "Collection type")
    "caller_id":   "A1",                   // the account that called
    "event_type":  "OPERATION_OUTCOME"
  },
  "request_id":      "req-A",              // one inbound attempt (new on every retry)
  "idempotency_key": "fx-A1-A2-20260624-001", // stable across retries of one logical request
  "actor":   { "principal": "A1", "ip": "203.0.113.4", "user_agent": "...", "session": "sess-9" },
  "intent":  { "type": "FX_TRANSFER", "from": "A1_VND", "to": "A2_USD", "amount": 1, "ccy": "USD", "rate": 27000 },
  "outcome":         "COMMITTED",          // ACCEPTED | REJECTED | COMMITTED | ROLLED_BACK | ERROR
  "reason":          null,                 // e.g. "INSUFFICIENT_FUNDS" when rejected/error
  "operation_id":    "ltxn-fx-001",        // = ledger_txn_id; null until the operation exists
  "latency_ms":      42
}
```

| Field | Type | Notes |
|---|---|---|
| event_id | UUID | unique per event |
| event_type | string | `REQUEST_RECEIVED`, `VALIDATION_REJECTED`, `IDEMPOTENT_REPLAY`, `OPERATION_OUTCOME`, `ACCESS` |
| ts | date | event time (the time-series `timeField`) |
| meta | object | `{ caller_id, event_type }`, the time-series `metaField` |
| request_id | string | one inbound HTTP attempt; new on each retry |
| idempotency_key | string | one logical request; stable across retries |
| actor | object | principal, ip, user agent, session |
| intent | object | the requested action; shape varies by `type` |
| outcome | string | `ACCEPTED`, `REJECTED`, `COMMITTED`, `ROLLED_BACK`, `ERROR` |
| reason | string | populated on reject/error |
| operation_id | string | the `ledger_txn_id` once known; null on an early reject |
| latency_ms | number | end-to-end latency for the attempt |

## Example events

**Successful FX transfer (two events, before and after the txn):**

```jsonc
// written BEFORE the DB transaction, recording intent
{ "event_type":"REQUEST_RECEIVED", "ts":"...:00.100Z", "request_id":"req-A",
  "idempotency_key":"fx-A1-A2-20260624-001", "meta":{"caller_id":"A1","event_type":"REQUEST_RECEIVED"},
  "intent":{"type":"FX_TRANSFER","from":"A1_VND","to":"A2_USD","amount":1,"ccy":"USD","rate":27000},
  "outcome":"ACCEPTED", "operation_id":null }

// written AFTER the txn resolves, reporting the REAL result
{ "event_type":"OPERATION_OUTCOME", "ts":"...:00.142Z", "request_id":"req-A",
  "idempotency_key":"fx-A1-A2-20260624-001", "meta":{"caller_id":"A1","event_type":"OPERATION_OUTCOME"},
  "outcome":"COMMITTED", "operation_id":"ltxn-fx-001", "latency_ms":42 }
```

**Rejected transfer (proves L3 survives rollback):** the DB transaction rolled back, so L1 and L2 are
empty and the idempotency key is released, but L3 still holds the attempt and the denial.

```jsonc
{ "event_type":"OPERATION_OUTCOME", "ts":"...", "request_id":"req-B",
  "idempotency_key":"fx-A1-A2-20260624-002", "meta":{"caller_id":"A1","event_type":"OPERATION_OUTCOME"},
  "outcome":"ROLLED_BACK", "reason":"INSUFFICIENT_FUNDS", "operation_id":null, "latency_ms":18 }
```

**Idempotent replay:** a retry of an already-completed request.

```jsonc
{ "event_type":"IDEMPOTENT_REPLAY", "ts":"...", "request_id":"req-C",
  "idempotency_key":"fx-A1-A2-20260624-001", "meta":{"caller_id":"A1","event_type":"IDEMPOTENT_REPLAY"},
  "outcome":"ACCEPTED", "operation_id":"ltxn-fx-001" }
```

## Correlation: joining an activity event back to the ledger

Three IDs thread the layers (see ERD `idempotency_key` and `audit_log`):

- `request_id` ties one attempt's events together (new on each retry).
- `idempotency_key` groups all retries of one logical request.
- `operation_id` (= the ledger `transaction_id`) is the bridge from an activity event into the ledger.

So forensics becomes:

- "every attempt on this transfer, including the rejected ones" -> filter L3 by `idempotency_key`.
- "what actually moved" -> L1 ledger by `operation_id`.
- "everything one user did in a window, committed or not" -> L3 by `meta.caller_id` plus a time range.

## Collection type, immutability, and retention (open decision)

The goal is **append-only (immutable) *and* full retention** (no silent loss of old events). Three shapes
are workable; the choice is **deferred**, to revisit once the expected event volume, concurrency, sharding
need, and the compliance retention period are known. They differ on *how* immutability and retention are
guaranteed:

| Option | Immutability | Retention | Scale (high volume) |
|---|---|---|---|
| **A. Capped, huge + resizable** | strongest, engine-enforced (no deletes, no size-growing updates, even an admin cannot rewrite) | size-based only; **no time floor**; mitigate with huge size + `collMod` growth + monitoring + archival | weaker: writes are serialized, and capped collections **cannot be sharded** |
| **B. Time-series + insert/find-only role** | by privilege (the role has no update/remove) | insert-optimized; TTL/archival on your schedule | strong: insert-optimized, compressed, shardable |
| **C. Regular + insert/find-only role + TTL** | by privilege | TTL expiry + archival; widest control | strong: shardable, widest index freedom |

### Option A - capped collection, sized huge and resizable

Its real advantage is **engine-enforced immutability**: a capped collection forbids deletes and
size-growing updates outright, so not even an admin can rewrite history, which is exactly the
tamper-evidence compliance likes.

```js
// cappedSize can be up to 1 PB. Size for (peak event rate x retention window x safety factor).
db.createCollection("activity_audit", { capped: true, size: 500000000000 /* 500 GB, example */ })

// MongoDB 6.0+: grow it later WITHOUT losing data (trimming happens only when you shrink).
// Requires featureCompatibilityVersion >= 6.0.
db.runCommand({ collMod: "activity_audit", cappedSize: 1000000000000 /* grow to 1 TB */ })
```

Caveats to design around:
- **No time-based retention floor.** A capped collection truncates purely by size; once full it overwrites
  the oldest events. The oplog's `oplogMinRetentionHours` (a time floor that lets it grow past its cap) is
  **oplog-only** and does not apply to user collections. So retention here is "size it large enough, monitor
  utilization, grow with `collMod`, and archive to WORM before it ever wraps", not a built-in guarantee.
- **Throughput and sharding.** Capped collections serialize writes (worse concurrent throughput) and
  **cannot be sharded**, which bounds horizontal scale.

### Option B - time-series collection + insert/find-only role

Insert-optimized and compressed for timestamped events, and shardable. Immutability is enforced by
privilege (below) rather than the storage engine.

```js
db.createCollection("activity_audit", {
  timeseries: { timeField: "ts", metaField: "meta", granularity: "seconds" }
})
```

### Option C - regular collection + insert/find-only role + TTL

The most flexible (widest index freedom, shardable); MongoDB's own docs suggest TTL on a regular
collection over capped for most "expire old data" needs. Immutability is again by privilege.

```js
db.createCollection("activity_audit")
// Optional TTL, set to the compliance retention window (often years), never shorter:
db.activity_audit.createIndex({ ts: 1 }, { expireAfterSeconds: 220752000 /* ~7 years */ })
```

### Immutability by privilege (Options B and C)

```js
// The app connects as a role that can only insert and read - no update, no remove.
db.createRole({
  role: "auditAppender",
  privileges: [{ resource: { db: "audit", collection: "activity_audit" },
                 actions: ["insert", "find"] }],
  roles: []
})
```

This is weaker than capped's engine-enforced immutability (a DBA superuser could still mutate), so pair it
with the system-of-record note below.

### The reframing that may decide it

Per doc 06, the **immutable system of record is the out-of-band stream / WORM archive** (the app emits to a
log pipeline / Kafka / SIEM, and compliance-grade immutability lives in WORM object storage with object
lock). This MongoDB collection is the **queryable projection** of that stream. If the hard immutability and
retention live in WORM, then the in-DB choice (A vs B vs C) is about query and throughput ergonomics, not
the ultimate guarantee, which makes B or C attractive without giving up tamper-evidence (it lives in WORM).

> Decision deferred. Criteria to settle it later: is engine-enforced immutability a hard requirement (favours
> A), is the event volume/concurrency high or does it need sharding (favours B/C), and where does the
> compliance system-of-record actually live (WORM archive relieves the in-DB immutability pressure).
> Verified facts behind this section, from the MongoDB manual: `oplogMinRetentionHours` is oplog-only;
> capped collections are resizable via `collMod` in 6.0+ (growth preserves data) but serialize writes and
> cannot be sharded; TTL indexes are the documented alternative for time-based expiry on a normal collection.

## Indexes (for the access patterns above)

```js
db.activity_audit.createIndex({ idempotency_key: 1, ts: 1 })      // all attempts of one request
db.activity_audit.createIndex({ "meta.caller_id": 1, ts: -1 })    // one caller over a window
db.activity_audit.createIndex({ operation_id: 1 }, { sparse: true }) // bridge to the ledger; null on early reject
// time-range scans use the time-series timeField (ts) directly
```

Indexes on measurement fields such as `idempotency_key` and `operation_id` need a recent MongoDB
(6.0+) on a time-series collection; on older versions, use the plain-collection alternative above.

## Writing it reliably (out-of-band, no dual-write divergence)

Log at honest boundaries:

- `REQUEST_RECEIVED` **before** the work, recording intent (who, what, when, idempotency key).
- `OPERATION_OUTCOME` **after** the transaction resolves, reporting the real DB result
  (`COMMITTED`, `ROLLED_BACK`, or `ERROR`).

The outcome event reflects what actually committed, so the log never claims "committed" for something
that rolled back. The source of truth for L3 is the durable out-of-band stream (the app emits to a log
pipeline / Kafka / SIEM); this MongoDB collection is the **queryable projection** of that stream. For a
stronger "no gaps" guarantee the app can write to MongoDB synchronously before responding, at the cost
of request latency, the trade-off is a deployment choice.

A transactional outbox is the wrong tool here: the outbox lives in the business transaction, so it dies
with the rollback too. Failed attempts need true out-of-band logging.

## Boundaries

- **Compliance specifics** (exact retention period, WORM requirement, who may read the log) come from the
  compliance and legal owners, not from this design. For a Vietnam payment intermediary that likely
  involves the State Bank of Vietnam non-cash payment regime and AML/CFT rules; treat those as items to
  confirm.
- **PII** in `actor` and `intent` may need redaction or tokenization, since the activity stream often
  lands in a SIEM with broader access than the OLTP database.
- **"Who ran what SQL"** is a separate concern, covered by `pgaudit` on the Postgres side, not by this
  application activity log.
