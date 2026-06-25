/* ============================================================
   content.js - VietPay DBA Assessment briefing pack
   Reorganization of 00-journal.md + docs/ into the /research format.
   No new analysis: every figure/diagram here is reused or transcribed
   from the committed deliverable. Accents: cyan ember amber violet green.
   ============================================================ */

window.SITE = {
  brand: "VIETPAY",
  classification: "ASSESSMENT",
  title: "VietPay DBA <b>Briefing Pack</b>",
  titlePlain: "Assessment Report - VietPay DBA Briefing Pack",
  subtitle: "six tasks, authorship marked",
  description:
    "A research-format reorganization of the VietPay Enterprise Database Architect take-home, by its six tasks, with the candidate's reasoning kept verbatim and every AI-assisted contribution marked.",
  foot: ["SCOPE  7 docs - 6 tasks", "BUILT  2026-06-25"],
  metric: { label: "TASKS", value: "6" },

  hero: {
    kicker: "Enterprise Database Architect - Fintech - take-home",
    headline:
      'A payments ledger, <span class="g">designed and reasoned</span>, with <span class="e">owned vs AI</span> kept separable.',
    lede: "This pack re-presents the design journal and committed docs, one document per assessment task. <b>Teal pills are the candidate's verbatim words; violet pills are AI-assisted</b>, the same split the journal uses.",
  },

  stats: [
    ["6", "tasks", "by the assessment", "cyan"],
    ["9", "entities", "relational core, validated PG 17.2", "violet"],
    ["26x", "fewer buffer reads", "Task 2, measured", "amber"],
    ["1.4ms", "SET NOT NULL", "Task 3, vs 581ms naive", "green"],
  ],

  sections: {
    map: "The ledger at a glance",
    synthesis: "Threads across all six tasks",
    compare: "Who wrote what, per task",
    briefing: "Full index (README)",
  },

  docs: [
    { id: "doc-00", accent: "cyan", sub: "overview" },
    { id: "doc-01", accent: "cyan", sub: "Task 1 - core model", star: true },
    { id: "doc-02", accent: "amber", sub: "Task 2 - performance", star: true },
    { id: "doc-03", accent: "ember", sub: "Task 3 - migration", star: true },
    { id: "doc-04", accent: "violet", sub: "Task 4 - polyglot" },
    { id: "doc-05", accent: "green", sub: "Task 5 - observability" },
    { id: "doc-06", accent: "cyan", sub: "Task 6 - ADR" },
  ],

  drill: {
    kicker: "Practice - reveal mode",
    headline: 'Drill - <span class="e">rehearse the design</span>',
    lede: "Read the prompt, answer aloud, then reveal. Grounded in the committed deliverable.",
  },
};

/* Overview "insights" cards - the cross-axis threads (AI synthesis for this pack). */
window.INSIGHTS = [
  {
    ix: "01",
    a: "cyan",
    t: "One source of truth",
    p: "The relational ledger entries are authoritative; wallet.balance, the summary rollup, and the MongoDB/Neo4j stores are all rebuildable projections, never the financial source of truth.",
    ref: "tasks 1 - 2 - 4",
  },
  {
    ix: "02",
    a: "violet",
    t: "By construction, not by hope",
    p: "Per-currency zero-sum, currency consistency, idempotency, and immutability are schema-level guarantees; observability just puts a panel on what the schema already exposes.",
    ref: "tasks 1 - 5",
  },
  {
    ix: "03",
    a: "amber",
    t: "Honest about the PG gap",
    p: "PostgreSQL is not the candidate's main stack; AI fills the PG-specific mechanics (query plans, migration internals, metric names) and those parts are marked, not claimed.",
    ref: "tasks 2 - 3 - 5",
  },
  {
    ix: "04",
    a: "green",
    t: "Best tool, proven not assumed",
    p: "Task 4 insists on a litmus that the fraud ring is genuinely a graph problem, and names the boundary where JSONB or Postgres is the right call instead.",
    ref: "task 4",
  },
  {
    ix: "05",
    a: "ember",
    t: "The entry split propagates",
    p: "Mapping the flat transactions table onto transaction + entry turns the report into a join and places the migration on entries; the tasks are not independent.",
    ref: "tasks 1 - 2 - 3",
  },
];

