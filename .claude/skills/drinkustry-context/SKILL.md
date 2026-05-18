---
name: drinkustry-context
description: Load when starting work on the Drinkustry / butykos Godot codebase, or whenever the user mentions corps (Agri / Industrial / Logistics / Business), the design pivot, slice-1, the four-corp model, lager chain, or asks anything about the project's direction. Loads the design-pivot orientation so the LLM doesn't fall back on the stale CLAUDE.md narrative or the pre-pivot DEVELOPMENT_STATUS.md roadmap.
---

# Drinkustry — project orientation

The codebase folder is `butykos` (legacy name). The game's working title is **Drinkustry**.

## The pivot in one paragraph

Pre-May-2026 this was a single-player alcohol tycoon (`Alcohol Empire Tycoon`) at Phase 7B. May 2026 it pivoted to a **4-player asymmetric co-op cyberpunk-megacorp tycoon** with four corps (Agri, Industrial, Logistics, Business). The pivot is **additive on top of the existing code, not a rewrite**. Slice-1 narrows content to a single lager-beer chain but expands per-corp mechanical depth so all four players have a brewery-interior-equivalent signature mechanic. Networking is the **last** phase, not the first — hot-seat single-machine prototype validates the design first.

## The depth bar

The existing brewery factory interior (`scenes/factory_interior/`) is the depth-bar reference. Every corp must have a signature mechanic of equivalent depth or 3 of 4 players become spectators. Locked in:
- **Industrial:** factory interior (shipped)
- **Agri:** irrigation pipe network (extends Logistics graph; new `network_kind`)
- **Logistics:** OpenTTD-grade route/depot/schedule system + catchment radius + transfer hubs
- **Business:** spatial demand model (settlement tiers, sales outlets) + espionage/integrity

## Read these before designing or implementing

In order:
1. `design_docs/2026-04-30_design_summary.html` — strategic pivot, four corps, two-layer tech tree, Phase 8–12 roadmap
2. `design_docs/2026-05-01_gameplay_corps_production.html` — slice-1 lager chain, 11 starting buildings, universal principles (water+power utilities, agri-input-everywhere, biological/sewage waste split, pollution-shrinks-suitable-land)
3. `design_docs/2026-05-02_per_corp_v1_mechanics.html` — depth-bar rule, per-corp signature mechanics, catchment-radius rule
4. `design_docs/2026-05-07_technical_architecture.html` — engine retrofit (ownership layer, action pipe, MP architecture, refactor ordering)

`CLAUDE.md` describes the architecture, coordinate system, code conventions — these are still accurate. Its "Project Overview" and "Next Development Priorities" sections were updated to reflect the pivot. `DEVELOPMENT_STATUS.md` is now a pre-pivot snapshot (the banner says so); ignore its roadmap.

## Hard constraints

- **No literal combat.** External pressure delivered via espionage / regulatory pressure / market warfare / disasters — implemented as event chains, not as dedicated combat systems.
- **Theme-agnostic core.** Cyberpunk is reskin. Mechanics neutral. Don't bake theme-flavored strings into managers.
- **Hot-seat first, networked last.** Every line of code from Phase 8 onward is written under the lockstep+action-pipe model so Phase 12 is glue, not rewrite.
- **One catchment-radius rule** applied to silos, output bays, and markets uniformly. Don't fragment per corp.
- **Per-corp data namespaced from day one** (`corp_id` field on every owned entity) even before MP exists. Reserve `corp_id: "shared"` for utilities and shared research.

## Refactor ordering (Phase 8 onwards)

Order matters — wrong order = redo:
1. ~~Ownership layer (`corp_id` field everywhere)~~ — **shipped** (step 1, 2026-05-18; alias cleanup as step 0.5 prior)
2. ~~Save schema v3 + migration~~ — **shipped** (step 2, 2026-05-18; `shared.money` for now; per-corp wallets are v3→v4 in a later commit)
3. `submit_action(corp_id, action_type, payload)` skeleton — **next** (step 3)
4. Tech-tree two-layer refactor
5. UtilityManager (water/power/sewage — one manager, three named graphs)
6. CatchmentManager replacing direct routes
7. OverlayManager (suitability + pollution first; same infra carries water/power/integrity later)
8. Per-corp signature mechanics: Industrial (done) → Agri irrigation → Logistics route-network → Business demand+espionage
9. EventManager (narrative events)
10. Networking glue (Phase 12)

## Slice-1 scope discipline

Slice-1 = lager only. Distillery, packaging plant, storage warehouse, spirits chain, packaged_ale, premium variants — **all carried forward in code as content, gated as post-slice-1**. Don't build new content in those areas during Phase 8/9/10. Cider lands in slice-2 with apple orchards.

## Architectural primitives that already exist and are foundation, not legacy

- Singleton-manager + EventBus pattern (40+ signals)
- Dual-layer map (isometric strategic + orthogonal interior)
- Data-driven JSON content
- Sprite-with-fallback rendering pipeline
- Multi-slot save system (schema gets bumped, not replaced)
- Profit-gated tech tree (split into two layers, not replaced)

## When in doubt

Read the technical architecture doc first (`design_docs/2026-05-07_technical_architecture.html`). It pins the architectural decisions. Anything not pinned there is an open question — flag it rather than guessing.
