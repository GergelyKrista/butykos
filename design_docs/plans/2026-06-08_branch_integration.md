# Branch Integration Plan — 2026-06-08

Integrate the parallel work stream (11 remote branches off `origin/dev` = `a54c271`) into `dev`,
stabilize, then promote `dev` → `main` as a single step.

**This is a plan. Nothing is merged. No PRs opened. `dev` is untouched.**

All SHAs below verified via `git log` / `git merge-base` / `git patch-id` against the fetched remotes
on 2026-06-08. `origin/dev` = `a54c271cd96e2e400308817864511acb6fbbf1c3`.

---

## 0. Executive summary (read this first)

- **The parallel stream did NOT rewire UI to `submit_action`.** The `testing` branch's UI files call
  managers directly (corp-aware: `EconomyManager.spend_money(GameManager.active_corp_id, …)`,
  `WorldManager.place_facility(…)`), exactly the step-3b direct-call pattern. `submit_action` appears
  only in `core/game_manager.gd` (8x) and `systems/economy_manager.gd` (1x) in `testing` — identical
  to `dev`. **Step 3c is real, non-redundant work that must be re-applied on top of the merged stream.**
  → **Decision: option (b).** Merge the downstream stream first, then apply the step-3c rewire on top.

- **`testing/farmhouse+corp-switcher` is the integration shortcut.** It already contains, by content,
  ALL four merged feature branches: `corp-switcher` (exact SHA), `logistics-network-readable` (exact SHA),
  `brewery-lager-chain` (exact SHA), and `farmhouse-rectangle-and-farm-fields` (cherry-picked — **identical
  patch-ids**, see §1). Merging `testing` brings in all four in one go. The four feature branches can then
  be **dropped** (do not merge them separately).

- **Riskiest merge: step-3c re-application over `testing`.** Not a textual git conflict — a semantic
  re-implementation. `testing` reworked the same 5 UI files far more heavily than the step-3c branch did,
  AND added new direct-call flows (Trading Screen sell, Water Pump, farm-field place) that have **no
  `submit_action` equivalent yet**. See §2 and §4.

- **Phase-ordering divergence (informational, needs user call):** the stream jumped to Phase 10 step 0a/0b
  (corp switcher) and Slice 3.x content/Business-corp work, **skipping Phase 8 step 4 (two-layer tech tree)
  and steps 5–7 (utilities / catchment / pollution overlay)**. See §8.

---

## 1. Branch inventory

Base for all = `a54c271` (= `origin/dev`). "In testing?" = contained by content in
`origin/testing/farmhouse+corp-switcher` (tip `d972c4e`).

| Branch | Tip | Commits ahead | Purpose | In testing? |
|---|---|---|---|---|
| `feature/phase8-step3c-ui-rewire` | `835e684` | 1 | Rewire UI call sites → `submit_action` | **NO** (the one thing testing lacks) |
| `feature/corp-switcher-debug-ui` | `f5142ed` | 3 | Phase 10 0a/0b: dev corp-switcher dropdown + per-corp build-menu filter + agri road | **YES (exact SHA)** |
| `feature/farmhouse-rectangle-and-farm-fields` | `62d010d` | 8 | Farm-field rework (working_area rect, generic farm_field, per-field crop, multi-tile, radius-from-footprint) | **YES (6 by SHA + 2 by patch-id)** |
| `feature/logistics-network-readable` | `52b9787` | 11 | Node-graph logistics UI (box nodes, sockets, zoom/pan, product-colored lines, marching arrows, per-corp view state) | **YES (exact SHA)** |
| `feature/brewery-lager-chain` | `bd9af28` | 2 | Slice 3.1 brewery chain data (machines + recipes), respect `hidden_from_build_menu` | **YES (exact SHA)** |
| `testing/farmhouse+corp-switcher` | `d972c4e` | 51 | Integration branch: above 4 + Slice 3.2/3.3 per-machine config + buffer caps, Water Pump, Slice-1 Business corp (outside connections + Trading Screen), 1920x1080/1280x720, Godot 4.6 metadata, lower auto-dispatch threshold | — (is the integration branch) |

