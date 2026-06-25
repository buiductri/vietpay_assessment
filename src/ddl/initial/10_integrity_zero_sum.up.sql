-- ============================================================================
-- VietPay core ledger | initial 10 (up): zero-sum invariant (per currency)
-- Source of truth: docs/ERD.md  ("Zero-sum, per currency"); journal T2
-- One-time baseline. Idempotent. Reverse: 10_integrity_zero_sum.down.sql
-- Target: PostgreSQL 14+   Depends on: 07 entries
-- ============================================================================
-- THE balance guarantee, enforced by the schema (not by application hope).
--
-- Within EACH currency of a transaction:
--     SUM(amount WHERE type = 'DEBIT') = SUM(amount WHERE type = 'CREDIT')
--
-- Per currency, not a single global total (journal T2): a currency-blind total
-- can be fooled because an imbalance in one currency can cross-cancel an
-- imbalance in another and still net to zero globally (e.g. a 27,000 VND debit
-- "balancing" a 27,000 USD credit leaks ~27,000x value but passes a global
-- check).  The per-currency check is strictly stronger.  The FX rate never
-- enters this check; a cross-currency transfer is two balanced single-currency
-- legs bridged through the platform's FX-position wallets.
--
-- A CHECK constraint cannot do this (it cannot see other rows), so we use a
-- CONSTRAINT TRIGGER that is DEFERRABLE INITIALLY DEFERRED: it fires at COMMIT,
-- after all legs of the transaction are inserted, and rolls the whole
-- transaction back if any currency is unbalanced.  Entries are immutable
-- (step 11), so AFTER INSERT is the only event that can change a balance.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION assert_transaction_balanced()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    bad RECORD;
BEGIN
    -- Find the first currency in this transaction whose debits != credits.
    SELECT e.currency,
           COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'DEBIT'),  0) AS debits,
           COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'CREDIT'), 0) AS credits
      INTO bad
      FROM entries e
     WHERE e.transaction_id = NEW.transaction_id
     GROUP BY e.currency
    HAVING COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'DEBIT'),  0)
        <> COALESCE(SUM(e.amount) FILTER (WHERE e.type = 'CREDIT'), 0)
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Ledger imbalance in transaction % for currency %: debits=% credits=%',
            NEW.transaction_id, bad.currency, bad.debits, bad.credits
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;  -- AFTER ... FOR EACH ROW: return value is ignored
END;
$$;

COMMENT ON FUNCTION assert_transaction_balanced() IS
    'Deferred per-currency zero-sum check: every currency in a transaction must have SUM(DEBIT)=SUM(CREDIT) at COMMIT.';

-- CREATE CONSTRAINT TRIGGER has no IF NOT EXISTS; drop-then-create for idempotency.
DROP TRIGGER IF EXISTS trg_entries_balanced ON entries;
CREATE CONSTRAINT TRIGGER trg_entries_balanced
    AFTER INSERT ON entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION assert_transaction_balanced();
