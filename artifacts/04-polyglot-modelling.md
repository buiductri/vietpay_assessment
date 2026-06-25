# Task 4: Polyglot modelling

> Generated: 2026-06-25 | Axis: Polyglot modelling (MongoDB + Neo4j) | Primary sources: journal section 5, `docs/audit-l3-mongodb.md`, `src/mongo/create_activity_audit.js`

This axis reorganizes the existing Task 4 material. The candidate is explicit about uneven confidence: the MongoDB reasoning is his own; the Neo4j model and Cypher are AI-composed from research he commissioned. That asymmetry is preserved below.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content. This mirrors the journal's own human / `<ai>` split.

## TL;DR

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 5*

"the core idea is the same one I keep coming back to: the best tool for the job, chosen by the property of the workload, not by trend. ... MongoDB I know from production, so the MongoDB reasoning below is mine. Neo4j I do not have production experience with, and I lack some of the graph-theory grounding, so I commissioned research first and then had the AI compose the graph model and the Cypher from it. ... the MongoDB half is mostly my own thought, the Neo4j model and queries are AI-composed from the research I asked for."

---

## Key Findings

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the candidate's own words, verbatim quotes from journal section 5.1 and 5.2*

- "it must record the events that the business transaction *rolls back* (a denied transfer, an insufficient-funds attempt). A row written inside that transaction dies with the rollback ... That forces Layer 3 out-of-band, and an append-only document store is the natural home."
- "the audit stream is schema-volatile (each event type is a different shape) and it has to be immutable."
- "prove this is *genuinely* a graph problem and not Neo4j-by-trend, because that is literally the rubric ("right tool for the job, with clear justification")."
- "PostgreSQL stays the system of record; the graph is a downstream, rebuildable, derived store, never the financial source of truth."

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *the deliverables: `docs/audit-l3-mongodb.md`, `src/mongo/create_activity_audit.js`, and the Neo4j model/Cypher*

- The full "why MongoDB over a Postgres JSONB column" answer adds workload isolation, independent retention lifecycle, and the honest boundary where JSONB wins.
- The L3 event document, three correlation IDs, and the three collection-type options (capped huge / time-series / regular+TTL), with the choice deferred.
- The fraud-ring graph model and two Cypher queries (cycle detection, WCC community detection).

---

## Detailed Analysis: MongoDB (the candidate's own reasoning)

### Why MongoDB, and the Layer 3 audit use case

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 5.1*

For MongoDB, its strongest points are the dynamic schema approach and document-centric design. With its self-developed physical data representation, BSON, MongoDB makes good use of document storage and the aggregation framework. One other strong point that most people miss is that MongoDB has a built-in HA solution (replica sets), which most RDBMSs lack, so the choice is not only about the data modelling aspect; some administrative considerations come with it too, but that is outside this task so I will not push on it here.

Most people reach for MongoDB to store logs, and that is understandable: logs are very schema-volatile, so the flexible schema is best used there. The angle that matters more for a payments platform is auditing. Compliance usually requires the underlying audit data to be immutable, and MongoDB has capped collections that forbid all updates on the collection. Even the root account cannot modify the data without dropping and repopulating it, so storing audit data in MongoDB carries that tamper-evidence advantage on top of the schema fit. The latest MongoDB also has time-series collections and clustered collections, so if the data wants those access patterns (high-frequency timestamped events), that is another reason to consider it.

This is exactly why I put the **Layer 3 activity audit** in MongoDB, and it is the use case I choose for this task (the requirement offered raw webhook capture or an append-only audit log as examples; I take the audit log, since we have already worked through it in Task 1). The three-layer audit was settled in the core design: Layer 1 is the immutable ledger entries (their own audit), Layer 2 is the in-Postgres `audit_log` for committed non-ledger state changes, and Layer 3 is the append-only activity stream of attempts, denials, replays, and access. Layer 3 is the one that does not belong in Postgres, and the reason is sharp: it must record the events that the business transaction *rolls back* (a denied transfer, an insufficient-funds attempt). A row written inside that transaction dies with the rollback, so the record of the attempt would vanish exactly when AML and fraud review need it. That forces Layer 3 out-of-band, and an append-only document store is the natural home.