Note `dev` IS an ancestor of `testing` (`git merge-base --is-ancestor origin/dev origin/testing` → true).
The `testing` → `dev` merge is therefore a fast-forward-equivalent: it introduces no conflict against `dev`
itself. All the merge risk is between `testing` and the **separately-merged step-3c branch**, not between
`testing` and `dev`.

### Farmhouse patch-id proof (why the feature branch is fully superseded)

```
62d010d  patch-id a0bd221883722d38703daaea759a05f782b051a3
6be46ba  patch-id e12e101c014f7b2b65282ae10c8b997f97c9c46a
testing 0568443  patch-id a0bd221883722d38703daaea759a05f782b051a3   <- identical
testing a03cdb8  patch-id e12e101c014f7b2b65282ae10c8b997f97c9c46a   <- identical
```

The "2 farmhouse commits not in testing by SHA" are present by content (cherry-picked). **Drop the
farmhouse feature branch.**

### Docs branches (all doc-only at the commit level — verified)

| Branch | Commit(s) | Files | Base |
|---|---|---|---|
| `docs/brewery-chain-2026-06-05` | `e264837` | 1 design `.md` | `a54c271` |
| `docs/bugs-2026-06-04` | `3ae895f` | `BUGS.md` | `a54c271` |
| `docs/bugs-2026-06-05` | `97678d1`, `e00c39a` | `BUGS.md` | `a54c271` |
| `docs/factory-backpressure` | `98a2428` | 1 design `.html` (440 lines) | **`b402645` (a testing-lineage merge commit)** |
| `docs/storage-sales-business` | `336a45e` | 1 design `.html` (539 lines) | **`b402645` (a testing-lineage merge commit)** |

The last two LOOK code-heavy in a raw `git diff origin/dev..` because their base sits inside the testing
lineage (`b402645` = "Merge pull request #4"). The **commit itself is one HTML file**. Once `testing` is in
`dev`, their code delta vanishes and only the HTML remains — cherry-pick the single commit. See §5.

---

## 2. The step-3c integration decision (central)

### What was found

| Question | Finding |
|---|---|
| Does `testing` use `submit_action` in UI? | **No.** `git grep -c submit_action` on `testing` = `game_manager.gd:8`, `economy_manager.gd:1` — identical to `dev`. Zero in any `scenes/**/*.gd`. |
| Does step-3c use `submit_action` in UI? | **Yes**, in all 5 UI files (`world_map.gd` 11x, `factory_interior.gd` 4x, `farmhouse_ui.gd` 2x, `logistics_network_panel.gd` 2x, `world_map_ui.gd` 2x). |
| Do the action handlers exist in `testing`? | **Yes — identical to dev.** All `ACTION_*` constants and handlers (`PLACE_FACILITY`, `PLACE_FIELD`, `PLACE_ROAD`, `DEMOLISH_FACILITY`, `CREATE_LOGISTICS_CONNECTION`, `RESEARCH_TECH`, …) are byte-identical between `dev` and `testing`. testing inherited the step-3b pipe but never routed UI through it. |
| Does `testing` source `active_corp_id` already? | **Yes.** testing's `world_map.gd` already reads `GameManager.active_corp_id` for direct economy calls and listens to `active_corp_changed`. The corp plumbing step-3c assumes is present. |
| New flows in `testing` with no action handler? | **Yes.** `trading_screen.gd:373` calls `EconomyManager.earn_money(GameManager.CORP_BUSINESS, …)` directly; farm-field place calls `spend_money` directly; Water Pump path is direct. There is **no `ACTION_SELL_TO_MARKET` / Business-sell action constant**. |

### Options

- **(a) Step-3c first, then rebase downstream on top.** Rejected: downstream is 51 commits with merge
  commits and would have to be re-applied over the submit_action pattern — far more conflict surface, and
  testing's UI is the larger/newer version we want to keep. Wrong direction.
