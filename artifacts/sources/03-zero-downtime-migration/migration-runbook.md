# Migration 001: add `settlement_batch_id NOT NULL` to `entries` (Task 3)

A concrete **expand-contract** (parallel-change) migration that adds a `NOT NULL`
column to the live, large, **partitioned** `entries` table under production load,
with **zero downtime** and a **rollback at every phase**. This is the Task 3
deliverable; the written reasoning is in `00-journal.md` (section 4).

Validated end to end against the provided PostgreSQL 17.2 (full lifecycle, idempotent
re-runs, per-phase rollback, full teardown), in an isolated schema so nothing shared
was touched. The headline property was **measured on 2,000,000 rows**: the fast-path
`SET NOT NULL` took **1.4 ms** (scan skipped) versus **581 ms** for a naive
`SET NOT NULL` (full `ACCESS EXCLUSIVE` scan); the equivalent verification scan
(379 ms) is moved into `VALIDATE CONSTRAINT`, which holds only `SHARE UPDATE
EXCLUSIVE` and does not block reads or writes. At 50M rows the naive path is a
multi-second exclusive lock; the fast path stays a millisecond-scale metadata flip.

> **Dependency:** these scripts are written against the current `initial/07`
> (`entries` range-partitioned monthly on `created_at`) and `initial/11` (deny
> trigger named `trg_entries_immutable`). Both are owned by other tasks and were
> still uncommitted when this was built; if their shape or names change, re-run the
> validation harness. The backfill also handles a non-partitioned `entries` (it
> falls back to the table itself), so it does not silently no-op on a shape change.

## Which table, and why `entries`

The assessment names "the 50M-row transactions table". In this design that table
is **`entries`**: Task 1 split the assessment's flat
`transactions(id, wallet_id, type, amount, currency, status, created_at)` into a
`transaction` header plus `entry` lines, and the 50M rows live in `entries`
(`00-journal.md` sec. 3: "the query on 'transactions' ... is now entries"). So the
column goes on `entries`. `settlement_batch_id` groups the entries cleared in one
settlement cycle.

`entries` is **range-partitioned monthly on `created_at`** (Task 2, `initial/07`),
PK `(entry_id, created_at)`, with one partition per month plus a default. Every
operation here is on the partitioned parent and cascades to its partitions, which
adds several partition-specific wrinkles (below).

## The twist: `entries` is append-only

`entries` carries the two-layer immutability guard from `initial/11`:

1. **Privilege**: `REVOKE UPDATE, DELETE, TRUNCATE` from `vietpay_app`.
2. **Trigger**: `trg_entries_immutable` (`deny_mutation`), defence-in-depth, which
   fires for **every** role, owner included (a trigger is universal; `REVOKE` only
   binds the role it names), and is **cloned onto every partition**.

