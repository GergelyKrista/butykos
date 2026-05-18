extends Node

## SaveManager - Save/load game state and player preferences
##
## Handles serialization of game state to disk and restoration.
## Uses JSON format for readability and easy debugging.

# ========================================
# CONSTANTS
# ========================================

const SAVE_DIR = "user://saves/"
const SAVE_EXTENSION = ".save"
const PREFERENCES_FILE = "user://preferences.cfg"

const CURRENT_SAVE_VERSION = 3

# V3 partition section name constants.
const SECTION_SHARED = "shared"
const SECTION_CORPS = "corps"

# Facility-type → corp mapping for legacy saves without corp_id.
# Cover every type listed in data/facilities.json (24 entries).
# If a new type is added to facilities.json, add it here in the same commit.
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

# ========================================
# STATE
# ========================================

var current_save_slot: String = ""
var auto_save_enabled: bool = true
var auto_save_interval: float = 300.0  # 5 minutes

var _auto_save_timer: float = 0.0

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("SaveManager initialized")
	_ensure_save_directory()
	load_preferences()


func _process(delta: float) -> void:
	if auto_save_enabled and GameManager.current_state == GameManager.GameState.WORLD_MAP:
		_auto_save_timer += delta
		if _auto_save_timer >= auto_save_interval:
			_auto_save_timer = 0.0
			auto_save()


# ========================================
# SAVE MANAGEMENT
# ========================================

func save_game(slot_name: String = "") -> bool:
	"""Save current game state to specified slot"""

	if slot_name.is_empty():
		slot_name = current_save_slot

	if slot_name.is_empty():
		push_error("No save slot specified")
		return false

	print("Saving game to slot: %s" % slot_name)

	EventBus.before_save.emit()

	var save_data: Dictionary = _gather_save_data()
	var success: bool = _write_save_file(slot_name, save_data)

	if success:
		current_save_slot = slot_name
		print("Game saved successfully")
	else:
		push_error("Failed to save game")

	EventBus.save_completed.emit(success)
	return success


func load_game(slot_name: String) -> bool:
	"""Load game state from specified slot"""

	print("Loading game from slot: %s" % slot_name)

	var save_data: Dictionary = _read_save_file(slot_name)
	if save_data.is_empty():
		push_error("Failed to load save file: %s" % slot_name)
		return false

	var save_version: int = int(save_data.get("version", 1))
	if save_version < CURRENT_SAVE_VERSION:
		if not _backup_legacy_save(slot_name, save_version):
			push_warning("Could not back up legacy save before migration; proceeding anyway")

	var success: bool = _apply_save_data(save_data)

	if success:
		current_save_slot = slot_name
		print("Game loaded successfully")
		EventBus.after_load.emit()
	else:
		push_error("Failed to apply save data")

	return success


func auto_save() -> bool:
	"""Perform an auto-save"""
	if current_save_slot.is_empty():
		return false

	var auto_save_name: String = current_save_slot + "_auto"
	print("Auto-saving...")
	return save_game(auto_save_name)


func delete_save(slot_name: String) -> bool:
	"""Delete a save file"""
	var file_path: String = _get_save_path(slot_name)

	if not FileAccess.file_exists(file_path):
		push_error("Save file does not exist: %s" % slot_name)
		return false

	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	var error: int = dir.remove(file_path)

	if error == OK:
		print("Save deleted: %s" % slot_name)
		return true
	else:
		push_error("Failed to delete save: %s" % slot_name)
		return false


func list_saves() -> Array[Dictionary]:
	"""Get list of available save files. .v1.bak files are excluded because
	they do not end with SAVE_EXTENSION ('.save')."""
	var saves: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)

	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()

		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(SAVE_EXTENSION):
				var slot_name: String = file_name.trim_suffix(SAVE_EXTENSION)
				var file_path: String = _get_save_path(slot_name)

				saves.append({
					"slot": slot_name,
					"path": file_path,
					"modified": FileAccess.get_modified_time(file_path)
				})

			file_name = dir.get_next()

		dir.list_dir_end()

	# Sort by modified time (newest first)
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.modified > b.modified)

	return saves


# ========================================
# PREFERENCES
# ========================================

func save_preferences() -> void:
	"""Save player preferences"""
	var config: ConfigFile = ConfigFile.new()

	config.set_value("game", "auto_save_enabled", auto_save_enabled)
	config.set_value("game", "auto_save_interval", auto_save_interval)

	var error: int = config.save(PREFERENCES_FILE)
	if error != OK:
		push_error("Failed to save preferences")


func load_preferences() -> void:
	"""Load player preferences"""
	var config: ConfigFile = ConfigFile.new()
	var error: int = config.load(PREFERENCES_FILE)

	if error != OK:
		print("No preferences file found, using defaults")
		return

	auto_save_enabled = config.get_value("game", "auto_save_enabled", true)
	auto_save_interval = config.get_value("game", "auto_save_interval", 300.0)


# ========================================
# PRIVATE METHODS — TEMPLATES
# ========================================

