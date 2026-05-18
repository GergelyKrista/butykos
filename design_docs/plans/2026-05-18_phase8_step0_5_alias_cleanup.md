# Phase 8 — Step 0.5: LogisticsManager Alias-Creep Cleanup

**Doc type:** Refactor plan, hand-off to drinkustry-implementer
**Date:** 2026-05-18
**Author:** Architect
**Scope:** Collapse every `route` / `connection` alias pair to a single canonical name. **No `corp_id` work, no save-version bump, no schema redesign.**
**Predecessor:** `design_docs/2026-05-07_technical_architecture.html` §5 (schema-drift warning), `.claude/skills/drinkustry-save-migration/SKILL.md` (the "stop alias-creep" rule)
**Successor:** `design_docs/plans/2026-05-18_phase8_step1_corp_id.md` (step 1 — corp_id field). Step 0.5 must land before step 1.

---

## TL;DR for the implementer

You will pick one name per alias pair (always the non-aliased canonical), delete every alias getter/setter/wrapper, and update every call site across managers, UI, and renderers. EventBus loses three signals (`route_created`, `route_removed`, `route_updated`). `save_manager.gd` keeps reading either old or new keys for one more version (migrate-on-load), but only writes canonical keys going forward. The save schema stays `version: 1` for now — that bump is step 2.

When you are done: rg for `\broutes\b`, `\broute_id\b`, `_next_route_id`, `route_paths`, `create_route`, `remove_route`, `get_route`, `get_all_routes`, `get_route_count`, `set_route_active`, `toggle_route_active`, `get_routes_from_facility`, `get_routes_to_facility`, `pickup_amount`, `EventBus\.route_` returns **zero hits in `core/`, `systems/`, `scenes/`**. Hits in `design_docs/`, `*.md` documentation, and skill files are fine — those are descriptive, not load-bearing.

---

## 1. Inventory — every symbol pair and call site

### 1.1 Symbol pairs in `systems/logistics_manager.gd`

| # | Aliased symbol | Canonical | Site (logistics_manager.gd) |
|---|---|---|---|
| 1 | `routes: Dictionary` (getter/setter) | `connections` | :53–55 |
| 2 | `route_paths: Dictionary` (getter/setter) | `connection_paths` | :62–64 |
| 3 | `_next_route_id: int` (getter/setter) | `_next_connection_id` | :68–70 |
| 4 | `pickup_amount: int` (getter/setter) | `vehicle_capacity` | :79–81 |
| 5 | `create_route()` wrapper | `create_connection()` | :188 |
| 6 | `remove_route()` wrapper | `remove_connection()` | :253 |
| 7 | `get_route()` wrapper | `get_connection()` | :288 |
| 8 | `set_route_active()` wrapper | `set_connection_active()` | :298 |
| 9 | `toggle_route_active()` wrapper | `toggle_connection_active()` | :316 |
| 10 | `get_routes_from_facility()` wrapper | `get_connections_from_facility()` | :334 |
| 11 | `get_routes_to_facility()` wrapper | `get_connections_to_facility()` | :348 |
| 12 | `get_all_routes()` wrapper | `get_all_connections()` | :659 |
| 13 | `get_route_count()` wrapper | `get_connection_count()` | :683 |

**In-file vehicle `route_id` alias** — every vehicle dict carries both `connection_id` and `route_id` (same value). Sites where `vehicle.get("connection_id", vehicle.get("route_id", ""))` is used as a defensive read: :178, :268, :336 (in save_manager), :366, :388 (vehicle dict creation — *writes* both keys), :426, :647. **Pair 14: `vehicle.route_id` key, canonical `vehicle.connection_id`.**

### 1.2 EventBus signal pairs (`core/event_bus.gd`)

| # | Aliased signal | Canonical | Site |
|---|---|---|---|
| 15 | `signal route_created(route_data: Dictionary)` | `connection_created` | :85 |
| 16 | `signal route_removed(route_id: String)` | `connection_removed` | :88 |
| 17 | `signal route_updated(route_data: Dictionary)` | `connection_updated` | :91 |

### 1.3 Save-format key pairs (`core/save_manager.gd`)

