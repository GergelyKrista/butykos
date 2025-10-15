# Development Status - Alcohol Empire Tycoon

**Last Updated:** 2025-10-15
**Current Phase:** Dual-Layer MVP Complete - Phase 4B Next
**Target:** 15-18 months to Early Access

## 🎯 Project Vision

OTTD-inspired business tycoon game with dual-layer gameplay:
- **Strategic Layer:** 50x50 world map for facility placement and logistics
- **Tactical Layer:** 20x20 factory interiors for machine placement and optimization
- **Theme:** Alcohol production empire (beer, spirits, etc.)

## ✅ Completed Features

### Core Architecture (Phase 0) - 100% Complete
- [x] Project structure and folder organization
- [x] Singleton autoload managers (EventBus, GameManager, SaveManager, DataManager)
- [x] Signal-based communication system (40+ signals)
- [x] Data-driven design with JSON configuration
- [x] Comprehensive documentation (ARCHITECTURE.md, TROUBLESHOOTING.md, etc.)

### System Managers - 90% Complete

| Manager | Status | Description |
|---------|--------|-------------|
| **EventBus** | ✅ | Signal hub for decoupled system communication |
| **GameManager** | ✅ | Game state, time, scene transitions, factory tracking |
| **DataManager** | ✅ | JSON loading with helper methods for filtering |
| **SaveManager** | 🟡 | Framework created, not fully implemented |
| **WorldManager** | ✅ | 50x50 grid management, coordinate conversion |
| **EconomyManager** | ✅ | Money tracking, transactions, purchase/refund |
| **ProductionManager** | ✅ | Input-based production cycles, inventory management |
| **LogisticsManager** | ✅ | Routes, vehicles, automatic cargo transport |
| **FactoryManager** | ✅ | Factory interior state tracking, machine placement |

### World Map Layer (Strategic) - 95% Complete
- [x] 50x50 grid rendering with visual feedback
- [x] Camera controls (pan, zoom)
- [x] Multi-tile facility placement system (2x2, 3x3)
- [x] Sprite-based facility visuals (ready for asset replacement)
- [x] Area2D click detection for reliable facility selection
- [x] Placement preview with validity checking (green/red)
- [x] Build menu UI with dynamic buttons
- [x] Money display with real-time updates
- [x] Facility visual representation with labels
- [ ] Additional facility types (only 3 exist)
- [ ] Visual polish and animations

### Production Chain System - 90% Complete
- [x] Input-based production (requires raw materials)
- [x] Intermediate products (barley, malt) stay in inventory
- [x] Final products (ale, whiskey) auto-sell for profit
- [x] Facility inventory management per building
- [x] Production cycle timing and progress tracking
- [x] 3-stage chain: Barley Field → Grain Mill → Brewery
- [x] Console logging for debugging production flow
- [ ] Visual production indicators
- [ ] Advanced recipes with multiple inputs

### Logistics System - 85% Complete
- [x] Route creation between facilities
- [x] Vehicle spawning and management
- [x] Automatic cargo pickup and delivery
- [x] Vehicle state machine (at_source → traveling → at_destination)
- [x] Two-click route creation UI
- [x] Visual facility highlighting during route mode
- [x] Product compatibility checking for routes
- [x] Instant delivery mode for testing
- [ ] Visual route lines on map
- [ ] Vehicle visuals and animations
- [ ] Multiple vehicles per route

### Factory Interior Layer (Tactical) - 60% Complete ⭐ NEW
- [x] FactoryManager with 20x20 interior grid per facility
- [x] Factory interior scene with grid renderer
- [x] Machine placement system (similar to facilities)
- [x] Machine data definitions (machines.json with 12 types)
- [x] Scene transitions (double-click or Shift+click facility)
- [x] Back button navigation to world map
- [x] State persistence across layer transitions
- [x] Independent interior state per facility
- [x] Machine visual placeholders (ready for sprites)
- [x] Interior camera and UI system
- [ ] Machine placement UI/build menu
- [ ] Machine production logic
- [ ] Interior logistics (conveyor belts)
- [ ] Input/output nodes for facility connection
- [ ] Visual production flow

### Data Configuration - 70% Complete

