# Known Bugs & Issues — Alcohol Empire Tycoon (PRE-PIVOT SNAPSHOT)

> **⚠️ STALE — Last updated 2025-10-16, before Phase 6/7/4F-H work AND before the May 2026 design pivot to Drinkustry.**
>
> Many "won't fix" items below are now resolved (save/load, static pricing, isometric grid math, facility upgrades) and many "high priority" items are no longer phased the same way. The "Won't Fix / By Design" section reflects the pre-pivot single-player frame.
>
> See `design_docs/` for current direction. Treat this file as a historical bug log, not as a current backlog.

---

# 🎮 Post-Pivot Playtest Findings

> Reactivated **2026-06-04** by Ambrus (artist) for ongoing post-pivot playtest notes.
> Pre-pivot entries (below this section) remain as historical reference; new findings live here.
> Add a new dated section each playtest session — latest on top — and reuse the entry template at the bottom of this file (`🐛 Bug Reporting Template`).

## 🗓 2026-06-04 — Phase 8 step 3c smoke test session

**Tested on branch:** `feature/phase8-step3c-ui-rewire` (action-pipe UI rewire)
**Tester:** Ambrus
**Result:** Action pipe verified — no regressions on the rewired flows (place / demolish / route create / route pause / route delete / machine place / machine connect / machine delete / research / set crop). Findings below are **pre-existing** issues uncovered during the smoke test, not caused by step 3c.

### 🚨 Critical
- [ ] **Brewery interior machines connect but nothing transports** — Placed mash tun + fermentation vat inside brewery interior, connected them via the connect tool, no product moved between them.
  - **Impact:** Blocks the slice-1 ale chain at the tactical (factory-interior) layer. Players can build the chain but it doesn't actually produce anything.
  - **Reproduce:** Enter brewery interior. Place an Input Hopper, Mash Tun, Fermentation Vat, Output Depot. Connect them in order. Observe (no movement).
  - **Fix:** Investigate machine-machine transfer logic and machine IO config. May be missing recipes (`data/recipes.json` is empty per CLAUDE.md) or broken transfer cycle.
  - **Phase:** Pre-Phase 10 (needed before slice-1 chain is validatable)
  - **File:** `systems/factory_manager.gd`, `systems/production_manager.gd`, `data/machines.json`, `data/recipes.json`

### ⚠️ High Priority
- [ ] **Money death-spiral — no recovery once broke** — When the player runs out of money, the game effectively ends. No income source bootstraps recovery (Market Outlet requires already having a production chain).
  - **Impact:** Soft game-over with no exit; player must reset to main menu.
  - **Fix:** Income floor, starting loans, bankruptcy mechanic, or guaranteed bootstrap revenue. Design decision needed.
  - **Phase:** Phase 10 (economy / Business-corp work)
  - **File:** `systems/economy_manager.gd`

- [ ] **Cannot remove road tiles with the demolish tool** — Demolish mode targets facilities and machines but does not detect road tiles. `ACTION_REMOVE_ROAD` exists in the action pipe but has no UI driver yet (plan §6 noted this gap).
  - **Impact:** Players can't undo road placement mistakes; the road network becomes permanent terrain.
  - **Fix:** In demolish-mode click handler, detect road tile at the clicked position and submit `ACTION_REMOVE_ROAD`.
  - **Phase:** Pre-Phase 10
  - **File:** `scenes/world_map/world_map.gd` (demolish-mode click handler)

### 📋 Medium Priority
- [ ] **Production overview panel: nodes are unlabeled colored squares with no input/output hints** — User can't tell which node represents which building, and any node visually accepts any input, implying universal compatibility.
  - **Impact:** Production overview panel is unusable as a planning tool.
  - **Fix:** Show building name on each node (matching world-map labels). Show accepted inputs / outputs as tags or tooltip. Color-code connectors by product type.
  - **Phase:** Phase 9 (art look-dev) or sooner if blocking
  - **File:** `scenes/ui/network_view.gd`, `scenes/ui/logistics_network_panel.gd`

