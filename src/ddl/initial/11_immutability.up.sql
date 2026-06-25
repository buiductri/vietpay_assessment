-- ============================================================================
-- VietPay core ledger | initial 11 (up): immutability (entries + audit_logs)
-- Source of truth: docs/ERD.md  ("Immutability"); CONTEXT.md (audit never deleted)
-- One-time baseline. Idempotent. Reverse: 11_immutability.down.sql
-- Target: PostgreSQL 14+   Depends on: 07 entries, 09 audit_logs, 01 (vietpay_app)
-- ============================================================================
-- `entries` and `audit_logs` are append-only.  A posted entry is never edited or
-- deleted; an undo is a new reversing transaction.  An audit row is the
-- compliance record and is never deleted.  Enforced two ways:
--
--   1. PRIVILEGE (primary): REVOKE UPDATE/DELETE/TRUNCATE from the app role, so
--      even a buggy or compromised service cannot rewrite history.
--   2. TRIGGER (defence-in-depth): raise on any UPDATE/DELETE/TRUNCATE, which
--      also catches mistakes made by the owner/superuser the app role can't
--      reach.  (A superuser can still disable triggers deliberately; that is an
--      audited, intentional act, not an accident.)
-- ----------------------------------------------------------------------------

-- 1. Privilege model -----------------------------------------------------------
-- Applied only if vietpay_app exists (it may not yet, if the deployer lacked
-- CREATEROLE in step 01).  The deny TRIGGER below enforces immutability either
-- way, so the guarantee holds even before the role is provisioned.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        REVOKE UPDATE, DELETE, TRUNCATE ON entries, audit_logs FROM vietpay_app;
        GRANT  SELECT, INSERT            ON entries, audit_logs TO   vietpay_app;
        RAISE NOTICE 'applied entries/audit_logs privileges for vietpay_app';
    ELSE
        RAISE NOTICE 'vietpay_app absent; immutability enforced by trigger. Re-run step 11 after provisioning the role to apply REVOKE.';
    END IF;
END
$$;

-- 2. Defence-in-depth trigger --------------------------------------------------
CREATE OR REPLACE FUNCTION deny_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        '% is append-only; % is not allowed (post a reversing transaction instead)',
        TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION deny_mutation() IS 'Defence-in-depth: rejects UPDATE/DELETE/TRUNCATE on append-only ledger/audit tables.';

DROP TRIGGER IF EXISTS trg_entries_immutable ON entries;
CREATE TRIGGER trg_entries_immutable
    BEFORE UPDATE OR DELETE ON entries
    FOR EACH ROW EXECUTE FUNCTION deny_mutation();

DROP TRIGGER IF EXISTS trg_entries_no_truncate ON entries;
CREATE TRIGGER trg_entries_no_truncate
    BEFORE TRUNCATE ON entries
    FOR EACH STATEMENT EXECUTE FUNCTION deny_mutation();

DROP TRIGGER IF EXISTS trg_audit_logs_immutable ON audit_logs;
CREATE TRIGGER trg_audit_logs_immutable
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION deny_mutation();

DROP TRIGGER IF EXISTS trg_audit_logs_no_truncate ON audit_logs;
CREATE TRIGGER trg_audit_logs_no_truncate
    BEFORE TRUNCATE ON audit_logs
    FOR EACH STATEMENT EXECUTE FUNCTION deny_mutation();

-- `entries` is range-partitioned (step 07).  Row-level UPDATE/DELETE triggers
-- on a partitioned parent ARE cloned to every partition automatically, but the
-- statement-level TRUNCATE trigger above is NOT -- it only guards the parent, so
-- a direct `TRUNCATE entries_pYYYYMM` would slip past it.  The app role can never
-- TRUNCATE (no privilege, and partitions grant it nothing), so the guarantee
-- holds regardless; this closes the defence-in-depth gap for the owner/superuser
-- path by attaching the guard to each existing partition.  Future partitions get
-- it from create_entries_partition() (step 07), which now finds deny_mutation().
DO $$
DECLARE part regclass;
BEGIN
    IF to_regclass('public.entries') IS NOT NULL THEN
        FOR part IN
            SELECT inhrelid::regclass FROM pg_inherits WHERE inhparent = 'entries'::regclass
        LOOP
            EXECUTE format('DROP TRIGGER IF EXISTS trg_entries_no_truncate ON %s', part);
            EXECUTE format(
                'CREATE TRIGGER trg_entries_no_truncate BEFORE TRUNCATE ON %s '
                'FOR EACH STATEMENT EXECUTE FUNCTION deny_mutation()', part);
        END LOOP;
    END IF;
END $$;