| File | Status | Contents |
|------|--------|----------|
| `facilities.json` | ✅ | 3 facility types with production chains |
| `machines.json` | ✅ | 12 machine types (mash tun, fermentation vat, etc.) |
| `products.json` | ⬜ | Placeholder for future expansion |
| `recipes.json` | ⬜ | Placeholder for future expansion |

## 🎮 Current Playable Game Loop

### What You Can Do Now
1. ✅ Place Barley Field on world map → produces barley every 5s
2. ✅ Place Grain Mill → waits for barley input
3. ✅ Create route from Field to Mill → vehicle transports barley
4. ✅ Mill converts barley to malt every 3s
5. ✅ Place Brewery → waits for malt input
6. ✅ Create route from Mill to Brewery → vehicle transports malt
7. ✅ Brewery converts malt to ale → auto-sells for profit
8. ✅ **NEW:** Double-click Brewery to enter interior
9. ✅ **NEW:** See 20x20 grid with placed machines
10. ✅ **NEW:** Click back button to return to world map
11. ✅ Money accumulates, build more facilities

### What's Being Tested
- Scene transitions between layers
- State persistence for multiple factories
- Machine placement (manual testing needed)
- Dual-layer workflow

## 📋 Next Steps (Priority Order)

### Phase 4A: Testing & Validation (Current)
1. **Test dual-layer gameplay loop** (use DUAL_LAYER_TEST.md)
   - Verify scene transitions
   - Check state persistence
   - Test with multiple factories
   - Identify any bugs or issues

### Phase 4B: Machine Production (1-2 sessions)
2. **Add machine placement UI**
   - Build menu in factory interior
   - Filter machines by category
   - Show costs and requirements

3. **Connect machine production to facility**
   - Machines process materials
   - Machine inventory feeds facility output
   - Production efficiency based on layout

### Phase 4C: Interior Logistics (2-3 sessions) ✅ COMPLETE
4. ✅ **Manual connection system**
   - Click-to-connect machines (no adjacency required)
   - Visual connection lines with arrows
   - Input/Output nodes use connections
   - Flexible factory layouts

### Phase 4D: Early Game Economy (1 session) ⭐ NEW - HIGH PRIORITY
5. **Raw material selling for bootstrap income**
   - Add "Market Outlet" machine type (low cost: $50-100)
   - Sells intermediate products for reduced profit:
     - Barley: $5 per unit (vs. ale at $100)
     - Malt: $15 per unit
     - Mash: $20 per unit
     - Fermented wash: $40 per unit
   - Allows players to generate income before affording expensive machines
   - Optional: Add to world map as "Trading Post" facility
   - Balancing: Raw sales should be less profitable than finished products

   **Design Goal:** Players can place cheap Market Outlet to sell barley/malt early, generate $200-500, then invest in Fermentation Vat ($500) or Bottling Line ($600)

### Phase 4E: Logistics Visualization (1-2 sessions)
6. **Visual route lines on world map**
   - Draw lines/paths between connected facilities
   - Show route direction (arrows or flow indicators)
   - Color-code by product type or efficiency
   - Highlight routes on hover/selection

7. **Vehicle visuals and animations**
   - Add vehicle sprites (trucks, carts, etc.)
   - Animate vehicles moving along routes
   - Show cargo type on vehicles
   - Vehicle speed based on distance/efficiency

8. **Route statistics and feedback**
   - Display cargo flow rate per route
   - Show route congestion/bottlenecks
   - Efficiency indicators
   - Route management UI (pause, delete, assign vehicles)

### Phase 5: Content Expansion (3-5 sessions)
9. **Additional facilities**
   - Distillery (whiskey production)
   - Wheat farm (alternative grain)
   - Packaging facilities
   - Storage warehouses

10. **More machines**
   - Distillation columns
   - Aging barrels
   - Bottling lines
   - Quality control stations

### Phase 6: Economic Depth (5-7 sessions)
11. **Market system**
   - Dynamic pricing
   - Supply and demand
   - Market trends

12. **Upgrades and research**
   - Facility upgrades
   - Machine efficiency improvements
   - Unlock new recipes

### Phase 7: Polish & Systems (7-10 sessions)
13. **Save/Load system**
    - Complete SaveManager implementation
    - JSON save file format
    - Autosave functionality

