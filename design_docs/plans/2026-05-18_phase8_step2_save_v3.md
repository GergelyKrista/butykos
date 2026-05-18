# Phase 8 — Step 2: Save Schema v3 + Migration from v1

**Doc type:** Refactor plan, hand-off to drinkustry-implementer
**Date:** 2026-05-18
**Author:** Architect
**Scope:** Bump `CURRENT_SAVE_VERSION` to 3, write a `_migrate_to_v3()` that absorbs v1 (pre-step-0.5), v1 (post-step-0.5), and v1+corp_id (post-step-1) shapes uniformly. Drop the step-0.5 tolerant reads. Rebucket every legacy facility/machine/connection/contract into per-corp partitions on first load.
**Predecessor:** `design_docs/plans/2026-05-18_phase8_step1_corp_id.md`
**Companion skills:** `.claude/skills/drinkustry-save-migration/SKILL.md`, `.claude/skills/drinkustry-corp-ownership/SKILL.md`
**Successor:** `2026-05-18_phase8_step3_action_pipe.md` (not yet written).

---

## TL;DR for the implementer

You will rewrite `_gather_save_data` and `_apply_save_data` to read/write the v3 shape: a top-level dict with `version: 3`, a `shared` block for cross-corp infra, and a `corps` block partitioned into the four corps. You will add `_migrate_to_v3(data, from_version)` that walks any legacy save (flat single-bucket) and rebuckets entities by their `corp_id` field — falling back to a facility/machine-type → corp lookup when `corp_id` is missing (pre-step-1 saves). The legacy file is backed up to `<slot>.save.v1.bak` before any v3 file overwrites it. Writes are v3-only; the step-0.5 `routes`/`route_paths`/`next_route_id`/`route_id` tolerant-read fallbacks are deleted (their fallback path moves into `_migrate_to_v3`).

When you are done:

- `quicksave.save` (post-step-1) loads cleanly, re-saves as v3, reloads cleanly.
- `ghibbon.save` (pre-step-0.5, no `corp_id`, legacy `routes` key) loads cleanly, gets backed up to `ghibbon.save.v1.bak`, re-saves as v3 with the grain_mill in `corps.industrial` and brewery in `corps.industrial`.
- `rg 'TODO\(step-2 v3 bump\)' core/` returns zero hits.
- `rg '"routes"|"route_paths"|"next_route_id"|"route_id"' core/save_manager.gd` returns zero hits.

**One PR, one commit.** Diff target: 200–300 lines including the migration function.

---

## 0. Architectural decisions baked into this plan

The technical-architecture doc §5 and the save-migration skill give two slightly different v3 shapes. Reconciling them is the first decision:

### 0.1 Money stays in `shared.money` for step 2

The technical doc §5.2 says current money becomes `corps.business.money`. The skill (lines 32–33) shows `money` on each corp partition. **Recommendation: in step 2, money lives at `shared.money`.**

Why: step 2 is the schema-shape commit. Step 3 introduces `submit_action(corp_id, …)` which is when corp-gated spending becomes a real concept. Step 1 already pushed `corp_id` onto entities; per-corp wallets are a Phase 8 entry-checklist item but distinct from this commit. Forcing money into `corps.business.money` in step 2 either:

1. Pushes step-2 to also implement an EconomyManager refactor (scope creep), or
2. Leaves all four corps with `money: 0` except business — and there is no corp-switcher yet, so the player would lose their bank.

`shared.money` preserves the v1 single-wallet semantics behind a schema shape that **lifts trivially** when per-corp wallets land. The lift is "delete `shared.money`, populate `corps.<corp>.money` from it." That happens in the EconomyManager-refactor commit, with its own forward migration v3→v4.

**Load-bearing flag:** the EconomyManager refactor in a later step is a v3 → v4 migration. Plan for it; don't try to land it here.

### 0.2 Per-corp partition shape: only entities, not derived data

The skill shows each corp partition with `money`, `facilities`, `machines`, `routes`, `vehicles`, `research_internal`, `contracts`. We hew to that but with one departure: **per-corp `money` is absent in step 2** (see 0.1).

```
corps.<corp_id> = {
    "facilities":   { "<id>": {...}, ... },
    "machines":     { "<id>": {...}, ... },
    "connections":  { "<id>": {...}, ... },   # routes are now Logistics-owned (mostly); other corps' partitions hold zero in v1
    "vehicles":     { "<id>": {...}, ... },
    "contracts":    [ {...}, ... ],
    "research_internal": { "unlocked_techs": [], "current_tier": 1, "tier_deliveries": {} }
}
```

**Why connection/vehicle dicts under each corp instead of all under logistics:** the corp_id-on-entity is the source of truth (skill rule). If Logistics owns a route today and Agri buys-out the route in v1.5+, the migration is "move the dict from corps.logistics.connections to corps.agri.connections" — clean. Keeping all connections under one place would break that contract.

**In v1 reality:** `corps.logistics.connections` holds 99% of the rows; the other three corps hold zero. The shape costs four empty dicts per save. Fine.

**Departure from skill `"routes"` key naming:** the skill (line 110) used the legacy `routes` name. We use the canonical `connections` per step 0.5's no-alias-creep rule. **The skill should be updated to match after this lands** (see §10 follow-ups).

### 0.3 `production` is per-corp by partition of its keys

`ProductionManager` state is keyed by `facility_id` and `machine_id` (or `facility_id|machine_id` composites). Each of those ids resolves to a corp via the facility's `corp_id`. So `production_timers`, `production_outputs`, `machine_timers`, `machine_inventories`, `facility_stats`, `farmhouse_crop_types`, `field_production_targets` all partition by **looking up the owning facility's corp** for each key.

**Per-corp partition for production state:**

```
corps.<corp_id>.production = {
    "production_timers": { "<facility_id>": float, ... },
    "production_outputs": { "<facility_id>": {...}, ... },
    "machine_timers": { "<machine_key>": float, ... },
    "machine_inventories": { "<machine_key>": {...}, ... },
    "facility_stats": { "<facility_id>": {...}, ... },
    "farmhouse_crop_types": { "<farmhouse_id>": "...", ... },
    "field_production_targets": { "<field_id>": "...", ... }
}
```

A machine_key has the form `"<facility_id>|<machine_id>"` (verify in `production_manager.gd` before implementing — see §6 micro-step 4c). Resolving its corp = the parent facility's corp.

### 0.4 What goes into `shared`

