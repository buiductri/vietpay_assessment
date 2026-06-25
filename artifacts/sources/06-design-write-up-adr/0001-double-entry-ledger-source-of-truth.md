# 0001. Double-entry ledger is the source of truth; wallet balance is derived

- Status: Accepted
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

The assessment hands us a `transactions(id, wallet_id, type, amount, currency, status, created_at)` table as the entry point. Read literally, each such row is a single signed movement against one wallet, which is an *entry* in double-entry terms, not a balanced transaction. A payments ledger has to answer "what is this wallet's balance" and "do the books balance" with no room for drift.

## Decision

Model the core as two entities: a `transaction` (the journal header) and an `entry` (one debit or credit line against one wallet). Every transaction has two or more entries that balance. `wallet.balance` is a cache computed inside the posting transaction and is **never** the source of truth; the entries are. A scheduled `balance_audit` reconciles each wallet's cached balance against `SUM(entries)` and alerts on any nonzero discrepancy.

## Consequences

- Reads of "current balance" can use the cache, but correctness never depends on it; it is verifiable against the entries at any time.
- Every financial movement is a balanced, append-only record, which is the foundation for the per-currency and immutability invariants (ADR 0002, 0003).
- The given `transactions` table maps onto `entry`, not `transaction`; the naming is reconciled in CONTEXT.md.

## Provenance

The split and the "balance is never the source of truth" stance are mine, carried over from prior work on a customer-asset and balance-monitoring system. AI research on double-entry ledgers (`0-research/double-entry-ledger`) confirmed the terminology and the reconciliation pattern.
