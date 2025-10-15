# Where to Place Sprite Assets

This is a quick reference for adding completed sprite assets to the game.

## 📂 Directory Structure

```
assets/
├── sprites/          ← World map facilities (isometric view)
├── machines/         ← Factory interior machines (top-down view)
├── ui/              ← UI elements, icons, buttons (future)
├── vehicles/        ← Logistics vehicles (future)
└── products/        ← Product icons (future)
```

---

## 🏭 World Map Facilities → `sprites/`

**Art Style:** Isometric (~30° angle), show top + front + side

| Sprite File | Size | Facility |
|------------|------|----------|
| `barley_field.png` | 128×64 | Barley Field (2×2 grid) |
| `wheat_farm.png` | 128×64 | Wheat Farm (2×2 grid) |
| `grain_mill.png` | 128×64 | Grain Mill (2×2 grid) |
| `brewery.png` | 192×96 | Brewery (3×3 grid) |
| `distillery.png` | 192×96 | Distillery (3×3 grid) |
| `packaging_plant.png` | 128×192 | Packaging Plant (2×3 grid) |
| `storage_warehouse.png` | 192×128 | Storage Warehouse (3×2 grid) |

**To add a sprite:**
1. Save PNG file as exact name above
2. Place in `assets/sprites/` folder
3. Launch game (F5)
4. Sprite appears automatically!

---

## ⚙️ Factory Interior Machines → `machines/`

**Art Style:** Top-down (straight down), orthogonal view

### Current Machines (Priority Order)

| Sprite File | Size | Machine |
|------------|------|---------|
| `input_hopper.png` | 64×64 | Input Hopper (1×1) |
| `mash_tun.png` | 128×128 | Mash Tun (2×2) |
| `fermentation_vat.png` | 128×192 | Fermentation Vat (2×3) |
| `bottling_line.png` | 192×128 | Bottling Line (3×2) |
| `storage_tank.png` | 128×128 | Storage Tank (2×2) |
| `market_outlet.png` | 64×64 | Market Outlet (1×1) |
| `output_depot.png` | 64×64 | Output Depot (1×1) |

### Additional Machines (Lower Priority)

| Sprite File | Size | Machine |
|------------|------|---------|
| `conveyor_belt.png` | 64×64 | Conveyor Belt (1×1) |
| `distillation_column.png` | 128×256 | Distillation Column (2×4) |
| `aging_barrel.png` | 64×64 | Aging Barrel (1×1) |
| `quality_control.png` | 128×128 | Quality Control (2×2) |
| `boiler.png` | 128×192 | Steam Boiler (2×3) |
| `water_pump.png` | 64×128 | Water Pump (1×2) |

**To add a sprite:**
1. Save PNG file as exact name above
2. Place in `assets/machines/` folder
3. Launch game (F5)
4. Sprite appears automatically!

---

## 🚚 Vehicles → `vehicles/` (Future)

| Sprite File | Size | Vehicle |
|------------|------|---------|
| `truck.png` | 24×12 | Delivery Truck |

---

## ✅ Testing Your Sprites

1. **Add PNG file** to correct folder (`sprites/` or `machines/`)
2. **Ensure filename matches exactly** (lowercase, underscores)
3. **Launch game** in Godot (press F5)
4. **Place facility/machine** in game
5. **Sprite should appear!**

If sprite doesn't show:
- Check filename spelling (must match exactly)
- Check file is PNG with transparency (RGBA)
- Check file is in correct folder
- See `ASSET_NAMING_CONVENTION.md` for full details

---

## 📐 Canvas Size Reference

**Grid Size → Canvas Size:**
- 1×1 = 64×64 pixels
- 1×2 = 64×128 pixels
- 2×1 = 128×64 pixels
- 2×2 = 128×128 pixels
- 2×3 = 128×192 pixels
- 3×2 = 192×128 pixels
- 2×4 = 128×256 pixels
- 3×3 = 192×192 pixels

**Isometric (World Map):**
- 2×2 = 128×64 pixels
- 3×3 = 192×96 pixels

---

**For complete specifications, see:** `ASSET_NAMING_CONVENTION.md`
