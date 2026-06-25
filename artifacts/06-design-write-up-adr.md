# Task 6: Design write-up (ADR)

> Generated: 2026-06-25 | Axis: Architecture Decision Records | Primary sources: journal section 1.2 and 2.3, `docs/adr/`, `CONTEXT.md`

This axis reorganizes the existing Task 6 material: the candidate's ADR set (authored in his own voice, with AI-surfaced facts noted per ADR), and the AI consistency audit that checked the extracted docs against the committed schema before commit.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content. This mirrors the journal's own human / `<ai>` split.

## TL;DR

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 1.2 and the ADR README*

"Our analysis can cover most of the ADR here, but the task requires some more thought about standards and the microservices aspect, so I need to cover them too." The ADRs "are authored in my own voice as the candidate (Bùi Đức Trí). Where AI-assisted research surfaced a fact, a gap, or a technique, the "Provenance" section of that ADR says so, so my own reasoning stays separable from the AI's contribution." The three forward-looking decisions are framed as Proposed placeholders: "None is decided."

---

## Key Findings

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the accepted decisions, `docs/adr/`*

- **0001** Double-entry ledger is the source of truth; wallet balance is derived.
- **0002** Zero-sum enforced per currency, by a deferred constraint trigger.
- **0003** Entry amount is a positive magnitude with direction in `type` (standards choice).
- **0004** Cross-currency transfers use currency-pure wallets and house FX wallets.
- **0005** Entry/wallet currency consistency by composite foreign key.
- **0006** Idempotency scoped to `(caller_id, key)` on a single-atomic-posting assumption.
- **0007** Three-layer audit; Layer 2 in Postgres, Layer 3 in MongoDB; no trigger audit.

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *the open decisions the assessment Task 6 calls for, framed as Proposed*

- **0008** Strong vs eventual consistency across microservices.
- **0009** Data contracts between services (ownership, transport, versioning).
- **0010** TEXT + CHECK vs native ENUM for status/type columns (DDL standard).

---

## Detailed Analysis

### The candidate's design write-up note and authorship model

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 1.2 and the ADR README intro*

(journal 1.2) Our analysis can cover most of the ADR here, but the task requires some more thought about standards and the microservices aspect, so I need to cover them too.

(`docs/adr/README.md`) Decisions for the VietPay core payments ledger, extracted from the design journal (`../../00-journal.md`) and the audited model (`../ERD.md`). Each record is one decision. These are authored in my own voice as the candidate (Bùi Đức Trí). Where AI-assisted research surfaced a fact, a gap, or a technique, the "Provenance" section of that ADR says so, so my own reasoning stays separable from the AI's contribution.

### Example of the per-ADR provenance line (ADR 0001)

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, `docs/adr/0001` Provenance section*

> The split and the "balance is never the source of truth" stance are mine, carried over from prior work on a customer-asset and balance-monitoring system. AI research on double-entry ledgers (`0-research/double-entry-ledger`) confirmed the terminology and the reconciliation pattern.

The full set of accepted ADRs (0001 to 0007) and the Proposed placeholders (0008 to 0010) are in [`docs/adr/`](sources/06-design-write-up-adr/adr-index.md), each carrying its own Context, Decision, Consequences, and Provenance.

### The consistency audit before commit

The standing design documents (the `CONTEXT.md` glossary and invariants, the Task 6 ADRs, and the report `README.md`) restate decisions already reasoned through. Before committing them the candidate had the model cross-check that they describe the schema as actually built, not as remembered.

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 2.3*

The standing design documents (the `CONTEXT.md` glossary and invariants, the Task 6 ADRs under `docs/adr/`, and a report `README.md`) restate decisions already reasoned through above. Before committing them I wanted to confirm they describe the schema as actually built, not as I remembered it. Extracted docs regress fast, so this pass guards against the restatement drifting away from the DDL. I had the model run the cross-check explicitly.

---

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *verbatim, the `<ai>` block in journal section 2.3*

Rescanned every concrete claim in `CONTEXT.md` and the ten ADRs against the committed schema (`src/ddl/`), the smoke test, and `docs/ERD.md`:

- The seven accepted ADRs (0001-0007) match the DDL: the transaction/entry split with a derived balance, the per-currency `DEFERRABLE INITIALLY DEFERRED` zero-sum trigger, positive-amount with direction in `type`, currency-pure plus house-FX wallets, the composite-FK currency consistency, `UNIQUE (caller_id, key)` idempotency, and the three-layer audit with a polymorphic `audit_logs`.
- CONTEXT's domain terms, key invariants, the `{PENDING, SETTLED, REVERSED}` status machine, and the money/id types all match.
- ADR 0002's and the README's claims about the smoke test were checked against `test/smoke_test.sql` directly.

Two drifts were found and fixed in the same commit:

- **ADR 0010** listed `transaction.type` among the `TEXT + CHECK` columns. In the DDL `transaction.type` is deliberately open `TEXT` with no `CHECK` (its vocabulary is spec-dependent). Corrected the ADR to name it as the exception.
- **`06_transaction.up.sql`** carried a comment saying `CONTEXT.md` "sketches a fuller PROCESSING/FAILED machine". CONTEXT had since been rewritten to record those states as dropped, so the comment was stale. Made it self-contained.

> **Human direction (Bùi Đức Trí):** Audit the extracted ADRs and CONTEXT against the current project before committing, and only commit if they are consistent. The extracted docs exist to be a faithful restatement of the design as built, so a claim that no longer matches the schema (like the `transaction.type` CHECK) is exactly what this pass is meant to catch. One open item to settle later: the ADR "Provenance" lines point at `0-research/` and `../1-assessment/`, which sit in the parent workspace, outside this report repo. They resolve across the whole workspace but would dangle if the report ever ships on its own; whether to inline them is a packaging decision I will make then.

## Open Questions

*The Proposed ADRs, from `docs/adr/README.md` (verbatim).*

These decisions the assessment (Task 6) calls for are not yet made; the journal flags them as needing more thought. Each has a placeholder ADR (Status: Proposed) that frames the open question and the trade-offs. **None is decided.**

- **0008** Strong vs eventual consistency across microservices.
- **0009** Data contracts between services (ownership, transport, versioning).
- **0010** TEXT + CHECK vs native ENUM for status/type columns.

## Sources

[1] Design journal, section 1.2 and 2.3 (candidate's reasoning + AI consistency audit), verbatim - (local: sources/journal/00-journal.md)
[2] ADR index (authored in the candidate's voice, with per-ADR Provenance) - (local: sources/06-design-write-up-adr/adr-index.md)
[3] Accepted ADRs 0001-0007 and Proposed 0008-0010 - (local: sources/06-design-write-up-adr/0001-double-entry-ledger-source-of-truth.md)
[4] Domain glossary, invariants, flagged-ambiguities resolutions - (local: sources/journal/CONTEXT.md)