- **(b) Downstream (`testing`) first, then apply step-3c's rewire on top.** **CHOSEN.** testing's UI is the
  canonical, larger version; the action handlers already exist; step-3c becomes a focused UI-layer task of
  swapping direct calls for `submit_action(...)` wrappers in the merged files.
- **(c) testing already did an equivalent rewire — drop step-3c.** Rejected: false. testing has zero
  `submit_action` in UI.

### Decision

**Option (b).** Merge `testing` into `dev` first. Then re-apply the step-3c rewire as a fresh task over the
merged UI files — NOT by merging the `835e684` branch (it would conflict textually with testing's far-larger
versions and lose testing's new flows). Treat the `feature/phase8-step3c-ui-rewire` branch as a **reference
spec** for the rewire, executed by hand against testing's files.

**Load-bearing:** step-3c-over-testing must cover the call sites the original branch knew about **plus** the
new testing-only flows (Business sell, Water Pump, farm-field place). The original step-3c branch is an
incomplete map of the post-testing UI. Do not assume "apply the 5-file diff and done."

**Schema-discipline flag:** the new Business-sell flow needs its own action (`ACTION_SELL_TO_MARKET` or
similar) added to `game_manager.gd` with a predicate + handler, not a direct `earn_money`. That is net-new
pipe work surfaced by this merge — record it, don't paper over it. (No save-schema bump implied; this is the
action layer, not the save format.)

---

## 3. Ordered merge sequence (into `dev`)

Execute on a throwaway integration branch first if desired, but the target is `dev`. Each step lists
expected conflicts and the resolution side.

### Step I-1 — Merge `origin/testing/farmhouse+corp-switcher` → `dev`
- **Why first:** it is a strict superset of `dev` (dev is its ancestor) and contains all four feature
  branches. One merge replaces five.
- **Expected conflicts:** none against `dev` (fast-forward-equivalent; dev is ancestor). Use a real merge
  commit (`--no-ff`) for a clean promotion record, or fast-forward — either is conflict-free.
- **Brings in:** corp-switcher, logistics-network-readable, brewery-lager-chain, farmhouse fields,
  Slice 3.2/3.3, Water Pump, Business corp + Trading Screen, **project.godot resolution + Godot 4.6 bump**,
  Godot 4.6 `.import` regen.
- **Done when:** `git log` shows `d972c4e` reachable from `dev`; Godot opens the project without import
  errors (see smoke checkpoint C1).

### Step I-2 — Apply step-3c rewire over merged UI (hand-executed, spec = `835e684`)
- **Why second:** the action handlers already exist in the merged tree; this is the last piece to make the
  whole UI route through `submit_action`, satisfying the MP-boundary constraint.
- **Do NOT `git merge origin/feature/phase8-step3c-ui-rewire`** — it conflicts textually with testing's
  larger UI files and predates the new flows. Instead:
  1. Diff `a54c271..835e684` per file to extract the *intent* (which direct calls became which actions).
  2. In the merged tree, replace each direct mutation call site in the 5 UI files with the matching
     `GameManager.submit_action(GameManager.active_corp_id, ACTION_*, {payload})`.
  3. Apply step-3c's `systems/economy_manager.gd` change verbatim (removes the compat predicates — this file
     is unchanged in testing, so it applies clean; see §4).
  4. Add the new action(s) for testing-only flows: `ACTION_SELL_TO_MARKET` (Business/Trading sell), and
     route Water Pump / farm-field place through existing or new actions. Wire predicate + handler in
     `game_manager.gd`.
- **Expected conflicts:** semantic, not textual (you are editing, not merging). The risk is *missing* a
  call site. Mitigate by grepping the merged tree for residual direct mutations:
  `EconomyManager.spend_money|earn_money|sell_product`, `WorldManager.place_facility|place_road|remove_facility`,
  `FactoryManager.place_machine|create_connection`, `ResearchManager.research_*` in `scenes/**/*.gd`.
  After rewire, those should appear only inside `game_manager.gd` handlers.
