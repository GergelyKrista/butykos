# Asset Naming Convention Guide

This document defines the exact naming conventions and specifications for all visual assets in **Alcohol Empire Tycoon**. Follow these guidelines precisely to ensure assets load correctly in the game.

---

## 📂 Directory Structure

```
butykos/
└── assets/
    ├── sprites/          # World map facility sprites (isometric)
    ├── machines/         # Factory interior machine sprites (top-down)
    ├── ui/              # UI elements, icons, buttons
    ├── vehicles/        # Logistics vehicle sprites
    └── audio/           # Sound effects and music
```

---

## 🏭 World Map Facilities (Isometric)

**Location:** `assets/sprites/`

**Art Style:**
- Isometric perspective (~30-35° viewing angle)
- Show top, front, and one side of structure
- Tile ratio: 2:1 (width:height)
- Base tile: 64×32 pixels
- Pivot point: Bottom-center of diamond footprint

### Current Facilities

| Facility Type | File Name | Canvas Size | Grid Size | Description |
|--------------|-----------|-------------|-----------|-------------|
| Barley Field | `barley_field.png` | 128×64 | 2×2 | Golden wheat field with rows |
| Grain Mill | `grain_mill.png` | 128×64 | 2×2 | Stone mill building with wheel |
| Brewery | `brewery.png` | 192×96 | 3×3 | Large brick building with chimney |

### Future Facilities (Planned)

| Facility Type | File Name | Canvas Size | Grid Size | Description |
|--------------|-----------|-------------|-----------|-------------|
| Wheat Farm | `wheat_farm.png` | 128×64 | 2×2 | Wheat field variant |
| Corn Farm | `corn_farm.png` | 128×64 | 2×2 | Corn field with stalks |
| Water Tower | `water_tower.png` | 64×32 | 1×1 | Tall cylindrical water storage |
| Distillery | `distillery.png` | 192×96 | 3×3 | Industrial distilling facility |
| Bottling Plant | `bottling_plant.png` | 256×128 | 4×4 | Large packaging facility |
| Warehouse | `warehouse.png` | 192×96 | 3×3 | Storage building |
| Market Stall | `market_stall.png` | 64×32 | 1×1 | Small selling booth |
| Distribution Center | `distribution_center.png` | 256×128 | 4×4 | Large logistics hub |
| Cooperage | `cooperage.png` | 128×64 | 2×2 | Barrel-making workshop |
| Malthouse | `malthouse.png` | 128×64 | 2×2 | Malt processing building |

---

## ⚙️ Factory Interior Machines (Top-Down)

**Location:** `assets/machines/`

**Art Style:**
- Pure top-down orthogonal view (straight down)
- Simple, clear silhouettes
- Base tile: 64×64 pixels
- Pivot point: Center of sprite
- Show functional elements (pipes, valves, gauges)

### Current Machines

| Machine Type | File Name | Canvas Size | Grid Size | Category | Description |
|-------------|-----------|-------------|-----------|----------|-------------|
| Conveyor Belt | `conveyor_belt.png` | 64×64 | 1×1 | Logistics | Belt mechanism |
| Mash Tun | `mash_tun.png` | 128×128 | 2×2 | Brewing | Large circular vat |
| Fermentation Vat | `fermentation_vat.png` | 128×192 | 2×3 | Brewing | Tall cylindrical tank |
| Distillation Column | `distillation_column.png` | 128×256 | 2×4 | Distilling | Vertical tower |
| Aging Barrel | `aging_barrel.png` | 64×64 | 1×1 | Distilling | Wooden barrel |
| Bottling Line | `bottling_line.png` | 192×128 | 3×2 | Packaging | Conveyor with bottles |
| Quality Control | `quality_control.png` | 128×128 | 2×2 | Quality | Lab station |
| Storage Tank | `storage_tank.png` | 128×128 | 2×2 | Storage | Large metal tank |
| Input Hopper | `input_hopper.png` | 64×64 | 1×1 | Logistics | Funnel/chute |
| Output Depot | `output_depot.png` | 64×64 | 1×1 | Logistics | Loading dock |
| Market Outlet | `market_outlet.png` | 64×64 | 1×1 | Logistics | Sales counter |
| Steam Boiler | `boiler.png` | 128×192 | 2×3 | Utility | Large boiler |
| Water Pump | `water_pump.png` | 64×128 | 1×2 | Utility | Pump station |

### Future Machines (Planned)

