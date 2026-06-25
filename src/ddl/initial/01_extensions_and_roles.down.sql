-- ============================================================================
-- VietPay core ledger | initial 01 (down): drop application role
-- Reverses: 01_extensions_and_roles.up.sql   Idempotent.
-- ----------------------------------------------------------------------------
-- Runs LAST in a teardown (down order is 12 -> 01), so by this point every
-- object the role was granted on has already been dropped.  Dropping the role
-- needs the same privilege that created it; degrade gracefully if not.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        REVOKE USAGE ON SCHEMA public FROM vietpay_app;
        DROP ROLE vietpay_app;
        RAISE NOTICE 'dropped role vietpay_app';
    END IF;
EXCEPTION WHEN insufficient_privilege OR dependent_objects_still_exist THEN
    RAISE NOTICE 'left role vietpay_app in place (insufficient privilege or still referenced).';
END
$$;
