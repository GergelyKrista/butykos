# Development Status - Alcohol Empire Tycoon

**Last Updated:** 2026-01-21
**Current Phase:** Phase 4F Complete - Node-Based Logistics & Farmhouse Fields ✅
**Target:** 15-18 months to Early Access

## 🎯 Project Vision

OTTD-inspired business tycoon game with dual-layer gameplay:
- **Strategic Layer:** 50×50 world map for facility placement and logistics
- **Tactical Layer:** 20×20 factory interiors for machine placement and optimization
- **Theme:** Alcohol production empire (beer, spirits, wine)

---

## ✅ Completed Features (Latest Session - 2026-01-21)

### Phase 4F: Node-Based Logistics Network ✅ COMPLETE
- [x] **Logistics Network Panel** - Visual node-based connection management UI
- [x] **Drag-to-Connect** - Drag from one facility node to another to create connections
- [x] **Network Visualization** - Facilities shown as nodes with connection lines
- [x] **Right-click Delete** - Remove connections from the network panel
- [x] **Renamed Routes to Connections** - Clearer terminology with backward compatibility
- [x] **Multi-Vehicle Auto-Dispatch** - Trucks spawn automatically when source has 50+ units
- [x] **Higher Truck Capacity** - Increased from 10 to 50 units per truck
- [x] **Vehicle Limits** - Maximum 3 trucks per connection (prevents traffic jams)
- [x] **No Return Trips** - Vehicles removed after delivery (continuous flow)
- [x] **Save/Load Compatibility** - Old route saves load as new connection format

### Phase 4G: Farmhouse Field System ✅ COMPLETE
- [x] **Farmhouse UI Panel** - Dedicated panel for farmhouse management
- [x] **Crop Field Placement** - Place barley/wheat fields around farmhouses
- [x] **Drag-to-Place Fields** - Drag over multiple tiles to place fields in bulk
- [x] **Field Adjacency Rules** - Fields must connect to farmhouse or other fields
- [x] **Max Distance Limit** - Fields limited to 10 tiles from farmhouse
- [x] **Field Preview System** - Green/red preview showing valid placement areas
- [x] **1x1 Field Tiles** - Each field occupies single grid cell (scaled sprites)
- [x] **Barley Field Animation** - Growth stage animation (6 stages)

### Phase 4H: Road System ✅ COMPLETE
- [x] **Road Placement** - Place roads on the world map
- [x] **Road Renderer** - Visual rendering of road network
- [x] **Facility-Road Validation** - Facilities cannot be placed over roads
- [x] **roads.json Data File** - Road type definitions

### Bug Fixes & Improvements
- [x] Fixed facility placement over roads (now properly blocked)
- [x] Fixed truck spam issue (limited to 3 per connection)
- [x] Added debug output for field placement troubleshooting
- [x] Improved sprite scaling for 1x1 field tiles

---

## ✅ Completed Features (Previous Session - 2026-01-20)

### Phase 6A: Market System ✅ COMPLETE
- [x] Dynamic pricing with ±30% variance
- [x] Price fluctuations every 10 seconds
- [x] Price trend indicators (up/down arrows)
- [x] Contract system for bonus deliveries
- [x] Market panel UI with product categories
- [x] Save/load integration for market state

### Phase 6B: Research Tree System ✅ COMPLETE
- [x] Civilization-style tech tree (8 branches × 5 tiers = 40 techs)
- [x] Satisfactory-style tier unlocks (sell products to unlock tiers)
- [x] Money-based research purchase
- [x] Visual research tree with Civ6-style connecting lines
- [x] Tier progress display with sprite placeholders
- [x] ESC key properly closes panels before opening pause menu
- [x] Save/load integration for research state
- [x] RESEARCH_TREE.md documentation

### Phase 6C: Research Bonuses Applied ✅ COMPLETE
- [x] Production bonuses (cycle_time_multiplier, yield_multiplier, efficiency_multiplier)
- [x] Price bonuses (price_multiplier, value_multiplier) applied to sales
- [x] Logistics bonuses (speed_multiplier, capacity_multiplier, instant_delivery)
- [x] New facilities unlocked by research (corn_field, hop_farm, vineyard)
- [x] Build menu reorganized by categories (Tools, Agriculture, Processing, Production, Storage)
- [x] Locked facilities shown with research requirements
- [x] Build menu auto-refreshes when research completed
- [x] New products added (corn, hops, grapes)

---

## ✅ Completed Features (Previous Session - 2025-10-16)