func _v3_empty_template() -> Dictionary:
	"""Return a fully populated v3 dict with empty per-corp partitions.
	Used by both migration and fresh-save gathering."""
	return {
		"version": 3,
		"wall_timestamp": Time.get_unix_time_from_system(),
		"date": {"year": 1850, "month": 1, "day": 1},
		"game_state": "WORLD_MAP",
		"active_corp_id": GameManager.CORP_SINGLE,
		"active_factory_id": "",
		"tick_count": 0,
		"rng_seed": 0,

		SECTION_SHARED: {
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

		SECTION_CORPS: _empty_corps_block(),

		"utilities": null,
		"events": null
	}


func _empty_corps_block() -> Dictionary:
	"""Return an empty corp partition block for all four corps."""
	var corps: Dictionary = {}
	for corp_id: String in [GameManager.CORP_AGRI, GameManager.CORP_INDUSTRIAL,
			GameManager.CORP_LOGISTICS, GameManager.CORP_BUSINESS]:
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


# ========================================
# PRIVATE METHODS — GATHER (WRITE PATH)
# ========================================

func _gather_save_data() -> Dictionary:
	"""Gather all game state data into v3 shape for saving."""
	var data: Dictionary = _v3_empty_template()
	data.wall_timestamp = Time.get_unix_time_from_system()
	data.date = GameManager.current_date
	data.game_state = GameManager.GameState.keys()[GameManager.current_state]
	data.active_corp_id = GameManager.active_corp_id
	data.active_factory_id = GameManager.active_factory_id

	_gather_shared_data(data[SECTION_SHARED])
	_gather_corp_partitions(data[SECTION_CORPS])
	return data


func _gather_shared_data(out: Dictionary) -> void:
	"""Populate the shared block from live managers."""
	# Economy
	out.money = EconomyManager.money
	out.total_earned = EconomyManager.total_earned
	out.total_spent = EconomyManager.total_spent
	out.total_maintenance_paid = EconomyManager.total_maintenance_paid
	out.last_maintenance_cost = EconomyManager.last_maintenance_cost
	out.disabled_facilities = EconomyManager.disabled_facilities.keys()

	# World tiles
	out.world_tiles.next_facility_id = WorldManager._next_facility_id

	var roads_data: Dictionary = {}
	for x: int in range(WorldManager.GRID_SIZE.x):
		for y: int in range(WorldManager.GRID_SIZE.y):
			var road_type: String = WorldManager.get_road_type_at(Vector2i(x, y))
			if not road_type.is_empty():
				roads_data["%d,%d" % [x, y]] = road_type
	out.world_tiles.roads = roads_data

	out.world_tiles.field_parents = WorldManager.field_parents.duplicate()

	var farmhouse_children_data: Dictionary = {}
	for farmhouse_id: String in WorldManager.farmhouse_children:
		farmhouse_children_data[farmhouse_id] = WorldManager.farmhouse_children[farmhouse_id].duplicate()
	out.world_tiles.farmhouse_children = farmhouse_children_data

	# Global counters
	out.next_machine_id = FactoryManager._next_machine_id
	out.next_connection_id = LogisticsManager._next_connection_id
	out.next_vehicle_id = LogisticsManager._next_vehicle_id

	# Market state (without contracts — contracts go to corps.business)
	var market_save: Dictionary = MarketManager.get_save_data()
	out.market.current_prices = market_save.get("current_prices", {})
	out.market.price_multipliers = market_save.get("price_multipliers", {})
	out.market.supply_pressure = market_save.get("supply_pressure", {})
	out.market.market_trends = market_save.get("market_trends", {})
	out.next_contract_id = market_save.get("next_contract_id", 1)

	# Factory-internal machine-to-machine connections (scoped to parent facility, no corp)
	for facility_id: String in FactoryManager.factory_interiors:
		var interior: Dictionary = FactoryManager.factory_interiors[facility_id]
		var connections_data: Array = []
		for conn in interior.get("connections", []):
			connections_data.append({"from": conn.from, "to": conn.to})
		out.factory_connections[facility_id] = connections_data


func _gather_corp_partitions(out: Dictionary) -> void:
	"""Slot every owned entity into its corp partition."""

	# Facilities
	for facility_id: String in WorldManager.facilities:
		var facility: Dictionary = WorldManager.facilities[facility_id]
		var corp_id: String = _resolve_entity_corp_for_write(facility, GameManager.CORP_INDUSTRIAL)
		out[corp_id].facilities[facility_id] = {
			"id": facility.id,
			"corp_id": corp_id,
			"type": facility.type,
			"grid_pos": {"x": facility.grid_pos.x, "y": facility.grid_pos.y},
			"size": {"x": facility.size.x, "y": facility.size.y},
			"world_pos": {"x": facility.world_pos.x, "y": facility.world_pos.y},
			"constructed": facility.constructed,
			"construction_progress": facility.construction_progress,
			"production_active": facility.production_active,
			"inventory": facility.get("inventory", {}),
			"created_date": facility.created_date
		}

	# Machines (keyed under their parent corp partition)
	for facility_id: String in FactoryManager.factory_interiors:
		var interior: Dictionary = FactoryManager.factory_interiors[facility_id]
		# Corp for all machines in this interior = parent facility's corp.
		var parent_facility: Dictionary = WorldManager.facilities.get(facility_id, {})
		var corp_id: String = _resolve_entity_corp_for_write(parent_facility, GameManager.CORP_INDUSTRIAL)

		for machine_id: String in interior.get("machines", {}):
			var machine: Dictionary = interior.machines[machine_id]
			out[corp_id].machines[machine_id] = {
				"id": machine.id,
				"corp_id": corp_id,
				"facility_id": facility_id,
				"type": machine.type,
				"grid_pos": {"x": machine.grid_pos.x, "y": machine.grid_pos.y},
				"size": {"x": machine.size.x, "y": machine.size.y},
				"world_pos": {"x": machine.world_pos.x, "y": machine.world_pos.y},
				"active": machine.get("active", true),
				"inventory": machine.get("inventory", {})
			}

	# Connections
	for connection_id: String in LogisticsManager.connections:
		var connection: Dictionary = LogisticsManager.connections[connection_id]
		var corp_id: String = _resolve_entity_corp_for_write(connection, GameManager.CORP_LOGISTICS)
		var path_array: Array = []
		for pos in LogisticsManager.connection_paths.get(connection_id, []):
			path_array.append({"x": pos.x, "y": pos.y})
		out[corp_id].connections[connection_id] = {
			"id": connection.id,
			"corp_id": corp_id,
			"source_id": connection.source_id,
			"destination_id": connection.destination_id,
			"product": connection.product,
			"active": connection.get("active", true),
			"created_date": connection.get("created_date", GameManager.current_date),
			"vehicle_capacity": connection.get("vehicle_capacity", LogisticsManager.vehicle_capacity),
			"current_throughput": connection.get("current_throughput", 0),
			"path": path_array
		}

	# Vehicles
	for vehicle_id: String in LogisticsManager.vehicles:
		var vehicle: Dictionary = LogisticsManager.vehicles[vehicle_id]
		var corp_id: String = _resolve_entity_corp_for_write(vehicle, GameManager.CORP_LOGISTICS)
		var vehicle_path: Array = []
		for pos in vehicle.get("path", []):
			vehicle_path.append({"x": pos.x, "y": pos.y})
		out[corp_id].vehicles[vehicle_id] = {
			"id": vehicle.id,
			"corp_id": corp_id,
			"connection_id": vehicle.get("connection_id", ""),
			"source_id": vehicle.source_id,
			"destination_id": vehicle.destination_id,
			"state": vehicle.get("state", "at_source"),
			"position": {"x": vehicle.position.x, "y": vehicle.position.y},
			"cargo": vehicle.get("cargo", {}),
			"travel_progress": vehicle.get("travel_progress", 0.0),
			"path": vehicle_path,
			"path_index": vehicle.get("path_index", 0),
			"is_returning": vehicle.get("is_returning", false)
		}

	# Contracts (always business)
	for contract in MarketManager.active_contracts:
		var c: Dictionary = contract.duplicate()
		c["corp_id"] = GameManager.CORP_BUSINESS
		out[GameManager.CORP_BUSINESS].contracts.append(c)

	# Production state — partitioned by parent facility's corp
	_gather_production_partitions(out)

	# Research — entire blob into corps.industrial.research_internal for step 2.
	var research_save: Dictionary = ResearchManager.get_save_data()
	var ri: Dictionary = out[GameManager.CORP_INDUSTRIAL].research_internal
	ri.unlocked_techs = research_save.get("unlocked_techs", [])
	ri.current_tier = int(research_save.get("current_tier", 1))
	ri.tier_deliveries = research_save.get("tier_deliveries", {})


func _gather_production_partitions(out: Dictionary) -> void:
	"""Distribute ProductionManager flat dicts into per-corp partitions for saving."""

	# Build facility_id → corp_id lookup from already-gathered facilities.
	var facility_to_corp: Dictionary = {}
	for corp_id: String in out:
		for fid: String in out[corp_id].facilities:
			facility_to_corp[fid] = corp_id

	# Facility-keyed sections
	for key: String in ["production_timers", "production_outputs", "facility_stats"]:
		var src: Dictionary = {}
		match key:
			"production_timers":  src = ProductionManager.production_timers
			"production_outputs": src = ProductionManager.production_outputs
			"facility_stats":     src = ProductionManager.facility_stats
		for fid: String in src:
			var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)
			out[corp_id].production[key][fid] = src[fid]

	# Machine-keyed sections (key format: "facility_id:machine_id")
	for key: String in ["machine_timers", "machine_inventories"]:
		var src: Dictionary = {}
		match key:
			"machine_timers":       src = ProductionManager.machine_timers
			"machine_inventories":  src = ProductionManager.machine_inventories
		for mk: String in src:
			var fid: String = _facility_id_from_machine_key(mk)
			var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)
			out[corp_id].production[key][mk] = src[mk]

	# Always-agri sections
	out[GameManager.CORP_AGRI].production.farmhouse_crop_types = ProductionManager.farmhouse_crop_types.duplicate()
	out[GameManager.CORP_AGRI].production.field_production_targets = ProductionManager.field_production_targets.duplicate()


