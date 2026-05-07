---
name: godot-gdscript-conventions
description: Use when writing or reviewing GDScript code for the Drinkustry / butykos project. Captures the project's specific Godot 4.2 patterns — singleton-autoload + EventBus signal-bus + data-driven JSON, type hints everywhere, predicate-then-action manager API, deterministic-friendly idioms. Triggers on requests like "add a function to <manager>.gd", "implement X in GDScript", "review this Godot code", or any code-level work in core/ systems/ scenes/.
---

# Drinkustry — GDScript conventions

This is the language-and-pattern layer. For higher-level architectural rules see `drinkustry-add-system`.

## Type hints — always

```gdscript
func place_facility(facility_type: String, grid_pos: Vector2i) -> String:
    var facility_def: Dictionary = DataManager.facilities.get(facility_type, {})
    if facility_def.is_empty():
        return ""
    ...
```

- Function params and return types: required.
- Local vars: typed when the type isn't obvious from the assignment (`var x: int = 0` is overkill; `var def: Dictionary = ...` is helpful).
- `void` for mutators. Don't return `null` from a `-> String` — return `""` and let callers check `.is_empty()`. Same for `Array` (return `[]`) and `Dictionary` (return `{}`).

## Naming

- `snake_case` functions, vars, signals, files
- `PascalCase` class names, autoload names
- Private members prefixed `_`: `_next_facility_id`, `_load_data()`
- Predicates: `can_<action>`, `is_<state>`, `has_<thing>` — return `bool` or `{ ok: bool, reason: String }` for action-gating predicates
- Signals: past tense (`facility_placed`, `connection_created`), not commands

## Singleton + EventBus pattern

Every cross-system call goes through `EventBus`. Direct manager-to-manager calls are reserved for read-only queries (e.g. `DataManager.facilities.get(...)` is fine; `LogisticsManager.create_route(...)` from `WorldManager` is not — emit a signal).

```gdscript
# In WorldManager — emit, don't reach
func place_facility(...) -> String:
    var facility := { ... }
    _facilities[id] = facility
    EventBus.facility_placed.emit(facility)
    return id

# In ProductionManager — subscribe
func _ready() -> void:
    EventBus.facility_placed.connect(_on_facility_placed)

func _on_facility_placed(facility: Dictionary) -> void:
    if facility.has("production"):
        _start_production_timer(facility.id)
```

## Manager API shape — predicate-then-action

```gdscript
func can_place_facility(corp_id: String, facility_type: String, grid_pos: Vector2i) -> Dictionary:
    if not _is_in_bounds(grid_pos):
        return { "ok": false, "reason": "Out of bounds" }
    if _is_occupied(grid_pos):
        return { "ok": false, "reason": "Tile occupied" }
    if not _corp_can_build(corp_id, facility_type):
        return { "ok": false, "reason": "Corp %s cannot build %s" % [corp_id, facility_type] }
    return { "ok": true, "reason": "" }

func place_facility(corp_id: String, facility_type: String, grid_pos: Vector2i) -> String:
    var check := can_place_facility(corp_id, facility_type, grid_pos)
    if not check.ok:
        push_warning("Rejected place_facility: %s" % check.reason)
        return ""
    # ... actually place ...
```

UI calls `can_<action>` to grey out buttons. Manager re-checks before mutating. Never silently filter — explicit rejection with reason.

## Action pipe (Phase 8+)

All state mutations go through `GameManager.submit_action(corp_id, action_type, payload)`. The manager's mutator functions become callees of the pipe, not direct UI targets.

```gdscript
GameManager.submit_action(active_corp_id, "place_facility", {
    "facility_type": "brewery",
    "grid_pos": Vector2i(10, 10),
})

# In GameManager.submit_action
func submit_action(corp_id: String, action_type: String, payload: Dictionary) -> bool:
    match action_type:
        "place_facility":
            return WorldManager.place_facility(corp_id, payload.facility_type, payload.grid_pos) != ""
```

This is the seam that becomes the network boundary in Phase 12. Don't bypass it for "simple" mutations.

## Data-driven content

Content lives in `data/<type>.json`. `DataManager` loads at startup. Validate on load:

```gdscript
func _load_facilities() -> void:
    var path := "res://data/facilities.json"
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Cannot open %s" % path)
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        push_error("%s root is not Dictionary" % path)
        return
    facilities = parsed
```

Fail loud. Don't silently fall back to defaults — the player won't know the facility data is broken.

## Determinism rules (Phase 8+)

- **No `randf()` in tick code.** Use a seeded RNG passed via the action pipe (or a manager-owned `RandomNumberGenerator` with explicit seed).
- **No `Time.get_unix_time_from_system()` in game logic.** Use `GameManager.tick_count`.
- **Don't depend on dictionary iteration order for state mutation.** If order matters, `for key in dict.keys().sort()`. (Reads for display: order doesn't matter.)
- Vehicles already use fixed-tick movement — preserve that pattern.

## Save/load shape

```gdscript
func save_state() -> Dictionary:
    return {
        "version": 3,
        "corps": _save_corp_partition(),
        "shared": _save_shared_state(),
    }

func load_state(data: Dictionary) -> void:
    var version: int = data.get("version", 1)
    if version < 3:
        data = _migrate_to_v3(data, version)
    _load_corp_partition(data.corps)
    _load_shared_state(data.shared)
```

Bump `version` when schema changes. Always provide a migration. JSON, not binary — debugging > size.

**Stop alias-creep.** The codebase has been silently absorbing schema drift via getter aliases (`routes` → `connections`, `pickup_amount` → `vehicle_capacity`) without bumping `version`. From v3 onward this is forbidden — bump the version, write a migration, remove the aliases. Alias-creep is how MP determinism quietly breaks later.

## Common Godot 4.2 idioms in this codebase

- `Vector2i` for grid coords, `Vector2` for screen/world coords. Convert explicitly at the boundary.
- `@onready` for node refs from the scene tree. `%NodeName` syntax for unique-name lookups.
- Connect signals in `_ready()`, disconnect in `_exit_tree()` if the connection outlives the emitter.
- `class_name` only on classes that get instantiated multiple times. Singletons don't need it.
- Use `assert(condition, "message")` in dev for invariants — they get stripped in release builds.

## What to avoid

- Don't `await get_tree().process_frame` in tick code — breaks determinism.
- Don't store node refs across scene transitions — they get freed. Store ids and re-resolve.
- Don't put gameplay logic in `_process(delta)` for tick-based systems — use timers or game-tick subscribers.
- Don't `tool` mode managers — the autoload pattern doesn't need it and editor-running scripts cause weird bugs.
- Don't return early without a typed value — if `func foo() -> String`, never `return` on its own.
