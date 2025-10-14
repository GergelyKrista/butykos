# Dual-Layer Gameplay Testing Guide

This guide walks you through testing the dual-layer gameplay system: transitioning between the world map (strategic layer) and factory interiors (tactical layer).

## Prerequisites

- Godot 4.x project with all singleton managers loaded
- `data/facilities.json` with brewery/distillery having `"has_interior": true`
- `data/machines.json` with machine definitions
- Both `world_map.tscn` and `factory_interior.tscn` scenes created

## Test Flow

### Phase 1: Place a Facility with Interior

1. **Run the game** (F5)
   - Should start in world map scene
   - Grid should be visible (50x50)
   - Camera should be centered

2. **Place a Brewery**
   - Click "Build Brewery" button (or trigger placement mode)
   - Move mouse over grid - preview should follow cursor
   - Click to place (2x2 or 3x3 tiles)
   - Facility should appear with sprite placeholders

**Expected Console Output:**
```
WorldMap scene loaded
GameManager: State changed to WORLD_MAP
Placement mode started: Brewery
Facility placed successfully: facility_XXXXX
Factory interior created for facility: facility_XXXXX
```

### Phase 2: Enter Factory Interior

3. **Double-click the Brewery**
   - Double-click on any part of the facility sprite
   - Scene should transition to factory interior

**Alternative:** **Shift+Click the Brewery**
   - Hold Shift and left-click the facility
   - Should also enter factory interior

**Expected Console Output:**
```
Entering factory interior for: facility_XXXXX
GameManager: Entering factory view for: facility_XXXXX
GameManager: State changed to FACTORY_VIEW
FactoryInterior scene loaded
Viewing factory interior for facility: facility_XXXXX
```

**Expected Visual:**
- 20x20 grid displayed
- Camera centered on interior grid
- "Back" button in top-left
- Factory name label showing "Brewery Interior"
- Empty grid ready for machine placement

### Phase 3: Place Machines (Manual Test)

4. **Try placing a machine** (if placement UI exists)
   - Use machine placement mode similar to facility placement
   - Click to place on interior grid

**OR manually trigger via console:**
```gdscript
# Get the active factory interior scene
var factory_interior = get_tree().current_scene
factory_interior.start_placement_mode("mash_tun")
```

**Expected:**
- Machine preview follows cursor
- Placement respects 20x20 grid boundaries
- Machine appears after placement

### Phase 4: Return to World Map

5. **Click the "← Back" button**
   - Should return to world map
   - Brewery should still be there at same position

**Expected Console Output:**
```
Back button clicked
Exiting factory interior: facility_XXXXX
GameManager: Exiting factory view
GameManager: State changed to WORLD_MAP
WorldMap scene loaded
```

### Phase 5: State Persistence

6. **Re-enter the same Brewery**
   - Double-click or Shift+click the brewery again
   - Should enter factory interior

7. **Verify machines persisted**
   - Any machines placed in Phase 3 should still be there
   - Machine positions should match previous placement

**Expected Console Output:**
```
Entering factory interior for: facility_XXXXX
FactoryInterior scene loaded
Machine loaded: machine_XXXXX (mash_tun)
```

### Phase 6: Multiple Facilities

8. **Return to world map**
9. **Place a second Brewery** at a different location
10. **Enter the second Brewery**
    - Should have an empty interior (no machines)
11. **Return to world map**
12. **Enter the first Brewery again**
    - Should still have the machines from Phase 5

**This verifies:**
- Each facility has independent interior state
- FactoryManager correctly tracks multiple interiors
- No state leakage between facilities

## Verification Checklist

### Scene Transitions
- [ ] Double-click enters factory interior
- [ ] Shift+click enters factory interior
- [ ] Back button returns to world map
- [ ] Escape key does NOT exit factory (only cancels placement)
- [ ] World map scene reloads correctly
- [ ] Factory interior scene reloads correctly

### State Persistence
- [ ] Placed machines persist after exiting factory
- [ ] Machine positions remain correct
- [ ] Multiple facilities have independent interior states
- [ ] Facility ID is correctly passed between scenes

### Visual Feedback
- [ ] Factory interior grid renders (20x20)
- [ ] Factory name displays correctly in UI
- [ ] Back button is visible and clickable
- [ ] Camera is properly centered in factory interior
- [ ] Machine sprites/placeholders appear correctly

### GameManager State
- [ ] `GameManager.current_state` changes to FACTORY_VIEW
- [ ] `GameManager.active_factory_id` is set correctly
- [ ] State returns to WORLD_MAP after exiting

## Expected Data Structures

### After placing a machine:
```gdscript
# FactoryManager.factory_interiors structure
{
  "facility_abc123": {
    "facility_id": "facility_abc123",
    "grid": [[...]], # 20x20 array
    "machines": {
      "machine_xyz789": {
        "id": "machine_xyz789",
        "type": "mash_tun",
        "grid_pos": Vector2i(5, 5),
        "world_pos": Vector2(320, 320),
        "size": Vector2i(2, 2),
        "state": "idle",
        "inventory": {},
        "placed_date": {...}
      }
    },
    "created_date": {...}
  }
}
```

## Common Issues

### Issue: "No active factory set!" error
**Symptom:** Factory interior scene loads but shows error
**Cause:** `GameManager.active_factory_id` not set before scene transition
**Fix:** Ensure `GameManager.enter_factory_view(facility_id)` is called before `change_scene_to_file()`

### Issue: Can't enter factory interior
**Symptom:** Clicking facility does nothing
**Cause 1:** Facility doesn't have `"has_interior": true` in facilities.json
**Cause 2:** Click detection not working (Area2D issue)
**Fix:** Check console for "Facility has no interior" message, verify facilities.json

### Issue: Machines don't persist
**Symptom:** Placed machines disappear after exiting
**Cause:** FactoryManager not saving machine placements
**Fix:** Check `FactoryManager.place_machine()` is being called, not just visual creation

### Issue: Wrong factory interior loads
**Symptom:** Entering Brewery A shows Brewery B's machines
**Cause:** `active_factory_id` not properly updated
**Fix:** Verify `GameManager.active_factory_id` before scene transition

## Performance Notes

- Each factory interior creates a 20x20 grid (400 cells)
- Each machine creates visual nodes (Sprite2D, Labels)
- Frequent scene transitions may cause brief loading
- State is kept in memory via FactoryManager (no disk writes yet)

## Next Steps After Testing

Once dual-layer system works:
1. Add machine placement UI/build menu
2. Implement machine production logic (similar to facility production)
3. Add conveyor belt connections between machines
4. Visual feedback for production flow
5. Interior inventory management
6. Input/output nodes connecting to logistics routes

## Debug Commands (Optional)

Add these to factory_interior.gd for testing:
```gdscript
func _unhandled_input(event):
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_M:
            # Quick test: place a mash_tun at cursor
            start_placement_mode("mash_tun")
        elif event.keycode == KEY_F:
            # Quick test: place a fermentation_vat
            start_placement_mode("fermentation_vat")
        elif event.keycode == KEY_P:
            # Print all machines in current factory
            print(FactoryManager.get_all_machines(facility_id))
```