func _resolve_entity_corp_for_write(entity_dict: Dictionary, default_corp: String) -> String:
	"""Resolve a valid write-side corp from an entity dict.
	Calls push_error and returns default_corp if corp_id is missing or invalid."""
	var cid: String = entity_dict.get("corp_id", "")
	if cid in [GameManager.CORP_AGRI, GameManager.CORP_INDUSTRIAL,
			GameManager.CORP_LOGISTICS, GameManager.CORP_BUSINESS]:
		return cid
	push_error("Entity has invalid corp_id '%s' for save; routing to '%s'" % [cid, default_corp])
	return default_corp


# ========================================
# PRIVATE METHODS — APPLY (READ PATH)
# ========================================

func _apply_save_data(data: Dictionary) -> bool:
	"""Dispatch to migration then v3 reader."""
	var version: int = int(data.get("version", 1))

	if version > CURRENT_SAVE_VERSION:
		push_error("Save version %d is newer than supported %d" % [version, CURRENT_SAVE_VERSION])
		return false

	if version < CURRENT_SAVE_VERSION:
		data = _migrate_to_v3(data, version)
		if data.is_empty():
			return false  # migration failure already logged

	return _apply_v3_data(data)


func _apply_v3_data(data: Dictionary) -> bool:
	"""Apply a confirmed-v3 save dict to all managers."""
	print("Applying v3 save data...")
	_clear_game_state()

	GameManager.current_date = data.get("date", {"year": 1850, "month": 1, "day": 1})
	GameManager.active_corp_id = data.get("active_corp_id", GameManager.CORP_SINGLE)
	GameManager.active_factory_id = data.get("active_factory_id", "")

	var shared: Dictionary = data.get(SECTION_SHARED, {})
	var corps: Dictionary = data.get(SECTION_CORPS, {})

	_restore_shared(shared)
	_restore_corp_partitions(corps)

	print("Save data applied successfully")
	return true


