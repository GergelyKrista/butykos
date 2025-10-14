# Production Chain Testing Guide

Test the complete production chain with input requirements and logistics!

## 🔗 What's New

**Input-Based Production:**
- Facilities now require inputs to produce outputs
- Grain Mill needs barley to produce malt
- Brewery needs malt to produce ale
- Production blocked if inputs aren't available

**Logistics System:**
- Routes transport goods between facilities
- Vehicles pickup, travel, and deliver cargo
- Automatic cargo management

## 🧪 Test Scenario: Complete Production Chain

Follow these steps to test the full barley → malt → ale chain:

### Step 1: Build the Facilities

1. **Start the game** (F5)
2. **Build 1 Barley Field** ($500)
   - Place it anywhere on the grid
   - Wait 5 seconds
   - Should produce 10 barley (stays in inventory, NOT sold!)

3. **Build 1 Grain Mill** ($800)
   - Place it near the Barley Field
   - It will try to produce malt every 3 seconds
   - **Should see "Production blocked: Grain Mill needs 10 barley (has 0)"**

4. **Build 1 Brewery** ($1,500)
   - Place it near the Grain Mill
   - It will try to produce ale every 8 seconds
   - **Should see "Production blocked: Brewery needs 8 malt (has 0)"**

### Step 2: Create Routes

#### Route 1: Barley Field → Grain Mill

1. Click **"Create Route"** button
2. Console shows: "Route mode started - Click source facility, then destination facility"
3. **Click the Barley Field** (should turn yellow)
4. Console shows: "Route source selected: facility_1 - Now click destination"
5. **Click the Grain Mill**
6. Console shows:
   ```
   Route destination selected: facility_2
   Route created: route_1
   Vehicle vehicle_1 picked up 10 barley from facility_1
   Delivered 10 barley to facility facility_2
   ```

#### Route 2: Grain Mill → Brewery

1. Click **"Create Route"** button again
2. **Click the Grain Mill** (turns yellow)
3. **Click the Brewery**
4. Console shows route creation for malt transport

### Step 3: Watch the Chain Work!

**After a few seconds, you should see:**

```
Production complete: Barley Field produced 10 barley
Vehicle vehicle_1 picked up 10 barley from facility_1
Delivered 10 barley to facility facility_2
Consumed 10 barley for production
Production complete: Grain Mill produced 8 malt
Vehicle vehicle_2 picked up 8 malt from facility_2
Delivered 8 malt to facility facility_3
Consumed 8 malt for production
Production complete: Brewery produced 5 ale
Sold 5 ale for $500
Money added: +$500 (Sold 5 ale)
```

## ✅ Success Criteria

The production chain is working if:

1. **Barley Field** produces barley every 5 seconds
2. **Routes automatically transport** goods between facilities
3. **Grain Mill** produces malt when it receives barley
4. **Brewery** produces ale when it receives malt
5. **Ale is sold automatically** for profit
6. **Money increases** from ale sales (not barley/malt)

## 📊 Expected Production Flow

| Step | Facility | Input | Output | Cycle Time | Revenue |
|------|----------|-------|--------|------------|---------|
| 1 | Barley Field | - | 10 barley | 5s | $0 (stored) |
| 2 | Grain Mill | 10 barley | 8 malt | 3s | $0 (stored) |
| 3 | Brewery | 8 malt | 5 ale | 8s | $500 |

**Full chain time:** ~16 seconds from barley to profit

## 🔍 Console Commands for Debugging

While the game is running, use these commands in the Godot console:

```gdscript
# Check production status
ProductionManager.print_production_status()

# Check logistics status
LogisticsManager.print_logistics_status()

# Check facility inventory
ProductionManager.get_inventory("facility_1")
ProductionManager.get_inventory("facility_2")
ProductionManager.get_inventory("facility_3")

# Check specific product in facility
ProductionManager.get_inventory_item("facility_2", "barley")
```

## 🐛 Troubleshooting

### "Production blocked" messages

**Symptom:** Grain Mill or Brewery shows "Production blocked: needs X product (has 0)"

**Cause:** No route delivering the required input

**Solution:**
- Create a route from the upstream facility
- Check the route was created (console should show "Route created")
- Wait for vehicle to complete one delivery cycle

### Facilities not producing

**Symptom:** No "Production complete" messages

**Cause:** Facility might not be constructed

**Solution:**
- Check console for "Facility constructed" message
- Check "Production started" message
- Use `ProductionManager.print_production_status()` to see active producers

### Routes not transporting goods

**Symptom:** Vehicle picked up cargo but not delivering

**Cause:** Instant delivery might be disabled

**Solution:**
- Wait a few seconds for vehicle to travel
- Check `LogisticsManager.print_logistics_status()` to see vehicle state
- Vehicle should cycle: at_source → traveling → at_destination

### No money from production

**Symptom:** Facilities producing but money not increasing

**Expected Behavior:**
- Barley and malt should NOT generate money (intermediate products)
- Only ale should generate money ($500 per 5 ale)
- Check console for "Sold 5 ale for $500" messages

## 🎯 Advanced Tests

Once the basic chain works, try these:

### Test 1: Multiple Parallel Chains

1. Build 3 Barley Fields
2. Build 3 Grain Mills
3. Build 3 Breweries
4. Create 6 routes connecting them
5. Watch money accumulate faster!

### Test 2: Bottleneck Identification

1. Build 1 Barley Field
2. Build 3 Grain Mills connected to it
3. Note: Mills will compete for barley (only one gets it per cycle)
4. This demonstrates supply constraints

### Test 3: Route Removal (Manual)

1. Remove a route using `LogisticsManager.remove_route("route_1")`
2. Watch downstream facilities run out of inputs
3. See "Production blocked" messages return

## 📈 Expected Economics

**Investment:**
- 1 Barley Field: $500
- 1 Grain Mill: $800
- 1 Brewery: $1,500
- **Total: $2,800**

**Revenue:**
- Ale: $500 per batch (5 ale)
- Cycle time: ~16 seconds (depends on logistics)
- **Revenue rate: ~$1,875/minute**
- **Break-even: ~1.5 minutes**

**Scaling:**
- 3 complete chains: ~$5,625/minute
- 5 complete chains: ~$9,375/minute

## 🎮 Next Steps After Testing

Once the production chain works:

1. Add visual route lines on the map
2. Add vehicle visualization (moving sprites)
3. Add inventory display on facilities
4. Add production progress bars
5. Add market system with dynamic pricing
6. Add construction time for facilities
7. Implement factory interior layer

---

**Report Issues:**
- Production not consuming inputs?
- Routes not creating properly?
- Vehicles not moving?
- Money not updating correctly?

Let me know and we'll debug together!