- **Done when:** `git grep` finds direct manager mutation calls only in `game_manager.gd` (and read-only
  getters anywhere); game still places/sells/builds correctly (smoke checkpoint C2).

### Step I-3 — Cherry-pick the two testing-base docs commits
- `git cherry-pick 98a2428` (factory-backpressure HTML) and `git cherry-pick 336a45e`
  (storage-sales-business HTML). With testing already in `dev`, only the HTML lands; no code delta.
- **Done when:** both HTML files exist on `dev`; `git show` of each cherry-pick touches one file.

### Step I-4 — Batch-merge the four pure-doc branches
- `docs/brewery-chain-2026-06-05` (`e264837`), `docs/bugs-2026-06-04` (`3ae895f`),
  `docs/bugs-2026-06-05` (`97678d1`, `e00c39a`). Base = `a54c271`, all doc-only.
- Possible `BUGS.md` text conflict between `docs/bugs-2026-06-04` and `docs/bugs-2026-06-05` (both append to
  `BUGS.md`). Resolution: keep both sessions' entries (union; chronological order). Trivial.
- **Done when:** all four doc files present; `BUGS.md` contains both playtest sessions.

### Step I-5 — Update the canonical decision log
- Append an ADR to `design_docs/2026-05-07_technical_architecture.html` (or a successor dated doc) recording:
  the step-3c-over-testing decision, the new `ACTION_SELL_TO_MARKET`, the Phase-8 step 4–7 deferral, and the
  resolution bump / Godot 4.6 adoption. Architect-owned follow-up, not a code merge.

### Step I-6 — Promote `dev` → `main`
- After C3 passes. Single `--no-ff` promotion. See §6.

---

## 4. Conflict matrix and resolution guidance

File overlap between the two things that actually collide — `testing` (cumulative since `a54c271`) and the
step-3c branch:

| File | testing change | step-3c change | Overlap | Resolution principle |
|---|---|---|---|---|
| `scenes/world_map/world_map.gd` | +370 (corp-aware direct calls, farm fields, road, build menu) | reworks 202 (direct → submit_action) | **YES** | Keep testing's body; convert its direct mutation calls to `submit_action`. Preserve testing's `GameManager.active_corp_id` sourcing (step-3c uses the same idiom). |
| `scenes/factory_interior/factory_interior.gd` | +294 (Slice 3.2/3.3 per-machine config, buffer caps) | reworks 103 | **YES** | Keep testing's body; wrap machine place/connect/config mutations in `ACTION_PLACE_MACHINE` / `ACTION_CREATE_MACHINE_CONNECTION` etc. |
| `scenes/ui/farmhouse_ui.gd` | +104 (info-only refactor) | reworks 10 | **YES** | Keep testing's info-only UI; route the few remaining mutations (crop set) through `ACTION_SET_FARMHOUSE_CROP`. |
| `scenes/ui/logistics_network_panel.gd` | +70 (node-graph overhaul) | reworks 14 | **YES** | Keep testing's panel; route connection create/remove/toggle through the existing logistics actions. |
| `scenes/world_map/world_map_ui.gd` | +246 (build-menu filter, corp switcher HUD) | reworks 8 | **YES** | Keep testing's HUD; route any spend through actions. |
| `systems/economy_manager.gd` | **unchanged from dev** | removes 24 lines (compat predicates) | **NO** | Apply step-3c's deletion verbatim. Clean — testing never touched this file. |
| `scenes/ui/trading_screen.gd` | NEW (+398, direct `earn_money`) | absent | step-3c blind spot | Add `ACTION_SELL_TO_MARKET`; route `earn_money(CORP_BUSINESS,…)` through it. |
| `core/game_manager.gd` | identical to dev | identical to dev | none | Handlers already present; add new sell action here. |
| `project.godot` | +13 (4.2→4.6, 1920x1080, stretch) | untouched | none | testing wins (only changer). See §4a. |
| `data/machines.json` (+1703), `recipes.json` (+68), `products.json` (+81), `facilities.json` (+300), `roads.json` (+13) | testing only | untouched | none | testing wins outright. Brewery chain + Water Pump + per-machine config data. |
| `scenes/ui/network_view.gd` (+853), `route_renderer.gd`, `camera_controller.gd`, `world_manager.gd` (+230), `production_manager.gd` (+586), `logistics_manager.gd`, `factory_manager.gd`, `market_manager.gd`, `data_manager.gd`, `event_bus.gd` (+12) | testing only | untouched | none | testing wins outright. |