/* Overview comparison matrix - the owned / AI split per task (the pack's whole point). */
window.MATRIX = {
  filters: [
    { label: "All", value: "all" },
    { label: "Owned-led", value: "own" },
    { label: "AI-led", value: "ai", accent: "violet" },
  ],
  columns: ["Task", "Owned (Bùi Đức Trí)", "AI-assisted", "Validated"],
  rows: [
    {
      cat: "own",
      cells: [
        { name: "1 Core model", sub: "ledger + ERD + DDL" },
        { pill: "yes", text: "entities, FX, idempotency, audit choice" },
        { pill: "evt", text: "ERD audit, DDL generation" },
        "PG 17.2",
      ],
    },
    {
      cat: "ai",
      cells: [
        { name: "2 Query & perf", sub: "settlement report" },
        { pill: "yes", text: "reasoning, partitioning, DDL" },
        { pill: "evt", text: "query-plan analysis" },
        "PG 17.2",
      ],
    },
    {
      cat: "ai",
      cells: [
        { name: "3 Migration", sub: "expand-contract" },
        { pill: "yes", text: "deployment-planning shape" },
        { pill: "evt", text: "PG expand-contract + rollback" },
        "PG 17.2",
      ],
    },
    {
      cat: "own",
      cells: [
        { name: "4 Polyglot", sub: "Mongo + Neo4j" },
        { pill: "yes", text: "MongoDB Layer 3 reasoning" },
        { pill: "evt", text: "Neo4j model + Cypher, why-over-JSONB" },
        "node --check",
      ],
    },
    {
      cat: "ai",
      cells: [
        { name: "5 Observability", sub: "Grafana" },
        { pill: "yes", text: "two-layer split, metric list, T10 rule" },
        { pill: "evt", text: "dashboard, SLOs, alert table" },
        "design",
      ],
    },
    {
      cat: "own",
      cells: [
        { name: "6 ADR", sub: "decisions + contracts" },
        { pill: "yes", text: "ADRs in his voice, 0001-0007" },
        { pill: "evt", text: "consistency audit vs schema" },
        "cross-check",
      ],
    },
  ],
};

/* Visualisations - all reused or transcribed from the committed deliverable. */
window.VIZ = {
  overview: [
    {
      kind: "mermaid",
      accent: "cyan",
      tag: "ERD",
      title: "Core payments ledger",
      meta: "entity-relationship (from docs/ERD.md)",
      cap: "The audited nine-entity model. <b>account owns wallets; a transaction has two or more balancing entries</b>; audit_log is detached (polymorphic).",
      def: `erDiagram
  account          ||--o{ wallet        : "owns"
  transaction      ||--|{ entry         : "has 2 or more"
  wallet           ||--o{ entry         : "targeted by"
  idempotency_key  ||--o| transaction   : "maps to"
  exchange_rate    |o--o{ transaction   : "rates"
  currency         ||--o{ exchange_rate : "base"
  account {
    uuid account_id PK
    text type "CUSTOMER PLATFORM_FLOAT FX_POSITION"
  }
  wallet {
    uuid wallet_id PK
    char currency "unique with wallet_id"
    text kind "regular or holding"
    numeric balance "derived, never source of truth"
  }
  transaction {
    uuid transaction_id PK
    text status "PENDING SETTLED REVERSED"
    uuid exchange_rate_id FK "pinned rate, nullable"
  }
  entry {
    uuid entry_id PK
    text type "DEBIT or CREDIT"
    numeric amount "positive; direction in type"
    char currency "= wallet.currency (FK)"
  }
  idempotency_key {
    text key "unique with caller_id"
    timestamptz expires_at "cleanup window"
  }
  exchange_rate {
    uuid exchange_rate_id PK
    numeric rate
  }
  currency {
    char code "ISO 4217"
  }`,
    },
  ],
  "doc-01": [
    {
      kind: "mermaid",
      accent: "violet",
      tag: "STATE",
      title: "Transaction status machine",
      meta: "state (from CONTEXT.md)",
      at: "Entities: explore",
      cap: "<b>PENDING to SETTLED or REVERSED</b>. REVERSED is reached by posting a new reversing transaction, never by mutating the original; an entry has no status of its own.",
      def: `stateDiagram-v2
  [*] --> PENDING
  PENDING --> SETTLED
  PENDING --> REVERSED : reversing transaction
  SETTLED --> [*]
  REVERSED --> [*]`,
    },
  ],
  "doc-02": [
    {
      kind: "chart",
      accent: "amber",
      tag: "CHART",
      title: "Shared-buffer reads: flat vs partitioned",
      meta: "bar - measured on PostgreSQL 17.2",
      at: "Empirical performance",
      cap: "About 26x fewer shared-buffer reads after partition pruning + index-only header (both at a matched work_mem). Real EXPLAIN (ANALYZE, BUFFERS) numbers from src/ddl/perf/bench.sql.",
      chart: {
        type: "bar",
        data: {
          labels: ["flat baseline", "partitioned + covering index"],
          datasets: [
            {
              label: "shared-buffer reads",
              data: [68300, 2570],
              backgroundColor: ["#d96a4a", "#2fe3cf"],
              borderRadius: 6,
            },
          ],
        },
        options: {
          plugins: { legend: { display: false } },
          scales: {
            y: { grid: { color: "#1d2531" }, ticks: { color: "#5f6b7c" } },
            x: { grid: { display: false }, ticks: { color: "#9aa6b8" } },
          },
        },
      },
    },
  ],
  "doc-03": [
    {
      kind: "chart",
      accent: "green",
      tag: "CHART",
      title: "SET NOT NULL: fast path vs naive",
      meta: "bar - measured on 2,000,000 rows",
      at: "realized migration",
      cap: "The CHECK NOT VALID to VALIDATE to SET NOT NULL fast path is <b>1.4 ms</b> versus <b>581 ms</b> for a naive scanning SET NOT NULL; the verification scan moves into VALIDATE (non-blocking).",
      chart: {
        type: "bar",
        data: {
          labels: ["naive SET NOT NULL", "fast-path SET NOT NULL"],
          datasets: [
            {
              label: "milliseconds",
              data: [581, 1.4],
              backgroundColor: ["#d96a4a", "#4ddb8b"],
              borderRadius: 6,
            },
          ],
        },
        options: {
          plugins: { legend: { display: false } },
          scales: {
            y: { grid: { color: "#1d2531" }, ticks: { color: "#5f6b7c" } },
            x: { grid: { display: false }, ticks: { color: "#9aa6b8" } },
          },
        },
      },
    },
  ],
};

