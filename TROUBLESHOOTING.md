# Troubleshooting - Autoload Issues

## Problem: "Identifier not declared in current scope" errors

If you see errors like:
```
Parse Error: Identifier "EventBus" not declared in the current scope.
Parse Error: Identifier "GameManager" not declared in the current scope.
```

This means the autoload singletons aren't being recognized by Godot.

## Solution 1: Restart Godot

1. **Close Godot completely**
2. **Reopen the project**
3. Wait for Godot to fully reload (check bottom status bar)
4. Try running (F5) again

## Solution 2: Manually Configure Autoloads (if restart doesn't work)

If the autoloads still aren't recognized:

1. **Open Project Settings:**
   - Menu: `Project → Project Settings`
   - Or press `Alt + P`

2. **Go to Autoload tab:**
   - Click the **Autoload** tab at the top

3. **Check if autoloads are listed:**
   - You should see 7 items: EventBus, GameManager, SaveManager, DataManager, WorldManager, EconomyManager, ProductionManager
   - Each should have a checkmark in the "Enable" column

4. **If they're missing, add them manually:**

   For each autoload:

   a. Click the folder icon next to "Path"

   b. Navigate to and select the script:
   - `res://core/event_bus.gd` → Name: **EventBus** → Enable: ✅ → Add
   - `res://core/game_manager.gd` → Name: **GameManager** → Enable: ✅ → Add
   - `res://core/save_manager.gd` → Name: **SaveManager** → Enable: ✅ → Add
   - `res://core/data_manager.gd` → Name: **DataManager** → Enable: ✅ → Add
   - `res://systems/world_manager.gd` → Name: **WorldManager** → Enable: ✅ → Add
   - `res://systems/economy_manager.gd` → Name: **EconomyManager** → Enable: ✅ → Add
   - `res://systems/production_manager.gd` → Name: **ProductionManager** → Enable: ✅ → Add

5. **Click "Close"**

6. **Try running (F5) again**

## Solution 3: Check for Script Errors

If autoloads are configured but still failing:

1. **Open each core script and check for syntax errors:**
   - `core/event_bus.gd`
   - `core/game_manager.gd`
   - etc.

2. **Look for red error markers in the script editor**

3. **Check the Output panel (bottom) for specific error messages**

## Solution 4: Reimport Project

If nothing works:

1. Close Godot
2. Delete the `.godot` folder in your project directory
3. Reopen the project (Godot will reimport everything)
4. Try running again

## Solution 5: Check Godot Version

Ensure you're using **Godot 4.2+**:
- Menu: `Help → About Godot`
- Should show "4.2.x" or higher

This project requires Godot 4.2 or newer.

## Verification

Once autoloads are working, you should see this output when running:

```
EventBus initialized
GameManager initialized
SaveManager initialized
DataManager initialized
Data loaded: 3 facilities, 0 products, 0 recipes, 0 machines
WorldManager initialized
EconomyManager initialized
Starting money: $5000
ProductionManager initialized
WorldMap scene loaded
```

If you see this, the autoloads are working correctly!

## Still Having Issues?

If none of these solutions work:

1. Check that all script files exist in the correct locations
2. Verify no syntax errors in any .gd files
3. Try creating a new empty scene and running it (F6) to test if Godot itself is working
4. Check Godot's issue tracker for known bugs with autoloads in your version
