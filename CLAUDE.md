# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Alcohol Empire Tycoon** - OTTD-inspired business tycoon game built in Godot 4.2
- **Theme:** Build and manage an alcohol production empire (beer, spirits, wine)
- **Dual-layer gameplay:** Strategic world map + Tactical factory interiors
- **Engine:** Godot 4.2 with GDScript
- **Status:** Phase 7A Complete - Save/Load System fully functional

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
- `route_created`, `route_removed`
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

3. **Sprite Rendering:** Facilities use Sprite2D with fallback to Polygon2D diamonds
   ```gdscript
   var sprite_path = facility_def.get("visual", {}).get("icon", "")
   if ResourceLoader.exists(sprite_path):
       var sprite = Sprite2D.new()
       sprite.texture = load(sprite_path)
       sprite.centered = true
   else:
       # Fallback to colored diamond polygon
   ```

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
- Naming: Match facility ID (e.g., `barley_field.png`)
- Referenced in `facilities.json` as `visual.icon`
- Automatic fallback to colored diamonds if sprite missing

### Factory Interior Machines (Top-Down)
- Location: `assets/machines/`
- Naming: Match machine ID (e.g., `mash_tun.png`)
- Referenced in `machines.json` as `visual.sprite` (note: different field name)
- Automatic fallback to colored rectangles if sprite missing

### Artist Workflow
1. Drop PNG file in correct folder
2. Match exact filename from JSON
3. Launch game (F5)
4. Sprite appears automatically

See `assets/PLACE_SPRITES_HERE.md` for quick reference.

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
7. **Machine not producing:** Check if it has input materials in its own inventory (not facility inventory)
8. **Machine placement incorrect:** Use `get_viewport().get_mouse_position()` + canvas transform inverse, not `camera.get_global_mouse_position()`
9. **Mode conflicts:** Always cancel conflicting modes before starting new mode (placement, route, demolish, connect)

## Next Development Priorities

Based on `DEVELOPMENT_STATUS.md`:

**Phase 6A - Market System (HIGH PRIORITY, 2-3 hours):**
- Dynamic pricing based on supply/demand
- Price fluctuations over time
- Market trends and cycles
- Contract system

**Phase 7C - Remaining UI/UX (2-3 hours):**
- Route management UI (pause, delete, stats)
- Resource flow visualization (animated particles)
- Mini-map for world view

**Phase 8 - More Content (2-4 hours):**
- More facility types (vineyard, hop farm, water source)
- More machine types (conveyor belt, aging barrel, quality control)
- More product chains (wine, premium whiskey, multiple beer types)

## Current Game Status

### Content Metrics
- **Facilities:** 7 (Barley Field, Wheat Farm, Grain Mill, Brewery, Distillery, Packaging Plant, Storage Warehouse)
- **Products:** 14 (raw materials through finished products with pricing)
- **Machines:** 13 (including special IO nodes and Market Outlet)
- **Production Chains:** 4 complete chains working

### System Completion
- Core Architecture: 100% ✅
- World Map Layer: 100% ✅ (sprites, routes, vehicles, demolish, tooltips)
- Factory Interior: 98% ✅ (connections, production, sprites, demolish)
- Logistics: 95% ✅
- Production: 95% ✅
- Economy: 90% ✅
- UI/UX: 80% ✅ (stats panel, tooltips, mode indicators, demolish, save/load UI)
- Save/Load: 100% ✅ (multiple slots, persistence, hotkeys)

### Known Limitations
- Static pricing (no supply/demand) - Phase 6A
- No tutorial/onboarding - Phase 7D
- No multi-input recipes (can add in Phase 5C)
- Route management UI incomplete (pause, delete routes)
- No mini-map for navigation

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