/* Drill - Q&A reveal cards grounded in the deliverable. */
window.DRILL = [
  {
    n: "Q1",
    q: "Why does the assessment's flat transactions row become an entry, not a transaction?",
    core: "A single signed movement against one wallet is an entry in double-entry terms, not a balanced transaction. The core splits into a transaction header plus two or more balancing entry lines.",
    bullets: [
      "Each transaction: 1 CREDIT (+) and 1 DEBIT (-) summing to zero, per currency",
      "The 50M rows live in entries, which is why Task 2 is a join and Task 3 targets entries",
    ],
  },
  {
    n: "Q2",
    q: "Why per-currency zero-sum rather than a global signed total?",
    core: "A currency-blind total can be fooled: an imbalance in one currency can cross-cancel an imbalance in another and still net to zero globally.",
    bullets: [
      "Per-currency is strictly stronger and cannot be fooled this way",
      "Enforced by a DEFERRABLE INITIALLY DEFERRED constraint trigger at COMMIT",
    ],
  },
  {
    n: "Q3",
    q: "On an append-only entries table, how does a NOT NULL backfill happen at all?",
    core: "The backfill is a privileged DBA migration that temporarily disables the deny trigger for the backfill window; the privilege REVOKE still holds, so the application still cannot rewrite history.",
    bullets: [
      "Two-layer immutability (REVOKE + trigger) is what makes this safe",
      "Backfill runs partition by partition; ctid is unique only within one partition",
    ],
  },
  {
    n: "Q4",
    q: "What makes the fraud ring genuinely a graph problem?",
    core: "If you remove most of the edges and the application still works, it is not a graph problem; if the edges are the application, it is. A fraud ring exists only in the connection structure.",
    bullets: [
      "Variable, unknown hop count (a ring might be 2 or 6 hops)",
      "Structural answer (a cycle) not a row; an N-hop ring is an N-way recursive join in SQL",
    ],
  },
  {
    n: "Q5",
    q: "Why is balance reconciliation the headline alert (Task 5)?",
    core: "wallet.balance is a cache, never the source of truth. balance_audit_drift is already a view in the DDL, so the most important alert is a row count off that view: target 0, any nonzero pages.",
    bullets: [
      "Integrity is a hard invariant, not a percentile SLO with an error budget",
      "This is the T10 reconciliation rule from Task 1 made operational",
    ],
  },
];
