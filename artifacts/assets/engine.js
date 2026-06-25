/* ============================================================
   RESEARCH HTMLSITE - generic SPA engine (topic-agnostic).
   Reads content from globals (all optional except the docs):
     window.SITE      = { brand, classification, title, subtitle, foot[],
                          hero{kicker,headline,lede}, stats[][], sections{},
                          docs[], metric{label,value}, drill{}, glossaryIntro }
     window.VIZ       = { 'overview':[panel...], 'doc-01':[panel...] }   // mermaid/chart, optional, `at` anchors to a heading
     window.INSIGHTS  = [ {ix,a,t,p,ref} ]                               // optional overview cards
     window.MATRIX    = { filters[], columns[], rows[{cat,cells[]}] }    // optional comparison table
     window.DRILL     = [ {n,q,core,bullets[]} ]                          // optional Q&A reveal cards
     window.GLOSSARY  = { cats[{id,label,accent}], terms[{t,c,d,see[]}] } // optional searchable glossary
   Markdown docs are embedded by build.mjs as <script type="text/markdown" id="md-<id>">.
   Do not edit per-topic - put all topic content in content.js / glossary.js.
   ============================================================ */
(function () {
  const AC = {
    cyan: "#2fe3cf",
    ember: "#ff5a4d",
    amber: "#f6b13c",
    violet: "#9d8cff",
    green: "#4ddb8b",
  };
  const SITE = window.SITE || (window.SITE = {});
  // Shared adapter rules (assets/contract.js): Source parsing, Viz-anchor match,
  // cross-Doc link parsing. Present in practice (build.mjs copies it, loaded before
  // engine.js); guarded so a missing contract.js degrades (no rows/nav) not throws.
  const Contract = window.ResearchContract || null;
  const $ = (s, r = document) => r.querySelector(s);
  const el = (tag, cls, html) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  };

  /* ---------- docs: the manifest is identity+order; SITE.docs only ENRICHES ----------
     build.mjs is the SOLE owner of doc identity: it emits the authoritative
     window.__MANIFEST__ = [{id,code,file,title}]. SITE.docs is optional Doc
     *enrichment* keyed by id (or file): accent / sub / star / title override -
     the author never re-states ids, so the doc-id rule lives in one place.

     deriveManifestFallback() is a DEGRADED PATH, not a second home for the rule:
     it runs only for a page served WITHOUT __MANIFEST__ (hand-authored or a stale
     build), reconstructing a best-effort list so the page still renders. The
     Builder's manifest is authoritative whenever present - do not rely on this. */
  const PAL = ["cyan", "ember", "violet", "amber", "green"];
  function deriveManifestFallback() {
    const out = [];
    document.querySelectorAll('script[type="text/markdown"]').forEach((s) => {
      const id = s.id.replace(/^md-/, "");
      if (id === "overview") return;
      const code = (id.match(/(\d+)/) || ["", ""])[1] || String(out.length + 1);
      const h1 = (s.textContent.match(/^#\s+(.+)$/m) || [])[1] || id;
      out.push({
        id,
        code,
        file: id + ".md",
        title: h1.replace(/[*_`]/g, "").trim(),
      });
    });
    return out;
  }
  const MANIFEST =
    window.__MANIFEST__ && window.__MANIFEST__.length
      ? window.__MANIFEST__
      : deriveManifestFallback();
  const enrById = {},
    enrByFile = {};
  (SITE.docs || []).forEach((d) => {
    if (d.id) enrById[d.id] = d;
    if (d.file) enrByFile[d.file] = d;
  });
  const DOCS = MANIFEST.map((m, i) => {
    const e = enrById[m.id] || enrByFile[m.file] || {};
    return {
      id: m.id,
      code: e.code || m.code,
      file: m.file,
      title: e.title || m.title,
      sub: e.sub || "",
      star: !!e.star,
      accent: e.accent || PAL[i % PAL.length],
    };
  });
  const fileToId = {};
  DOCS.forEach((d) => {
    fileToId[d.file] = d.id;
  });

  /* ---------- markdown ---------- */
  if (window.marked)
    marked.setOptions({
      gfm: true,
      breaks: false,
      headerIds: false,
      mangle: false,
    });
  function mdToHtml(text) {
    try {
      return window.marked ? marked.parse(text) : "<pre>" + text + "</pre>";
    } catch (e) {
      return "<pre>" + e + "</pre>";
    }
  }
  function getMd(key) {
    const n = document.getElementById("md-" + key);
    return n ? n.textContent : "";
  }

  /* ---------- mermaid ---------- */
  if (window.mermaid)
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "loose",
      theme: "base",
      themeVariables: {
        fontFamily: "JetBrains Mono, monospace",
        fontSize: "13px",
        background: "#0e131b",
        mainBkg: "#121823",
        primaryColor: "#121823",
        primaryTextColor: "#e8ecf3",
        primaryBorderColor: "#2a3543",
        secondaryColor: "#161d2a",
        tertiaryColor: "#0e131b",
        lineColor: "#6a7686",
        textColor: "#cdd6e4",
        nodeBorder: "#2a3543",
        clusterBkg: "#0b0f16",
        clusterBorder: "#243042",
        edgeLabelBackground: "#0b0f16",
        actorBkg: "#141a24",
        actorBorder: "#2fe3cf",
        actorTextColor: "#e8ecf3",
        signalColor: "#9aa6b8",
        signalTextColor: "#cdd6e4",
        labelBoxBkg: "#141a24",
        labelBoxBorderColor: "#2a3543",
        noteBkgColor: "#1a2230",
        noteTextColor: "#e8ecf3",
        noteBorderColor: "#f6b13c",
        cScale0: "#2fe3cf",
        cScale1: "#ff5a4d",
        cScale2: "#9d8cff",
        pie1: "#2fe3cf",
        pie2: "#ff5a4d",
      },
      flowchart: {
        curve: "basis",
        htmlLabels: true,
        padding: 14,
        nodeSpacing: 42,
        rankSpacing: 50,
      },
      sequence: { useMaxWidth: true, mirrorActors: false, actorMargin: 64 },
    });
  async function renderMermaidIn(scope) {
    if (!window.mermaid) return;
    for (const n of [...scope.querySelectorAll(".mermaid:not([data-done])")]) {
      n.setAttribute("data-done", "1");
      try {
        const { svg } = await mermaid.render(
          "mm-" + Math.random().toString(36).slice(2),
          n.getAttribute("data-def"),
        );
        n.innerHTML = svg;
      } catch (e) {
        n.innerHTML =
          '<div style="color:#ff8a5c;font-family:monospace;font-size:12px;padding:14px">diagram error: ' +
          (e.message || e) +
          "</div>";
      }
    }
  }

  /* ---------- charts ---------- */
  if (window.Chart) {
    Chart.defaults.color = "#9aa6b8";
    Chart.defaults.font.family = "Hanken Grotesk, system-ui, sans-serif";
    Chart.defaults.font.size = 12;
    Chart.defaults.plugins.legend.labels.boxWidth = 12;
    Chart.defaults.plugins.legend.labels.boxHeight = 12;
    Chart.defaults.plugins.legend.labels.usePointStyle = true;
  }
  function makeChart(canvas, cfg) {
    if (!window.Chart || canvas._made) return;
    canvas._made = true;
    cfg = JSON.parse(JSON.stringify(cfg));
    cfg.options = Object.assign(
      { responsive: true, maintainAspectRatio: false },
      cfg.options || {},
    );
    new Chart(canvas, cfg);
  }
  function renderChartsIn(scope) {
    if (!window.Chart) return;
    scope.querySelectorAll("canvas").forEach((c) => {
      if (c._cfg && !c._made) makeChart(c, c._cfg);
    });
  }

  /* ---------- viz panels ---------- */
  function vizPanel(v) {
    const p = el("div", "viz");
    p.style.setProperty("--accent", AC[v.accent] || AC.cyan);
    p.appendChild(
      el(
        "div",
        "vh",
        `<span class="tag">${v.tag || "VIZ"}</span><h4>${v.title || ""}</h4><span class="meta">${v.meta || ""}</span>`,
      ),
    );
    const body = el("div", "vbody");
    if (v.kind === "mermaid") {
      const m = el("div", "mermaid");
      m.setAttribute("data-def", v.def);
      body.appendChild(m);
    } else if (v.kind === "chart") {
      const w = el("div", "chart-wrap" + (v.tall ? " tall" : ""));
      const c = el("canvas");
      c.id = "ch-" + Math.random().toString(36).slice(2);
      c._cfg = v.chart;
      w.appendChild(c);
      body.appendChild(w);
    }
    p.appendChild(body);
    if (v.cap) p.appendChild(el("div", "vcap", v.cap));
    return p;
  }
  function injectViz(container, list) {
    (list || []).forEach((v) => container.appendChild(vizPanel(v)));
  }

  /* ---------- comparison matrix (generic) ---------- */
  function buildMatrix(M) {
    const wrap = el("div");
    const tools = el(
      "div",
      "matrix-tools",
      `<span style="font-family:var(--f-mono);font-size:10px;letter-spacing:.2em;color:var(--txt-faint);text-transform:uppercase">FILTER</span>`,
    );
    (M.filters || [{ label: "All", value: "all" }]).forEach((f, i) => {
      const ch = el(
        "span",
        "chip" +
          (i === 0 ? " on" : "") +
          (f.accent === "ember" ? " ember" : ""),
        f.label,
      );
      ch.dataset.f = f.value;
      tools.appendChild(ch);
    });
    wrap.appendChild(tools);
    const scroll = el("div");
    scroll.style.overflowX = "auto";
    const t = el("table", "mtx");
    t.innerHTML =
      "<thead><tr>" +
      (M.columns || []).map((c) => `<th>${c}</th>`).join("") +
      "</tr></thead>";
    const tb = el("tbody");
    (M.rows || []).forEach((r) => {
      const tr = el("tr");
      tr.dataset.cat = r.cat || "";
      tr.innerHTML = (r.cells || [])
        .map((cell) => {
          if (cell && typeof cell === "object") {
            if (cell.name != null)
              return `<td class="name">${cell.name}${cell.sub ? `<small>${cell.sub}</small>` : ""}</td>`;
            if (cell.pill != null)
              return `<td><span class="pill ${cell.pill}">${cell.text || ""}</span></td>`;
            return `<td>${cell.text || ""}</td>`;
          }
          return `<td style="color:var(--txt-faint);font-size:12px">${cell == null ? "" : cell}</td>`;
        })
        .join("");
      tb.appendChild(tr);
    });
    t.appendChild(tb);
    scroll.appendChild(t);
    wrap.appendChild(scroll);
    tools.addEventListener("click", (e) => {
      const c = e.target.closest(".chip");
      if (!c) return;
      tools.querySelectorAll(".chip").forEach((x) => x.classList.remove("on"));
      c.classList.add("on");
      const f = c.dataset.f;
      tb.querySelectorAll("tr").forEach((tr) => {
        tr.style.display =
          f === "all" || (tr.dataset.cat || "").includes(f) ? "" : "none";
      });
    });
    return wrap;
  }

  /* ---------- views ---------- */
  const content = $("#content");
  const views = {};
  function makeView(id) {
    const v = el("section", "view");
    v.id = "view-" + id;
    views[id] = v;
    content.appendChild(v);
    return v;
  }
  function secH(code, title) {
    return el(
      "div",
      "sec-h",
      `<span class="c">// ${code}</span><h3>${title}</h3><span class="rule"></span>`,
    );
  }

  function buildOverview() {
    const v = makeView("overview");
    const H = SITE.hero || {};
    const S = SITE.sections || {};
    v.appendChild(
      el(
        "div",
        "hero",
        `<span class="kicker">${H.kicker || SITE.subtitle || "Research"}</span>
       <h2>${H.headline || SITE.title || "Overview"}</h2>
       ${H.lede ? `<p class="lede">${H.lede}</p>` : ""}`,
      ),
    );
    if (SITE.stats && SITE.stats.length) {
      const stats = el("div", "stats");
      SITE.stats.forEach(([n, l, s, a]) => {
        const st = el(
          "div",
          "stat",
          `<div class="n" data-target="${n}">0</div><div class="l">${l}</div>${s ? `<div class="s">${s}</div>` : ""}`,
        );
        st.style.setProperty("--accent", AC[a] || AC.cyan);
        stats.appendChild(st);
      });
      v.appendChild(stats);
    }
    if (window.VIZ && VIZ.overview && VIZ.overview.length) {
      v.appendChild(secH("MAP", S.map || "At a glance"));
      const c = el("div");
      injectViz(c, VIZ.overview);
      v.appendChild(c);
    }
    if (window.INSIGHTS && INSIGHTS.length) {
      v.appendChild(secH("SYNTHESIS", S.synthesis || "Key insights"));
      const ins = el("div", "insights");
      INSIGHTS.forEach((i) => {
        const c = el(
          "div",
          "icard",
          `<div class="ix">INSIGHT ${i.ix}</div><h4>${i.t}</h4><p>${i.p}</p>${i.ref ? `<div class="ref">▸ ${i.ref}</div>` : ""}`,
        );
        c.style.setProperty("--accent", AC[i.a] || AC.cyan);
        ins.appendChild(c);
      });
      v.appendChild(ins);
    }
    if (window.MATRIX) {
      v.appendChild(secH("COMPARE", S.compare || "Comparison"));
      v.appendChild(buildMatrix(window.MATRIX));
    }
    if (getMd("overview")) {
      v.appendChild(secH("BRIEFING", S.briefing || "Full briefing (README)"));
      const md = el("div", "md");
      md.innerHTML = mdToHtml(getMd("overview"));
      rewriteLinks(md);
      enrichLinks(md, "overview");
      v.appendChild(md);
    }
  }

  function buildDoc(d) {
    const v = makeView(d.id);
    v.style.setProperty("--accent", AC[d.accent] || AC.cyan);
    v.appendChild(
      el(
        "div",
        "hero",
        `<span class="kicker" style="color:${AC[d.accent] || AC.cyan}">${d.code} · ${d.sub || ""}</span>`,
      ),
    );
    const md = el("div", "md");
    md.innerHTML = mdToHtml(getMd(d.id));
    rewriteLinks(md);
    enrichLinks(md, d.id);
    v.appendChild(md);
    const list = (window.VIZ && VIZ[d.id]) || [];
    const headings = [...md.querySelectorAll("h2, h3")];
    const orphans = [];
    list.forEach((vi) => {
      const panel = vizPanel(vi);
      let anchor = null;
      if (vi.at && Contract)
        anchor = headings.find((h) =>
          Contract.anchorMatches(h.textContent, vi.at),
        );
      if (anchor) anchor.insertAdjacentElement("afterend", panel);
      else orphans.push(panel);
    });
    if (orphans.length) {
      const strip = el("div", "docviz");
      strip.appendChild(el("div", "dvh", "Visualisations"));
      orphans.forEach((p) => strip.appendChild(p));
      md.parentNode.insertBefore(strip, md);
    }
  }

  function buildDrill() {
    if (!window.DRILL || !DRILL.length) return;
    const v = makeView("drill");
    const D = SITE.drill || {};
    v.appendChild(
      el(
        "div",
        "hero",
        `<span class="kicker">${D.kicker || "Practice · reveal mode"}</span>
       <h2 style="font-size:34px">${D.headline || 'Drill - <span class="e">' + DRILL.length + " questions</span>"}</h2>
       ${D.lede ? `<p class="lede">${D.lede}</p>` : '<p class="lede">Read the prompt, answer it aloud, then reveal the model answer.</p>'}`,
      ),
    );
    const grid = el("div", "drill-grid");
    DRILL.forEach((d) => {
      const card = el("div", "dcard");
      card.innerHTML = `<div class="q"><span class="qn">${d.n || ""}</span><span class="qt">${d.q}</span><span class="tgl">+</span></div>
        <div class="a"><div class="inner"><div class="core">${d.core || ""}</div>${d.bullets && d.bullets.length ? `<ul>${d.bullets.map((b) => "<li>" + b + "</li>").join("")}</ul>` : ""}</div></div>`;
      card
        .querySelector(".q")
        .addEventListener("click", () => card.classList.toggle("open"));
      grid.appendChild(card);
    });
    v.appendChild(grid);
  }

  /* ---------- glossary ---------- */
  function buildGlossary() {
    const G = window.GLOSSARY;
    if (!G || !G.terms) return;
    const v = makeView("glossary");
    v.appendChild(
      el(
        "div",
        "hero",
        `<span class="kicker">Reference · searchable</span>
       <h2 style="font-size:34px">Glossary - <span class="g">${G.terms.length}</span> terms</h2>
       <p class="lede">${SITE.glossaryIntro || "Search any term or definition, filter by category, or click a ↳ see-also to jump."}</p>`,
      ),
    );
    const tools = el("div", "gl-tools");
    const search = el("input", "gl-search");
    search.type = "search";
    search.placeholder = "Search terms and definitions…";
    tools.appendChild(search);
    v.appendChild(tools);
    const chips = el("div", "gl-chips");
    const allChip = el("span", "chip on");
    allChip.dataset.c = "all";
    allChip.textContent = "All";
    chips.appendChild(allChip);
    const catMap = {};
    (G.cats || []).forEach((c) => {
      catMap[c.id] = c;
      const ch = el("span", "chip", c.label);
      ch.dataset.c = c.id;
      ch.style.setProperty("--accent", AC[c.accent] || AC.cyan);
      chips.appendChild(ch);
    });
    v.appendChild(chips);
    const count = el("div", "gl-count");
    v.appendChild(count);
    const grid = el("div", "gl-grid");
    v.appendChild(grid);
    G.terms
      .slice()
      .sort((a, b) => a.t.localeCompare(b.t))
      .forEach((term) => {
        const cat = catMap[term.c] || { label: term.c, accent: "cyan" };
        const card = el("div", "gl-card");
        card.style.setProperty("--accent", AC[cat.accent] || AC.cyan);
        card.dataset.c = term.c;
        card.dataset.term = term.t.toLowerCase();
        card.dataset.text = (
          term.t +
          " " +
          term.d +
          " " +
          (term.see || []).join(" ")
        ).toLowerCase();
        const see = (term.see || [])
          .map(
            (s) =>
              `<span class="gl-see" data-jump="${s.toLowerCase().replace(/"/g, "&quot;")}">${s}</span>`,
          )
          .join("");
        card.innerHTML = `<div class="gl-top"><span class="gl-term">${term.t}</span><span class="gl-tag">${cat.label}</span></div><div class="gl-def">${term.d}</div>${see ? `<div class="gl-sees">↳ ${see}</div>` : ""}`;
        grid.appendChild(card);
      });
    const cards = [...grid.children];
    let curCat = "all";
    function apply() {
      const q = search.value.trim().toLowerCase();
      let n = 0;
      cards.forEach((c) => {
        const ok =
          (curCat === "all" || c.dataset.c === curCat) &&
          (!q || c.dataset.text.includes(q));
        c.style.display = ok ? "" : "none";
        if (ok) n++;
      });
      count.textContent = n + " / " + cards.length + " terms shown";
    }
    search.addEventListener("input", apply);
    chips.addEventListener("click", (e) => {
      const ch = e.target.closest(".chip");
      if (!ch) return;
      chips.querySelectorAll(".chip").forEach((x) => x.classList.remove("on"));
      ch.classList.add("on");
      curCat = ch.dataset.c;
      apply();
    });
    grid.addEventListener("click", (e) => {
      const s = e.target.closest(".gl-see");
      if (!s) return;
      search.value = s.dataset.jump;
      curCat = "all";
      chips
        .querySelectorAll(".chip")
        .forEach((x) => x.classList.toggle("on", x.dataset.c === "all"));
      apply();
      const target =
        cards.find(
          (c) =>
            c.style.display !== "none" && c.dataset.term === s.dataset.jump,
        ) || cards.find((c) => c.style.display !== "none");
      if (target) {
        target.scrollIntoView({ behavior: "smooth", block: "center" });
        target.classList.add("flash");
        setTimeout(() => target.classList.remove("flash"), 1300);
      }
    });
    apply();
  }

  /* ---------- link rewriting (md cross-refs → in-app nav) ---------- */
  function rewriteLinks(scope) {
    scope.querySelectorAll("a[href]").forEach((a) => {
      const href = a.getAttribute("href");
      const link = Contract ? Contract.parseDocLink(href) : null; // cross-Doc link rule lives in contract.js
      if (link && fileToId[link.file]) {
        a.setAttribute("data-nav", fileToId[link.file]);
        a.setAttribute("href", "#" + fileToId[link.file]);
      } else if (link && link.file === "README.md") {
        a.setAttribute("data-nav", "overview");
        a.setAttribute("href", "#overview");
      } else if (/^https?:/.test(href)) {
        a.setAttribute("target", "_blank");
        a.setAttribute("rel", "noopener");
      }
    });
  }

  /* ---------- citation & source linking ---------- */
  function enrichLinks(scope, docId) {
    const map = rebuildSources(scope, docId);
    linkifyBareUrls(scope);
    linkifyCitations(scope, docId, map);
  }
  function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function escapeAttr(s) {
    return s.replace(/&/g, "&amp;").replace(/"/g, "&quot;");
  }
  function linkifyBareUrls(scope) {
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
      acceptNode(n) {
        if (!/https?:\/\//.test(n.nodeValue)) return NodeFilter.FILTER_REJECT;
        let p = n.parentElement;
        while (p && p !== scope) {
          const t = p.tagName;
          if (t === "A" || t === "CODE" || t === "PRE")
            return NodeFilter.FILTER_REJECT;
          p = p.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const nodes = [];
    let t;
    while ((t = walker.nextNode())) nodes.push(t);
    const re = /https?:\/\/[^\s<>()\[\]]+/g;
    nodes.forEach((node) => {
      const s = node.nodeValue;
      const frag = document.createDocumentFragment();
      let last = 0,
        m;
      re.lastIndex = 0;
      while ((m = re.exec(s))) {
        let url = m[0],
          trail = "";
        while (/[.,;:]$/.test(url)) {
          trail = url.slice(-1) + trail;
          url = url.slice(0, -1);
        }
        if (m.index > last)
          frag.appendChild(document.createTextNode(s.slice(last, m.index)));
        const a = document.createElement("a");
        a.href = url;
        a.target = "_blank";
        a.rel = "noopener";
        a.textContent = url;
        frag.appendChild(a);
        if (trail) frag.appendChild(document.createTextNode(trail));
        last = m.index + m[0].length;
      }
      if (last < s.length)
        frag.appendChild(document.createTextNode(s.slice(last)));
      node.parentNode.replaceChild(frag, node);
    });
  }
  /* DOM adapter over the shared Source contract: locate the Sources block, hand its
     text to ResearchContract.parseSources, build the clickable rows. verify.mjs
     wraps the same contract for assertions. (Contract is declared at the top.) */
  function blockText(node) {
    // lists carry no newlines between items - expand them so contract list-mode works
    if (node.tagName === "OL" || node.tagName === "UL")
      return [...node.children].map((li) => li.textContent).join("\n");
    return node.textContent;
  }
  function rebuildSources(scope, docId) {
    const map = {};
    if (!Contract) return map;
    const heads = [...scope.querySelectorAll("h2, h3")];
    if (!heads.length) return map;
    const si = Contract.pickSourcesHeading(heads.map((h) => h.textContent));
    const srcH = si >= 0 ? heads[si] : null;
    if (!srcH) return map;
    const sibs = [];
    let n = srcH.nextElementSibling;
    while (n && !/^H[1-3]$/.test(n.tagName)) {
      sibs.push(n);
      n = n.nextElementSibling;
    }
    if (!sibs.length) return map;
    const parsed = Contract.parseSources(sibs.map(blockText).join("\n"));
    if (!parsed.length) return map;
    sibs.forEach((s) => s.remove());
    const list = document.createElement("div");
    list.className = "src-list";
    parsed.forEach(({ num, title, url, local }) => {
      const row = document.createElement("div");
      row.id = docId + "-src-" + num;
      row.className = "src-entry";
      let h = `<span class="src-n">[${num}]</span> `;
      if (title) h += `<span class="src-title">${escapeHtml(title)}</span> `;
      if (url)
        h += `<a class="src-url" href="${escapeAttr(url)}" target="_blank" rel="noopener">↗ open source</a> `;
      if (local)
        h += `<a class="src-local" href="${escapeAttr(local)}" target="_blank">📄 local copy</a>`;
      row.innerHTML = h;
      list.appendChild(row);
      map[num] = { url, local, el: row };
    });
    srcH.insertAdjacentElement("afterend", list);
    return map;
  }
  function linkifyCitations(scope, docId, map) {
    if (!Object.keys(map).length) return;
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT, {
      acceptNode(n) {
        if (!/\[\d+\]/.test(n.nodeValue)) return NodeFilter.FILTER_REJECT;
        let p = n.parentElement;
        while (p && p !== scope) {
          if (p.classList && p.classList.contains("src-entry"))
            return NodeFilter.FILTER_REJECT;
          const t = p.tagName;
          if (
            t === "A" ||
            t === "CODE" ||
            t === "PRE" ||
            t === "H1" ||
            t === "H2" ||
            t === "H3"
          )
            return NodeFilter.FILTER_REJECT;
          p = p.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const nodes = [];
    let t;
    while ((t = walker.nextNode())) nodes.push(t);
    const re = /\[(\d+)\]/g;
    nodes.forEach((node) => {
      const s = node.nodeValue;
      const frag = document.createDocumentFragment();
      let last = 0,
        m;
      re.lastIndex = 0;
      while ((m = re.exec(s))) {
        const num = m[1];
        if (m.index > last)
          frag.appendChild(document.createTextNode(s.slice(last, m.index)));
        if (map[num]) {
          const sup = document.createElement("sup");
          const a = document.createElement("a");
          a.className = "cite";
          a.dataset.jump = docId + "-src-" + num;
          a.textContent = "[" + num + "]";
          a.tabIndex = 0;
          a.title = map[num].url
            ? "Source " + num + " - " + map[num].url
            : "jump to source " + num;
          sup.appendChild(a);
          frag.appendChild(sup);
        } else frag.appendChild(document.createTextNode(m[0]));
        last = m.index + m[0].length;
      }
      if (last < s.length)
        frag.appendChild(document.createTextNode(s.slice(last)));
      node.parentNode.replaceChild(frag, node);
    });
  }
  function jumpToSource(id) {
    const t = document.getElementById(id);
    if (!t) return;
    t.scrollIntoView({ behavior: "smooth", block: "center" });
    t.classList.remove("flash");
    void t.offsetWidth;
    t.classList.add("flash");
    setTimeout(() => t.classList.remove("flash"), 1700);
  }

  /* ---------- navigation ---------- */
  let current = null;
  function go(id) {
    if (!views[id]) id = "overview";
    if (current === id) return;
    Object.values(views).forEach((v) => v.classList.remove("active"));
    document
      .querySelectorAll(".nav-item")
      .forEach((n) => n.classList.toggle("active", n.dataset.go === id));
    views[id].classList.add("active");
    current = id;
    const main = $(".main");
    if (main) main.scrollTop = 0;
    window.scrollTo(0, 0);
    if (location.hash !== "#" + id) history.replaceState(null, "", "#" + id);
    renderMermaidIn(views[id]);
    renderChartsIn(views[id]);
    if (id === "overview") runCounters(views[id]);
    const sb = $(".sidebar");
    if (sb) sb.classList.remove("open");
    const loc = $("#tb-loc");
    if (loc) {
      const d = DOCS.find((x) => x.id === id);
      loc.textContent =
        id === "overview"
          ? "OVERVIEW"
          : id === "drill"
            ? "DRILL"
            : id === "glossary"
              ? "GLOSSARY"
              : d
                ? (d.code + " " + d.title).toUpperCase()
                : id;
    }
  }

  /* ---------- chrome (brand, footer, topbar, nav) ---------- */
  function fillChrome() {
    const brand = $("#brand");
    if (brand)
      brand.innerHTML = `<div class="mark"><span class="dot"></span> ${SITE.brand || "RESEARCH"}${SITE.classification ? " // " + SITE.classification : ""}</div>
       <h1>${SITE.title || "Research"}</h1>${SITE.subtitle ? `<div class="sub">${SITE.subtitle}</div>` : ""}`;
    const foot = $("#side-foot");
    if (foot && SITE.foot)
      foot.innerHTML = SITE.foot.map((f) => `<div>${f}</div>`).join("");
    const cls = $("#tb-class");
    if (cls && SITE.classification) cls.textContent = SITE.classification;
    const metric = $("#tb-metric");
    if (metric && SITE.metric)
      metric.innerHTML = `<b>${SITE.metric.label}</b> <span class="v">${SITE.metric.value}</span>`;
  }
  function buildNav() {
    const nav = $("#nav");
    nav.appendChild(el("div", "nav-label", "Console"));
    const ov = el("div", "nav-item active");
    ov.dataset.go = "overview";
    ov.style.setProperty("--accent", AC.ember);
    ov.innerHTML = `<span class="code">◎</span><span class="ttl">Overview<small>${SITE.overviewSub || "map · synthesis"}</small></span>`;
    nav.appendChild(ov);
    nav.appendChild(el("div", "nav-label", "Documents"));
    DOCS.forEach((d) => {
      const n = el("div", "nav-item" + (d.star ? " star" : ""));
      n.dataset.go = d.id;
      n.style.setProperty("--accent", AC[d.accent] || AC.cyan);
      n.innerHTML = `<span class="code">${d.code}</span><span class="ttl">${d.title}<small>${d.sub || ""}</small></span>`;
      nav.appendChild(n);
    });
    if (window.DRILL && DRILL.length) {
      nav.appendChild(el("div", "nav-label", "Practice"));
      const dr = el("div", "nav-item");
      dr.dataset.go = "drill";
      dr.style.setProperty("--accent", AC.ember);
      dr.innerHTML = `<span class="code">▣</span><span class="ttl">Drill mode<small>${DRILL.length} reveal cards</small></span>`;
      nav.appendChild(dr);
    }
    if (window.GLOSSARY && GLOSSARY.terms) {
      nav.appendChild(el("div", "nav-label", "Reference"));
      const gl = el("div", "nav-item");
      gl.dataset.go = "glossary";
      gl.style.setProperty("--accent", AC.cyan);
      gl.innerHTML = `<span class="code">≡</span><span class="ttl">Glossary<small>${GLOSSARY.terms.length} terms · searchable</small></span>`;
      nav.appendChild(gl);
    }
    nav.addEventListener("click", (e) => {
      const it = e.target.closest(".nav-item");
      if (it) go(it.dataset.go);
    });
  }

  /* ---------- counters ---------- */
  function runCounters(scope) {
    scope.querySelectorAll(".stat .n").forEach((n) => {
      if (n._done) return;
      n._done = true;
      const raw = n.dataset.target;
      const num = parseFloat(raw);
      const suffix = raw.replace(/[\d.]/g, "");
      let t0 = null;
      const dur = 1100;
      function step(ts) {
        if (!t0) t0 = ts;
        const p = Math.min((ts - t0) / dur, 1);
        const e = 1 - Math.pow(1 - p, 3);
        n.textContent =
          (num >= 100 ? Math.round(num * e) : (num * e).toFixed(0)) + suffix;
        if (p < 1) requestAnimationFrame(step);
        else n.textContent = raw;
      }
      requestAnimationFrame(step);
    });
  }

  /* ---------- boot ---------- */
  function boot() {
    if (window.__kitBooted) return;
    window.__kitBooted = true;
    fillChrome();
    buildNav();
    buildOverview();
    DOCS.forEach(buildDoc);
    buildDrill();
    buildGlossary();
    window.addEventListener("hashchange", () => go(location.hash.slice(1)));
    content.addEventListener("click", (e) => {
      const nav = e.target.closest("a[data-nav]");
      if (nav) {
        e.preventDefault();
        go(nav.getAttribute("data-nav"));
        return;
      }
      const cite = e.target.closest("a.cite[data-jump]");
      if (cite) {
        e.preventDefault();
        jumpToSource(cite.dataset.jump);
        return;
      }
    });
    const mb = $("#menuBtn");
    if (mb)
      mb.addEventListener("click", () =>
        $(".sidebar").classList.toggle("open"),
      );
    go(location.hash ? location.hash.slice(1) : "overview");
  }
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
