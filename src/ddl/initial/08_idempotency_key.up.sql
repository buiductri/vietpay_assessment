-- ============================================================================
-- VietPay core ledger | initial 08 (up): idempotency_keys
-- Source of truth: docs/ERD.md  ("idempotency_key" entity; journal T6)
-- One-time baseline. Idempotent. Reverse: 08_idempotency_key.down.sql
-- Target: PostgreSQL 14+   Depends on: 06 transactions
-- ============================================================================
-- Tracks the idempotency key so a duplicate request cannot post twice, and maps
-- it to the resulting transaction.  The guarantee is UNIQUE (caller_id, key):
-- client-supplied keys are unique only per caller, so dedup is scoped per
-- caller.  The application claims the key with
--     INSERT ... ON CONFLICT (caller_id, key) DO NOTHING RETURNING transaction_id
-- inside the SAME transaction as the posting; a rollback releases the key, and
-- crash-recovery rolls back any uncommitted claim (journal T6).
--
-- Deliberately NO Brandur-style `recovery_point` / `locked_at`: for a single
-- atomic posting they add nothing (journal T6).  Only `expires_at` is kept, as
-- a retention marker for a cleanup/watchdog job (operational, not correctness).
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS idempotency_keys (
    idempotency_key_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    key                 TEXT        NOT NULL,
    caller_id           TEXT        NOT NULL,            -- request initiator (customer or system account)
    request_id          TEXT,                            -- the API request id, distinct from `key`
    transaction_id      UUID,                            -- the successful transaction (set after posting)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),                       -- baseline (not in logical ERD)
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours', -- retention/cleanup window
    CONSTRAINT idempotency_keys_caller_key_uq UNIQUE (caller_id, key),
    CONSTRAINT idempotency_keys_transaction_fk
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id) ON DELETE RESTRICT
);

-- supports the cleanup/watchdog sweep of expired keys
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires ON idempotency_keys (expires_at);

COMMENT ON TABLE idempotency_keys IS 'Per-caller dedup: UNIQUE (caller_id, key) makes a retried request map to the original transaction.';
