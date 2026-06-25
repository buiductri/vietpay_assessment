-- ============================================================================
-- VietPay core ledger | initial 04 (up): accounts (chart of accounts)
-- Source of truth: docs/ERD.md  ("account" entity; chart of accounts on type)
-- One-time baseline. Idempotent. Reverse: 04_account.down.sql
-- Target: PostgreSQL 14+
-- ============================================================================
-- A chart-of-accounts bucket that owns wallets.  `type` gives its ledger role:
-- CUSTOMER for end users, plus the platform's own accounts that let a fee, a
-- top-up, or an FX leg balance.  Enumerated values are TEXT + CHECK rather than
-- a native ENUM: the ERD models these as TEXT, and a CHECK list is trivial to
-- evolve (ALTER ... DROP/ADD CONSTRAINT) whereas ENUM relabel/reorder is not.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounts (
    account_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    type        TEXT NOT NULL
        CONSTRAINT accounts_type_ck CHECK (type IN (
            'CUSTOMER',          -- end user
            'PLATFORM_FLOAT',    -- real bank cash the platform holds
            'PLATFORM_REVENUE',  -- fees earned
            'MERCHANT_PAYABLE',  -- funds owed out to merchants
            'FX_POSITION'        -- the FX desk
        )),
    status      TEXT NOT NULL DEFAULT 'active'
        CONSTRAINT accounts_status_ck CHECK (status IN ('active', 'closed')),
    -- baseline operational column (not in the logical ERD; trivial columns are
    -- omitted there).  Useful for audit_logs correlation and housekeeping.
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  accounts      IS 'Chart-of-accounts bucket owning wallets; ledger role lives on accounts.type.';
COMMENT ON COLUMN accounts.type IS 'CUSTOMER, PLATFORM_FLOAT, PLATFORM_REVENUE, MERCHANT_PAYABLE, FX_POSITION.';
