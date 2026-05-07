---
name: drinkustry-save-migration
description: Use when modifying the save schema, bumping the version number, writing a migration from an older save format, or working with `core/save_manager.gd`. Triggers on save-format changes, schema bumps, save corruption issues, or any work where save/load compatibility matters. Especially relevant for Phase 8 (v3 schema with per-corp partitions).
---

# Drinkustry — save schema discipline

## Hard rule: bump the version, write a migration

The pre-pivot codebase silently absorbed schema drift via getter aliases (e.g., `LogisticsManager.routes` aliasing `connections`, `_restore_logistics_data()` reading both old and new keys against the same `version: 1` schema). **This is forbidden from v3 onward.** Bump the version, write a migration, remove the aliases.

Why: alias-creep is exactly how MP determinism breaks. Two clients running with different alias-handling order produce diverging state. Version-gated migrations make state shape uniform across clients.

## The schema versions

- **v1** — pre-pivot single-player (legacy)
- **v2** — pre-pivot single-player with route→connection rename absorbed silently (still tagged v1 in saves; effectively a hidden v2)
- **v3** — Drinkustry per-corp partitions (Phase 8)

Future versions:
- **v4** — utility networks (water/power/sewage) added (Phase 11)
- **v5** — narrative event state (Phase 11)
- **v6** — networking-required determinism state (Phase 12)

## v3 schema shape

```json
{
  "version": 3,
  "tick_count": 12345,
  "rng_seed": 0xDEADBEEF,
  "corps": {
    "agri": { "money": 50000, "facilities": [...], "research": {...}, ... },
    "industrial": { ... },
    "logistics": { ... },
    "business": { ... }
  },
  "shared": {
    "research_shared": {...},
    "world_tiles": [...],
    "events_log": [...]
  },
  "utilities": null,
  "events": null
}
```

`utilities: null` and `events: null` are placeholders for v4/v5 systems — present so the schema shape is stable across the v3 generation, even though those fields aren't read yet.

## Migration pattern

```gdscript
func load_state(data: Dictionary) -> void:
    var version: int = data.get("version", 1)

    if version < 3:
        data = _migrate_to_v3(data, version)

    if data.version != 3:
        push_error("Unknown save version: %s" % data.version)
        return

    _load_v3(data)

func _migrate_to_v3(data: Dictionary, from_version: int) -> Dictionary:
    # v1/v2 → v3: wrap legacy single-player state under corps.single,
    # then re-bucket facilities into the four corps based on facility_type.
    var migrated := {
        "version": 3,
        "tick_count": data.get("tick_count", 0),
        "rng_seed": _stable_seed_from_legacy(data),
        "corps": _rebucket_legacy_facilities(data),
        "shared": _extract_shared_state(data),
        "utilities": null,
        "events": null,
    }
    return migrated

func _rebucket_legacy_facilities(data: Dictionary) -> Dictionary:
    var corps := { "agri": {...}, "industrial": {...}, "logistics": {...}, "business": {...} }
    for facility in data.get("facilities", []):
        var corp_id := _facility_type_to_corp(facility.facility_type)
        corps[corp_id].facilities.append(facility)
    return corps
```

## Migration rules

1. **Migrations are one-way.** v1 → v3 is supported; v3 → v1 is not. Saves auto-upgrade on load.
2. **Migrations never lose data.** If you can't bucket a legacy facility into a corp, log a warning and put it in `corps.industrial` as a default. Don't drop it.
3. **Migrations are deterministic.** Given the same v1 input, always produce the same v3 output. No `randf()`, no time-based logic, no dictionary-iteration-order dependence.
4. **Test migrations against real legacy saves** before shipping. Keep a few v1 sample saves in `tests/save_fixtures/` for regression testing.
5. **Once a save is migrated and re-saved, it's v3 forever.** The migration code stays in the codebase indefinitely (someone might reload an ancient v1 save).

## Schema design rules

- **JSON, not binary.** Debugging > size. Read access during dev is more valuable than file size.
- **Numbers are numbers, not strings.** `"money": 50000`, not `"money": "50000"`.
- **Vector2/Vector2i serialize as `[x, y]` arrays** or as `{ "x": ..., "y": ... }` — pick one and stay consistent (project uses arrays).
- **Don't serialize node refs.** Store entity ids; rebuild scene tree on load.
- **Reserve `corp_id: "shared"`** for utilities and shared research. Don't invent per-system shared markers.

## Per-corp partition layout

Each corp's partition has a uniform shape:
```json
{
  "money": 50000,
  "facilities": [...],
  "machines": [...],
  "routes": [...],
  "vehicles": [...],
  "research_internal": {...},
  "contracts": [...]
}
```

Empty lists/dicts when a corp doesn't own that entity type. Never omit the field — uniform shape simplifies migration and querying.

## Auto-save and slot management

- Auto-save every 5 minutes (already shipped).
- Quick save (F5) and quick load (F9) (already shipped).
- Multiple named slots (already shipped).
- Co-op session saves to one file with all four corps — no per-corp save files.

## When you bump the version

1. Bump the version constant in `SaveManager`
2. Write a migration from the previous version
3. Update the schema-shape doc in `design_docs/2026-05-07_technical_architecture.html` §5
4. Remove any deprecated alias getters (do this in the **same commit** as the version bump — don't let aliases linger across versions)
5. Add a sample save at the new version to `tests/save_fixtures/` for regression
