#!/usr/bin/env bash
# ============================================================================
# VietPay core ledger - INITIAL deployment orchestrator
# ----------------------------------------------------------------------------
# Applies the one-time baseline schema in ./initial as ordered, reversible
# steps.  Each step has an NN_name.up.sql and a matching NN_name.down.sql.
#
# These are the INITIAL (one-time) schema-creation steps.  Later, incremental
# changes (e.g. the Task 3 expand-contract migration) belong in a SEPARATE
# phase/folder, tracked under their own keys; this runner owns only `initial/`.
#
# DEPLOYMENT STATE is tracked in a `schema_migrations` table so an accidental
# re-deploy cannot break anything:
#   - already-applied steps are SKIPPED (not re-run);
#   - each applied step stores an md5 CHECKSUM of its .up.sql.  If a step that
#     was already applied has since CHANGED on disk, `up` REFUSES to proceed
#     (you must add a new migration instead of silently mutating a shipped one).
# Steps are also individually idempotent (IF NOT EXISTS / CREATE OR REPLACE),
# and each step is applied in ONE transaction with its bookkeeping row, so a
# failure mid-step rolls the whole step back.  No step uses CREATE INDEX
# CONCURRENTLY (tables are empty at deploy time), so wrapping each in a
# transaction is always safe here.
#
# CONNECTION (no secrets in this script): set DATABASE_URL, e.g.
#     export DATABASE_URL="postgres://user:pass@host:5432/vietpay"
# or the standard libpq vars (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE).
#
# USAGE:
#   ./deploy.sh up              apply all pending steps
#   ./deploy.sh up-to 07        apply pending steps up to and including step 07
#   ./deploy.sh down            revert ALL applied steps (full teardown)
#   ./deploy.sh down-to 06      revert applied steps after 06 (keep 06 and below)
#   ./deploy.sh redo 10         revert then re-apply a single step (iterate)
#   ./deploy.sh status          show applied / pending / changed per step
#   ./deploy.sh verify          assert all expected objects exist
#   ./deploy.sh test            run test/smoke_test.sql (integrity spec)
#   ./deploy.sh bundle          print all up steps concatenated (review/CI)
#
# A step is named by its number ("07"), prefix, or full name ("07_entry").
# Exit code is nonzero on any failure (set -e + ON_ERROR_STOP).
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE="initial"                       # tracking namespace + step folder
INITIAL_DIR="$SCRIPT_DIR/$PHASE"
TEST_DIR="$SCRIPT_DIR/test"

# ---- psql invocation --------------------------------------------------------
PSQL=(psql -v ON_ERROR_STOP=1 --no-psqlrc)
if [[ -n "${DATABASE_URL:-}" ]]; then
    PSQL+=("$DATABASE_URL")
fi

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

# psql is only needed by commands that touch the database (not help/bundle).
check_conn() {
    command -v psql >/dev/null 2>&1 || die "psql not found on PATH."
    "${PSQL[@]}" -tAc 'SELECT 1' >/dev/null 2>&1 \
        || die "cannot connect. Set DATABASE_URL or PG* env vars (PGHOST/PGUSER/PGDATABASE/PGPASSWORD)."
}

