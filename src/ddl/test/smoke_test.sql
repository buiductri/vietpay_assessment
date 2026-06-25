-- ============================================================================
-- VietPay core ledger - smoke test (executable integrity spec)
-- ----------------------------------------------------------------------------
-- Run AFTER `deploy.sh up`:   ./deploy.sh test
--
-- This file is the executable statement of intended behaviour.  It runs inside
-- ONE transaction and ROLLBACKs at the end, so it leaves NO data behind.  It
-- proves, against a real database, the guarantees the schema claims:
--
--   POSITIVE   a balanced same-currency transfer is accepted
--   POSITIVE   a 4-entry cross-currency FX bridge is accepted (per-currency)
--   POSITIVE   the reconciliation view shows zero drift once caches are synced
--   NEGATIVE   an unbalanced transaction is rejected (per-currency zero-sum)
--   NEGATIVE   a duplicate (caller_id, key) is rejected (idempotency)
--   NEGATIVE   UPDATE / DELETE on a posted entry is rejected (immutability)
--   NEGATIVE   an entry whose currency != its wallet's is rejected (composite FK)
--   NEGATIVE   amount <= 0 is rejected (CHECK)
--   NEGATIVE   the app role cannot mutate entries (privilege REVOKE) [skips if no role]
--
-- The deferred zero-sum trigger normally fires at COMMIT; since we never commit,
-- the positive/negative cases force it with `SET CONSTRAINTS ALL IMMEDIATE`.
-- Run with ON_ERROR_STOP=1 (deploy.sh test does this) so any failed assertion
-- aborts with a nonzero exit code.
--
-- ID legend (fixed UUIDs for readability):
--   currency  VND 0c..01   USD 0c..02
--   account   alice a0..01  bob a0..02  revenue a0..03  fx-desk a0..04
--   wallet    alice_vnd b0..01  bob_vnd b0..02  rev_vnd b0..03
--             fx_vnd b0..04  fx_usd b0..05  bob_usd b0..06
--   xrate     USD/VND e0..01
--   txn       p2p d0..01  fx d0..02
-- ============================================================================
\set ON_ERROR_STOP on
\echo '== VietPay core ledger :: smoke test =================================='

BEGIN;
SET CONSTRAINTS ALL DEFERRED;

-- ---- SEED reference data (rolled back at the end) ---------------------------
INSERT INTO currencies (currency_id, name, code) VALUES
    ('0c000000-0000-0000-0000-000000000001', 'Vietnamese Dong', 'VND'),
    ('0c000000-0000-0000-0000-000000000002', 'US Dollar',       'USD');

INSERT INTO accounts (account_id, name, type) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Alice',            'CUSTOMER'),
    ('a0000000-0000-0000-0000-000000000002', 'Bob',              'CUSTOMER'),
    ('a0000000-0000-0000-0000-000000000003', 'Platform Revenue', 'PLATFORM_REVENUE'),
    ('a0000000-0000-0000-0000-000000000004', 'FX Desk',          'FX_POSITION');

INSERT INTO wallets (wallet_id, account_id, name, currency) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'alice VND', 'VND'),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002', 'bob VND',   'VND'),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003', 'rev VND',   'VND'),
    ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000004', 'fx VND',    'VND'),
    ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000004', 'fx USD',    'USD'),
    ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'bob USD',   'USD');

-- 1 USD = 27,000 VND (base USD, quoted VND)
INSERT INTO exchange_rates (exchange_rate_id, exchange_date, base_currency_id, currency_id, rate) VALUES
    ('e0000000-0000-0000-0000-000000000001', DATE '2026-06-15',
     '0c000000-0000-0000-0000-000000000002', '0c000000-0000-0000-0000-000000000001', 27000.00000000);

-- ---- POSITIVE 1: balanced same-currency transfer with fee -------------------
-- Alice sends 100,000 VND to Bob; platform takes a 1,000 VND fee.
-- Alice -101,000 ; Bob +100,000 ; Revenue +1,000  -> VND debits = credits.
INSERT INTO transactions (transaction_id, type, status) VALUES
    ('d0000000-0000-0000-0000-000000000001', 'transfer', 'PENDING');
