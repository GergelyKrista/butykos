# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **⚠️ DESIGN PIVOT — READ FIRST**
>
> The project pivoted in May 2026 from a **single-player alcohol tycoon** to **Drinkustry**: a 4-player asymmetric co-op cyberpunk-megacorp tycoon. The pivot is **additive on top of the existing Phase 7B+ codebase** — no rewrite. The architecture, coordinate system, and code conventions in this file are still accurate. The roadmap, "next priorities", phase numbering, and content scope are **not**.
>
> **For forward-looking direction, read `design_docs/` in this order:**
> 1. `2026-04-30_design_summary.html` — strategic pivot, four corps, shared+per-corp tech, Phase 8–12 roadmap
> 2. `2026-05-01_gameplay_corps_production.html` — slice-1 lager chain, 11 starting buildings across corps
> 3. `2026-05-02_per_corp_v1_mechanics.html` — depth-bar rule (brewery interior is the bar)
> 4. `2026-05-07_technical_architecture.html` — engine retrofit: ownership layer, MP architecture, refactor ordering, Phase 8 entry checklist
>
> `DEVELOPMENT_STATUS.md` describes the **pre-pivot** state (Phase 4F/4G/4H + 7B). Treat it as a snapshot of where the code is, not where it's going.

## Project Overview

**Drinkustry** (working title; codebase still named `butykos`) — Godot 4.2 dual-layer tycoon
- **Theme:** Cyberpunk-megacorp (reskin of alcohol-production base; mechanics theme-agnostic)
- **Mode:** 4-player asymmetric co-op (v1). Solo deferred. Networking is the **last** phase, not the first — hot-seat single-machine prototype validates the design first.
- **Four corps:** Agricultural, Industrial, Logistics, Business/Marketing — each with a signature mechanic that must hit the depth bar set by the existing brewery factory interior.
- **Slice-1 chain:** Lager beer only (Malt+Hops+Water → Lager). Spirits, packaging, wine deferred to slice-2+.
- **Dual-layer gameplay:** Strategic isometric world map + tactical orthogonal factory interiors (preserved from pre-pivot codebase).
- **Engine:** Godot 4.2 with GDScript.
- **Code status:** Phase 7B complete + Phase 4F/4G/4H (node-based logistics, farmhouse fields, roads) + research tree + market system. Design pivoted; code starts Phase 8 (consolidate + tech-tree refactor) per the technical architecture doc.

## Running the Project

**Prerequisites:**
- Godot 4.2 or later

**To run:**
1. Open the project in Godot Editor
2. Press F5 or click "Run Project"
3. Main scene: `res://scenes/world_map/world_map.tscn`

**No build step required** - Godot projects run directly in the editor during development.

## Git Workflow

**Branch Strategy:**
- `main` - Production branch (stable releases)
- `dev` - Development branch (permanent, never deleted)
- Feature branches - Merge into `dev` first, then `dev` → `main` when ready

**Workflow:**
1. Create feature branch from `dev`
2. Develop and commit changes
3. Merge feature → `dev`, test
4. Merge `dev` → `main` for production release
5. Delete feature branches after merge

## Architecture Overview

### Singleton Autoload System

The game uses singleton managers (autoloaded in `project.godot`) for global state:

```
core/
├── event_bus.gd         # Signal hub (40+ signals for decoupled communication)
├── game_manager.gd      # Game state, scene transitions, active_factory_id tracking
├── data_manager.gd      # JSON data loading (facilities, machines, products)
└── save_manager.gd      # Save/load system with multiple slots, auto-save, hotkeys

systems/
├── world_manager.gd     # 50×50 isometric grid, facility placement, coordinate conversion
├── economy_manager.gd   # Money tracking, transactions
├── production_manager.gd # Input-based production cycles, inventory, product pricing
├── logistics_manager.gd  # Routes, vehicles, cargo transport
└── factory_manager.gd   # 20×20 factory interiors per facility, machine placement, connections
```

**Access pattern:** All managers are globally accessible:
```gdscript
WorldManager.place_facility(...)
EventBus.facility_placed.emit(facility)
EconomyManager.money
ProductionManager.product_prices["ale"]  # Returns 100
```

### Dual-Layer System