func _restore_shared(data: Dictionary) -> void:
	"""Restore shared block into managers."""
	# Economy
	EconomyManager.money = data.get("money", 5000)
	EconomyManager.total_earned = data.get("total_earned", 0)
	EconomyManager.total_spent = data.get("total_spent", 0)
	EconomyManager.total_maintenance_paid = data.get("total_maintenance_paid", 0)
	EconomyManager.last_maintenance_cost = data.get("last_maintenance_cost", 0)
	EconomyManager.disabled_facilities.clear()
	for facility_id in data.get("disabled_facilities", []):
		EconomyManager.disabled_facilities[facility_id] = true
	print("Economy restored: $%d" % EconomyManager.money)

	# World tiles
	var world_tiles: Dictionary = data.get("world_tiles", {})
	WorldManager._next_facility_id = int(world_tiles.get("next_facility_id", 1))

	var roads_data: Dictionary = world_tiles.get("roads", {})
	for pos_key: String in roads_data:
		var parts: PackedStringArray = pos_key.split(",")
		if parts.size() == 2:
			var x: int = int(parts[0])
			var y: int = int(parts[1])
			WorldManager.road_grid[x][y] = roads_data[pos_key]
			EventBus.road_placed.emit(Vector2i(x, y), roads_data[pos_key])

	var field_parents_data: Dictionary = world_tiles.get("field_parents", {})
	for field_id: String in field_parents_data:
		WorldManager.field_parents[field_id] = field_parents_data[field_id]

	var farmhouse_children_data: Dictionary = world_tiles.get("farmhouse_children", {})
	for farmhouse_id: String in farmhouse_children_data:
		var children = farmhouse_children_data[farmhouse_id]
		WorldManager.farmhouse_children[farmhouse_id] = children.duplicate() if children is Array else []

	# Global counters
	FactoryManager._next_machine_id = int(data.get("next_machine_id", 1))
	LogisticsManager._next_connection_id = int(data.get("next_connection_id", 1))
	LogisticsManager._next_vehicle_id = int(data.get("next_vehicle_id", 1))

	# Market (global prices; contracts come from corps.business below)
	var market_data: Dictionary = data.get("market", {})
	var next_contract_id: int = int(data.get("next_contract_id", 1))
	# Build a dict load_save_data understands (without active_contracts so it skips that key)
	var market_load: Dictionary = {
		"current_prices":    market_data.get("current_prices", {}),
		"price_multipliers": market_data.get("price_multipliers", {}),
		"supply_pressure":   market_data.get("supply_pressure", {}),
		"market_trends":     market_data.get("market_trends", {}),
		"next_contract_id":  next_contract_id
	}
	MarketManager.load_save_data(market_load)

	# Factory-internal connections
	var factory_connections: Dictionary = data.get("factory_connections", {})
	for facility_id: String in factory_connections:
		if FactoryManager.factory_interiors.has(facility_id):
			var interior: Dictionary = FactoryManager.factory_interiors[facility_id]
			interior.connections.clear()
			for conn in factory_connections[facility_id]:
				interior.connections.append({"from": conn.from, "to": conn.to})