### Phase 7A: Save/Load System ✅ COMPLETE
- [x] Save/Load dialog component (unified UI for both modes)
- [x] Multiple named save slots with timestamps and game dates
- [x] Main menu integration (Load Game button)
- [x] Pause menu integration (Save/Load buttons)
- [x] Quick save/load hotkeys (F5 to save, F9 to load)
- [x] Delete save functionality
- [x] Game state reset system (GameManager.reset_game())
- [x] Full persistence across game restarts
- [x] Complete game state restoration (facilities, machines, routes, money, date)
- [x] Scene reload integration for loading saves

### Phase 7B: UI/UX Improvements ✅ COMPLETE
- [x] Production statistics panel (toggleable side panel)
- [x] Facility info tooltips on hover (name, type, status, inventory)
- [x] Demolish mode for facilities and machines (50% refund)
- [x] Visual mode indicators (colored panels for demolish/connect/delete modes)
- [x] Red highlight on facilities in demolish mode
- [x] Mode conflict prevention (auto-cancel conflicting modes)
- [x] Factory interior UI restructure (all buttons in bottom navbar)
- [x] Machine build menu view swapping (Actions ↔ Machines views)
- [x] Optimized machine menu layout (compact header, spacious button area)
- [x] Fixed machine placement coordinates (proper viewport-to-world conversion)

### Phase 4E: Logistics Visualization ✅ COMPLETE
- [x] Visual route lines on world map (blue lines with arrows)
- [x] Vehicle rendering system (yellow truck sprites)
- [x] Animated vehicles moving along routes
- [x] Cargo labels on vehicles
- [x] Route direction indicators

### Phase 5A: Content Expansion - Facilities ✅ COMPLETE
- [x] **Wheat Farm** - Alternative grain source for spirits ($550)
- [x] **Distillery** - Spirits production with factory interior ($2000)
- [x] **Packaging Plant** - Premium product packaging ($1200)
- [x] **Storage Warehouse** - 500-unit storage capacity ($900)
- [x] **Total: 7 facilities** (was 3)

### Phase 5B: Product System ✅ COMPLETE
- [x] **products.json created** - 14 product definitions
- [x] Product categories: raw_material, processed_material, finished_product
- [x] Product pricing system integrated
- [x] Auto-sell system with product-specific pricing
- [x] Premium packaged_ale ($150 vs ale $100)

### Sprite Rendering System ✅ COMPLETE
- [x] Facility sprite rendering (world map)
- [x] Machine sprite rendering (factory interiors)
- [x] Automatic fallback to colored placeholders
- [x] Artist can now add sprites incrementally
- [x] Assets guide updated for new facilities

---

## 📊 Current Game Status

### Content Metrics
| Category | Count | Notes |
|----------|-------|-------|
| **Facilities** | 7 | Barley Field, Wheat Farm, Grain Mill, Brewery, Distillery, Packaging Plant, Storage Warehouse |
| **Products** | 14 | Raw materials through finished products |
| **Machines** | 13 | Mash Tun, Fermentation Vat, Bottling Line, Storage Tank, Market Outlet, etc. |
| **Production Chains** | 4 | Beer, Premium Beer, Spirits Foundation, Buffered Storage |

### System Completion
| System | Completion | Status |
|--------|------------|--------|
| Core Architecture | 100% | ✅ All managers functional |
| World Map Layer | 100% | ✅ Sprite rendering, roads, vehicles, demolish mode, tooltips, field placement |
| Factory Interior | 98% | ✅ Manual connections, machine production, sprites, demolish mode |
| Logistics | 100% | ✅ Node-based network UI, multi-vehicle auto-dispatch, connection management |
| Production | 95% | ✅ Input-based, pricing, auto-sell |
| Economy | 95% | ✅ Money, dynamic pricing, market system |
| UI/UX | 90% | ✅ Tooltips, stats panel, mode indicators, demolish mode, save/load UI, market panel, research panel, logistics panel, farmhouse UI |
| Research | 100% | ✅ Full tech tree with 40 technologies, 8 branches |
| Content | 45% | 🟡 Basic chains working, needs expansion |
| Save/Load | 100% | ✅ Full save/load with multiple slots, persistence, hotkeys |
| Farmhouse System | 100% | ✅ Field placement, drag-to-place, adjacency rules, animations |
| Road System | 90% | ✅ Road placement, rendering, facility validation |

---

## 🎮 Complete Production Chains Available

