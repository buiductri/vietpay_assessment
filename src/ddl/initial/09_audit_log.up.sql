-- ============================================================================
-- VietPay core ledger | initial 09 (up): audit_logs (Layer 2 audit)
-- Source of truth: docs/ERD.md  ("audit_log" entity; audit-l3-mongodb.md)
-- One-time baseline. Idempotent. Reverse: 09_audit_log.down.sql
-- Target: PostgreSQL 14+   Depends on: 06 transactions
-- ============================================================================
-- Layer 2 of the audit model: an in-Postgres, transactional record of committed
-- state changes to NON-ledger entities (wallet freeze, KYC tier, limit change).
-- Written in the SAME DB transaction as the change it describes, so it is always
-- consistent with committed state (and disappears if that change rolls back).
--
--  - Layer 1 is the ledger entries themselves (immutable, their own audit).
--  - Layer 3 (attempts, denials, access) is an append-only MongoDB event log,
--    modelled in docs/audit-l3-mongodb.md, not a table here.
--
-- It audits ALL entities through the polymorphic (entity_type, entity_id) pair,
-- which is NOT a drawable foreign key.  The only real FK is the optional
-- `transaction_id` pointer to the operation that caused a change.
-- This table is append-only; immutability is enforced in step 11.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_logs (
    audit_log_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type     TEXT        NOT NULL,            -- 'wallet', 'account', 'transaction', ...
    entity_id       UUID        NOT NULL,            -- the changed row; polymorphic, so not a FK
    action          TEXT        NOT NULL,            -- 'CREATED', 'STATUS_CHANGED', 'FROZEN', ...
    old_state       JSONB,                           -- null on create
    new_state       JSONB,
    reason          TEXT,                            -- e.g. 'ops_manual_review', 'bank_declined'
    actor_id        UUID,                            -- account / user / service that caused the change
    actor_type      TEXT
        CONSTRAINT audit_logs_actor_type_ck CHECK (actor_type IN ('ACCOUNT', 'SERVICE', 'OPS_USER')),
    transaction_id  UUID,                            -- optional pointer to the causing operation
    request_id      UUID,                            -- trace to the Layer 3 activity event
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT audit_logs_transaction_fk
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
    ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor
    ON audit_logs (actor_id) WHERE actor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_transaction
    ON audit_logs (transaction_id) WHERE transaction_id IS NOT NULL;

COMMENT ON TABLE audit_logs IS 'Layer 2 audit: committed non-ledger state changes; polymorphic (entity_type, entity_id); append-only.';