- [ ] **Demolish brush 2-tile preview rotates with cursor movement** — While demolish mode is active, the 2-tile preview rotates as the cursor moves around the map, instead of staying grid-aligned.
  - **Impact:** Confusing visual feedback; misleads players about which tiles will be demolished.
  - **Reproduce:** Activate demolish mode, move cursor in circles. Watch preview orientation.
  - **Fix:** Lock preview orientation to grid; remove cursor-direction-based rotation.
  - **Phase:** Phase 7B-leftover polish
  - **File:** `scenes/world_map/world_map.gd` (demolish preview rendering)

- [ ] **Build-preview hover renders behind farm tiles** — In placement mode, the hover ghost renders below already-placed farm-tile sprites, hiding where the new building will land.
  - **Impact:** Player can't see exactly where a building will be placed when hovering over farms.
  - **Fix:** Bump placement preview `z_index` above farm-tile rendering layer.
  - **Phase:** Pre-Phase 10
  - **File:** `scenes/world_map/world_map.gd` (placement preview rendering)

- [ ] **Cannot build on farm-field tiles** — Engine rejects placing buildings on land occupied by farm fields.
  - **Impact:** Forces players to plan farm placement separately from production buildings; reduces layout flexibility. User (artist) feels this constraint is unnecessary.
  - **Fix:** Design decision. Either allow placement (auto-demolish field with refund) or keep constraint with clearer UX. Worth discussing with Gergely.
  - **Phase:** Design review needed
  - **File:** `systems/world_manager.gd` (`can_place_facility` / `can_place_field_for_farmhouse`)

### 🔧 Low Priority / Design Open Questions
- [ ] **Demolish refund UX feels off** — Currently a flat 50% refund any time, including immediately after placement. User suggests: full refund within a short undo window OR no refund once the building has been used.
  - **Impact:** Either accidental placement is unforgiving (current — only 50% back), or refund-cycling could be exploited if too generous.
  - **Fix:** Design decision. Options: (a) time-windowed full-refund undo, (b) full-refund-when-fresh-and-unused, (c) keep current as baseline.
  - **Phase:** Phase 10 (economy tuning)
  - **File:** `core/game_manager.gd` (`_action_demolish_facility`, `_action_demolish_machine` handlers)

- [ ] **Machine connection deletion clicks endpoints, not the line** — Player enters delete-connection mode and clicks both machines to delete a connection. User suggests clicking the connection line directly would be more intuitive.
  - **Note:** Likely becomes moot when the conveyor/pipe system arrives — under that system, conveyors carry solids and pipes carry liquids, and the player would interact with conveyor/pipe segments directly (place, delete, plan).
  - **Phase:** Defer to Industrial-corp signature work / conveyor system design
  - **File:** `scenes/factory_interior/factory_interior.gd`

### ✅ Investigated this session, NOT a bug
- ✅ **Malt house → brewery logistics route can't be created** — Verified: data is correct (`grain_mill` outputs `malt`, `brewery` accepts `malt`). Rejection comes from `LogisticsManager.can_create_connection` because there is **no road path between the two facilities** — routes require a connecting road (auto-connect within 2 tiles). Fix is to build roads connecting source and destination first. A "No road connection!" notification is emitted via EventBus but may be easy to miss. **Latent UX issue logged separately:** consider stronger feedback for route-creation rejections (modal, persistent banner, or highlight road-gap on map).
- ✅ **Road drag-place** — Reported initially as broken; confirmed working on retest. No action.

---

## 🚨 Critical (Fix ASAP)
*Bugs that prevent development or break core gameplay*

- [ ] None currently

---

## ⚠️ High Priority (Fix This Phase)
*Important bugs that affect gameplay but don't block development*

### Isometric Grid System
- [x] ~~**Temporary 45° rotation**~~ — RESOLVED. True `cart_to_iso()` / `iso_to_cart()` math now in `systems/world_manager.gd`. CLAUDE.md "Critical: Isometric Coordinate System" section is the current source of truth.