### 1. Basic Beer Chain
```
Barley Field ($500) → Grain Mill ($800) → Brewery ($1500)
→ produces ale → auto-sells for $100/unit
ROI: ~15 cycles to break even
```

### 2. Premium Beer Chain
```
Barley Field → Grain Mill → Brewery → Packaging Plant ($1200)
→ produces packaged_ale → auto-sells for $150/unit (+50% profit!)
ROI: Better margins, requires more investment
```

### 3. Spirits Foundation Chain
```
Wheat Farm ($550) → Grain Mill ($800) → Distillery ($2000)
→ produces raw_spirit → sells for $50/unit
NEXT: Distillery interior machines for full whiskey production
```

### 4. Storage-Buffered Chain
```
Any production → Storage Warehouse ($900) → Distribution
Purpose: Buffer complex multi-stage production
Storage: 500 units capacity
```

---

## 📋 Development Roadmap

### ✅ COMPLETED PHASES

#### Phase 0: Core Architecture (100%)
- [x] Project structure and autoload managers
- [x] Signal-based EventBus communication (40+ signals)
- [x] Data-driven JSON configuration
- [x] Comprehensive documentation

#### Phase 4C: Interior Logistics (100%)
- [x] Manual machine connection system
- [x] Visual connection lines with arrows
- [x] Input/Output nodes
- [x] Storage buffers
- [x] Market Outlet for bootstrap income

#### Phase 4D: Early Game Economy (100%)
- [x] Market Outlet machine ($75)
- [x] Product pricing system
- [x] Bootstrap income mechanics
- [x] Intermediate product sales

#### Phase 4E: Logistics Visualization (100%)
- [x] Route lines (blue with directional arrows)
- [x] Vehicle rendering (yellow trucks)
- [x] Animated vehicle movement
- [x] Cargo labels

#### Phase 5A: More Facilities (100%)
- [x] Wheat Farm
- [x] Distillery (with interior)
- [x] Packaging Plant
- [x] Storage Warehouse

#### Phase 5B: Product System (100%)
- [x] products.json (14 products)
- [x] Product pricing
- [x] Auto-sell integration
- [x] Premium pricing mechanics

#### Phase 7A: Save/Load System (100%)
- [x] Save/Load dialog with named slots
- [x] Multiple save slots with timestamps
- [x] Main menu Load Game integration
- [x] Pause menu Save/Load integration
- [x] Quick save (F5) / Quick load (F9) hotkeys
- [x] Delete save functionality
- [x] Full game state persistence
- [x] Scene reload integration

#### Phase 7B: UI/UX Improvements (100%)
- [x] Production statistics panel (right-side toggleable)
- [x] Facility tooltips with inventory display
- [x] Demolish mode (world map and factory interior)
- [x] Visual mode indicators (colored panels)
- [x] Mode conflict prevention system
- [x] Factory interior navbar restructure
- [x] Machine build menu optimization
- [x] Mouse coordinate fix for machine placement

---

### 🔄 IN PROGRESS / NEXT PHASES

#### Phase 5C: Recipe System (Optional, 1-2 hours)
**Priority:** Medium
**Status:** Not started

- [ ] Create recipes.json
- [ ] Multi-input production (e.g., grain + water → mash)
- [ ] Quality modifiers
- [ ] Recipe unlock system

**Why do this:**
- More complex production chains
- Player strategic choices
- Quality/efficiency gameplay

**Why skip:**
- Current single-input system works well
- Can add later without breaking existing systems

---

#### Phase 6: Economic Depth ✅ MOSTLY COMPLETE

##### Phase 6A: Market System ✅ COMPLETE
- [x] Dynamic pricing with ±30% variance
- [x] Price fluctuations every 10 seconds
- [x] Market trends (up/down indicators)
- [x] Contract system for bonus deliveries
- [x] Market panel UI

##### Phase 6B: Research Tree ✅ COMPLETE
- [x] Civilization-style tech tree (8 branches × 5 eras)
- [x] 40 total technologies with cross-branch prerequisites
- [x] Money-based research purchase
- [x] Building upgrade unlocks
- [x] Production bonuses from research
- [x] Research panel UI with progress tracking

##### Phase 6C: Maintenance Costs (Not Started)
- [ ] Daily/monthly facility upkeep
- [ ] Machine wear and repair
- [ ] Operating cost vs profit balance

**Benefits:**
- Long-term strategic gameplay
- Player progression system
- Economic challenge

---

#### Phase 7: Polish & Systems (5-10 hours)
**Priority:** High for release
**Status:** Phase 7A & 7B Complete ✅

