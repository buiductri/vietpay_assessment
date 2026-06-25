/* ============================================================
   contract.js - the SHARED ADAPTER RULES, one runtime-agnostic home.
   Pure string logic that the two adapters must agree on:
     • engine.js (browser)  wraps it for DOM mutation (rows, cites, anchors, nav)
     • verify.mjs (node)    wraps it for assertions  ([N] resolves, anchors/links match)
   UMD: attaches to globalThis in a browser, module.exports under node.
   No DOM, no fs, no deps - just the parsing/selection/matching rules.

   The rules (also documented in REFERENCE.md):
     • Source contract - a doc's `## Sources` block is rows of
       `[N] Title - URL (local: sources/…)`; inline `[N]` resolves to row N.
     • Viz anchor - a panel's `at:` matches a heading by case-insensitive substring.
     • Cross-Doc link - a target ending in `<name>.md(#hash)?` navigates to that Doc.
   ============================================================ */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.ResearchContract = factory();
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  /* Which heading is the Sources block? Exact "Sources" wins; else the LAST
     heading whose text mentions "sources" (so decoys like "Primary sources"
     earlier in the prose don't capture). Returns an index into `headings`, or -1.
     Both adapters pass their own heading-text list (DOM nodes vs markdown lines). */
  function pickSourcesHeading(headings) {
    const exact = headings.findIndex(
      (h) => h.trim().toLowerCase() === "sources",
    );
    if (exact >= 0) return exact;
    let last = -1;
    headings.forEach((h, i) => {
      if (/sources/i.test(h)) last = i;
    });
    return last;
  }

  /* Parse a Sources block (raw text - markdown lines OR joined DOM textContent)
     into rows. Format-agnostic: `[N] …` paragraphs (the canonical form), or
     `- [N] …` / `N.` lists (numbered by position when <2 bracket markers).
     Each row: { num, title, url, local, locals[] }.
       local  = first md|pdf path (the engine's 📄 button target)
       locals = every sources/… path (what verify.mjs checks on disk) */
  function parseSources(text) {
    const out = [];
    const bracketCount = (text.match(/\[\d+\]/g) || []).length;
    if (bracketCount >= 1) {
      // bracketed `[N] …` - the canonical Source contract form
      const re = /\[(\d+)\]\s*([\s\S]*?)(?=\s*\[\d+\]|$)/g;
      let m;
      while ((m = re.exec(text))) {
        const body = m[2].trim();
        if (body) out.push(row(m[1], body));
      }
    } else {
      // no brackets: number `- …` / `N.` list items by position

      const lines = text
        .split(/\r?\n/)
        .map((s) => s.trim())
        .filter(Boolean);
      let i = 0;
      for (const line of lines) {
        const body = line
          .replace(/^[-*]\s*/, "")
          .replace(/^\[?\d+\]?[.\)]?\s*/, "")
          .trim();
        if (body) {
          i++;
          out.push(row(String(i), body));
        }
      }
    }
    return out;
  }

  function row(num, body) {
    const urlM = body.match(/https?:\/\/[^\s)`'"<>]+/);
    const url = urlM ? urlM[0] : null;
    // Blank out http(s) URLs BEFORE scanning for local 'sources/…' paths, so a
    // 'sources/' substring inside a URL (the tail of 're·sources/…', or a literal
    // '/sources/' path segment) isn't mis-read as a local file that must exist on
    // disk. Local copies only ever appear in '(local: sources/…)'/'pdf: sources/…'.
    const bodyNoUrls = body.replace(/https?:\/\/[^\s)`'"<>]+/g, " ");
    const locals =
      bodyNoUrls.match(/sources\/[^\s)`'"<>]+\.[A-Za-z0-9]+/g) || [];
    const local =
      locals.find((p) => /\.(?:md|pdf)$/i.test(p)) || locals[0] || null;
    let title = body;
    if (url) title = title.replace(url, "");
    locals.forEach((p) => {
      title = title.replace(p, "");
    });
    title = title
      .replace(/\(?\s*(?:local|pdf|binary[^:]*)\s*:\s*\)?/gi, "")
      .replace(/[`'"]/g, "")
      .replace(/[\s-–\-():.,]+$/, "")
      .replace(/^[\s-–\-:.]+/, "")
      .trim();
    return { num, title, url, local, locals };
  }

  /* Citation numbers actually used in prose. Strips fenced/inline code first so
     a `[3]` inside a code sample isn't counted. Returns a sorted, de-duped list.
     Callers pass the body WITHOUT the Sources block (so source rows aren't cites). */
  function citationRefs(text) {
    const stripped = text
      .replace(/```[\s\S]*?```/g, "")
      .replace(/`[^`]*`/g, "");
    const nums = new Set();
    let m;
    const re = /\[(\d+)\]/g;
    while ((m = re.exec(stripped))) nums.add(Number(m[1]));
    return [...nums].sort((a, b) => a - b);
  }

  /* Viz-anchor match: does this heading host a panel whose `at` points at it?
     Case-insensitive substring - the rule both adapters share. engine.js passes
     a DOM heading's textContent; verify.mjs passes an extracted heading string. */
  function anchorMatches(headingText, at) {
    if (!at) return false;
    return String(headingText).toLowerCase().includes(String(at).toLowerCase());
  }

  /* Cross-Doc link rule: a link target ending in `<name>.md` (optional `#hash`)
     navigates to that Doc. Returns { file, hash } (file = basename) or null for
     non-Doc links. engine.js feeds an href; verify.mjs feeds the target it
     scraped from `](…)`. The caller maps `file` → Doc id (engine: fileToId /
     README→overview; verify: the docFiles set). */
  function parseDocLink(target) {
    const m = String(target).match(/([\w-]+\.md)(#[^\s)]*)?$/);
    return m ? { file: m[1], hash: m[2] || "" } : null;
  }

  return {
    pickSourcesHeading,
    parseSources,
    citationRefs,
    anchorMatches,
    parseDocLink,
  };
});
