# Sprite Asset Integration Guide

How to replace placeholder sprites with real art assets.

## Current System

**Both layers now use Sprite2D with placeholder textures:**
- **World Map Facilities:** Programmatically generated colored squares
- **Factory Interior Machines:** Programmatically generated colored squares
- Color defined in `data/facilities.json` and `data/machines.json`
- Created on-the-fly using `Image.create()` and `ImageTexture`

**Locations:**
- World Map: `scenes/world_map/world_map.gd:295-300`
- Factory Interior: `scenes/factory_interior/factory_interior.gd:247-251`

```gdscript
func _create_placeholder_texture(tile_size: int, color: Color) -> ImageTexture:
    var image = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
    image.fill(color)
    return ImageTexture.create_from_image(image)
```

## Adding Real Sprites

### Method 1: Single Sprite Per Facility (Recommended)

**Best for:** Facilities that look like one cohesive building

1. **Create sprite assets:**
   - Barley Field: `128x128px` (2x2 tiles, 64px each)
   - Grain Mill: `128x128px` (2x2 tiles)
   - Brewery: `192x192px` (3x3 tiles, 64px each)

2. **Place in project:**
   ```
   assets/sprites/
   ├── barley_field.png
   ├── grain_mill.png
   └── brewery.png
   ```

3. **Update facilities.json:**
   ```json
   "barley_field": {
       "visual": {
           "sprite": "res://assets/sprites/barley_field.png"
       }
   }
   ```

4. **Modify `_create_facility_node()` in world_map.gd:**

   Replace this:
   ```gdscript
   for x in range(size.x):
       for y in range(size.y):
           var sprite = Sprite2D.new()
           sprite.texture = _create_placeholder_texture(WorldManager.TILE_SIZE - 4, color)
           sprite.position = Vector2(...)
           area.add_child(sprite)
   ```

   With this:
   ```gdscript
   # Check if custom sprite exists
   var sprite_path = facility_def.get("visual", {}).get("sprite", "")

   if not sprite_path.is_empty() and FileAccess.file_exists(sprite_path):
       # Use custom sprite for entire facility
       var sprite = Sprite2D.new()
       sprite.texture = load(sprite_path)
       area.add_child(sprite)
   else:
       # Fall back to per-tile placeholders
       for x in range(size.x):
           for y in range(size.y):
               var sprite = Sprite2D.new()
               sprite.texture = _create_placeholder_texture(WorldManager.TILE_SIZE - 4, color)
               sprite.position = Vector2(...)
               area.add_child(sprite)
   ```

### Method 2: Per-Tile Sprites

**Best for:** Modular facilities or tilesets

1. **Create tile sprites:**
   - Each 64x64px tile
   - Name: `barley_field_00.png`, `barley_field_01.png`, etc.

2. **Update facilities.json:**
   ```json
   "barley_field": {
       "visual": {
           "sprite_tiles": [
               ["res://assets/sprites/barley_field_00.png", "res://assets/sprites/barley_field_01.png"],
               ["res://assets/sprites/barley_field_10.png", "res://assets/sprites/barley_field_11.png"]
           ]
       }
   }
   ```

3. **Modify code to load per-tile sprites**

## Sprite Requirements

### Technical Specs
- **Format:** PNG (with transparency)
- **Size:** Multiple of 64px (tile size)
- **Color Mode:** RGBA
- **Import Settings:**
  - Filter: Disabled (for pixel art)
  - Mipmaps: Disabled
  - Repeat: Disabled

### Visual Style
Based on your design doc:
- **Clean minimalist 2D**
- **Simple sprites/icons** (not detailed pixel art)
- **Color-coded** for easy identification
- Think: Prison Architect / Mini Metro aesthetic

### Recommended Sizes

**Facilities (World Map - 64px tiles):**
| Facility | Grid Size | Sprite Size |
|----------|-----------|-------------|
| Barley Field | 2x2 | 128x128px |
| Grain Mill | 2x2 | 128x128px |
| Brewery | 3x3 | 192x192px |

**Machines (Factory Interior - 64px tiles):**
| Machine | Grid Size | Sprite Size |
|---------|-----------|-------------|
| Conveyor Belt | 1x1 | 64x64px |
| Mash Tun | 2x2 | 128x128px |
| Fermentation Vat | 2x3 | 128x192px |
| Distillation Column | 2x4 | 128x256px |
| Bottling Line | 3x2 | 192x128px |
| Quality Control | 2x2 | 128x128px |
| Storage Tank | 2x2 | 128x128px |

## Example: Adding Barley Field Sprite

### Step 1: Create/Get Asset
- Find or create a simple barley field icon
- Resize to 128x128px
- Save as `barley_field.png`

### Step 2: Import to Godot
```
assets/
└── sprites/
    └── barley_field.png  (128x128px)
```

### Step 3: Update JSON
```json
{
    "barley_field": {
        "name": "Barley Field",
        "size": [2, 2],
        "visual": {
            "color": "#7cba3f",
            "sprite": "res://assets/sprites/barley_field.png"
        }
    }
}
```

### Step 4: Modify Code (see Method 1 above)

### Step 5: Test
- Run game
- Build barley field
- Should show your sprite instead of colored square!

## Fallback System

The current implementation allows graceful fallback:
1. Try to load custom sprite
2. If not found, use placeholder colored squares
3. No crashes if assets missing

## Animation Support (Future)

To add animated sprites later:

```gdscript
var animated_sprite = AnimatedSprite2D.new()
animated_sprite.sprite_frames = load("res://assets/sprites/barley_field_anim.tres")
animated_sprite.play("producing")
```

## Multi-State Sprites (Future)

Show different sprites based on facility state:

```gdscript
var sprite_path = facility_def.get("visual", {}).get("sprite", "")

# Choose sprite based on state
if not facility.constructed:
    sprite_path = sprite_path.replace(".png", "_construction.png")
elif facility.production_active:
    sprite_path = sprite_path.replace(".png", "_active.png")
```

## Sprite Atlases (Optimization)

For better performance with many sprites:

1. Combine all facility sprites into one atlas texture
2. Use `AtlasTexture` to reference regions
3. Reduces draw calls and memory usage

## Color Tinting

Current system supports color tinting:

```gdscript
sprite.modulate = Color.YELLOW  # Highlight on selection
sprite.modulate = Color(1, 1, 1, 0.5)  # Semi-transparent
```

This is used for:
- Selection highlighting (yellow)
- Construction progress (fade in)
- Disabled state (grayed out)

## Current Facility Colors

From `data/facilities.json`:

| Facility | Color | Hex |
|----------|-------|-----|
| Barley Field | Green | #7cba3f |
| Grain Mill | Brown | #8b6f47 |
| Brewery | Orange | #c97a3f |

These make good base colors if using tinted sprites.

---

**Next Steps:**
1. Create/commission simple sprite assets
2. Place in `assets/sprites/`
3. Update `facilities.json` with sprite paths
4. Modify `_create_facility_node()` to load sprites
5. Test and iterate!
