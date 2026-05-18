# Phase 8 — Step 3: Action Pipe Scaffold (`submit_action`) and Predicate Gating

**Doc type:** Refactor plan, hand-off to drinkustry-implementer
**Date:** 2026-05-18
**Author:** Architect
**Scope:** Add `GameManager.submit_action(corp_id, action_type, payload) -> bool` and route every UI-driven state mutation through it. Add `can_<action>(corp_id, ...) -> Dictionary { ok, reason }` predicates on every mutator. Reset `active_corp_id` in `reset_game()`. **No real corp gating** — predicates pass trivially in v1; they exist to fix the shape so Phase 10 fills them in without re-wiring the call sites.
**Predecessor:** `design_docs/plans/2026-05-18_phase8_step2_save_v3.md`
**Successor:** Phase 8 step 4 — tech-tree two-layer refactor.
**Companion skills:** `.claude/skills/drinkustry-corp-ownership/SKILL.md`, `.claude/skills/drinkustry-add-system/SKILL.md`, `.claude/skills/godot-gdscript-conventions/SKILL.md`

---

## TL;DR for the implementer

You will add `submit_action(corp_id, action_type, payload) -> bool` on `GameManager`. It dispatches by `action_type` string to manager mutators. Every UI site that today calls a manager mutator directly (e.g. `WorldManager.place_facility(...)`) instead calls `GameManager.submit_action(GameManager.active_corp_id, ACTION_PLACE_FACILITY, {...})`. Each manager mutator gets a paired `can_<action>(corp_id, ...) -> Dictionary` predicate that returns `{ ok: bool, reason: String }`. Mutators re-check the predicate before mutating. UI uses the predicate to grey out buttons (optional in step 3 — required in later phases).

**What this is not:**
- Not a real gating step — predicates trivially pass in v1 (no corp switcher UI, `active_corp_id == CORP_SINGLE`)
- Not a save bump — schema stays v3
- Not a networking step — the pipe is in-process; Phase 12 swaps the transport
- Not a determinism step — RNG seeding lands separately
- Not an undo/redo system — actions are not reversible

**What it absolutely is:** the seam where every state mutation funnels. Every line of mutator code written from this commit onward enters via `submit_action`. No exceptions, including internal-use actions like `ACTION_SPEND_MONEY` (see §0.4).

When you are done:

- Placing a facility, demolishing a facility, building a road, creating/removing a connection, placing/demolishing a machine, creating/removing a machine-machine connection, researching a tech, accepting/cancelling a contract, setting a farmhouse crop type **all** funnel through `submit_action`.
- Every mutator above has a `can_<action>(corp_id, ...)` predicate; the mutator re-checks it before applying state changes.
- `reset_game()` resets `active_corp_id` to `CORP_SINGLE`.
- A grep for the legacy direct-mutator call pattern from `scenes/` returns nothing except the four explicitly-allowed paths in §11.
- The smoke test in §10 passes end-to-end.

**Diff target: ~600–800 lines across `core/game_manager.gd` (+150), the six managers (+200 across), and the UI files (~250 lines net for call-site rewires). One PR; recommended decomposition into 4 commits in §13.**

---

## 0. Architectural decisions baked into this plan

### 0.1 The pipe lives on `GameManager`, predicates live on the managers

`GameManager.submit_action` is the network seam. Predicates live on the managers that own the data. Reason: `GameManager` is corp-blind today; if it had the predicates, it would have to reach into every manager's private state to check ownership, occupancy, etc. Manager-owned predicates keep `GameManager.submit_action` a thin dispatch shell that any future network layer can swap.

```
UI call site
   │
   ▼
GameManager.submit_action(corp_id, ACTION_X, payload)
   │
   ├── validate payload keys     ◄── shape check; cheap; pipe-side
   │
   ├── manager.can_X(corp_id, …) ◄── ownership / state check; manager-side
   │
   ├── manager.X(corp_id, …)     ◄── mutation; manager re-checks the predicate;
   │                                 emits EventBus signal as consequence
   │
   ▼
return bool
```

### 0.2 Action-type strings are stable identifiers

Action types are `const String` on `GameManager` (`ACTION_PLACE_FACILITY = "place_facility"`, etc.). UI code uses the constant; the string is what the network layer in Phase 12 will dispatch on. **Renaming a constant in step 3 is fine; renaming the underlying string later is a network-protocol break.** Pick names now and own them — short, snake_case, present-tense imperative (`"place_facility"`, not `"facility_placed"` — `facility_placed` is the EventBus signal name and intentionally past-tense).

The action-type string list lives in one block on `GameManager` (§2). When a new mutator is added to any manager, the implementer adds the constant in the same commit.

### 0.3 `submit_action` returns `bool`, not the rich result

Originally proposed in technical-architecture §4.4 as `{ accepted: bool, reason: String, action_id: int }`. Decision: **collapse to bool** for step 3.

- `action_id` is a Phase-12 networking concept — it's the sequence number the host assigns when broadcasting; in-process v1 has no need.
- The rejection reason is already pushed via `push_warning` from the manager mutator's predicate re-check; UI doesn't currently surface it in a richer way than the existing warning banner.
- A bool return is what every existing UI call site already expects (existing manager mutators return `String` for place/create — empty on failure — or `bool`; both collapse cleanly to "did the action succeed?").

**Phase 12 will widen the return to a dict** — that's a deliberate widening, not a contract break. Add a TODO in `submit_action`'s docstring noting this.

### 0.4 Internal-use actions go through the pipe too

`EconomyManager.subtract_money(cost, reason)` is called by UI (road placement, field placement), by other managers (`ResearchManager.research`, `WorldManager._remove_field_for_road` → `refund_facility`), and internally by `purchase_facility`. **All three paths route through the pipe.**

Reasoning:
1. **Network consistency.** Money is shared state (`shared.money` in save v3). In Phase 12, every monetary change must be ordered through the host. If 90% of `subtract_money` calls go through the pipe and 10% bypass it, the 10% becomes a desync source.
2. **Determinism.** All mutations on `shared.money` are funneled through one place. Useful even pre-MP for replay/audit.
3. **Cheap to ship.** EconomyManager already has a clean entry point; we just rename UI/manager call sites to `submit_action`.

Action types added: `ACTION_SPEND_MONEY`, `ACTION_EARN_MONEY`. These are corp-blind in v1 (corp_id is `active_corp_id` which is `CORP_SINGLE`) — they prefigure the per-corp wallet refactor (v3→v4) without forcing it now.

**The one exception:** `EconomyManager.add_money` and `subtract_money` called from inside `purchase_facility` / `refund_facility` / `sell_product` / `_collect_maintenance` are internal compositional calls and stay direct — they're already inside an action being executed. The action pipe must not re-enter itself; it would double-validate and emit the EventBus signal twice. **Rule: once you're inside a manager mutator running on behalf of `submit_action`, downstream manager calls are direct.** This is the same pattern as transactional code in any system.

### 0.5 EventBus signal discipline

EventBus signals are emitted by **manager mutators after they apply state changes**, exactly as today. The action pipe does not emit EventBus signals itself. UI subscribes to EventBus and updates its own state in response.

```
GameManager.submit_action calls WorldManager.place_facility
WorldManager.place_facility mutates _facilities, emits EventBus.facility_placed
UI's subscriber to facility_placed redraws the facility in the world
```