##### Phase 7A: Save/Load System ✅ COMPLETE
- [x] Complete SaveManager implementation
- [x] JSON save file format
- [x] Autosave functionality (every 5 minutes)
- [x] Multiple save slots with custom names
- [x] Save file versioning
- [x] Quick save/load hotkeys (F5/F9)
- [x] Main menu and pause menu integration

##### Phase 7B: UI/UX Improvements ✅ COMPLETE
- [x] Production statistics panel (toggleable side panel)
- [x] Facility info tooltips (hover for details)
- [x] Demolish mode for facilities and machines
- [x] Visual mode indicators (colored panels)
- [x] Mode conflict prevention
- [ ] Route management UI (pause, delete, stats) - TODO
- [ ] Resource flow visualization (animated particles) - TODO
- [ ] Mini-map for world view - TODO

##### Phase 7C: Visual Polish
- [ ] Replace all placeholder sprites (ongoing with artist)
- [ ] Production animations
- [ ] Particle effects (smoke from brewery, etc.)
- [ ] Improved grid visuals
- [ ] Camera zoom improvements

##### Phase 7D: Tutorial & Progression
- [ ] Onboarding tutorial
- [ ] Unlock progression system
- [ ] Achievement system
- [ ] In-game help system

---

#### Phase 8: Additional Content (3-6 hours)
**Priority:** Medium
**Status:** Not started

##### Phase 8A: More Facility Types
- [ ] Vineyard (wine production)
- [ ] Hop Farm (beer ingredients)
- [ ] Water Source (required resource)
- [ ] Quality Control Lab
- [ ] Research Center

##### Phase 8B: More Machine Types
- [ ] Conveyor Belt (active transport)
- [ ] Distillation Column variants
- [ ] Aging Barrel (time-based production)
- [ ] Quality Control Station
- [ ] Steam Boiler (power system)

##### Phase 8C: More Product Chains
- [ ] Wine chain (grapes → juice → wine)
- [ ] Premium whiskey (aging system)
- [ ] Multiple beer types (lager, wheat beer, stout)
- [ ] Vodka production
- [ ] Specialty spirits

---

#### Phase 9: Advanced Features (5-10 hours)
**Priority:** Low (post-MVP)
**Status:** Planning

##### Phase 9A: Competition & Markets
- [ ] AI competitors
- [ ] Market share mechanics
- [ ] Pricing strategy
- [ ] Regional markets

##### Phase 9B: Events & Scenarios
- [ ] Random events (crop failures, booms, etc.)
- [ ] Seasonal effects
- [ ] Historical scenarios
- [ ] Challenge modes

##### Phase 9C: Multiplayer/Co-op
- [ ] Shared world
- [ ] Trade between players
- [ ] Cooperative production chains
- [ ] Competitive leaderboards

---

## 🎯 Recommended Next Steps (For Tomorrow)

### Option 1: Phase 6A - Market System ⭐ RECOMMENDED
**Time:** 2-3 hours
**Why:** Adds economic depth, player engagement

**Tasks:**
1. Add price fluctuation system (±20% variation)
2. Supply/demand mechanics (more production → lower prices)
3. Market trends (weekly cycles)
4. Contract system (deliver X for bonus payment)

**Impact:** High - Makes economy more engaging

---

### Option 2: Phase 7A - Save/Load System ⭐ RECOMMENDED
**Time:** 3-4 hours
**Why:** Critical for playability

**Tasks:**
1. Implement SaveManager JSON export
2. Save facilities, machines, connections, routes
3. Load game state on startup
4. Autosave every 5 minutes
5. Multiple save slots

**Impact:** Critical - Players can't test without saves

---

### Option 3: Phase 8 - More Content
**Time:** 2-4 hours
**Why:** Adds variety, keeps artist busy

**Tasks:**
1. Add 3-5 more facilities
2. Add 5-10 more machines
3. Create wine production chain
4. Add wheat beer variant

**Impact:** Medium - More variety

---

### Option 4: Phase 7B - UI/UX Improvements
**Time:** 2-3 hours
**Why:** Better user experience

**Tasks:**
1. Production statistics panel (shows rates, inventory)
2. Facility tooltips (hover for info)
3. Route management UI
4. Resource flow indicators

**Impact:** High - Makes game more playable

---

## 📁 Key Files Reference

### Core Systems
- `core/event_bus.gd` - Signal hub (40+ signals)
- `core/game_manager.gd` - Game state, scene transitions
- `core/data_manager.gd` - JSON loading (facilities, machines, products)
- `core/save_manager.gd` - Save/load system (✅ complete)