A `NOT NULL` backfill must `UPDATE` every historical row, which both layers forbid
for the application. So the backfill is a **privileged, intentional, audited DBA
migration**, run by the table owner (never `vietpay_app`), that **temporarily
disables `trg_entries_immutable` on the parent and every partition for the backfill
window only** (the audited, intentional act the trigger's own comment sanctions).

The payoff of the two-layer design shows here: while the trigger is off, the
**privilege `REVOKE` still holds**, so the application still cannot rewrite history
during the window. New rows keep arriving by `INSERT`, which immutability never
blocked. After promotion the trigger is re-enabled and immutability is fully
restored (and `03` verifies no partition clone is left disabled).

## Why not a single `ALTER TABLE ... ADD COLUMN ... NOT NULL DEFAULT ...`

- Adding `NOT NULL` with **no default** fails outright on a non-empty table.
- Adding `NOT NULL DEFAULT <constant>` is fast in PG 11+ (metadata only, no
  rewrite), but it stamps **one constant** on all 50M rows, and a settlement batch
  is **per row**, not a constant. The value must be backfilled, not defaulted,
  which is exactly why expand-contract exists.
- The genuinely blocking operation is the later `SET NOT NULL`, which by default
  scans every partition under `ACCESS EXCLUSIVE`. Phase 5 avoids that scan.

## Partition-specific facts that shape this migration

These were verified on PG 17.2; the scripts are written to also be safe on 14+.

| Fact | Consequence here |
|---|---|
| A partitioned table **rejects a `NOT VALID` foreign key** | No DB-level FK to `settlement_batches`; see "Foreign key" below. |
| `CREATE INDEX CONCURRENTLY` is **illegal on a partitioned parent** | Index is built `ON ONLY` parent + CIC per partition + `ATTACH` (step 4). |
| `ctid` is unique only **within one partition** | Backfill runs **partition by partition** (step 2), not over the parent. |
| `DISABLE TRIGGER` on the parent cascades to partitions in **PG 15+** but not PG 14 | Step 2/3 disable/enable on parent **and** loop every partition (version-safe). |
| `SET NOT NULL` + a validated `CHECK` skips the scan **per partition** | Promotion (step 5) is fast on the parent and every partition. |
| `ADD COLUMN` / `SET NOT NULL` / `DROP COLUMN` on the parent **recurse** | One statement covers all partitions. |

## Lock profile of each operation

| Operation | Phase | Lock | Scans 50M? | Blocks reads/writes? |
|---|---|---|---|---|
| `ADD COLUMN ... UUID` (nullable, no default) | 1 | ACCESS EXCLUSIVE (brief, parent + partitions) | no | no |
| batched `UPDATE` backfill, per partition | 2 | ROW locks, per batch | yes, in chunks | no |
| `DISABLE/ENABLE TRIGGER` (parent + partitions) | 2,3 | ACCESS EXCLUSIVE (brief, each) | no | no |
| `CREATE INDEX ON ONLY entries` (stub) | 4 | brief, parent only | no | no |
| `CREATE INDEX CONCURRENTLY` per partition | 4 | SHARE UPDATE EXCLUSIVE | builds online | no |
| `ALTER INDEX ... ATTACH PARTITION` | 4 | brief | no | no |
| `ADD CONSTRAINT ck ... NOT VALID` | 5 | ACCESS EXCLUSIVE (brief) | no | no |
| `VALIDATE CONSTRAINT` | 5 | SHARE UPDATE EXCLUSIVE | yes, online (379 ms / 2M, non-blocking) | no |
| `SET NOT NULL` (with validated CHECK) | 5 | ACCESS EXCLUSIVE (brief) | **no** (1.4 ms / 2M; vs 581 ms naive) | no |

Every `ACCESS EXCLUSIVE` operation is taken under a short `lock_timeout` with a
bounded retry, so a brief lock cannot queue behind a long statement and then block
everything behind it. Each script is idempotent, so a `lock_timeout` abort is just
re-run.

## Ordered runbook (DB steps interleaved with app deploys)

| # | Step | Artifact | Who | `--single-transaction`? |
|---|---|---|---|---|
| 1 | **EXPAND**: parent table + sentinel, add NULLABLE column | `01_expand.up.sql` | DBA | yes |
| 2 | **Deploy app `vN+1` (dual-write)**: write `settlement_batch_id` on every `INSERT`; reads still use the OLD shape | app deploy | App | - |
| 3 | Verify no new NULLs: `SELECT count(*) FROM entries WHERE settlement_batch_id IS NULL AND created_at > '<deploy ts>'` is 0 | check | DBA | - |
| 4 | **BACKFILL** historical NULLs, partition by partition (disables deny trigger) | `02_backfill.up.sql` | DBA | **no** |
| 5 | **RESTORE IMMUTABILITY** (re-enable parent + partitions, verify `tgenabled`) | `03_restore_immutability.up.sql` | DBA | yes |
| 6 | **INDEX** online (stub + per-partition CIC + attach) | `04_index.up.sql` | DBA | **no** |
| 7 | **PROMOTE**: `CHECK NOT VALID` -> `VALIDATE` -> `SET NOT NULL` | `05_promote.up.sql` | DBA | yes |
| 8 | **Deploy app `vN+2` (contract)**: app now READS the new shape, drops any NULL-tolerant fallback | app deploy | App | - |

Steps 4 and 6 must NOT be run with `--single-transaction` (the backfill COMMITs per
batch; the index uses `CONCURRENTLY` and `\gexec`).

## When the application reads the OLD vs the NEW shape

| Window | App version | Writes the column? | Reads/requires the column? | Column constraint |
|---|---|---|---|---|
| before step 1 | `vN` | no | no | absent |
| steps 1 -> 7 | `vN+1` (dual-write) | yes (new rows) | **no, still OLD shape** | NULLABLE |
| after step 8 | `vN+2` (contract) | yes | **yes, NEW shape** | `NOT NULL` |

The column is only ever **read/required** by the application **after** it is
`NOT NULL` and every row has a value. Between expand and contract the app writes it
but does not depend on it, which is what makes each phase independently reversible.

## Rollback at each phase

| Phase | To roll back | Effect |
|---|---|---|
| 1 EXPAND | `01_expand.down.sql` | drops column (cascades to partitions) and the parent table. Old app unaffected. |
| 2 dual-write | redeploy `vN` | stops writing the column. Column stays NULLABLE, harmless. |
| 4 BACKFILL | `02_backfill.down.sql` | drops the procedure, re-enables the deny trigger everywhere. Backfilled value is harmless; full revert is `01.down`. Resumable, so usually continue rather than revert. |
| 5 RESTORE | `03_restore_immutability.down.sql` | re-disables the trigger (parent + partitions) to resume a backfill. |
| 6 INDEX | `04_index.down.sql` | drops the partitioned index (and its attached leaf indexes). |
| 7 PROMOTE | `05_promote.down.sql` | `DROP NOT NULL` (cascades to partitions). |
| 8 contract | redeploy `vN+1` | app stops requiring the column; it tolerates the value again. |

### Rollback asymmetry (the one trap)

Expand-contract is **not symmetric**. Once the column is `NOT NULL` (step 7), an app
version that does **not** write it will fail every `INSERT`. So to unwind past the
dual-write version you must **`05_promote.down.sql` (DROP NOT NULL) first**, then
revert the app. Always relax the constraint before reverting the writer.

## Foreign key on a partitioned table

The column points at `settlement_batches`, but there is intentionally **no DB-level
foreign key**. A partitioned table rejects a `NOT VALID` foreign key, so the online
"add NOT VALID then VALIDATE later" path used for ordinary tables is unavailable.
The options, none free:

- **Validated FK in a maintenance window**: `ALTER TABLE entries ADD CONSTRAINT ...
  FOREIGN KEY ...` validates immediately, scanning every partition under
  `SHARE ROW EXCLUSIVE` (blocks writes). Not zero-downtime.
- **Per-partition `NOT VALID` + `VALIDATE`**: leaf (non-partitioned) tables *do*
  accept a `NOT VALID` FK, so you can add and validate it partition by partition.
  Caveat: new partitions need the FK wired into the partition factory
  (`create_entries_partition()` in `initial/07`), which is owned by Task 2 and not
  modified here.
- **Application-enforced**: large partitioned fact tables commonly omit the DB-level
  FK for exactly these operational reasons and enforce the reference in the writer
  plus a reconciliation check.

This migration keeps the `settlement_batches` table and the sentinel row (the
backfill value and the dual-write target) and leaves the referential choice to the
team. The Task 3 requirement is the `NOT NULL` column; the FK is a separate decision.

## Operational tail

- **Bloat + WAL**: backfilling 50M rows creates 50M dead tuples and a large WAL
  volume. Run a plain `VACUUM entries` (or per partition) after the backfill to
  reclaim space and refresh stats. **Never `VACUUM FULL`**: it takes
  `ACCESS EXCLUSIVE` and rewrites the table, the outage we are avoiding.
- **Partition-by-partition is the payoff**: old months are static, so each partition
  backfills with far less contention and can be parallelised; only the current
  month sees concurrent inserts (already handled by dual-write).
- **Replication lag**: the per-batch `pg_sleep` throttle lets replicas and
  autovacuum keep up; widen it if replica lag climbs.
- **Aborted backfill**: if step 4 dies mid-run, `trg_entries_immutable` is left
  disabled (on the partitions it reached). The privilege `REVOKE` still protects the
  app, but run step 5 (idempotent) to restore it; it asserts no clone is left
  disabled. `deploy.sh verify` only checks the trigger EXISTS, not that it is
  ENABLED, which is why step 5 does the `tgenabled` check itself.

## Idempotency and reversibility

Every `*.up.sql` is safe to re-run: `IF NOT EXISTS` / `CREATE OR REPLACE` / catalog
`pg_constraint`, `pg_attribute`, `pg_index`, `pg_inherits` guards / `WHERE ... IS
NULL` backfill / `DISABLE/ENABLE TRIGGER` no-ops / `ATTACH` skipped when already
attached / invalid-leaf-index drop-then-rebuild. Catalog scoping is by **OID**
(`'entries'::regclass` + `pg_inherits`), not by relname, so a same-named table in
another schema cannot skew a check. Every step has a matching `*.down.sql`.

These incremental steps live outside `deploy.sh`'s `initial/` runner on purpose: an
expand-contract migration is gated by application deploys, so it is a human-driven
runbook, not a single automated `up`. Register the steps in `schema_migrations` with
a `migrations/001_settlement_batch_id/NN` key if you want them tracked alongside the
baseline.
