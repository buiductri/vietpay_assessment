# 0006. Idempotency is scoped to (caller_id, key) on a single-atomic-posting assumption

- Status: Accepted
- Date: 2026-06-25
- Deciders: Bùi Đức Trí

## Context

Idempotency prevents a retried or duplicated request from posting twice. Client-supplied keys are only unique per caller, so the dedup scope must include the caller. A well-known pattern (Brandur's) adds lifecycle fields (`recovery_point`, `locked_at`, `response_code`/`response_body`) to recover a request that died part-way through.

## Decision

Track idempotency in an `idempotency_key` entity with `UNIQUE (caller_id, key)`; a duplicate is rejected and mapped to the original transaction. The key is **claimed inside the business transaction**. Keep only `expires_at` (a retention marker for a cleanup/watchdog job). Do **not** add the Brandur lifecycle fields.

## Consequences

- A duplicate `(caller_id, key)` is rejected by the unique constraint; the original transaction id is returned.
- Because the claim is inside the posting transaction, a rollback releases the key, and PostgreSQL crash-recovery rolls back any uncommitted transaction on restart, so a crash leaves no partial state and nothing to recover.
- This holds **only** for a single atomic posting. A multi-step flow that commits each step separately, with non-rollback-able external calls between steps, would need the lifecycle state; that is a different design, out of scope here, and would be revisited per the business flow.

## Alternatives considered

- **Global unique `key`**: wrong, since keys are only unique per caller.
- **Brandur lifecycle fields**: real value for multi-step flows, nothing for a single atomic posting; rejected here to avoid modelling state that cannot occur in this design.

## Provenance

The `(caller_id, key)` scoping was surfaced by AI research. Rejecting the lifecycle fields is my own argument: for a single atomic posting the claim-in-transaction plus crash-recovery semantics leave no in-between state, so `recovery_point`/`locked_at` have no role. `expires_at` is kept for operational cleanup.