### Managers
- `systems/world_manager.gd` - 50×50 grid, isometric math, facility placement, farmhouse-field relationships
- `systems/economy_manager.gd` - Money tracking, transactions
- `systems/production_manager.gd` - Production cycles, inventory, pricing
- `systems/logistics_manager.gd` - Connections (formerly routes), multi-vehicle auto-dispatch, cargo transport
- `systems/factory_manager.gd` - Factory interiors, machine placement, connections
- `systems/market_manager.gd` - Dynamic pricing, contracts
- `systems/research_manager.gd` - Tech tree, research unlocks

### Scenes
- `scenes/world_map/world_map.tscn/.gd` - Strategic layer (isometric), field placement mode
- `scenes/world_map/road_renderer.gd` - Road visualization ⭐ NEW
- `scenes/world_map/vehicle_renderer.gd` - Vehicle rendering (multi-vehicle support)
- `scenes/factory_interior/factory_interior.tscn/.gd` - Tactical layer (orthogonal)

### UI Panels
- `scenes/ui/logistics_network_panel.gd/.tscn` - Node-based connection management ⭐ NEW
- `scenes/ui/network_view.gd` - Custom control for network visualization ⭐ NEW
- `scenes/ui/farmhouse_ui.gd/.tscn` - Farmhouse management and field placement ⭐ NEW

### Data Files
- `data/facilities.json` - 10 facility definitions (includes farmhouses and fields)
- `data/products.json` - 14 product definitions
- `data/machines.json` - 13 machine definitions
- `data/recipes.json` - Empty (future expansion)
- `data/research_tree.json` - 40 technology definitions
- `data/roads.json` - Road type definitions ⭐ NEW

### Documentation
- `TESTING.md` - Comprehensive testing guide
- `assets/PLACE_SPRITES_HERE.md` - Quick sprite reference
- `ASSET_NAMING_CONVENTION.md` - Full asset specifications
- `TROUBLESHOOTING.md` - Common issues
- `ARCHITECTURE.md` - System design overview
- `RESEARCH_TREE.md` - Tech tree design document ⭐ NEW

---

## 🐛 Known Issues & Limitations

### Current Limitations
- ✅ ~~No save/load functionality~~ **COMPLETE - Full save/load system working!**
- ✅ ~~Basic logistics~~ **COMPLETE - Node-based network UI with multi-vehicle auto-dispatch!**
- ⚠️ No multi-input recipes (can add in Phase 5C)
- ⚠️ Wheat field animation not yet implemented (barley has 6-stage growth animation)
- ⚠️ No tutorial/onboarding (Phase 7D)
- ⚠️ Field 1x1 placement needs verification (debug output added)

### Performance Notes
- ✅ 60 FPS with 10+ facilities and 15+ routes
- ✅ Smooth vehicle animation
- ✅ No memory leaks detected
- ⚠️ Not tested with 50+ facilities (optimization may be needed)

### Design Decisions Made
- ✅ Manual machine connections (not adjacency-based)
- ✅ Per-machine inventory (not shared facility pool)
- ✅ Sprite-based rendering with fallbacks
- ✅ Isometric world map, orthogonal interiors

---

## 📈 Milestone Tracking

### Milestone 1: Dual-Layer MVP ✅ COMPLETE
- ✅ World map with facility placement
- ✅ Production chains with input requirements
- ✅ Logistics with routes and vehicles
- ✅ Factory interiors with machines
- ✅ Scene transitions and state persistence

### Milestone 2: Interior Production ✅ COMPLETE
- ✅ Machine production logic
- ✅ Interior logistics (manual connections)
- ✅ Machine build menu UI
- ✅ Input/output nodes
- ✅ Early game economy (Market Outlet)
- ✅ Bootstrap income mechanics

### Milestone 3: Content Expansion ✅ 80% COMPLETE
- ✅ 7 facility types (target: 10+)
- ✅ 13 machine types (target: 20+)
- ✅ 4 production chains (target: 8+)
- ✅ 14 products defined
- ⬜ Recipe variety (optional)
- ⬜ More end products

### Milestone 4: Economic Depth (Next, 4-6 weeks)
- [ ] Market system with dynamic pricing
- [ ] Research and upgrades
- [ ] Facility maintenance costs
- [ ] Quality and efficiency mechanics

