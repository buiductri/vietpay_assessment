-- ============================================================================
-- VietPay core ledger | initial 12 (up): reconciliation view + app grants
-- Source of truth: docs/ERD.md  ("Reconciliation"; "Derived balance")
-- One-time baseline. Idempotent. Reverse: 12_reconciliation_view.down.sql
-- Target: PostgreSQL 14+   Depends on: all prior steps
-- ============================================================================
-- `wallets.balance` is a cache, not the source of truth.  `balance_audit`
-- recomputes the authoritative balance from the entries (SUM(CREDIT) -
-- SUM(DEBIT), since CREDIT = money into the wallet, DEBIT = money out) and
-- exposes the discrepancy.  A scheduled job reads `balance_audit_drift` and
-- alerts on any nonzero row (detailed alerting is Task 5, observability).
--
-- Joining on wallet_id alone is correct: a wallet is single-currency and the
-- entries composite FK forces every entry's currency to match its wallet, so
-- all of a wallet's entries share one currency.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW balance_audit AS
SELECT
    w.wallet_id,
    w.currency,
    w.balance AS cached_balance,
    COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'CREDIT'), 0)
  - COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'DEBIT'),  0) AS computed_balance,
    w.balance
      - ( COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'CREDIT'), 0)
        - COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'DEBIT'),  0) ) AS discrepancy
FROM wallets w
LEFT JOIN entries e ON e.wallet_id = w.wallet_id
GROUP BY w.wallet_id, w.currency, w.balance;

COMMENT ON VIEW balance_audit IS 'Cached wallets.balance vs authoritative SUM(entries); discrepancy should be 0.';

-- Convenience view for the scheduled reconciliation/alerting job: only drift.
CREATE OR REPLACE VIEW balance_audit_drift AS
SELECT * FROM balance_audit WHERE discrepancy <> 0;

COMMENT ON VIEW balance_audit_drift IS 'Rows where cached balance has drifted from the ledger; any row = integrity alert.';

-- ----------------------------------------------------------------------------
-- Least-privilege grants for the application role.  Guarded: applied only if
-- vietpay_app exists (see step 01).  vietpay_app is not the object owner, so it
-- has ONLY what is granted here (plus entries/audit_logs from step 11).  No
-- DELETE on financial history; idempotency_keys allows DELETE so a cleanup job
-- can sweep expired keys.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        GRANT SELECT                         ON currencies, exchange_rates       TO vietpay_app;
        GRANT SELECT, INSERT, UPDATE         ON accounts, wallets, transactions  TO vietpay_app;
        GRANT SELECT, INSERT, UPDATE, DELETE ON idempotency_keys                 TO vietpay_app;
        GRANT SELECT                         ON balance_audit, balance_audit_drift TO vietpay_app;
        RAISE NOTICE 'applied table/view grants for vietpay_app';
    ELSE
        RAISE NOTICE 'vietpay_app absent; skipped grants. Re-run step 12 after provisioning the role.';
    END IF;
END
$$;