### Mouse Input
- [x] ~~**Mouse position offset in rotated view**~~ — RESOLVED with the proper isometric conversion above. (Note: factory-interior mouse picking has its own gotcha — use `get_viewport().get_mouse_position()` + canvas transform inverse, see CLAUDE.md gotcha #9.)

---

## 📋 Medium Priority (Fix During Polish Phase)
*Issues that affect user experience but don't break functionality*

### Visual/UI Issues
- [ ] **Facility labels overlap** - When placing multiple facilities close together, their name labels clip through each other
  - **Impact:** Visual clutter, hard to read
  - **Fix:** Add label positioning logic or billboard sprites
  - **Phase:** Phase 7B (UI/UX Improvements)

- [ ] **Grid lines visibility** - Grid lines at 2.0 width and 0.8 opacity may be too visible/distracting
  - **Impact:** Visual polish
  - **Fix:** Adjust grid_color and grid_line_width in grid_renderer.gd, possibly add toggle
  - **Phase:** Phase 7C (Visual Polish)

- [ ] **Placement preview rotation** - Preview ghosts don't perfectly match final placement in isometric view
  - **Impact:** Slight mismatch between preview and actual placement
  - **Fix:** Update placement preview to use same coordinate conversion as actual placement
  - **Phase:** When fixing proper isometric grid

### Factory Interior
- [ ] **Machine labels missing** - Machines don't show their type/name when placed
  - **Impact:** Hard to identify machines at a glance
  - **Fix:** Add Label nodes to machine nodes (similar to facilities)
  - **Phase:** Phase 7B (UI/UX Improvements)

- [ ] **Connection lines overlap** - Multiple connection lines between machines can overlap and obscure each other
  - **Impact:** Visual clarity in complex factory layouts
  - **Fix:** Add line offset logic or connection bundling
  - **Phase:** Phase 7B (UI/UX Improvements)

### World Map
- [ ] **Camera zoom limits** - Camera can zoom too far in/out, causing visual issues
  - **Impact:** Can lose orientation or see rendering artifacts
  - **Fix:** Add min/max zoom constraints to camera_controller.gd
  - **Phase:** Phase 7B (UI/UX Improvements)

---

## 🔧 Low Priority (Fix If Time)
*Nice-to-have fixes that don't significantly impact gameplay*

### Performance
- [ ] **Untested at scale** - Not tested with 50+ facilities and 100+ vehicles
  - **Impact:** Unknown performance characteristics at full scale
  - **Fix:** Performance profiling and optimization pass
  - **Phase:** Phase 7 (Polish) or when performance issues arise

### Visual Polish
- [ ] **Route lines are straight** - Routes between facilities use straight lines instead of curves
  - **Impact:** Visual aesthetic
  - **Fix:** Implement bezier curves for route rendering
  - **Phase:** Phase 7C (Visual Polish)

- [ ] **No production animations** - Facilities don't show visual feedback when producing
  - **Impact:** Game feels static
  - **Fix:** Add particle effects, smoke stacks, activity indicators
  - **Phase:** Phase 7C (Visual Polish)

- [ ] **Vehicle sprites are placeholders** - Yellow rectangles instead of truck sprites
  - **Impact:** Visual polish
  - **Fix:** Replace with proper vehicle sprites when artist provides them
  - **Phase:** Phase 7C (Visual Polish) / Ongoing

### UX Improvements
- [ ] **No facility tooltips** - Hovering over facilities doesn't show information
  - **Impact:** Hard to see facility stats without clicking
  - **Fix:** Add tooltip system with facility info on hover
  - **Phase:** Phase 7B (UI/UX Improvements)

- [ ] **No route management UI** - Can't pause, delete, or view stats for routes
  - **Impact:** Limited logistics control
  - **Fix:** Add route list panel with controls
  - **Phase:** Phase 7B (UI/UX Improvements)

---

## ✅ Won't Fix (By Design / Planned Features)
*Issues that are intentional limitations or planned features for later phases*

### Incomplete Systems (pre-pivot list — many now obsolete or resolved)
- ~~**No save/load functionality**~~ — RESOLVED Phase 7A. Multi-slot save/load, F5/F9 hotkeys, auto-save shipped. *(Schema gets bumped to v3 in new Phase 8 for per-corp partitions; see technical architecture doc.)*
- ~~**Static product pricing**~~ — RESOLVED Phase 6A (`systems/market_manager.gd`). *(Reframed in pivot as Business-corp-owned spatial demand in new Phase 10.)*
- ~~**No facility upgrades**~~ — RESOLVED Phase 6B/6C. 40-tech research tree shipped. *(Refactored to two-layer per-corp + shared in new Phase 8.)*
- **No tutorial/onboarding** — still unresolved; deferred to post-Phase 12 in new roadmap.
- **No multi-input recipes** — `data/recipes.json` still empty. The lager chain (Malt + Hops + Water) requires this; lands in new Phase 10 with Industrial corp signature work.
- **No AI competition** — REFRAMED. Pivot is asymmetric **co-op**, not solo-vs-AI. AI failsafe for disconnects (D-16 in design summary) is the only AI-player code planned.

### Design Decisions
- **Manual machine connections** - Not adjacency-based automatic connections
  - **Status:** Intentional design choice for player control
  - **Reasoning:** Gives players precise control over production flow

- **Per-machine inventory** - Machines don't share facility inventory pool
  - **Status:** Intentional design choice
  - **Reasoning:** Allows buffer management and complex logistics

- **Factory interiors are top-down** - Not isometric like world map
  - **Status:** Intentional design choice
  - **Reasoning:** Easier machine placement and clearer spatial understanding

---

## 🐛 Bug Reporting Template

When discovering new bugs, add them using this template:

```markdown
- [ ] **Bug Title** - Brief description
  - **Impact:** How it affects gameplay/development
  - **Reproduce:** Steps to reproduce (if known)
  - **Fix:** Proposed solution or investigation needed
  - **Phase:** When to fix (immediate, next phase, polish)
  - **File:** Relevant source files
```

---

## 🔍 Testing Checklist

Use this to verify major systems after changes:

### Core Systems
- [ ] Facility placement (1×1, 2×2, 3×3 tiles)
- [ ] Facility removal
- [ ] Route creation between facilities
- [ ] Vehicle spawning and movement
- [ ] Money deduction on purchases
- [ ] Production cycles (barley → malt → ale)
- [ ] Auto-sell on finished products

### Factory Interior
- [ ] Enter factory (double-click / shift+click)
- [ ] Exit factory (Back button)
- [ ] Machine placement
- [ ] Machine connection (Connect Machines button)
- [ ] Machine production (with inputs)
- [ ] Input Hopper pulls from facility inventory
- [ ] Output Depot sends to facility inventory
- [ ] Market Outlet generates bootstrap income

### Scene Transitions
- [ ] World map → Factory interior (state persists)
- [ ] Factory interior → World map (facilities still visible)
- [ ] Multiple factories maintain independent state

### Edge Cases
- [ ] Place facility at grid boundary (0,0) and (49,49)
- [ ] Attempt to place overlapping facilities (should fail)
- [ ] Create route to/from same facility (should fail)
- [ ] Place machine without enough money
- [ ] Produce without input materials (should wait)

---

## 📊 Bug Statistics

**Total Bugs:** 12
**Critical:** 0
**High Priority:** 2
**Medium Priority:** 7
**Low Priority:** 3
**Won't Fix / By Design:** 8 known limitations

**Resolved This Session:** 2
- ✅ Fixed: Facilities disappear when returning from factory interior
- ✅ Fixed: Multi-tile facility placement offset

---

## 🔄 Recent Fixes (Change Log)

### 2025-10-16
- ✅ **Fixed: Facilities not loading on return from factory interior**
  - Added `_load_existing_facilities()` function in world_map.gd
  - Facilities now restore from WorldManager on scene reload

- ✅ **Fixed: Multi-tile facilities not placing where clicked**
  - Updated facility world_pos calculation to center position
  - Fixed Sprite2D positioning with proper offsets
  - Updated placement preview positioning

### 2025-10-15 (Phase 5)
- ✅ Added sprite rendering system with automatic fallbacks
- ✅ Created 14 product definitions with pricing
- ✅ Added 4 new facilities (7 total)

---

**Note:** This file should be updated whenever bugs are discovered, fixed, or reclassified. Keep the "Bug Statistics" and "Recent Fixes" sections current.
