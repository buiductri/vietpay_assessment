-- ============================================================================
-- VietPay core ledger | initial 03 (up): exchange_rates lookup
-- Source of truth: docs/ERD.md  ("exchange_rate" entity; FX worked example)
-- One-time baseline. Idempotent. Reverse: 03_exchange_rate.down.sql
-- Target: PostgreSQL 14+   Depends on: 02 currencies
-- ============================================================================
-- Holds the exchange rate for a date and currency pair (OANDA-style: one rate
-- per date/pair).  A `transactions` row that does a currency exchange references
-- the exact row here via `exchange_rate_id`, which pins the point-in-time rate
-- so a retry is deterministic.  `rate` carries more precision than a money value.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS exchange_rates (
    exchange_rate_id  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange_date     DATE          NOT NULL,
    base_currency_id  UUID          NOT NULL,
    currency_id       UUID          NOT NULL,         -- the quoted currency
    rate              NUMERIC(19,8) NOT NULL CHECK (rate > 0),
    CONSTRAINT exchange_rates_base_fk
        FOREIGN KEY (base_currency_id) REFERENCES currencies (currency_id) ON DELETE RESTRICT,
    CONSTRAINT exchange_rates_quote_fk
        FOREIGN KEY (currency_id)      REFERENCES currencies (currency_id) ON DELETE RESTRICT,
    -- one rate per date / pair
    CONSTRAINT exchange_rates_date_pair_uq
        UNIQUE (exchange_date, base_currency_id, currency_id),
    -- base and quoted currency must differ
    CONSTRAINT exchange_rates_distinct_ccy_ck
        CHECK (base_currency_id <> currency_id)
);

COMMENT ON TABLE  exchange_rates      IS 'Point-in-time FX rate per date and currency pair; pinned by transactions.exchange_rate_id.';
COMMENT ON COLUMN exchange_rates.rate IS 'NUMERIC(19,8): rate carries more precision than a money value.';
