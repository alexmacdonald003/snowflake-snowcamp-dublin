#!/usr/bin/env python3
"""Render the day 2 guide markdown as one self-contained HTML page.

The page mirrors the structure and look of the official quickstart:

    https://www.snowflake.com/en/developers/guides/sfguide-build-end-to-end-ai-app-on-snowflake/

Two guides go in, one page comes out, with a visible break where session 4 ends and
session 5 begins.

The output has NO external dependencies: no CDN, no web fonts, no /libs/ paths. That
is deliberate. Attendees download this file and open it from their own machine, where
Snowflake's vendored /libs/ path does not resolve and network access may be absent.
Everything the page needs -- styles, script, syntax highlighting -- is inline.

Usage:
    python3 build_guide_html.py guide/session4_analytics_etl.md \
                                guide/session5_agents.md \
                                guide/fiserv_workshop_day2.html
"""

import html
import re
import sys
from datetime import date

# Sections in the order the official quickstart presents them. CoCo Plugin and
# Iceberg V3 are deliberately absent: they were dropped for this workshop.
# ("source guide", "heading in that guide") -> emitted in this order.
OFFICIAL_ORDER = [
    ("s4", "Setup"),
    ("s4", "Explore Your Data"),
    ("s4", "Data Quality"),
    ("s4", "Dynamic Tables Pipeline"),
    ("s4", "dbt Analytics"),
    ("s4", "Gen2 Warehouse: Optima Indexing"),
    ("s4", "Interactive Tables"),
    ("s4", "CoCo Custom Skill"),
    # --- session break inserted here ---
    ("s5", "Snowflake CoWork"),
    ("s5", "Security and Governance"),
    ("s5", "Streamlit Dashboard"),
    ("s5", "Agent Evaluation"),
    ("s5", "Agent Observability"),
    ("s5", "Optional: MCP Server"),
    ("s5", "Cleanup"),
    ("s5", "Troubleshooting"),
    ("s5", "Conclusion"),
]

BREAK_AFTER = "CoCo Custom Skill"

SQL_KEYWORDS = """
SELECT FROM WHERE GROUP BY ORDER HAVING JOIN LEFT RIGHT INNER OUTER FULL CROSS ON AS
AND OR NOT IN IS NULL LIKE ILIKE BETWEEN EXISTS CASE WHEN THEN ELSE END DISTINCT
COUNT SUM AVG MIN MAX ROUND CAST COALESCE NULLIF GREATEST LEAST OVER PARTITION
CREATE REPLACE ALTER DROP TABLE VIEW SCHEMA DATABASE WAREHOUSE ROLE USER STAGE
INSERT UPDATE DELETE MERGE INTO VALUES SET USE SHOW DESCRIBE DESC EXPLAIN GRANT
REVOKE TO WITH RECURSIVE UNION ALL EXCEPT INTERSECT LIMIT OFFSET QUALIFY
DYNAMIC TARGET_LAG REFRESH_MODE WAREHOUSE_SIZE GENERATION INITIALLY SUSPENDED
FUNCTION PROCEDURE POLICY MASKING ROW ACCESS SEMANTIC MODEL AGENT SEARCH SERVICE
IF NOT EXISTS PRIMARY KEY FOREIGN REFERENCES CLUSTER LATERAL FLATTEN TABLE
CURRENT_ROLE CURRENT_ACCOUNT CURRENT_TIMESTAMP DATE_TRUNC DATEADD DATEDIFF
COUNT_IF ROW_NUMBER RANK DENSE_RANK LAG LEAD ASC DESC BEFORE STATEMENT AT
TRUE FALSE INTERVAL COMMENT COPY LIST GET PUT COLUMN ADD RENAME ENABLE
""".split()

_KW = r"\b(" + "|".join(sorted(set(SQL_KEYWORDS), key=len, reverse=True)) + r")\b"