func _restore_corp_partitions(corps: Dictionary) -> void:
	"""Pour all four corp partitions back into the corp-blind manager storage."""
	var road_tile_count: int = 0
	var total_facilities: int = 0
	var total_machines: int = 0
	var total_connections: int = 0
	var total_vehicles: int = 0

	for corp_id: String in corps:
		var corp: Dictionary = corps[corp_id]

		# Facilities
		var facilities_data: Dictionary = corp.get("facilities", {})
		for facility_id: String in facilities_data:
			var fac_data: Dictionary = facilities_data[facility_id]
			var facility: Dictionary = {
				"id": fac_data.get("id", facility_id),
				"corp_id": fac_data.get("corp_id", corp_id),
				"type": fac_data.get("type", ""),
				"grid_pos": Vector2i(int(fac_data.get("grid_pos", {}).get("x", 0)),
									int(fac_data.get("grid_pos", {}).get("y", 0))),
				"size": Vector2i(int(fac_data.get("size", {}).get("x", 1)),
								int(fac_data.get("size", {}).get("y", 1))),
				"world_pos": Vector2(float(fac_data.get("world_pos", {}).get("x", 0)),
									float(fac_data.get("world_pos", {}).get("y", 0))),
				"constructed": fac_data.get("constructed", false),
				"construction_progress": float(fac_data.get("construction_progress", 0.0)),
				"production_active": fac_data.get("production_active", false),
				"inventory": fac_data.get("inventory", {}),
				"created_date": fac_data.get("created_date", GameManager.current_date)
			}
			WorldManager.facilities[facility_id] = facility

			# Occupy grid tiles
			for x: int in range(facility.size.x):
				for y: int in range(facility.size.y):
					var gx: int = facility.grid_pos.x + x
					var gy: int = facility.grid_pos.y + y
					WorldManager.grid[gx][gy] = facility_id

			EventBus.facility_placed.emit(facility)
			total_facilities += 1

		# Machines — rebuild interiors keyed by facility_id
		var machines_data: Dictionary = corp.get("machines", {})
		for machine_id: String in machines_data:
			var mach_data: Dictionary = machines_data[machine_id]
			var fid: String = mach_data.get("facility_id", "")
			if fid.is_empty():
				push_warning("Machine %s has no facility_id in v3 save; skipping" % machine_id)
				continue

			# Ensure interior exists
			if not FactoryManager.factory_interiors.has(fid):
				FactoryManager.factory_interiors[fid] = {
					"facility_id": fid,
					"grid": FactoryManager._initialize_interior_grid(),
					"machines": {},
					"connections": [],
					"created_date": GameManager.current_date
				}

			var interior: Dictionary = FactoryManager.factory_interiors[fid]
			var machine: Dictionary = {
				"id": mach_data.get("id", machine_id),
				"corp_id": mach_data.get("corp_id", corp_id),
				"type": mach_data.get("type", ""),
				"grid_pos": Vector2i(int(mach_data.get("grid_pos", {}).get("x", 0)),
									int(mach_data.get("grid_pos", {}).get("y", 0))),
				"size": Vector2i(int(mach_data.get("size", {}).get("x", 1)),
								int(mach_data.get("size", {}).get("y", 1))),
				"world_pos": Vector2(float(mach_data.get("world_pos", {}).get("x", 0)),
									float(mach_data.get("world_pos", {}).get("y", 0))),
				"active": mach_data.get("active", true),
				"inventory": mach_data.get("inventory", {})
			}
			interior.machines[machine_id] = machine

			# Occupy interior grid tiles
			var gp: Vector2i = machine.grid_pos
			var sz: Vector2i = machine.size
			for x: int in range(sz.x):
				for y: int in range(sz.y):
					interior.grid[gp.x + x][gp.y + y] = machine_id

			total_machines += 1

		# Connections
		var connections_data: Dictionary = corp.get("connections", {})
		for connection_id: String in connections_data:
			var conn_data: Dictionary = connections_data[connection_id]
			var connection: Dictionary = {
				"id": conn_data.get("id", connection_id),
				"corp_id": conn_data.get("corp_id", corp_id),
				"source_id": conn_data.get("source_id", ""),
				"destination_id": conn_data.get("destination_id", ""),
				"product": conn_data.get("product", ""),
				"active": conn_data.get("active", true),
				"created_date": conn_data.get("created_date", GameManager.current_date),
				"vehicle_capacity": conn_data.get("vehicle_capacity", LogisticsManager.vehicle_capacity),
				"current_throughput": conn_data.get("current_throughput", 0)
			}
			LogisticsManager.connections[connection_id] = connection

			# Restore path (path is now embedded in the connection dict)
			var path_array = conn_data.get("path", [])
			var path: Array = []
			for pos in path_array:
				path.append(Vector2i(int(pos.get("x", 0)), int(pos.get("y", 0))))
			LogisticsManager.connection_paths[connection_id] = path

			EventBus.connection_created.emit(connection)
			total_connections += 1

		# Vehicles
		var vehicles_data: Dictionary = corp.get("vehicles", {})
		for vehicle_id: String in vehicles_data:
			var veh_data: Dictionary = vehicles_data[vehicle_id]
			var vehicle_path: Array = []
			for pos in veh_data.get("path", []):
				vehicle_path.append(Vector2i(int(pos.get("x", 0)), int(pos.get("y", 0))))
			var vehicle: Dictionary = {
				"id": veh_data.get("id", vehicle_id),
				"corp_id": veh_data.get("corp_id", corp_id),
				"connection_id": veh_data.get("connection_id", ""),
				"source_id": veh_data.get("source_id", ""),
				"destination_id": veh_data.get("destination_id", ""),
				"state": veh_data.get("state", "at_source"),
				"position": Vector2(float(veh_data.get("position", {}).get("x", 0)),
									float(veh_data.get("position", {}).get("y", 0))),
				"cargo": veh_data.get("cargo", {}),
				"travel_progress": float(veh_data.get("travel_progress", 0.0)),
				"path": vehicle_path,
				"path_index": int(veh_data.get("path_index", 0)),
				"is_returning": veh_data.get("is_returning", false)
			}
			LogisticsManager.vehicles[vehicle_id] = vehicle
			EventBus.vehicle_spawned.emit(vehicle)
			total_vehicles += 1

		# Contracts (rebuild MarketManager.active_contracts from business partition)
		if corp_id == GameManager.CORP_BUSINESS:
			for contract in corp.get("contracts", []):
				MarketManager.active_contracts.append(contract.duplicate())

		# Research (read from industrial; all other corps are empty in step 2)
		if corp_id == GameManager.CORP_INDUSTRIAL:
			var ri: Dictionary = corp.get("research_internal", {})
			if not ri.is_empty():
				ResearchManager.load_save_data({
					"unlocked_techs": ri.get("unlocked_techs", []),
					"current_tier": ri.get("current_tier", 1),
					"tier_deliveries": ri.get("tier_deliveries", {})
				})

		# Production state
		var prod: Dictionary = corp.get("production", {})
		_restore_production_from_corp(prod)

	print("World restored: %d facilities, %d road tiles" % [total_facilities, road_tile_count])
	print("Factories restored: %d interiors" % FactoryManager.factory_interiors.size())
	print("Logistics restored: %d connections, %d vehicles" % [total_connections, total_vehicles])
	print("Market restored: %d active contracts" % MarketManager.active_contracts.size())
	print("Research restored: %d technologies unlocked" % ResearchManager.get_unlocked_count())