**World Map (Strategic Layer):**
- 50×50 **isometric grid** (64×32 pixel tiles, 2:1 ratio)
- Facility placement with multi-tile support (2×2, 3×3, etc.)
- Route creation for logistics
- Vehicle rendering and animation
- Scene: `scenes/world_map/world_map.tscn`

**Factory Interior (Tactical Layer):**
- 20×20 **orthogonal top-down grid** (64×64 pixel tiles)
- Machine placement within facilities
- Manual connection system (click-to-connect)
- Independent state per facility
- Scene: `scenes/factory_interior/factory_interior.tscn`

**Scene Transition:**
- Double-click or Shift+click facility → Enter interior
- `GameManager.active_factory_id` tracks current factory
- State persists across transitions

### Signal-Based Communication

All system communication goes through `EventBus` to maintain loose coupling:

```gdscript
# Example: Facility placement flow
WorldManager.place_facility(...)
  → EventBus.facility_placed.emit(facility)
  → ProductionManager starts production timers
  → WorldMap creates visual representation
  → FactoryManager creates interior if has_interior flag
```

**Key signals:**
- `facility_placed`, `facility_removed`
- `machine_placed`, `machine_removed`
- `connection_created`, `connection_removed`, `connection_updated`
- `vehicle_spawned`, `vehicle_removed`
- `money_changed`, `production_changed`

### Data-Driven Design

Game content defined in JSON files (`data/`):
- `facilities.json` - 7 facilities (Barley Field, Wheat Farm, Grain Mill, Brewery, Distillery, Packaging Plant, Storage Warehouse)
- `machines.json` - 13 machines (Mash Tun, Fermentation Vat, Bottling Line, Storage Tank, Market Outlet, Input Hopper, Output Depot, etc.)
- `products.json` - 14 products (barley, wheat, malt, mash, fermented_wash, raw_spirit, ale, packaged_ale, whiskey, etc.)
- `recipes.json` - Empty (future expansion for multi-input recipes)

All costs, production times, pricing, and recipes in JSON for easy balancing.

## Critical: Isometric Coordinate System

The world map uses **true isometric mathematics** (not 45° rotation hack):

### Constants (WorldManager)
```gdscript
const TILE_WIDTH = 64   # Isometric tile width
const TILE_HEIGHT = 32  # Isometric tile height (2:1 ratio)
const GRID_SIZE = Vector2i(50, 50)
```

### Coordinate Conversion Functions
```gdscript
# Cartesian (grid) to Isometric (screen)
func cart_to_iso(cart_pos: Vector2) -> Vector2:
    var iso_x = (cart_pos.x - cart_pos.y) * (TILE_WIDTH / 2.0)
    var iso_y = (cart_pos.x + cart_pos.y) * (TILE_HEIGHT / 2.0)
    return Vector2(iso_x, iso_y)

# Isometric (screen) to Cartesian (grid)
func iso_to_cart(iso_pos: Vector2) -> Vector2:
    var cart_x = (iso_pos.x / (TILE_WIDTH / 2.0) + iso_pos.y / (TILE_HEIGHT / 2.0)) / 2.0
    var cart_y = (iso_pos.y / (TILE_HEIGHT / 2.0) - iso_pos.x / (TILE_WIDTH / 2.0)) / 2.0
    return Vector2(cart_x, cart_y)
```

### Key Rules for Isometric Code

1. **Tile Alignment:** Tiles sit *between* grid lines, not *on* them
   - Grid lines at integer coords (0, 1, 2...)
   - Tile centers at half-integer coords (0.5, 1.5, 2.5...)
   - Always add `+ 0.5` offset when positioning tiles

2. **Z-Index Sorting:** Required for proper depth
   ```gdscript
   facility.z_index = grid_pos.y * 100 + grid_pos.x
   ```

3. **Sprite Rendering:** Facilities use Sprite2D with bottom-center alignment, fallback to Polygon2D diamonds
   ```gdscript
   var sprite_path = facility_def.get("visual", {}).get("icon", "")
   if ResourceLoader.exists(sprite_path):
       var sprite = Sprite2D.new()
       sprite.texture = load(sprite_path)
       sprite.centered = false  # Manual positioning for proper isometric alignment

       # Bottom-center alignment: sprite bottom sits at isometric footprint base
       var footprint_height = (size.x + size.y) * TILE_HEIGHT / 2.0
       sprite.position = Vector2(-sprite_width / 2.0, -sprite_height + footprint_height / 2.0)
   else:
       # Fallback to colored diamond polygon
   ```

   **Critical:** Sprites must use bottom-center alignment for proper isometric grid placement.
   Sprites can have extra vertical height for building detail - the engine handles positioning automatically.