14. **Visual improvements**
    - Replace placeholder sprites
    - Production animations
    - UI polish and tooltips

15. **Tutorial and progression**
    - Onboarding for new players
    - Unlock progression
    - Achievement system

## 📊 Development Progress by System

### Core Systems: 90% Complete
- ✅ EventBus
- ✅ GameManager
- ✅ DataManager
- ✅ WorldManager
- ✅ EconomyManager
- ✅ ProductionManager
- ✅ LogisticsManager
- ✅ FactoryManager
- 🟡 SaveManager (framework only)

### World Map Layer: 95% Complete
- ✅ Grid and camera
- ✅ Facility placement
- ✅ Route creation
- ✅ Production visualization
- 🟡 Visual polish needed
- 🟡 More facility variety

### Factory Interior Layer: 60% Complete
- ✅ Scene structure
- ✅ Grid rendering
- ✅ Machine placement
- ✅ State persistence
- ⬜ Machine production
- ⬜ Interior logistics
- ⬜ UI/UX polish

### Content: 30% Complete
- ✅ 3 facility types
- ✅ 12 machine types
- ✅ 1 complete production chain
- ⬜ Additional chains
- ⬜ Variety of recipes
- ⬜ Research/upgrades

## 📁 Key Files Reference

### Managers (core/ and systems/)
- `core/event_bus.gd` - Signal hub
- `core/game_manager.gd` - Game state, `active_factory_id` for transitions
- `core/data_manager.gd` - JSON loading, `get_machine_data()`, filtering
- `systems/world_manager.gd` - 50x50 grid, facility placement
- `systems/economy_manager.gd` - Money and costs
- `systems/production_manager.gd` - Input-based production
- `systems/logistics_manager.gd` - Routes and vehicles
- `systems/factory_manager.gd` - 20x20 interiors, machine placement

### Scenes
- `scenes/world_map/world_map.tscn/.gd` - Strategic layer
- `scenes/world_map/grid_renderer.gd` - 50x50 grid drawing
- `scenes/factory_interior/factory_interior.tscn/.gd` - Tactical layer
- `scenes/factory_interior/factory_interior_grid_renderer.gd` - 20x20 grid
- `scenes/factory_interior/factory_interior_ui.gd` - Back button, labels

### Data
- `data/facilities.json` - Barley Field, Grain Mill, Brewery
- `data/machines.json` - 12 machine types for interiors

### Documentation
- `ARCHITECTURE.md` - System design overview
- `TESTING_GUIDE.md` - Production chain testing (outdated)
- `SPRITE_ASSET_GUIDE.md` - How to replace placeholder sprites
- `TROUBLESHOOTING.md` - Common issues (autoload not recognized, etc.)
- `DUAL_LAYER_TEST.md` - Factory interior testing guide ⭐ NEW
- `DEVELOPMENT_STATUS.md` - This file ⭐ UPDATED

## 🐛 Known Issues & Limitations

### Current Limitations
- No machine placement UI in factory interior (manual testing only)
- Machine production not connected to facility output yet
- No visual feedback for route lines between facilities
- Camera zoom controls not implemented
- No vehicle visuals (invisible transport)

### Design Decisions Pending
- Should machines produce independently or feed facility?
- Interior logistics: automatic or player-designed?
- Input/output node positions: fixed or player-placed?
- Quality system: percentage bonuses or discrete tiers?

### Fixed Issues (Historical)
- ✅ Autoload singletons not recognized → restart Godot
- ✅ Route creation click detection → replaced with Area2D
- ✅ Facilities auto-selling all products → only final products now

## 🚀 Performance Considerations

### Current Performance
- 50x50 world grid: Efficient (line drawing only)
- Facility rendering: Lightweight (Image.fill placeholders)
- Production cycles: Efficient (dict lookups)
- Scene transitions: Brief load time (<1 second)

### Future Optimization Opportunities
- Object pooling for vehicles
- Occlusion culling for off-screen facilities
- Batch rendering for grid lines
- Lazy loading of factory interiors
- Spatial partitioning for large facility counts

## 📈 Milestone Progress

### Milestone 1: Dual-Layer MVP ✅ COMPLETE (Current)
- ✅ World map with facility placement
- ✅ Production chain with input requirements
- ✅ Logistics with automatic transport
- ✅ Factory interior with machine placement
- ✅ Scene transitions and state persistence
- 🔄 **Testing in progress**

