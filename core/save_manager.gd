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

const CURRENT_SAVE_VERSION = 1

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

	var save_data = _gather_save_data()
	var success = _write_save_file(slot_name, save_data)

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

	var save_data = _read_save_file(slot_name)
	if save_data.is_empty():
		push_error("Failed to load save file: %s" % slot_name)
		return false

	var success = _apply_save_data(save_data)

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

	var auto_save_name = current_save_slot + "_auto"
	print("Auto-saving...")
	return save_game(auto_save_name)


func delete_save(slot_name: String) -> bool:
	"""Delete a save file"""
	var file_path = _get_save_path(slot_name)

	if not FileAccess.file_exists(file_path):
		push_error("Save file does not exist: %s" % slot_name)
		return false

	var dir = DirAccess.open(SAVE_DIR)
	var error = dir.remove(file_path)

	if error == OK:
		print("Save deleted: %s" % slot_name)
		return true
	else:
		push_error("Failed to delete save: %s" % slot_name)
		return false


func list_saves() -> Array[Dictionary]:
	"""Get list of available save files"""
	var saves: Array[Dictionary] = []
	var dir = DirAccess.open(SAVE_DIR)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(SAVE_EXTENSION):
				var slot_name = file_name.trim_suffix(SAVE_EXTENSION)
				var file_path = _get_save_path(slot_name)

				saves.append({
					"slot": slot_name,
					"path": file_path,
					"modified": FileAccess.get_modified_time(file_path)
				})

			file_name = dir.get_next()

		dir.list_dir_end()

	# Sort by modified time (newest first)
	saves.sort_custom(func(a, b): return a.modified > b.modified)

	return saves


# ========================================
# PREFERENCES
# ========================================

func save_preferences() -> void:
	"""Save player preferences"""
	var config = ConfigFile.new()

	config.set_value("game", "auto_save_enabled", auto_save_enabled)
	config.set_value("game", "auto_save_interval", auto_save_interval)

	var error = config.save(PREFERENCES_FILE)
	if error != OK:
		push_error("Failed to save preferences")


func load_preferences() -> void:
	"""Load player preferences"""
	var config = ConfigFile.new()
	var error = config.load(PREFERENCES_FILE)

	if error != OK:
		print("No preferences file found, using defaults")
		return

	auto_save_enabled = config.get_value("game", "auto_save_enabled", true)
	auto_save_interval = config.get_value("game", "auto_save_interval", 300.0)


# ========================================
# PRIVATE METHODS
# ========================================

func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _get_save_path(slot_name: String) -> String:
	"""Get full path for a save slot"""
	return SAVE_DIR + slot_name + SAVE_EXTENSION


func _gather_save_data() -> Dictionary:
	"""Gather all game state data for saving"""
	return {
		"version": CURRENT_SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"date": GameManager.current_date,
		"game_state": GameManager.GameState.keys()[GameManager.current_state],

		# System data from managers
		"world": _gather_world_data(),
		"factories": _gather_factory_data(),
		"logistics": _gather_logistics_data(),
		"economy": _gather_economy_data(),
		"production": _gather_production_data(),
		"market": _gather_market_data(),
		"research": _gather_research_data(),
	}


