// create_activity_audit.js
// Layer 3 activity audit (the Task 4 MongoDB use case) - create-collection script for mongosh.
//
//   mongosh "mongodb://<host>:27017" src/mongo/create_activity_audit.js
//
// This file just CONSOLIDATES the commands already reasoned through in
// docs/audit-l3-mongodb.md into one runnable script. It is not new design; the
// collection name (activity_audit), db (audit), sizes, role, and indexes are the
// same ones that document presents.
//
// Collection-type decision is DEFERRED (see ADR 0007 and the doc's "Collection
// type" section): three shapes are workable - (A) capped sized huge + resizable,
// (B) time-series + insert/find-only role, (C) regular + insert/find-only role +
// TTL. The human lean was to keep the capped approach sized extremely large, so
// THIS script implements option A as the active path; B and C are kept as
// commented alternatives so switching later is a one-block edit, not a rewrite.
//
// On the "oplog minimum-retention" idea that was raised for A: verified against
// the MongoDB manual that `oplogMinRetentionHours` is OPLOG-ONLY and does not
// apply to user capped collections. So a capped collection has no time-based
// retention floor; it truncates purely by size. Mitigate with: size large, grow
// with collMod (6.0+ preserves data), monitor utilization, and archive to a WORM
// store before it can ever wrap. That is the trade-off A accepts.

const DB_NAME = "audit";
const COLL = "activity_audit";

db = db.getSiblingDB(DB_NAME);

// ---------------------------------------------------------------------------
// 1. Create the collection (idempotent: skip if it already exists)
// ---------------------------------------------------------------------------
if (db.getCollectionNames().includes(COLL)) {
  print(`[skip] ${DB_NAME}.${COLL} already exists`);
} else {
  // --- Option A (ACTIVE): capped, sized huge and resizable --------------------
  // Engine-enforced immutability: a capped collection forbids deletes and
  // size-growing updates outright, so not even an admin can rewrite history.
  // Size for (peak event rate x retention window x safety factor); up to 1 PB.
  db.createCollection(COLL, { capped: true, size: 500000000000 /* 500 GB, example */ });
  print(`[ok] created capped ${DB_NAME}.${COLL}`);

  // Grow later WITHOUT losing data (trimming happens only on shrink). FCV >= 6.0.
  // db.runCommand({ collMod: COLL, cappedSize: 1000000000000 /* grow to 1 TB */ });

  // --- Option B (ALTERNATIVE): time-series, insert-optimized, shardable -------
  // db.createCollection(COLL, {
  //   timeseries: { timeField: "ts", metaField: "meta", granularity: "seconds" }
  // });

  // --- Option C (ALTERNATIVE): regular collection + TTL -----------------------
  // db.createCollection(COLL);
  // // TTL set to the compliance retention window (often years), never shorter:
  // db[COLL].createIndex({ ts: 1 }, { expireAfterSeconds: 220752000 /* ~7 years */ });
}

// ---------------------------------------------------------------------------
// 2. Immutability by privilege (the layer B and C rely on; defense-in-depth for A)
// ---------------------------------------------------------------------------
// The app connects as a role that can only insert and read - no update, no remove.
// For option A the storage engine already blocks rewrites; this still enforces
// least privilege (the app cannot drop or mutate either way).
if (db.getRole("auditAppender")) {
  print("[skip] role auditAppender already exists");
} else {
  db.createRole({
    role: "auditAppender",
    privileges: [{ resource: { db: DB_NAME, collection: COLL },
                   actions: ["insert", "find"] }],
    roles: []
  });
  print("[ok] created role auditAppender");
}

// ---------------------------------------------------------------------------
// 3. Indexes for the L3 access patterns (createIndex is idempotent)
// ---------------------------------------------------------------------------
db[COLL].createIndex({ idempotency_key: 1, ts: 1 });          // all attempts of one request
db[COLL].createIndex({ "meta.caller_id": 1, ts: -1 });        // one caller over a window
db[COLL].createIndex({ operation_id: 1 }, { sparse: true });  // bridge to the ledger; null on early reject
// A time-range scan uses the `ts` field directly (or the time-series timeField under option B).
print("[ok] indexes ensured");