func _restore_production_from_corp(prod: Dictionary) -> void:
	"""Merge a single corp's production block back into the flat ProductionManager dicts."""
	var timers: Dictionary = prod.get("production_timers", {})
	for fid: String in timers:
		ProductionManager.production_timers[fid] = timers[fid]

	var outputs: Dictionary = prod.get("production_outputs", {})
	for fid: String in outputs:
		ProductionManager.production_outputs[fid] = outputs[fid].duplicate()

	var machine_timers: Dictionary = prod.get("machine_timers", {})
	for mk: String in machine_timers:
		ProductionManager.machine_timers[mk] = machine_timers[mk]

	var machine_inventories: Dictionary = prod.get("machine_inventories", {})
	for mk: String in machine_inventories:
		ProductionManager.machine_inventories[mk] = machine_inventories[mk].duplicate()

	var stats: Dictionary = prod.get("facility_stats", {})
	for fid: String in stats:
		ProductionManager.facility_stats[fid] = stats[fid].duplicate(true)

	var farmhouse_crop_types: Dictionary = prod.get("farmhouse_crop_types", {})
	for farmhouse_id: String in farmhouse_crop_types:
		ProductionManager.farmhouse_crop_types[farmhouse_id] = farmhouse_crop_types[farmhouse_id]

	var field_production_targets: Dictionary = prod.get("field_production_targets", {})
	for field_id: String in field_production_targets:
		ProductionManager.field_production_targets[field_id] = field_production_targets[field_id]


# ========================================
# PRIVATE METHODS — MIGRATION
# ========================================