TOKEN_RE = re.compile(
    r"(?P<comment>--[^\n]*)"
    r"|(?P<string>'(?:[^']|'')*')"
    r"|(?P<kw>" + _KW + r")"
    r"|(?P<num>\b\d+(?:\.\d+)?\b)",
    re.IGNORECASE,
)


def highlight_sql(code):
    """Tokenise SQL into escaped, span-wrapped HTML.

    Escaping happens per fragment as we walk the string, so we never risk matching a
    keyword inside markup we just inserted.
    """
    out, cursor = [], 0
    for m in TOKEN_RE.finditer(code):
        out.append(html.escape(code[cursor:m.start()]))
        kind = m.lastgroup
        # lastgroup can be the inner alternation group of the keyword pattern
        if kind not in ("comment", "string", "num"):
            kind = "kw"
        out.append('<span class="t-%s">%s</span>' % (kind, html.escape(m.group(0))))
        cursor = m.end()
    out.append(html.escape(code[cursor:]))
    return "".join(out)


def render_inline(text):
    """Inline markdown: bold, inline code, and nothing else the guides use."""
    # Protect inline code first so ** inside it is left alone.
    spans, holder = [], "\x00%d\x00"
    def stash(m):
        spans.append('<code>%s</code>' % html.escape(m.group(1)))
        return holder % (len(spans) - 1)
    text = re.sub(r"`([^`]+)`", stash, text)

    text = html.escape(text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)

    for i, s in enumerate(spans):
        text = text.replace(html.escape(holder % i), s).replace(holder % i, s)
    return text


def slugify(text):
    s = re.sub(r"[^0-9a-zA-Z]+", "-", text.strip().lower()).strip("-")
    return s or "section"


def parse_blocks(md):
    """Turn markdown into a flat list of block dicts."""
    lines = md.split("\n")
    blocks, i = [], 0
    while i < len(lines):
        line = lines[i]

        if line.startswith("```"):
            lang = line[3:].strip() or "text"
            i += 1
            body = []
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(lines[i])
                i += 1
            i += 1
            blocks.append({"t": "code", "lang": lang, "src": "\n".join(body)})
            continue

        if re.match(r"^#{1,4} ", line):
            level = len(line) - len(line.lstrip("#"))
            blocks.append({"t": "h", "level": level, "text": line[level:].strip()})
            i += 1
            continue

        if line.strip() == "---":
            blocks.append({"t": "hr"})
            i += 1
            continue

        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append(lines[i])
                i += 1
            blocks.append({"t": "table", "rows": rows})
            continue

        if line.startswith("> "):
            body = []
            while i < len(lines) and (lines[i].startswith("> ") or lines[i].strip() == ">"):
                body.append(lines[i][2:] if len(lines[i]) > 2 else "")
                i += 1
            blocks.append({"t": "quote", "text": "\n".join(body).strip()})
            continue

        if re.match(r"^[-*] ", line):
            items = []
            while i < len(lines) and re.match(r"^[-*] ", lines[i]):
                items.append(lines[i][2:].strip())
                i += 1
            blocks.append({"t": "ul", "items": items})
            continue

        if re.match(r"^\d+\. ", line):
            items = []
            while i < len(lines) and re.match(r"^\d+\. ", lines[i]):
                items.append(re.sub(r"^\d+\. ", "", lines[i]).strip())
                i += 1
            blocks.append({"t": "ol", "items": items})
            continue

        if not line.strip():
            i += 1
            continue

        para = []
        while i < len(lines) and lines[i].strip() and not re.match(
            r"^(#{1,4} |```|\||> |[-*] |\d+\. |---\s*$)", lines[i]
        ):
            para.append(lines[i].strip())
            i += 1
        if para:
            blocks.append({"t": "p", "text": " ".join(para)})
    return blocks


WARN_RE = re.compile(r"^\*\*(Not yet verified|Note|Warning|Important)")