4. **Mouse Input:** Use `WorldManager.world_to_grid()` directly (handles isometric conversion)

5. **Factory Interiors:** Stay orthogonal (top-down), use `FactoryManager.INTERIOR_TILE_SIZE = 64`

## Production System Flow

### Complete Production Chains

**Beer Chain:**
```
Barley Field ($500) → Grain Mill ($800) → Brewery ($1500)
→ produces ale → auto-sells for $100/unit
```

**Premium Beer Chain:**
```
Barley Field → Grain Mill → Brewery → Packaging Plant ($1200)
→ produces packaged_ale → auto-sells for $150/unit (+50% premium)
```

**Spirits Foundation:**
```
Wheat Farm ($550) → Grain Mill ($800) → Distillery ($2000)
→ produces raw_spirit → sells for $50/unit
```

### Key Production Rules

- **Intermediate products** (barley, wheat, malt, mash) stay in facility inventory
- **Final products** (ale, packaged_ale, whiskey, vodka) auto-sell immediately
- Production requires inputs (checked via `ProductionManager`)
- Routes transport goods between facilities (`LogisticsManager`)
- Products have category-based pricing in `ProductionManager.product_prices`

### Machine Production (Factory Interiors)

**Manual Connection System:**
- Click "Connect Machines" button
- Click source machine → click destination machine
- Creates visual connection line with arrow
- Machines transfer products through connections every 2 seconds

**Special Machine Types:**
- **Input Hopper** (`is_input_node: true`) - Pulls from facility inventory to machines
- **Output Depot** (`is_output_node: true`) - Sends machine output to facility inventory
- **Market Outlet** (`is_market_outlet: true`) - Sells intermediate products for bootstrap income
- **Storage Tank** (`is_storage_buffer: true`) - Actively transfers to connected machines

**Machine Inventory:**
- Each machine has separate inventory (not shared with facility)
- IO nodes run every 2 seconds (`IO_NODE_CYCLE_TIME: 2.0`)
- Transfer amount: 10 units per cycle (`io_node_transfer_amount: 10`)

## Sprite Asset System

### World Map Facilities (Isometric)
- Location: `assets/sprites/`
- Naming: Match facility ID (e.g., `sprite_facility_malt_house.png`)
- Referenced in `facilities.json` as `visual.icon`
- Automatic fallback to colored diamonds if sprite missing
- **Positioning:** Bottom-center alignment (engine handles automatically)
- **Extra Height:** Sprites can exceed strict isometric footprint for building height

### Factory Interior Machines (Top-Down)
- Location: `assets/machines/`
- Naming: Match machine ID (e.g., `mash_tun.png`)
- Referenced in `machines.json` as `visual.sprite` (note: different field name)
- Automatic fallback to colored rectangles if sprite missing

### Sprite Positioning Details (World Map)
**Critical for proper grid alignment:**
- Sprites use `centered = false` with manual positioning
- Bottom-center of sprite = base of isometric footprint
- Engine calculates: `position = Vector2(-width/2, -height + footprint_height/2)`
- Examples:
  - Malt House (2×2): 128×80px sprite on 128×64px footprint
  - Brewery (3×3): 192×112px sprite on 192×96px footprint

### Artist Workflow
1. Draw sprite with isometric perspective
2. Ensure bottom edge = where building touches ground
3. Add vertical height as needed for building detail
4. Drop PNG file in correct folder (`assets/sprites/` or `assets/machines/`)
5. Match exact filename from JSON
6. Launch game (F5) - sprite appears automatically with correct alignment

See `ASSET_NAMING_CONVENTION.md` for complete sprite specifications.

## Code Style Requirements

**Type Hints:**
```gdscript
func place_facility(facility_type: String, grid_pos: Vector2i) -> String:
    # Always use explicit types for parameters and returns
```

**Coordinate Comments:**
```gdscript
# Convert from cartesian grid space to isometric screen space
var world_pos = cart_to_iso(center_grid_pos)
```

