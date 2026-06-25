-- ============================================================================
-- VietPay core ledger | initial 07 (up): entries (double-entry lines)
-- Source of truth: docs/ERD.md  ("entry" entity; currency-consistency rule)
-- One-time baseline. Idempotent. Reverse: 07_entry.down.sql
-- Target: PostgreSQL 14+   Depends on: 05 wallets, 06 transactions
-- ============================================================================
-- The double-entry line: one DEBIT or one CREDIT against one wallet.  An
-- immutable, append-only fact (immutability enforced in step 11).  `amount` is
-- a POSITIVE magnitude; direction lives in `type`.  This (positive amount +
-- direction-in-type) is a recorded STANDARDS choice, not a correctness fix:
-- a signed amount with a CHECK is equally correct.  See journal T3.
--
-- PARTITIONING NOTE (Task 2): this is the logical model, so the PK is
-- `entry_id` and the table is not partitioned.  Task 2 (query & performance)
-- converts `entries` to monthly RANGE partitioning on `created_at`; PostgreSQL
-- then requires the partition key in the PK, so the physical PK becomes
-- `(entry_id, created_at)`.  That conversion, and the settlement-query indexes,
-- are the Task 2 deliverable and are intentionally NOT done here.
--
-- CURRENCY CONSISTENCY: the composite FK `(wallet_id, currency)` -> wallets
-- guarantees an entry's currency equals its wallet's.  Both columns are
-- NOT NULL because under the default MATCH SIMPLE a NULL in either would skip
-- the check entirely.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS entries (
    entry_id        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID          NOT NULL,
    wallet_id       UUID          NOT NULL,
    type            TEXT          NOT NULL
        CONSTRAINT entries_type_ck   CHECK (type IN ('DEBIT', 'CREDIT')),
    amount          NUMERIC(19,4) NOT NULL
        CONSTRAINT entries_amount_ck CHECK (amount > 0),   -- positive magnitude; direction is in `type`
    currency        CHAR(3)       NOT NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT entries_transaction_fk
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id) ON DELETE RESTRICT,
    CONSTRAINT entries_wallet_currency_fk
        FOREIGN KEY (wallet_id, currency) REFERENCES wallets (wallet_id, currency) ON DELETE RESTRICT
);

-- FK / join support and per-wallet balance scans (baseline; Task 2 adds the
-- workload-specific settlement indexes alongside partitioning).
CREATE INDEX IF NOT EXISTS idx_entries_transaction ON entries (transaction_id);
CREATE INDEX IF NOT EXISTS idx_entries_wallet      ON entries (wallet_id, created_at DESC);

COMMENT ON TABLE  entries        IS 'Immutable double-entry lines; one DEBIT or CREDIT against one wallet.';
COMMENT ON COLUMN entries.amount IS 'NUMERIC(19,4), always > 0; direction is carried in `type` (standards choice, journal T3).';
COMMENT ON CONSTRAINT entries_wallet_currency_fk ON entries IS 'Currency consistency: entry.currency must equal its wallet.currency.';
