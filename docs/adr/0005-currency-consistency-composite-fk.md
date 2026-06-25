# 0005. Entry/wallet currency consistency is enforced by a composite foreign key

- Status: Accepted
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

A wallet is single-currency, and an entry carries its own `currency` (kept for the per-currency check, for partition and query, and as an immutable record). Nothing yet stopped an `entry.currency` from differing from its wallet's currency, which would corrupt the per-currency balance.

## Decision

Enforce consistency by construction. `wallet` carries `UNIQUE (wallet_id, currency)`, and `entry` has a composite foreign key `(wallet_id, currency) -> wallet`. Because `wallet_id` is the wallet PK (one currency per wallet), a mismatched currency becomes impossible. Both entry columns are `NOT NULL`, otherwise the default `MATCH SIMPLE` would skip the check when either is NULL.

## Consequences

- `wallet` needs the otherwise-redundant `UNIQUE (wallet_id, currency)` purely as the FK target.
- `entry.wallet_id` and `entry.currency` must be `NOT NULL`.
- Keeping `entry.currency` (rather than dropping it and joining to wallet) means the per-currency check and the partition key read straight off `entry`, and the entry stays a self-contained immutable record.

## Alternatives considered

- **Drop `entry.currency`, join to wallet for currency (option B)**: removes the duplication but loses the self-contained record and forces a join into the hot balance check and the partitioning.

## Provenance

This decision was AI-proposed and I approved it; unlike the encoding (ADR 0003) and idempotency (ADR 0006) decisions, it did not originate from my own argument. AI research (`0-research/vp-assessment-dba/04-postgres-schema-integrity-idempotency.md`) surfaced the gap, the option A vs option B trade-off, and the composite-FK technique, and recommended keeping `entry.currency` (option A); I reviewed it and accepted it as an immutable record.
