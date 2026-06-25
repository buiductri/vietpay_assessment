-- ============================================================================
-- VietPay core ledger | initial 02 (up): currencies lookup
-- Source of truth: docs/ERD.md  ("currency" entity)
-- One-time baseline. Idempotent. Reverse: 02_currency.down.sql
-- Target: PostgreSQL 14+
-- ============================================================================
-- A small lookup of the currencies in use.  Referenced by `exchange_rates`
-- (base and quoted).  Per the ERD, `wallets.currency` and `entries.currency`
-- are carried directly as CHAR(3) strings and are NOT normalised onto this
-- lookup (that normalisation is deliberately deferred).
-- (Table names are plural; the column noun `currency` stays singular.)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS currencies (
    currency_id  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT    NOT NULL,                 -- e.g. 'US Dollar'
    code         CHAR(3) NOT NULL,                 -- ISO 4217, e.g. 'USD'
    CONSTRAINT currencies_code_uq UNIQUE (code)
);

COMMENT ON TABLE  currencies      IS 'Lookup of ISO 4217 currencies referenced by exchange_rates.';
COMMENT ON COLUMN currencies.code IS 'ISO 4217 alpha-3 code; unique.';