```
shared = {
    "money": <int>,                           # see 0.1; lifts to per-corp in v4
    "total_earned": <int>,
    "total_spent": <int>,
    "total_maintenance_paid": <int>,
    "last_maintenance_cost": <int>,
    "disabled_facilities": [<facility_id>, ...],

    "world_tiles": {                          # the grid is global; not corp-owned
        "next_facility_id": <int>,
        "roads": { "x,y": "<road_type>", ... },
        "field_parents": { "<field_id>": "<farmhouse_id>", ... },
        "farmhouse_children": { "<farmhouse_id>": [<field_id>, ...], ... }
    },

    "next_machine_id": <int>,                 # FactoryManager global counter, deliberately not per-corp
    "next_connection_id": <int>,              # LogisticsManager global counter
    "next_vehicle_id": <int>,
    "next_contract_id": <int>,                # MarketManager global counter

    "factory_grids": { "<facility_id>": "<base64-of-empty-grid-or-omitted>" }, # see 0.5

    "factory_connections": {                  # machine-to-machine connections inside factory interiors
        "<facility_id>": [ {"from": "<machine_id>", "to": "<machine_id>"}, ... ]
    },

    "market": {                               # global market state (no contracts — those moved to corps.business.contracts)
        "current_prices": {...},
        "price_multipliers": {...},
        "supply_pressure": {...},
        "market_trends": {...}
    },

    "research_shared": null                   # placeholder for two-layer tree refactor (step 4 of master)
}
```

`disabled_facilities` lives in `shared` because the per-facility ownership is captured in the facility dict itself; the disabled-list is just a flat lookup set against any of those facilities.

`next_machine_id`, `next_connection_id`, `next_vehicle_id`, `next_contract_id` are global to avoid id collisions. Per the step-1 plan's A1 resolution: ids are corp-blind opaque counters, ownership is a field on the entity. Keep that contract.

### 0.5 Factory interior grids — drop them from save, rebuild on load