| # | Old key (read fallback) | Canonical key | Sites |
|---|---|---|---|
| 18 | `routes` (read) / `routes` (write) | `connections` | :356 (write), :622 (read fallback), :306 (comment) |
| 19 | `route_paths` (read) / `route_paths` (write) | `connection_paths` | :357 (write), :613 (read fallback) |
| 20 | `next_route_id` (read) / `next_route_id` (write) | `next_connection_id` | :355 (write), :609 (read fallback) |
| 21 | `route_id` (read) on vehicle dicts / `route_id` (write) | `connection_id` | :336 (write), :652 (read fallback), :657 (writes both keys on restore) |

### 1.4 Every external call site touching aliases

**`scenes/world_map/world_map.gd`:**
- :883 — `LogisticsManager.create_route(...)` → must become `create_connection`
- :883, :885, :886 — local var `route_id` renamed to `connection_id`

**`scenes/world_map/world_map_ui.gd`:**
- :65 — `EventBus.route_created.connect(_on_route_changed)`
- :66 — `EventBus.route_removed.connect(_on_route_removed)`
- :67 — `EventBus.route_updated.connect(_on_route_changed)`
- :503–612 — entire "Routes Panel" UI section (function names, variable names, label strings — see §4.4 for the keep/rename decision)
- :539 — `LogisticsManager.get_all_routes()` → `get_all_connections()`
- :615 — `LogisticsManager.toggle_route_active(route_id)` → `toggle_connection_active(connection_id)`
- :621 — `LogisticsManager.remove_route(route_id)` → `remove_connection(connection_id)`

**`scenes/world_map/route_renderer.gd`:** entire file is alias-soaked (`LogisticsManager.routes`, `EventBus.route_created/removed`). See §4.5 for the file-rename decision.
- :13–14 — signal connects
- :31–32 — iterates `LogisticsManager.routes`
- :36, :71, :122, :132 — function names use `route`
- :56, :83 — node name strings use `route_line_` / `route_arrow_`
- Multiple local var `route_id` and `route` dicts

**`scenes/world_map/vehicle_renderer.gd`:**
- :83 — comment "Draw above routes and facilities"
- :104 — `var route_id = vehicle.get("route_id", "")` → `var connection_id = vehicle.get("connection_id", "")`
- :109, :114, :122, :127, :129, :143 — parameter `route_id` renamed; `LogisticsManager.routes.get(...)` → `connections.get(...)`

**`scenes/world_map/world_map.tscn`:** :7 — `path="res://scenes/world_map/route_renderer.gd"` (see §4.5 for whether the file is renamed)

### 1.5 No other call sites

Verified via grep — `scenes/ui/logistics_network_panel.gd` (:58, :59, :87, :95) and `scenes/ui/network_view.gd` (:58, :152) already use canonical names. They need **zero changes**.

