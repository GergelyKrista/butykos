---
name: drinkustry-isometric-coords
description: Use when working with the world map's isometric coordinate system, facility placement, sprite alignment, mouse picking on the world map, or grid-related rendering. Triggers on requests touching world_map.gd, world_manager.gd, scenes/world_map/, sprite alignment issues, or any work involving isometric ↔ cartesian conversion. Do NOT load for factory interior work — that's orthogonal top-down.
---

# Drinkustry — isometric coordinate system

The world map uses **true isometric mathematics** (not a 45° rotation hack — that was the pre-pivot approach and is gone).

## Constants — already defined in WorldManager

```gdscript
const TILE_WIDTH = 64    # Isometric tile width
const TILE_HEIGHT = 32   # Isometric tile height (2:1 ratio)
const GRID_SIZE = Vector2i(50, 50)
```

## Conversion functions — already defined, don't reimplement

```gdscript
# Cartesian (grid) to Isometric (screen)
func cart_to_iso(cart_pos: Vector2) -> Vector2:
    var iso_x = (cart_pos.x - cart_pos.y) * (TILE_WIDTH / 2.0)
    var iso_y = (cart_pos.x + cart_pos.y) * (TILE_HEIGHT / 2.0)
    return Vector2(iso_x, iso_y)

# Isometric (screen) to Cartesian (grid)
func iso_to_cart(iso_pos: Vector2) -> Vector2:
    var cart_x = (iso_pos.x / (TILE_WIDTH / 2.0) + iso_pos.y / (TILE_HEIGHT / 2.0)) / 2.0
    var cart_y = (iso_pos.y / (TILE_HEIGHT / 2.0) - iso_pos.x / (TILE_WIDTH / 2.0)) / 2.0
    return Vector2(cart_x, cart_y)
```

For mouse picking, use the wrapper `WorldManager.world_to_grid(world_pos)` — it handles the conversion internally.

## Hard rules

1. **Tiles sit between grid lines, not on them.** Grid lines at integer coords (0, 1, 2…); tile centers at half-integer coords (0.5, 1.5…). Always add `+ 0.5` offset when positioning tiles.

2. **Z-index sorting required for proper depth:**
   ```gdscript
   facility.z_index = grid_pos.y * 100 + grid_pos.x
   ```
   Without this, facilities render in arbitrary order and break depth.

3. **Sprite rendering uses bottom-center alignment.** Sprites must use `centered = false` with manual positioning so the sprite bottom sits at the isometric footprint base. Sprites can have extra vertical height for building detail — the engine handles the alignment.

   ```gdscript
   var sprite = Sprite2D.new()
   sprite.texture = load(sprite_path)
   sprite.centered = false
   var footprint_height = (size.x + size.y) * TILE_HEIGHT / 2.0
   sprite.position = Vector2(-sprite_width / 2.0, -sprite_height + footprint_height / 2.0)
   ```

   Examples:
   - Malt House (2×2): 128×80px sprite on 128×64px footprint
   - Brewery (3×3): 192×112px sprite on 192×96px footprint

4. **Facilities use Sprite2D with bottom-center alignment, fallback to Polygon2D diamond** if the sprite path doesn't resolve. Don't replace the fallback — artists drop in PNGs incrementally.

5. **Multi-tile facilities:** size is a `Vector2i` like `Vector2i(2, 2)` or `Vector2i(3, 3)`. Footprint base = sum of dimensions × half tile height.

## Common gotchas

- **Tiles misaligned with grid?** You forgot the `+ 0.5` offset.
- **Facilities render in wrong order?** Check the Z-index calculation.
- **Mouse picking fails?** Don't bypass the conversion — use `WorldManager.world_to_grid()` directly.
- **Sprite misaligned with grid?** You set `centered = true` instead of using the bottom-center formula.
- **Sprite not showing at all?** Check the field name — facilities use `visual.icon` in JSON, machines use `visual.sprite` (different field name on purpose; don't unify them).

## Factory interior — DIFFERENT system

Factory interiors stay **orthogonal top-down**, 64×64 pixel tiles, never apply isometric logic to factory scenes. If a coordinate question is about a factory interior, this skill doesn't apply — use straight grid math (`grid_pos * 64`).

## Mouse coordinates — the factory-interior trap

Even though factory interiors are orthogonal, machine placement has its own gotcha: use `get_viewport().get_mouse_position()` + canvas transform inverse, NOT `camera.get_global_mouse_position()`. The latter looks right but breaks at non-default zoom.

## When making per-corp signature mechanics that use the world map

- **Agri irrigation pipes:** use the same isometric grid; pipes draw between tile centers (cart → iso conversion).
- **Logistics routes:** already isometric; transfer hubs need the same z-index sorting.
- **Business sales outlets:** isometric placement, same rules as facilities.
- **Espionage outposts:** same.

The single coordinate system is shared across corps. Don't add a per-corp coord variant.

## Heat-map overlays (Phase 11)

Overlays are textures rendered above the grid. Coord-wise they're trivial: 1 tile = 1 texel (or whatever resolution `OverlayManager` settles on). The overlay's coordinate system is the cartesian grid, then transformed once to isometric on display. Don't compute overlays in isometric space — that breaks the per-tile sampling.