The current `_gather_factory_data` saves `interior.grid` implicitly via the absence of saving it (it's a 20×20 array of machine_ids per facility — `_initialize_interior_grid()` already runs on restore and the grid is rebuilt by re-occupying tiles when machines are reconstructed at `save_manager.gd:589–593`). **This logic stays.** The line item `factory_grids` in 0.4 is **NOT** in the v3 schema — listed only to make the omission explicit so the implementer doesn't accidentally serialize the grid. Remove that bullet from the final shape doc-comment.

### 0.6 New top-level placeholder fields (per the skill)

```
utilities = null    # reserved for v4 (Phase 11)
events = null       # reserved for v5 (Phase 11)
```

Present in the v3 shape from day one. Always written as JSON `null`. Read tolerantly (default `null` on absence).

### 0.7 Top-level fields that stay at the root

```
version: 3
wall_timestamp: <unix>          # for save-list sort, never sim-relevant
date: { year, month, day }
game_state: "WORLD_MAP" | "FACTORY_VIEW" | ...
active_corp_id: "single" | "agri" | ...
active_factory_id: ""           # added for state preservation through save/load
tick_count: 0                   # reserved for determinism work; always 0 in step 2
rng_seed: 0                     # reserved for determinism work; always 0 in step 2
```

`tick_count` and `rng_seed` are skill-required (skill lines 30–31) but not yet driven by anything in the code. Write them as 0. The determinism-refactor commit will populate them and bump the version when their semantics solidify.

Renaming `timestamp` → `wall_timestamp` is intentional: the technical doc §9 (determinism section) calls out that wall-clock `Time.get_unix_time_from_system()` is sim-poisonous if anyone treats it as sim time. The rename forces a search-and-find on any future code that mistakes save metadata for game-tick time.

---

## 1. The full v3 schema, written out

```json
{
  "version": 3,
  "wall_timestamp": 1779106576.724,
  "date": { "year": 1850, "month": 1, "day": 1 },
  "game_state": "WORLD_MAP",
  "active_corp_id": "single",
  "active_factory_id": "",
  "tick_count": 0,
  "rng_seed": 0,

  "shared": {
    "money": 98500,
    "total_earned": 0,
    "total_spent": 1500,
    "total_maintenance_paid": 0,
    "last_maintenance_cost": 0,
    "disabled_facilities": [],

    "world_tiles": {
      "next_facility_id": 2,
      "roads": {},
      "field_parents": {},
      "farmhouse_children": {}
    },

    "next_machine_id": 1,
    "next_connection_id": 1,
    "next_vehicle_id": 1,
    "next_contract_id": 1,

    "factory_connections": {
      "facility_1": []
    },

    "market": {
      "current_prices": { ... },
      "price_multipliers": { ... },
      "supply_pressure": { ... },
      "market_trends": { ... }
    },

    "research_shared": null
  },

  "corps": {
    "agri": {
      "facilities": {},
      "machines": {},
      "connections": {},
      "vehicles": {},
      "contracts": [],
      "research_internal": { "unlocked_techs": [], "current_tier": 1, "tier_deliveries": {} },
      "production": {
        "production_timers": {},
        "production_outputs": {},
        "machine_timers": {},
        "machine_inventories": {},
        "facility_stats": {},
        "farmhouse_crop_types": {},
        "field_production_targets": {}
      }
    },
    "industrial": {
      "facilities": {
        "facility_1": {
          "id": "facility_1",
          "corp_id": "industrial",
          "type": "brewery",
          "grid_pos": { "x": 22, "y": 23 },
          "size": { "x": 3, "y": 3 },
          "world_pos": { "x": -32, "y": 768 },
          "constructed": true,
          "construction_progress": 1,
          "production_active": true,
          "inventory": {},
          "created_date": { "year": 1850, "month": 1, "day": 1 }
        }
      },
      "machines": {},
      "connections": {},
      "vehicles": {},
      "contracts": [],
      "research_internal": { "unlocked_techs": [], "current_tier": 1, "tier_deliveries": {} },
      "production": {
        "production_timers": { "facility_1": 4.93 },
        "production_outputs": { "facility_1": {} },
        "machine_timers": {},
        "machine_inventories": {},
        "facility_stats": {},
        "farmhouse_crop_types": {},
        "field_production_targets": {}
      }
    },
    "logistics": {
      "facilities": {},
      "machines": {},
      "connections": {},
      "vehicles": {},
      "contracts": [],
      "research_internal": { "unlocked_techs": [], "current_tier": 1, "tier_deliveries": {} },
      "production": { /* all empty */ }
    },
    "business": {
      "facilities": {},
      "machines": {},
      "connections": {},
      "vehicles": {},
      "contracts": [ { "id": 1, "corp_id": "business", "product": "raw_spirit", "quantity": 29, ... } ],
      "research_internal": { "unlocked_techs": [], "current_tier": 1, "tier_deliveries": {} },
      "production": { /* all empty */ }
    }
  },

  "utilities": null,
  "events": null
}
```

**Single-tier research (step-2 reality):** the existing ResearchManager has one shared tier-pool across all unlocks. Step 2 must keep it round-trippable. Put the entire `unlocked_techs` / `current_tier` / `tier_deliveries` blob inside `corps.industrial.research_internal` (the default-corp for legacy saves) — *not* in `shared.research_shared`. Two-layer tech-tree refactor (step 4 of master ordering) is where nodes get partitioned across corps and a `shared` tier appears.

**Load-bearing flag:** anyone reading `corps.<corp>.research_internal.unlocked_techs` in step 2 must understand that **all four corps share one logical pool** until step-4 refactor. The other three corps' research_internal blocks are empty defaults in v3. This is intentional shape-now, partition-later.

---

## 2. Round-trip preservation guarantee

Every v1 field maps somewhere in v3. Exhaustive table:

| v1 location | v3 location | Notes |
|---|---|---|
| `version` | `version` (bumped to 3) | |
| `timestamp` | `wall_timestamp` | renamed (see 0.7) |
| `date` | `date` | unchanged |
| `game_state` | `game_state` | unchanged |
| `world.next_facility_id` | `shared.world_tiles.next_facility_id` | |
| `world.facilities.*` | `corps.<corp>.facilities.*` | rebucketed by corp_id or by `_facility_type_to_corp(type)` |
| `world.roads` | `shared.world_tiles.roads` | roads are CORP_SHARED, but the road grid itself is global state |
| `world.field_parents` | `shared.world_tiles.field_parents` | |
| `world.farmhouse_children` | `shared.world_tiles.farmhouse_children` | |
| `factories.next_machine_id` | `shared.next_machine_id` | global counter |
| `factories.interiors.<fid>.machines.*` | `corps.<corp>.machines.<id>` | rebucketed; `facility_id` field added so machines remember their parent |
| `factories.interiors.<fid>.connections` | `shared.factory_connections.<fid>` | machine-to-machine inside-factory wiring; no corp_id (scoped to parent facility) |
| `logistics.next_connection_id` / `next_route_id` | `shared.next_connection_id` | absorb both legacy keys |
| `logistics.next_vehicle_id` | `shared.next_vehicle_id` | |
| `logistics.connections` / `logistics.routes` | `corps.<corp>.connections.<id>` | absorb both; rebucketed by corp_id (defaults to CORP_LOGISTICS) |
| `logistics.connection_paths` / `logistics.route_paths` | `corps.<corp>.connections.<id>.path` | path moves *into* the connection dict (was a sibling structure; this de-duplicates the connection_id key) |
| `logistics.vehicles` | `corps.<corp>.vehicles.<id>` | rebucketed by vehicle.corp_id (defaults to CORP_LOGISTICS) |
| `economy.money` | `shared.money` | per 0.1 |
| `economy.total_earned` | `shared.total_earned` | |
| `economy.total_spent` | `shared.total_spent` | |
| `economy.total_maintenance_paid` | `shared.total_maintenance_paid` | |
| `economy.last_maintenance_cost` | `shared.last_maintenance_cost` | |
| `economy.disabled_facilities` | `shared.disabled_facilities` | |
| `production.production_timers` | `corps.<corp>.production.production_timers` | partitioned by parent facility's corp |
| `production.production_outputs` | `corps.<corp>.production.production_outputs` | partitioned by parent facility's corp |
| `production.machine_timers` | `corps.<corp>.production.machine_timers` | partitioned by parent facility's corp (machine_key starts with facility_id) |
| `production.machine_inventories` | `corps.<corp>.production.machine_inventories` | same |
| `production.facility_stats` | `corps.<corp>.production.facility_stats` | partitioned by facility's corp |
| `production.farmhouse_crop_types` | `corps.agri.production.farmhouse_crop_types` | always agri |
| `production.field_production_targets` | `corps.agri.production.field_production_targets` | always agri |
| `market.current_prices` | `shared.market.current_prices` | global market state |
| `market.price_multipliers` | `shared.market.price_multipliers` | |
| `market.supply_pressure` | `shared.market.supply_pressure` | |
| `market.market_trends` | `shared.market.market_trends` | |
| `market.active_contracts` | `corps.business.contracts` | contracts are Business-owned |
| `market.next_contract_id` | `shared.next_contract_id` | global counter |
| `research.unlocked_techs` | `corps.industrial.research_internal.unlocked_techs` | see §1 single-tier note |
| `research.current_tier` | `corps.industrial.research_internal.current_tier` | |
| `research.tier_deliveries` | `corps.industrial.research_internal.tier_deliveries` | |

**Anything missing from this table is a regression.** If the implementer finds a v1 key not listed, stop and flag it before shipping.

---

## 3. `_facility_type_to_corp()` mapping (canonical)

Every facility type in `data/facilities.json` must appear. Bucketed per the technical doc §3.4 and the skill (lines 77–86):

```gdscript
const FACILITY_TYPE_TO_CORP: Dictionary = {
    # Agricultural
    "farmhouse":          "agri",
    "barley_field":       "agri",
    "wheat_field":        "agri",
    "corn_field":         "agri",
    "hop_farm":           "agri",
    "vineyard":           "agri",
    "water_source":       "agri",

    # Industrial
    "grain_mill":         "industrial",
    "industrial_mill":    "industrial",
    "brewery":            "industrial",
    "lager_brewery":      "industrial",
    "distillery":         "industrial",
    "whiskey_distillery": "industrial",
    "vodka_distillery":   "industrial",
    "winery":             "industrial",
    "aging_cellar":       "industrial",
    "barrel_house":       "industrial",
    "packaging_plant":    "industrial",
    "bottling_facility":  "industrial",

    # Logistics
    "storage_warehouse":  "logistics",
    "distribution_depot": "logistics",
    "rail_depot":         "logistics",

    # Business
    "tavern":             "business",
    "trade_office":       "business",
}

func _facility_type_to_corp(facility_type: String) -> String:
    if FACILITY_TYPE_TO_CORP.has(facility_type):
        return FACILITY_TYPE_TO_CORP[facility_type]
    push_warning("Unknown facility_type during migration: %s — defaulting to industrial" % facility_type)
    return GameManager.CORP_INDUSTRIAL
```

**Verified against `data/facilities.json`** at the time of writing (24 entries, all listed above). When a new facility type lands later, the implementer must update this table **in the same commit** that adds the JSON entry. Add a TODO in the data-loader to catch this drift.

### 3.1 Machine type to corp — derive from parent facility, not type

Machines have no inherent corp; they inherit from the facility they live in. In migration, for every machine the lookup is:

```
machine.corp_id = (machine.corp_id if present)
                  else (parent_facility.corp_id if present)
                  else _facility_type_to_corp(parent_facility.type)
```

No `_machine_type_to_corp()` table needed.

If a machine ever exists without a discoverable parent facility (orphan in legacy save — shouldn't happen, but defensive): push_warning, default `industrial`.

---

## 4. Migration algorithm (pseudocode, near-actual GDScript)

```gdscript
# core/save_manager.gd

const CURRENT_SAVE_VERSION = 3   # was 1

func _apply_save_data(data: Dictionary) -> bool:
    var version: int = int(data.get("version", 1))

    if version > CURRENT_SAVE_VERSION:
        push_error("Save version %d is newer than supported %d" % [version, CURRENT_SAVE_VERSION])
        return false

    if version < CURRENT_SAVE_VERSION:
        data = _migrate_to_v3(data, version)
        if data.is_empty():
            return false  # migration failure already logged

    return _apply_v3_data(data)


func _migrate_to_v3(data: Dictionary, from_version: int) -> Dictionary:
    """Forward-only migration from any v1 shape (pre-step-0.5, post-step-0.5, post-step-1)
    to v3. Builds the v3 dict entirely in memory; returns {} on failure."""
    print("Migrating save from v%d to v3..." % from_version)

    var migrated := _v3_empty_template()

    # ---- Top level ----
    migrated.wall_timestamp = float(data.get("timestamp", Time.get_unix_time_from_system()))
    migrated.date = data.get("date", { "year": 1850, "month": 1, "day": 1 })
    migrated.game_state = data.get("game_state", "WORLD_MAP")
    migrated.active_corp_id = GameManager.CORP_SINGLE
    migrated.active_factory_id = ""

    # ---- Shared: economy ----
    var econ: Dictionary = data.get("economy", {})
    migrated.shared.money = int(econ.get("money", 5000))
    migrated.shared.total_earned = int(econ.get("total_earned", 0))
    migrated.shared.total_spent = int(econ.get("total_spent", 0))
    migrated.shared.total_maintenance_paid = int(econ.get("total_maintenance_paid", 0))
    migrated.shared.last_maintenance_cost = int(econ.get("last_maintenance_cost", 0))
    migrated.shared.disabled_facilities = (econ.get("disabled_facilities", []) as Array).duplicate()

    # ---- Shared: world tiles ----
    var world: Dictionary = data.get("world", {})
    migrated.shared.world_tiles.next_facility_id = int(world.get("next_facility_id", 1))
    migrated.shared.world_tiles.roads = (world.get("roads", {}) as Dictionary).duplicate()
    migrated.shared.world_tiles.field_parents = (world.get("field_parents", {}) as Dictionary).duplicate()
    var fc_legacy: Dictionary = world.get("farmhouse_children", {})
    for fh_id in fc_legacy:
        migrated.shared.world_tiles.farmhouse_children[fh_id] = (fc_legacy[fh_id] as Array).duplicate()

    # ---- Shared: counters ----
    var factories_root: Dictionary = data.get("factories", {})
    var logistics_root: Dictionary = data.get("logistics", {})
    var market_root: Dictionary = data.get("market", {})

    migrated.shared.next_machine_id = int(factories_root.get("next_machine_id", 1))
    # Absorb both legacy and canonical connection-id-counter names.
    migrated.shared.next_connection_id = int(logistics_root.get("next_connection_id",
                                              logistics_root.get("next_route_id", 1)))
    migrated.shared.next_vehicle_id = int(logistics_root.get("next_vehicle_id", 1))
    migrated.shared.next_contract_id = int(market_root.get("next_contract_id", 1))

    # ---- Shared: market (global state, no contracts) ----
    migrated.shared.market.current_prices = (market_root.get("current_prices", {}) as Dictionary).duplicate()
    migrated.shared.market.price_multipliers = (market_root.get("price_multipliers", {}) as Dictionary).duplicate()
    migrated.shared.market.supply_pressure = (market_root.get("supply_pressure", {}) as Dictionary).duplicate()
    migrated.shared.market.market_trends = (market_root.get("market_trends", {}) as Dictionary).duplicate()

    # ---- Facilities: rebucket into corps ----
    # Walk legacy world.facilities; resolve corp_id; place in corps.<corp>.facilities.
    var facility_to_corp := {}  # facility_id -> corp_id; lookup table for downstream phases
    var legacy_facilities: Dictionary = world.get("facilities", {})
    for fid in legacy_facilities:
        var fac: Dictionary = legacy_facilities[fid]
        var corp_id: String = _resolve_facility_corp(fac)
        # Force the on-disk corp_id to match what we resolved (overwriting any stale CORP_SINGLE).
        fac["corp_id"] = corp_id
        migrated.corps[corp_id].facilities[fid] = fac
        facility_to_corp[fid] = corp_id

    # ---- Machines: rebucket via parent facility ----
    # Also: factory_connections (machine-to-machine inside-factory wiring) → shared.factory_connections.
    var legacy_interiors: Dictionary = factories_root.get("interiors", {})
    for fid in legacy_interiors:
        var interior: Dictionary = legacy_interiors[fid]
        var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)

        var legacy_machines: Dictionary = interior.get("machines", {})
        for mid in legacy_machines:
            var machine: Dictionary = legacy_machines[mid]
            # Inherit corp_id from parent if not present; force-correct if stale.
            machine["corp_id"] = corp_id
            # Add facility_id so the machine remembers its parent (was implicit via the nesting).
            machine["facility_id"] = fid
            migrated.corps[corp_id].machines[mid] = machine

        # Factory-internal connections live under shared (scoped to facility, no corp_id).
        migrated.shared.factory_connections[fid] = (interior.get("connections", []) as Array).duplicate()

    # ---- Connections & paths: rebucket ----
    # Tolerate both legacy `routes` / `route_paths` keys and canonical `connections` / `connection_paths`.
    var legacy_connections: Dictionary = logistics_root.get("connections", logistics_root.get("routes", {}))
    var legacy_paths: Dictionary = logistics_root.get("connection_paths", logistics_root.get("route_paths", {}))
    var connection_to_corp := {}
    for cid in legacy_connections:
        var conn: Dictionary = legacy_connections[cid]
        var corp_id: String = conn.get("corp_id", GameManager.CORP_LOGISTICS)
        # Move path into the connection dict.
        if legacy_paths.has(cid):
            conn["path"] = (legacy_paths[cid] as Array).duplicate()
        else:
            conn["path"] = []
        conn["corp_id"] = corp_id
        migrated.corps[corp_id].connections[cid] = conn
        connection_to_corp[cid] = corp_id

    # ---- Vehicles: rebucket via parent connection (fallback: own corp_id) ----
    var legacy_vehicles: Dictionary = logistics_root.get("vehicles", {})
    for vid in legacy_vehicles:
        var veh: Dictionary = legacy_vehicles[vid]
        # Tolerate legacy `route_id` field.
        if veh.has("route_id") and not veh.has("connection_id"):
            veh["connection_id"] = veh["route_id"]
            veh.erase("route_id")
        var cid: String = veh.get("connection_id", "")
        var corp_id: String = veh.get("corp_id",
                                connection_to_corp.get(cid, GameManager.CORP_LOGISTICS))
        veh["corp_id"] = corp_id
        migrated.corps[corp_id].vehicles[vid] = veh

    # ---- Contracts: rebucket (always business) ----
    var legacy_contracts: Array = market_root.get("active_contracts", [])
    for contract in legacy_contracts:
        # Force-correct corp_id (step-1 already wrote "business" for new contracts).
        contract["corp_id"] = GameManager.CORP_BUSINESS
        migrated.corps.business.contracts.append(contract)

    # ---- Production state: rebucket by owning facility ----
    var prod_root: Dictionary = data.get("production", {})
    _rebucket_production(prod_root, migrated.corps, facility_to_corp)

    # ---- Research: place entire blob in corps.industrial.research_internal ----
    # Single-tier in step 2; two-layer refactor lands later.
    var research_root: Dictionary = data.get("research", {})
    if not research_root.is_empty():
        var ri: Dictionary = migrated.corps.industrial.research_internal
        ri.unlocked_techs = (research_root.get("unlocked_techs", []) as Array).duplicate()
        ri.current_tier = int(research_root.get("current_tier", 1))
        ri.tier_deliveries = (research_root.get("tier_deliveries", {}) as Dictionary).duplicate()

    print("Migration complete. Facilities by corp: agri=%d industrial=%d logistics=%d business=%d" % [
        migrated.corps.agri.facilities.size(),
        migrated.corps.industrial.facilities.size(),
        migrated.corps.logistics.facilities.size(),
        migrated.corps.business.facilities.size(),
    ])
    return migrated


func _resolve_facility_corp(facility: Dictionary) -> String:
    """Three-fallback chain: explicit corp_id (post-step-1) → type lookup (pre-step-1).
    The legacy CORP_SINGLE placeholder is treated as 'unset' and rebucketed by type."""
    var existing: String = facility.get("corp_id", "")
    if existing != "" and existing != GameManager.CORP_SINGLE and existing in GameManager.VALID_CORP_IDS:
        return existing
    return _facility_type_to_corp(facility.get("type", ""))


func _rebucket_production(prod: Dictionary, corps: Dictionary, facility_to_corp: Dictionary) -> void:
    """Distribute production state across per-corp partitions by walking owning facility."""

    # Helpers: keyed-by-facility-id sections.
    var by_facility_keys := ["production_timers", "production_outputs", "facility_stats"]
    for key in by_facility_keys:
        var src: Dictionary = prod.get(key, {})
        for fid in src:
            var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)
            corps[corp_id].production[key][fid] = src[fid]

    # Keyed-by-machine-key (format: "<facility_id>|<machine_id>" — verify in production_manager.gd).
    var by_machine_keys := ["machine_timers", "machine_inventories"]
    for key in by_machine_keys:
        var src: Dictionary = prod.get(key, {})
        for mk in src:
            var facility_id := _facility_id_from_machine_key(mk)
            var corp_id: String = facility_to_corp.get(facility_id, GameManager.CORP_INDUSTRIAL)
            corps[corp_id].production[key][mk] = src[mk]

    # Always-agri sections.
    corps.agri.production.farmhouse_crop_types = (prod.get("farmhouse_crop_types", {}) as Dictionary).duplicate()
    corps.agri.production.field_production_targets = (prod.get("field_production_targets", {}) as Dictionary).duplicate()


func _facility_id_from_machine_key(machine_key: String) -> String:
    """Machine keys are 'facility_id|machine_id'. If the format is different,
    fall back to empty string (forces CORP_INDUSTRIAL default)."""
    var parts := machine_key.split("|", true, 1)
    if parts.size() >= 1:
        return parts[0]
    return ""
```

**Implementer verification before coding:** open `systems/production_manager.gd` and confirm `machine_timers` / `machine_inventories` keys are `"<facility_id>|<machine_id>"`. If the separator is different (e.g., `:` or `_`), update `_facility_id_from_machine_key`. If keys are *not* facility-id-prefixed at all, this whole rebucket path needs reshaping — flag back to the architect before proceeding.

---

## 5. `_v3_empty_template()` — the canonical fresh-save shape

```gdscript
func _v3_empty_template() -> Dictionary:
    """Return a fully populated v3 dict with empty per-corp partitions.
    Used by both migration and fresh-save gathering."""
    return {
        "version": 3,
        "wall_timestamp": Time.get_unix_time_from_system(),
        "date": { "year": 1850, "month": 1, "day": 1 },
        "game_state": "WORLD_MAP",
        "active_corp_id": GameManager.CORP_SINGLE,
        "active_factory_id": "",
        "tick_count": 0,
        "rng_seed": 0,

        "shared": {
            "money": 0,
            "total_earned": 0,
            "total_spent": 0,
            "total_maintenance_paid": 0,
            "last_maintenance_cost": 0,
            "disabled_facilities": [],

            "world_tiles": {
                "next_facility_id": 1,
                "roads": {},
                "field_parents": {},
                "farmhouse_children": {}
            },

            "next_machine_id": 1,
            "next_connection_id": 1,
            "next_vehicle_id": 1,
            "next_contract_id": 1,

            "factory_connections": {},

            "market": {
                "current_prices": {},
                "price_multipliers": {},
                "supply_pressure": {},
                "market_trends": {}
            },

            "research_shared": null
        },

        "corps": _empty_corps_block(),

        "utilities": null,
        "events": null
    }


func _empty_corps_block() -> Dictionary:
    var corps := {}
    for corp_id in [GameManager.CORP_AGRI, GameManager.CORP_INDUSTRIAL, GameManager.CORP_LOGISTICS, GameManager.CORP_BUSINESS]:
        corps[corp_id] = {
            "facilities": {},
            "machines": {},
            "connections": {},
            "vehicles": {},
            "contracts": [],
            "research_internal": {
                "unlocked_techs": [],
                "current_tier": 1,
                "tier_deliveries": {}
            },
            "production": {
                "production_timers": {},
                "production_outputs": {},
                "machine_timers": {},
                "machine_inventories": {},
                "facility_stats": {},
                "farmhouse_crop_types": {},
                "field_production_targets": {}
            }
        }
    return corps
```

---

## 6. Micro-steps (single PR)

### Micro-step 1 — Bump version constant + add migration entry point

**File:** `core/save_manager.gd:16`

```gdscript
const CURRENT_SAVE_VERSION = 3   # was 1
```

Rewrite `_apply_save_data` per §4 to dispatch to `_migrate_to_v3` then `_apply_v3_data`.

**Done when:** version constant flipped; `_apply_save_data` is a dispatch shell, not the worker.

**Depends on:** nothing.

### Micro-step 2 — Add the migration function + helpers

**File:** `core/save_manager.gd`

Add `_v3_empty_template`, `_empty_corps_block`, `_migrate_to_v3`, `_resolve_facility_corp`, `_facility_type_to_corp`, `FACILITY_TYPE_TO_CORP` constant, `_rebucket_production`, `_facility_id_from_machine_key` per §3–§5.

**Done when:** unit-shaped — running migration in isolation against `ghibbon.save` content produces a v3 dict matching the §1 schema.

**Depends on:** micro-step 1.

### Micro-step 3 — Rewrite `_gather_save_data` for v3 writes

**File:** `core/save_manager.gd:202–218`

Rebuild from the v3 template. For each entity, walk its source manager and slot it into the right per-corp partition by `corp_id`. **Writes never use legacy keys.** Writes never write the `CORP_SINGLE` default fallback — if an entity dict has `corp_id == ""` or `corp_id not in VALID_CORP_IDS`, `push_error()` and fall back to `CORP_SINGLE` (so the save isn't lost, but the bug is loud).

Roughly:

```gdscript
func _gather_save_data() -> Dictionary:
    var data := _v3_empty_template()
    data.wall_timestamp = Time.get_unix_time_from_system()
    data.date = GameManager.current_date
    data.game_state = GameManager.GameState.keys()[GameManager.current_state]
    data.active_corp_id = GameManager.active_corp_id
    data.active_factory_id = GameManager.active_factory_id

    _gather_shared_data(data.shared)
    _gather_corp_partitions(data.corps)
    return data
```

`_gather_shared_data(out)` populates economy, world_tiles, counters, factory_connections, market (no contracts).

`_gather_corp_partitions(out)` walks `WorldManager.facilities`, `FactoryManager.factory_interiors[*].machines`, `LogisticsManager.connections`, `LogisticsManager.vehicles`, `MarketManager.active_contracts`, `ProductionManager.*` and slots each entity into `out[entity.corp_id]`. Production state is dispatched via the same helper as migration (different input shape, same logic — refactor for shared code).

**Critical:** the helper that resolves an entity's destination corp must `push_error()` and fall back to `CORP_SINGLE` on an invalid `corp_id`, not silently inject. Per the user constraint: "if one slips through with empty corp_id, write push_error() and use CORP_SINGLE rather than silently injecting a corp."

But `corps.single` does not exist as a partition (we have agri/industrial/logistics/business only). So **define a sentinel error-bucket only on write-side detection**:

```gdscript
func _resolve_entity_corp_for_write(entity_dict: Dictionary, default: String) -> String:
    var cid: String = entity_dict.get("corp_id", "")
    if cid in [GameManager.CORP_AGRI, GameManager.CORP_INDUSTRIAL, GameManager.CORP_LOGISTICS, GameManager.CORP_BUSINESS]:
        return cid
    push_error("Entity has invalid corp_id %s for save; routing to %s and logging" % [cid, default])
    return default
```

The default for facilities is `CORP_INDUSTRIAL` (matches the migration unknown-fallback). For connections/vehicles: `CORP_LOGISTICS`. For contracts: `CORP_BUSINESS`. CORP_SHARED roads aren't entities and go to `shared.world_tiles.roads` directly.

**Done when:** a fresh game (place brewery, save) writes a v3 file matching §1 schema.

**Depends on:** micro-step 2.

### Micro-step 4 — Rewrite `_apply_v3_data` for v3 reads

**File:** `core/save_manager.gd`

Replace the existing `_restore_*_data` chain with a v3-aware walker. For each corp partition, restore the entity dicts into their managers (without re-emitting EventBus signals during the restore loop, then re-emit at the end — current restore code already does this pattern via emit-during-loop; verify the order is identical post-rewrite).

Critical: when restoring facilities, restore from **all four corp partitions** into the single `WorldManager.facilities` dictionary (the manager is corp-blind at storage; corp_id is a field on the entity). Same for machines, connections, vehicles, contracts.

```gdscript
func _apply_v3_data(data: Dictionary) -> bool:
    print("Applying v3 save data...")
    _clear_game_state()

    GameManager.current_date = data.date
    GameManager.active_corp_id = data.get("active_corp_id", GameManager.CORP_SINGLE)
    GameManager.active_factory_id = data.get("active_factory_id", "")

    _restore_shared(data.shared)
    _restore_corp_partitions(data.corps)
    return true
```

`_restore_shared` populates EconomyManager, WorldManager road grid + farmhouse links, all the `_next_*_id` counters, and global market state.

`_restore_corp_partitions` iterates the four corp blocks and pours their entity dicts back into the corp-blind manager storage, emitting EventBus signals where the current code emits them (facility_placed, connection_created, vehicle_spawned, road_placed).

Production state restore walks each `corps.<corp>.production` and merges keys back into the flat ProductionManager dicts (corp partition is purely a save-shape; the manager itself stays corp-blind in step 2; per-corp ProductionManager refactor is later).

**Done when:** loading a v3 file produces identical in-memory state to a v1 file from the same game (verified by smoke test §8).

**Depends on:** micro-step 3.

### Micro-step 5 — Drop the step-0.5 tolerant reads

**File:** `core/save_manager.gd` lines 611, 615, 624, 654

The four `# TODO(step-2 v3 bump)` lines from step 0.5. With v3 reads going through `_migrate_to_v3`, the legacy-key tolerance lives there (migration is the only place that sees pre-v3 shapes). The restore path for v3 reads only canonical keys.

After this micro-step:

- `rg 'TODO\(step-2 v3 bump\)' core/save_manager.gd` → zero hits.
- The phrases `"routes"`, `"route_paths"`, `"next_route_id"`, `"route_id"` appear *only* inside `_migrate_to_v3`. Outside the migration function: zero hits.

**Done when:** the grep checks pass.

**Depends on:** micro-step 4 (the v3 reader is in place to take over).

### Micro-step 6 — Backup-before-overwrite on first migration

**File:** `core/save_manager.gd`

When a save is loaded with `version < 3`, after a successful migration but before the *next* save overwrites the file, write a one-time backup. Two implementation options:

**Option A (recommended):** back up at *load time, on a successful migration*, before doing anything else.

```gdscript
func load_game(slot_name: String) -> bool:
    var save_data := _read_save_file(slot_name)
    if save_data.is_empty():
        push_error("Failed to load save file: %s" % slot_name)
        return false

    var save_version: int = int(save_data.get("version", 1))
    if save_version < CURRENT_SAVE_VERSION:
        if not _backup_legacy_save(slot_name, save_version):
            push_warning("Could not back up legacy save before migration; proceeding anyway")

    var success := _apply_save_data(save_data)
    # ... rest unchanged
```

```gdscript
func _backup_legacy_save(slot_name: String, version: int) -> bool:
    var src := _get_save_path(slot_name)
    var dst := SAVE_DIR + slot_name + ".save.v%d.bak" % version
    if FileAccess.file_exists(dst):
        return true   # already backed up on a previous load; don't overwrite the bak with the same data
    var dir := DirAccess.open(SAVE_DIR)
    if dir == null:
        return false
    var err := dir.copy(src, dst)
    if err == OK:
        print("Backed up legacy save: %s -> %s" % [src, dst])
        return true
    push_error("Backup failed: error %d copying %s to %s" % [err, src, dst])
    return false
```

**Backup retention:** keep `.v1.bak` files indefinitely for now. They're small (legacy saves are tiny). A future "save management" UI pass can offer a "delete legacy backups" toggle. Do not auto-prune.

**Don't list `.v1.bak` files in `list_saves()`:** `SAVE_EXTENSION = ".save"` already filters by ends_with, but a slot named `foo.save.v1.bak` ends with `.bak` not `.save`, so it's already excluded. Verify; do not add a filter for the wrong reason.

**Done when:** loading `ghibbon.save` creates `ghibbon.save.v1.bak` in the saves directory.

**Depends on:** micro-step 1 (version constant set).

### Micro-step 7 — Atomic write semantics for v3 saves

**File:** `core/save_manager.gd:_write_save_file`

Migration builds the v3 dict in memory before any disk write happens — that already covers "migration partial-success leaves the legacy save intact" (we never open the legacy file for writing during migration; the migrated dict goes through `save_game` → `_write_save_file` on the *next* save, not during load).

Belt-and-braces upgrade: write to `<path>.tmp`, then rename. If the rename fails, the previous `.save` is intact.

```gdscript
func _write_save_file(slot_name: String, data: Dictionary) -> bool:
    var file_path := _get_save_path(slot_name)
    var tmp_path := file_path + ".tmp"
    var file := FileAccess.open(tmp_path, FileAccess.WRITE)
    if not file:
        push_error("Failed to open temp save file for writing: %s" % tmp_path)
        return false
    file.store_string(JSON.stringify(data, "\t"))
    file.close()

    var dir := DirAccess.open(SAVE_DIR)
    if dir == null:
        push_error("Cannot open save dir for rename")
        return false
    if FileAccess.file_exists(file_path):
        dir.remove(file_path)
    var err := dir.rename(tmp_path, file_path)
    if err != OK:
        push_error("Failed to rename %s to %s (err %d)" % [tmp_path, file_path, err])
        return false
    return true
```

**Done when:** save still works; if you `kill -9` the editor between writing and renaming (don't actually do this; conceptually), the previous save is untouched.

**Depends on:** none — purely defensive.

### Micro-step 8 — Smoke test (§8)

---

## 7. Failure modes and mitigations

| Failure | Mitigation |
|---|---|
| Legacy facility `type` not in `FACILITY_TYPE_TO_CORP` | `push_warning`, default to industrial. **Loud, not silent.** |
| Connection has `corp_id == CORP_SINGLE` (step-1 default fallback shouldn't have produced this for connections — step-1 used CORP_LOGISTICS as the default — but defensive) | Migration treats CORP_SINGLE as "unresolved" and rebuckets by entity-type default: facilities by type-lookup, connections to CORP_LOGISTICS, vehicles inherit from connection. |
| Machine has no parent facility in legacy save (orphan) | push_warning, route to CORP_INDUSTRIAL, keep the machine (`migrations never lose data` rule). |
| Migration crashes mid-way | Migration builds the v3 dict in memory; the legacy save file is never opened for writing during migration. On exception, the load fails, the legacy file is still on disk, the user can re-load. |
| Migration succeeds but next save crashes | Atomic write via `.tmp` rename (§6 micro-step 7). The previous file is still the legacy v1, and the `.v1.bak` is already in place from the load-time backup. |
| Two slots use the same `<slot>.save.v1.bak` name | Slot names are unique per save file already; `<slot>.save.v1.bak` is also unique. If a user names a save `foo.save.v1.bak` (literal): collision. Don't worry about it; `_get_save_path` slot naming uses the slot string verbatim, and any user naming a save with a `.` is in territory we already don't validate. |
| Save migration is non-idempotent — load v1, save v3, load v3, save again | Idempotent. `_migrate_to_v3` only runs when `version < 3`. Once a save is v3, subsequent loads route to `_apply_v3_data` directly. |
| `machine_key` separator in ProductionManager isn't `|` | **Verify before coding micro-step 2.** If different, update `_facility_id_from_machine_key`. If keys aren't facility-prefixed: stop, flag, redesign. |
| `current_date` in legacy save missing some fields | `_v3_empty_template()` populates defaults; `migrated.date = data.get("date", default)` is a shallow merge; if a legacy save has `{year: 1850}` only, the migration produces `{year: 1850}` and downstream code reading `current_date.day` crashes. **Defend at migration:** merge with template defaults. |

### 7.1 Specific defense for the `date` merge

```gdscript
func _merge_with_default(value, default: Dictionary) -> Dictionary:
    var result: Dictionary = default.duplicate()
    if value is Dictionary:
        for k in value:
            result[k] = value[k]
    return result

# in _migrate_to_v3:
migrated.date = _merge_with_default(data.get("date"), { "year": 1850, "month": 1, "day": 1 })
```

---

## 8. Smoke-test sequence

Run in Godot before declaring step 2 done. Steps 1–6 are the user's pre-existing fixture flow; 7–9 verify the new contract.

1. Backup the legacy fixtures externally (copy `quicksave.save` and `ghibbon.save` to a safe location outside `user://saves/` — not for the engine, for you).
2. Launch the game with the v3 code. Auto-load does nothing; the menu shows the two legacy saves.
3. Load `ghibbon.save` (pre-step-0.5, no `corp_id`, legacy `routes` key). Console shows `Migrating save from v1 to v3...` and `Backed up legacy save: ... -> ghibbon.save.v1.bak`. Facility list rebuilds; grain_mill and brewery both appear at the right grid positions.
4. Check `user://saves/`: `ghibbon.save.v1.bak` exists; `ghibbon.save` is *not yet* overwritten (load doesn't write).
5. F5 quick save → confirm `quicksave.save` is overwritten with the v3 shape. Open it in a text editor; grep for `"version": 3` and the per-corp partitions.
6. Load `quicksave.save` (the freshly written v3) — confirm money, facilities, production timers, contracts all restored.
7. Open the v3 save in a text editor; confirm:
   - `corps.industrial.facilities` contains the brewery (`facility_1`) with `corp_id: "industrial"` (rebucketed from the legacy `corp_id: "single"`).
   - `corps.business.contracts` has the raw_spirit contract.
   - `shared.money` is 98500.
   - `shared.world_tiles.next_facility_id` is 2.
   - `utilities` and `events` are `null`.
8. With the v3 save loaded: place a Barley Field (CORP_SINGLE since hot-seat switcher isn't here yet — but it will go into `corps.industrial.facilities` via the write-side `_resolve_entity_corp_for_write` fallback, with a `push_error` in the console). **Better: console-run `GameManager.set_active_corp("agri")` first, then place the barley field — it should land in `corps.agri.facilities` cleanly.**
9. F5 save again. Confirm the barley field is in `corps.agri.facilities`, the brewery is still in `corps.industrial.facilities`. **This is the proof per-corp partitioning is live and field-driven, not type-hardcoded.**

**Done when:** all 9 checks pass and the console has no unexpected errors (the deliberate push_error from step 8 in the CORP_SINGLE write fallback path is expected and documented).

---

## 9. Files touched (final inventory)

```
core/save_manager.gd       (~200 lines net, ~+250 -50)
```

That is the only file. Migration is internal to SaveManager. No new public API.

**Files explicitly NOT touched:**

- `core/game_manager.gd` — no API changes; `active_factory_id` and `active_corp_id` fields already exist.
- `systems/*` — production/world/logistics/factory/market managers stay corp-blind in step 2; per-corp refactor of each is later.
- `data/*` — no JSON changes; the `FACILITY_TYPE_TO_CORP` table lives in code.
- `.claude/skills/drinkustry-save-migration/SKILL.md` — needs a follow-up update (see §10) but **not in this commit** (keeps the diff focused).

---

## 10. Follow-ups to land in separate commits

These are intentionally deferred and tracked here so they don't get lost.

1. **Update `drinkustry-save-migration/SKILL.md`** — change the per-corp partition example (lines 105–116) to use `connections` instead of `routes`, drop the standalone `money` field per 0.1 decision (the skill should show `shared.money` for step 2; the example currently shows per-corp money which is post-step-2). One-line follow-up after this lands.
2. **EconomyManager per-corp wallet refactor (v3 → v4 schema bump)** — when the action pipe (step 3) is wired and each `submit_action` carries a corp_id, split `shared.money` into `corps.<corp>.money`. This is its own commit with its own forward migration.
3. **Two-layer tech tree refactor (step 4 of master ordering)** — when research nodes get `tier: "corp_internal" | "shared"`, the migration moves shared-tier unlocks into `shared.research_shared` (currently `null`). v3 → v5 schema bump.
4. **Production-state per-corp refactor** — ProductionManager itself becomes corp-aware (queryable per corp), at which point its internal storage matches the save shape. Until then, the v3 save shape partitions on serialize/deserialize but the manager keeps flat dicts.
5. **`data/facilities.json` `default_corp` field** — same defer reason as step 1 plan §micro-step 7. Per-corp build menus consume it; lands with the build-menu refactor.

---

## 11. Open architectural questions surfaced

### A3 (save merging across hot-seat sessions): not blocked, schema supports the future case

The technical doc deferred A3. Step 2 doesn't need merging — one save file, all four corps, swap `active_corp_id` to play another corp. The v3 partition shape *does* support a future "import this corp's state from another save" feature: read the source save's `corps.<corp_id>` block, write it into the target save's same block, fix up any cross-references (vehicle.connection_id pointing at a connection that doesn't exist in the target — that case isn't possible if entire corp blocks are atomic and corps' connections don't span). **Schema lets it; UX/UI is the deferred work.** No change needed in step 2.

### A6 (determinism in migration): not required

Migration is deterministic by construction — dictionary iteration order is insertion order in GDScript, and we iterate legacy dicts to build a new dict; same input produces same output on the same machine. No `randf()` is used. `tick_count` and `rng_seed` are written as 0; their semantics solidify in the determinism-refactor commit, which is its own version bump.

The `rng_seed = 0` choice is intentional. Once MarketManager's `randf()` calls route through a seeded RNG (Phase 8 entry checklist item), the seed needs a real source. Step 2 doesn't drive that work, so the field is reserved but inert.

### New: should `active_factory_id` be in the save?

It is now. Reason: smoke-test step 8 — if the player saves while inside a factory interior, reloads, they should land back in the interior. Current code already supports state-preservation across save/load (the `GameState` enum is saved); the factory id was implicitly preserved by being absent from clearing logic. Making it explicit in the save shape is +2 lines and prevents future bugs. Trivial decision; documented for the record.

---

## 12. What I'm leaving for the implementer to call out

If any of these surface during implementation, **stop and flag back to the architect:**

- ProductionManager `machine_key` separator is not `|`.
- Any v1 field not in the §2 table.
- A legacy save with a `corp_id` value not in `VALID_CORP_IDS` (something other than agri/industrial/logistics/business/shared/single).
- An entity with `corp_id == "shared"` that lands somewhere unexpected (shared-owned roads are handled via `shared.world_tiles.roads`, not via a corp partition; shared-owned facilities or machines don't exist in v1 but if one appears in a legacy save, the rebucket has no destination — flag and decide).
- `FactoryManager._initialize_interior_grid` signature or contract changed since the step-1 plan referenced it (`save_manager.gd:567`).