func _gather_world_data() -> Dictionary:
	"""Gather world map data from WorldManager"""
	var facilities_data = {}

	for facility_id in WorldManager.facilities:
		var facility = WorldManager.facilities[facility_id]
		facilities_data[facility_id] = {
			"id": facility.id,
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

	# Save road grid in sparse format (only non-empty tiles)
	var roads_data = {}
	for x in range(WorldManager.GRID_SIZE.x):
		for y in range(WorldManager.GRID_SIZE.y):
			var road_type = WorldManager.get_road_type_at(Vector2i(x, y))
			if not road_type.is_empty():
				roads_data["%d,%d" % [x, y]] = road_type

	# Save farmhouse relationships
	var field_parents_data = WorldManager.field_parents.duplicate()
	var farmhouse_children_data = {}
	for farmhouse_id in WorldManager.farmhouse_children:
		farmhouse_children_data[farmhouse_id] = WorldManager.farmhouse_children[farmhouse_id].duplicate()

	return {
		"next_facility_id": WorldManager._next_facility_id,
		"facilities": facilities_data,
		"roads": roads_data,
		"field_parents": field_parents_data,
		"farmhouse_children": farmhouse_children_data
	}


func _gather_factory_data() -> Dictionary:
	"""Gather factory interior data from FactoryManager"""
	var factories_data = {}

	for facility_id in FactoryManager.factory_interiors:
		var interior = FactoryManager.factory_interiors[facility_id]
		var machines_data = {}

		# Save all machines
		for machine_id in interior.machines:
			var machine = interior.machines[machine_id]
			machines_data[machine_id] = {
				"id": machine.id,
				"type": machine.type,
				"grid_pos": {"x": machine.grid_pos.x, "y": machine.grid_pos.y},
				"size": {"x": machine.size.x, "y": machine.size.y},
				"world_pos": {"x": machine.world_pos.x, "y": machine.world_pos.y},
				"active": machine.active,
				"inventory": machine.get("inventory", {})
			}

		# Save connections (already in correct format - array of {from, to} dicts)
		var connections_data = []
		for conn in interior.connections:
			connections_data.append({"from": conn.from, "to": conn.to})

		factories_data[facility_id] = {
			"machines": machines_data,
			"connections": connections_data
		}

	return {
		"next_machine_id": FactoryManager._next_machine_id,
		"interiors": factories_data
	}


func _gather_logistics_data() -> Dictionary:
	"""Gather logistics data from LogisticsManager"""
	var connections_data = {}
	var vehicles_data = {}
	var connection_paths_data = {}

	# Save all connections
	for connection_id in LogisticsManager.connections:
		var connection = LogisticsManager.connections[connection_id]
		connections_data[connection_id] = {
			"id": connection.id,
			"source_id": connection.source_id,
			"destination_id": connection.destination_id,
			"product": connection.product,
			"active": connection.active,
			"created_date": connection.get("created_date", GameManager.current_date),
			"vehicle_capacity": connection.get("vehicle_capacity", LogisticsManager.vehicle_capacity),
			"current_throughput": connection.get("current_throughput", 0)
		}

	# Save connection paths (road paths for each connection)
	for connection_id in LogisticsManager.connection_paths:
		var path = LogisticsManager.connection_paths[connection_id]
		var path_array = []
		for pos in path:
			path_array.append({"x": pos.x, "y": pos.y})
		connection_paths_data[connection_id] = path_array

	# Save all vehicles (transient - vehicles are auto-dispatched, but save current state)
	for vehicle_id in LogisticsManager.vehicles:
		var vehicle = LogisticsManager.vehicles[vehicle_id]
		var vehicle_path = []
		for pos in vehicle.get("path", []):
			vehicle_path.append({"x": pos.x, "y": pos.y})
		vehicles_data[vehicle_id] = {
			"id": vehicle.id,
			"connection_id": vehicle.get("connection_id", ""),
			"source_id": vehicle.source_id,
			"destination_id": vehicle.destination_id,
			"state": vehicle.state,
			"position": {"x": vehicle.position.x, "y": vehicle.position.y},
			"cargo": vehicle.cargo,
			"travel_progress": vehicle.travel_progress,
			"path": vehicle_path,
			"path_index": vehicle.get("path_index", 0),
			"is_returning": vehicle.get("is_returning", false)
		}

	return {
		"next_connection_id": LogisticsManager._next_connection_id,
		"next_vehicle_id": LogisticsManager._next_vehicle_id,
		"connections": connections_data,
		"vehicles": vehicles_data,
		"connection_paths": connection_paths_data
	}


func _gather_economy_data() -> Dictionary:
	"""Gather economy data from EconomyManager"""
	return {
		"money": EconomyManager.money,
		"total_earned": EconomyManager.total_earned,
		"total_spent": EconomyManager.total_spent,
		"disabled_facilities": EconomyManager.disabled_facilities.keys(),
		"total_maintenance_paid": EconomyManager.total_maintenance_paid,
		"last_maintenance_cost": EconomyManager.last_maintenance_cost
	}


func _gather_production_data() -> Dictionary:
	"""Gather production data from ProductionManager"""
	return {
		"production_timers": ProductionManager.production_timers,
		"production_outputs": ProductionManager.production_outputs,
		"machine_timers": ProductionManager.machine_timers,
		"machine_inventories": ProductionManager.machine_inventories,
		"facility_stats": ProductionManager.facility_stats,
		"farmhouse_crop_types": ProductionManager.farmhouse_crop_types,
		"field_production_targets": ProductionManager.field_production_targets
	}


func _gather_market_data() -> Dictionary:
	"""Gather market data from MarketManager"""
	return MarketManager.get_save_data()


func _gather_research_data() -> Dictionary:
	"""Gather research data from ResearchManager"""
	return ResearchManager.get_save_data()


func _apply_save_data(data: Dictionary) -> bool:
	"""Apply loaded save data to game state"""

	# Version check
	if not data.has("version") or data.version != CURRENT_SAVE_VERSION:
		push_error("Incompatible save version")
		return false

	print("Applying save data...")

	# Clear existing state
	_clear_game_state()

	# Restore game manager state
	GameManager.current_date = data.get("date", {"year": 1850, "month": 1, "day": 1})

	# Restore each system
	if data.has("economy"):
		_restore_economy_data(data.economy)

	if data.has("world"):
		_restore_world_data(data.world)

	if data.has("factories"):
		_restore_factory_data(data.factories)

	if data.has("logistics"):
		_restore_logistics_data(data.logistics)

	if data.has("production"):
		_restore_production_data(data.production)

	if data.has("market"):
		_restore_market_data(data.market)

	if data.has("research"):
		_restore_research_data(data.research)

	print("Save data applied successfully")
	return true


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


func _restore_economy_data(data: Dictionary) -> void:
	"""Restore economy state"""
	EconomyManager.money = data.get("money", 5000)
	EconomyManager.total_earned = data.get("total_earned", 0)
	EconomyManager.total_spent = data.get("total_spent", 0)
	EconomyManager.total_maintenance_paid = data.get("total_maintenance_paid", 0)
	EconomyManager.last_maintenance_cost = data.get("last_maintenance_cost", 0)

	# Restore disabled facilities
	EconomyManager.disabled_facilities.clear()
	var disabled_list = data.get("disabled_facilities", [])
	for facility_id in disabled_list:
		EconomyManager.disabled_facilities[facility_id] = true

	print("Economy restored: $%d" % EconomyManager.money)


func _restore_world_data(data: Dictionary) -> void:
	"""Restore world map state"""
	# Restore facility ID counter
	WorldManager._next_facility_id = data.get("next_facility_id", 1)

	# Restore all facilities
	var facilities_data = data.get("facilities", {})
	for facility_id in facilities_data:
		var fac_data = facilities_data[facility_id]

		# Reconstruct facility dictionary
		var facility = {
			"id": fac_data.id,
			"type": fac_data.type,
			"grid_pos": Vector2i(fac_data.grid_pos.x, fac_data.grid_pos.y),
			"size": Vector2i(fac_data.size.x, fac_data.size.y),
			"world_pos": Vector2(fac_data.world_pos.x, fac_data.world_pos.y),
			"constructed": fac_data.get("constructed", false),
			"construction_progress": fac_data.get("construction_progress", 0.0),
			"production_active": fac_data.get("production_active", false),
			"inventory": fac_data.get("inventory", {}),
			"created_date": fac_data.get("created_date", GameManager.current_date)
		}

		# Add to WorldManager
		WorldManager.facilities[facility_id] = facility

		# Occupy grid tiles
		for x in range(facility.size.x):
			for y in range(facility.size.y):
				var grid_x = facility.grid_pos.x + x
				var grid_y = facility.grid_pos.y + y
				WorldManager.grid[grid_x][grid_y] = facility_id

		# Emit signal so world map can create visuals
		EventBus.facility_placed.emit(facility)

	# Restore road grid
	var roads_data = data.get("roads", {})
	for pos_key in roads_data:
		var parts = pos_key.split(",")
		if parts.size() == 2:
			var x = int(parts[0])
			var y = int(parts[1])
			var road_type = roads_data[pos_key]
			WorldManager.road_grid[x][y] = road_type
			EventBus.road_placed.emit(Vector2i(x, y), road_type)

	# Restore farmhouse relationships
	var field_parents_data = data.get("field_parents", {})
	for field_id in field_parents_data:
		WorldManager.field_parents[field_id] = field_parents_data[field_id]

	var farmhouse_children_data = data.get("farmhouse_children", {})
	for farmhouse_id in farmhouse_children_data:
		var children = farmhouse_children_data[farmhouse_id]
		WorldManager.farmhouse_children[farmhouse_id] = children.duplicate() if children is Array else []

	print("World restored: %d facilities, %d road tiles" % [facilities_data.size(), roads_data.size()])


func _restore_factory_data(data: Dictionary) -> void:
	"""Restore factory interiors state"""
	# Restore global machine ID counter
	FactoryManager._next_machine_id = data.get("next_machine_id", 1)

	var interiors_data = data.get("interiors", {})
	var factory_count = 0

	for facility_id in interiors_data:
		var interior_data = interiors_data[facility_id]
		var machines_data = interior_data.get("machines", {})
		var connections_data = interior_data.get("connections", [])

		# Reconstruct interior dictionary (without next_machine_id - it's global)
		var interior = {
			"facility_id": facility_id,
			"grid": FactoryManager._initialize_interior_grid(),
			"machines": {},
			"connections": [],
			"created_date": GameManager.current_date
		}

		# Restore machines
		for machine_id in machines_data:
			var mach_data = machines_data[machine_id]
			var machine = {
				"id": mach_data.id,
				"type": mach_data.type,
				"grid_pos": Vector2i(mach_data.grid_pos.x, mach_data.grid_pos.y),
				"size": Vector2i(mach_data.size.x, mach_data.size.y),
				"world_pos": Vector2(mach_data.world_pos.x, mach_data.world_pos.y),
				"active": mach_data.get("active", true),
				"inventory": mach_data.get("inventory", {})
			}
			interior.machines[machine_id] = machine

			# Occupy grid tiles
			var grid_pos = machine.grid_pos
			var size = machine.size
			for x in range(size.x):
				for y in range(size.y):
					interior.grid[grid_pos.x + x][grid_pos.y + y] = machine_id

		# Restore connections (array of {from, to} objects)
		for conn in connections_data:
			interior.connections.append({
				"from": conn.from,
				"to": conn.to
			})

		FactoryManager.factory_interiors[facility_id] = interior
		factory_count += 1

	print("Factories restored: %d interiors" % factory_count)


func _restore_logistics_data(data: Dictionary) -> void:
	"""Restore logistics state (handles both old 'routes' and new 'connections' format)"""
	# Restore ID counters (try new name first, fall back to old)
	LogisticsManager._next_connection_id = data.get("next_connection_id", data.get("next_route_id", 1))  # TODO(step-2 v3 bump): drop the next_route_id fallback once schema bumps to v3.
	LogisticsManager._next_vehicle_id = data.get("next_vehicle_id", 1)

	# Restore connection paths first (try new name first, fall back to old)
	var connection_paths_data = data.get("connection_paths", data.get("route_paths", {}))  # TODO(step-2 v3 bump): drop the route_paths fallback once schema bumps to v3.
	for connection_id in connection_paths_data:
		var path_array = connection_paths_data[connection_id]
		var path: Array = []
		for pos in path_array:
			path.append(Vector2i(pos.x, pos.y))
		LogisticsManager.connection_paths[connection_id] = path

	# Restore connections (try new name first, fall back to old)
	var connections_data = data.get("connections", data.get("routes", {}))  # TODO(step-2 v3 bump): drop the routes fallback once schema bumps to v3.
	for connection_id in connections_data:
		var connection_data = connections_data[connection_id]
		var connection = {
			"id": connection_data.id,
			"source_id": connection_data.source_id,
			"destination_id": connection_data.destination_id,
			"product": connection_data.product,
			"active": connection_data.get("active", true),
			"created_date": connection_data.get("created_date", GameManager.current_date),
			"vehicle_capacity": connection_data.get("vehicle_capacity", connection_data.get("capacity", LogisticsManager.vehicle_capacity)),
			"current_throughput": connection_data.get("current_throughput", 0)
		}
		LogisticsManager.connections[connection_id] = connection

		# Emit signal so connection visuals are created
		EventBus.connection_created.emit(connection)

	# Restore vehicles
	var vehicles_data = data.get("vehicles", {})
	for vehicle_id in vehicles_data:
		var vehicle_data = vehicles_data[vehicle_id]

		# Restore vehicle path
		var vehicle_path: Array = []
		for pos in vehicle_data.get("path", []):
			vehicle_path.append(Vector2i(pos.x, pos.y))

		# Get connection_id (try new name first, fall back to old)
		var connection_id = vehicle_data.get("connection_id", vehicle_data.get("route_id", ""))  # TODO(step-2 v3 bump): drop the route_id fallback once schema bumps to v3.

		var vehicle = {
			"id": vehicle_data.id,
			"connection_id": connection_id,
			"source_id": vehicle_data.source_id,
			"destination_id": vehicle_data.destination_id,
			"state": vehicle_data.get("state", "at_source"),
			"position": Vector2(vehicle_data.position.x, vehicle_data.position.y),
			"cargo": vehicle_data.get("cargo", {}),
			"travel_progress": vehicle_data.get("travel_progress", 0.0),
			"path": vehicle_path,
			"path_index": vehicle_data.get("path_index", 0),
			"is_returning": vehicle_data.get("is_returning", false)
		}
		LogisticsManager.vehicles[vehicle_id] = vehicle

		# Emit signal so vehicle visuals are created
		EventBus.vehicle_spawned.emit(vehicle)

	print("Logistics restored: %d connections, %d vehicles, %d paths" % [connections_data.size(), vehicles_data.size(), connection_paths_data.size()])


func _restore_production_data(data: Dictionary) -> void:
	"""Restore production state"""
	# Restore production timers
	var timers = data.get("production_timers", {})
	for facility_id in timers:
		ProductionManager.production_timers[facility_id] = timers[facility_id]

	# Restore production outputs (facility inventories)
	var outputs = data.get("production_outputs", {})
	for facility_id in outputs:
		ProductionManager.production_outputs[facility_id] = outputs[facility_id].duplicate()

	# Restore machine timers
	var machine_timers = data.get("machine_timers", {})
	for machine_key in machine_timers:
		ProductionManager.machine_timers[machine_key] = machine_timers[machine_key]

	# Restore machine inventories
	var machine_inventories = data.get("machine_inventories", {})
	for machine_key in machine_inventories:
		ProductionManager.machine_inventories[machine_key] = machine_inventories[machine_key].duplicate()

	# Restore facility stats
	var stats = data.get("facility_stats", {})
	for facility_id in stats:
		ProductionManager.facility_stats[facility_id] = stats[facility_id].duplicate(true)

	# Restore farmhouse crop types
	var farmhouse_crop_types = data.get("farmhouse_crop_types", {})
	for farmhouse_id in farmhouse_crop_types:
		ProductionManager.farmhouse_crop_types[farmhouse_id] = farmhouse_crop_types[farmhouse_id]

	# Restore field production targets
	var field_production_targets = data.get("field_production_targets", {})
	for field_id in field_production_targets:
		ProductionManager.field_production_targets[field_id] = field_production_targets[field_id]

	print("Production restored: %d facilities, %d machines, %d farmhouses" % [timers.size(), machine_timers.size(), farmhouse_crop_types.size()])


func _restore_market_data(data: Dictionary) -> void:
	"""Restore market state"""
	MarketManager.load_save_data(data)
	print("Market restored: %d active contracts" % MarketManager.active_contracts.size())


func _restore_research_data(data: Dictionary) -> void:
	"""Restore research state"""
	ResearchManager.load_save_data(data)
	print("Research restored: %d technologies unlocked" % ResearchManager.get_unlocked_count())


func _write_save_file(slot_name: String, data: Dictionary) -> bool:
	"""Write save data to file"""
	var file_path = _get_save_path(slot_name)
	var file = FileAccess.open(file_path, FileAccess.WRITE)

	if not file:
		push_error("Failed to open save file for writing: %s" % file_path)
		return false

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()

	return true


func _read_save_file(slot_name: String) -> Dictionary:
	"""Read save data from file"""
	var file_path = _get_save_path(slot_name)

	if not FileAccess.file_exists(file_path):
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file for reading: %s" % file_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_error("Failed to parse save file JSON")
		return {}

	return json.data
