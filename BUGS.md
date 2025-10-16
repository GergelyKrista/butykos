# Known Bugs & Issues - Alcohol Empire Tycoon

**Last Updated:** 2025-10-16
**Current Branch:** dev
**Phase:** Phase 5 Complete

---

## 🚨 Critical (Fix ASAP)
*Bugs that prevent development or break core gameplay*

- [ ] None currently

---

## ⚠️ High Priority (Fix This Phase)
*Important bugs that affect gameplay but don't block development*

### Isometric Grid System
- [ ] **Temporary 45° rotation** - Current implementation rotates camera/world by 45° instead of true isometric coordinate conversion
  - **Impact:** Mouse input slightly imprecise, sprite artists need proper isometric specs
  - **Fix:** Implement proper cart_to_iso() and iso_to_cart() functions
  - **Planned:** Next development phase after Save/Load system
  - **File:** `systems/world_manager.gd`, `scenes/world_map/world_map.gd`

### Mouse Input
- [ ] **Mouse position offset in rotated view** - Click position doesn't perfectly match grid tile in isometric view
  - **Impact:** Placement feels slightly off, especially for larger facilities
  - **Fix:** Implement proper isometric mouse coordinate conversion
  - **Workaround:** Currently using rotated mouse position, good enough for testing
  - **File:** `scenes/world_map/world_map.gd` (_input function)

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

### Incomplete Systems
- **No save/load functionality** - SaveManager framework exists but not implemented
  - **Status:** Planned for Phase 7A (next major development phase)
  - **Impact:** Can't persist progress between sessions
  - **File:** `core/save_manager.gd`

- **Static product pricing** - All products have fixed prices, no supply/demand
  - **Status:** Planned for Phase 6A (Market System)
  - **Impact:** Limited economic gameplay
  - **File:** `systems/production_manager.gd`

- **No tutorial/onboarding** - New players have to figure out mechanics themselves
  - **Status:** Planned for Phase 7D (Tutorial & Progression)
  - **Impact:** Steep learning curve

- **No multi-input recipes** - All production only uses single input type
  - **Status:** Optional Phase 5C, may be added later
  - **Impact:** Limited production complexity
  - **File:** `data/recipes.json` (currently empty)

- **No facility upgrades** - Can't improve existing facilities
  - **Status:** Planned for Phase 6B (Upgrades & Research)
  - **Impact:** Limited progression mechanics

- **No AI competition** - Player has monopoly on all markets
  - **Status:** Planned for Phase 9A (Competition & Markets)
  - **Impact:** No competitive pressure

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