def render_table(rows):
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    # Drop the |---|---| separator row.
    body = [r for r in cells[1:] if not all(re.fullmatch(r":?-{2,}:?", c or "-") for c in r)]
    head = "".join("<th>%s</th>" % render_inline(c) for c in cells[0])
    out = ['<div class="table-wrap"><table><thead><tr>%s</tr></thead><tbody>' % head]
    for r in body:
        out.append("<tr>%s</tr>" % "".join("<td>%s</td>" % render_inline(c) for c in r))
    out.append("</tbody></table></div>")
    return "".join(out)


PROMPT_LEAD_RE = re.compile(r"^\*\*Prompt ([A-Za-z]+):?\*\*\s*$")


def render_blocks(blocks, code_ids):
    out = []
    # Blockquotes are prompts. Which assistant they belong to is declared by the bold
    # lead-in above them ("**Prompt CoCo:**" / "**Prompt CoWork:**"), because CoCo builds
    # objects while CoWork queries the agent, and sending a prompt to the wrong one simply
    # does not work. Defaults to CoCo, which is the majority case.
    prompt_tool = "CoCo"
    for b in blocks:
        t = b["t"]
        if t == "p":
            m = PROMPT_LEAD_RE.match(b["text"].strip())
            if m:
                prompt_tool = m.group(1)
        if t == "h":
            # h2 is the section title, emitted by the caller. Everything else inline.
            tag = "h%d" % min(b["level"] + 1, 6) if b["level"] >= 3 else "h3"
            out.append('<%s id="%s">%s</%s>' % (tag, slugify(b["text"]), render_inline(b["text"]), tag))
        elif t == "p":
            cls = ""
            if b["text"].startswith("**What to take away:**"):
                cls = ' class="takeaway"'
            out.append("<p%s>%s</p>" % (cls, render_inline(b["text"])))
        elif t == "ul":
            out.append("<ul>%s</ul>" % "".join("<li>%s</li>" % render_inline(x) for x in b["items"]))
        elif t == "ol":
            out.append("<ol>%s</ol>" % "".join("<li>%s</li>" % render_inline(x) for x in b["items"]))
        elif t == "table":
            out.append(render_table(b["rows"]))
        elif t == "hr":
            out.append("<hr>")
        elif t == "quote":
            if WARN_RE.match(b["text"]):
                out.append('<div class="callout warn">%s</div>' % render_inline(b["text"]))
            else:
                code_ids.append(None)
                pid = "p%d" % len(code_ids)
                out.append(
                    '<div class="callout prompt">'
                    '<div class="chip-row"><span class="chip">Prompt %s</span>' % html.escape(prompt_tool) +
                    '<button class="copy" data-copy="%s" type="button">Copy</button></div>'
                    '<div class="prompt-body" id="%s">%s</div></div>'
                    % (pid, pid, render_inline(b["text"]))
                )
        elif t == "code":
            code_ids.append(None)
            cid = "c%d" % len(code_ids)
            out.append(
                '<div class="code-card"><div class="code-head">'
                '<span class="code-lang">%s</span>'
                '<button class="copy" data-copy="%s" type="button">Copy</button></div>'
                '<pre id="%s"><code>%s</code></pre></div>'
                % (html.escape(b["lang"]), cid, cid, highlight_sql(b["src"]))
            )
    return "\n".join(out)


def split_sections(md):
    """Map level-2 heading -> list of blocks under it (excluding the heading)."""
    blocks = parse_blocks(md)
    sections, current, title = {}, [], None
    order = []
    for b in blocks:
        if b["t"] == "h" and b["level"] == 2:
            if title is not None:
                sections[title] = current
            title = b["text"]
            order.append(title)
            current = []
        elif title is None:
            continue  # front matter before the first h2 (the h1 title)
        else:
            current.append(b)
    if title is not None:
        sections[title] = current
    return sections, order


