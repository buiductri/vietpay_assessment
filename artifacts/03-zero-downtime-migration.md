# Task 3: Zero-downtime migration

> Generated: 2026-06-25 | Axis: Zero-downtime migration | Primary sources: journal section 4, `src/ddl/migrations/001_settlement_batch_id/`

This axis reorganizes the existing Task 3 material: the candidate's deployment-planning reasoning from the journal, and the AI-built, PostgreSQL-specific expand-contract migration with per-phase rollback. Owned text is verbatim; AI work is marked and pointed at its committed runbook.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content. This mirrors the journal's own human / `<ai>` split.

## TL;DR

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 4*

"The column name `settlement_batch_id` is just an example, so this task is really about deployment planning. I treat the column as a vehicle for a zero-downtime DDL change and keep its business meaning out of scope". "This is the right shape. PostgreSQL has its own internals, so I had AI turn this sketch into a concrete, tested PostgreSQL expand-contract migration following the direction above."

---

## Key Findings

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the candidate's own words, verbatim quotes from journal section 1.2 and 4*

- "So I can safely skip the business aspect of the column and focus on deployment steps only."
- "In the worst case scenario I have observed, a schema change took 2 hours to run then failed, and took more than 3 hours to rollback due to cascaded effect on transaction log and bottleneck on disk IO, which almost brought the instance down."
- "This is the right shape."
- "Usually, I want database deployment to be as independent as possible. So the best way is to have a 3-stage deployment".

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *the realized migration, full runbook in `src/ddl/migrations/001_settlement_batch_id/README.md`*

- The genuinely blocking operation is the later `SET NOT NULL`; the fast path (`CHECK ... NOT VALID` -> `VALIDATE` -> `SET NOT NULL`) was **measured on 2,000,000 rows**: 1.4 ms versus 581 ms naive.
- The append-only collision is the core of the answer: the backfill temporarily disables the immutability trigger while the privilege `REVOKE` still protects the app.
- `entries` is partitioned, which changes the mechanics (no `NOT VALID` FK on a partitioned parent; `CREATE INDEX CONCURRENTLY` per partition; `ctid` unique only per partition; backfill partition by partition).

---

## Detailed Analysis

### The deployment-planning frame and the naive command

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 4*

We will use the example in the task requirement to demonstrate the expansion. The column name `settlement_batch_id` is just an example, so this task is really about deployment planning. I treat the column as a vehicle for a zero-downtime DDL change and keep its business meaning out of scope (history is backfilled to a sentinel batch, see below).

The goal is to add the column `settlement_batch_id` with constraint `NOT NULL`. For most RDBMS, we can achieve this using a single command

```
# populate full working command here as pgsql syntax
ALTER TABLE entries ADD COLUMN settlement_batch_id NOT NULL
```

This works for small AND infrequent access table, since schema changes must put exclusive lock on the table, and block almost all other operations. This is risky, so in production, we avoid this change as much as possible, unless reach consensus about downtime, and thorough testing the time needed for the task to ensure maintenance windows not need to extend past planning. Also the biggest risk is transaction rollback. The more it holds locks, the effect on transaction log will be bigger. In the worst case scenario I have observed, a schema change took 2 hours to run then failed, and took more than 3 hours to rollback due to cascaded effect on transaction log and bottleneck on disk IO, which almost brought the instance down. Luckily the instance is the testing one so we avoided a big mistake there.

### The SQL Server shape that carries over

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 4*

Since we want zero-downtime, the approach has to be changed. In SQL Server, we split the changes into 3 parts:
- (1) ADD COLUMN with NULL and DEFAULT: this still holds lock, but the change is metadata only, so even though still have locking, it should be quick and rollback is trivial, new data will have default value so that old queries do not insert NULL for new data
- (2) Run script to populate data, either default or computed, we can decide as per specification
- (3) Run check to ensure all data is not NULL
- (4) ALTER COLUMN with NOT NULL
- (5) Working with application side to ensure new versions are deployed. We can then remove DEFAULT if not needed.

This is the right shape. PostgreSQL has its own internals, so I had AI turn this sketch into a concrete, tested PostgreSQL expand-contract migration following the direction above.

### PostgreSQL specifics that reframe the cost

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` correction block in journal section 4*

Two things differ from the SQL Server intuition and reframe where the cost is:

- The command as written fails: `ADD COLUMN ... NOT NULL` with **no default** errors on a non-empty table (existing rows would violate NOT NULL). The runnable single command is `ALTER TABLE entries ADD COLUMN settlement_batch_id UUID NOT NULL DEFAULT '<constant>'`.
- In PostgreSQL 11+ that command does NOT rewrite the table: a constant default is stored once in the catalog, so the add is metadata only and fast even on 50M rows. So it is not the table-rewrite disaster older engines suffer. It still takes a brief `ACCESS EXCLUSIVE` lock, which under load can queue behind a long statement and block everything behind it.

The real reason the single command does not fit is the value, not the lock: a settlement batch is **per row**, not one constant for all history, so the value must be **backfilled**, not defaulted. And the genuinely blocking operation is the later `SET NOT NULL`, which by default scans the whole table under `ACCESS EXCLUSIVE`. That scan is the outage we design around. This is exactly why a per-row value needs expand-contract.

### The realized migration (five phases, per-phase rollback)

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` deliverable block in journal section 4; full runbook in `src/ddl/migrations/001_settlement_batch_id/README.md`*