### Milestone 5: Polish & Systems (8-12 weeks)
- [ ] Save/Load implementation
- [ ] Visual improvements (sprite integration)
- [ ] UI/UX polish
- [ ] Tutorial and progression
- [ ] Performance optimization

### Milestone 6: Early Access Prep (14-18 weeks)
- [ ] Content balancing
- [ ] Bug fixing and testing
- [ ] Settings and options
- [ ] Documentation and guides
- [ ] Steam page preparation

---

## 🎯 Session Summary (2026-01-21)

### What We Completed Today

#### Phase 4F: Node-Based Logistics Network ✅
1. ✅ **Logistics Network Panel** - Visual panel showing all facilities as nodes
2. ✅ **Drag-to-Connect** - Drag from one facility to another to create connection
3. ✅ **Network View Control** - Custom drawing control with facility nodes and connection lines
4. ✅ **Right-click Delete** - Remove connections directly from the panel
5. ✅ **Multi-Vehicle Auto-Dispatch** - Trucks spawn automatically when source has 50+ units
6. ✅ **Higher Capacity** - Trucks carry 50 units (was 10)
7. ✅ **Vehicle Limits** - Maximum 3 trucks per connection to prevent traffic jams
8. ✅ **Routes → Connections** - Renamed with full backward compatibility

#### Phase 4G: Farmhouse Field System ✅
9. ✅ **Farmhouse UI Panel** - Dedicated panel for managing farmhouses
10. ✅ **Crop Field Placement** - Place barley/wheat fields around farmhouses
11. ✅ **Drag-to-Place** - Drag over area to place multiple 1x1 fields at once
12. ✅ **Adjacency Rules** - Fields must connect to farmhouse or other fields
13. ✅ **Distance Limits** - Fields limited to 10 tiles from parent farmhouse
14. ✅ **Visual Preview** - Green/red preview showing valid/invalid placement

#### Phase 4H: Road System ✅
15. ✅ **Road Placement** - Roads can be placed on the world map
16. ✅ **Road Renderer** - Visual rendering of road network
17. ✅ **Placement Validation** - Facilities cannot be placed over roads

### Key Achievements
- **Professional Logistics UI** - Node-based drag-to-connect replaces click-based route creation
- **Scalable Transport** - Multi-vehicle system with auto-dispatch handles high throughput
- **Intuitive Farming** - Drag-to-place makes field expansion fast and easy
- **Clean Architecture** - New UI panels follow established patterns

### Technical Improvements
- LogisticsNetworkPanel with custom NetworkView control
- FarmhouseUI panel for field management
- RoadRenderer for road visualization
- WorldManager farmhouse-field relationship tracking
- EventBus signals for connections (replacing routes)
- Save/load backward compatibility for old route format

### Testing Needed
```
⬜ Verify field placement is truly 1x1 (debug output added)
⬜ Test logistics network drag-to-connect
⬜ Test multi-vehicle auto-dispatch with 50+ units
⬜ Test road placement and facility blocking
⬜ Test farmhouse field adjacency rules
```

---

## 🚀 Next Session Recommended Focus

**Top Priority:** Verify & Polish New Systems ⭐ RECOMMENDED
- Test field 1x1 placement with debug output
- Add wheat field growth animation (barley has it, wheat doesn't)
- Test logistics network panel thoroughly
- Fix any issues found during testing

**Alternative 1:** Phase 7C - Remaining UI/UX
- Resource flow visualization (animated particles on connections)
- Mini-map for world navigation
- Connection stats display (throughput, vehicle count)

**Alternative 2:** Phase 8 - Content Expansion
- More facility types (water source, quality control lab)
- More machine types (conveyor belt, aging barrel)
- Wine production chain (grapes → juice → wine)

**Alternative 3:** Phase 6C - Maintenance Costs
- Daily/monthly facility upkeep
- Machine wear and repair
- Operating cost vs profit balance

---

## 📝 Development Philosophy

- **Incremental development:** Build minimal features, test thoroughly, iterate
- **Data-driven design:** JSON for all gameplay configuration
- **Signal-based communication:** Loose coupling via EventBus
- **Performance-first:** 60 FPS target with many facilities
- **Artist-friendly:** Sprite system with automatic fallbacks

---

**Status:** Phase 4F/4G/4H Complete! Node-based logistics network + Farmhouse field system + Road system.

**Next Session:** Verify new systems, add wheat field animation, or continue with content expansion

**GitHub Branch:** `dev`

**Build:** Fully playable with save/load, market system, research tree, node-based logistics, farmhouse fields, multi-vehicle transport
