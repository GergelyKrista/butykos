# Artist Testing Guide

Quick guide for artists to test sprites and assets in-game.

## Getting Started

1. Open the project in Godot 4.2+
2. Press **F5** to run the game
3. Click "Start New Game" from the main menu

## Adding Your Sprites

### World Map Facilities (Isometric)
- **Location**: `assets/sprites/`
- **Naming**: Must match facility ID from `data/facilities.json`
  - Example: `barley_field.png`, `grain_mill.png`, `brewery.png`
- **Format**: PNG with transparency
- **Perspective**: Isometric view (top + front + side visible)
- **Recommended size**: 64×64 to 128×128 pixels

### Factory Interior Machines (Top-Down)
- **Location**: `assets/machines/`
- **Naming**: Must match machine ID from `data/machines.json`
  - Example: `mash_tun.png`, `fermentation_vat.png`
- **Format**: PNG with transparency
- **Perspective**: Top-down orthogonal view
- **Recommended size**: 64×64 pixels

### Hot Reload
- Drop PNG files in the correct folder with the correct name
- Godot will automatically import them
- Press **F5** to restart the game and see your sprite

## Testing Your Assets

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **F1** | Show keyboard shortcuts help |
| **F5** | Quick save game |
| **F9** | Quick load game |
| **ESC** | Pause menu (save/load/exit) |
| **DELETE** | Delete hovered facility |
| **Right-Click** | Cancel placement mode |
| **Double-Click** | Enter factory interior |
| **Shift+Click** | Enter factory interior |

### Building Facilities

1. Look at the **BUILD MENU** at the bottom of the screen
2. Click a facility button to enter placement mode
3. Move mouse to position the facility
   - **Green tint** = Valid placement
   - **Red tint** = Invalid placement (occupied or out of bounds)
4. **Left-click** to place the facility
5. **Right-click** or **ESC** to cancel

### Viewing Facility Info

- **Hover** over any placed facility to see a tooltip with:
  - Facility name and type
  - Production status
  - Current inventory

### Deleting Facilities (for testing)

1. **Hover** your mouse over a facility
2. Press **DELETE** key
3. Facility is instantly removed

This is useful for:
- Testing different sprite placements
- Quickly rebuilding to see updated assets
- Clearing space for new tests

### Entering Factory Interiors

1. Place a facility that has an interior (Brewery, Distillery, etc.)
2. **Double-click** or **Shift+click** on the facility
3. You'll enter the factory interior view
4. Click "Back" button to return to world map

### Saving/Loading Your Test Setup

- **F5** - Quick save your current setup
- **F9** - Quick load your setup
- **ESC → Save Game** - Save to a named slot
- **ESC → Load Game** - Load from a named slot

Use this to save layouts with multiple facilities so you don't have to rebuild every time you restart!

## Asset Checklist

When testing a new sprite:

- [ ] Place sprite file in correct folder (`assets/sprites/` or `assets/machines/`)
- [ ] Name matches ID in JSON files exactly
- [ ] Restart game (F5)
- [ ] Build/place the facility in-game
- [ ] Check sprite renders correctly
- [ ] Check sprite centering/alignment
- [ ] Test hover tooltip (shows facility info)
- [ ] If facility has interior, enter it to test interior sprites
- [ ] Save game (F5) with your test setup

## Common Issues

### Sprite Not Showing
- Check filename matches JSON ID exactly (case-sensitive!)
- Check file is PNG format
- Restart Godot editor
- Check console for errors

### Sprite Misaligned
- For world map: Check if sprite needs pivot adjustment
- Sprites should be centered
- See `ASSET_NAMING_CONVENTION.md` for detailed specs

### Can't Click Facility
- Collision area is automatically generated
- Try clicking center of the sprite
- Hover should show tooltip if clickable

## Quick Test Workflow

**Fastest way to test multiple sprites:**

1. Start game, click "Start New Game"
2. Press F1 to see all shortcuts
3. Build your facilities quickly using build menu
4. Press F5 to save this layout
5. Close game, update sprite files
6. Press F5 to restart game
7. Press F9 to reload your test layout
8. Check your updated sprites!

## Production Chain Testing

To see facilities in action:

1. Place **Barley Field** (produces barley)
2. Place **Grain Mill** (converts barley → malt)
3. Click "Create Route" → click Field → click Mill
4. Watch vehicles transport barley automatically!
5. Hover over facilities to see inventory changing

For full chain:
- Barley Field → Grain Mill → Brewery
- Creates routes between each
- Brewery auto-sells ale for profit

This lets you see sprites with active production, inventory, and vehicles moving.

## Getting Help

- Press **F1** in-game for keyboard shortcuts
- Check `ASSET_NAMING_CONVENTION.md` for detailed asset specs
- Check `assets/PLACE_SPRITES_HERE.md` for quick reference
- Console output shows facility placements and errors

## Asset Feedback

When reviewing sprites in-game, check:
- Visual clarity at normal zoom level
- Distinguishable from other facility types
- Fits isometric perspective (for world map)
- Readable at small size
- Works with green/red placement tint

Use **Delete key** liberally to quickly test different arrangements and compositions!