This is the existing pattern; step 3 does not change it. The only thing that changes is **how the mutator is invoked**. The signal carries the action's *effect* (the new facility dict, the removed id), not the action's intent (which lives in the pipe's parameters).

**Load-bearing flag:** the manager mutator emits exactly *once* per action. A predicate failure path emits *nothing* (and the UI doesn't update — it reads the bool return). Don't add a "rejection" EventBus signal; UI gates via the bool return and the `push_warning` log.

### 0.6 What does NOT change in step 3 (explicit non-goals)

| Out of scope | Why | Lands in |
|---|---|---|
| Real corp gating (predicate fails when corp_id ≠ owner) | No corp switcher UI; `active_corp_id == CORP_SINGLE` always | Phase 10 (per-corp build menus) |
| Corp switcher UI | Per-corp build menus first, then switcher | Phase 10 |
| Money refactor (per-corp wallets) | Stays `shared.money`; v3→v4 migration owns this | EconomyManager refactor (Phase 8 later step) |
| Two-layer tech tree | Step 4 of master ordering | Step 4 |
| `submit_action` returns rich dict | Step 3 ships `bool`; Phase 12 widens | Phase 12 |
| Networking glue | Phase 12 by definition | Phase 12 |
| Determinism enforcement (RNG seeding) | Distinct Phase 8 entry-checklist item | Separate ticket |
| Event-engine integration | EventManager doesn't exist | Phase 11 |
| Undo/redo | Actions are not reversible per technical-architecture §4.4 | Never (out of scope by design) |

---

## 1. Mutator inventory — everything that needs an action

Walked every public mutator across all managers. Total **22 distinct mutators** routed through the pipe in step 3, plus 3 internal compositional mutators that stay direct (called from inside other mutators; see §0.4).

### 1.1 WorldManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `place_facility` | `(facility_type, grid_pos, facility_data={}, corp_id=CORP_SINGLE) -> String` | `ACTION_PLACE_FACILITY` | Partial — `can_place_facility(grid_pos, size)` exists; **lacks corp_id param** | `world_map.gd:441`, `world_map.gd:578`, `world_map.gd:1661` | Wrap. Predicate gains `corp_id` param. |
| `remove_facility` | `(facility_id) -> bool` | `ACTION_DEMOLISH_FACILITY` | No | `world_map.gd:1074`, `world_map.gd:2230` | New predicate `can_remove_facility(corp_id, facility_id)`. |
| `place_road` | `(grid_pos, road_type="dirt_road") -> bool` | `ACTION_PLACE_ROAD` | Partial — `can_place_road(grid_pos)` exists, no corp_id | `world_map.gd:1208`, `world_map.gd:1323` | Wrap. Predicate gains corp_id. Roads are CORP_SHARED. |
| `remove_road` | `(grid_pos) -> bool` | `ACTION_REMOVE_ROAD` | No | **No UI call site** in v1 (only `road_renderer._remove_road_tile` is visual cleanup driven by the EventBus signal). | Add the action + predicate anyway for symmetry — Phase 10 logistics signature mechanic will need it. |
| `start_production` | `(facility_id) -> bool` | `ACTION_START_PRODUCTION` | No | Called by `EconomyManager._enable_facility` (internal — stays direct) | **Skip routing in step 3.** This is currently always internal-use; if a UI path ever calls it, route then. Mark as deferred in code comment. |
| `stop_production` | `(facility_id) -> bool` | `ACTION_STOP_PRODUCTION` | No | Called by `EconomyManager._disable_facility` (internal — stays direct) | Same as above; **skip routing in step 3**. |
| `complete_construction` | `(facility_id) -> void` | `ACTION_COMPLETE_CONSTRUCTION` | No | `world_map.gd:447`, `world_map.gd:583`, `world_map.gd:1668` | **Skip routing in step 3.** This is currently a UI-side post-place auto-complete (no construction-time-in-MVP semantic). It is always called immediately after a successful `place_facility` in the same code path. Rolling it into `ACTION_PLACE_FACILITY` is cleaner — see §1.7. |
| `register_field_with_farmhouse` | `(field_id, farmhouse_id) -> void` | (part of `ACTION_PLACE_FIELD`) | No | `world_map.gd:1671` | Roll into `ACTION_PLACE_FIELD`. See §1.7. |

### 1.2 FactoryManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `place_machine` | `(facility_id, machine_type, grid_pos, machine_data={}, corp_id="") -> String` | `ACTION_PLACE_MACHINE` | Partial — `can_place_machine(facility_id, grid_pos, size)` exists, no corp_id | `factory_interior.gd:293` | Wrap. Predicate gains corp_id. |
| `remove_machine` | `(facility_id, machine_id) -> bool` | `ACTION_DEMOLISH_MACHINE` | No | `factory_interior.gd:690` | New predicate. |
| `create_connection` *(machine-to-machine, factory-internal)* | `(facility_id, from_machine_id, to_machine_id) -> bool` | `ACTION_CREATE_MACHINE_CONNECTION` | No | `factory_interior.gd:360` | New predicate. **Distinct from LogisticsManager.create_connection.** |
| `remove_connection` *(machine-to-machine)* | `(facility_id, from_machine_id, to_machine_id) -> bool` | `ACTION_REMOVE_MACHINE_CONNECTION` | No | `factory_interior.gd:460` | New predicate. |
| `create_factory_interior` | `(facility_id) -> Dictionary` | (none — internal) | No | Auto-called by `_on_facility_placed` and `get_factory_interior` | **Not routed.** Pure derived state; created in response to `facility_placed` signal. |

### 1.3 LogisticsManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `create_connection` | `(source_id, destination_id, product, corp_id=CORP_LOGISTICS) -> String` | `ACTION_CREATE_LOGISTICS_CONNECTION` | No (inline validation: facilities exist, road path exists, no duplicate) | `world_map.gd:883`, `logistics_network_panel.gd:87` | Wrap. Inline validation moves to predicate. |
| `remove_connection` | `(connection_id) -> bool` | `ACTION_REMOVE_LOGISTICS_CONNECTION` | No | `world_map_ui.gd:621`, `logistics_network_panel.gd:95` | New predicate. |
| `set_connection_active` | `(connection_id, active) -> bool` | `ACTION_SET_CONNECTION_ACTIVE` | No | (none — only `toggle_*` used by UI) | Add for symmetry; route only if needed in step 3. **Defer — no UI driver.** |
| `toggle_connection_active` | `(connection_id) -> bool` | `ACTION_TOGGLE_CONNECTION_ACTIVE` | No | `world_map_ui.gd:615` | Wrap. New predicate. |
| `_create_vehicle` | `(connection_id, source_id, destination_id, path=[]) -> String` | (none — internal) | n/a | Auto-dispatch | **Not routed.** Internal to auto-dispatch tick. |
| `_remove_vehicle` | `(vehicle_id) -> void` | (none — internal) | n/a | Internal | **Not routed.** Internal to delivery tick. |

### 1.4 EconomyManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `add_money` | `(amount, reason="") -> void` | `ACTION_EARN_MONEY` | No (defensive `amount > 0` check only) | `world_map.gd:1071`, `factory_interior.gd:682` (refunds) | Wrap **only the direct UI call sites**. The internal compositional calls (from `sell_product`, `refund_facility`, contract reward) stay direct per §0.4. |
| `subtract_money` | `(amount, reason="") -> bool` | `ACTION_SPEND_MONEY` | No (`can_afford` is the read predicate; promote to full `can_spend_money`) | `world_map.gd:1207`, `world_map.gd:1322`, `world_map.gd:1658`, `factory_interior.gd:288` | Wrap **only direct UI sites**. Internal calls from `purchase_facility`, `pay_maintenance`, research, contracts stay direct. |
| `set_money` | `(amount) -> void` | (none — load/cheat only) | n/a | Used during save-load restore only | **Not routed.** Save-load is pre-network; saves are local. |
| `reset_economy` | `() -> void` | (none — driven by `reset_game`) | n/a | Internal to `GameManager.reset_game` | Not routed. |
| `purchase_facility` | `(facility_id) -> bool` | (composed inside `ACTION_PLACE_FACILITY`) | No | `world_map.gd:440`, `world_map.gd:577` | **Roll into `ACTION_PLACE_FACILITY` payload.** The pipe charges money as part of the place action; don't expose as separate action. See §1.7. |
| `refund_facility` | `(facility_id, refund_percent=0.5) -> void` | (composed inside demolish/road overwrite) | No | `world_manager.gd:274` (internal call from `_remove_field_for_road`) | Stays direct (internal compositional). |
| `sell_product` | `(product_id, quantity, price_per_unit) -> void` | (none — internal, called by production_manager) | n/a | Called by `ProductionManager._sell_via_market_outlet` and `_auto_sell_product` | **Not routed.** Driven by the production tick, not user input. |
| `pay_maintenance` | `(facility_id) -> bool` | (none — internal tick) | n/a | Internal to `_collect_maintenance` | Not routed. |
| `cheat_add_money` | `(amount) -> void` | `ACTION_CHEAT_ADD_MONEY` (debug only) | n/a | **No UI call site**; documented in TESTING.md as console command | **Optional — skip in step 3.** Add the action only if you want every state mutation through the pipe even in cheat mode. Recommend yes (one-line) for the determinism story; the cost is trivial. |

### 1.5 MarketManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `_try_generate_contract` | `() -> void` | (none — tick-driven) | n/a | Internal tick (every 60s) | Not routed. Auto-tick is not user action. |
| `deliver_to_contract` | `(contract_id, product, quantity) -> int` | `ACTION_DELIVER_TO_CONTRACT` | No | **No UI call site** in v1 (contracts aren't deliverable through UI yet — auto-fill when production happens, see TODO in MarketManager) | **Add the action + predicate** anyway. The Business signature mechanic in Phase 10 will need it. Predicate trivially passes in v1; UI driver lands later. |
| `cancel_contract` | `(contract_id) -> bool` | `ACTION_CANCEL_CONTRACT` | No | **No UI call site** in v1 | Same as above — add for forward compatibility. |
| `_complete_contract` | `(contract) -> void` | (none — internal) | n/a | Internal | Not routed. |
| `add_supply_pressure` | `(product, amount) -> void` | (none — debug/event) | n/a | Internal (called from `_on_product_sold`) | Not routed in step 3. |

### 1.6 ResearchManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `research` | `(tech_id) -> bool` | `ACTION_RESEARCH_TECH` | Yes — `can_research(tech_id)` exists, no corp_id | `world_map.gd:2283`, `world_map.gd:2577` | Wrap. Predicate gains corp_id. |
| `try_unlock_next_tier` | `() -> bool` | (none — auto-triggered) | `can_unlock_next_tier` exists | Internal — auto-called when deliveries hit threshold | Not routed. Threshold-driven. |
| `deliver_product` | `(product_type, quantity) -> bool` | (manual UI button doesn't exist in v1) | No | **No UI call site** | Not routed in step 3. |
| `set_dev_mode` | `(enabled) -> void` | (none — debug toggle) | n/a | `research_tree.gd:392` | **Not routed.** Dev-mode toggle is debug; doesn't affect saved state. Document the exception in code comment. |
| `clear_data` | `() -> void` | (none — load only) | n/a | Save load | Not routed. |

### 1.7 ProductionManager mutators

| Mutator | Current signature | Action type | Predicate exists? | UI call sites | Notes |
|---|---|---|---|---|---|
| `add_item_to_facility` | `(facility_id, product, quantity) -> bool` | (none — internal) | No | Internal to logistics (`_handle_delivery`) | Not routed. Internal to delivery tick. |
| `remove_item_from_facility` | `(facility_id, product, quantity) -> bool` | (none — internal) | No | Internal to logistics (`_handle_pickup`) and research (`deliver_product`) | Not routed. |
| `set_farmhouse_crop_type` | `(farmhouse_id, crop_type) -> void` | `ACTION_SET_FARMHOUSE_CROP` | No | `farmhouse_ui.gd:119`, `farmhouse_ui.gd:168` | Wrap. New predicate. |
| `register_field_with_farmhouse` | `(field_id, farmhouse_id) -> void` | (part of `ACTION_PLACE_FIELD`) | No | `world_map.gd:1672` | Roll into `ACTION_PLACE_FIELD`. |
| `unregister_field_from_farmhouse` | `(field_id) -> void` | (none — internal on facility remove) | No | Internal | Not routed. |
| `synchronize_production_timers` | `(facility_ids) -> void` | (none — internal) | n/a | Called by `world_map.gd:588` after drag-place | Not routed. Internal optimization. |

### 1.8 Composite actions — when one action wraps multiple mutators

Three actions in this plan execute multiple manager mutators atomically. These are deliberate compositions, not bypasses of the rule:

#### `ACTION_PLACE_FACILITY`
Wraps: `EconomyManager.purchase_facility` → `WorldManager.place_facility` → `WorldManager.complete_construction`

UI today (`world_map.gd:440-447`):
```gdscript
if EconomyManager.purchase_facility(placement_facility_id):
    var facility_id = WorldManager.place_facility(placement_facility_id, mouse_grid_pos, {
        "size": size
    }, GameManager.active_corp_id)
    if facility_id:
        WorldManager.complete_construction(facility_id)
```

After step 3:
```gdscript
GameManager.submit_action(GameManager.active_corp_id, GameManager.ACTION_PLACE_FACILITY, {
    "facility_type": placement_facility_id,
    "grid_pos": mouse_grid_pos,
    "size": size,
})
```

The pipe handler executes the three-step composition. If `purchase_facility` succeeds but `place_facility` fails, the pipe **refunds the cost** (see §3.2 — failure handling). This is the kind of atomicity the action pipe enables that the current code does sloppily (failed-place after successful charge leaks money today).

#### `ACTION_PLACE_FIELD`
Wraps: `EconomyManager.subtract_money` → `WorldManager.place_facility` → `WorldManager.complete_construction` → `WorldManager.register_field_with_farmhouse` → `ProductionManager.register_field_with_farmhouse`

Same atomicity story. Payload includes `farmhouse_id` (the parent).

#### `ACTION_PLACE_ROAD`
Wraps: `EconomyManager.subtract_money` → `WorldManager.place_road`

Same shape.

**Rule for composite actions:** all sub-mutators called inside a composite stay direct (per §0.4). The composition is a single transaction at the pipe level.

---

## 2. The action-type registry — placed on GameManager

Add to `core/game_manager.gd` after the corp constants block:

```gdscript
# ========================================
# ACTION PIPE — ACTION TYPE CONSTANTS
# ========================================
#
# Every state mutation initiated by UI (or by any code outside the manager that
# owns the data) goes through GameManager.submit_action(corp_id, action_type, payload).
# These constants ARE the network protocol. Renaming the underlying string later
# is a protocol break — pick names now and own them.
#
# Naming: snake_case, verb-first imperative. EventBus signals are past-tense
# (facility_placed); these are present-tense intents (place_facility).
#
# When adding a new mutator to any manager, add the constant here in the same
# commit and wire its dispatch in submit_action's match block.

# World / facilities
const ACTION_PLACE_FACILITY: String = "place_facility"
const ACTION_PLACE_FIELD: String = "place_field"               # composite: place + complete + register
const ACTION_DEMOLISH_FACILITY: String = "demolish_facility"
const ACTION_PLACE_ROAD: String = "place_road"                 # composite: charge + place
const ACTION_REMOVE_ROAD: String = "remove_road"               # reserved; no UI driver in v1

# Factory interiors
const ACTION_PLACE_MACHINE: String = "place_machine"
const ACTION_DEMOLISH_MACHINE: String = "demolish_machine"
const ACTION_CREATE_MACHINE_CONNECTION: String = "create_machine_connection"
const ACTION_REMOVE_MACHINE_CONNECTION: String = "remove_machine_connection"

# Logistics
const ACTION_CREATE_LOGISTICS_CONNECTION: String = "create_logistics_connection"
const ACTION_REMOVE_LOGISTICS_CONNECTION: String = "remove_logistics_connection"
const ACTION_TOGGLE_CONNECTION_ACTIVE: String = "toggle_connection_active"

# Economy (internal-use — see plan §0.4)
const ACTION_SPEND_MONEY: String = "spend_money"
const ACTION_EARN_MONEY: String = "earn_money"
const ACTION_CHEAT_ADD_MONEY: String = "cheat_add_money"        # debug

# Market / contracts
const ACTION_DELIVER_TO_CONTRACT: String = "deliver_to_contract"
const ACTION_CANCEL_CONTRACT: String = "cancel_contract"

# Research
const ACTION_RESEARCH_TECH: String = "research_tech"

# Production / farmhouse
const ACTION_SET_FARMHOUSE_CROP: String = "set_farmhouse_crop"

# Set of all valid action types — used by submit_action for validation
const VALID_ACTION_TYPES: Array[String] = [
    ACTION_PLACE_FACILITY,
    ACTION_PLACE_FIELD,
    ACTION_DEMOLISH_FACILITY,
    ACTION_PLACE_ROAD,
    ACTION_REMOVE_ROAD,
    ACTION_PLACE_MACHINE,
    ACTION_DEMOLISH_MACHINE,
    ACTION_CREATE_MACHINE_CONNECTION,
    ACTION_REMOVE_MACHINE_CONNECTION,
    ACTION_CREATE_LOGISTICS_CONNECTION,
    ACTION_REMOVE_LOGISTICS_CONNECTION,
    ACTION_TOGGLE_CONNECTION_ACTIVE,
    ACTION_SPEND_MONEY,
    ACTION_EARN_MONEY,
    ACTION_CHEAT_ADD_MONEY,
    ACTION_DELIVER_TO_CONTRACT,
    ACTION_CANCEL_CONTRACT,
    ACTION_RESEARCH_TECH,
    ACTION_SET_FARMHOUSE_CROP,
]
```

19 action types in step 3.

---

## 3. `submit_action` — the dispatch shell

### 3.1 Signature and shape

Add to `core/game_manager.gd` after `set_active_corp`:

```gdscript
# ========================================
# ACTION PIPE
# ========================================

func submit_action(corp_id: String, action_type: String, payload: Dictionary) -> bool:
    """Single entry point for every state mutation in the game.
    Returns true on success, false on rejection. Rejection reason is push_warning-logged
    by the manager's predicate; UI uses the bool return to decide whether to update.

    Phase 8 step 3: in-process dispatch only. Phase 12 will swap the transport for a
    networked one without changing this signature.

    Phase 12 TODO: widen return to Dictionary { accepted, reason, action_id } when
    network sequencing arrives. Step 3 collapses to bool because there's no consumer
    of the richer shape yet."""

    # 1. Validate corp_id
    if corp_id not in VALID_CORP_IDS:
        push_error("submit_action: invalid corp_id '%s'" % corp_id)
        return false

    # 2. Validate action_type
    if action_type not in VALID_ACTION_TYPES:
        push_error("submit_action: unknown action_type '%s'" % action_type)
        return false

    # 3. Validate payload has all required keys for this action_type
    if not _validate_action_payload(action_type, payload):
        # _validate_action_payload pushes its own push_error with the missing key
        return false

    # 4. Dispatch by action_type. Each handler:
    #    a. Calls the manager's can_<action> predicate
    #    b. If ok, calls the manager's mutator
    #    c. Returns bool reflecting mutator success
    match action_type:
        ACTION_PLACE_FACILITY:        return _action_place_facility(corp_id, payload)
        ACTION_PLACE_FIELD:           return _action_place_field(corp_id, payload)
        ACTION_DEMOLISH_FACILITY:     return _action_demolish_facility(corp_id, payload)
        ACTION_PLACE_ROAD:            return _action_place_road(corp_id, payload)
        ACTION_REMOVE_ROAD:           return _action_remove_road(corp_id, payload)
        ACTION_PLACE_MACHINE:         return _action_place_machine(corp_id, payload)
        ACTION_DEMOLISH_MACHINE:      return _action_demolish_machine(corp_id, payload)
        ACTION_CREATE_MACHINE_CONNECTION:    return _action_create_machine_connection(corp_id, payload)
        ACTION_REMOVE_MACHINE_CONNECTION:    return _action_remove_machine_connection(corp_id, payload)
        ACTION_CREATE_LOGISTICS_CONNECTION:  return _action_create_logistics_connection(corp_id, payload)
        ACTION_REMOVE_LOGISTICS_CONNECTION:  return _action_remove_logistics_connection(corp_id, payload)
        ACTION_TOGGLE_CONNECTION_ACTIVE:     return _action_toggle_connection_active(corp_id, payload)
        ACTION_SPEND_MONEY:           return _action_spend_money(corp_id, payload)
        ACTION_EARN_MONEY:            return _action_earn_money(corp_id, payload)
        ACTION_CHEAT_ADD_MONEY:       return _action_cheat_add_money(corp_id, payload)
        ACTION_DELIVER_TO_CONTRACT:   return _action_deliver_to_contract(corp_id, payload)
        ACTION_CANCEL_CONTRACT:       return _action_cancel_contract(corp_id, payload)
        ACTION_RESEARCH_TECH:         return _action_research_tech(corp_id, payload)
        ACTION_SET_FARMHOUSE_CROP:    return _action_set_farmhouse_crop(corp_id, payload)
        _:
            push_error("submit_action: action_type '%s' is in VALID_ACTION_TYPES but has no dispatch handler — code bug" % action_type)
            return false
```

### 3.2 Payload-schema validation

Required-key validation lives in `GameManager` (the pipe checks shape; the manager checks semantics). One block, one source of truth:

```gdscript
# Required payload keys per action_type. Add an entry when adding a new action.
const _ACTION_PAYLOAD_SCHEMA: Dictionary = {
    ACTION_PLACE_FACILITY:               ["facility_type", "grid_pos", "size"],
    ACTION_PLACE_FIELD:                  ["field_type", "grid_pos", "farmhouse_id"],
    ACTION_DEMOLISH_FACILITY:            ["facility_id"],
    ACTION_PLACE_ROAD:                   ["grid_pos", "road_type"],
    ACTION_REMOVE_ROAD:                  ["grid_pos"],
    ACTION_PLACE_MACHINE:                ["facility_id", "machine_type", "grid_pos", "size"],
    ACTION_DEMOLISH_MACHINE:             ["facility_id", "machine_id"],
    ACTION_CREATE_MACHINE_CONNECTION:    ["facility_id", "from_machine_id", "to_machine_id"],
    ACTION_REMOVE_MACHINE_CONNECTION:    ["facility_id", "from_machine_id", "to_machine_id"],
    ACTION_CREATE_LOGISTICS_CONNECTION:  ["source_id", "destination_id", "product"],
    ACTION_REMOVE_LOGISTICS_CONNECTION:  ["connection_id"],
    ACTION_TOGGLE_CONNECTION_ACTIVE:     ["connection_id"],
    ACTION_SPEND_MONEY:                  ["amount", "reason"],
    ACTION_EARN_MONEY:                   ["amount", "reason"],
    ACTION_CHEAT_ADD_MONEY:              ["amount"],
    ACTION_DELIVER_TO_CONTRACT:          ["contract_id", "product", "quantity"],
    ACTION_CANCEL_CONTRACT:              ["contract_id"],
    ACTION_RESEARCH_TECH:                ["tech_id"],
    ACTION_SET_FARMHOUSE_CROP:           ["farmhouse_id", "crop_type"],
}


func _validate_action_payload(action_type: String, payload: Dictionary) -> bool:
    var required: Array = _ACTION_PAYLOAD_SCHEMA.get(action_type, [])
    for key in required:
        if not payload.has(key):
            push_error("submit_action: action '%s' missing required payload key '%s'" % [action_type, key])
            return false
    return true
```

This is the "missing field" failure-mode mitigation from the request. Loud, not silent.

### 3.3 Composite action atomicity — failure unwinds

The `ACTION_PLACE_FACILITY` handler illustrates the atomicity rule. Bug fix relative to today (today's `world_map.gd:440-447` charges money then can fail at `place_facility` and leak the charge):

```gdscript
func _action_place_facility(corp_id: String, payload: Dictionary) -> bool:
    var facility_type: String = payload.facility_type
    var grid_pos: Vector2i = payload.grid_pos
    var size: Vector2i = payload.size

    # Predicate — manager-side ownership / state check
    var check := WorldManager.can_place_facility_v2(corp_id, facility_type, grid_pos, size)
    if not check.ok:
        push_warning("place_facility rejected: %s" % check.reason)
        return false

    # Cost — affordability predicate
    var facility_def: Dictionary = DataManager.get_facility_data(facility_type)
    var cost: int = facility_def.get("cost", 0)
    var afford_check := EconomyManager.can_spend_money(corp_id, cost)
    if not afford_check.ok:
        push_warning("place_facility rejected: %s" % afford_check.reason)
        return false

    # Charge — uses _direct path (already inside the pipe; don't re-enter)
    if not EconomyManager.spend_money(corp_id, cost, "Built %s" % facility_def.get("name", facility_type)):
        # Should never hit: can_spend_money said ok. Defensive log.
        push_error("place_facility: predicate ok but spend failed — race? bug?")
        return false

    # Place
    var facility_id := WorldManager.place_facility(facility_type, grid_pos, {"size": size}, corp_id)
    if facility_id.is_empty():
        # Unwind the charge so we don't leak money on a place failure
        EconomyManager.earn_money(corp_id, cost, "Refund: failed place")
        push_error("place_facility: predicate ok but mutator failed — bug")
        return false

    # Complete construction (currently always immediate; future construction-time goes here)
    WorldManager.complete_construction(facility_id)
    return true
```

**Naming note:** the existing `EconomyManager.subtract_money` and `add_money` get renamed in step 3 to `spend_money` / `earn_money` *as the pipe-internal versions*, and the predicate `can_spend_money` replaces `can_afford`. See §4 EconomyManager block. Old `subtract_money`/`add_money` names are deleted (no aliasing — per the no-alias-creep rule).

`WorldManager.can_place_facility_v2` is the new corp-aware predicate; the old `can_place_facility(grid_pos, size)` is **renamed to `_can_place_facility_geometry`** (private, used by both the legacy occupancy check and the new predicate). See §4 WorldManager block.

### 3.4 Where `corp_id` comes from at every call site

At every UI call site in this plan, `corp_id` is `GameManager.active_corp_id`. In v1 that always equals `CORP_SINGLE`. **Do not derive corp from the entity being acted on.** That's a Phase-10 question (when corps differ and the cross-corp ownership rules need to express things like "Logistics can demolish a road owned by `shared`"). For step 3, the rule is: **the actor is always `active_corp_id`**, even when the action targets an entity owned by a different corp. The predicate checks whether the actor is permitted; in v1 it trivially is.

---

## 4. Per-manager predicate inventory + before/after

### 4.1 WorldManager

#### `can_place_facility_v2(corp_id, facility_type, grid_pos, size) -> Dictionary`

Wraps existing geometry check, adds corp + research-unlock check.

```gdscript
func can_place_facility_v2(corp_id: String, facility_type: String, grid_pos: Vector2i, size: Vector2i) -> Dictionary:
    """Predicate for ACTION_PLACE_FACILITY. v1: corp check trivially passes (single corp).
    Phase 10 fills in per-corp build-menu permissions."""
    # Geometry
    if not _can_place_facility_geometry(grid_pos, size):
        return { "ok": false, "reason": "Invalid placement: out of bounds or tile occupied" }
    # Facility type must exist
    var facility_def: Dictionary = DataManager.get_facility_data(facility_type)
    if facility_def.is_empty():
        return { "ok": false, "reason": "Unknown facility type: %s" % facility_type }
    # Research unlock — already enforced today via ResearchManager.is_facility_unlocked; promote to predicate
    if not ResearchManager.is_facility_unlocked(facility_type):
        return { "ok": false, "reason": "Facility locked: research required" }
    # Corp permission — v1 trivially passes; Phase 10 reads data/facilities.json `corp` field
    # (placeholder: every corp can build everything until per-corp build menus land)
    return { "ok": true, "reason": "" }
```

**Rename:** the existing public `can_place_facility(grid_pos, size)` becomes private `_can_place_facility_geometry(grid_pos, size)`. Internal call sites in `world_map.gd` (`:430`, `:493`, `:568`) — these are pre-place affordance previews (greying out tiles); they keep calling the geometry-only helper because the geometry result is what they visualize, and the predicate is invoked on the actual click via `submit_action`. **Acceptable double-validation pattern** because the UI preview is a UX cue, not a state mutation.

#### `can_remove_facility(corp_id, facility_id) -> Dictionary`

```gdscript
func can_remove_facility(corp_id: String, facility_id: String) -> Dictionary:
    if not facilities.has(facility_id):
        return { "ok": false, "reason": "Facility not found: %s" % facility_id }
    # v1: trivially ok. Phase 10:
    # var facility = facilities[facility_id]
    # if facility.corp_id != corp_id and facility.corp_id != GameManager.CORP_SHARED:
    #     return { "ok": false, "reason": "Corp %s does not own %s" % [corp_id, facility_id] }
    return { "ok": true, "reason": "" }
```

#### `can_place_road(corp_id, grid_pos) -> Dictionary`

Existing `can_place_road(grid_pos)` becomes `_can_place_road_geometry(grid_pos)` (private). New corp-aware version:

```gdscript
func can_place_road(corp_id: String, grid_pos: Vector2i) -> Dictionary:
    if not _can_place_road_geometry(grid_pos):
        return { "ok": false, "reason": "Cannot place road: out of bounds, occupied by building, or already a road" }
    return { "ok": true, "reason": "" }
```

#### `can_remove_road(corp_id, grid_pos) -> Dictionary`

```gdscript
func can_remove_road(corp_id: String, grid_pos: Vector2i) -> Dictionary:
    if not is_valid_grid_position(grid_pos):
        return { "ok": false, "reason": "Out of bounds" }
    if road_grid[grid_pos.x][grid_pos.y] == null:
        return { "ok": false, "reason": "No road at position" }
    return { "ok": true, "reason": "" }
```

### 4.2 FactoryManager

#### `can_place_machine_v2(corp_id, facility_id, machine_type, grid_pos, size) -> Dictionary`

Existing `can_place_machine(facility_id, grid_pos, size)` becomes `_can_place_machine_geometry`.

```gdscript
func can_place_machine_v2(corp_id: String, facility_id: String, machine_type: String, grid_pos: Vector2i, size: Vector2i) -> Dictionary:
    if WorldManager.get_facility(facility_id).is_empty():
        return { "ok": false, "reason": "Parent facility not found" }
    if not _can_place_machine_geometry(facility_id, grid_pos, size):
        return { "ok": false, "reason": "Invalid machine placement: out of bounds or tile occupied" }
    var machine_def: Dictionary = DataManager.get_machine_data(machine_type)
    if machine_def.is_empty():
        return { "ok": false, "reason": "Unknown machine type: %s" % machine_type }
    if not ResearchManager.is_machine_unlocked(machine_type):
        return { "ok": false, "reason": "Machine locked: research required" }
    return { "ok": true, "reason": "" }
```

#### `can_remove_machine(corp_id, facility_id, machine_id) -> Dictionary`

```gdscript
func can_remove_machine(corp_id: String, facility_id: String, machine_id: String) -> Dictionary:
    var interior := get_factory_interior(facility_id)
    if not interior.machines.has(machine_id):
        return { "ok": false, "reason": "Machine not found" }
    return { "ok": true, "reason": "" }
```

#### `can_create_machine_connection(corp_id, facility_id, from_machine_id, to_machine_id) -> Dictionary`

The current `create_connection` returns `false` for three distinct reasons silently (missing machines, duplicate connection, self-connection). Promote to predicate:

```gdscript
func can_create_machine_connection(corp_id: String, facility_id: String, from_machine_id: String, to_machine_id: String) -> Dictionary:
    var interior := get_factory_interior(facility_id)
    if not interior.machines.has(from_machine_id):
        return { "ok": false, "reason": "Source machine not found" }
    if not interior.machines.has(to_machine_id):
        return { "ok": false, "reason": "Destination machine not found" }
    if from_machine_id == to_machine_id:
        return { "ok": false, "reason": "Cannot connect machine to itself" }
    for conn in interior.connections:
        if conn.from == from_machine_id and conn.to == to_machine_id:
            return { "ok": false, "reason": "Connection already exists" }
    return { "ok": true, "reason": "" }
```

#### `can_remove_machine_connection(corp_id, facility_id, from_machine_id, to_machine_id) -> Dictionary`

```gdscript
func can_remove_machine_connection(corp_id: String, facility_id: String, from_machine_id: String, to_machine_id: String) -> Dictionary:
    var interior := get_factory_interior(facility_id)
    for conn in interior.connections:
        if conn.from == from_machine_id and conn.to == to_machine_id:
            return { "ok": true, "reason": "" }
    return { "ok": false, "reason": "Connection not found" }
```

### 4.3 LogisticsManager

#### `can_create_connection(corp_id, source_id, destination_id, product) -> Dictionary`

The current `create_connection` has the most complex inline validation in the codebase — three rejection paths (missing facilities, no road, duplicate). **This is the hardest predicate to factor cleanly because the "no road path" check is itself an A* call that mutates nothing but is expensive.** Decision: keep the A* inside the predicate. Failed-fast saves the mutator from doing the same work; if A* becomes a hot path later, cache the result on the connection_id during the predicate→mutator window.

```gdscript
func can_create_connection(corp_id: String, source_id: String, destination_id: String, product: String) -> Dictionary:
    if WorldManager.get_facility(source_id).is_empty():
        return { "ok": false, "reason": "Source facility not found" }
    if WorldManager.get_facility(destination_id).is_empty():
        return { "ok": false, "reason": "Destination facility not found" }
    if source_id == destination_id:
        return { "ok": false, "reason": "Cannot connect facility to itself" }
    # Road path — A* check; failure here is a real "no road" rejection, not a logic bug
    var path := WorldManager.find_road_path(source_id, destination_id)
    if path.is_empty():
        return { "ok": false, "reason": "No road path between facilities" }
    # Duplicate
    for conn_id in connections:
        var conn = connections[conn_id]
        if conn.source_id == source_id and conn.destination_id == destination_id:
            return { "ok": false, "reason": "Connection already exists" }
    return { "ok": true, "reason": "" }
```

Implementation note for the implementer: the `create_connection` mutator currently calls `find_road_path` again. Leave that; the cost is minor and the alternative — threading the cached path through the action pipe — is more complexity than it saves. If this becomes a profiler-flagged hot path later, then optimize.

#### `can_remove_connection(corp_id, connection_id) -> Dictionary`

```gdscript
func can_remove_connection(corp_id: String, connection_id: String) -> Dictionary:
    if not connections.has(connection_id):
        return { "ok": false, "reason": "Connection not found" }
    return { "ok": true, "reason": "" }
```

#### `can_toggle_connection_active(corp_id, connection_id) -> Dictionary`

```gdscript
func can_toggle_connection_active(corp_id: String, connection_id: String) -> Dictionary:
    if not connections.has(connection_id):
        return { "ok": false, "reason": "Connection not found" }
    return { "ok": true, "reason": "" }
```

### 4.4 EconomyManager — predicate and the rename

`subtract_money` and `add_money` are the most widely-called mutators in the codebase. Renaming them in step 3 is load-bearing but contained — every direct UI caller is going through `submit_action` after this commit anyway, so the renames are concentrated in the new pipe handlers + internal compositional callers.

**Decision: rename `subtract_money` → `spend_money` and `add_money` → `earn_money`.**

Reason: the predicate-then-action naming convention wants `can_spend_money` / `spend_money`. `can_subtract_money` reads wrong; `can_earn_money` reads wrong (the question is whether you *can*, not whether you'll *earn*). The verbs spend/earn match the action-type constants. The existing `can_afford(amount) -> bool` becomes `can_spend_money(corp_id, amount) -> Dictionary`.

Renames touch:
- `EconomyManager.subtract_money` → `spend_money` (signature: `(corp_id: String, amount: int, reason: String) -> bool`; corp_id added)
- `EconomyManager.add_money` → `earn_money` (signature: `(corp_id: String, amount: int, reason: String) -> void`; corp_id added)
- `EconomyManager.can_afford` → `can_spend_money` (signature: `(corp_id: String, amount: int) -> Dictionary`; corp_id added)
- All internal callers of the old names: `purchase_facility`, `refund_facility`, `sell_product`, `pay_maintenance`, `_collect_maintenance`, `_handle_maintenance_shortfall`, `cheat_add_money`, `set_money`, `reset_economy`
- All UI callers: rewired via submit_action (so they don't call the renamed function directly)
- `ResearchManager.research`, `MarketManager._complete_contract` — these stay as direct internal calls per §0.4 but get renamed to use the new names

```gdscript
func can_spend_money(corp_id: String, amount: int) -> Dictionary:
    """v1: single shared wallet; corp_id ignored. v4 (per-corp wallets): reads money_by_corp[corp_id]."""
    if amount <= 0:
        return { "ok": false, "reason": "Amount must be positive" }
    if money < amount:
        return { "ok": false, "reason": "Insufficient funds: need $%d, have $%d" % [amount, money] }
    return { "ok": true, "reason": "" }


func spend_money(corp_id: String, amount: int, reason: String = "") -> bool:
    """Public mutator. Called from inside submit_action handlers and internal compositional code."""
    var check := can_spend_money(corp_id, amount)
    if not check.ok:
        push_warning("spend_money rejected: %s" % check.reason)
        return false
    money -= amount
    total_spent += amount
    _record_transaction(-amount, reason, "expense")
    EventBus.money_changed.emit(money, -amount)
    print("Money spent: -$%d (%s) | Remaining: $%d" % [amount, reason, money])
    return true


func earn_money(corp_id: String, amount: int, reason: String = "") -> void:
    if amount <= 0:
        push_warning("Trying to add non-positive amount: %d" % amount)
        return
    money += amount
    total_earned += amount
    _record_transaction(amount, reason, "income")
    EventBus.money_changed.emit(money, amount)
    print("Money added: +$%d (%s) | Total: $%d" % [amount, reason, money])
```

**Internal helper callers of the renamed functions** (these stay direct per §0.4 — they're inside other actions):

| Old call | New call |
|---|---|
| `subtract_money(cost, "Built X")` in `purchase_facility` | `spend_money(corp_id, cost, "Built X")` — but `purchase_facility` itself becomes private; see below |
| `add_money(refund, "Removed X")` in `refund_facility` | `earn_money(corp_id, refund, "Removed X")` |
| `add_money(revenue, "Sold X")` in `sell_product` | `earn_money(corp_id, revenue, "Sold X")` |
| `subtract_money(cost, "Maintenance: X")` in `pay_maintenance` | `spend_money(corp_id, cost, "Maintenance: X")` |
| `subtract_money(total_cost, "Maintenance ...")` in `_collect_maintenance` | `spend_money(corp_id, total_cost, "Maintenance ...")` |
| `subtract_money(cost, "Research: X")` in `ResearchManager.research` | `spend_money(corp_id, cost, "Research: X")` |
| `add_money(contract.reward, ...)` in `MarketManager._complete_contract` | `earn_money(corp_id, contract.reward, ...)` |

The `corp_id` parameter in these internal calls comes from whatever spawned the chain — usually it's threaded through. For `_collect_maintenance` and `_complete_contract` (tick-driven, no submit_action context), use `CORP_SINGLE` for v1; this prefigures the per-corp tick refactor in the v3→v4 EconomyManager commit.

**`purchase_facility` and `refund_facility` become private helpers (`_purchase_facility`, `_refund_facility`)** called only from the composite action handlers. They're not pipe-exposed as standalone actions — they're always inside a place/demolish composition.

### 4.5 MarketManager predicates

#### `can_deliver_to_contract(corp_id, contract_id, product, quantity) -> Dictionary`

```gdscript
func can_deliver_to_contract(corp_id: String, contract_id: int, product: String, quantity: int) -> Dictionary:
    for contract in active_contracts:
        if contract.id == contract_id:
            if contract.status != "active":
                return { "ok": false, "reason": "Contract is not active (status: %s)" % contract.status }
            if contract.product != product:
                return { "ok": false, "reason": "Contract is for %s, not %s" % [contract.product, product] }
            if quantity <= 0:
                return { "ok": false, "reason": "Quantity must be positive" }
            return { "ok": true, "reason": "" }
    return { "ok": false, "reason": "Contract not found" }
```

#### `can_cancel_contract(corp_id, contract_id) -> Dictionary`

```gdscript
func can_cancel_contract(corp_id: String, contract_id: int) -> Dictionary:
    for contract in active_contracts:
        if contract.id == contract_id:
            if contract.status != "active":
                return { "ok": false, "reason": "Contract is not active" }
            return { "ok": true, "reason": "" }
    return { "ok": false, "reason": "Contract not found" }
```

### 4.6 ResearchManager predicate

Existing `can_research(tech_id) -> bool` is the closest existing match to the predicate pattern in the codebase. Promote to dict-return:

```gdscript
func can_research_v2(corp_id: String, tech_id: String) -> Dictionary:
    if is_unlocked(tech_id):
        return { "ok": false, "reason": "Already researched" }
    var tech = research_tree.get(tech_id)
    if not tech:
        return { "ok": false, "reason": "Unknown tech: %s" % tech_id }
    var tech_tier = tech.get("tier", 1)
    if not dev_mode and tech_tier > current_tier:
        return { "ok": false, "reason": "Tier %d not unlocked (current: %d)" % [tech_tier, current_tier] }
    for prereq in tech.get("prerequisites", []):
        if not is_unlocked(prereq):
            return { "ok": false, "reason": "Missing prerequisite: %s" % prereq }
    if not dev_mode:
        var cost = tech.get("cost", 0)
        var afford := EconomyManager.can_spend_money(corp_id, cost)
        if not afford.ok:
            return { "ok": false, "reason": afford.reason }
    return { "ok": true, "reason": "" }
```

Old `can_research(tech_id) -> bool` is **kept** (used internally by UI to grey out buttons; renaming all those sites is out of scope). It becomes a one-liner wrapper:

```gdscript
func can_research(tech_id: String) -> bool:
    return can_research_v2(GameManager.active_corp_id, tech_id).ok
```

The wrapper is the **one explicit exception** to the no-alias rule, justified because: (a) `can_research` is read-only / UI affordance, not a mutator; (b) every caller passes the same `active_corp_id` so it can't drift; (c) the wrapper deletes when the corp-switcher UI lands and UI calls `can_research_v2` directly. Mark it `# TODO(phase-10): delete after corp-switcher UI lands and UI calls can_research_v2 directly.`

### 4.7 ProductionManager predicate

#### `can_set_farmhouse_crop(corp_id, farmhouse_id, crop_type) -> Dictionary`

```gdscript
func can_set_farmhouse_crop(corp_id: String, farmhouse_id: String, crop_type: String) -> Dictionary:
    var facility := WorldManager.get_facility(farmhouse_id)
    if facility.is_empty():
        return { "ok": false, "reason": "Farmhouse not found" }
    var facility_def := DataManager.get_facility_data(facility.type)
    var supported: Array = facility_def.get("supported_crops", [])
    if crop_type not in supported:
        return { "ok": false, "reason": "Crop %s not supported by %s" % [crop_type, facility.type] }
    return { "ok": true, "reason": "" }
```

---

## 5. Pipe handler implementations — one per action

These are the per-action handlers that `submit_action` dispatches to. Pattern: validate via predicate, mutate via manager, return bool. All live in `core/game_manager.gd`.

```gdscript
# ============================================================
# ACTION HANDLERS — one per ACTION_* constant. Pattern: predicate → mutate → return bool.
# ============================================================

func _action_place_facility(corp_id: String, payload: Dictionary) -> bool:
    var facility_type: String = payload.facility_type
    var grid_pos: Vector2i = payload.grid_pos
    var size: Vector2i = payload.size

    var place_check := WorldManager.can_place_facility_v2(corp_id, facility_type, grid_pos, size)
    if not place_check.ok:
        push_warning("ACTION_PLACE_FACILITY rejected: %s" % place_check.reason)
        return false
    var facility_def: Dictionary = DataManager.get_facility_data(facility_type)
    var cost: int = facility_def.get("cost", 0)
    var afford_check := EconomyManager.can_spend_money(corp_id, cost)
    if not afford_check.ok:
        push_warning("ACTION_PLACE_FACILITY rejected: %s" % afford_check.reason)
        return false
    # Charge first; unwind if place fails.
    if not EconomyManager.spend_money(corp_id, cost, "Built %s" % facility_def.get("name", facility_type)):
        push_error("ACTION_PLACE_FACILITY: predicate said ok but spend failed; possible bug")
        return false
    var facility_id := WorldManager.place_facility(facility_type, grid_pos, {"size": size}, corp_id)
    if facility_id.is_empty():
        EconomyManager.earn_money(corp_id, cost, "Refund: failed place_facility")
        push_error("ACTION_PLACE_FACILITY: place mutator failed after predicate ok; bug")
        return false
    WorldManager.complete_construction(facility_id)
    return true


func _action_place_field(corp_id: String, payload: Dictionary) -> bool:
    var field_type: String = payload.field_type
    var grid_pos: Vector2i = payload.grid_pos
    var farmhouse_id: String = payload.farmhouse_id
    var size: Vector2i = Vector2i(1, 1)  # Fields are 1x1 per existing convention

    # Predicate uses farmhouse-adjacency check (already in WorldManager)
    if not WorldManager.can_place_field_for_farmhouse(grid_pos, size, farmhouse_id):
        push_warning("ACTION_PLACE_FIELD rejected: invalid position for farmhouse")
        return false
    var field_def: Dictionary = DataManager.get_facility_data(field_type)
    var cost: int = field_def.get("cost", 100)
    var afford := EconomyManager.can_spend_money(corp_id, cost)
    if not afford.ok:
        push_warning("ACTION_PLACE_FIELD rejected: %s" % afford.reason)
        return false
    if not EconomyManager.spend_money(corp_id, cost, "Field placement"):
        push_error("ACTION_PLACE_FIELD: spend failed after predicate ok")
        return false
    var field_id := WorldManager.place_facility(field_type, grid_pos, {"size": size}, corp_id)
    if field_id.is_empty():
        EconomyManager.earn_money(corp_id, cost, "Refund: failed place_field")
        push_error("ACTION_PLACE_FIELD: place mutator failed")
        return false
    WorldManager.complete_construction(field_id)
    WorldManager.register_field_with_farmhouse(field_id, farmhouse_id)
    ProductionManager.register_field_with_farmhouse(field_id, farmhouse_id)
    return true


func _action_demolish_facility(corp_id: String, payload: Dictionary) -> bool:
    var facility_id: String = payload.facility_id
    var check := WorldManager.can_remove_facility(corp_id, facility_id)
    if not check.ok:
        push_warning("ACTION_DEMOLISH_FACILITY rejected: %s" % check.reason)
        return false
    # Refund first (uses the existing refund_facility helper, now private)
    var facility := WorldManager.get_facility(facility_id)
    var facility_def: Dictionary = DataManager.get_facility_data(facility.type)
    var refund: int = int(facility_def.get("cost", 0) * 0.5)
    if refund > 0:
        EconomyManager.earn_money(corp_id, refund, "Demolished %s" % facility_def.get("name", facility.type))
    var ok := WorldManager.remove_facility(facility_id)
    if not ok:
        # Shouldn't hit after predicate ok; if it does, the refund is already issued — leaks a tiny amount.
        # Defensive log only; the predicate is the contract.
        push_error("ACTION_DEMOLISH_FACILITY: predicate ok but mutator failed")
    return ok


func _action_place_road(corp_id: String, payload: Dictionary) -> bool:
    var grid_pos: Vector2i = payload.grid_pos
    var road_type: String = payload.road_type
    var check := WorldManager.can_place_road(corp_id, grid_pos)
    if not check.ok:
        push_warning("ACTION_PLACE_ROAD rejected: %s" % check.reason)
        return false
    var road_def: Dictionary = DataManager.get_road_data(road_type)
    var cost: int = road_def.get("cost", 25)
    var afford := EconomyManager.can_spend_money(corp_id, cost)
    if not afford.ok:
        push_warning("ACTION_PLACE_ROAD rejected: %s" % afford.reason)
        return false
    if not EconomyManager.spend_money(corp_id, cost, "Road placement"):
        return false
    var ok := WorldManager.place_road(grid_pos, road_type)
    if not ok:
        EconomyManager.earn_money(corp_id, cost, "Refund: failed place_road")
    return ok


func _action_remove_road(corp_id: String, payload: Dictionary) -> bool:
    var grid_pos: Vector2i = payload.grid_pos
    var check := WorldManager.can_remove_road(corp_id, grid_pos)
    if not check.ok:
        push_warning("ACTION_REMOVE_ROAD rejected: %s" % check.reason)
        return false
    return WorldManager.remove_road(grid_pos)


func _action_place_machine(corp_id: String, payload: Dictionary) -> bool:
    var facility_id: String = payload.facility_id
    var machine_type: String = payload.machine_type
    var grid_pos: Vector2i = payload.grid_pos
    var size: Vector2i = payload.size
    var check := FactoryManager.can_place_machine_v2(corp_id, facility_id, machine_type, grid_pos, size)
    if not check.ok:
        push_warning("ACTION_PLACE_MACHINE rejected: %s" % check.reason)
        return false
    var machine_def: Dictionary = DataManager.get_machine_data(machine_type)
    var cost: int = machine_def.get("cost", 0)
    var afford := EconomyManager.can_spend_money(corp_id, cost)
    if not afford.ok:
        push_warning("ACTION_PLACE_MACHINE rejected: %s" % afford.reason)
        return false
    if not EconomyManager.spend_money(corp_id, cost, "Machine: %s" % machine_def.get("name", machine_type)):
        return false
    var machine_id := FactoryManager.place_machine(facility_id, machine_type, grid_pos, {"size": size}, corp_id)
    if machine_id.is_empty():
        EconomyManager.earn_money(corp_id, cost, "Refund: failed place_machine")
        return false
    return true


func _action_demolish_machine(corp_id: String, payload: Dictionary) -> bool:
    var facility_id: String = payload.facility_id
    var machine_id: String = payload.machine_id
    var check := FactoryManager.can_remove_machine(corp_id, facility_id, machine_id)
    if not check.ok:
        push_warning("ACTION_DEMOLISH_MACHINE rejected: %s" % check.reason)
        return false
    var machine := FactoryManager.get_machine(facility_id, machine_id)
    var machine_def: Dictionary = DataManager.get_machine_data(machine.type)
    var refund: int = int(machine_def.get("cost", 0) * 0.5)
    if refund > 0:
        EconomyManager.earn_money(corp_id, refund, "Demolished machine %s" % machine.type)
    return FactoryManager.remove_machine(facility_id, machine_id)


func _action_create_machine_connection(corp_id: String, payload: Dictionary) -> bool:
    var check := FactoryManager.can_create_machine_connection(corp_id, payload.facility_id, payload.from_machine_id, payload.to_machine_id)
    if not check.ok:
        push_warning("ACTION_CREATE_MACHINE_CONNECTION rejected: %s" % check.reason)
        return false
    return FactoryManager.create_connection(payload.facility_id, payload.from_machine_id, payload.to_machine_id)


func _action_remove_machine_connection(corp_id: String, payload: Dictionary) -> bool:
    var check := FactoryManager.can_remove_machine_connection(corp_id, payload.facility_id, payload.from_machine_id, payload.to_machine_id)
    if not check.ok:
        push_warning("ACTION_REMOVE_MACHINE_CONNECTION rejected: %s" % check.reason)
        return false
    return FactoryManager.remove_connection(payload.facility_id, payload.from_machine_id, payload.to_machine_id)


func _action_create_logistics_connection(corp_id: String, payload: Dictionary) -> bool:
    var check := LogisticsManager.can_create_connection(corp_id, payload.source_id, payload.destination_id, payload.product)
    if not check.ok:
        push_warning("ACTION_CREATE_LOGISTICS_CONNECTION rejected: %s" % check.reason)
        EventBus.notification_posted.emit(check.reason, "warning")  # Preserve existing UX
        return false
    # Logistics is the broker — use CORP_LOGISTICS (default) regardless of actor corp in v1.
    var conn_id := LogisticsManager.create_connection(payload.source_id, payload.destination_id, payload.product)
    return not conn_id.is_empty()


func _action_remove_logistics_connection(corp_id: String, payload: Dictionary) -> bool:
    var check := LogisticsManager.can_remove_connection(corp_id, payload.connection_id)
    if not check.ok:
        push_warning("ACTION_REMOVE_LOGISTICS_CONNECTION rejected: %s" % check.reason)
        return false
    return LogisticsManager.remove_connection(payload.connection_id)


func _action_toggle_connection_active(corp_id: String, payload: Dictionary) -> bool:
    var check := LogisticsManager.can_toggle_connection_active(corp_id, payload.connection_id)
    if not check.ok:
        push_warning("ACTION_TOGGLE_CONNECTION_ACTIVE rejected: %s" % check.reason)
        return false
    return LogisticsManager.toggle_connection_active(payload.connection_id)


func _action_spend_money(corp_id: String, payload: Dictionary) -> bool:
    return EconomyManager.spend_money(corp_id, int(payload.amount), String(payload.reason))


func _action_earn_money(corp_id: String, payload: Dictionary) -> bool:
    EconomyManager.earn_money(corp_id, int(payload.amount), String(payload.reason))
    return true


func _action_cheat_add_money(corp_id: String, payload: Dictionary) -> bool:
    EconomyManager.cheat_add_money(int(payload.amount))
    return true


func _action_deliver_to_contract(corp_id: String, payload: Dictionary) -> bool:
    var check := MarketManager.can_deliver_to_contract(corp_id, int(payload.contract_id), String(payload.product), int(payload.quantity))
    if not check.ok:
        push_warning("ACTION_DELIVER_TO_CONTRACT rejected: %s" % check.reason)
        return false
    var delivered := MarketManager.deliver_to_contract(int(payload.contract_id), String(payload.product), int(payload.quantity))
    return delivered > 0


func _action_cancel_contract(corp_id: String, payload: Dictionary) -> bool:
    var check := MarketManager.can_cancel_contract(corp_id, int(payload.contract_id))
    if not check.ok:
        push_warning("ACTION_CANCEL_CONTRACT rejected: %s" % check.reason)
        return false
    return MarketManager.cancel_contract(int(payload.contract_id))


func _action_research_tech(corp_id: String, payload: Dictionary) -> bool:
    var check := ResearchManager.can_research_v2(corp_id, payload.tech_id)
    if not check.ok:
        push_warning("ACTION_RESEARCH_TECH rejected: %s" % check.reason)
        return false
    return ResearchManager.research(payload.tech_id)


func _action_set_farmhouse_crop(corp_id: String, payload: Dictionary) -> bool:
    var check := ProductionManager.can_set_farmhouse_crop(corp_id, payload.farmhouse_id, payload.crop_type)
    if not check.ok:
        push_warning("ACTION_SET_FARMHOUSE_CROP rejected: %s" % check.reason)
        return false
    ProductionManager.set_farmhouse_crop_type(payload.farmhouse_id, payload.crop_type)
    return true
```

---

## 6. UI call-site rewiring inventory

Every direct manager mutator call from a UI file. The table below is the exhaustive list — if the implementer finds one not in this table, **stop and flag it** before continuing.

| File:line | Current call | New call (submit_action) |
|---|---|---|
| `scenes/world_map/world_map.gd:440-447` | `if EconomyManager.purchase_facility(...) { WorldManager.place_facility(...); WorldManager.complete_construction(...) }` | `GameManager.submit_action(active_corp_id, ACTION_PLACE_FACILITY, {facility_type, grid_pos: mouse_grid_pos, size})` |
| `scenes/world_map/world_map.gd:577-583` | Same pattern (drag-place) | `GameManager.submit_action(active_corp_id, ACTION_PLACE_FACILITY, {facility_type, grid_pos, size})` inside the loop |
| `scenes/world_map/world_map.gd:883` | `LogisticsManager.create_connection(route_source_id, route_destination_id, product)` | `GameManager.submit_action(active_corp_id, ACTION_CREATE_LOGISTICS_CONNECTION, {source_id, destination_id, product})` |
| `scenes/world_map/world_map.gd:1071-1074` | `EconomyManager.add_money(refund); WorldManager.remove_facility(facility_id)` | `GameManager.submit_action(active_corp_id, ACTION_DEMOLISH_FACILITY, {facility_id})` *(refund handled inside handler)* |
| `scenes/world_map/world_map.gd:1207-1208` | `EconomyManager.subtract_money(cost, ...); WorldManager.place_road(mouse_grid_pos, road_type)` | `GameManager.submit_action(active_corp_id, ACTION_PLACE_ROAD, {grid_pos: mouse_grid_pos, road_type})` |
| `scenes/world_map/world_map.gd:1322-1323` | Same pattern (drag-road) | `GameManager.submit_action(active_corp_id, ACTION_PLACE_ROAD, {grid_pos: pos, road_type})` |
| `scenes/world_map/world_map.gd:1658-1672` | `subtract_money + place_facility + complete_construction + register_field_with_farmhouse + ProductionManager.register_field_with_farmhouse` | `GameManager.submit_action(active_corp_id, ACTION_PLACE_FIELD, {field_type, grid_pos, farmhouse_id})` |
| `scenes/world_map/world_map.gd:2230` | `WorldManager.remove_facility(facility_id)` (debug delete) | `GameManager.submit_action(active_corp_id, ACTION_DEMOLISH_FACILITY, {facility_id})` |
| `scenes/world_map/world_map.gd:2283` | `ResearchManager.research(tech_id)` | `GameManager.submit_action(active_corp_id, ACTION_RESEARCH_TECH, {tech_id})` |
| `scenes/world_map/world_map.gd:2577` | `ResearchManager.research(tech_id)` | `GameManager.submit_action(active_corp_id, ACTION_RESEARCH_TECH, {tech_id})` |
| `scenes/world_map/world_map_ui.gd:615` | `LogisticsManager.toggle_connection_active(connection_id)` | `GameManager.submit_action(active_corp_id, ACTION_TOGGLE_CONNECTION_ACTIVE, {connection_id})` |
| `scenes/world_map/world_map_ui.gd:621` | `LogisticsManager.remove_connection(connection_id)` | `GameManager.submit_action(active_corp_id, ACTION_REMOVE_LOGISTICS_CONNECTION, {connection_id})` |
| `scenes/factory_interior/factory_interior.gd:288-293` | `subtract_money + FactoryManager.place_machine(...)` | `GameManager.submit_action(active_corp_id, ACTION_PLACE_MACHINE, {facility_id, machine_type, grid_pos: mouse_grid_pos, size})` |
| `scenes/factory_interior/factory_interior.gd:360` | `FactoryManager.create_connection(facility_id, from, to)` | `GameManager.submit_action(active_corp_id, ACTION_CREATE_MACHINE_CONNECTION, {facility_id, from_machine_id, to_machine_id})` |
| `scenes/factory_interior/factory_interior.gd:460` | `FactoryManager.remove_connection(facility_id, from, to)` | `GameManager.submit_action(active_corp_id, ACTION_REMOVE_MACHINE_CONNECTION, {facility_id, from_machine_id, to_machine_id})` |
| `scenes/factory_interior/factory_interior.gd:682-690` | `EconomyManager.add_money(refund); FactoryManager.remove_machine(facility_id, machine_id)` | `GameManager.submit_action(active_corp_id, ACTION_DEMOLISH_MACHINE, {facility_id, machine_id})` *(refund handled inside handler)* |
| `scenes/ui/logistics_network_panel.gd:87` | `LogisticsManager.create_connection(_drag_source, target_facility_id, product)` | `GameManager.submit_action(active_corp_id, ACTION_CREATE_LOGISTICS_CONNECTION, {source_id: _drag_source, destination_id: target_facility_id, product})` |
| `scenes/ui/logistics_network_panel.gd:95` | `LogisticsManager.remove_connection(connection_id)` | `GameManager.submit_action(active_corp_id, ACTION_REMOVE_LOGISTICS_CONNECTION, {connection_id})` |
| `scenes/ui/farmhouse_ui.gd:119` | `ProductionManager.set_farmhouse_crop_type(current_farmhouse_id, current_crop)` | `GameManager.submit_action(active_corp_id, ACTION_SET_FARMHOUSE_CROP, {farmhouse_id: current_farmhouse_id, crop_type: current_crop})` |
| `scenes/ui/farmhouse_ui.gd:168` | `ProductionManager.set_farmhouse_crop_type(current_farmhouse_id, crop_type)` | `GameManager.submit_action(active_corp_id, ACTION_SET_FARMHOUSE_CROP, {farmhouse_id: current_farmhouse_id, crop_type})` |
| `scenes/ui/research_tree.gd:392` | `_research_manager.set_dev_mode(button_pressed)` | **Unchanged.** Dev-mode toggle is debug, not state mutation; documented exception. |

**21 call sites in `scenes/` rewired across 5 files.** Largest by count: `scenes/world_map/world_map.gd` with 10 rewires.

Notable removals (these lines disappear because the composite action absorbs them):
- `world_map.gd:447` (`WorldManager.complete_construction` — absorbed by `_action_place_facility`)
- `world_map.gd:583` (same)
- `world_map.gd:1668` (same in field placement)
- `world_map.gd:1071` (`EconomyManager.add_money(refund)` — absorbed by `_action_demolish_facility`)
- `world_map.gd:1671-1672` (`register_field_with_farmhouse` twice — absorbed by `_action_place_field`)
- `factory_interior.gd:682` (refund — absorbed by `_action_demolish_machine`)

After step 3 the rewired sites are noticeably shorter — the UI stops doing transaction orchestration; the pipe does it.

---

## 7. `reset_game()` cleanup — followup from step 1

Add one line. `core/game_manager.gd:reset_game`:

```gdscript
func reset_game() -> void:
    """Reset game to initial state for a new game"""
    print("Resetting game to initial state...")

    current_date = { "year": 1850, "month": 1, "day": 1 }
    current_state = GameState.WORLD_MAP
    is_paused = false
    active_factory_id = ""
    active_corp_id = CORP_SINGLE     # NEW (step 3 cleanup; carried-over flag from step 1)
    game_speed = 1.0

    EconomyManager.reset_economy()
    EventBus.game_reset.emit()
```

Step 1's report flagged this; step 3 picks it up. **Done when:** loading the main menu twice (start new game → quit to menu → start new game) leaves `active_corp_id` at `CORP_SINGLE`.

---

## 8. Micro-step ordering for the implementer

The diff is large enough that splitting commits is worth it for review. Suggested decomposition:

### Commit A — `submit_action` skeleton + EconomyManager rename (+ first action wired)
Files: `core/game_manager.gd` (action constants + payload schema + `submit_action` shell + `_action_spend_money` + `_action_earn_money`), `systems/economy_manager.gd` (rename + predicate). Plus internal-caller updates inside `EconomyManager.purchase_facility`, `refund_facility`, `sell_product`, `pay_maintenance`, `_collect_maintenance` to use new names. Plus internal callers outside EconomyManager (`ResearchManager.research`, `MarketManager._complete_contract`, `WorldManager._remove_field_for_road`).

**Smoke check after A:** game compiles; placing a facility via UI still works (still going through the old direct path); console prints both old and new money paths.

### Commit B — Wire remaining managers' predicates + handlers
Files: `core/game_manager.gd` (all the `_action_*` handlers), all manager predicates (`WorldManager`, `FactoryManager`, `LogisticsManager`, `MarketManager`, `ResearchManager`, `ProductionManager`).

**Smoke check after B:** game compiles; `GameManager.submit_action(active_corp_id, ACTION_PLACE_FACILITY, {...})` works from a console call; UI not yet rewired so it still uses direct calls.

### Commit C — Rewire all UI call sites
Files: `scenes/world_map/world_map.gd`, `scenes/world_map/world_map_ui.gd`, `scenes/factory_interior/factory_interior.gd`, `scenes/ui/logistics_network_panel.gd`, `scenes/ui/farmhouse_ui.gd`.

**Smoke check after C:** the full smoke test (§10) passes; no direct manager mutator calls remain in `scenes/` except the four explicitly allowed paths (§11).

### Commit D — `reset_game` cleanup + audit
Files: `core/game_manager.gd` (one-liner), plus grep verification audit. Add the §12 verification command output to the PR description.

Single PR; 4 commits. If you'd rather one commit, you can; the decomposition is for review-ergonomics, not correctness.

---

## 9. Failure modes and mitigations

### 9.1 A UI call site is missed

**Mitigation:** the audit grep in §12 catches it. Run before commit C lands.

```
rg "(WorldManager|FactoryManager|LogisticsManager|EconomyManager|MarketManager|ResearchManager|ProductionManager)\.(place_facility|remove_facility|place_road|remove_road|place_machine|remove_machine|create_connection|remove_connection|toggle_connection_active|set_connection_active|purchase_facility|refund_facility|sell_product|spend_money|earn_money|set_money|deliver_to_contract|cancel_contract|research|deliver_product|set_farmhouse_crop_type|register_field_with_farmhouse)" scenes/
```

Expected output after step 3 lands: zero hits.

### 9.2 A payload key is missing or wrong type

**Mitigation:** `_validate_action_payload` rejects with `push_error` naming both the action and the missing key. Caught loud. Smoke test §10.6 deliberately submits a malformed payload to verify the path.

### 9.3 A predicate passes but the mutator fails

This is a code bug (predicate and mutator out of sync). Mitigation:
- Composite handlers (`_action_place_facility`, `_action_place_field`, `_action_place_road`, `_action_place_machine`) unwind their money charge if the mutator fails — bug doesn't leak money.
- Non-composite handlers `push_error` with the action name. Loud, visible in console.
- This is exactly the case Phase-12 lockstep would surface as a desync; getting it loud now is the prep.

### 9.4 Determinism regression

**Mitigation:** the pipe is the *only* new mutation entry. No `randf()` calls introduced. If the implementer feels tempted to add randomness inside an action handler (e.g. random refund?), stop and flag — that's the next phase (seeded RNG), not this one. Audit grep: `rg "randf\(\)|randi\(\)|randf_range|randi_range" core/game_manager.gd` should return zero hits after step 3.

### 9.5 EventBus double-emission

If both the pipe handler and the mutator emit the same EventBus signal, UI updates twice (or, worse, gets confused state). **Rule (already enforced by §0.5):** only the manager mutator emits; pipe handlers don't touch EventBus directly (with one explicit exception — `_action_create_logistics_connection` re-emits `EventBus.notification_posted` for the "no road" rejection, because that string is currently shown to the user via the existing notification path, not pushed via `push_warning`. Preserve the UX).

### 9.6 Save format regression

Save schema doesn't change in step 3. Smoke test §10.7 saves+loads to verify nothing in the action pipe is accidentally persisted or referenced from a save path.

### 9.7 ResearchManager `can_research` wrapper drift

The one-liner wrapper around `can_research_v2` (§4.6) is the only alias kept in step 3. If a Phase-9 or Phase-10 commit removes `can_research_v2` and forgets the wrapper, UI greys-out logic silently breaks. Mitigation: TODO comment with explicit phase 10 deletion target. Grep `can_research(` (without `_v2`) in `scenes/` to find the consumers when the corp-switcher UI lands.

### 9.8 `set_dev_mode` exception drift

Dev-mode toggle bypasses the pipe per §0.4 doc. If a future change makes dev-mode-state save-relevant (e.g., dev-mode persists across save load), it must be routed. Add a code comment on `set_dev_mode` saying so. Mitigation is a comment, not a check — dev mode is debug-only.

---

## 10. Smoke test sequence

Run in Godot before declaring step 3 done. Trace logs must be on (debug build). Each step has a verification.

1. **Launch the game.** Console shows `Active corp: single -> single` (or no message — startup doesn't switch). `GameManager.active_corp_id == "single"`.

2. **Place a Barley Field** via the build menu.
   - Console shows the existing `Facility placed: barley_field ...` line.
   - No `push_error` or `push_warning` in the log.
   - Field appears on the map.
   - Money decreased by Barley Field cost.

3. **Add a `print()` line at the top of `submit_action`** (temporary; remove after smoke test):
   ```gdscript
   print("submit_action: corp=%s action=%s payload_keys=%s" % [corp_id, action_type, payload.keys()])
   ```
   - Re-place a facility. Console line appears with `action=place_facility`.
   - Remove the temporary print.

4. **Demolish the field** via demolish mode.
   - Console shows the existing demolish log.
   - Money increased by 50% refund (verify math: $250 refund for $500 field).
   - Field disappears.

5. **Place a Brewery** ($1500).
   - Verify money decreased by $1500.
   - Enter the brewery interior (double-click).

6. **Place a Mash Tun** inside the brewery.
   - Money decreased.
   - Mash Tun appears.

7. **Create a machine-machine connection** (Mash Tun → some other machine, after placing the other machine).
   - Connection line drawn.
   - Console shows existing connection-created log.

8. **Demolish the machine connection** via delete-connection mode.
   - Line removed.

9. **Return to world map**, place a Grain Mill, build a road between Brewery and Grain Mill, **create a logistics connection** (Grain Mill → Brewery) carrying `malt`.
   - Connection created.
   - A vehicle auto-dispatches (verify in console).

10. **Toggle the connection** (pause / resume) via the routes panel.
    - Console shows `Connection conn_1 paused` / `resumed`.

11. **Remove the connection.**
    - Vehicle disappears.
    - Connection gone.

12. **Predicate rejection — try to place a facility on an occupied tile** (place a field on top of the Brewery).
    - Console shows `ACTION_PLACE_FACILITY rejected: Invalid placement: out of bounds or tile occupied`.
    - Money NOT charged.
    - UI does not show the facility being placed.

13. **Predicate rejection — try to research a locked tech** (any tech with prerequisites you haven't met).
    - Click the research button.
    - Console shows `ACTION_RESEARCH_TECH rejected: Missing prerequisite: <tech_id>`.
    - Money not charged.

14. **Payload validation — invoke `submit_action` from console with malformed payload:**
    ```gdscript
    GameManager.submit_action("single", "place_facility", {"facility_type": "barley_field"})
    ```
    - Console shows `submit_action: action 'place_facility' missing required payload key 'grid_pos'`.
    - Returns `false`.

15. **Save → load** (F5 then F9).
    - All entities persist.
    - Money restored.
    - No `push_error` in the load path.

16. **Reset game** (main menu → new game).
    - `active_corp_id` is `CORP_SINGLE` (verify via console: `print(GameManager.active_corp_id)` should print `single`).

17. **Optional: corp-id smoke check.** `GameManager.set_active_corp("agri")` then place a facility — confirm via `print(WorldManager.facilities[<id>].corp_id)` that the new facility has `corp_id: "agri"`. The action pipe propagated it from `active_corp_id` correctly. Reset back to `single` after.

**Done when:** all 17 checks pass with no unexpected push_error / push_warning lines.

---

## 11. Explicit exceptions — direct manager calls allowed after step 3

These remain after step 3 and are **intentionally not routed** through the pipe. Each has a one-line code comment documenting why.

| Site | Why exempt |
|---|---|
| Internal manager-to-manager calls (e.g., `EconomyManager.spend_money` from inside `_action_place_facility`'s handler, or from `ResearchManager.research`) | Compositional — already inside an action; routing would double-validate and double-emit |
| `EconomyManager.set_money` from save-load restore | Save/load is local-only; restoring is not an action |
| `EconomyManager.reset_economy` from `GameManager.reset_game` | Reset is a meta-action that runs before the pipe is conceptually relevant |
| `EconomyManager._collect_maintenance` and downstream | Tick-driven internal state; not user-initiated |
| `MarketManager._try_generate_contract`, `_complete_contract`, `_check_contract_expirations`, `_decay_supply_pressure` | All tick-driven |
| `LogisticsManager._update_vehicles`, `_check_auto_dispatch`, `_create_vehicle`, `_remove_vehicle` | Tick-driven |
| `WorldManager.start_production`, `stop_production` (called from EconomyManager's enable/disable) | Internal compositional, currently never user-driven |
| `WorldManager.complete_construction` from inside `_action_place_facility` / `_action_place_field` | Compositional — inside an action |
| `WorldManager._remove_field_for_road` and `_unregister_field_from_farmhouse` | Internal compositional from `place_road` flow |
| `FactoryManager.create_factory_interior` driven by `_on_facility_placed` signal | Reactive derived state, not user input |
| `ResearchManager.set_dev_mode` from research tree UI | Debug toggle, not gameplay state |
| `ResearchManager.try_unlock_next_tier` (auto-triggered when deliveries threshold met) | Threshold-driven, not user input |
| `ProductionManager.add_item_to_facility` / `remove_item_from_facility` from logistics tick | Tick-driven |
| `road_renderer._remove_road_tile` | Visual cleanup driven by EventBus, not a mutator |

Phase 12 will revisit several of these (tick-driven mutations need a host-authoritative tick, which is a pipe-adjacent concept). For step 3, they stay direct.

---

## 12. Audit grep — paste into PR description

After commit C and before commit D, run from the repo root:

```
# Mutator calls from scenes/ that bypass the pipe — must be empty
rg "(WorldManager|FactoryManager|LogisticsManager|EconomyManager|MarketManager|ResearchManager|ProductionManager)\.(place_facility|remove_facility|place_road|remove_road|place_machine|remove_machine|create_connection|remove_connection|toggle_connection_active|set_connection_active|purchase_facility|refund_facility|sell_product|spend_money|earn_money|set_money|deliver_to_contract|cancel_contract|research|deliver_product|set_farmhouse_crop_type|register_field_with_farmhouse|complete_construction)" scenes/

# Old EconomyManager names — must be empty
rg "(subtract_money|add_money|can_afford)" scenes/ systems/ core/

# submit_action references in scenes/ — must be non-empty (the rewires)
rg "GameManager\.submit_action" scenes/
```

The first two should return zero hits. The third should return ~21 hits (the rewired call sites; the count matches §6's table).

`add_money` and `subtract_money` may still appear in `core/save_manager.gd` if save migration touches money fields by name — verify those are reading from saved JSON keys, not calling EconomyManager methods. Keep `set_money` for the load path.

---

## 13. Files touched (final inventory)

```
core/game_manager.gd                          (+~350 lines) — action constants, payload schema, submit_action, 19 _action_* handlers, reset_game cleanup
systems/world_manager.gd                      (+~60 lines)  — can_place_facility_v2, can_remove_facility, can_place_road (corp-aware), can_remove_road; rename can_place_facility → _can_place_facility_geometry, can_place_road → _can_place_road_geometry
systems/factory_manager.gd                    (+~50 lines)  — can_place_machine_v2, can_remove_machine, can_create_machine_connection, can_remove_machine_connection; rename can_place_machine → _can_place_machine_geometry
systems/logistics_manager.gd                  (+~40 lines)  — can_create_connection, can_remove_connection, can_toggle_connection_active
systems/economy_manager.gd                    (~+50 -30 lines) — rename subtract_money/add_money/can_afford → spend_money/earn_money/can_spend_money; add corp_id param; update internal callers
systems/market_manager.gd                     (+~30 lines)  — can_deliver_to_contract, can_cancel_contract; update _complete_contract internal earn_money call
systems/research_manager.gd                   (+~20 lines)  — can_research_v2; one-liner can_research wrapper; update internal spend_money call
systems/production_manager.gd                 (+~15 lines)  — can_set_farmhouse_crop
scenes/world_map/world_map.gd                 (~-50 lines net) — 10 rewires (composites shrink call-site bodies)
scenes/world_map/world_map_ui.gd              (~+0 lines)    — 2 rewires (one-line swaps)
scenes/factory_interior/factory_interior.gd   (~-15 lines net) — 4 rewires; refund/charge orchestration moves to pipe
scenes/ui/logistics_network_panel.gd          (~+0 lines)    — 2 rewires
scenes/ui/farmhouse_ui.gd                     (~+0 lines)    — 2 rewires
```

Net diff: ~+550 / ~-100, single PR / 4 commits per §8. No new files. No new autoloads. No JSON changes. No save-schema changes.

---

## 14. Open questions and resolutions

### A2 — Hot-seat process model
**Resolution: not gated by step 3.** The pipe is in-process regardless. When multi-process testing arrives (per technical-architecture A2 recommendation: after steps 1–4 are proven), each process will own a local `submit_action` and route through a transport that's NOT-yet-defined. Pipe shape unchanged.

### EconomyManager actions through the pipe — confirmed yes
Per §0.4: every `spend_money` / `earn_money` from UI or cross-manager composition goes through `ACTION_SPEND_MONEY` / `ACTION_EARN_MONEY`. Internal compositional calls (inside other action handlers) stay direct. This is the resolution promised in the prompt.

### Action ordering and re-entrancy
The pipe is **synchronous** in v1 — `submit_action` returns when the mutator returns. No queueing, no deferred execution. **The pipe must not be called from inside a manager mutator** (re-entrancy would double-validate and corrupt state). The implementer should add an assertion in `submit_action`:

```gdscript
var _in_action: bool = false  # re-entrancy guard

func submit_action(corp_id: String, action_type: String, payload: Dictionary) -> bool:
    assert(not _in_action, "submit_action is not re-entrant. Internal manager calls must be direct.")
    _in_action = true
    var result := _submit_action_impl(corp_id, action_type, payload)
    _in_action = false
    return result
```

In release builds the assertion compiles out; in debug it catches the bug class loudly. This is the single most important defensive check in step 3 — get it in.

### Forward-compat for replay/save-action-log
Phase 12's lockstep model wants an action log. Step 3 does not record one. The dispatch shape is record-friendly (every mutation is `corp_id + action_type + payload` — trivially serializable). Phase 12 adds the log at the top of `submit_action`; no other code changes. **Don't try to add the log now** — there's no consumer.

### Predicate placement decision — confirmed
Predicates live on the managers, not on `GameManager`. The pipe is the dispatcher; the data-owning manager is the validator. This keeps `GameManager` from reaching into other managers' private state, and makes the predicate a natural place to add corp-permission gating in Phase 10. Justification per §0.1.

---

## 15. What I'm leaving for the implementer to call out

If any of these surface during implementation, **stop and flag back to the architect:**

- A mutator call from `scenes/` not in §6's table. Add it; the inventory should be exhaustive.
- A composite action whose unwind logic doesn't trivially restore money on mutator failure (e.g., if the place mutator has a side-effect besides creating the dict). Today the mutators are clean — flag if that changes.
- An EventBus signal that gets emitted *twice* during a single action (pipe handler emits and mutator emits). Should never happen per §0.5; flag if observed.
- A `set_money` call from a UI path (save/load is exempt; UI is not). None today; flag if added.
- A new manager mutator added during step 3 that's not in the inventory. Update the action-type registry in the same commit.
- A determinism regression — `randf()` introduced into any action handler. Stop and route through a seeded RNG.
- `world_map.gd:447` etc. (`complete_construction`) — the implementer might want to keep these "for safety." They're absorbed into the composite action; leaving them creates double-completion. Remove them.

---

## 16. Coupling with later phases

This plan is the linchpin commit for Phase 10 (asymmetric corp scaffold), Phase 11 (cross-corp tension, events, security), and Phase 12 (networking). Decisions baked in here that affect later phases:

- **Action-type strings are stable.** Renaming them is a protocol break.
- **Predicate signature is `Dictionary { ok, reason }`.** Adding fields is fine; renaming `ok` or `reason` breaks every predicate caller. Settle on these names now.
- **Pipe is synchronous and re-entrancy-guarded.** Phase 12's queue/buffer/sequence work goes around the pipe (above it), not through it.
- **Composite actions are the unit of atomicity.** When per-corp wallets land (v3→v4), the composite handlers don't change — only `spend_money`'s implementation does. The pipe handler's `corp_id` argument is already in place.
- **EventBus signals stay past-tense facts.** Phase 11's narrative engine reads them as triggers.

If any of those decisions need to change in a later phase, the cost is high. Plan accordingly.

