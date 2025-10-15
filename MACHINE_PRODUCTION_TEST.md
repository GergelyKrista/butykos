# Machine Production Test Guide

**Purpose:** Verify that machine production system works correctly in Phase 4B

**Prerequisites:**
- Godot 4.2 project open
- On branch: `feature/phase-4b-machine-production`

---

## Test Scenario 1: Basic Machine Production Chain

This test verifies that machines can:
1. Pull materials from facility inventory
2. Process materials through production cycles
3. Output finished products to facility inventory
4. Auto-sell final products for profit

### Setup (World Map Layer)

1. **Start the game** (F5)
2. **Place a Brewery** ($500)
   - This gives us a facility to enter
   - Note: Brewery won't produce anything yet (needs malt from outside)

3. **Manually add malt to brewery inventory**
   - Open Godot console (Output panel)
   - Run this in the debug console:
   ```gdscript
   ProductionManager.add_item_to_facility("facility_1", "malt", 50)
   ```
   - This simulates malt arriving from logistics routes
   - Gives machines raw materials to work with

### Test (Factory Interior Layer)

4. **Enter the Brewery**
   - Double-click the brewery OR Shift+click it
   - Should transition to factory interior scene
   - See 20×20 orthogonal grid

5. **Place a Mash Tun** ($300)
   - Click "Brewing" category in build menu
   - Click "Mash Tun" button
   - Click on grid to place (2×2 machine)
   - Preview should show green if affordable
   - Money should decrease by $300

6. **Place a Fermentation Vat** ($500)
   - Click "Fermentation Vat" button
   - Place it near the Mash Tun (2×3 machine)
   - Money should decrease by $500

7. **Place a Bottling Line** ($600)
   - Click "Packaging" category
   - Click "Bottling Line" button
   - Place it (3×2 machine)
   - Money should decrease by $600

### Expected Production Chain

**Mash Tun:**
- Input: 5 malt → Output: 4 mash (4 second cycle)
- Pulls malt from facility inventory

**Fermentation Vat:**
- Input: 4 mash → Output: 3 fermented_wash (8 second cycle)
- Uses mash produced by Mash Tun

**Bottling Line:**
- Input: 3 fermented_wash → Output: 5 ale (3 second cycle)
- Produces final product "ale" which auto-sells

### Watch Console Output

Monitor Godot output console for production messages:

```
Machine production initialized: Mash Tun in facility facility_1 (cycle: 4.0s)
Machine production initialized: Fermentation Vat in facility facility_1 (cycle: 8.0s)
Machine production initialized: Bottling Line in facility facility_1 (cycle: 3.0s)

[After 4 seconds]
Machine consumed 5 malt from facility inventory
Machine production complete: Mash Tun produced 4 mash

[After 8 seconds]
Machine consumed 4 mash from facility inventory
Machine production complete: Fermentation Vat produced 3 fermented_wash

[After 3 seconds]
Machine consumed 3 fermented_wash from facility inventory
Machine production complete: Bottling Line produced 5 ale
Sold 5 ale for $500
```

### Success Criteria

✅ **Machines placed successfully** - All three machines visible in factory interior
✅ **Costs deducted properly** - Money decreased by correct amounts
✅ **Production cycles running** - Console shows production messages
✅ **Materials flowing** - Mash Tun consumes malt, produces mash
✅ **Chain processing** - Fermentation Vat uses mash, Bottling Line uses fermented_wash
✅ **Auto-selling works** - Ale auto-sells for profit, money increases

---

## Test Scenario 2: Production Blocking (Insufficient Materials)

This test verifies that machines wait when materials are unavailable.

### Setup

1. **Exit factory interior** (Back button)
2. **Place another Brewery** ($500)
3. **Enter the new brewery** (double-click)
4. **Place a Mash Tun** ($300)
5. **DO NOT add malt to facility inventory**

### Expected Behavior

Watch console:

```
Machine production initialized: Mash Tun in facility facility_2 (cycle: 4.0s)

[After 4 seconds]
Machine production blocked: Mash Tun needs 5 malt from facility (has 0)

[Cycle resets, tries again after 4 seconds]
Machine production blocked: Mash Tun needs 5 malt from facility (has 0)
```

### Success Criteria

✅ **Production blocked** - Console shows "Machine production blocked" message
✅ **No crashes** - Game continues running smoothly
✅ **Timer resets** - Machine keeps trying every cycle

---

## Test Scenario 3: Multiple Machines in Same Facility

This test verifies that multiple machines can share facility inventory.

### Setup

1. **Enter first brewery** (the one with malt)
2. **Add more malt** (console command):
   ```gdscript
   ProductionManager.add_item_to_facility("facility_1", "malt", 100)
   ```
3. **Place a second Mash Tun** ($300)
4. **Place nearby** (different location than first Mash Tun)

### Expected Behavior

Both Mash Tuns should:
- Pull malt from the same facility inventory pool
- Produce mash independently
- Add mash to the same facility inventory pool
- Run on independent production timers

### Success Criteria

✅ **Both machines producing** - Console shows messages from both machines
✅ **Shared inventory** - Both consume from same malt pool
✅ **Independent timers** - Production cycles don't sync up
✅ **No conflicts** - Both machines work simultaneously

---

## Test Scenario 4: Machine Removal

This test verifies that production timers clean up properly.

### Setup

1. **Place a machine** (any type)
2. **Wait for it to start producing** (check console)
3. **Remove the machine**
   - Currently no UI for removal, would need to implement OR
   - Test via console: `FactoryManager.remove_machine("facility_1", "machine_X")`

### Expected Behavior

```
Machine production removed: machine_X from facility facility_1
```

### Success Criteria

✅ **Cleanup message** - Console shows machine removed
✅ **No errors** - No crashes or errors after removal
✅ **Production stops** - Machine no longer produces

---

## Debugging Tips

### Check Facility Inventory

Run in console:
```gdscript
print(ProductionManager.get_inventory("facility_1"))
```

Should show dictionary like:
```
{ "malt": 45, "mash": 8, "fermented_wash": 3 }
```

### Check Active Machine Timers

Run in console:
```gdscript
print(ProductionManager.machine_timers)
```

Should show dictionary like:
```
{ "facility_1:machine_1": 2.5, "facility_1:machine_2": 6.1 }
```

### Check Current Money

```gdscript
print(EconomyManager.money)
```

---

## Known Limitations (Expected)

⚠️ **No visual production indicators** - Can't see machines working visually
⚠️ **No conveyor belts yet** - Phase 4C feature
⚠️ **No input/output nodes** - Phase 4C feature
⚠️ **Manual malt addition** - Normally comes from logistics routes
⚠️ **No machine removal UI** - Would need to be implemented

---

## Common Issues

**Problem:** "Machine production blocked" immediately
**Solution:** Add materials to facility inventory first

**Problem:** Money not increasing
**Solution:** Check if final product is in `_should_auto_sell()` list (line 292 of production_manager.gd)

**Problem:** Machines not producing
**Solution:** Ensure facility `production_active` is true (facilities auto-start when constructed)

**Problem:** Can't afford machines
**Solution:** Start with more money via console: `EconomyManager.add_money(10000, "Testing")`

---

## Next Steps After Testing

If all tests pass:
1. Commit changes to `feature/phase-4b-machine-production`
2. Merge into `dev` branch
3. Move on to Phase 4C: Interior Logistics (conveyor belts)

If tests fail:
1. Note specific failure scenario
2. Debug production_manager.gd
3. Check EventBus signal connections
4. Verify machine data in machines.json