**Separation of Concerns:**
- Isometric logic → `WorldManager` and `scenes/world_map/`
- Orthogonal logic → `FactoryManager` and `scenes/factory_interior/`
- Never mix coordinate systems

## Common Gotchas

1. **Autoload not recognized:** Restart Godot editor (known initialization issue)
2. **Tiles misaligned with grid:** Add 0.5 offset to tile positions
3. **Facilities render in wrong order:** Check Z-index calculation (`y * 100 + x`)
4. **Mouse picking fails:** Ensure using proper isometric conversion
5. **Factory interior broken:** Never apply isometric logic to factory scenes
6. **Sprite not showing:** Check field name - facilities use `icon`, machines use `sprite`
7. **Sprite misaligned with grid:** Ensure using `centered = false` with bottom-center positioning formula (see Sprite Asset System section)
8. **Machine not producing:** Check if it has input materials in its own inventory (not facility inventory)
9. **Machine placement incorrect:** Use `get_viewport().get_mouse_position()` + canvas transform inverse, not `camera.get_global_mouse_position()`
10. **Mode conflicts:** Always cancel conflicting modes before starting new mode (placement, route, demolish, connect)

## Next Development Priorities

> Superseded by the design pivot. The list below is the **current** roadmap; the old `DEVELOPMENT_STATUS.md` plan (vineyard / hop farm / wine / AI competitors) is historical.

**Phase 8 — Consolidate + tech-tree refactor (in progress):**
- ~~Add `corp_id` ownership field to facility/machine/route/vehicle entities~~ — **done** (step 0.5 alias cleanup + step 1 corp_id field, 2026-05-18)
- ~~Save schema v3 with per-corp partitions + migration from existing saves~~ — **done** (step 2, 2026-05-18; `shared.money` for now; per-corp wallets are v3→v4 in a later commit)
- `submit_action(corp_id, action_type, payload)` skeleton in `GameManager` — **next** (step 3)
- Two-layer tech tree: existing 40 nodes migrate to `tier: "corp_internal"` distributed across four corps; add `tier: "shared"` layer for cross-corp research

**Phase 9 — Art look-dev (parallel to mechanic work):**
- Cyberpunk palette + key art for four corps
- Four second-layer visual modes (Agri overlay, Industrial interior — shipped, Logistics route graph, Business demand/integrity board)

**Phase 10 — Asymmetric corp scaffold (single machine, hot-seat):**
- Per-corp build menus and permission gating
- Industrial signature already shipped (brewery interior)
- Agri irrigation network (extends Logistics graph; new `network_kind`)
- Logistics OpenTTD-grade route/depot system + catchment radius rule
- Business demand model (settlement tiers, sales outlets read spatial demand)

**Phase 11 — Cross-corp tension (still hot-seat):**
- Utilities: water + sewage + power (one `UtilityManager`, three named graphs)
- Pollution-shrinks-suitable-land overlay
- Shared credits + multi-source spend on the shared tech tier
- Narrative event engine (~30 events: shared / corp-exclusive / cross-corp; feeds Business contracts)
- Espionage/integrity layer for Business

**Phase 12 — Networked MP:**
- Networking glue on top of the action pipe established in Phase 8
- Lockstep on tick boundary, host as authority

See `design_docs/2026-05-07_technical_architecture.html` for the full refactor ordering, ownership-layer design, and decision log.

## Current Game Status

> Snapshot of the **pre-pivot** code. Everything below describes what's *built*, not what slice-1 of Drinkustry actually ships. Several systems will be subtracted or reframed (e.g., distillery + packaging plant are post-slice-1; static auto-sell becomes spatial demand).

### Content Metrics (pre-pivot baseline)
- **Facilities:** 10+ (incl. farmhouses, fields, roads added Phase 4F-H)
- **Products:** 14 (raw materials through finished products)
- **Machines:** 13 (including special IO nodes and Market Outlet)
- **Production Chains:** 4 complete (beer / premium beer / spirits foundation / storage-buffered)
- **Research:** 40-tech tree, 8 branches × 5 tiers
- **Slice-1 retains:** lager beer chain only. Other chains carried forward as code; gated as post-slice-1 content.