func _migrate_to_v3(data: Dictionary, from_version: int) -> Dictionary:
	"""Forward-only migration from any pre-v3 shape to v3.
	Builds the v3 dict entirely in memory; returns {} on failure."""
	print("Migrating save from v%d to v3..." % from_version)

	var migrated: Dictionary = _v3_empty_template()

	# ---- Top level ----
	migrated.wall_timestamp = float(data.get("timestamp", Time.get_unix_time_from_system()))
	migrated.date = _merge_with_default(data.get("date", null), {"year": 1850, "month": 1, "day": 1})
	migrated.game_state = data.get("game_state", "WORLD_MAP")
	migrated.active_corp_id = GameManager.CORP_SINGLE
	migrated.active_factory_id = ""

	# ---- Shared: economy ----
	var econ: Dictionary = data.get("economy", {})
	migrated[SECTION_SHARED].money = int(econ.get("money", 5000))
	migrated[SECTION_SHARED].total_earned = int(econ.get("total_earned", 0))
	migrated[SECTION_SHARED].total_spent = int(econ.get("total_spent", 0))
	migrated[SECTION_SHARED].total_maintenance_paid = int(econ.get("total_maintenance_paid", 0))
	migrated[SECTION_SHARED].last_maintenance_cost = int(econ.get("last_maintenance_cost", 0))
	var disabled_legacy = econ.get("disabled_facilities", [])
	migrated[SECTION_SHARED].disabled_facilities = (disabled_legacy as Array).duplicate()

	# ---- Shared: world tiles ----
	var world: Dictionary = data.get("world", {})
	migrated[SECTION_SHARED].world_tiles.next_facility_id = int(world.get("next_facility_id", 1))
	var roads_legacy: Dictionary = world.get("roads", {})
	migrated[SECTION_SHARED].world_tiles.roads = roads_legacy.duplicate()
	var field_parents_legacy: Dictionary = world.get("field_parents", {})
	migrated[SECTION_SHARED].world_tiles.field_parents = field_parents_legacy.duplicate()
	var fc_legacy: Dictionary = world.get("farmhouse_children", {})
	for fh_id: String in fc_legacy:
		migrated[SECTION_SHARED].world_tiles.farmhouse_children[fh_id] = (fc_legacy[fh_id] as Array).duplicate()

	# ---- Shared: global counters ----
	var factories_root: Dictionary = data.get("factories", {})
	var logistics_root: Dictionary = data.get("logistics", {})
	var market_root: Dictionary = data.get("market", {})

	migrated[SECTION_SHARED].next_machine_id = int(factories_root.get("next_machine_id", 1))
	# Absorb both legacy and canonical connection-id-counter key names.
	migrated[SECTION_SHARED].next_connection_id = int(
		logistics_root.get("next_connection_id", logistics_root.get("next_route_id", 1)))
	migrated[SECTION_SHARED].next_vehicle_id = int(logistics_root.get("next_vehicle_id", 1))
	migrated[SECTION_SHARED].next_contract_id = int(market_root.get("next_contract_id", 1))

	# ---- Shared: market (global state, no contracts) ----
	migrated[SECTION_SHARED].market.current_prices = (market_root.get("current_prices", {}) as Dictionary).duplicate()
	migrated[SECTION_SHARED].market.price_multipliers = (market_root.get("price_multipliers", {}) as Dictionary).duplicate()
	migrated[SECTION_SHARED].market.supply_pressure = (market_root.get("supply_pressure", {}) as Dictionary).duplicate()
	migrated[SECTION_SHARED].market.market_trends = (market_root.get("market_trends", {}) as Dictionary).duplicate()

	# ---- Facilities: rebucket into corps ----
	var facility_to_corp: Dictionary = {}  # facility_id -> corp_id; used by downstream phases
	var legacy_facilities: Dictionary = world.get("facilities", {})
	for fid: String in legacy_facilities:
		var fac: Dictionary = (legacy_facilities[fid] as Dictionary).duplicate(true)
		var corp_id: String = _resolve_facility_corp(fac)
		fac["corp_id"] = corp_id
		migrated[SECTION_CORPS][corp_id].facilities[fid] = fac
		facility_to_corp[fid] = corp_id

	# ---- Machines: rebucket via parent facility + factory_connections → shared ----
	var legacy_interiors: Dictionary = factories_root.get("interiors", {})
	for fid: String in legacy_interiors:
		var interior: Dictionary = legacy_interiors[fid]
		var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)

		var legacy_machines: Dictionary = interior.get("machines", {})
		for mid: String in legacy_machines:
			var machine: Dictionary = (legacy_machines[mid] as Dictionary).duplicate(true)
			machine["corp_id"] = corp_id
			machine["facility_id"] = fid
			migrated[SECTION_CORPS][corp_id].machines[mid] = machine

		# Factory-internal connections live under shared (scoped to facility, no corp_id).
		migrated[SECTION_SHARED].factory_connections[fid] = (interior.get("connections", []) as Array).duplicate()

	# ---- Connections & paths: rebucket ----
	# Tolerate both legacy routes/route_paths keys and canonical connections/connection_paths.
	var legacy_connections: Dictionary = logistics_root.get("connections",
		logistics_root.get("routes", {}))
	var legacy_paths: Dictionary = logistics_root.get("connection_paths",
		logistics_root.get("route_paths", {}))
	var connection_to_corp: Dictionary = {}
	for cid: String in legacy_connections:
		var conn: Dictionary = (legacy_connections[cid] as Dictionary).duplicate(true)
		var corp_id: String = conn.get("corp_id", GameManager.CORP_LOGISTICS)
		# Treat CORP_SINGLE on a connection as unresolved — rebucket to CORP_LOGISTICS.
		if corp_id == GameManager.CORP_SINGLE:
			corp_id = GameManager.CORP_LOGISTICS
		# Move path into the connection dict (was a sibling structure).
		if legacy_paths.has(cid):
			conn["path"] = (legacy_paths[cid] as Array).duplicate()
		else:
			conn["path"] = []
		conn["corp_id"] = corp_id
		migrated[SECTION_CORPS][corp_id].connections[cid] = conn
		connection_to_corp[cid] = corp_id

	# ---- Vehicles: rebucket via parent connection (fallback: own corp_id) ----
	var legacy_vehicles: Dictionary = logistics_root.get("vehicles", {})
	for vid: String in legacy_vehicles:
		var veh: Dictionary = (legacy_vehicles[vid] as Dictionary).duplicate(true)
		# Tolerate legacy route_id field — rename to connection_id.
		if veh.has("route_id") and not veh.has("connection_id"):
			veh["connection_id"] = veh["route_id"]
			veh.erase("route_id")
		var cid: String = veh.get("connection_id", "")
		var corp_id: String = veh.get("corp_id",
			connection_to_corp.get(cid, GameManager.CORP_LOGISTICS))
		if corp_id == GameManager.CORP_SINGLE:
			corp_id = GameManager.CORP_LOGISTICS
		veh["corp_id"] = corp_id
		migrated[SECTION_CORPS][corp_id].vehicles[vid] = veh

	# ---- Contracts: always business ----
	var legacy_contracts: Array = market_root.get("active_contracts", [])
	for contract in legacy_contracts:
		var c: Dictionary = (contract as Dictionary).duplicate(true)
		c["corp_id"] = GameManager.CORP_BUSINESS
		migrated[SECTION_CORPS][GameManager.CORP_BUSINESS].contracts.append(c)

	# ---- Production state: rebucket by owning facility ----
	var prod_root: Dictionary = data.get("production", {})
	_rebucket_production(prod_root, migrated[SECTION_CORPS], facility_to_corp)

	# ---- Research: entire blob into corps.industrial.research_internal ----
	var research_root: Dictionary = data.get("research", {})
	if not research_root.is_empty():
		var ri: Dictionary = migrated[SECTION_CORPS][GameManager.CORP_INDUSTRIAL].research_internal
		ri.unlocked_techs = (research_root.get("unlocked_techs", []) as Array).duplicate()
		ri.current_tier = int(research_root.get("current_tier", 1))
		ri.tier_deliveries = (research_root.get("tier_deliveries", {}) as Dictionary).duplicate()

	print("Migration complete. Facilities by corp: agri=%d industrial=%d logistics=%d business=%d" % [
		migrated[SECTION_CORPS][GameManager.CORP_AGRI].facilities.size(),
		migrated[SECTION_CORPS][GameManager.CORP_INDUSTRIAL].facilities.size(),
		migrated[SECTION_CORPS][GameManager.CORP_LOGISTICS].facilities.size(),
		migrated[SECTION_CORPS][GameManager.CORP_BUSINESS].facilities.size(),
	])
	return migrated


