# Phase 8 — Step 1: `corp_id` Ownership Field (No Behavior Change)

**Doc type:** Refactor plan, hand-off to drinkustry-implementer
**Date:** 2026-05-18
**Author:** Architect
**Scope:** Add `corp_id` to every owned-entity creation/serialization site. **No gating, no save bump, no action pipe.**
**Predecessor:** `design_docs/2026-05-07_technical_architecture.html` §3, §7 step 1
**Companion skill:** `.claude/skills/drinkustry-corp-ownership/SKILL.md`

---

## TL;DR for the implementer

You will add a `corp_id: String` field to facility, machine, route/connection, vehicle, and contract entity dicts. Everywhere those entities are constructed, `corp_id` is passed through as a parameter and defaults to the literal string `"single"`. You will also add `GameManager.active_corp_id` and a corp-id constants block. **Nothing reads the field for gating.** Save format does not bump (that is step 2). Action pipe is not built (that is step 3).

When you are done: place a brewery, save, load — brewery still works, brewery dict now has `"corp_id": "single"`, save file has `"corp_id": "single"` in it.

---

## Architectural notes that gate this plan

### A1 resolution: corp ownership immutable in v1, tradable later

**Decision:** Confirm immutable for v1, tradable in v1.5+. Validated by code review:

- Entity ids are opaque counters: `"facility_%d"`, `"machine_%d"`, `"conn_%d"`, `"vehicle_%d"`. **No corp prefix anywhere.** (`world_manager.gd:108`, `factory_manager.gd:132`, `logistics_manager.gd:222`, `logistics_manager.gd:379`)
- Save format stores ids as strings, not corp-keyed.
- Therefore: writing `corp_id` as a *mutable field on the entity dict* (not as part of the id) leaves the tradable-later door open. **Implementer constraint: do not encode corp_id into any id string.**

### Deferred (do not address in step 1)

A2 (hot-seat process model), A3 (save merging), A4 (overlay resolution), A5 (event triggers), A6 (determinism enforcement) — none gate this step. Leave them open.

### Anticipating aging + cider (`2026-05-07_aging_and_speculation.html`, `2026-05-07_orchards_and_cider_chain.html`)

New entity types those docs imply:

- **Aging-cellar / barrel-store / bottle-warehouse / wine-cellar** — they are *facilities*, will get `corp_id` automatically (industrial-owned default).
- **Aging batches inside cellars** — held inventory slots; owned by the facility that holds them, no separate `corp_id` needed.
- **Speculation contracts** — same shape as `MarketManager.active_contracts`; gets `corp_id` like contracts already do.
- **Orchard tiles** — *facilities* with `is_field`-like flag and lifecycle stages. Get `corp_id` via the same path as `barley_field`.
- **Cider brewery interior machines** — `corp_id` inherited from parent facility, same as existing brewery interior. No special handling.

**Conclusion:** the corp_id design proposed here does not need to bend for either doc. New entity types will fall out of the existing parameter path.

---

## Step skeleton (single commit, single PR)

Eight micro-steps, all in one commit. They are ordered for clean review but can ship together. If the diff balloons past ~400 lines, split between micro-step 5 and micro-step 6 (state plumbing vs serialization).

| # | What | Files touched |
|---|------|---------------|
| 1 | Define corp-id constants | `core/game_manager.gd` |
| 2 | Add `active_corp_id` field + signal | `core/game_manager.gd`, `core/event_bus.gd` |
| 3 | Add `corp_id` param to entity creators | `systems/world_manager.gd`, `systems/factory_manager.gd`, `systems/logistics_manager.gd`, `systems/market_manager.gd` |
| 4 | Plumb `corp_id` through call sites | `scenes/world_map/world_map.gd`, `scenes/factory_interior/factory_interior.gd`, `scenes/ui/logistics_network_panel.gd` |
| 5 | Carry `corp_id` to derived entities | `systems/factory_manager.gd` (machine inherits), `systems/logistics_manager.gd` (vehicle inherits) |
| 6 | Serialize/deserialize `corp_id` | `core/save_manager.gd` (no version bump) |
| 7 | Defer JSON `default_corp` (recommendation only) | none |
| 8 | Smoke test + checkpoints | manual |

---

## Micro-step 1 — Corp-id constants

**File:** `core/game_manager.gd`
**Where:** New section near top, after the `GameState` enum, before `current_state`.

