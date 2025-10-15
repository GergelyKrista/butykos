# Testing Guide - Alcohol Empire Tycoon

Complete testing guide covering all game systems and features.

**Last Updated:** 2025-10-15
**Current Phase:** Phase 4E Complete (Interior Logistics + Visualization)

---

## Table of Contents

1. [Quick Start Testing](#quick-start-testing)
2. [Basic Systems Testing](#basic-systems-testing)
3. [Interior Logistics Testing](#interior-logistics-testing)
4. [Route & Vehicle Testing](#route--vehicle-testing)
5. [Debug Commands](#debug-commands)
6. [Common Issues](#common-issues)

---

## Quick Start Testing

### Prerequisites
- Godot 4.2+ installed
- Project open in Godot Editor

### Launch the Game
1. Press **F5** (or click "Play" button)
2. Main scene loads: `res://scenes/world_map/world_map.tscn`

### What You Should See
- ✅ 50×50 isometric grid
- ✅ HUD: "Money: $5000" and "Date: 1850-01-01"
- ✅ Build menu with 3 facility types (bottom of screen)

---

## Basic Systems Testing

### Test 1: Camera Controls

**Pan:** Hold middle mouse button + drag
**Zoom:** Mouse wheel up/down

**Verify:**
- ✅ Camera stays within grid bounds
- ✅ Smooth zooming (0.25× to 2.0× range)
- ✅ Grid remains centered

---

### Test 2: Facility Placement

**Steps:**
1. Click **"Barley Field ($500)"** in build menu
2. Move mouse over grid
3. Observe green/red preview (valid/invalid placement)
4. Left-click to place
5. Right-click or **Escape** to cancel

**Verify:**
- ✅ Preview follows mouse cursor
- ✅ Green when valid, red when invalid (overlapping, out of bounds, can't afford)
- ✅ Money decreases by $500 on placement
- ✅ Facility appears with label
- ✅ Production starts immediately

**Try Invalid Placements:**
- Outside grid bounds → Should not place
- Overlapping existing facility → Should not place
- Insufficient funds → Should not place

---

### Test 3: Production & Revenue

**Steps:**
1. Place a Barley Field
2. Wait ~5 seconds

**Console Output:**
```
Production complete: Barley Field produced 10 barley
Sold 10 barley for $1000
Money added: +$1000 | Total: $5500
```

**Verify:**
- ✅ Production cycle completes every 5 seconds
- ✅ Auto-sell generates revenue
- ✅ Money increases in HUD
- ✅ Process repeats continuously

**Economic Loop:**
- Spend: $500 (facility cost)
- Earn: $1000 per cycle (every 5s)
- Net: +$500 profit per facility

---

### Test 4: Multiple Facilities

**Steps:**
1. Place 3+ Barley Fields (you start with $5000)
2. Wait for multiple production cycles

**Verify:**
- ✅ Each facility produces independently
- ✅ Money accumulates from all facilities
- ✅ Grid correctly tracks occupancy
- ✅ 60 FPS maintained

---

### Test 5: Advanced Facilities

**Grain Mill ($800):**
- 2×2 grid size
- Consumes 10 barley → Produces 8 malt
- Requires input from Barley Field

**Brewery ($1500):**
- 3×3 grid size
- Consumes 8 malt → Produces 5 ale ($500 revenue)
- Has factory interior (double-click to enter)

---

## Interior Logistics Testing

### Test 6: Factory Interior Entry

**Steps:**
1. Place a **Brewery** ($1500)
2. **Double-click** the brewery (or Shift+click)

**Expected:**
- ✅ Scene transitions to factory interior
- ✅ 20×20 orthogonal grid (top-down view)
- ✅ Machine build menu appears
- ✅ "Back" button visible

**Return to World Map:**
- Click **"Back"** button
- ✅ Returns to world map with facilities preserved

---

### Test 7: Machine Connections

**Setup:**
1. Enter Brewery interior
2. Place machines:
   - **Input Hopper** ($100) at (4, 6)
   - **Mash Tun** ($300) at (7, 10)
   - **Fermentation Vat** ($500) at (10, 10)
   - **Bottling Line** ($600) at (13, 10)
   - **Storage Tank** ($250) at (13, 7)
   - **Market Outlet** ($75) at (14, 3)

3. Click **"Connect Machines"** button
4. Create connections by clicking machines:
   - Click **Input Hopper** → Click **Mash Tun**
   - Click **Mash Tun** → Click **Fermentation Vat**
   - Click **Fermentation Vat** → Click **Bottling Line**
   - Click **Bottling Line** → Click **Storage Tank**
   - Click **Storage Tank** → Click **Market Outlet**

**Expected Visual:**
- ✅ White arrow lines appear between connected machines
- ✅ Console shows: "Connection created: machine_X → machine_Y"

---

### Test 8: Production Flow

**Prerequisites:** Machines connected as above

**Add materials to facility (console):**
```gdscript
ProductionManager.add_item_to_facility("facility_1", "malt", 100)
```

**Watch Console for Flow (every 2 seconds):**

```
[Time 0s]
Input Hopper: 10 malt (facility → machine_2)

[Time 4s]
Machine consumed 5 malt from own inventory
Machine production complete: Mash Tun produced 4 mash
Transferred 2 mash: machine_2 → machine_3

[Time 12s]
Machine consumed 4 mash from own inventory
Machine production complete: Fermentation Vat produced 3 fermented_wash
Transferred 1 fermented_wash: machine_3 → machine_4

[Time 15s]
Machine consumed 3 fermented_wash from own inventory
Machine production complete: Bottling Line produced 5 ale
Transferred 5 ale: machine_4 → machine_5

[Time 16s]
Storage Buffer: Transferred 5 ale (machine_5 → machine_6)

[Time 18s]
Market Outlet: Sold 5 ale for $500 ($100/unit)
Money added: +$500 | Total: $XXXX
```

**Verify:**
- ✅ Input Hopper pulls from facility inventory
- ✅ Materials flow through connected machines
- ✅ Each machine uses own inventory (not shared)
- ✅ Storage Tank actively transfers to Market Outlet
- ✅ Market Outlet sells for cash
- ✅ Money increases

---

### Test 9: Connection Deletion

**Steps:**
1. Click **"Delete Connection"** button
2. Click **source machine** (gets yellow highlight)
3. Click **destination machine**

**Expected:**
- ✅ White connection line disappears
- ✅ Console shows: "Connection deleted: machine_X → machine_Y"
- ✅ Material transfer stops

---

### Test 10: Market Outlet (Bootstrap Income)

**Purpose:** Sell intermediate products for reduced profit

**Setup:**
1. Place **Mash Tun** and **Market Outlet**
2. Connect: Mash Tun → Market Outlet
3. Add malt to Mash Tun inventory:
   ```gdscript
   ProductionManager._add_to_machine_inventory("facility_1", "machine_1", "malt", 20)
   ```

**Expected:**
```
Machine production complete: Mash Tun produced 4 mash
Market Outlet: Sold 4 mash for $80 ($20/unit)
Money added: +$80
```

**Pricing:**
- Barley: $5/unit
- Malt: $15/unit
- Mash: $20/unit
- Fermented Wash: $40/unit
- Ale: $100/unit (full price)

**Verify:**
- ✅ Market Outlet pulls from connected machines
- ✅ Sells at reduced price (not full ale price)
- ✅ Allows early-game income generation

---

## Route & Vehicle Testing

### Test 11: Route Creation

**Setup (World Map):**
1. Place **Barley Field** at (10, 37)
2. Place **Grain Mill** at (36, 37)
3. Click **"Create Route"** button

**Steps:**
1. Click **Barley Field** (source)
2. Click **Grain Mill** (destination)

**Expected:**
- ✅ Yellow highlight on source facility
- ✅ Blue route line appears connecting facilities
- ✅ Orange directional arrows at 1/3 and 2/3 along route
- ✅ Console shows: "Route created: facility_X → facility_Y (barley)"

---

### Test 12: Vehicle Visualization

**Prerequisites:** Route created as above

**Expected:**
- ✅ Yellow truck sprite spawns at source facility
- ✅ Truck shows label: "Loading..."
- ✅ After pickup: label changes to "10 barley"
- ✅ Truck animates smoothly along blue route line
- ✅ Truck rotates to face direction of travel
- ✅ At destination: label shows "Unloading..."
- ✅ Truck returns to source and repeats

**Console Output:**
```
Vehicle visual created: vehicle_1
Vehicle vehicle_1 picked up 10 barley from facility_1
Delivered 10 barley to facility facility_2
Vehicle vehicle_1 delivered 10 barley to facility_2
```

**Verify:**
- ✅ Trucks are visible (yellow polygons)
- ✅ Smooth animation along routes
- ✅ Cargo labels update correctly
- ✅ Multiple vehicles work simultaneously

---

### Test 13: Multiple Routes

**Setup:**
1. Add **Brewery** at (32, 6)
2. Create route: Grain Mill → Brewery (malt)
3. Create route: Second Barley Field → Grain Mill (barley)

**Expected:**
- ✅ Multiple blue route lines visible
- ✅ Multiple yellow trucks animate simultaneously
- ✅ Each truck shows correct cargo
- ✅ No visual overlap issues
- ✅ Performance stays at 60 FPS

---

## Debug Commands

### Economy Commands

```gdscript
# Add money
EconomyManager.add_money(10000, "cheat")

# Print balance
EconomyManager.print_balance()
```

### Production Commands

```gdscript
# Add items to facility
ProductionManager.add_item_to_facility("facility_1", "malt", 100)

# Add items to machine
ProductionManager._add_to_machine_inventory("facility_1", "machine_1", "malt", 50)

# Check facility inventory
print(ProductionManager.get_inventory("facility_1"))

# Check machine inventory
print(ProductionManager.get_machine_inventory("facility_1", "machine_1"))

# Print all machine inventories
print(ProductionManager.machine_inventories)

# Print production status
ProductionManager.print_production_status()
```

### Logistics Commands

```gdscript
# Print logistics status
LogisticsManager.print_logistics_status()

# Get all routes
print(LogisticsManager.get_all_routes())

# Get all vehicles
print(LogisticsManager.get_all_vehicles())
```

### World Commands

```gdscript
# Print grid info
WorldManager.print_grid_info()

# Get all facilities
print(WorldManager.get_all_facilities())
```

---

## Common Issues

### Issue: "Machine production blocked: needs X malt (has 0)"

**Cause:** Machine doesn't have required inputs
**Solution:**
- Connect Input Hopper to machine
- Ensure facility has materials
- Wait 2 seconds for IO node cycle

---

### Issue: Vehicles not visible on world map

**Cause:** Route/vehicle renderer not loaded
**Solution:**
- Check `world_map.tscn` has RoutesRenderer and VehiclesRenderer nodes
- Verify EventBus signals: `vehicle_spawned`, `vehicle_removed`

---

### Issue: Market Outlet not selling

**Cause:** Not connected to producing machine
**Solution:**
- Connect machine → Market Outlet (or machine → Storage Tank → Market Outlet)
- Ensure connected machine has products in inventory
- Wait 2 seconds for IO node cycle

---

### Issue: Storage Tank not transferring

**Cause:** Missing `is_storage_buffer: true` flag
**Solution:**
- Check `data/machines.json` has flag for storage_tank
- Verify `_process_storage_buffer()` exists in production_manager.gd

---

### Issue: Facilities/machines not appearing

**Cause:** Autoload not initialized
**Solution:**
- Restart Godot Editor (known autoload initialization issue)
- Verify project.godot has all autoloads configured

---

## Performance Testing

### Stress Test: 10+ Facilities

**Setup:**
1. Place 10+ Barley Fields
2. Place 5+ Grain Mills
3. Place 3+ Breweries
4. Create 15+ routes

**Expected:**
- ✅ 60 FPS maintained
- ✅ All vehicles animate smoothly
- ✅ No lag when placing new facilities
- ✅ Console output remains readable

---

### Stress Test: Complex Factory

**Setup:**
1. Enter brewery interior
2. Place 20+ machines
3. Create 15+ connections
4. Run full production chain

**Expected:**
- ✅ 60 FPS maintained
- ✅ All transfers work simultaneously
- ✅ Console fills with transfer messages
- ✅ Money increases steadily

---

## Success Criteria

**All systems pass if:**

✅ **World Map:**
- Facilities place correctly on isometric grid
- Camera controls work smoothly
- Production cycles run automatically
- Money accumulates from sales

✅ **Factory Interior:**
- Can enter/exit factory interiors
- Machines place on 20×20 grid
- Connections create visual links
- Materials flow through connections

✅ **Logistics:**
- Routes create blue lines with arrows
- Vehicles animate along routes
- Cargo displays correctly
- Multiple routes work simultaneously

✅ **Economy:**
- Market Outlet sells intermediate products
- Storage Tank buffers production
- Money increases from sales
- Bootstrap economy allows early expansion

✅ **Performance:**
- 60 FPS with 10+ facilities
- No crashes or errors
- Smooth gameplay experience

---

## Next Steps

After testing:

1. **Report Issues:** Note specific failures with console logs
2. **Document Bugs:** Include steps to reproduce
3. **Continue Development:** See `DEVELOPMENT_STATUS.md` for next phase

---

**Testing Complete? Move on to Phase 5: Content Expansion!**