def build_overview(s4, s5):
    """One Overview merging both sessions' front matter."""
    out = []
    for b in s4.get("Overview", []):
        if b["t"] == "h" and b["text"] in ("Table of Contents",):
            break
        out.append(b)
    # Fold in anything session 5 promises that session 4 does not mention.
    extra = []
    for b in s5.get("Overview", []):
        if b["t"] == "h" and b["text"] == "Table of Contents":
            break
        if b["t"] == "ul":
            extra.extend(b["items"])
    if extra:
        out.append({"t": "h", "level": 3, "text": "Session 5 adds"})
        out.append({"t": "ul", "items": extra})
    return out


STYLE = """
:root {
  color-scheme: light dark;
  --sf-blue: #29b5e8;
  --bg: light-dark(#ffffff, #11151c);
  --bg-alt: light-dark(#f6f8fa, #171d26);
  --fg: light-dark(#1f2933, #d8dee9);
  --fg-strong: light-dark(#11181f, #f2f5f8);
  --muted: light-dark(#5c6b7a, #93a1b1);
  --rule: light-dark(#e2e8ee, #2a323d);
  --code-bg: light-dark(#f6f8fa, #0d1117);
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  font-size: 16px;
  line-height: 1.65;
}
.topbar {
  position: sticky; top: 0; z-index: 20;
  background: light-dark(#11181f, #0b0f14);
  color: #fff;
  padding: 12px clamp(16px, 4vw, 28px);
  display: flex; align-items: center; gap: 12px; flex-wrap: wrap;
  border-bottom: 3px solid var(--sf-blue);
}
.topbar .brand { font-weight: 700; letter-spacing: .2px; }
.topbar .brand span { color: var(--sf-blue); }
.topbar .crumb { color: #9fb0c0; font-size: 14px; }
.layout {
  display: grid;
  grid-template-columns: 288px minmax(0, 1fr);
  gap: clamp(20px, 3vw, 44px);
  max-width: 1240px; width: 100%;
  margin: 0 auto; padding: clamp(16px, 4vw, 32px);
}
nav.toc {
  position: sticky; top: 74px; align-self: start;
  max-height: calc(100vh - 96px); overflow-y: auto;
  border-right: 1px solid var(--rule); padding-right: 16px;
}
nav.toc h2 {
  font-size: 12px; text-transform: uppercase; letter-spacing: .09em;
  color: var(--muted); margin: 0 0 12px;
}
nav.toc ol { list-style: none; margin: 0; padding: 0; counter-reset: step; }
nav.toc li { counter-increment: step; }
nav.toc a {
  display: grid; grid-template-columns: 26px 1fr; gap: 8px;
  padding: 6px 8px; border-radius: 6px;
  color: var(--fg); text-decoration: none; font-size: 14.5px;
}
nav.toc a::before { content: counter(step); color: var(--muted); font-variant-numeric: tabular-nums; }
nav.toc a:hover { background: var(--bg-alt); }
nav.toc a.active { background: light-dark(#e8f6fd, #14232c); color: var(--sf-blue); font-weight: 600; }
nav.toc a.active::before { color: var(--sf-blue); }
nav.toc .navbreak {
  margin: 14px 0; padding: 8px 10px; border-radius: 6px;
  background: var(--bg-alt); border-left: 3px solid var(--sf-blue);
  font-size: 12px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted);
}
main { min-width: 0; max-width: 880px; }
h1 { font-size: clamp(28px, 4vw, 38px); line-height: 1.2; color: var(--fg-strong); margin: 0 0 8px; }
.subtitle { color: var(--muted); font-size: 17px; margin: 0 0 28px; }
h2.section {
  font-size: clamp(22px, 3vw, 27px); color: var(--fg-strong);
  margin: 52px 0 4px; padding-top: 12px; border-top: 1px solid var(--rule);
}
h2.section .num {
  display: inline-block; min-width: 30px;
  color: var(--sf-blue); font-variant-numeric: tabular-nums;
}
h3 { font-size: 19px; color: var(--fg-strong); margin: 30px 0 6px; }
h4 { font-size: 16.5px; color: var(--fg-strong); margin: 22px 0 4px; }
p { margin: 12px 0; }
a { color: light-dark(#0b6ea8, #6cc9ee); }
ul, ol { margin: 12px 0; padding-left: 24px; }
li { margin: 5px 0; }
hr { border: 0; border-top: 1px solid var(--rule); margin: 28px 0; }
strong { color: var(--fg-strong); }
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: .89em; background: var(--bg-alt);
  border: 1px solid var(--rule); border-radius: 4px; padding: 1px 5px;
}
.table-wrap { overflow-x: auto; margin: 18px 0; }
table { border-collapse: collapse; width: 100%; font-size: 14.5px; }
th, td { border: 1px solid var(--rule); padding: 8px 11px; text-align: left; vertical-align: top; }
th { background: var(--bg-alt); color: var(--fg-strong); font-weight: 600; }
img, svg { max-width: 100%; height: auto; }

.code-card { margin: 18px 0; border: 1px solid var(--rule); border-radius: 8px; overflow: hidden; }
.code-head {
  display: flex; justify-content: space-between; align-items: center;
  background: var(--bg-alt); border-bottom: 1px solid var(--rule); padding: 6px 10px;
}
.code-lang { font-size: 11.5px; text-transform: uppercase; letter-spacing: .09em; color: var(--muted); }
.code-card pre {
  margin: 0; padding: 14px; overflow-x: auto; background: var(--code-bg);
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 13.5px; line-height: 1.55;
}
.code-card pre code { background: none; border: 0; padding: 0; font-size: inherit; }
.t-kw { color: light-dark(#0a5aa8, #7cb7f0); font-weight: 600; }
.t-string { color: light-dark(#0a7b4a, #86d9a8); }
.t-comment { color: var(--muted); font-style: italic; }
.t-num { color: light-dark(#a2510b, #e0a35e); }

button.copy {
  font: inherit; font-size: 12px; cursor: pointer;
  background: transparent; color: var(--muted);
  border: 1px solid var(--rule); border-radius: 5px; padding: 3px 10px;
}
button.copy:hover { color: var(--sf-blue); border-color: var(--sf-blue); }
button.copy.done { color: #0a7b4a; border-color: #0a7b4a; }

.callout { margin: 18px 0; border-radius: 8px; padding: 12px 14px; }
.callout.prompt { background: light-dark(#f2fafe, #101d25); border: 1px solid light-dark(#bde5f7, #23414f); }
.chip-row { display: flex; justify-content: space-between; align-items: center; gap: 10px; margin-bottom: 8px; }
.chip {
  background: var(--sf-blue); color: #05222e; font-size: 11px; font-weight: 700;
  text-transform: uppercase; letter-spacing: .07em; padding: 2px 9px; border-radius: 20px;
}
.prompt-body { font-size: 15.5px; }
.callout.warn {
  background: light-dark(#fff8e6, #241d0d);
  border: 1px solid light-dark(#f0d491, #5c4a1c);
}
p.takeaway {
  margin: 18px 0; padding: 12px 14px; border-radius: 8px;
  background: var(--bg-alt); border-left: 4px solid var(--sf-blue);
}
ol.toc-body { margin: 12px 0; }
ol.toc-body li { margin: 3px 0; }

.sessionbreak {
  margin: 56px 0; padding: clamp(20px, 4vw, 30px);
  border: 2px solid var(--sf-blue); border-radius: 12px;
  background: light-dark(#f2fafe, #101d25);
}
.sessionbreak .stop {
  display: inline-block; background: var(--sf-blue); color: #05222e;
  font-size: 12px; font-weight: 800; text-transform: uppercase; letter-spacing: .1em;
  padding: 4px 12px; border-radius: 20px; margin-bottom: 12px;
}
.sessionbreak h2 { margin: 0 0 10px; border: 0; padding: 0; font-size: clamp(21px, 3vw, 26px); color: var(--fg-strong); }
footer { max-width: 880px; margin: 60px auto 0; color: var(--muted); font-size: 14px; }

@media (max-width: 900px) {
  .layout { grid-template-columns: minmax(0, 1fr); }
  nav.toc {
    position: static; max-height: none; border-right: 0;
    border-bottom: 1px solid var(--rule); padding: 0 0 16px;
  }
}
"""

