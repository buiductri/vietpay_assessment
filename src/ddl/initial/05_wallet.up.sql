-- ============================================================================
-- VietPay core ledger | initial 05 (up): wallets
-- Source of truth: docs/ERD.md  ("wallet" entity; currency-consistency rule)
-- One-time baseline. Idempotent. Reverse: 05_wallet.down.sql
-- Target: PostgreSQL 14+   Depends on: 04 accounts
-- ============================================================================
-- A single-currency balance container under one account.  `kind` distinguishes
-- a spendable `regular` wallet from a `holding` wallet (holds the account's
-- balance while an external flow settles).  The account *role* lives on
-- accounts.type, not here, so one account can hold both a regular and a holding
-- wallet per currency.
--
-- `balance` is a DERIVED cache: computed inside the posting transaction, NEVER
-- the source of truth (the entries are).  Step 12 ships a reconciliation view
-- that compares it against SUM(entries).
--
-- UNIQUE (wallet_id, currency): wallet_id alone is already the PK, but the
-- composite FK from `entries (wallet_id, currency)` requires a unique constraint
-- on EXACTLY that column set to reference.  It is the linchpin of the
-- currency-consistency guarantee (an entry cannot name a currency its wallet
-- does not hold).  See step 07.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS wallets (
    wallet_id   UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  UUID          NOT NULL,
    name        TEXT          NOT NULL,
    currency    CHAR(3)       NOT NULL,                 -- ISO 4217
    kind        TEXT          NOT NULL DEFAULT 'regular'
        CONSTRAINT wallets_kind_ck   CHECK (kind   IN ('regular', 'holding')),
    balance     NUMERIC(19,4) NOT NULL DEFAULT 0,       -- derived cache only
    status      TEXT          NOT NULL DEFAULT 'active'
        CONSTRAINT wallets_status_ck CHECK (status IN ('active', 'closed')),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),   -- baseline (not in logical ERD)
    CONSTRAINT wallets_account_fk
        FOREIGN KEY (account_id) REFERENCES accounts (account_id) ON DELETE RESTRICT,
    CONSTRAINT wallets_id_currency_uq UNIQUE (wallet_id, currency)
);

CREATE INDEX IF NOT EXISTS idx_wallets_account ON wallets (account_id);

COMMENT ON TABLE  wallets         IS 'Single-currency balance container under one account.';
COMMENT ON COLUMN wallets.balance IS 'Derived cache, never the source of truth; reconciled against SUM(entries).';
COMMENT ON CONSTRAINT wallets_id_currency_uq ON wallets IS 'Target of the entries (wallet_id, currency) composite FK; enforces currency consistency.';