So my own reason for putting Layer 3 in MongoDB rather than a Postgres JSONB column comes down to the two properties I already trust it for: the audit stream is schema-volatile (each event type is a different shape) and it has to be immutable. The fuller, structured "why over JSONB" answer (the explicit ask) and the honest boundary where JSONB is actually the better call are in the AI block below, because that side-by-side comparison came out of the research, not my own prior reasoning, and I would rather mark it than pass it off as mine.

### The full "why over JSONB" answer

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 5.1; full deliverable in `docs/audit-l3-mongodb.md`*

**The deliverable that already exists:** [`docs/audit-l3-mongodb.md`](sources/04-polyglot-modelling/audit-l3-mongodb.md) (AI-drafted, realizing the author's plan). It carries the three-layer table, the event-document schema (one `activity_audit` collection, one document per event), worked examples that prove L3 survives a rollback that empties L1/L2, and the three correlation IDs (`request_id`, `idempotency_key`, `operation_id`) that thread an activity event back to the ledger.

Beyond the author's own two points (schema volatility, immutability), the research adds two more and a boundary:

- **Workload isolation.** L3 is append-heavy and high-volume (every request, every denial, every access). Co-locating it as a JSONB column inside the ledger's OLTP database makes it compete for the ledger's I/O and buffer cache; a separate store keeps that write traffic off the hot path.
- **Independent retention lifecycle.** AML retention is often multi-year, while the ledger's hot data is partitioned and pruned on a different schedule. Separate stores let each follow its own retention and archival policy.
- **The honest boundary (when JSONB wins).** Low volume, a stable shape, and a need to join the audit row to ledger rows in one transaction. Layer 3 is none of those, so this is a genuine right-tool split, not Mongo-by-default.

The file also records the reframing that de-risks the in-DB choice: the compliance system of record is really a WORM archive fed by an out-of-band stream (Kafka/SIEM), and this collection is the *queryable projection* of that stream, so the A/B/C collection-type choice is about query and throughput ergonomics, not the ultimate guarantee.

> **Human direction / feedback (Bùi Đức Trí):** Keep exploring the capped-collection approach by sizing it extremely large, and check whether the oplog's minimum-retention-time idea applies here. Outcome (verified against the MongoDB manual): the huge + resizable sizing is viable and mitigates overwrite, but `oplogMinRetentionHours` is oplog-only, so a user capped collection has no built-in time floor. So the collection-type decision (A: capped huge + resizable; B: time-series + insert/find-only role; C: regular + role + TTL) stays **deferred**, to settle once the event volume, sharding need, and the compliance retention period are known. All three are written into the file; capped is the leading option because engine-enforced immutability (not even an admin can rewrite history) is the property compliance likes most.

### The runnable create-collection script

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 5.1; deliverable `src/mongo/create_activity_audit.js`*

`src/mongo/create_activity_audit.js`, runnable in `mongosh`. It is a consolidation of the commands already in the L3 doc into one re-runnable file: it creates the capped `audit.activity_audit` collection (option A, the leading choice, with the time-series and regular+TTL shapes kept as commented alternatives), the insert/find-only `auditAppender` role (least privilege), and the three access-pattern indexes (`{idempotency_key, ts}`, `{meta.caller_id, ts}`, sparse `{operation_id}`). The script is idempotent and carries the oplog-min-retention finding as a header comment. Syntax validated with `node --check`.

## Detailed Analysis: Neo4j (AI-composed from commissioned research)

### The candidate's framing

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 5.2*

For Neo4j, the best use is, of course, graph problems such as relationship mapping or fraud detection. I lack some basic knowledge about real-world graph problems, so I ran research for this part (`0-research/neo4j-graph-fintech/` for the fintech application and `0-research/graph-problem-patterns/` for the domain-agnostic "what even is a graph problem" grounding). The one thing I insisted on before accepting any model: prove this is *genuinely* a graph problem and not Neo4j-by-trend, because that is literally the rubric ("right tool for the job, with clear justification"). And the same boundary as everywhere else in this design holds: PostgreSQL stays the system of record; the graph is a downstream, rebuildable, derived store, never the financial source of truth. Past that point, the model and the Cypher are AI-composed from the research, so I have put them in an AI block rather than claim them as my own reasoning.

### The graph model and Cypher

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 5.2*

**Is it genuinely a graph problem (the litmus the author asked for).** The sharpest single test from the pattern research: if you remove most of the edges and the application still works, it is not a graph problem; if the edges *are* the application, it is. A fraud ring passes hard: one transaction at a time looks benign, and the fraud exists *only* in the connection structure (A pays B pays C pays A). Two more tells also fire: the query follows a **variable, unknown number of hops**, and the answer is **structural** (a cycle, a cluster) rather than a row. In relational terms each hop is a self-join, so an N-hop ring is an N-way recursive join whose cost explodes; a graph database uses index-free adjacency, so each hop is a pointer traversal that stays cheap.

**The property-graph model.** A derived projection fed from the Postgres ledger and the KYC/PII side:

```
(:Account {id, name, risk_score})
(:Card    {fingerprint})
(:Device  {id})

(:Account)-[:TRANSFERRED {amount, currency, at, txn_id}]->(:Account)   // derived from the ledger
(:Account)-[:REFERRED]->(:Account)                                     // referral network
(:Account)-[:USED]->(:Card)                                            // shared-PII link
(:Account)-[:LOGGED_IN_FROM]->(:Device)
```

**Tie-back to our schema (why this is not a foreign model).** Neo4j's canonical fraud-ring model reifies each money movement as a `Transaction` node sitting *between* two accounts. That is literally the model we already built in Task 1: a `transaction` header with two balancing `entry` lines against wallets. So the graph is a projection of the ledger, not a new design.

**Cypher 1 - fraud ring (cycle detection).** Money that flows in a cycle back to its origin inside a window, each hop within 20% of the previous amount (the layering fee a mule skims):

```cypher
MATCH path = (a:Account)-[:TRANSFERRED*2..6]->(a)
WHERE all(r IN relationships(path) WHERE r.at >= datetime('2026-06-01T00:00:00Z'))
  AND all(i IN range(0, size(relationships(path)) - 2)
          WHERE relationships(path)[i+1].amount >= 0.80 * relationships(path)[i].amount)
WITH a,
     [n IN nodes(path) | n.id] AS ring,
     reduce(total = 0.0, r IN relationships(path) | total + r.amount) AS cycle_volume
RETURN a.id AS ring_seed, ring AS accounts_in_ring, cycle_volume
ORDER BY cycle_volume DESC
LIMIT 50;
```

The variable-length pattern `[:TRANSFERRED*2..6]->(a)` returning to the same node *is* the cycle test; in SQL it would be a recursive CTE with cycle guards, far harder to read and tune.

**Cypher 2 - referral network (community detection with WCC, via GDS).** Cluster accounts into referral communities, the reachable-set answer:

```cypher
CALL gds.graph.project('refs', 'Account', 'REFERRED');

CALL gds.wcc.stream('refs')
YIELD nodeId, componentId
RETURN componentId,
       count(*) AS cluster_size,
       collect(gds.util.asNode(nodeId).id)[..10] AS sample_accounts
ORDER BY cluster_size DESC
LIMIT 20;
```

**When NOT to use it (the honest negative).** A single-hop lookup ("this account's transactions") is a B-tree index answer, not a graph problem, and aggregations belong in Postgres or a columnar store. That is precisely why the ledger stays relational and Neo4j is only the derived traversal store.

> **Human direction (Bùi Đức Trí):** Keep the system of record (wallets, ledger) in PostgreSQL. Neo4j and MongoDB are downstream, derived stores fed from events, rebuildable from the ledger, never the financial source of truth. This is the same principle as the derived `wallet.balance`: the source of truth is the relational ledger, and everything else is a projection off it.

## Open Questions

*Status, summarized from journal section 5 and the report README.*

- The MongoDB collection-type decision (capped huge / time-series / regular+TTL) is deferred until event volume, sharding need, and the compliance retention period are known. All three shapes are written into `docs/audit-l3-mongodb.md`.
- The Neo4j half was the in-progress piece at the time of the report; the model and Cypher above are the AI-composed deliverable from the commissioned research.

## Sources

[1] Design journal, section 5 (MongoDB reasoning owned; Neo4j model AI-composed), verbatim - (local: sources/journal/00-journal.md)
[2] Layer 3 activity audit, MongoDB design, AI-drafted - (local: sources/04-polyglot-modelling/audit-l3-mongodb.md)
[3] Runnable create-collection script - `src/mongo/create_activity_audit.js` (repo)
