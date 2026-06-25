-- ============================================================================
-- VietPay core ledger | initial 01 (up): extensions and application role
-- Source of truth: docs/ERD.md  (money/id rules; immutability via app role)
-- One-time baseline. Idempotent. Reverse: 01_extensions_and_roles.down.sql
-- Target: PostgreSQL 14+
-- ============================================================================
--
-- ids are UUID.  gen_random_uuid() is in core PostgreSQL since v13, so no
-- extension is required on the 14+ target.  (On <13 you would instead
-- `CREATE EXTENSION IF NOT EXISTS pgcrypto;` to get gen_random_uuid().)
--
-- `vietpay_app` is the least-privilege role the application connects as.  It is
-- created NOLOGIN (a group role); grant it to your actual login role, e.g.
--     GRANT vietpay_app TO vietpay_service;
-- Immutability (step 11) REVOKEs UPDATE/DELETE from THIS role, so even a buggy
-- or compromised service cannot rewrite ledger history.
--
-- Creating a role needs CREATEROLE (or superuser).  A migration is often run by
-- a non-privileged owner role, so this DEGRADES GRACEFULLY: if the role cannot
-- be created here, the deploy continues and the privilege REVOKE/GRANT steps
-- (11, 12) skip themselves until the role is provisioned out-of-band.
-- Immutability is still enforced meanwhile by the deny TRIGGER (step 11).
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        CREATE ROLE vietpay_app NOLOGIN;
        RAISE NOTICE 'created role vietpay_app';
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'vietpay_app NOT created (deployer lacks CREATEROLE). Provision it out-of-band; privilege steps will skip until it exists.';
END
$$;

-- Let the role use the schema its objects live in.  Guarded the same way.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        GRANT USAGE ON SCHEMA public TO vietpay_app;
    END IF;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'could not GRANT USAGE on schema public to vietpay_app (insufficient privilege).';
END
$$;