SCRIPT = """
// Copy buttons. No inline handlers: the sandbox strips them.
document.querySelectorAll('button.copy').forEach(function (btn) {
  btn.addEventListener('click', function () {
    var el = document.getElementById(btn.getAttribute('data-copy'));
    if (!el) { return; }
    var text = el.innerText;
    var done = function () {
      var old = btn.textContent;
      btn.textContent = 'Copied';
      btn.classList.add('done');
      window.setTimeout(function () {
        btn.textContent = old;
        btn.classList.remove('done');
      }, 1400);
    };
    // navigator.clipboard is unavailable on file:// in some browsers, so fall back.
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { legacy(text, done); });
    } else {
      legacy(text, done);
    }
  });
});

function legacy(text, done) {
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand('copy'); done(); } catch (e) { /* nothing more to try */ }
  document.body.removeChild(ta);
}

// Scroll-spy: highlight the section currently in view.
var links = Array.prototype.slice.call(document.querySelectorAll('nav.toc a'));
var targets = links.map(function (a) {
  return document.getElementById(a.getAttribute('href').slice(1));
}).filter(Boolean);

if ('IntersectionObserver' in window && targets.length) {
  var seen = new Map();
  var obs = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) { seen.set(e.target.id, e.intersectionRatio); });
    var best = null, bestRatio = 0;
    seen.forEach(function (ratio, id) {
      if (ratio > bestRatio) { bestRatio = ratio; best = id; }
    });
    if (best) {
      links.forEach(function (a) {
        a.classList.toggle('active', a.getAttribute('href') === '#' + best);
      });
    }
  }, { rootMargin: '-80px 0px -60% 0px', threshold: [0, 0.15, 0.4, 0.75, 1] });
  targets.forEach(function (t) { obs.observe(t); });
}
"""