### Milestone 2: Interior Production ✅ 90% COMPLETE (Next, 2-3 weeks)
- [x] Machine production logic
- [x] Interior logistics (manual connections)
- [x] Machine build menu UI
- [x] Input/output nodes
- [ ] ⭐ **Early game economy fix (bootstrap income)**
- [ ] Production efficiency system

### Milestone 3: Content Expansion (4-6 weeks)
- [ ] 5+ new facility types
- [ ] 20+ new machine types
- [ ] Multiple production chains
- [ ] Recipe variety

### Milestone 4: Economic Depth (7-10 weeks)
- [ ] Market system with pricing
- [ ] Research and upgrades
- [ ] Facility maintenance costs
- [ ] Quality and efficiency mechanics

### Milestone 5: Polish & Systems (11-15 weeks)
- [ ] Save/Load implementation
- [ ] Visual improvements
- [ ] UI/UX polish
- [ ] Tutorial and progression
- [ ] Performance optimization

### Milestone 6: Early Access Prep (16-20 weeks)
- [ ] Content balancing
- [ ] Bug fixing and testing
- [ ] Settings and options
- [ ] Documentation and guides
- [ ] Steam page preparation

## 🎯 Session Summary

### What Was Just Completed (This Session)
1. ✅ **Manual connection system** - Click-to-connect machines (no adjacency!)
2. ✅ Visual connection lines with directional arrows
3. ✅ Input/Output nodes updated to use manual connections
4. ✅ "Connect Machines" button in factory interior UI
5. ✅ Full machine production chain working with connections
6. ✅ **Identified critical issue:** Early game economy needs bootstrap income
7. ✅ Added Phase 4D: Early Game Economy to roadmap

### Previously Completed (Earlier Sessions)
- ✅ Dual-layer factory interior system
- ✅ Machine placement and production logic
- ✅ Machine inventory system (per-machine, not shared)
- ✅ Isometric grid rendering with diamond tiles
- ✅ Scene transition system
- ✅ State persistence across layers

### Next Focus (HIGH PRIORITY)
- **Phase 4D: Early Game Economy** - Market Outlet for selling raw materials
  - Allows players to bootstrap income before expensive machines
  - Critical gameplay issue discovered during testing
- Phase 4E: Logistics visualization (route lines, vehicles)
- Phase 5: Content expansion (more facilities, machines)

## 📝 Notes

### Development Philosophy
- **Incremental development:** Build minimal features, test thoroughly, iterate
- **Data-driven design:** JSON for all gameplay configuration and balancing
- **Signal-based communication:** Loose coupling via EventBus
- **Performance-first:** Target smooth gameplay even with many facilities

### Technical Patterns Used
- Singleton autoloads for global state management
- Signal-based events via EventBus
- Multi-tile grid with occupation tracking
- Area2D for reliable click detection
- Sprite2D with programmatic textures (easy asset replacement)
- Scene state persistence via dedicated manager classes

### User Feedback Integration
- ✅ Multi-tile facilities preferred over single-tile
- ✅ Sprite-based system for easy asset replacement
- ✅ Conveyor belts planned for Phase 4C
- ✅ Dual-layer system (strategic + tactical) implemented
- 🔄 Visual route lines and vehicles planned for Phase 4D

### Git History
```
6030fce Add testing guide and development status documentation
c1becef Add complete world map scene and production simulation
aa90f3d Add WorldManager, EconomyManager, and facility data system
54a7687 Add core singleton manager autoloads
ef4b153 Create project folder structure and documentation
```

## 🎓 Learning Resources

For understanding the codebase:
- Start with `ARCHITECTURE.md` for system overview
- Read `TESTING_GUIDE.md` to understand production flow
- Check `SPRITE_ASSET_GUIDE.md` for visual asset integration
- Use `TROUBLESHOOTING.md` if you encounter issues
- Follow `DUAL_LAYER_TEST.md` to test factory interiors

---

**Status:** Dual-layer MVP complete! Ready for comprehensive testing. Next focus: machine production logic and interior logistics.

**Recommended Next Action:** Run through DUAL_LAYER_TEST.md and report findings.