func _resolve_facility_corp(facility: Dictionary) -> String:
	"""Three-fallback chain: explicit corp_id → type lookup.
	CORP_SINGLE is treated as 'unset' and rebucketed by type."""
	var existing: String = facility.get("corp_id", "")
	if existing != "" and existing != GameManager.CORP_SINGLE and existing in GameManager.VALID_CORP_IDS:
		return existing
	return _facility_type_to_corp(facility.get("type", ""))


func _facility_type_to_corp(facility_type: String) -> String:
	"""Map a facility type string to its owning corp.
	Unknowns default to industrial with a push_warning."""
	if FACILITY_TYPE_TO_CORP.has(facility_type):
		return FACILITY_TYPE_TO_CORP[facility_type]
	push_warning("Unknown facility_type during migration: '%s' — defaulting to industrial" % facility_type)
	return GameManager.CORP_INDUSTRIAL


func _rebucket_production(prod: Dictionary, corps: Dictionary, facility_to_corp: Dictionary) -> void:
	"""Distribute production state across per-corp partitions by parent facility."""

	# Facility-keyed sections
	for key: String in ["production_timers", "production_outputs", "facility_stats"]:
		var src: Dictionary = prod.get(key, {})
		for fid: String in src:
			var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)
			corps[corp_id].production[key][fid] = src[fid]

	# Machine-keyed sections (format: "facility_id:machine_id" — verified in production_manager.gd)
	for key: String in ["machine_timers", "machine_inventories"]:
		var src: Dictionary = prod.get(key, {})
		for mk: String in src:
			var fid: String = _facility_id_from_machine_key(mk)
			var corp_id: String = facility_to_corp.get(fid, GameManager.CORP_INDUSTRIAL)
			corps[corp_id].production[key][mk] = src[mk]

	# Always-agri sections
	corps[GameManager.CORP_AGRI].production.farmhouse_crop_types = (prod.get("farmhouse_crop_types", {}) as Dictionary).duplicate()
	corps[GameManager.CORP_AGRI].production.field_production_targets = (prod.get("field_production_targets", {}) as Dictionary).duplicate()


func _facility_id_from_machine_key(machine_key: String) -> String:
	"""Machine keys are 'facility_id:machine_id' (separator is ':', confirmed in production_manager.gd).
	Returns the facility_id portion; empty string forces CORP_INDUSTRIAL default."""
	var parts: PackedStringArray = machine_key.split(":", false, 1)
	if parts.size() >= 1:
		return parts[0]
	return ""


func _merge_with_default(value, default: Dictionary) -> Dictionary:
	"""Merge a potentially-null/incomplete dict with a default. Used for date fields."""
	var result: Dictionary = default.duplicate()
	if value is Dictionary:
		for k in value:
			result[k] = value[k]
	return result


# ========================================
# PRIVATE METHODS — BACKUP
# ========================================

func _backup_legacy_save(slot_name: String, version: int) -> bool:
	"""Copy legacy save to <slot>.save.v<version>.bak before migration overwrites it.
	Skips if the backup already exists (idempotent)."""
	var src: String = _get_save_path(slot_name)
	var dst: String = SAVE_DIR + slot_name + ".save.v%d.bak" % version
	if FileAccess.file_exists(dst):
		return true  # already backed up on a previous load
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	var err: int = dir.copy(src, dst)
	if err == OK:
		print("Backed up legacy save: %s -> %s" % [src, dst])
		return true
	push_error("Backup failed: error %d copying %s to %s" % [err, src, dst])
	return false


# ========================================
# PRIVATE METHODS — FILE I/O
# ========================================

func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _get_save_path(slot_name: String) -> String:
	"""Get full path for a save slot"""
	return SAVE_DIR + slot_name + SAVE_EXTENSION


func _write_save_file(slot_name: String, data: Dictionary) -> bool:
	"""Write save data to file via atomic tmp+rename to protect against partial writes."""
	var file_path: String = _get_save_path(slot_name)
	var tmp_path: String = file_path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)

	if not file:
		push_error("Failed to open temp save file for writing: %s" % tmp_path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		push_error("Cannot open save dir for rename")
		return false
	if FileAccess.file_exists(file_path):
		dir.remove(file_path)
	var err: int = dir.rename(tmp_path, file_path)
	if err != OK:
		push_error("Failed to rename %s to %s (err %d)" % [tmp_path, file_path, err])
		return false
	return true


func _read_save_file(slot_name: String) -> Dictionary:
	"""Read save data from file"""
	var file_path: String = _get_save_path(slot_name)

	if not FileAccess.file_exists(file_path):
		return {}

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file for reading: %s" % file_path)
		return {}

	var json_string: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: int = json.parse(json_string)

	if error != OK:
		push_error("Failed to parse save file JSON")
		return {}

	return json.data


func _clear_game_state() -> void:
	"""Clear all existing game state before loading"""
	print("Clearing existing game state...")

	# Clear world map
	WorldManager.facilities.clear()
	WorldManager._initialize_grid()

	# Clear factories
	FactoryManager.factory_interiors.clear()

	# Clear logistics
	LogisticsManager.connections.clear()
	LogisticsManager.connection_paths.clear()
	LogisticsManager.vehicles.clear()

	# Clear production
	ProductionManager.production_timers.clear()
	ProductionManager.production_outputs.clear()
	ProductionManager.machine_timers.clear()
	ProductionManager.machine_inventories.clear()
	ProductionManager.facility_stats.clear()

	# Clear economy/maintenance
	EconomyManager.reset_economy()

	# Clear market - reinitialize to base values
	MarketManager._initialize_market()
	MarketManager.active_contracts.clear()

	# Clear research
	ResearchManager.clear_data()