**General rule:** wherever the two collide, **testing supplies the code body, step-3c supplies the routing
discipline.** Resolve every UI conflict in favor of "testing's logic, called through the pipe."

### 4a. project.godot / Godot 4.6 / resolution — isolation note
- `project.godot` diff is small (13 lines: `config/features` 4.2→4.6, `[display]` 1920x1080 + stretch,
  one `[animation]` compat flag). The wide-but-shallow surface is the **`.import` regen** (many 6-line
  `.import` files) and the Godot 4.6 metadata. These are entangled in the `testing` history (commits
  `8301527` "Godot 4.6 metadata regeneration", `c3f9a79` / `a55b966` resolution).
- **Recommendation:** do NOT try to cherry-pick these out of `testing` — they are interleaved with code
  commits and re-merge cleanly as part of the single `testing` merge (Step I-1). The isolation that matters
  is **verification**: at checkpoint C1, the *first* thing to confirm is that the project opens under the
  user's Godot version with no import/parse errors, before touching any gameplay. If the user's installed
  Godot is < 4.6, the `config/features=4.6` line will warn — flag to user (see §8 unknowns).

---

## 5. Docs branches — recommendation

- All five are doc-only at the commit level (verified per-commit `--stat`).
- `docs/factory-backpressure` and `docs/storage-sales-business` sit on a testing-lineage base, so merge them
  **after** `testing` is in `dev` (Step I-3, cherry-pick the single commit each — code delta is already
  present).
- The three true-`a54c271`-base doc branches batch into one merge (Step I-4). Only expected conflict is
  `BUGS.md` (two branches append) — union-resolve.

---

## 6. dev vs main

- The user said "merge into main." The project workflow is **feature → dev → main**.
- **Recommendation:** integrate and stabilize everything on `dev` (Steps I-1…I-5), run the smoke
  checkpoints, then promote `dev` → `main` as ONE `--no-ff` merge (Step I-6). Do not merge any feature/docs
  branch directly into `main`.
- **Flag for user confirmation:** confirm `main` should receive this whole batch now, or whether `main`
  stays at the last stable release until the step-3c rewire + Business-sell action are fully smoke-tested.
  Given step-3c-over-testing is the riskiest piece, holding `main` until C3 passes is the safe call.

---

## 7. Smoke-test checkpoints

Run Godot at these points rather than one big-bang test at the end.

- **C1 — after Step I-1 (testing merged).** Project opens under Godot (verify version vs 4.6), no import or
  parse errors. Launch `scenes/ui/main_menu.tscn`. Verify: corp switcher dropdown works; per-corp build
  menu filters; place a farm field (multi-tile, crop selector); brewery chain machines appear; logistics
  node-graph panel renders (zoom/pan/sockets); Trading Screen opens and a lager sale credits the Business
  corp wallet; load an existing save (schema v3 migration intact). **Gate: do not proceed to I-2 if C1 fails.**
- **C2 — after Step I-2 (step-3c rewire over testing).** Re-run every mutation from C1 (place facility,
  place field, place road, demolish, place/connect/config machine, create/toggle logistics connection,
  research a tech, Business sell). All must still succeed AND now flow through `submit_action`
  (confirm via the grep in I-2 plus a log/print in the action handlers). **This is the checkpoint that
  catches a missed call site.**
