# Interior Logistics Test Guide - Phase 4C

**Purpose:** Verify that interior logistics system works correctly with machine inventories and adjacent transfers

**Prerequisites:**
- Godot 4.2 project open
- On branch: `feature/phase-4c-interior-logistics`

---

## Overview of Changes

**Phase 4C implements automatic material flow between machines:**

1. **Machine Inventories** - Each machine now has its own inventory (not shared with facility)
2. **Adjacent Transfer** - Machines automatically transfer outputs to adjacent machines that need them
3. **Input Hoppers** - Pull materials from facility inventory → distribute to adjacent machines
4. **Output Depots** - Collect materials from adjacent machines → send to facility inventory

---

## Test Scenario 1: Adjacent Machine Transfer

This test verifies that machines automatically transfer materials to adjacent machines.

### Setup (World Map Layer)

1. **Start the game** (F5)
2. **Place a Brewery** ($1500)
3. **Enter the Brewery** (double-click or Shift+click)

### Test (Factory Interior Layer)

4. **Place an Input Hopper** ($100)
   - Click "Logistics" category
   - Click "Input Hopper" button
   - Place at position (5, 5)

5. **Place a Mash Tun** ($300) **ADJACENT** to Input Hopper
   - Place at position (6, 5) - directly to the right of hopper
   - Important: Machines must be touching (adjacent tiles)

6. **Place a Fermentation Vat** ($500) **ADJACENT** to Mash Tun
   - Place at position (8, 5) - directly to the right of Mash Tun
   - Or position (6, 7) - below Mash Tun

7. **Add malt to facility inventory** (via console):
   ```gdscript
   ProductionManager.add_item_to_facility("facility_1", "malt", 100)
   ```

### Expected Behavior - Step by Step

**Within 2 seconds (Input Hopper activates):**
```
Input Hopper: 10 malt (facility → machine_2)
```
- Input Hopper transfers malt from facility to adjacent Mash Tun

**After 4 seconds (Mash Tun produces):**
```
Machine consumed 5 malt from own inventory
Machine production complete: Mash Tun produced 4 mash
Transferred 2 mash: machine_2 → machine_3
```
- Mash Tun consumes 5 malt from its own inventory (not facility!)
- Mash Tun produces 4 mash into its own inventory
- **Automatically transfers 2 mash to adjacent Fermentation Vat**

**After 8 seconds (Fermentation Vat produces):**
```
Machine consumed 4 mash from own inventory
Machine production complete: Fermentation Vat produced 3 fermented_wash
```
- Fermentation Vat had received mash from adjacent Mash Tun
- Now produces fermented_wash

### Success Criteria

✅ **Input Hopper works** - Transfers malt from facility to Mash Tun
✅ **Adjacent transfer works** - Mash Tun automatically sends mash to Fermentation Vat
✅ **Machines use own inventory** - Console shows "from own inventory"
✅ **No crashes** - Game runs smoothly

---

## Test Scenario 2: Output Depot

This test verifies that Output Depots collect products and send them to facility for auto-selling.

### Setup

1. **Continue from Test Scenario 1**
2. **Place a Bottling Line** ($600) adjacent to Fermentation Vat
3. **Place an Output Depot** ($100) adjacent to Bottling Line

### Expected Behavior

**After Bottling Line produces ale:**
```
Machine production complete: Bottling Line produced 5 ale
Output Depot: 5 ale (machine_4 → facility)
Sold 5 ale for $500
Money added: +$500
```

- Bottling Line produces ale into its own inventory
- **Every 2 seconds**, Output Depot pulls ale from Bottling Line
- Output Depot transfers ale to facility inventory
- Ale auto-sells immediately (final product)
- Money increases!

### Success Criteria

✅ **Output Depot collects** - Pulls ale from adjacent machine
✅ **Auto-sell works** - Ale sells immediately for profit
✅ **Money increases** - Balance goes up by $500

---

## Test Scenario 3: Complete Production Chain

This test creates a full production chain with input/output nodes.

### Ideal Layout (20×20 grid)

```
[Input Hopper] → [Mash Tun] → [Fermentation Vat] → [Bottling Line] → [Output Depot]
     (5,5)         (6,5)            (8,5)              (10,5)            (13,5)
```

### Setup

1. **Place all machines in a horizontal line** (as shown above)
2. **Add malt to facility** (console):
   ```gdscript
   ProductionManager.add_item_to_facility("facility_1", "malt", 200)
   ```

### Expected Flow

**Materials flow automatically:**
```
Facility malt (200)
    ↓ [Input Hopper transfers every 2s]
Mash Tun inventory (malt)
    ↓ [Produces mash, transfers to adjacent]
Fermentation Vat inventory (mash)
    ↓ [Produces fermented_wash, transfers to adjacent]
Bottling Line inventory (fermented_wash)
    ↓ [Produces ale, Output Depot collects every 2s]
Facility inventory (ale) → Auto-sells → $$$
```

### Watch Console for Complete Flow

```
[Time 0s]
Input Hopper: 10 malt (facility → machine_2)

[Time 4s]
Machine consumed 5 malt from own inventory
Machine production complete: Mash Tun produced 4 mash
Transferred 2 mash: machine_2 → machine_3

[Time 8s]
Machine consumed 4 mash from own inventory
Machine production complete: Fermentation Vat produced 3 fermented_wash
Transferred 1 fermented_wash: machine_3 → machine_4

[Time 11s]
Machine consumed 3 fermented_wash from own inventory
Machine production complete: Bottling Line produced 5 ale

[Time 12s]
Output Depot: 5 ale (machine_4 → facility)
Sold 5 ale for $500
Money added: +$500 | Total: $XXXX
```