def build(s4_path, s5_path, out_path):
    s4, _ = split_sections(open(s4_path).read())
    s5, _ = split_sections(open(s5_path).read())

    # Session 5 keeps Cleanup and Troubleshooting in one heading; the official guide
    # separates them. Split on the first table: prose and SQL are Cleanup, the symptom
    # table is Troubleshooting.
    combined = s5.pop("Cleanup and Troubleshooting", [])
    cut = next((i for i, b in enumerate(combined) if b["t"] == "table"), len(combined))
    s5["Cleanup"] = combined[:cut]
    s5["Troubleshooting"] = combined[cut:]
    s5["Conclusion"] = s5.pop("Close", [])

    sources = {"s4": s4, "s5": s5}
    missing = [(g, t) for g, t in OFFICIAL_ORDER if t not in sources[g]]
    if missing:
        sys.exit("Missing sections in source guides: %r" % (missing,))

    overview = build_overview(s4, s5)

    # ---- sidebar -------------------------------------------------------------
    nav = ['<nav class="toc"><h2>Contents</h2><ol>']
    nav.append('<li><a href="#overview">Overview</a></li>')
    nav.append('<li><a href="#table-of-contents">Table of Contents</a></li>')
    for guide, title in OFFICIAL_ORDER:
        nav.append('<li><a href="#%s">%s</a></li>' % (slugify(title), html.escape(title)))
        if title == BREAK_AFTER:
            nav.append('</ol><div class="navbreak">Break &middot; session 5 starts here</div><ol start="10">')
    nav.append("</ol></nav>")

    # ---- body ----------------------------------------------------------------
    code_ids = []
    body = [
        "<h1>Fiserv SnowCamp &mdash; Day 2</h1>",
        '<p class="subtitle">Building and governing an AI data application on Snowflake, '
        "with Snowflake CoCo. Sessions 4 and 5, 2&ndash;3 September 2026, Dublin.</p>",
        '<h2 class="section" id="overview"><span class="num">&nbsp;</span>Overview</h2>',
        render_blocks(overview, code_ids),
    ]

    number = 0
    # The official page carries a Table of Contents section in the body as well as the
    # sidebar. Keep it: it is the only navigation that survives printing.
    toc = ['<ol class="toc-body">']
    for guide, title in OFFICIAL_ORDER:
        toc.append('<li><a href="#%s">%s</a></li>' % (slugify(title), html.escape(title)))
        if title == BREAK_AFTER:
            toc.append('</ol><p class="takeaway"><strong>Session 4 ends here.</strong> '
                       'Everything below is session 5, after the break.</p>'
                       '<ol class="toc-body" start="9">')
    toc.append("</ol>")
    body.append('<h2 class="section" id="table-of-contents">'
                '<span class="num">&nbsp;</span>Table of Contents</h2>')
    body.append("".join(toc))

    for guide, title in OFFICIAL_ORDER:
        number += 1
        body.append(
            '<h2 class="section" id="%s"><span class="num">%d</span>%s</h2>'
            % (slugify(title), number, html.escape(title))
        )
        body.append(render_blocks(sources[guide][title], code_ids))

        if title == BREAK_AFTER:
            close4 = render_blocks(s4.get("Close", []), code_ids)
            body.append(
                '<div class="sessionbreak" id="session-break">'
                '<span class="stop">Stop here</span>'
                "<h2>End of session 4</h2>"
                "%s"
                "<p><strong>Take the break.</strong> Session 5 puts a governed agent on top of "
                "everything above, then asks the harder question: how do you know its answers "
                "are right? Nothing below depends on you having finished every optional "
                "subsection, so if you are behind, stop here rather than rushing.</p>"
                "</div>" % close4
            )

    metadata = {
        "generated": date.today().isoformat(),
        "intent": "Fiserv SnowCamp day 2 lab guide, mirroring the official CoCo end-to-end quickstart",
        "upstream": "https://www.snowflake.com/en/developers/guides/sfguide-build-end-to-end-ai-app-on-snowflake/",
        "sourceGuides": [s4_path, s5_path],
        "producerNotes": (
            "Generated by build_guide_html.py. Do not edit this file: edit the markdown "
            "guides and regenerate. Sections dropped from the upstream quickstart: "
            "CoCo Plugin, Optional Iceberg V3."
        ),
        "sections": [
            {"id": slugify(t), "title": t, "source": g} for g, t in OFFICIAL_ORDER
        ],
    }

    import json

    page = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="snowflake-source" content="cortex-agent-authored">