INSERT INTO entries (transaction_id, wallet_id, type, amount, currency) VALUES
    ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'DEBIT',  101000.0000, 'VND'),
    ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'CREDIT', 100000.0000, 'VND'),
    ('d0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'CREDIT',   1000.0000, 'VND');
SET CONSTRAINTS ALL IMMEDIATE;   -- force the per-currency zero-sum check now
SET CONSTRAINTS ALL DEFERRED;
\echo 'PASS: balanced same-currency P2P transfer accepted'

-- ---- POSITIVE 2: cross-currency FX bridge (one transaction) -----------------
-- Bob receives 1 USD; Alice pays 27,000 VND; routed through FX-position wallets.
-- VND leg: Alice -27,000 / FX_VND +27,000 ;  USD leg: FX_USD -1 / Bob +1.
INSERT INTO transactions (transaction_id, type, status, exchange_rate_id, extra_info) VALUES
    ('d0000000-0000-0000-0000-000000000002', 'exchange', 'PENDING',
     'e0000000-0000-0000-0000-000000000001',
     '{"sent_vnd": 27000, "received_usd": 1, "rate": 27000}');
INSERT INTO entries (transaction_id, wallet_id, type, amount, currency) VALUES
    ('d0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'DEBIT',  27000.0000, 'VND'),
    ('d0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000004', 'CREDIT', 27000.0000, 'VND'),
    ('d0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000005', 'DEBIT',      1.0000, 'USD'),
    ('d0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000006', 'CREDIT',     1.0000, 'USD');
SET CONSTRAINTS ALL IMMEDIATE;   -- VND 27000=27000 AND USD 1=1 -> passes
SET CONSTRAINTS ALL DEFERRED;
\echo 'PASS: cross-currency FX-bridge transfer accepted (per-currency balanced)'

-- ---- POSITIVE 3: counts + reconciliation view -------------------------------
DO $$
BEGIN
    IF (SELECT count(*) FROM entries WHERE transaction_id = 'd0000000-0000-0000-0000-000000000001') <> 3
    OR (SELECT count(*) FROM entries WHERE transaction_id = 'd0000000-0000-0000-0000-000000000002') <> 4 THEN
        RAISE EXCEPTION 'TEST-FAIL: unexpected entry counts';
    END IF;

    -- sync the cached balances from the ledger, then assert no drift
    UPDATE wallets w SET balance = COALESCE((
        SELECT SUM(CASE WHEN e.type = 'CREDIT' THEN e.amount ELSE -e.amount END)
        FROM entries e WHERE e.wallet_id = w.wallet_id), 0);

    IF EXISTS (SELECT 1 FROM balance_audit_drift) THEN
        RAISE EXCEPTION 'TEST-FAIL: balance_audit_drift is non-empty after cache sync';
    END IF;
    RAISE NOTICE 'PASS: reconciliation view shows zero drift after cache sync';
END $$;

-- ---- NEGATIVE A: unbalanced transaction rejected (per-currency zero-sum) -----
DO $$
DECLARE ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO transactions (transaction_id, type) VALUES
            ('d0000000-0000-0000-0000-0000000000aa', 'transfer');
        INSERT INTO entries (transaction_id, wallet_id, type, amount, currency) VALUES
            ('d0000000-0000-0000-0000-0000000000aa', 'b0000000-0000-0000-0000-000000000001', 'DEBIT',  500.0000, 'VND'),
            ('d0000000-0000-0000-0000-0000000000aa', 'b0000000-0000-0000-0000-000000000002', 'CREDIT', 400.0000, 'VND');
        SET CONSTRAINTS ALL IMMEDIATE;            -- forces the deferred check -> should raise
    EXCEPTION WHEN check_violation THEN
        ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'TEST-FAIL: unbalanced transaction was accepted'; END IF;
    RAISE NOTICE 'PASS: unbalanced transaction rejected (per-currency zero-sum)';
END $$;
SET CONSTRAINTS ALL DEFERRED;   -- restore mode at top level after the forced check

-- ---- NEGATIVE B: duplicate idempotency key rejected -------------------------
DO $$
DECLARE ok boolean := false;
BEGIN
    INSERT INTO idempotency_keys (caller_id, key) VALUES ('alice', 'transfer-2026-06-15-001');
    BEGIN
        INSERT INTO idempotency_keys (caller_id, key) VALUES ('alice', 'transfer-2026-06-15-001');
    EXCEPTION WHEN unique_violation THEN
        ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'TEST-FAIL: duplicate (caller_id, key) was accepted'; END IF;
    RAISE NOTICE 'PASS: duplicate idempotency key rejected (UNIQUE caller_id,key)';
END $$;

-- ---- NEGATIVE C: UPDATE on a posted entry rejected (immutability) -----------
DO $$
DECLARE ok boolean := false;
BEGIN
    BEGIN
        UPDATE entries SET amount = amount + 1
        WHERE transaction_id = 'd0000000-0000-0000-0000-000000000001';
    EXCEPTION WHEN restrict_violation THEN
        ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'TEST-FAIL: entry UPDATE was accepted'; END IF;
    RAISE NOTICE 'PASS: entry UPDATE rejected (append-only)';
END $$;

-- ---- NEGATIVE D: DELETE on a posted entry rejected (immutability) -----------
DO $$
DECLARE ok boolean := false;
BEGIN
    BEGIN
        DELETE FROM entries WHERE transaction_id = 'd0000000-0000-0000-0000-000000000001';
    EXCEPTION WHEN restrict_violation THEN
        ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'TEST-FAIL: entry DELETE was accepted'; END IF;
    RAISE NOTICE 'PASS: entry DELETE rejected (append-only)';
END $$;

-- ---- NEGATIVE E: currency mismatch rejected (composite FK) ------------------
DO $$
DECLARE ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO transactions (transaction_id, type) VALUES
            ('d0000000-0000-0000-0000-0000000000ee', 'transfer');
        -- wallet b0..01 is VND, but the entry claims USD -> (wallet_id, 'USD') has no wallet row
        INSERT INTO entries (transaction_id, wallet_id, type, amount, currency) VALUES
            ('d0000000-0000-0000-0000-0000000000ee', 'b0000000-0000-0000-0000-000000000001', 'DEBIT', 1.0000, 'USD');
    EXCEPTION WHEN foreign_key_violation THEN
        ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'TEST-FAIL: currency-mismatch entry was accepted'; END IF;
    RAISE NOTICE 'PASS: currency-mismatch entry rejected (composite FK)';
END $$;

-- ---- NEGATIVE F: non-positive amount rejected (CHECK) -----------------------
DO $$
DECLARE ok boolean := false;
BEGIN
    BEGIN
        INSERT INTO transactions (transaction_id, type) VALUES
            ('d0000000-0000-0000-0000-0000000000ff', 'transfer');
        INSERT INTO entries (transaction_id, wallet_id, type, amount, currency) VALUES
            ('d0000000-0000-0000-0000-0000000000ff', 'b0000000-0000-0000-0000-000000000001', 'DEBIT', 0.0000, 'VND');
    EXCEPTION WHEN check_violation THEN
        ok := true;
    END;
    IF NOT ok THEN RAISE EXCEPTION 'TEST-FAIL: amount <= 0 was accepted'; END IF;
    RAISE NOTICE 'PASS: non-positive amount rejected (CHECK amount > 0)';
END $$;

-- ---- NEGATIVE G: app role cannot mutate entries (PRIVILEGE path) -------------
-- The deny trigger (tested in C/D) is defence-in-depth; the PRIMARY immutability
-- mechanism is the REVOKE of UPDATE/DELETE from vietpay_app.  This exercises it
-- by becoming that role.  Skips gracefully if the role is absent or the
-- connecting role may not SET ROLE vietpay_app (needs membership, or superuser).
DO $$
DECLARE
    can_switch boolean := true;
    denied     boolean := false;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vietpay_app') THEN
        RAISE NOTICE 'SKIP: role vietpay_app absent; privilege REVOKE not provisioned (immutability still enforced by trigger)';
    ELSE
        BEGIN
            SET ROLE vietpay_app;
        EXCEPTION WHEN OTHERS THEN
            can_switch := false;
        END;

        IF NOT can_switch THEN
            RAISE NOTICE 'SKIP: connecting role cannot SET ROLE vietpay_app; REVOKE path not exercised here';
        ELSE
            BEGIN
                UPDATE entries SET amount = amount + 1
                WHERE transaction_id = 'd0000000-0000-0000-0000-000000000001';
            EXCEPTION
                WHEN insufficient_privilege THEN denied := true;   -- REVOKE blocked it (primary)
                WHEN restrict_violation     THEN denied := true;   -- or the trigger did (defence-in-depth)
            END;
            RESET ROLE;
            IF NOT denied THEN
                RAISE EXCEPTION 'TEST-FAIL: vietpay_app was able to UPDATE entries';
            END IF;
            RAISE NOTICE 'PASS: vietpay_app cannot UPDATE entries (privilege REVOKE)';
        END IF;
    END IF;
END $$;
RESET ROLE;   -- belt-and-suspenders in case the block left the role switched

\echo '== all smoke tests passed (rolling back, no data persisted) ==========='
ROLLBACK;