```gdscript
# ========================================
# CORP OWNERSHIP CONSTANTS
# ========================================
#
# Valid corp_id values across all owned entities. See:
#   - design_docs/2026-05-07_technical_architecture.html §3
#   - .claude/skills/drinkustry-corp-ownership/SKILL.md
#
# Step 1 of Phase 8: every owned entity carries `corp_id` but nothing
# reads it for gating yet. All entities default to CORP_SINGLE during
# this phase. The action pipe (step 3) and predicates (step 4) come later.

const CORP_AGRI: String = "agri"
const CORP_INDUSTRIAL: String = "industrial"
const CORP_LOGISTICS: String = "logistics"
const CORP_BUSINESS: String = "business"
const CORP_SHARED: String = "shared"        # cross-corp infra (roads, utilities, shared research)
const CORP_SINGLE: String = "single"        # legacy / no-op default during step 1; replaced by real corp once action pipe lands

const VALID_CORP_IDS: Array[String] = [
    CORP_AGRI,
    CORP_INDUSTRIAL,
    CORP_LOGISTICS,
    CORP_BUSINESS,
    CORP_SHARED,
    CORP_SINGLE,
]
```

**Done when:** Constants exist; game still launches; `print(GameManager.CORP_AGRI)` prints `"agri"`.

**Depends on:** nothing.

---

## Micro-step 2 — `active_corp_id` field and signal

### 2a. Field on GameManager

**File:** `core/game_manager.gd`
**Where:** Inside `GAME STATE` block, near `active_factory_id`.

Before:
```gdscript
# Active factory being viewed (null when on world map)
var active_factory_id: String = ""
```

After:
```gdscript
# Active factory being viewed (null when on world map)
var active_factory_id: String = ""

# Currently active corp (hot-seat: which corp the player is acting as).
# Step 1 default: CORP_SINGLE. Real corp switching arrives with the hot-seat
# corp-switcher UI in a later step (per technical-architecture §3.1).
var active_corp_id: String = CORP_SINGLE
```

### 2b. Setter and signal

**File:** `core/event_bus.gd`
**Where:** New section after `GAME STATE SIGNALS` (~line 23).

```gdscript
## Emitted when the active corp changes (hot-seat switcher / network connect).
signal active_corp_changed(old_corp_id: String, new_corp_id: String)
```

**File:** `core/game_manager.gd`
**Where:** New function in a fresh section after `GAME STATE MANAGEMENT`.

```gdscript
# ========================================
# CORP MANAGEMENT
# ========================================

func set_active_corp(corp_id: String) -> void:
    """Switch the active corp. In step 1 this is only called manually for testing.
    The hot-seat switcher UI hooks into this in a later step."""
    if corp_id == active_corp_id:
        return
    if corp_id not in VALID_CORP_IDS:
        push_error("Invalid corp_id: %s" % corp_id)
        return

    var old_corp_id := active_corp_id
    active_corp_id = corp_id
    EventBus.active_corp_changed.emit(old_corp_id, corp_id)
    print("Active corp: %s -> %s" % [old_corp_id, corp_id])
```

**Done when:** `GameManager.active_corp_id == "single"` at startup; calling `GameManager.set_active_corp("agri")` flips the field and emits the signal.

**Depends on:** micro-step 1.

---

## Micro-step 3 — Add `corp_id` parameter to entity creators

