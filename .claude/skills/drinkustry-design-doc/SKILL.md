---
name: drinkustry-design-doc
description: Use when writing a new design doc, decision log, brainstorm, or technical RFC for the Drinkustry / butykos project. Captures the established HTML/CSS style from the existing docs in design_docs/ so new docs match visually and tonally. Triggers on requests like "write a design doc", "brainstorm doc", "add a decision log", "draft an RFC for X", "capture this design discussion as a doc".
---

# Drinkustry — design doc style guide

Docs live in `design_docs/<YYYY-MM-DD>_<topic>.html`. They are **standalone HTML files** — open one in a browser and it reads top-to-bottom. No build step, no asset deps, embedded CSS only.

## File naming

`<YYYY-MM-DD>_<topic_with_underscores>.html` — date is the doc's intellectual date (when the decision is made / brainstorm happens), not necessarily commit date. Topic is short and grep-friendly (`gameplay_corps_production`, not `the-meeting-notes-from-tuesday`).

## Voice

- Designer-to-designer, terse. No filler. No "this is an exciting opportunity".
- Decisions in `<strong>`. Recommendations explicitly marked. Open questions explicitly named.
- Use `<em>` for asides and tone, sparingly.
- Number open questions (`Q1`, `Q2`...) so they're addressable in later docs.
- Number major decisions (`D-01`, `D-02`...) for the same reason.

## Structure

Always:
1. `<header class="doc-header">` with eyebrow (date + tag), `<h1>` title, optional `<p class="lede">` 1-2 sentence framing
2. `.meta` grid (status, audience, supersedes/extends, etc.)
3. `.toc` table of contents — every `<h2>` listed
4. Body: `<h2>` major sections, `<h3>` subsections, `<h4>` for label-style headings (uppercase letterspaced)
5. `<footer class="doc-footer">` with date and pointer to next/prev doc if applicable

## Visual primitives (already defined in CSS)

Reuse these — don't invent new ones unless necessary:

- `.callout` (default), `.callout.warn`, `.callout.success`, `.callout.scratch` — for emphasis blocks. `.callout-title` for the bold lead.
- `.corp-card` with modifier `.agri` / `.industrial` / `.logistics` / `.business` — top-border colored. Inside: `.corp-tag` for the corp label.
- `.signature` block with `.signature-label` + `.signature-body` — for "the signature mechanic is X" statements.
- `.qbox` with `.qbox-q` + `.qbox-note` — for open questions. Pink left border.
- `.principle` with `.principle-title` — for general design principles.
- `.layer-grid` + `.layer-card` (with corp modifiers) — 2-col grid of corp-flavored cards.
- `<table>` — auto-styled, dark, bordered. Use for matrices/comparisons.

## Pills (status tags)

`<span class="pill pill-MOD">label</span>`:
- `pill.set` — resolved decision (blue)
- `pill.q` — open question (pink)
- `pill.locked` — hard constraint (orange)
- `pill.tbd` — deferred / not yet (yellow)
- `pill.seed` — seed/early-stage feature (green)

## Color palette (CSS variables — reuse, don't override)

```css
--bg: #0e1116;        /* deep page background */
--surface: #161b22;   /* card backgrounds */
--surface-2: #1f2630; /* inset / inputs / pills */
--border: #2a3340;    /* hairlines */
--text: #e6edf3;      /* body */
--text-dim: #9aa6b2;  /* secondary */
--accent: #4cc2ff;    /* logistics blue, default accent */
--accent-2: #ff6ec7;  /* business pink */
--accent-3: #7ee787;  /* agri green */
--warn: #f0b429;      /* warnings, deferred */
--agri: #7ee787;
--industrial: #f0883e;
--logistics: #4cc2ff;
--business: #ff6ec7;
```

When highlighting per corp, **always** use these four corp colors. Don't assign new colors per corp.

## Length guidance

- **Brainstorm doc** (raw output of a discussion): 200-500 lines is fine. Don't over-polish.
- **Design decision doc** (locks in choices): 400-800 lines. Every major decision visible in TOC.
- **Technical architecture / RFC** (engine retrofit, schema migration): 800-1300 lines. Include code-style examples in `<pre><code>` if helpful.

If a doc is over 1500 lines, split it into a series.

## What to put in vs leave out

**In:** decisions, recommendations, hard constraints, open questions, comparative reference, code-shape examples, tradeoff tables.
**Out:** rambling reasoning chains (compress to "considered X, picked Y because Z"), restating the previous doc (link instead), implementation pseudocode for things already shipped, marketing language.

## Bootstrapping a new doc

Fastest way: copy the most stylistically similar existing doc as a starting point.

- For a strategic / vision doc: copy `2026-04-30_design_summary.html` shape.
- For a gameplay-grounding doc: copy `2026-05-01_gameplay_corps_production.html`.
- For a per-corp signature / depth-bar discussion: copy `2026-05-02_per_corp_v1_mechanics.html`.
- For a technical / architecture / RFC doc: copy `2026-05-07_technical_architecture.html`.

Replace title, eyebrow date, meta grid, TOC, and body. Keep the `<style>` block intact across docs so they all match.

## After writing

- Update CLAUDE.md's "DESIGN PIVOT" notice section if this doc becomes part of the canonical reading order
- If the doc supersedes part of an older doc, add a `<callout class="warn">` near the top of the older doc pointing at the new one
- Don't auto-add to a master index — the date-prefixed filenames sort naturally
