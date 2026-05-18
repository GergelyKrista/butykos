---
name: drinkustry-corp-ownership
description: Use during the Phase 8 corp-ownership refactor or whenever adding `corp_id` to an entity, gating an action by corp, or reasoning about who-owns-what. Triggers on requests like "add corp ownership to X", "gate this by corp", "who owns the routes", "make this corp-aware", or any work touching the ownership layer that's keystone to the Drinkustry pivot.
---

# Drinkustry — corp ownership refactor

Phase 8's keystone change. Every singleton currently assumes one player. This skill captures the pattern for adding the corp-ownership layer additively (no rewrite).

## The four corps

```
agri        — Agricultural: fields, orchards, silos, irrigation
industrial  — Industrial: factories with internal grids (the depth-bar reference)
logistics   — Logistics: routes, depots, vehicles, utilities, roads
business    — Business: sales outlets, demand, contracts, espionage
```

Plus the meta-corp:
```
shared      — utilities, shared research, neutral roads, world tiles
```

Reserve `corp_id: "shared"` for cross-corp infrastructure. Don't invent per-system shared markers.

## What gets a corp_id field

**Owned entities (must have `corp_id`):**
- Facilities (incl. fields, farmhouses, brewery, distillery, silo, sales outlet, espionage outpost)
- Machines (inside factory interiors)
- Routes / connections / vehicles
- Contracts
- Research nodes (per-corp internal layer)
- Sales outlets and trade depots
- Irrigation pipe networks
- Espionage outposts and security outposts

**Shared entities (`corp_id: "shared"`):**
- Utility networks (water mains, power lines, sewage)
- Shared research nodes
- Public roads (Logistics-managed but accessible to all)

**Unowned (no `corp_id` field at all):**
- World tiles (terrain itself)
- Suitability / pollution overlay data
- Catchment regions (computed)
- Game settings, RNG state, tick counter

## Adding corp_id to an existing entity type

```gdscript
# Before (pre-pivot single-player)
var facility := {
    "id": id,
    "facility_type": facility_type,
    "grid_pos": grid_pos,
    ...
}

# After (Phase 8 onward)
var facility := {
    "id": id,
    "corp_id": corp_id,        # NEW — required, no default
    "facility_type": facility_type,
    "grid_pos": grid_pos,
    ...
}
```

**No default.** Every code path that creates an entity must pass `corp_id` explicitly. The action pipe makes this easy — `submit_action(corp_id, ...)` already has it.

## Migration of legacy saves

Existing v1/v2 saves don't have `corp_id`. The migration to v3 buckets facilities by type:

```gdscript
func _facility_type_to_corp(facility_type: String) -> String:
    match facility_type:
        "barley_field", "wheat_farm", "farmhouse", "field": return "agri"
        "grain_mill", "malt_house", "brewery", "distillery", "packaging_plant": return "industrial"
        "storage_warehouse", "truck_depot": return "logistics"
        "sales_outlet", "trading_depot": return "business"
        _:
            push_warning("Unknown facility_type %s — defaulting to industrial" % facility_type)
            return "industrial"
```

Update this match statement when adding new facility types.

## Predicate-then-action gating

Every mutator checks corp ownership before acting:

```gdscript
func can_demolish_facility(corp_id: String, facility_id: String) -> Dictionary:
    var facility = _facilities.get(facility_id)
    if facility == null:
        return { "ok": false, "reason": "Facility not found" }
    if facility.corp_id != corp_id and facility.corp_id != "shared":
        return { "ok": false, "reason": "Corp %s does not own facility %s (owned by %s)" % [corp_id, facility_id, facility.corp_id] }
    return { "ok": true, "reason": "" }
```

Note the `"shared"` exception — corps can demolish their own things AND shared infrastructure they're authorized for. (Authorization for shared demolition is itself a corp question; defer that to per-system rules.)

## Cross-corp interaction