`src/ddl/migrations/001_settlement_batch_id/` (separate from the `initial/` baseline, because an expand-contract migration is gated by application deploys and is a human-driven runbook, not a single automated `up`). Five ordered, individually reversible steps plus a runbook `README.md`:

```
01_expand        ADD nullable column (+ settlement_batches parent + sentinel)
02_backfill      disable immutability, fill history partition-by-partition (committed batches)
03_restore_immutability   re-enable + verify the deny trigger everywhere
04_index         online index (partitioned pattern)
05_promote       CHECK NOT VALID -> VALIDATE -> SET NOT NULL
```

The changelog of what the PostgreSQL reality forced (full text in the journal and the migration README):

- **T1 Target table `entries`, not `transactions`.** The assessment's flat 50M-row "transactions" table is what Task 1 split; the 50M rows live in `entries`.
- **T2 The append-only collision (the core of the answer).** `entries` is immutable by Invariant 3, enforced by `REVOKE UPDATE` **and** a `deny_mutation` trigger. A NOT NULL backfill must UPDATE every historical row, which both forbid. So the backfill, run by the OWNER/DBA, must **temporarily disable** `trg_entries_immutable` for the backfill window. The payoff: while the trigger is off, the privilege `REVOKE` still holds, so the application still cannot rewrite history during the window.
- **T3 `entries` is partitioned, which changes the mechanics.** A partitioned table rejects a `NOT VALID` foreign key; `CREATE INDEX CONCURRENTLY` is illegal on a partitioned parent (so build `ON ONLY` + CIC per partition + `ATTACH`); `ctid` is unique only within one partition (so backfill runs partition by partition); `DISABLE TRIGGER` on the parent cascades to partitions in PG 15+ but not PG 14 (so loop every partition, version-safe).
- **T4 The SET NOT NULL fast path (PG 12+), measured.** Step 05 adds `CHECK (col IS NOT NULL) NOT VALID` (instant), `VALIDATE CONSTRAINT` (SHARE UPDATE EXCLUSIVE, reads and writes continue), then `SET NOT NULL` (fast, the planner trusts the validated CHECK and skips the scan). Measured on 2,000,000 rows: the fast-path `SET NOT NULL` took **1.4 ms** versus **581 ms** for a naive `SET NOT NULL`.
- **T5 Dual-write window and old-vs-new read shape.** Expand adds the column NULLABLE. App `vN+1` then dual-writes the column on every INSERT but **still reads the old shape**. Only after promote does app `vN+2` read/require the new shape. So the application reads the OLD shape from expand through promote, and the NEW shape only after the column is NOT NULL and every row has a value.
- **T6 Rollback at each phase, and the asymmetry.** Once the column is NOT NULL, an app version that does not write it fails every INSERT, so to unwind past the dual-write app you must `DROP NOT NULL` (05.down) **before** reverting the app. Always relax the constraint before reverting the writer.
- **T7 Idempotency and lock safety.** Every up step re-runs cleanly (catalog guards, `IF NOT EXISTS`, `WHERE ... IS NULL` backfill). Every brief `ACCESS EXCLUSIVE` operation runs under a short `lock_timeout` with a bounded retry, so it cannot pile up behind a long statement under load.

The whole lifecycle was validated end to end against the provided PostgreSQL 17.2, in an isolated schema: up through promote, idempotent re-runs, per-phase rollback, and full teardown.

### When the application reads the old vs new shape

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *from the migration README*

| Window | App version | Writes the column? | Reads/requires the column? | Column constraint |
|---|---|---|---|---|
| before step 1 | `vN` | no | no | absent |
| steps 1 -> 7 | `vN+1` (dual-write) | yes (new rows) | **no, still OLD shape** | NULLABLE |
| after step 8 | `vN+2` (contract) | yes | **yes, NEW shape** | `NOT NULL` |

### Human direction

> **Human direction (Bùi Đức Trí):** The column goes on `entries`, not on a `transactions` header. We already mapped the assessment's original flat "transactions" table onto the `entry` entity in Task 1, so `entries` is the live 50M-row table the requirement is talking about. The immutability collision that this creates is not a reason to move the column off `entries`; it is part of the answer, handled by an audited, privileged disable of the deny trigger for the backfill window, with the privilege REVOKE still protecting the application.

## Open Questions

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *from the migration README "Foreign key on a partitioned table"*

- The foreign key to `settlement_batches` is intentionally left as a team decision: a partitioned table rejects a `NOT VALID` FK, so the options are a validated FK in a maintenance window, a per-partition `NOT VALID` + `VALIDATE`, or app-enforced (common for large partitioned fact tables). The Task 3 requirement is the `NOT NULL` column; the FK is a separate decision.

## Sources

[1] Design journal, section 4 (candidate's reasoning + interleaved AI changelog), verbatim - (local: sources/journal/00-journal.md)
[2] Task 3 expand-contract migration runbook, AI-built - (local: sources/03-zero-downtime-migration/migration-runbook.md)
[3] Task 3 migration scripts: 5 phases, each with `.down.sql` - `src/ddl/migrations/001_settlement_batch_id/` (repo)