### Success Criteria

✅ **Full chain works** - Materials flow from facility → machines → facility
✅ **Automatic transfers** - No manual intervention needed
✅ **Money generation** - Profit from ale sales
✅ **Sustainable** - Process repeats continuously

---

## Test Scenario 4: Production Blocking

This test verifies that machines wait when they don't have materials.

### Setup

1. **Place only Mash Tun and Fermentation Vat** (adjacent)
2. **Do NOT place Input Hopper**
3. **Do NOT add malt to facility**

### Expected Behavior

```
Machine production blocked: Mash Tun needs 5 malt (has 0)
[Keeps trying every 4 seconds]
Machine production blocked: Mash Tun needs 5 malt (has 0)
```

**Then add malt manually to Mash Tun:**
```gdscript
ProductionManager._add_to_machine_inventory("facility_1", "machine_1", "malt", 10)
```

**Now production works:**
```
Machine consumed 5 malt from own inventory
Machine production complete: Mash Tun produced 4 mash
Transferred 2 mash: machine_1 → machine_2
```

### Success Criteria

✅ **Blocking works** - Machines don't crash when starved
✅ **Manual addition works** - Can manually add to machine inventory
✅ **Resumes automatically** - Production starts when materials available

---

## Test Scenario 5: Non-Adjacent Machines

This test verifies that machines DON'T transfer when not adjacent.

### Setup

1. **Place Mash Tun** at (5, 5)
2. **Place Fermentation Vat** at (8, 8) - **NOT adjacent**
3. **Add malt to Mash Tun** (console):
   ```gdscript
   ProductionManager._add_to_machine_inventory("facility_1", "machine_1", "malt", 20)
   ```

### Expected Behavior

```
Machine consumed 5 malt from own inventory
Machine production complete: Mash Tun produced 4 mash
```

**NO transfer message** - Machines not adjacent, no transfer happens

- Mash Tun produces mash
- Mash stays in Mash Tun's inventory
- Fermentation Vat doesn't receive anything

### Success Criteria

✅ **No transfer** - Adjacent check works correctly
✅ **Inventory accumulates** - Mash stays in Mash Tun
✅ **No errors** - System handles non-adjacent gracefully

---

## Debugging Tips

### Check Machine Inventory

Run in console:
```gdscript
print(ProductionManager.get_machine_inventory("facility_1", "machine_1"))
```

Should show:
```
{ "malt": 5, "mash": 4 }
```

### Check All Machine Inventories

```gdscript
print(ProductionManager.machine_inventories)
```

Shows all machines:
```
{
  "facility_1:machine_1": { "malt": 5, "mash": 2 },
  "facility_1:machine_2": { "mash": 4, "fermented_wash": 1 }
}
```

### Check Facility Inventory

```gdscript
print(ProductionManager.get_inventory("facility_1"))
```

### Force Input Hopper Transfer

```gdscript
ProductionManager._process_input_hopper("facility_1", FactoryManager.get_machine("facility_1", "machine_1"))
```

---

## What You Should See - Visual Walkthrough

### **Step 1: Place Machines**
- You should see colored rectangles for each machine
- Labels show machine names
- Machines snap to grid

### **Step 2: Materials Arrive**
- **No visual indicators yet** (Phase 5 feature)
- Watch console for "Input Hopper: X malt" messages

### **Step 3: Production Happens**
- Every 4-8 seconds, see production messages
- Transfer messages show materials moving between machines

### **Step 4: Money Increases**
- Top-left money display goes up
- Console shows "Money added: +$500"

---

## Known Limitations (Expected)

⚠️ **No visual material flow** - Can't see items moving (console only)
⚠️ **No inventory UI** - Can't see machine inventories visually
⚠️ **No connection indicators** - Can't see which machines are connected
⚠️ **No conveyor belt visuals** - Adjacent transfer is invisible

These are intentional - visual feedback is Phase 5!

---

## Common Issues

**Problem:** "Machine production blocked" immediately
**Solution:** Place Input Hopper adjacent to machine, ensure facility has materials

**Problem:** No transfers happening
**Solution:** Machines must be adjacent (touching tiles), check grid positions

**Problem:** Input Hopper not working
**Solution:** Wait 2 seconds for IO node cycle, check facility inventory has materials

**Problem:** Output Depot not collecting
**Solution:** Wait 2 seconds, ensure adjacent machine has products in inventory

**Problem:** Money not increasing
**Solution:** Need complete chain: Input Hopper → Machines → Output Depot

---

## Performance Test

Try placing **10+ machines** in a chain:
```
[Hopper] → [Mash1] → [Vat1] → [Mash2] → [Vat2] → [Line1] → [Line2] → [Depot]
```

### Expected:
- Game runs at 60 FPS
- All transfers work simultaneously
- Console fills with transfer messages
- Money increases steadily

---

## Next Steps After Testing

If all tests pass:
1. Commit changes to `feature/phase-4c-interior-logistics`
2. **Push feature branch to remote**
3. **Create pull request on GitHub**
4. Merge PR into `dev` branch
5. Move on to Phase 4D: Logistics Visualization

If tests fail:
1. Note specific failure scenario
2. Debug production_manager.gd
3. Check adjacent position calculations
4. Verify machine inventory management

---

**Status:** Interior logistics core mechanics complete! Visual feedback coming in future phase.

**Recommended Next Action:** Run through all 5 test scenarios and report findings.