Some actions span corps:
- **Logistics building a route from an Agri silo to an Industrial brewery:** Logistics owns the route entity; the silo and brewery belong to their respective corps. The route has `corp_id: "logistics"`; `source_facility_id` and `dest_facility_id` reference cross-corp facilities by id.
- **Business reading demand at an Industrial brewery's catchment:** demand is unowned data; the catchment query is corp-blind.
- **Agri's biological waste auto-flowing to its own fertilizer plant:** internal corp loop, no cross-corp involvement.

Pattern: **the entity being acted upon owns its corp_id; the action's actor is the `corp_id` parameter to `submit_action`.** Rejection happens when actor ≠ owner AND owner ≠ shared (with system-specific exceptions).

## What about machines inside factories?

Machines inside an Industrial factory inherit the factory's corp_id implicitly — currently `industrial`. When other corps gain interior-style mechanics (Logistics depot interiors for vehicle assembly), their machines will be `logistics`-owned. Don't hardcode "industrial" anywhere; query the parent facility's corp_id.

## UI gating

UI calls the predicate before showing buttons:

```gdscript
func _refresh_demolish_button() -> void:
    var check = WorldManager.can_demolish_facility(GameManager.active_corp_id, _selected_facility_id)
    demolish_button.disabled = not check.ok
    demolish_button.tooltip_text = check.reason if not check.ok else "Demolish (50% refund)"
```

This avoids the player clicking and getting a silent failure. Clear feedback > graceful degradation.

## Open question: tradable ownership

Currently corp ownership is immutable per-game. Could corps trade buildings? **Recommend immutable for v1; tradable for v1.5+** — see open question A1 in `design_docs/2026-05-07_technical_architecture.html`. Don't build for tradability now; just don't write code that *prevents* it (e.g., don't bake `corp_id` into entity ids).

## Action pipe is the choke point

Every mutation routes through `GameManager.submit_action(corp_id, action_type, payload)`. The action pipe is where corp_id arrives from the UI and propagates into managers. Don't bypass it.

```gdscript
# WRONG — UI directly calling manager, bypassing the pipe
WorldManager.place_facility("agri", "barley_field", Vector2i(5, 5))

# RIGHT — UI submitting an action; pipe dispatches to manager
GameManager.submit_action(GameManager.active_corp_id, "place_facility", {
    "facility_type": "barley_field",
    "grid_pos": Vector2i(5, 5),
})
```

## Defensive fallback on write (step 2+)

When gathering save data, any entity with a missing or invalid `corp_id` must not silently inject into a wrong partition. Pattern established in step 2:

```gdscript
func _resolve_entity_corp_for_write(entity_dict: Dictionary, default_corp: String) -> String:
    var cid: String = entity_dict.get("corp_id", "")
    if cid in [GameManager.CORP_AGRI, GameManager.CORP_INDUSTRIAL,
               GameManager.CORP_LOGISTICS, GameManager.CORP_BUSINESS]:
        return cid
    push_error("Entity has invalid corp_id '%s' for save; routing to %s" % [cid, default_corp])
    return default_corp
```

Default values per entity type:
- Facilities → `GameManager.CORP_INDUSTRIAL`
- Connections / vehicles → `GameManager.CORP_LOGISTICS`
- Contracts → `GameManager.CORP_BUSINESS`

`push_error` (not `push_warning`) because a missing corp_id at write time means a step-1 code path didn't propagate the field — that is a bug, not a recoverable ambiguity.

## Rollout order (matches refactor ordering in technical doc §7)

1. ~~Add `corp_id` field to facility/machine/route/vehicle/contract entities~~ — **shipped (step 1, 2026-05-18)**; defaults to `"single"` with no behavior gating.
2. ~~Bump save schema to v3 with per-corp partitions; write migration~~ — **shipped (step 2, 2026-05-18)**; `shared.money` for now; v3→v4 migration when EconomyManager per-corp wallets land.
3. Wire `submit_action` skeleton; route every UI mutation through it — **next (step 3)**
4. Add `can_<action>(corp_id, ...)` predicates to every mutator
5. Surface `active_corp_id` in `GameManager` and a corp-switcher UI for hot-seat dev
6. Add per-corp build menus

Don't skip ordering. The earlier steps are prereqs for the later ones; if you do step 5 before step 1, you have a corp switcher with nothing to switch.
