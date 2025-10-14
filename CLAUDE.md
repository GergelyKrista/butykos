# Alcohol Empire Tycoon - Development Guidelines

## Isometric Grid System Requirements

### CRITICAL: Grid Perspective for World Map

The **world map layer** uses **isometric perspective** for proper visual presentation of the tycoon game, while **factory interiors remain top-down** for easier machine placement.

### Why Isometric for World Map?

For an OTTD-style tycoon game, isometric view is essential because:

1. **Visual depth**: Facilities and buildings look 3D while remaining 2D sprites
2. **Readability**: Multiple facilities visible simultaneously without overlapping
3. **Industry standard**: All classic tycoon games (OTTD, RollerCoaster Tycoon, SimCity 2000) use isometric
4. **Sprite efficiency**: Single sprite shows multiple sides of a building
5. **Spatial clarity**: Players can easily understand layout and connections between facilities

### Dual-Layer Architecture

**World Map (Strategic Layer):**
- Isometric view (2:1 ratio tiles)
- 50×50 grid
- Camera/world rotated 45°
- Tile size: 32×16 pixels (width×height)

**Factory Interior (Tactical Layer):**
- Top-down orthogonal view
- 20×20 grid
- No rotation
- Tile size: 64×64 pixels

## Technical Specifications

### Isometric Grid Properties

- **Tile dimensions**: 32×16 pixels (2:1 ratio)
- **Grid size**: 50×50 tiles
- **Rotation**: 45° world rotation
- **View angle**: ~26.565° from horizontal

### Coordinate System

#### World Map Isometric Conversion

```gdscript
# In WorldManager
const TILE_SIZE = 32  # Width of isometric tile
const TILE_HEIGHT = 16  # Height of isometric tile (2:1 ratio)
const GRID_SIZE = Vector2i(50, 50)

# Cartesian to Isometric
func cart_to_iso(cart_pos: Vector2) -> Vector2:
    var iso_x = (cart_pos.x - cart_pos.y) * (TILE_SIZE / 2.0)
    var iso_y = (cart_pos.x + cart_pos.y) * (TILE_HEIGHT / 2.0)
    return Vector2(iso_x, iso_y)

# Isometric to Cartesian
func iso_to_cart(iso_pos: Vector2) -> Vector2:
    var cart_x = (iso_pos.x / (TILE_SIZE / 2.0) + iso_pos.y / (TILE_HEIGHT / 2.0)) / 2.0
    var cart_y = (iso_pos.y / (TILE_HEIGHT / 2.0) - iso_pos.x / (TILE_SIZE / 2.0)) / 2.0
    return Vector2(cart_x, cart_y)
```

#### Factory Interior (Orthogonal)

```gdscript
# In FactoryManager
const INTERIOR_TILE_SIZE = 64  # Square tiles
const INTERIOR_GRID_SIZE = Vector2i(20, 20)

# Simple orthogonal conversion (no rotation)
func grid_to_world(grid_pos: Vector2i) -> Vector2:
    return Vector2(
        grid_pos.x * INTERIOR_TILE_SIZE + INTERIOR_TILE_SIZE / 2.0,
        grid_pos.y * INTERIOR_TILE_SIZE + INTERIOR_TILE_SIZE / 2.0
    )
```

### Mouse Input Handling

For world map with 45° rotation:

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventMouse:
        var screen_pos = camera.get_global_mouse_position()
        # Adjust for 45-degree rotation of the world
        var rotated_pos = screen_pos.rotated(-deg_to_rad(45))
        mouse_grid_pos = WorldManager.world_to_grid(rotated_pos)
```

### Rendering Order (Z-Index)

Critical for isometric: Objects further "back" render first.

```gdscript
# Calculate Z-index for proper rendering order
# Higher Y + Higher X = render first (behind)
facility.z_index = grid_y * 100 + grid_x
```

## Asset Requirements

### World Map Sprites (Isometric)

All facility/building sprites for the world map must be drawn from **isometric perspective**:

**Isometric building appearance:**
```
      ╱╲
     ╱  ╲      ← Roof visible
    ╱────╲
   │      │    ← Front face visible
   │      │    ← Side face visible
   └──────┘
```

**Key requirements:**
- View from above at ~30-35° angle
- Shows top, front, and right side of buildings (or left side - pick one and be consistent)
- All sprites at the same isometric angle

**Dimensions:**
- Fit within 64×64 pixel area (but maintain isometric shape)
- Use 32×16 base tile for smaller facilities
- Larger facilities can span multiple tiles (2×2, 3×3, etc.)

**Pivot points:**
- Set sprite origin/pivot to **bottom-center** of the isometric diamond
- Ensures proper vertical sorting

### Factory Interior Sprites (Top-Down)

Machine sprites use simple **orthogonal top-down** view:

**Dimensions:**
- Fit within 64×64 pixel area
- Machines can be 1×1, 2×2, 2×3, etc. tiles
- Simple top-down perspective (looking straight down)

**Pivot points:**
- Center of sprite

### Placeholder Sprites (Current Implementation)

For now, using colored Sprite2D placeholders:

```gdscript
func _create_placeholder_texture(tile_size: int, color: Color) -> ImageTexture:
    var image = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
    image.fill(color)
    return ImageTexture.create_from_image(image)
```

**Colors from data/facilities.json:**
- Barley Field: #7cba3f (green)
- Grain Mill: #8b6f47 (brown)
- Brewery: #c97a3f (orange)

## Implementation Checklist

### Phase 1: Current State (Main Branch)
- [x] World map with 45° rotation
- [x] Grid visible and rotated
- [x] Basic mouse input adjusted for rotation
- [x] Placeholder colored squares for facilities
- [x] Factory interior stays top-down

### Phase 2: Proper Isometric (New Branch)
- [ ] Update WorldManager with proper isometric conversion functions
- [ ] Adjust TILE_SIZE to 32×16 for isometric
- [ ] Fix mouse input for true isometric coordinate conversion
- [ ] Update facility placement preview for isometric tiles
- [ ] Adjust collision shapes for isometric diamond tiles
- [ ] Implement proper Z-index sorting
- [ ] Create isometric placeholder diamonds (not squares)
- [ ] Test multi-tile facility placement in isometric
- [ ] Ensure factory interior stays unchanged

### Phase 3: Asset Integration (Future)
- [ ] Design/commission isometric facility sprites
- [ ] Replace placeholders with real isometric art
- [ ] Add building animations (smoke, activity indicators)
- [ ] Design top-down machine sprites for factory interiors
- [ ] Implement sprite atlases for performance

## Code Style Guidelines

- Use explicit type hints for all function parameters and returns
- Comment coordinate space conversions clearly
- Keep isometric logic in WorldManager
- Keep orthogonal logic in FactoryManager
- Test both layers independently

## Testing Notes

When testing isometric implementation:
1. Verify grid lines form perfect diamonds
2. Check mouse clicks land on correct grid tiles
3. Test facility placement at all grid positions
4. Verify facilities don't overlap incorrectly
5. Ensure factory interior still works in top-down
6. Test scene transitions between layers