### System Completion (pre-pivot)
- Core Architecture: 100% ✅ — singletons + EventBus pattern, used as foundation for ownership layer
- World Map Layer: 100% ✅ (sprites, routes, vehicles, demolish, tooltips, fields, roads)
- Factory Interior: 98% ✅ — **this is the depth bar** other corps must match
- Logistics: 100% ✅ (node-based network UI, multi-vehicle dispatch) — extended in Phase 10 with catchment radius
- Production: 95% ✅
- Economy: 95% ✅ (market manager with dynamic pricing exists; reframed as Business-corp-owned in Phase 10)
- Research: 100% ✅ (single-layer tree; refactored to two-layer in Phase 8)
- Save/Load: 100% ✅ (schema v3 with per-corp partitions shipped Phase 8 step 2, 2026-05-18; `shared.money` until EconomyManager v3→v4 refactor)

### Known Gaps vs. New Direction
- ~~No corp-ownership layer on entities~~ — `corp_id` field shipped Phase 8 step 1; schema v3 shipped step 2; action pipe is step 3 (next)
- No utilities (water/power/sewage) — entirely new (Phase 11)
- No catchment-radius rule — current routes are direct-connect (Phase 10)
- No spatial demand model — sales auto-sell at flat prices (Phase 10)
- No narrative event engine, no espionage/integrity (Phase 11)
- Networking deliberately last (Phase 12)
- No tutorial/onboarding (post-Phase 12)

### Recent Improvements (Phase 7A & 7B Complete)
**Phase 7A - Save/Load System:**
- Multiple named save slots with timestamps and game dates
- Save/Load dialog with proper validation
- Main menu and pause menu integration
- Quick save (F5) and quick load (F9) hotkeys
- Delete save functionality
- Full game state persistence across restarts
- Auto-save every 5 minutes

**Phase 7B - UI/UX:**
- Production statistics panel (toggleable, shows all facility status)
- Facility tooltips with inventory on hover
- Demolish mode for facilities and machines (50% refund)
- Visual mode indicators (colored panels)
- Mode conflict prevention system
- Factory interior UI restructured (bottom navbar)
- Machine build menu optimized layout
- Fixed mouse coordinate conversion for machine placement

## Testing the Game

**Basic Playthrough:**
1. Place Barley Field ($500) - produces barley every 5s
2. Place Grain Mill ($800) - waits for barley
3. Click "Create Route" button, click Field → Mill
4. Mill converts barley to malt (consumes 10 barley → produces 8 malt)
5. Place Brewery ($1500) - waits for malt
6. Create route: Mill → Brewery
7. Brewery produces ale → auto-sells for $100/unit
8. Double-click Brewery to enter interior (20×20 grid)
9. Place machines, connect them manually
10. Click "Back" to return to world map

**Testing Production Chains:**
- Use console commands: `ProductionManager.add_item_to_facility("facility_1", "malt", 100)`
- Check inventory: `print(ProductionManager.get_inventory("facility_1"))`
- Print status: `ProductionManager.print_production_status()`

**Verification:**
```
Data loaded: 7 facilities, 14 products, 0 recipes, 13 machines
```

See `TESTING.md` for comprehensive testing guide.

## File Structure

```
butykos/
├── core/              # Singleton managers (autoloaded)
├── systems/           # Game system managers (autoloaded)
├── scenes/
│   ├── world_map/     # Strategic layer (isometric)
│   └── factory_interior/ # Tactical layer (orthogonal)
├── data/              # JSON configuration files
└── assets/            # Sprites (sprites/, machines/)

Documentation:
├── DEVELOPMENT_STATUS.md  # Current progress, roadmap, next steps
├── TESTING.md            # Comprehensive testing guide
├── ASSET_NAMING_CONVENTION.md  # Full asset specifications
├── assets/PLACE_SPRITES_HERE.md  # Quick sprite reference
└── TROUBLESHOOTING.md    # Common issues
```

## Performance Notes

- 60 FPS with 10+ facilities and 15+ routes
- Smooth vehicle animation
- No memory leaks detected
- Not tested with 50+ facilities (optimization may be needed)

## Save System

**Quick Access:**
- F5 - Quick save to "quicksave" slot
- F9 - Quick load from "quicksave" slot
- ESC → Save/Load Game - Access full save management

**Features:**
- Multiple named save slots
- Auto-save every 5 minutes
- Save versioning for compatibility
- Full game state persistence (facilities, machines, routes, money, date)
- Delete unwanted saves

**Save Location:** `user://saves/` directory (platform-specific user data folder)