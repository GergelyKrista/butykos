# Testing Guide - Minimal Playable Loop

This guide will help you test the minimal playable loop we've built.

## What's Been Built

✅ **Core Systems**
- WorldManager: 50x50 grid, facility placement/removal
- EconomyManager: Money tracking, transactions
- ProductionManager: Production cycles, auto-selling
- DataManager: JSON data loading
- EventBus: Signal-based communication
- GameManager: Game state and time management
- SaveManager: Save/load framework (placeholder)

✅ **World Map Scene**
- Grid visualization (50x50 tiles, 64px each)
- Camera controls (pan with middle mouse, zoom with wheel)
- Facility placement system with preview
- Dynamic build menu
- Money and date HUD

✅ **Production Loop**
- Facilities produce resources automatically
- Products auto-sell for revenue
- Money accumulates for expansion

## How to Test

### 1. Launch the Game

Open the project in Godot 4.x and press **F5** (or click Play).

You should see:
- A 50x50 grid
- HUD showing "Money: $5000" and "Date: 1850-01-01"
- Build menu on the left with 3 facility types

### 2. Test Camera Controls

**Pan:** Hold middle mouse button and drag
**Zoom:** Scroll mouse wheel up/down

Verify the camera:
- Stays within grid bounds
- Zooms smoothly (0.25x to 2.0x range)

### 3. Test Facility Placement

**Click "Barley Field ($500)"** in the build menu.

You should see:
- A semi-transparent 2x2 colored preview following your mouse
- Preview turns **green** when valid, **red** when invalid
- Money updates in real-time

**Left-click** to place the facility.

Verify:
- Money decreases by $500
- Facility appears on the grid with label
- Facility starts producing immediately

**Try invalid placements:**
- Click outside grid bounds (should not place)
- Try to place overlapping an existing facility (should not place)
- Try to place when you can't afford it (should not place)

**Cancel placement:** Right-click or press **Escape**

### 4. Test Production and Revenue

Wait ~5 seconds after placing a Barley Field.

You should see:
- Console message: "Production complete: Barley Field produced 10 barley"
- Console message: "Sold 10 barley for $1000"
- Money increases by $1000

**Verify the loop:**
1. Place facility (-$500)
2. Wait for production cycle (~5s)
3. Earn $1000 from auto-sale
4. Net profit: +$500 per cycle

### 5. Test Multiple Facilities

Place **multiple Barley Fields** (you start with $5000).

Verify:
- Each facility produces independently
- Money accumulates from all facilities
- Grid correctly tracks occupancy

### 6. Test Facility Types

Try building other facility types:
- **Grain Mill ($800)** - 2x2, produces malt
- **Brewery ($1500)** - 3x3, produces ale

Note: These require more money to unlock.

### 7. Test Edge Cases

**Zoom all the way out:** Verify grid is fully visible
**Zoom all the way in:** Verify tiles are large and clear
**Fill the grid:** Place many facilities, test performance
**Run out of money:** Verify you can't place more facilities

## Expected Console Output

When testing, you should see output like:

```
EventBus initialized
GameManager initialized
SaveManager initialized
DataManager initialized
Data loaded: 3 facilities, 0 products, 0 recipes, 0 machines
WorldManager initialized
EconomyManager initialized
Starting money: $5000
ProductionManager initialized
WorldMap scene loaded
Placement mode started: Barley Field
Facility placed: barley_field at (5, 5)
Money spent: -$500 (Built Barley Field) | Remaining: $4500
Facility constructed: facility_1
Production started for facility: facility_1
Production complete: Barley Field produced 10 barley
Sold 10 barley for $1000
Money added: +$1000 (Sold 10 barley) | Total: $5500
```

## Known Limitations (MVP)

These are intentional for the minimal loop:
- No construction time (facilities build instantly)
- No input requirements (barley grows without resources)
- Auto-sell only (no storage/logistics)
- Fixed sell price ($100/unit)
- No market simulation
- No factory interiors yet
- No save/load functionality yet

## Performance Testing

With 10+ facilities producing, verify:
- 60 FPS maintained
- No lag when placing new facilities
- Grid rendering remains smooth

## Debug Commands

Open the console (in Godot) and try:

```gdscript
# Add money
EconomyManager.cheat_add_money(10000)

# Print economy status
EconomyManager.print_balance()

# Print production status
ProductionManager.print_production_status()

# Print grid info
WorldManager.print_grid_info()
```

## Success Criteria

The minimal playable loop is successful if:
✅ You can place facilities on the grid
✅ Facilities produce resources automatically
✅ Money accumulates from sales
✅ You can expand by building more facilities
✅ Camera controls work smoothly
✅ No crashes or errors

## Next Steps

Once this loop is tested and working:
1. Add more facility types (from facilities.json)
2. Implement logistics system (vehicles, routes)
3. Add factory interior layer
4. Implement market simulation
5. Add construction time
6. Add input/output requirements for production

---

**Report Issues:**
If you find bugs or unexpected behavior, note:
- What you were doing
- Console error messages
- Expected vs actual behavior
