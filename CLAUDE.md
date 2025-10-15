# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Alcohol Empire Tycoon** - OTTD-inspired business tycoon game built in Godot 4.2
- **Theme:** Build and manage an alcohol production empire (beer, spirits)
- **Dual-layer gameplay:** Strategic world map + Tactical factory interiors
- **Engine:** Godot 4.2 with GDScript
- **Status:** Dual-layer MVP complete, ready for interior production implementation

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
├── data_manager.gd      # JSON data loading with helper filters
└── save_manager.gd      # Save/load framework (not fully implemented)

systems/
├── world_manager.gd     # 50×50 isometric grid, facility placement, coordinate conversion
├── economy_manager.gd   # Money tracking, transactions
├── production_manager.gd # Input-based production cycles, inventory
├── logistics_manager.gd  # Routes, vehicles, cargo transport
└── factory_manager.gd   # 20×20 factory interiors per facility, machine placement
```

**Access pattern:** All managers are globally accessible:
```gdscript
WorldManager.place_facility(...)
EventBus.facility_placed.emit(facility)
EconomyManager.money
```

### Dual-Layer System

**World Map (Strategic Layer):**
- 50×50 **isometric grid** (64×32 pixel tiles, 2:1 ratio)
- Facility placement with multi-tile support (2×2, 3×3, etc.)
- Route creation for logistics
- Scene: `scenes/world_map/world_map.tscn`

**Factory Interior (Tactical Layer):**
- 20×20 **orthogonal top-down grid** (64×64 pixel tiles)
- Machine placement within facilities
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
```

### Data-Driven Design

Game content defined in JSON files (`data/`):
- `facilities.json` - Buildings (Barley Field, Grain Mill, Brewery)
- `machines.json` - Interior machines (12 types: mash tuns, fermentation vats, etc.)
- Future: `products.json`, `recipes.json`

All costs, production times, and recipes in JSON for easy balancing.

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

3. **Diamond Shapes:** Facilities render as Polygon2D diamonds, not rectangles
   ```gdscript
   # Diamond vertices for 64×32 tile
   var half_width = TILE_WIDTH / 2.0   # 32
   var half_height = TILE_HEIGHT / 2.0 # 16
   polygon.polygon = PackedVector2Array([
       Vector2(0, -half_height),     # Top
       Vector2(half_width, 0),       # Right
       Vector2(0, half_height),      # Bottom
       Vector2(-half_width, 0)       # Left
   ])
   ```

4. **Mouse Input:** Use `WorldManager.world_to_grid()` directly (handles isometric conversion)

5. **Factory Interiors:** Stay orthogonal (top-down), use `FactoryManager.INTERIOR_TILE_SIZE = 64`

## Production System Flow

**3-Stage Chain Example:**
1. **Barley Field** (source) → produces barley every 5s
2. **Grain Mill** (processor) → consumes barley, produces malt every 3s
3. **Brewery** (final) → consumes malt, produces ale → **auto-sells for profit**

**Key Rules:**
- Intermediate products (barley, malt) stay in facility inventory
- Final products auto-sell immediately
- Production requires inputs (checked via ProductionManager)
- Routes transport goods between facilities (LogisticsManager)

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

1. **Autoload not recognized:** Restart Godot editor (known issue)
2. **Tiles misaligned with grid:** Add 0.5 offset to tile positions
3. **Facilities render in wrong order:** Check Z-index calculation
4. **Mouse picking fails:** Ensure using proper isometric conversion
5. **Factory interior broken:** Never apply isometric logic to factory scenes

## File Structure

```
butykos/
├── core/              # Singleton managers (autoloaded)
├── systems/           # Game system managers (autoloaded)
├── scenes/
│   ├── world_map/     # Strategic layer (isometric)
│   └── factory_interior/ # Tactical layer (orthogonal)
├── data/              # JSON configuration files
├── assets/            # Sprites, textures (currently placeholders)
└── ui/                # UI components

Documentation:
├── DEVELOPMENT_STATUS.md  # Current progress, milestones
├── TESTING_GUIDE.md       # Production chain testing
├── DUAL_LAYER_TEST.md     # Factory interior testing
├── SPRITE_ASSET_GUIDE.md  # Asset replacement guide
└── TROUBLESHOOTING.md     # Common issues
```

## Next Development Priorities

Based on `DEVELOPMENT_STATUS.md`:

**Phase 4B - Machine Production (current):**
- Add machine placement UI in factory interiors
- Connect machine production to facility output
- Machines process materials inside factories

**Phase 4C - Interior Logistics:**
- Conveyor belts between machines
- Input/output nodes connecting to facility logistics

**Phase 5 - Content Expansion:**
- More facility types (distillery, wheat farm, packaging)
- More machine types (20+ total)
- Multiple production chains

## Asset Guidelines

**World Map Sprites (Isometric):**
- Draw from ~30-35° viewing angle
- Show top, front, and one side
- Fit within 64×64 but maintain isometric diamond shape
- Pivot: bottom-center of diamond

**Factory Interior Sprites (Top-Down):**
- Simple orthogonal view (straight down)
- 64×64 square tiles
- Pivot: center

**Current Implementation:**
Using `Polygon2D` colored diamonds as placeholders - easy to replace with sprite textures.

## Testing the Game

**Basic Playthrough:**
1. Place Barley Field ($100) - produces barley
2. Place Grain Mill ($300) - waits for barley
3. Create route: Field → Mill (click "Create Route" button, click both facilities)
4. Mill converts barley to malt
5. Place Brewery ($500) - waits for malt
6. Create route: Mill → Brewery
7. Brewery produces ale → money increases
8. Double-click Brewery to enter interior (20×20 grid with machines)
9. Click "Back" to return to world map

**Current Limitations:**
- No machine placement UI yet (interior build menu not implemented)
- No visual route lines
- No vehicle sprites (transport is invisible but functional)
- Camera zoom not implemented