Documentation mentions in `CLAUDE.md`, `DEVELOPMENT_STATUS.md`, `TESTING.md`, `BUGS.md`, `TESTING_GUIDE.md`, `ARTIST_TESTING_GUIDE.md`, `ASSET_NAMING_CONVENTION.md`, design_docs/*.html, and `.claude/skills/*.md` are **out of scope for this cleanup**. They are descriptive prose ("routes" the user-facing word), not code symbols. Touching them is doc maintenance, not refactor.

---

## 2. Canonical-name decisions

| # | Pair | Canonical | One-line justification |
|---|---|---|---|
| 1 | `routes` vs `connections` | **`connections`** | "Route" is reserved for OpenTTD-grade route+schedule semantics arriving in Phase 10. The current data structure is a static directed graph edge — that is a *connection*. |
| 2 | `route_paths` vs `connection_paths` | **`connection_paths`** | Follows pair 1. |
| 3 | `_next_route_id` vs `_next_connection_id` | **`_next_connection_id`** | Follows pair 1. The ID-strings themselves are already `"conn_%d"` (logistics_manager.gd:222), so the counter name aligning is consistency with the wire format. |
| 4 | `pickup_amount` vs `vehicle_capacity` | **`vehicle_capacity`** | The field semantically describes truck capacity, not an action. "Pickup amount" is what *happens* using the capacity. Skill doc (`godot-gdscript-conventions/SKILL.md:141`) names this alias explicitly as the example. |
| 5 | `create_route()` vs `create_connection()` | **`create_connection()`** | Follows pair 1. Body is two lines forwarding to the canonical; delete the wrapper. |
| 6 | `remove_route()` vs `remove_connection()` | **`remove_connection()`** | Follows pair 1. |
| 7 | `get_route()` vs `get_connection()` | **`get_connection()`** | Follows pair 1. |
| 8 | `set_route_active()` vs `set_connection_active()` | **`set_connection_active()`** | Follows pair 1. |
| 9 | `toggle_route_active()` vs `toggle_connection_active()` | **`toggle_connection_active()`** | Follows pair 1. |
| 10 | `get_routes_from_facility()` vs `get_connections_from_facility()` | **`get_connections_from_facility()`** | Follows pair 1. |
| 11 | `get_routes_to_facility()` vs `get_connections_to_facility()` | **`get_connections_to_facility()`** | Follows pair 1. |
| 12 | `get_all_routes()` vs `get_all_connections()` | **`get_all_connections()`** | Follows pair 1. |
| 13 | `get_route_count()` vs `get_connection_count()` | **`get_connection_count()`** | Follows pair 1. |
| 14 | vehicle `route_id` key vs `connection_id` key | **`connection_id`** | Follows pair 1. The vehicle dict at logistics_manager.gd:388 currently writes both; after this cleanup it writes only `connection_id`. |
| 15 | `signal route_created` vs `signal connection_created` | **`connection_created`** | The emit-and-emit-again pattern (logistics_manager.gd:244–245) doubles signal traffic for zero benefit; canonical signal exists already. |
| 16 | `signal route_removed` vs `signal connection_removed` | **`connection_removed`** | Follows pair 15. |
| 17 | `signal route_updated` vs `signal connection_updated` | **`connection_updated`** | Follows pair 15. |
| 18 | save key `routes` vs `connections` | **`connections`** (write); read both | Save-format reads stay tolerant per §3 below. |
| 19 | save key `route_paths` vs `connection_paths` | **`connection_paths`** (write); read both | Same. |
| 20 | save key `next_route_id` vs `next_connection_id` | **`next_connection_id`** (write); read both | Same. |
| 21 | save key vehicle.`route_id` vs vehicle.`connection_id` | **`connection_id`** (write); read both | Same. |

---

## 3. Save compat decision: migrate-on-load for this step

**Recommendation: read either old or new key; write canonical only.** Do not bump the save version. Do not write old keys.

**Why migrate-on-load and not clean break:**
- The save schema bump to v3 is step 2 of the refactor ordering. Bumping the version *here* would force a v2 schema definition for a refactor that adds zero semantic shape — wasted version-space.
- Any save file in `user://saves/` right now was written by code that emits *both* old and new keys (save_manager.gd:355–357 writes `next_route_id` + `routes` + `route_paths` alongside the canonical ones). So existing saves are already compatible with either-key reads.
- A clean break here would refuse to load any save written before some recent commit. The cost of one extra `data.get(canonical, data.get(legacy, default))` per key is trivially cheap.

**Why writes go to canonical only:**
- The alias-creep rule (skill doc:10) is specifically about *silent absorption*. As long as writes converge on canonical and reads tolerate legacy, the schema is well-defined: legacy keys are explicitly an input-only migration, not a forever-aliased shape.
- Step 2 (v3 bump) will then **delete the read-side fallback** as part of the migration. The TODOs below mark exactly where.

**Open question that this resolves in passing:** the technical-architecture doc §5 says "skip v2." This cleanup does not introduce v2; it keeps v1 as the on-disk version while collapsing the in-memory shape. v3 is still the next bump.

---

## 4. Rename steps — file by file, ordered

Total: ~8 file edits + 1 optional file-rename. One commit if the diff stays under 400 lines; otherwise split between §4.1–4.3 (logistics + event_bus + save_manager — the "manager" half) and §4.4–4.7 (UI + renderers — the "consumer" half) with the manager half landing first. The wrapper deletions in §4.1 break callers immediately, so when split, the second commit must follow within the same PR.

### 4.1 `systems/logistics_manager.gd` (declaration site)

**Order matters: delete the alias getters/setters/wrappers, then fix in-file own-usages.**

Edits:
1. **Delete lines 53–55** (alias `var routes`).
2. **Delete lines 62–64** (alias `var route_paths`).
3. **Delete lines 68–70** (alias `var _next_route_id`).
4. **Delete lines 79–81** (alias `var pickup_amount`).
5. **Delete lines 188–191** (`create_route` wrapper).
6. **Delete lines 253–255** (`remove_route` wrapper).
7. **Delete lines 288–290** (`get_route` wrapper).
8. **Delete lines 298–300** (`set_route_active` wrapper).
9. **Delete lines 316–318** (`toggle_route_active` wrapper).
10. **Delete lines 334–336** (`get_routes_from_facility` wrapper).
11. **Delete lines 348–350** (`get_routes_to_facility` wrapper).
12. **Delete lines 659–661** (`get_all_routes` wrapper).
13. **Delete lines 683–685** (`get_route_count` wrapper).
14. **Line 51 comment**: delete "(Also accessible as 'routes' for backward compatibility)" — comment now lies.
15. **Lines 178, 268, 366, 426, 647** — replace `vehicle.get("connection_id", vehicle.get("route_id", ""))` with `vehicle.get("connection_id", "")` (the inner fallback chain dies; `connection_id` is now always written).
16. **Line 388** — vehicle dict creation. Delete the `"route_id": connection_id,  # Alias for backward compatibility` line.
17. **Lines 245, 283, 312, 330, 641** — delete the `EventBus.route_*.emit(...)  # Backward compatibility` lines.
18. **Line 403** — vehicle emit `EventBus.vehicle_spawned.emit(vehicle)  # Alias for visualization`. **KEEP this one.** `vehicle_spawned` is a *legitimate signal alias* used by visual layers (vehicle_renderer.gd:17 listens to spawned, not created). It is not part of the route↔connection alias-creep pattern. *Out of scope.* (Could be cleaned in a separate pass; do not lump it in here.)

**Done when:** `logistics_manager.gd` has zero references to `route`/`routes`/`pickup_amount`. The file is ~50 lines shorter.

**Depends on:** nothing within step 0.5.

### 4.2 `core/event_bus.gd` (signal declarations)

Edits:
1. **Delete lines 84–91** (the three `route_created`/`route_removed`/`route_updated` signal blocks including their `## Emitted when a route is ... (alias for ...)` comments).

**Done when:** EventBus has no signal whose name starts with `route_`. Grep `signal route_` returns zero hits.

**Depends on:** §4.1 (so emit sites are gone before declarations vanish). Strictly necessary — if §4.2 lands first, every emit in logistics_manager.gd is a parse error.

### 4.3 `core/save_manager.gd` (gather + restore)

**Writes drop the old keys; reads keep tolerating either.**

Edits:
1. **Line 306 comment**: change "Save all connections (formerly routes)" → "Save all connections".
2. **Lines 336** — vehicle gather: replace `vehicle.get("connection_id", vehicle.get("route_id", ""))` with `vehicle.get("connection_id", "")`.
3. **Lines 348–358** — `_gather_logistics_data()` return dict:
   - Keep `next_connection_id`, `connections`, `vehicles`, `connection_paths`.
   - **Delete** `"next_route_id": LogisticsManager._next_connection_id,`
   - **Delete** `"routes": connections_data,`
   - **Delete** `"route_paths": connection_paths_data`
4. **Line 609** — restore: **keep** the tolerant read `data.get("next_connection_id", data.get("next_route_id", 1))`. Add comment `# TODO(step-2 v3 bump): drop the next_route_id fallback once schema bumps to v3.`
5. **Line 613** — same: keep `data.get("connection_paths", data.get("route_paths", {}))` with TODO.
6. **Line 622** — same: keep `data.get("connections", data.get("routes", {}))` with TODO.
7. **Line 652** — vehicle restore: keep `vehicle_data.get("connection_id", vehicle_data.get("route_id", ""))` with TODO.
8. **Line 657** — vehicle dict reconstruction: delete the `"route_id": connection_id,  # Backward compatibility` line.
9. **Line 639** — delete `EventBus.route_created.emit(connection)  # Backward compatibility`.

**Done when:** `_gather_logistics_data()` returns a dict with **only canonical keys**. `_restore_logistics_data()` still loads old saves because reads are tolerant. Every tolerant read carries a `TODO(step-2 v3 bump)` comment.

**Depends on:** §4.2 (the `EventBus.route_created.emit` on line 639 must die before EventBus drops the signal — actually §4.3 needs to land *with or before* §4.2 for this one line; safer order is §4.1 → §4.3 → §4.2).

### 4.4 `scenes/world_map/world_map_ui.gd` (routes panel UI)

The "routes panel" is end-user-facing UI labelled "Create Route", "No routes created yet", etc. **The user-facing word "route" is fine** — it describes the gameplay concept of "a flow of goods between two facilities" which is what players think. The cleanup is about *code symbols*, not user labels.

Edits to **rename code symbols only**:
1. **:65–67** — change `EventBus.route_created` → `EventBus.connection_created`, `EventBus.route_removed` → `EventBus.connection_removed`, `EventBus.route_updated` → `EventBus.connection_updated`. Keep the handler names (`_on_route_changed`, `_on_route_removed`) **or** rename them to `_on_connection_changed`, `_on_connection_removed`. Recommend renaming for symmetry; it is a private callback so no fan-out.
2. **:539** — `LogisticsManager.get_all_routes()` → `LogisticsManager.get_all_connections()`.
3. **:615** — `LogisticsManager.toggle_route_active(route_id)` → `LogisticsManager.toggle_connection_active(connection_id)`.
4. **:621** — `LogisticsManager.remove_route(route_id)` → `LogisticsManager.remove_connection(connection_id)`.
5. **Local var renames** for `route` / `route_id` / `routes` inside the panel functions — straightforward `replace_all` per function. The button text strings ("No routes created yet.", "Delete Route", "Create Route", etc.) **stay** — user-facing labels.

**Done when:** every `LogisticsManager.*` call uses the canonical name; every `EventBus.route_*` reference is gone; local code uses `connection_id` / `connection` consistently. User-facing strings unchanged.

**Depends on:** §4.1 + §4.2 (the symbols this file calls into must exist by their canonical names).

### 4.5 `scenes/world_map/route_renderer.gd` — keep filename, rename internals

**File-rename decision:** **Keep the filename `route_renderer.gd` for this step.** The technical-architecture doc §6 explicitly references this file by name when discussing irrigation overlay reuse (line 427). Renaming requires updating `world_map.tscn:7` *and* the architecture doc. A file rename is fan-out beyond the alias-cleanup scope. Mark TODO for a separate file-rename pass during Phase 10's catchment work — that's when the visual layer is restructured anyway.

Edits (symbol-level only):
1. **:13–14** — `EventBus.route_created` → `connection_created`, `EventBus.route_removed` → `connection_removed`.
2. **:31–32** — `LogisticsManager.routes` → `LogisticsManager.connections` (both lines).
3. **Function name renames** (private — no fan-out):
   - `_on_route_created` → `_on_connection_created`
   - `_on_route_removed` → `_on_connection_removed`
   - `_create_route_visual` → `_create_connection_visual`
   - `_add_route_arrows` → `_add_connection_arrows`
   - `_redraw_all_routes` → `_redraw_all_connections`
4. **Local vars** `route_id`, `route` → `connection_id`, `connection`.
5. **Node-name strings** (:56, :83) — `"route_line_%s"` → `"connection_line_%s"`; `"route_arrow_%s_%d"` → `"connection_arrow_%s_%d"`. **This is the riskiest rename** — see §6.4 risk note. If any other file does string-matches on `"route_line_"` or `"route_arrow_"` to find/remove these nodes, the rename breaks them silently. **Verified via grep: no other file does this string-match**, so the rename is safe. But the implementer must re-verify with `Grep "route_line_\\|route_arrow_"` before changing the strings.
6. **Doc comment :3** — change "Draws route lines between facilities" → "Draws connection lines between facilities".
7. **:129 print** — `"Route visual created: %s"` → `"Connection visual created: %s"`. (Debug output; user-invisible.)
8. **Top-of-file TODO** — add `# TODO(Phase 10 catchment work): rename file route_renderer.gd → connection_renderer.gd as part of visual-layer restructure.`

**Done when:** the file has no `route` symbol or local var; only the filename and the irrigation-overlay-anticipating comment in the architecture doc reference it.

**Depends on:** §4.1, §4.2.

### 4.6 `scenes/world_map/vehicle_renderer.gd`

Edits:
1. **:83 comment** — "Draw above routes and facilities" → "Draw above connections and facilities". (Optional; comment is descriptive of z-order intent.)
2. **:104** — `var route_id = vehicle.get("route_id", "")` → `var connection_id = vehicle.get("connection_id", "")`.
3. **:109, :114, :122** — pass `connection_id` to helpers.
4. **:127, :143** — rename parameter `route_id: String` → `connection_id: String` on `_position_at_facility()` and `_position_traveling()`.
5. **:129** — `LogisticsManager.routes.get(route_id, {})` → `LogisticsManager.connections.get(connection_id, {})`. Rename local var `route` → `connection`.

**Done when:** zero `route` references in the file.

**Depends on:** §4.1.

### 4.7 `scenes/world_map/world_map.gd`

Edits (only one call site, three lines):
1. **:883** — `LogisticsManager.create_route(...)` → `LogisticsManager.create_connection(...)`. Local var `route_id` → `connection_id`.
2. **:885** — `if not route_id.is_empty():` → `if not connection_id.is_empty():`.
3. **:886** — `print("Route created: %s" % route_id)` → `print("Connection created: %s" % connection_id)`.

**Note:** `world_map.gd` has internal "route mode" state and `_cancel_route_mode()` — those are gameplay-concept names (the placement *mode* of drawing a route). Step 1's plan suggested leaving those alone; same answer here. "Route mode" is a UI state, not a code-level alias. Out of scope.

**Done when:** the three line-changes land; `_cancel_route_mode` and surrounding mode-state code unchanged.

**Depends on:** §4.1.

---

## 5. EventBus signal-rename fan-out (the load-bearing part of signal renames)

Signal renames have fan-out via `.connect()` callsites. Inventory:

| File | Line | Signal | Action |
|---|---|---|---|
| `scenes/world_map/world_map_ui.gd` | 65 | `EventBus.route_created.connect(_on_route_changed)` | Rename signal in §4.4 |
| `scenes/world_map/world_map_ui.gd` | 66 | `EventBus.route_removed.connect(_on_route_removed)` | Rename signal in §4.4 |
| `scenes/world_map/world_map_ui.gd` | 67 | `EventBus.route_updated.connect(_on_route_changed)` | Rename signal in §4.4 |
| `scenes/world_map/route_renderer.gd` | 13 | `EventBus.route_created.connect(_on_route_created)` | Rename signal in §4.5 |
| `scenes/world_map/route_renderer.gd` | 14 | `EventBus.route_removed.connect(_on_route_removed)` | Rename signal in §4.5 |
| `systems/logistics_manager.gd` | 245, 283, 312, 330, 641 | `EventBus.route_*.emit(...)` | Delete in §4.1 |
| `core/save_manager.gd` | 639 | `EventBus.route_created.emit(...)` | Delete in §4.3 |

**Total subscribers: 2 files (world_map_ui.gd, route_renderer.gd), 5 connect lines.** Already covered by §4.4 and §4.5 above. No other subscribers exist — verified via the full-repo grep for `EventBus.route_`.

**Verification step:** After all edits, run `Grep -n "EventBus\\.route_"` across the repo. Expected hits: zero. Any hit is a missed callsite.

---

## 6. Smoke test

### 6.1 Pre-cleanup baseline save

Before any edits, the implementer must:
1. Launch the current game, place at least: 1 Barley Field, 1 Grain Mill, 1 Brewery. Build a road between them.
2. Click "Create Route", connect Field → Mill, Mill → Brewery.
3. Watch one full delivery cycle (a vehicle spawns, picks up, delivers, despawns).
4. F5 quick save to slot `alias_cleanup_pre`.
5. Verify the save file (`user://saves/alias_cleanup_pre.save`) contains **both** `"routes"` *and* `"connections"` keys, **both** `"route_paths"` *and* `"connection_paths"`, **both** `"next_route_id"` *and* `"next_connection_id"`. This is the current dual-write behavior.
6. Verify vehicles in that save file have **both** `"route_id"` and `"connection_id"`.

### 6.2 Post-cleanup verification — load old save

After all edits:
1. Launch the game. Use the Load Game dialog → load slot `alias_cleanup_pre`.
2. Confirm: all facilities reappear; both connections reappear with their visuals; vehicle auto-dispatch resumes.
3. Watch one delivery cycle complete — same goods movement as before.
4. Console: `print(LogisticsManager.connections.size())` — expect 2. `print(LogisticsManager.connection_paths.size())` — expect 2. `print(LogisticsManager.vehicles.size())` — depends on dispatch state.
5. Confirm `LogisticsManager.routes` is now a **parse error or undefined property** (the alias is gone). The Godot debugger should reject the expression.

### 6.3 Post-cleanup verification — write new save

1. With the loaded state from §6.2, F5 quick save to slot `alias_cleanup_post`.
2. Open `user://saves/alias_cleanup_post.save` in a text editor.
3. Grep for `"routes"`, `"route_paths"`, `"next_route_id"`, `"route_id"` (the JSON keys — with the quote characters).
4. **Expected: zero hits.** The new save contains only canonical keys.
5. Grep for `"connections"`, `"connection_paths"`, `"next_connection_id"`, `"connection_id"`. Expected: present.

### 6.4 Visual regression spot-check

1. With connections drawn on the world map, briefly tap "Demolish" mode and remove one connection's destination facility. Verify the connection line/arrows disappear (handled by `_on_connection_removed` → child queue_free loop in route_renderer.gd:135).
2. Place a new connection. Verify a new Line2D plus two arrow Polygon2Ds appear under the route_renderer node, named `connection_line_conn_*` and `connection_arrow_conn_*_*` (proof the node-name-string rename from §4.5 step 5 landed).

**Done when:** all six §6 checks pass. The game behaves identically to pre-cleanup; only string keys in saves and signal/symbol names in code changed.

---

## 7. Non-goals (explicit)

| Out of scope | Why | Lands in |
|---|---|---|
| `corp_id` field on entities | Step 1 owns ownership-layer addition | Step 1 |
| Save schema version bump to v3 | Step 2 owns the v3 schema + migration | Step 2 |
| `submit_action()` skeleton | Step 3 owns the action pipe | Step 3 |
| Delete the read-side legacy-key fallback in `save_manager.gd` | Step 2 deletes it as part of v3 migration | Step 2 |
| Rename file `route_renderer.gd` → `connection_renderer.gd` | Fan-out hits `world_map.tscn` and architecture doc; bundled with Phase 10 visual-layer work | Phase 10 |
| Rename "route mode" UI state in `world_map.gd` | "Route mode" is a gameplay concept name, not a code-level alias | Never (the word is fine) |
| Rename user-facing strings ("Create Route", "No routes created yet") | Gameplay vocabulary, not code symbols | Never |
| Rename `EventBus.vehicle_spawned` alias of `vehicle_created` | Not part of route↔connection alias-creep; separate (small) cleanup | Separate pass, post-step 0.5 |
| Documentation cleanup in `CLAUDE.md`, `TESTING.md`, etc. | Descriptive prose, not load-bearing | Continuous; not blocking |

---

## 8. Files touched (final inventory)

```
core/event_bus.gd                          (-8 lines)   delete 3 alias signals + comments
core/save_manager.gd                       (-7 lines, +4 TODOs) drop dual-write keys + vehicle.route_id; keep read fallback w/ TODO
systems/logistics_manager.gd               (-50 lines)  delete 13 wrapper functions + 4 alias properties + 5 dual-emit lines + 1 dict alias key
scenes/world_map/world_map.gd              (3 lines edited) rename local var + one call
scenes/world_map/world_map_ui.gd           (~10 lines edited) rename signal connects + 3 LogisticsManager calls
scenes/world_map/route_renderer.gd         (~25 lines edited) full symbol rename; filename kept
scenes/world_map/vehicle_renderer.gd       (~6 lines edited) one local var + one .get on routes dict
```

**Estimated diff: ~-80 net lines across 7 files.** Single PR, single commit if it fits cleanly.

**Files explicitly NOT touched:**
- `scenes/ui/logistics_network_panel.gd` — already canonical
- `scenes/ui/network_view.gd` — already canonical
- `scenes/world_map/world_map.tscn` — file path stays
- `data/*.json` — no schema changes
- `*.md` documentation — descriptive prose, separate concern
- `design_docs/*.html` — same
- `.claude/skills/*.md` — same; the skill doc already names alias-creep correctly

---

## 9. Open questions

None surfaced. The migrate-on-load vs clean-break decision (§3) is the only one this plan had to resolve, and it was resolvable on the criteria already pinned in the architecture doc + skill rules.

One advisory note for the reviewer: **after step 0.5 lands, do a quick visual diff of the resulting saves against an older save.** If any save in `user://saves/` was written before the dual-write behavior in save_manager.gd:355–357 was added (i.e., a save older than that commit and containing only legacy keys), it will still load — that's the entire point of the migrate-on-load decision. If a save is corrupt or missing logistics state entirely, that's a pre-existing bug, not a regression from this cleanup.
