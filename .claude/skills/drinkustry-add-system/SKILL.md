---
name: drinkustry-add-system
description: Use when adding a new singleton manager, new system (UtilityManager, CatchmentManager, OverlayManager, DemandManager, EventManager, SecurityManager), new EventBus signal, or new entity type to the Drinkustry / butykos Godot codebase. Captures the project's singleton + EventBus + data-driven + corp-ownership conventions so new code matches existing patterns.
---

# Drinkustry — adding a new system

Use this whenever you're about to introduce a new manager, signal, entity type, or data file. Following the conventions matters because every new system has to slot into the ownership layer + action pipe being built in Phase 8.

## 1. Decide: new manager vs extend existing

Default to **extending an existing manager** unless the new system has its own data structure that doesn't fit. Examples:

- Irrigation network → **extend** `LogisticsManager` (it IS a logistics graph; add `network_kind: "transport" | "irrigation" | "utility"` per network)
- Water + power + sewage → **one new** `UtilityManager` with three named graphs (don't make three managers — same propagation algorithm, different content tags)
- Heat-map overlays → **one new** `OverlayManager` (generic data → texture pipeline that all overlays use; build it generic the first time)
- Settlement-tier spatial demand → **one new** `DemandManager` (Business-corp-owned conceptually)
- Narrative events → **one new** `EventManager` (data-driven from `data/events/*.json`)
- Espionage/integrity → **one new** `SecurityManager`

If you do create a new manager, register it in `project.godot` `[autoload]` and add it to the singleton list near the top of `CLAUDE.md`.

## 2. Manager skeleton (matches existing patterns)

```gdscript
extends Node
# SystemManager — owns <state>; emits <signals>; receives via EventBus

# State — typed Dictionaries keyed by entity id
var _entities: Dictionary = {}  # entity_id (String) -> { corp_id: String, ... }

func _ready() -> void:
    # Subscribe to relevant EventBus signals
    EventBus.facility_placed.connect(_on_facility_placed)

# Public API — predicate-then-action
func can_<action>(corp_id: String, ...) -> Dictionary:
    # Returns { ok: bool, reason: String }
    # UI calls this to gate buttons; manager calls this internally before mutation
    ...

func <action>(corp_id: String, ...) -> bool:
    var check := can_<action>(corp_id, ...)
    if not check.ok:
        push_warning("Rejected: %s" % check.reason)
        return false
    # Mutate state
    # Emit EventBus signal
    return true

# Save/load — match SaveManager schema v3
func save_state() -> Dictionary: ...
func load_state(data: Dictionary) -> void: ...
```

## 3. Corp ownership rules

- **Every owned entity gets `corp_id: String`.** Facilities, machines, routes, vehicles, contracts, research nodes, irrigation pipes, sales outlets, espionage outposts.
- **Reserve `corp_id: "shared"`** for utilities, shared research, neutral roads. World tiles are unowned by default (no field).
- **Pre-MP migration:** existing single-player saves get `corp_id: "single"` on load, then a migration script bumps each entity to one of the four corps based on building type. This is a save-schema break (v2 → v3).
- **Validation lives in the manager**, not in UI. UI calls `can_<action>(corp_id, ...)` to grey out buttons; manager rejects with reason if called anyway. Managers don't silently filter — always reject explicitly.

## 4. Action pipe

All state mutations go through `GameManager.submit_action(corp_id, action_type, payload)`. This is the seam that becomes the network boundary in Phase 12. Until Phase 12 it's a thin wrapper that just dispatches to the right manager. **Don't bypass it** even for "simple" mutations — the moment you bypass it once, MP becomes a rewrite instead of glue.

## 5. EventBus signals

- Add new signals to `core/event_bus.gd` near related signals.
- **Naming:** past tense (`facility_placed`, `connection_created`), not commands (`place_facility`).
- **Payloads:** prefer typed parameters over `Dictionary`. Pass entity ids, not full entities — receivers query the manager.
- The EventBus is a **local notification layer**; the action pipe is the network layer. Don't push action-intent through the bus; push facts.

## 6. Data-driven content

New content types go in `data/<type>.json` or `data/<type>/<subtype>.json`. Schema must be:
- **Mod-stable:** if it's content (events, recipes, contracts, research nodes), document the schema and treat it as public surface.
- **Internal:** if it's mechanical (utility-network primitives, catchment-rule constants), don't promise stability.

`DataManager` loads JSON at startup. Add new loaders there. Validate schema on load (fail loud, not silently).

## 7. Save schema

Update `core/save_manager.gd`:
- Bump `version` if you change schema shape
- Add a migration block from previous version
- Match the schema v3 partition shape: `{ version, corps: { agri: {...}, industrial: {...}, ... }, shared: {...}, utilities: {...}, events: {...} }`
- **JSON, not binary.** Debugging > size.

## 8. Determinism

Code from Phase 8 onward must be deterministic so Phase 12 networking works. Specifically:
- Use seeded RNG via the action pipe; don't call `randf()` directly in tick code
- Use a game-tick counter, not `Time.get_unix_time_from_system()`
- Don't depend on dictionary iteration order for state; use `keys().sort()` if order matters
- Vehicles already use fixed-tick movement — keep that pattern

## 9. Performance bounds

Targets per technical-architecture doc:
- 60 fps with 200 facilities, 4 corps active, all overlays on
- O(edges) per tick on graph propagation, dirty-flagged
- Catchment queries via spatial hash (not per-facility distance check)
- Overlay textures regenerate only on dirty events
- Event tick at 1Hz (not per-frame), bounded queue

## 10. Update CLAUDE.md gotchas if relevant

If your new system introduces a footgun (mode conflict, coordinate trap, ordering requirement), add a one-liner to the "Common Gotchas" section in `CLAUDE.md`. The list is short on purpose — only add if it would bite a future implementer.

## 11. Documentation

For systems landing in slice-1 / Phase 8–11, write a short section in `design_docs/2026-05-07_technical_architecture.html` (the technical doc). For experimental / brainstorm work, create a new dated `design_docs/YYYY-MM-DD_<topic>.html` matching the existing HTML style — see the `drinkustry-design-doc` skill.