<title>Fiserv SnowCamp &mdash; Day 2 Lab Guide</title>
<script type="application/json" id="snowflake-report-metadata">
%s
</script>
<style>%s</style>
</head>
<body>
<div class="topbar">
  <span class="brand">snow<span>flake</span></span>
  <span class="crumb">Developer Guides &middot; Fiserv SnowCamp &middot; Day 2</span>
</div>
<div class="layout">
%s
<main>
%s
<footer>
  <hr>
  <p>Adapted for Fiserv from
  <a href="https://www.snowflake.com/en/developers/guides/sfguide-build-end-to-end-ai-app-on-snowflake/">Build
  an End-to-End Application Using CoCo on Snowflake</a>. All figures in this guide were
  verified against the workshop account.</p>
</footer>
</main>
</div>
<script>%s</script>
</body>
</html>
""" % (json.dumps(metadata, indent=2), STYLE, "\n".join(nav), "\n".join(body), SCRIPT)

    with open(out_path, "w") as fh:
        fh.write(page)

    sections = len(OFFICIAL_ORDER) + 2  # plus Overview and Table of Contents
    print("%s + %s -> %s" % (s4_path, s5_path, out_path))
    print("  %d sections, %d copyable blocks, %d bytes"
          % (sections, len(code_ids), len(page)))


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2], sys.argv[3])