# ---- step discovery ---------------------------------------------------------
all_steps() {
    local f
    for f in "$INITIAL_DIR"/*.up.sql; do
        basename "$f" .up.sql
    done | sort
}

prefix_num()  { echo $((10#${1%%_*})); }                       # 07_entry -> 7
checksum_of() { md5sum "$1" | awk '{print $1}'; }

# resolve a user token ("7", "07", "07_entry", "entry") to a canonical step name
resolve_step() {
    local t="$1" s
    for s in $(all_steps); do
        if [[ "$s" == "$t" || "$s" == "${t}_"* ]]; then echo "$s"; return 0; fi
        if [[ "$t" =~ ^[0-9]+$ ]] && (( $(prefix_num "$s") == 10#$t )); then echo "$s"; return 0; fi
    done
    return 1
}

# ---- deployment-state bookkeeping -------------------------------------------
ensure_tracking() {
    "${PSQL[@]}" -qc "
        CREATE TABLE IF NOT EXISTS schema_migrations (
            step       TEXT PRIMARY KEY,
            checksum   TEXT NOT NULL,
            applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            applied_by TEXT NOT NULL DEFAULT current_user
        );
        -- tolerate an older tracking table without these columns
        ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum   TEXT;
        ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS applied_by TEXT;
    "
}

# echo the stored checksum for a step key, or empty if not applied
applied_checksum() {
    "${PSQL[@]}" -tAc "SELECT checksum FROM schema_migrations WHERE step = '$1'" 2>/dev/null | tr -d '[:space:]'
}

# apply one step + record it (step + checksum), atomically in one transaction.
# The checksum is a 32-char hex md5 (no quotes/specials), so it is inlined
# directly rather than via a psql variable (-c does not interpolate :'var').
apply_step() {
    local step="$1" key="$2" cur="$3"
    note "  + applying  $key"
    "${PSQL[@]}" --single-transaction \
        -f "$INITIAL_DIR/${step}.up.sql" \
        -c "INSERT INTO schema_migrations (step, checksum) VALUES ('${key}', '${cur}') ON CONFLICT (step) DO NOTHING;"
}

# revert one step + un-record it, atomically in one transaction
revert_step() {
    local step="$1" key="$2"
    note "  - reverting $key"
    "${PSQL[@]}" --single-transaction \
        -f "$INITIAL_DIR/${step}.down.sql" \
        -c "DELETE FROM schema_migrations WHERE step = '${key}';"
}

# ---- commands ---------------------------------------------------------------
cmd_up() {   # optional arg: up-to target
    check_conn; ensure_tracking
    local target="" tnum=999
    if [[ $# -ge 1 ]]; then
        target="$(resolve_step "$1")" || die "unknown step: $1"
        tnum=$(prefix_num "$target")
    fi
    local step key cur stored
    for step in $(all_steps); do
        (( $(prefix_num "$step") > tnum )) && break
        key="$PHASE/$step"
        cur=$(checksum_of "$INITIAL_DIR/${step}.up.sql")
        stored=$(applied_checksum "$key")
        if [[ -n "$stored" ]]; then
            if [[ "$stored" != "$cur" ]]; then
                die "step '$key' is already applied but its .up.sql CHANGED (recorded $stored, now $cur).
       Refusing to silently re-apply a shipped step. Add a new migration for the change,
       or './deploy.sh redo $step' if you are certain re-running it is safe."
            fi
            note "  = $key (already applied)"
        else
            apply_step "$step" "$key" "$cur"
        fi
    done
    note "up: done."
}

cmd_down() { # optional arg: down-to target (keep target and below)
    check_conn; ensure_tracking
    local keep_to=-1
    if [[ $# -ge 1 ]]; then
        local target; target="$(resolve_step "$1")" || die "unknown step: $1"
        keep_to=$(prefix_num "$target")
    fi
    local step key
    for step in $(all_steps | sort -r); do
        (( $(prefix_num "$step") <= keep_to )) && break
        key="$PHASE/$step"
        if [[ -n "$(applied_checksum "$key")" ]]; then revert_step "$step" "$key"
        else note "  = $key (not applied)"; fi
    done
    note "down: done."
}

cmd_redo() { # arg: step to revert then re-apply
    [[ $# -ge 1 ]] || die "redo needs a step, e.g. ./deploy.sh redo 10"
    check_conn; ensure_tracking
    local step; step="$(resolve_step "$1")" || die "unknown step: $1"
    local key="$PHASE/$step" cur; cur=$(checksum_of "$INITIAL_DIR/${step}.up.sql")
    [[ -n "$(applied_checksum "$key")" ]] && revert_step "$step" "$key"
    apply_step "$step" "$key" "$cur"
    note "redo: done ($key)."
}

cmd_status() {
    check_conn; ensure_tracking
    local step key cur stored
    printf '%-36s %s\n' "STEP" "STATE" >&2
    for step in $(all_steps); do
        key="$PHASE/$step"
        cur=$(checksum_of "$INITIAL_DIR/${step}.up.sql")
        stored=$(applied_checksum "$key")
        if   [[ -z "$stored"        ]]; then printf '  %-34s pending\n' "$key"
        elif [[ "$stored" == "$cur" ]]; then printf '  %-34s applied\n' "$key"
        else                                 printf '  %-34s applied (FILE CHANGED since apply!)\n' "$key"; fi
    done
}

cmd_bundle() {
    local step
    echo "-- VietPay core ledger - full INITIAL schema (generated by deploy.sh bundle)"
    echo "-- Apply order is top to bottom. Source of truth: docs/ERD.md"
    for step in $(all_steps); do
        echo; echo "-- ============================================================"
        echo "-- >>> initial/${step}.up.sql"
        echo "-- ============================================================"
        cat "$INITIAL_DIR/${step}.up.sql"
    done
}

cmd_test() {
    check_conn
    [[ -f "$TEST_DIR/smoke_test.sql" ]] || die "missing $TEST_DIR/smoke_test.sql"
    "${PSQL[@]}" -f "$TEST_DIR/smoke_test.sql"
}

cmd_verify() {
    check_conn
    "${PSQL[@]}" --single-transaction <<'SQL'
DO $$
DECLARE
    missing text := '';
    rel     text;
    fn      text;
    trg     RECORD;
BEGIN
    -- tables and views
    FOREACH rel IN ARRAY ARRAY[
        'currencies','exchange_rates','accounts','wallets','transactions','entries',
        'idempotency_keys','audit_logs','balance_audit','balance_audit_drift'
    ] LOOP
        IF to_regclass('public.'||rel) IS NULL THEN missing := missing||' '||rel; END IF;
    END LOOP;
    -- functions
    FOREACH fn IN ARRAY ARRAY['assert_transaction_balanced','deny_mutation'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = fn) THEN
            missing := missing||' fn:'||fn;
        END IF;
    END LOOP;
    -- key triggers
    FOR trg IN SELECT * FROM (VALUES
        ('trg_entries_balanced','entries'),
        ('trg_entries_immutable','entries'),
        ('trg_audit_logs_immutable','audit_logs')
    ) AS t(name, tbl) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_trigger g JOIN pg_class c ON c.oid = g.tgrelid
            WHERE g.tgname = trg.name AND c.relname = trg.tbl AND NOT g.tgisinternal
        ) THEN missing := missing||' trg:'||trg.name; END IF;
    END LOOP;

    IF length(missing) > 0 THEN
        RAISE EXCEPTION 'verify FAILED, missing:%', missing;
    END IF;

    -- the application role is optional (it may be provisioned out-of-band);
    -- report it but do not fail verification on its absence.
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        RAISE NOTICE 'verify OK (note: role vietpay_app absent; privilege REVOKE/GRANT not applied yet).';
    ELSE
        RAISE NOTICE 'verify OK: all expected objects present (incl. vietpay_app).';
    END IF;
END $$;
SQL
}

usage() { sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        up)       cmd_up "$@";;
        up-to)    cmd_up "$@";;
        down)     cmd_down "$@";;
        down-to)  cmd_down "$@";;
        redo)     cmd_redo "$@";;
        status)   cmd_status;;
        verify)   cmd_verify;;
        test)     cmd_test;;
        bundle)   cmd_bundle;;
        help|-h|--help) usage;;
        *) die "unknown command: $cmd (try: ./deploy.sh help)";;
    esac
}

main "$@"