- **C3 — after Steps I-3/I-4 (docs).** Sanity re-open only; docs can't break runtime. Then promote to `main`.

---

## 8. Risks, unknowns, and items needing the user's call

1. **Step-3c-over-testing is the single riskiest merge.** It is a hand re-application across 5 large,
   recently-rewritten UI files plus new flows the original step-3c branch never saw. Budget for missed call
   sites; the C2 grep + checkpoint is the safety net. (Architect-resolved approach; implementer executes.)
2. **New Business-sell action is net-new pipe work** surfaced by this merge — `trading_screen.gd` sells via
   direct `earn_money`. Needs `ACTION_SELL_TO_MARKET` (constant + predicate + handler). Confirm naming /
   whether market-side supply-pressure side effects belong in the handler.
3. **Phase-ordering divergence (needs user call).** The stream built Phase 10 step 0a/0b (corp switcher) and
   Slice 3.x content + Slice-1 Business corp, but **skipped Phase 8 step 4 (two-layer tech tree) and steps
   5–7 (utilities / catchment radius / pollution overlay)**, which the technical-architecture refactor
   ordering (§7) places before Phase 10. This is not a blocker for merging, but: confirm steps 4–7 are
   *deferred*, not *abandoned*. The catchment-radius rule (a hard constraint) is still unimplemented; corp
   switcher arriving first does not violate it but does mean Phase 10's spatial work lands on a base that
   skipped the radius foundation. Record the deferral in the decision log (Step I-5).
4. **Godot version.** `testing` sets `config/features=4.6` and regenerated metadata. The repo CLAUDE.md says
   Godot 4.2. Confirm the user's installed Godot is ≥ 4.6 before C1, else the project will warn/break on
   open. If the user is not on 4.6, this is a blocker to surface immediately.
5. **Resolution change is global** (1920x1080 base, 1280x720 panels, stretch=canvas_items). Confirm this is
   intended for `main`, not a dev-only experiment.
6. **`testing` carries merge commits** (it merged PR #4 etc.). Merging it with `--no-ff` preserves a noisy
   but accurate history. If the user wants a linear `dev`, a squash-merge of `testing` is an option — but
   that discards the per-feature attribution and makes future `git bisect` coarser. Recommend `--no-ff`
   (preserve history); flag squash as the alternative the user may prefer.
7. **Save-schema discipline:** none of the merged work appears to bump the save schema beyond v3 (verify
   `SAVE_VERSION` in `save_manager.gd` post-merge at C1). If any Slice 3.x per-machine config persists into
   the save, confirm it round-trips under v3 or warrants a v3→v4 migration — do NOT absorb new shape via
   getter aliases (hard constraint).

---

## 9. One-glance merge order

```
I-1  merge  origin/testing/farmhouse+corp-switcher  -> dev      (conflict-free; brings 4 features + Slice 3.x + Business + 4.6 + res)
        |--> C1 smoke (MUST pass)
I-2  apply  step-3c rewire BY HAND over merged UI (spec=835e684) + economy_manager deletion + new ACTION_SELL_TO_MARKET
        |--> C2 smoke (catches missed call sites)
I-3  cherry-pick 98a2428, 336a45e                    -> dev      (HTML only)
I-4  merge  docs/brewery-chain-2026-06-05, docs/bugs-2026-06-04, docs/bugs-2026-06-05 -> dev  (BUGS.md union)
        |--> C3 sanity
I-5  ADR    update technical-architecture decision log
I-6  promote dev -> main  (--no-ff, single step)     [pending user confirm per §6]

DROP (superseded by I-1, do not merge separately):
  feature/corp-switcher-debug-ui, feature/logistics-network-readable,
  feature/brewery-lager-chain, feature/farmhouse-rectangle-and-farm-fields,
  feature/phase8-step3c-ui-rewire (kept as REFERENCE SPEC only, not merged)
```
