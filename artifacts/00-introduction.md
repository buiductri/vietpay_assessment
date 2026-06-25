# Introduction: candidate, method, and authorship model

> Generated: 2026-06-25 | Axis: Overview | Primary sources: `00-introduction.md`, journal section 1

This briefing pack reorganizes the VietPay DBA assessment by its six tasks. It adds no new analysis: it re-presents the design journal and the committed documentation, keeping the candidate's reasoning verbatim and marking every AI-assisted contribution, the same human / `<ai>` split the journal itself uses.

> **Provenance key.** **<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** marks the candidate's own words, kept verbatim. **<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** marks AI-assisted content, including this reorganization itself.

## Who the candidate is, and how AI was used

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, `00-introduction.md`*

- My name is Bùi Đức Trí
- My experience is composite of SQL Server (7+ years) and MongoDB (5 years)
- My previous business domain do not related to fintech, but have a system that maintain customer assests and balance/transaction monitoring


- I will use AI for:
  - (1) research business context - this will help me to understand the business aspect related to fintech domain
  - (2) research about existing tool that support current problem (for example: pgledger)
  - (3) proofreeding and grammar/typo correcting
  - (4) auditing
  - (5) generation of pgSQL scripts and build up a prototype

## The starting frame: business domain and tech stack

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 1.1*

The assessment asks us to design a core data layer for fintech payments. This raises 2 issues for me: (1) I do not have experience with fintech and its terminology, and (2) the main tech stack is PostgreSQL, which we are studying, and it is not my main experience stack.

To cover our weaknesses here, we will utilize AI to help with the missing pieces. Then we will apply our previous knowledge about customer asset systems to resolve the given problem.

## On using the journal audit

**<span style="background:#10363a;color:#5eead4;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">OWNED (Bùi Đức Trí)</span>** *verbatim, journal section 1.3*

The audit shows my lack of knowledge of PostgreSQL. This is good, it gives me a pointer on how to address my gap here. Most of the clarification is for things I already know or awareness of what I lack. Some of it is kind of a misunderstanding because my thought wording is not clear enough, not that I do not know about that part, but I kind of forgot to include it in the thought. It's good to know how to clarify the thought. The final part is what the AI already assumes, like settlement; I will ignore this because of my lack of domain knowledge and stick to the technical aspect of the task. Lack of knowledge is not a bad thing; relying on AI for what I don't know is bad.

## How this pack marks authorship

**<span style="background:#2b2350;color:#c4b5fd;padding:2px 9px;border-radius:5px;font-size:.82em;letter-spacing:.04em">AI-GENERATED</span>** *this reorganization, derived from the report `README.md` "A note on authorship"*

The committed report already keeps authorship separable: the journal separates the candidate's reasoning from AI-assisted contributions inline (human feedback blocks vs `<ai>` markers); `CONTEXT.md` records standards as consensus decisions with trade-offs; each ADR carries a "Provenance" line; the AI-authored docs (`docs/query-performance.md`, `docs/observability.md`, `docs/audit-l3-mongodb.md`) are marked at their head; and `docs/ERD.md` / `docs/ERD.html` carry AI+/AI~ markers.

This pack carries that split into the research format. Each of the six task docs tags every block with an OWNED pill (the candidate's verbatim words) or an AI-GENERATED pill (AI-assisted content, including the synthesis prose written for this pack). The full primary sources are copied under `sources/` so the pack is self-contained.

## Sources

[1] Candidate background and how AI was used - (local: sources/journal/00-introduction.md)
[2] Design journal, section 1 (assessment analysis, first impressions, audit response) - (local: sources/journal/00-journal.md)
[3] Domain glossary, invariants, status machine - (local: sources/journal/CONTEXT.md)