| Machine Type | File Name | Canvas Size | Grid Size | Category | Description |
|-------------|-----------|-------------|-----------|----------|-------------|
| Grain Silo | `grain_silo.png` | 128×128 | 2×2 | Storage | Tall grain storage |
| Crusher | `crusher.png` | 128×128 | 2×2 | Processing | Grain crushing machine |
| Filter Press | `filter_press.png` | 128×128 | 2×2 | Processing | Filtering equipment |
| Centrifuge | `centrifuge.png` | 64×64 | 1×1 | Processing | Spinning separator |
| Pasteurizer | `pasteurizer.png` | 128×64 | 2×1 | Processing | Heat treatment unit |
| Carbonation Tank | `carbonation_tank.png` | 128×128 | 2×2 | Brewing | CO2 injection tank |
| Kegging Line | `kegging_line.png` | 192×128 | 3×2 | Packaging | Keg filling line |
| Canning Line | `canning_line.png` | 192×128 | 3×2 | Packaging | Can filling line |
| Labeling Machine | `labeling_machine.png` | 128×64 | 2×1 | Packaging | Label applicator |
| Palletizer | `palletizer.png` | 128×128 | 2×2 | Packaging | Pallet stacking |
| Forklift Station | `forklift_station.png` | 64×64 | 1×1 | Logistics | Loading vehicle |

---

## 🚚 Logistics Vehicles

**Location:** `assets/vehicles/`

**Art Style:**
- Isometric perspective to match world map
- Show direction of travel clearly
- Base size: ~24×12 pixels (smaller than facilities)
- Animate-friendly (simple shape)

### Current Vehicles

| Vehicle Type | File Name | Dimensions | Description |
|-------------|-----------|------------|-------------|
| Truck | `truck.png` | 24×12 | Standard delivery truck (currently Polygon2D) |

### Future Vehicles (Planned)

| Vehicle Type | File Name | Dimensions | Description |
|-------------|-----------|------------|-------------|
| Cart | `cart.png` | 20×10 | Small hand cart |
| Horse Cart | `horse_cart.png` | 32×16 | Horse-drawn wagon |
| Train Car | `train_car.png` | 48×20 | Railway cargo car |
| Boat | `boat.png` | 40×24 | River/canal transport |

---

## 🎨 UI Elements

**Location:** `assets/ui/`

**Art Style:**
- Flat design, modern minimalist
- Consistent color palette
- High contrast for readability
- Standard sizes: 32×32, 64×64, 128×128

### Current UI Assets (Placeholders)

| Element | File Name | Size | Description |
|---------|-----------|------|-------------|
| Build Button | `button_build.png` | 128×40 | Green build button |
| Cancel Button | `button_cancel.png` | 128×40 | Red cancel button |
| Route Button | `button_route.png` | 128×40 | Blue route button |
| Money Icon | `icon_money.png` | 32×32 | Dollar sign icon |
| Calendar Icon | `icon_date.png` | 32×32 | Calendar icon |

### Future UI Assets (Planned)

| Element | File Name | Size | Description |
|---------|-----------|------|-------------|
| Product Icons | `icon_barley.png` | 32×32 | Product type icons |
| | `icon_malt.png` | 32×32 | |
| | `icon_mash.png` | 32×32 | |
| | `icon_ale.png` | 32×32 | |
| | `icon_whiskey.png` | 32×32 | |
| Machine Icons | `icon_mash_tun.png` | 48×48 | Machine type icons |
| | `icon_fermentation_vat.png` | 48×48 | |
| | `icon_bottling_line.png` | 48×48 | |
| Status Icons | `icon_producing.png` | 24×24 | Production status |
| | `icon_idle.png` | 24×24 | |
| | `icon_blocked.png` | 24×24 | |
| | `icon_loading.png` | 24×24 | |

---

## 📋 Product Icons

**Location:** `assets/products/`

### Current Products

| Product | File Name | Size | Description |
|---------|-----------|------|-------------|
| Barley | `barley.png` | 32×32 | Raw grain |
| Malt | `malt.png` | 32×32 | Processed grain |
| Mash | `mash.png` | 32×32 | Wet grain mixture |
| Fermented Wash | `fermented_wash.png` | 32×32 | Fermented liquid |
| Ale | `ale.png` | 32×32 | Beer bottle |

### Future Products (Planned)

| Product | File Name | Size | Description |
|---------|-----------|------|-------------|
| Wheat | `wheat.png` | 32×32 | Wheat grain |
| Corn | `corn.png` | 32×32 | Corn kernel |
| Water | `water.png` | 32×32 | Water droplet |
| Raw Spirit | `raw_spirit.png` | 32×32 | Clear liquid |
| Aged Spirit | `aged_spirit.png` | 32×32 | Amber liquid |
| Whiskey | `whiskey.png` | 32×32 | Whiskey bottle |
| Vodka | `vodka.png` | 32×32 | Vodka bottle |
| Lager | `lager.png` | 32×32 | Lager bottle |

---

## 🎯 Naming Rules

### ✅ Correct Naming