For each function below, add `corp_id: String = GameManager.CORP_SINGLE` as the **last** parameter (default lets old call sites compile while you walk through them in micro-step 4). Then write the field into the entity dict, **directly under `id`** (top of the dict, for readability and to match the skill's example).

### 3a. `WorldManager.place_facility`

**File:** `systems/world_manager.gd:98`

Before:
```gdscript
func place_facility(facility_type: String, grid_pos: Vector2i, facility_data: Dictionary = {}) -> String:
    ...
    var facility = {
        "id": facility_id,
        "type": facility_type,
        "grid_pos": grid_pos,
        ...
    }
```

After:
```gdscript
func place_facility(facility_type: String, grid_pos: Vector2i, facility_data: Dictionary = {}, corp_id: String = GameManager.CORP_SINGLE) -> String:
    ...
    var facility = {
        "id": facility_id,
        "corp_id": corp_id,         # Phase 8 step 1: ownership field. No gating yet.
        "type": facility_type,
        "grid_pos": grid_pos,
        ...
    }
```

**Note:** `facility_data` is merged via `facility.merge(facility_data, true)` (line 133). The `true` flag means caller-provided data wins, so if a caller passes `corp_id` inside `facility_data` it overrides the parameter. That is intentional (used by save-load restore path).

### 3b. `FactoryManager.place_machine`

**File:** `systems/factory_manager.gd:119`

Before:
```gdscript
func place_machine(facility_id: String, machine_type: String, grid_pos: Vector2i, machine_data: Dictionary = {}) -> String:
    ...
    var machine = {
        "id": machine_id,
        "type": machine_type,
        ...
    }
```

After:
```gdscript
func place_machine(facility_id: String, machine_type: String, grid_pos: Vector2i, machine_data: Dictionary = {}, corp_id: String = "") -> String:
    """Place a machine. corp_id defaults to parent facility's corp_id (inherits).
    Explicit pass-through only matters when caller knows the parent ownership doesn't apply
    (which it always does for v1 — kept for API symmetry with place_facility)."""
    ...
    # Inherit corp_id from parent facility unless explicitly overridden.
    var resolved_corp_id := corp_id
    if resolved_corp_id == "":
        var parent_facility := WorldManager.get_facility(facility_id)
        resolved_corp_id = parent_facility.get("corp_id", GameManager.CORP_SINGLE)

    var machine = {
        "id": machine_id,
        "corp_id": resolved_corp_id,    # Phase 8 step 1: inherited from parent facility.
        "type": machine_type,
        ...
    }
```

**Why inherit not pass-through:** the skill (line 117) is explicit — *"Machines inside a factory inherit the factory's corp_id implicitly… Don't hardcode anywhere; query the parent facility's corp_id."* This is the cheapest, correct read.

### 3c. `LogisticsManager.create_connection` (and the `create_route` alias)

**File:** `systems/logistics_manager.gd:194`

Per the technical doc A7 recommendation and the skill (line 109), **routes default to `CORP_LOGISTICS`** in v1 — Logistics is the broker for cross-corp transport. Until the action pipe lands, that means the literal `"logistics"`, *not* `"single"`. This is the one place where the step-1 default is not `"single"` — it is `"logistics"`. Document this clearly with a comment.

Before:
```gdscript
func create_connection(source_id: String, destination_id: String, product: String) -> String:
    ...
    var connection = {
        "id": connection_id,
        "source_id": source_id,
        ...
    }
```

After:
```gdscript
func create_connection(source_id: String, destination_id: String, product: String, corp_id: String = GameManager.CORP_LOGISTICS) -> String:
    """Create a route between facilities.
    Per technical-architecture A7: Logistics owns transport routes in v1.
    Default corp_id is CORP_LOGISTICS, not CORP_SINGLE — Logistics is the broker.
    Cross-corp negotiation UI is a v1.5 feature."""
    ...
    var connection = {
        "id": connection_id,
        "corp_id": corp_id,           # Phase 8 step 1: Logistics-owned by default.
        "source_id": source_id,
        ...
    }
```

**Note for the implementer:** `create_route()` at `logistics_manager.gd:188` is an alias that just calls `create_connection()`. Update its signature to match and forward the parameter:

```gdscript
func create_route(source_id: String, destination_id: String, product: String, corp_id: String = GameManager.CORP_LOGISTICS) -> String:
    return create_connection(source_id, destination_id, product, corp_id)
```

### 3d. `LogisticsManager._create_vehicle`

**File:** `systems/logistics_manager.gd:376`

Vehicles inherit from their parent connection.

Before:
```gdscript
func _create_vehicle(connection_id: String, source_id: String, destination_id: String, path: Array = []) -> String:
    ...
    var vehicle = {
        "id": vehicle_id,
        "connection_id": connection_id,
        ...
    }
```

After:
```gdscript
func _create_vehicle(connection_id: String, source_id: String, destination_id: String, path: Array = []) -> String:
    ...
    # Vehicles inherit corp_id from their parent connection. No separate parameter
    # because vehicles are never created outside the auto-dispatch path inside this manager.
    var parent_connection := connections.get(connection_id, {})
    var vehicle_corp_id: String = parent_connection.get("corp_id", GameManager.CORP_LOGISTICS)

    var vehicle = {
        "id": vehicle_id,
        "corp_id": vehicle_corp_id,    # Phase 8 step 1: inherited from connection.
        "connection_id": connection_id,
        ...
    }
```

### 3e. `MarketManager._generate_random_contract`

**File:** `systems/market_manager.gd:303`

Contracts default to `CORP_BUSINESS` per the skill (line 33 — "Sales outlets and trade depots") and the technical doc §3.1 ("set when contract is offered; only owner can accept").

Before:
```gdscript
func _generate_random_contract() -> Dictionary:
    ...
    return {
        "id": _next_contract_id,
        "product": product,
        ...
    }
```

After:
```gdscript
func _generate_random_contract() -> Dictionary:
    ...
    return {
        "id": _next_contract_id,
        "corp_id": GameManager.CORP_BUSINESS,    # Phase 8 step 1: contracts are Business-owned in v1.
        "product": product,
        ...
    }
```

**Done when:** every entity-creator function above writes a `corp_id` key. No call site updated yet; everything still compiles because all new params have defaults.

**Depends on:** micro-step 1.

---

## Micro-step 4 — Plumb `corp_id` through call sites

Walk every call site identified by grep. For step 1, **always pass `GameManager.active_corp_id`** at the UI seam. This is the seam that will become `submit_action(active_corp_id, …)` in step 3 — establishing it now means step 3 is a wrap, not a refactor.

### 4a. `scenes/world_map/world_map.gd:441`

Before:
```gdscript
var facility_id = WorldManager.place_facility(placement_facility_id, mouse_grid_pos, {
    ...
})
```

After:
```gdscript
var facility_id = WorldManager.place_facility(placement_facility_id, mouse_grid_pos, {
    ...
}, GameManager.active_corp_id)
```

### 4b. `scenes/world_map/world_map.gd:578`

Same shape — append `, GameManager.active_corp_id` to the `place_facility(...)` call.

### 4c. `scenes/world_map/world_map.gd:1661` (field placement under farmhouse)

Same shape — append `, GameManager.active_corp_id`.

**Implementation note:** fields placed under a farmhouse logically *should* inherit the farmhouse's corp_id, not `active_corp_id`. In step 1 these are always equal (single-player). The right long-term behavior is the action pipe enforcing "you can only place a field under a farmhouse you own," which makes them equal by predicate. For step 1, pass `active_corp_id` — it works and avoids reaching across managers for the parent farmhouse's corp_id here.

### 4d. `scenes/world_map/world_map.gd:883` (create_route)

Before:
```gdscript
var route_id = LogisticsManager.create_route(route_source_id, route_destination_id, product)
```

After:
```gdscript
# Routes are Logistics-owned in v1 (technical-architecture A7); omit corp_id to take the default.
var route_id = LogisticsManager.create_route(route_source_id, route_destination_id, product)
```

**Leave the call site unchanged.** The default parameter on `create_route()` is already `CORP_LOGISTICS`, which is the correct v1 behavior. Just add the comment so the next reader knows why.

### 4e. `scenes/ui/logistics_network_panel.gd:87` (create_connection)

Same treatment as 4d — leave unchanged, add comment.

### 4f. `scenes/factory_interior/factory_interior.gd:293`

Before:
```gdscript
var machine_id = FactoryManager.place_machine(facility_id, placement_machine_id, mouse_grid_pos, {
    ...
})
```

After:
```gdscript
# Machine corp_id is inherited from the parent facility — no need to pass active_corp_id.
var machine_id = FactoryManager.place_machine(facility_id, placement_machine_id, mouse_grid_pos, {
    ...
})
```

**Leave the call site unchanged.** The default `corp_id = ""` triggers the inherit-from-parent path in `place_machine()`. Add the comment.

### 4g. `scenes/factory_interior/factory_interior.gd:360` (FactoryManager.create_connection)

This is a *machine* connection inside a factory interior, not a logistics route. Schema-wise, machine-to-machine connections live inside `interior.connections` as `{from, to}` dicts. **They do not get `corp_id`** — they are scoped to their parent factory, which already has it. Leave this call site alone.

**Done when:** all seven call sites above are reviewed; the three that need updating are updated; the four that take the default are commented. Game still launches; placing a facility still works.

**Depends on:** micro-step 3.

---

## Micro-step 5 — Carry `corp_id` on derived entities

Already handled in micro-step 3 (machine inherits from facility, vehicle inherits from connection). Nothing additional here — call this step a verification pass:

- [ ] `place_machine()` reads `WorldManager.get_facility(facility_id).corp_id` on the inherit path
- [ ] `_create_vehicle()` reads `connections[connection_id].corp_id` on the inherit path
- [ ] Both have a sane fallback (`CORP_SINGLE` / `CORP_LOGISTICS`) if the parent lookup fails (e.g., during save-load reconstruction order)

**Done when:** verification checklist passes by code reading.

**Depends on:** micro-step 3.

---

## Micro-step 6 — Save/load `corp_id` (no version bump)

The save file shape does change (new field appears in each entity object), but the *version* does not bump. This is acceptable for step 1 because:

1. The save schema bump to v3 is step 2 of the refactor ordering. Step 2 will read `version < 3` and run a migration that, among other things, ensures every entity has a `corp_id`.
2. Older saves loaded by step-1 code will simply not have `corp_id` in their entity dicts. The reconstruction code below handles that via `.get("corp_id", CORP_SINGLE)`.
3. Newer saves loaded by older code would have an extra ignored key. GDScript dict reconstruction in `save_manager.gd` is explicit about which keys it reads, so the new key is silently dropped — no crash.

**This is the only place in step 1 where you tolerate a missing field.** Every other path treats `corp_id` as required.

### 6a. `_gather_world_data()` — `core/save_manager.gd:221`

Add `"corp_id": facility.get("corp_id", GameManager.CORP_SINGLE),` to the `facilities_data[facility_id]` dict at line 227. Place it directly after `"id"`.

### 6b. `_gather_factory_data()` — `core/save_manager.gd:263`

Add `"corp_id": machine.get("corp_id", GameManager.CORP_SINGLE),` to the `machines_data[machine_id]` dict at line 274. Place it directly after `"id"`.

### 6c. `_gather_logistics_data()` — `core/save_manager.gd:300`

Add `"corp_id": connection.get("corp_id", GameManager.CORP_LOGISTICS),` to `connections_data[connection_id]` at line 309.
Add `"corp_id": vehicle.get("corp_id", GameManager.CORP_LOGISTICS),` to `vehicles_data[vehicle_id]` at line 334.

### 6d. `MarketManager.get_save_data()` — `systems/market_manager.gd:411`

Contracts are stored inside `active_contracts.duplicate(true)` — the duplicate deep-copies the corp_id field automatically once it exists on the contract dict (from micro-step 3e). No change needed here.

### 6e. Restore paths — `core/save_manager.gd:489` onward

For each entity restored, add `"corp_id"` to the reconstructed dict, defaulting from the saved data with the same fallback used in `_gather_*`:

`_restore_world_data` at line 500:
```gdscript
var facility = {
    "id": fac_data.id,
    "corp_id": fac_data.get("corp_id", GameManager.CORP_SINGLE),
    "type": fac_data.type,
    ...
}
```

`_restore_factory_data` at line 575:
```gdscript
var machine = {
    "id": mach_data.id,
    "corp_id": mach_data.get("corp_id", GameManager.CORP_SINGLE),
    "type": mach_data.type,
    ...
}
```

`_restore_logistics_data` at line 625:
```gdscript
var connection = {
    "id": connection_data.id,
    "corp_id": connection_data.get("corp_id", GameManager.CORP_LOGISTICS),
    "source_id": connection_data.source_id,
    ...
}
```

`_restore_logistics_data` at line 654:
```gdscript
var vehicle = {
    "id": vehicle_data.id,
    "corp_id": vehicle_data.get("corp_id", GameManager.CORP_LOGISTICS),
    "connection_id": connection_id,
    ...
}
```

**Done when:** save → reload → confirm via `print(WorldManager.facilities)` that every facility has `corp_id`.

**Depends on:** micro-step 3.

---

## Micro-step 7 — JSON `default_corp` field on facility/machine defs (DEFER)

**Recommendation: do not add `default_corp` to `data/facilities.json` / `data/machines.json` in step 1.**

Reasoning:

1. The action pipe (step 3) does not exist yet. Without it, `default_corp` has no consumer — `place_facility(corp_id)` already takes the corp explicitly from the UI seam.
2. The technical doc's migration map (§3.4) already encodes facility-type → corp ("fields → agri, breweries → industrial," etc.). When migration lands in step 2, that map lives in `SaveManager._facility_type_to_corp()` per the skill (line 77).
3. Putting it in JSON now creates a second source of truth (JSON `default_corp` vs the migration map vs hard-coded build-menu permissions) before any of them are needed. Pick the consumer first; let the data shape follow.

**Defer to:** Phase 8 step 5 ("per-corp build menus"). At that point, `data/facilities.json` gains a `corp: "industrial"` (or `corp: ["industrial", "agri"]` for shared buildings) field that drives both the build menu filter and the `place_facility` corp_id pre-fill. The exact shape is settled there.

**Done when:** the implementer reads this and does not edit the JSON files.

**Depends on:** nothing — this is an explicit non-action.

---

## Micro-step 8 — Smoke test

Minimum verification — no automated tests, just a manual play loop:

1. Launch project, console shows `Active corp: single -> single` (or no message, since startup doesn't call set_active_corp).
2. Place a Barley Field. Console message includes the facility id.
3. In the Godot debugger / via a quick `print(WorldManager.facilities)` call, confirm the new facility dict contains `"corp_id": "single"`.
4. Place a Brewery; enter its interior; place a Mash Tun.
5. Confirm `print(FactoryManager.factory_interiors[brewery_id].machines)` shows `"corp_id": "single"` on the Mash Tun.
6. Create a route between field and brewery (via roads). Confirm the connection dict has `"corp_id": "logistics"` — **the one place a non-single default lives.**
7. Watch a vehicle auto-dispatch. Confirm vehicle dict has `"corp_id": "logistics"`.
8. F5 quick save. Open the save file in a text editor; grep for `corp_id` — should appear on every facility, every machine, every connection, every vehicle.
9. F9 quick load. Confirm all entities restore with their `corp_id` intact.
10. Console run: `GameManager.set_active_corp("agri")` — confirm signal fires (you'll see the print line).
11. Place a new facility after switching to agri — confirm its `corp_id` is `"agri"` in the dict, while the brewery placed earlier still has `"single"`. **This is the proof the field is live and propagated, not a hardcoded constant.**

**Done when:** all 11 checks pass.

**Depends on:** all prior micro-steps.

---

## Explicit non-goals for this step

These are explicitly **out of scope** for step 1. If the implementer is tempted, push back:

| Out of scope | Why | Lands in |
|---|---|---|
| Save schema version bump | Step 2 owns the v3 schema + migration | Step 2 |
| `submit_action()` skeleton on GameManager | Step 3 owns the action pipe | Step 3 |
| `can_<action>(corp_id, ...)` predicates | Step 3/4; predicates need the pipe | Step 3 then refined in step 4 |
| Corp switcher UI | Needs per-corp build menus first | Step 5+ |
| Two-layer tech tree (`tier: corp_internal`) | Independent refactor, step 4 of the master ordering | Step 4 of master |
| Per-corp money on EconomyManager | Phase 8 entry checklist item, but distinct from corp_id on entities | Step 2 or 3 |
| Per-corp partition of research unlocks | Comes with tech-tree refactor | Step 4 of master |
| `data/facilities.json` `default_corp` field | No consumer until per-corp build menus | Step 5 of master |
| `data/corps.json` | Technical doc §10 says corps are hardcoded in v1 | Never (post-v1) |
| Determinism fixes (`randf()` in MarketManager) | Distinct Phase 8 checklist item; orthogonal to ownership | Phase 8 entry checklist (separate ticket) |

---

## Files touched (final inventory)

```
core/event_bus.gd                       (+3 lines)  — active_corp_changed signal
core/game_manager.gd                    (+30 lines) — corp constants, active_corp_id, set_active_corp
core/save_manager.gd                    (+8 lines)  — corp_id in gather/restore for facility, machine, connection, vehicle
systems/world_manager.gd                (+3 lines)  — corp_id param + dict field
systems/factory_manager.gd              (+6 lines)  — corp_id param + inherit logic
systems/logistics_manager.gd            (+8 lines)  — corp_id on connection/route/vehicle, inherit logic
systems/market_manager.gd               (+1 line)   — corp_id on contract
scenes/world_map/world_map.gd           (+3 lines)  — pass active_corp_id at three place_facility seams
```

Estimated diff: ~60 lines added across 8 files. Single PR.

**Files explicitly NOT touched:**
- `data/facilities.json`, `data/machines.json` — deferred (micro-step 7)
- `systems/research_manager.gd` — research-per-corp lands in step 4 of master ordering
- `systems/economy_manager.gd` — per-corp money lands separately
- All other UI files — they read entity dicts but don't iterate or serialize keys, so the new field is invisible to them

---

## Open questions you don't need to resolve

A2, A3, A4, A5, A6 from `2026-05-07_technical_architecture.html` §11 — deferred. None block step 1.

## One open question this step *does* surface

**Q (mark for follow-up):** When a field is placed *under* a farmhouse via the farmhouse UI (`world_map.gd:1661`), should the field's `corp_id` come from `GameManager.active_corp_id` or from the parent farmhouse's `corp_id`? In step 1 these are always equal so the answer doesn't matter. In step 3 (action pipe), the predicate "you may only place a field under a farmhouse you own" forces them equal. **No action needed in step 1; flag for predicate-design conversation in step 3.**