```
barley_field.png          ✓ Lowercase with underscores
mash_tun.png              ✓ Multi-word separation
bottling_line.png         ✓ Descriptive and clear
```

### ❌ Incorrect Naming

```
BarleyField.png           ✗ No CamelCase
barley-field.png          ✗ No hyphens
barleyfield.png           ✗ No spaces between words
barley_field_01.png       ✗ No version numbers in filename
```

---

## 📐 Technical Specifications

### File Format
- **Format:** PNG with transparency
- **Color Mode:** RGBA (8-bit per channel)
- **Compression:** PNG-8 or PNG-24
- **No metadata:** Strip EXIF data for smaller files

### Canvas Sizes by Grid Size

| Grid Size | Canvas Width | Canvas Height | Use Case |
|-----------|--------------|---------------|----------|
| 1×1 | 64 | 64 | Small machines, markers |
| 1×2 | 64 | 128 | Tall thin machines |
| 2×1 | 128 | 64 | Wide short machines |
| 2×2 | 128 | 128 | Standard machines |
| 2×3 | 128 | 192 | Tall machines |
| 3×2 | 192 | 128 | Wide machines |
| 2×4 | 128 | 256 | Very tall machines |
| 3×3 | 192 | 192 | Large facilities |
| 4×4 | 256 | 256 | Huge facilities |

### Isometric Canvas Sizes (World Map)

| Grid Size | Canvas Width | Canvas Height | Footprint |
|-----------|--------------|---------------|-----------|
| 1×1 | 64 | 32 | Single tile |
| 2×2 | 128 | 64 | Small building |
| 3×3 | 192 | 96 | Medium building |
| 4×4 | 256 | 128 | Large building |

---

## 🎨 Color Palette Reference

### Facility Categories

| Category | Primary Color | Hex Code | Example |
|----------|---------------|----------|---------|
| Agriculture | Green | `#7cba3f` | Barley Field |
| Processing | Brown | `#8b6f47` | Grain Mill |
| Production | Orange | `#c97a3f` | Brewery |
| Logistics | Gray | `#708090` | Storage |
| Utility | Red | `#DC143C` | Boiler |

### Machine Categories

| Category | Primary Color | Hex Code | Example |
|----------|---------------|----------|---------|
| Brewing | Brown | `#8B4513` | Mash Tun |
| Distilling | Silver | `#C0C0C0` | Distillation Column |
| Packaging | Cyan | `#00CED1` | Bottling Line |
| Storage | Gray | `#708090` | Storage Tank |
| Logistics | Dark Gray | `#A9A9A9` | Input Hopper |
| Quality | Blue | `#4169E1` | Quality Control |

---

## 🔄 Asset Loading Behavior

### Automatic Fallback System

The game uses a **smart fallback system**:

1. **Check for sprite file** at specified path
2. **If found:** Load and render sprite
3. **If not found:** Render colored Polygon2D placeholder using `color` field from JSON

### Example (from `data/facilities.json`)

```json
"visual": {
  "color": "#7cba3f",           ← Fallback color if sprite missing
  "icon": "res://assets/sprites/barley_field.png"  ← Primary sprite path
}
```

**Result:**
- With sprite: Renders `barley_field.png`
- Without sprite: Renders green diamond placeholder

---

## 📝 JSON Reference Paths

### Facilities
File: `data/facilities.json`

```json
"facility_name": {
  "visual": {
    "color": "#hexcode",
    "icon": "res://assets/sprites/{facility_name}.png"
  }
}
```

### Machines
File: `data/machines.json`

```json
"machine_name": {
  "visual": {
    "color": "#hexcode",
    "sprite": "res://assets/machines/{machine_name}.png"
  }
}
```

---

## 🚀 Quick Start for Artists

### Checklist for Creating New Asset

1. ✅ Check this document for exact filename
2. ✅ Verify canvas size matches grid size
3. ✅ Use PNG format with transparency
4. ✅ Follow art style (isometric vs top-down)
5. ✅ Use lowercase with underscores for filename
6. ✅ Place in correct directory (`sprites/` or `machines/`)
7. ✅ Test in-game (asset loads automatically)

### Testing Your Assets

1. Place PNG file in correct folder
2. Ensure filename matches JSON reference exactly
3. Launch game in Godot (F5)
4. Place facility/machine
5. Asset should appear immediately!

---

## 📞 Questions?

If you need to add a new asset type not listed here:

1. Check `data/facilities.json` and `data/machines.json` for reference paths
2. Follow the naming convention pattern: `{type_name}.png`
3. Use appropriate canvas size for grid dimensions
4. Place in correct folder based on asset type

**This is a living document** - it will be updated as new facilities, machines, and products are added to the game.

---

*Last Updated: 2025-10-15*
*Game Version: Phase 4E (Logistics Visualization)*
