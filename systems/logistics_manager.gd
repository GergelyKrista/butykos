extends Node

## LogisticsManager - Connections, vehicles, and cargo transport
##
## Manages transportation of goods between facilities via connections and vehicles.
## Handles auto-dispatch when full, delivery, and vehicle movement.
## Supports multiple vehicles per connection with automatic spawning.
## Integrates with ResearchManager for speed and capacity bonuses.

# ========================================
# RESEARCH BONUS HELPERS
# ========================================

func _get_vehicle_speed_multiplier() -> float:
	"""Get combined vehicle speed multiplier from research"""
	var multiplier = 1.0
	multiplier *= ResearchManager.get_bonus_multiplier("speed_multiplier", "vehicles")
	multiplier *= ResearchManager.get_bonus_multiplier("speed_multiplier", "all")
	return multiplier


func _get_vehicle_capacity_multiplier() -> float:
	"""Get combined vehicle capacity multiplier from research"""
	var multiplier = 1.0
	multiplier *= ResearchManager.get_bonus_multiplier("capacity_multiplier", "vehicles")
	multiplier *= ResearchManager.get_bonus_multiplier("capacity_multiplier", "all")
	return multiplier


func _has_instant_delivery_bonus() -> bool:
	"""Check if research grants instant delivery"""
	# instant_delivery bonus returns true if unlocked
	var value = ResearchManager.get_bonus_multiplier("instant_delivery", "vehicles")
	# If any bonus is active, the multiplier would be different from 1.0
	# But instant_delivery uses true/false, so we check differently
	for tech_id in ResearchManager.unlocked_techs:
		var tech = ResearchManager.research_tree.get(tech_id, {})
		var unlocks = tech.get("unlocks", {})
		var bonuses = unlocks.get("bonuses", [])
		for bonus in bonuses:
			if bonus.get("type") == "instant_delivery":
				return bonus.get("value", false)
	return false


# ========================================
# STATE
# ========================================

# Dictionary of connections: { connection_id: connection_data }
var connections: Dictionary = {}

# Dictionary of vehicles: { vehicle_id: vehicle_data }
var vehicles: Dictionary = {}

# Dictionary of connection paths: { connection_id: [Vector2i waypoints] }
var connection_paths: Dictionary = {}

# Counter for generating unique IDs
var _next_connection_id: int = 1
var _next_vehicle_id: int = 1

# ========================================
# CONFIGURATION
# ========================================

var vehicle_speed: float = 20.0  # pixels per second (slower for visible travel)
var vehicle_capacity: int = 50   # units per truck (increased from 10)
var instant_delivery: bool = false  # For testing: instant delivery

# Auto-dispatch settings
var auto_dispatch_enabled: bool = true  # Dispatch new vehicle when source has enough
var dispatch_check_interval: float = 1.0  # How often to check for dispatch
var max_vehicles_per_connection: int = 3  # Max trucks per connection (realistic limit)
var _dispatch_timer: float = 0.0

# ========================================
# NETWORK PANEL VIEW STATE (per-corp)
# ========================================
#
# State that the Logistics Network panel persists across scene reloads
# (factory interior trips) and across corp switches. Each corp keeps its
# own layout — switching to another corp swaps in that corp's state, so
# arrangements don't leak between players.
#
# Shape: { corp_id: { custom_positions, canvas_zoom, canvas_offset } }
# Lives on this autoload manager so it survives the world_map scene
# being re-instantiated when returning from a brewery interior.
var network_view_state: Dictionary = {}


func get_network_view_state_for_corp(corp_id: String) -> Dictionary:
	"""Return the per-corp view state for the Logistics Network panel.
	Creates a fresh default entry if no state exists for this corp yet.
	The returned dict is held by reference — mutating it (e.g. inserting
	into `custom_positions`) writes through to the persistent store."""
	if not network_view_state.has(corp_id):
		network_view_state[corp_id] = {
			"custom_positions": {},
			"canvas_zoom": 1.0,
			"canvas_offset": Vector2.ZERO,
		}
	return network_view_state[corp_id]

# Throughput tracking (per cycle)
var throughput_cycle_time: float = 60.0  # Seconds between throughput resets
var _throughput_timer: float = 0.0

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("LogisticsManager initialized")

	# Connect to facility events
	EventBus.facility_removed.connect(_on_facility_removed)

	# Connect to road events for path invalidation
	EventBus.road_removed.connect(_on_road_removed)


func _process(delta: float) -> void:
	_update_vehicles(delta)
	_update_throughput_cycle(delta)
	_update_auto_dispatch(delta)


func _update_throughput_cycle(delta: float) -> void:
	"""Reset connection throughput counters periodically"""
	_throughput_timer += delta
	if _throughput_timer >= throughput_cycle_time:
		_throughput_timer = 0.0
		# Reset throughput for all connections
		for connection_id in connections:
			connections[connection_id].current_throughput = 0


func _update_auto_dispatch(delta: float) -> void:
	"""Check all connections for auto-dispatch opportunities"""
	if not auto_dispatch_enabled:
		return

	_dispatch_timer += delta
	if _dispatch_timer < dispatch_check_interval:
		return
	_dispatch_timer = 0.0

	# Check each active connection for dispatch
	for connection_id in connections:
		var connection = connections[connection_id]
		if not connection.get("active", false):
			continue

		_check_auto_dispatch(connection_id, connection)


func _check_auto_dispatch(connection_id: String, connection: Dictionary) -> void:
	"""Check if we should spawn a new vehicle for this connection"""
	var source_id = connection.source_id
	var product = connection.product

	# Check vehicle count limit
	var current_vehicle_count = get_connection_vehicles(connection_id).size()
	if current_vehicle_count >= max_vehicles_per_connection:
		return  # Already at max capacity

	# Apply capacity bonus from research
	var capacity_mult = _get_vehicle_capacity_multiplier()
	var actual_capacity = int(vehicle_capacity * capacity_mult)

	# Check if source has enough product for a full load
	var available = ProductionManager.get_inventory_item(source_id, product)
	if available < actual_capacity:
		return

	# Check if any vehicle is currently loading at source
	if _has_loading_vehicle(connection_id):
		return

	# Spawn a new vehicle
	var path = connection_paths.get(connection_id, [])
	var vehicle_id = _create_vehicle(connection_id, source_id, connection.destination_id, path)

	print("Auto-dispatched vehicle %s for connection %s (%d/%d trucks, source has %d %s)" % [
		vehicle_id, connection_id, current_vehicle_count + 1, max_vehicles_per_connection, available, product
	])


func _has_loading_vehicle(connection_id: String) -> bool:
	"""Check if any vehicle is currently at source (loading) for this connection"""
	for vehicle in vehicles.values():
		if vehicle.get("connection_id", "") == connection_id:
			if vehicle.state == "at_source":
				return true
	return false


# ========================================
# ROUTE MANAGEMENT
# ========================================

func can_create_connection(corp_id: String, source_id: String, destination_id: String, product: String) -> Dictionary:
	"""Predicate for ACTION_CREATE_LOGISTICS_CONNECTION.
	Note: includes A* road-path check — expensive but necessary to surface 'no road' rejection
	before the mutator runs. See plan §4.3 for rationale."""
	if WorldManager.get_facility(source_id).is_empty():
		return { "ok": false, "reason": "Source facility not found" }
	if WorldManager.get_facility(destination_id).is_empty():
		return { "ok": false, "reason": "Destination facility not found" }
	if source_id == destination_id:
		return { "ok": false, "reason": "Cannot connect facility to itself" }
	var path: Array[Vector2i] = WorldManager.find_road_path(source_id, destination_id)
	if path.is_empty():
		return { "ok": false, "reason": "No road path between facilities" }
	for conn_id in connections:
		var conn: Dictionary = connections[conn_id]
		if conn.source_id == source_id and conn.destination_id == destination_id:
			return { "ok": false, "reason": "Connection already exists" }
	return { "ok": true, "reason": "" }


func can_remove_connection(corp_id: String, connection_id: String) -> Dictionary:
	"""Predicate for ACTION_REMOVE_LOGISTICS_CONNECTION."""
	if not connections.has(connection_id):
		return { "ok": false, "reason": "Connection not found" }
	return { "ok": true, "reason": "" }


func can_toggle_connection_active(corp_id: String, connection_id: String) -> Dictionary:
	"""Predicate for ACTION_TOGGLE_CONNECTION_ACTIVE."""
	if not connections.has(connection_id):
		return { "ok": false, "reason": "Connection not found" }
	return { "ok": true, "reason": "" }


func create_connection(source_id: String, destination_id: String, product: String, corp_id: String = GameManager.CORP_LOGISTICS) -> String:
	"""Create a connection between two facilities for a specific product.
	Per technical-architecture A7: Logistics owns transport routes in v1.
	Default corp_id is CORP_LOGISTICS, not CORP_SINGLE — Logistics is the broker.
	Cross-corp negotiation UI is a v1.5 feature.
	Vehicles will auto-dispatch when source has enough inventory."""

	# Validate facilities exist
	var source = WorldManager.get_facility(source_id)
	var destination = WorldManager.get_facility(destination_id)

	if source.is_empty() or destination.is_empty():
		push_error("Cannot create connection: invalid facilities")
		return ""

	# Find road path between facilities (auto-connects within 2 tiles)
	var path = WorldManager.find_road_path(source_id, destination_id)
	if path.is_empty():
		push_warning("Cannot create connection: no road connection between facilities")
		EventBus.notification_posted.emit("No road connection! Build roads near both facilities.", "error")
		return ""

	# Check for duplicate connection
	for conn_id in connections:
		var conn = connections[conn_id]
		if conn.source_id == source_id and conn.destination_id == destination_id:
			push_warning("Connection already exists between these facilities")
			EventBus.notification_posted.emit("Connection already exists!", "warning")
			return ""

	# Generate connection ID
	var connection_id = "conn_%d" % _next_connection_id
	_next_connection_id += 1

	# Store path for this connection
	connection_paths[connection_id] = path

	# Create connection data
	var connection = {
		"id": connection_id,
		"corp_id": corp_id,            # Phase 8 step 1: Logistics-owned by default.
		"source_id": source_id,
		"destination_id": destination_id,
		"product": product,
		"active": true,
		"created_date": GameManager.current_date.duplicate(),
		"vehicle_capacity": vehicle_capacity,
		"current_throughput": 0
	}

	connections[connection_id] = connection

	# Emit events
	print("Connection created: %s → %s (%s) via %d road tiles" % [source_id, destination_id, product, path.size()])
	EventBus.connection_created.emit(connection)

	# Immediately check for auto-dispatch
	_check_auto_dispatch(connection_id, connection)

	return connection_id


func remove_connection(connection_id: String) -> bool:
	"""Remove a connection and all its vehicles"""

	if not connections.has(connection_id):
		return false

	# Remove all vehicles for this connection
	var vehicles_to_remove: Array[String] = []
	for vehicle_id in vehicles:
		var vehicle = vehicles[vehicle_id]
		var conn_id = vehicle.get("connection_id", "")
		if conn_id == connection_id:
			vehicles_to_remove.append(vehicle_id)

	for vehicle_id in vehicles_to_remove:
		_remove_vehicle(vehicle_id)

	# Remove cached path
	connection_paths.erase(connection_id)

	# Remove connection
	connections.erase(connection_id)

	print("Connection removed: %s (removed %d vehicles)" % [connection_id, vehicles_to_remove.size()])
	EventBus.connection_removed.emit(connection_id)

	return true


func get_connection(connection_id: String) -> Dictionary:
	"""Get connection data"""
	return connections.get(connection_id, {})


func set_connection_active(connection_id: String, active: bool) -> bool:
	"""Pause or unpause a connection"""
	if not connections.has(connection_id):
		return false

	var connection = connections[connection_id]
	connection.active = active
	print("Connection %s %s" % [connection_id, "resumed" if active else "paused"])
	EventBus.connection_updated.emit(connection)
	return true


func toggle_connection_active(connection_id: String) -> bool:
	"""Toggle connection active state"""
	if not connections.has(connection_id):
		return false

	var connection = connections[connection_id]
	connection.active = not connection.active
	print("Connection %s %s" % [connection_id, "resumed" if connection.active else "paused"])
	EventBus.connection_updated.emit(connection)
	return true


func get_connections_from_facility(facility_id: String) -> Array[Dictionary]:
	"""Get all connections originating from a facility"""
	var result: Array[Dictionary] = []
	for connection in connections.values():
		if connection.source_id == facility_id:
			result.append(connection)
	return result


func get_connections_to_facility(facility_id: String) -> Array[Dictionary]:
	"""Get all connections going to a facility"""
	var result: Array[Dictionary] = []
	for connection in connections.values():
		if connection.destination_id == facility_id:
			result.append(connection)
	return result


func get_connection_vehicles(connection_id: String) -> Array[Dictionary]:
	"""Get all vehicles for a specific connection"""
	var result: Array[Dictionary] = []
	for vehicle in vehicles.values():
		var conn_id = vehicle.get("connection_id", "")
		if conn_id == connection_id:
			result.append(vehicle)
	return result


# ========================================
# VEHICLE MANAGEMENT
# ========================================

func _create_vehicle(connection_id: String, source_id: String, destination_id: String, path: Array = []) -> String:
	"""Create a vehicle for a connection"""

	var vehicle_id = "vehicle_%d" % _next_vehicle_id
	_next_vehicle_id += 1

	var source = WorldManager.get_facility(source_id)
	var destination = WorldManager.get_facility(destination_id)

	# Vehicles inherit corp_id from their parent connection. No separate parameter
	# because vehicles are never created outside the auto-dispatch path inside this manager.
	var parent_connection: Dictionary = connections.get(connection_id, {})
	var vehicle_corp_id: String = parent_connection.get("corp_id", GameManager.CORP_LOGISTICS)

	var vehicle = {
		"id": vehicle_id,
		"corp_id": vehicle_corp_id,    # Phase 8 step 1: inherited from connection.
		"connection_id": connection_id,
		"source_id": source_id,
		"destination_id": destination_id,
		"state": "at_source",  # at_source, traveling, at_destination
		"position": source.world_pos,
		"cargo": {},
		"travel_progress": 0.0,  # 0.0 to 1.0 for current segment
		"path": path,  # Array of Vector2i waypoints
		"path_index": 0,  # Current waypoint index
		"is_returning": false  # True when vehicle is on return trip
	}

	vehicles[vehicle_id] = vehicle

	EventBus.vehicle_created.emit(vehicle)
	EventBus.vehicle_spawned.emit(vehicle)  # Alias for visualization

	return vehicle_id


func _remove_vehicle(vehicle_id: String) -> void:
	"""Remove a vehicle"""
	EventBus.vehicle_removed.emit(vehicle_id)
	vehicles.erase(vehicle_id)


# ========================================
# VEHICLE UPDATES
# ========================================

func _update_vehicles(delta: float) -> void:
	"""Update all vehicle states"""

	# Collect vehicles to remove after processing
	var vehicles_to_remove: Array[String] = []

	for vehicle_id in vehicles.keys():
		var vehicle = vehicles[vehicle_id]
		var connection_id = vehicle.get("connection_id", "")
		var connection = connections.get(connection_id, {})

		if connection.is_empty() or not connection.get("active", false):
			continue

		match vehicle.state:
			"at_source":
				_handle_pickup(vehicle, connection)
			"traveling":
				_handle_travel(vehicle, connection, delta)
			"at_destination":
				var should_remove = _handle_delivery(vehicle, connection)
				if should_remove:
					vehicles_to_remove.append(vehicle_id)

	# Remove vehicles that completed their delivery
	for vehicle_id in vehicles_to_remove:
		_remove_vehicle(vehicle_id)


func _handle_pickup(vehicle: Dictionary, connection: Dictionary) -> void:
	"""Handle vehicle pickup at source facility"""

	var source_id = connection.source_id
	var product = connection.product

	# Apply capacity bonus from research
	var capacity_mult = _get_vehicle_capacity_multiplier()
	var actual_capacity = int(vehicle_capacity * capacity_mult)

	# Check if source has product available for full load
	var available = ProductionManager.get_inventory_item(source_id, product)

	if available >= actual_capacity:
		# Pickup cargo (full load)
		if ProductionManager.remove_item_from_facility(source_id, product, actual_capacity):
			vehicle.cargo[product] = actual_capacity
			vehicle.state = "traveling"
			vehicle.travel_progress = 0.0

			# Track throughput
			var current_throughput = connection.get("current_throughput", 0)
			connection.current_throughput = current_throughput + actual_capacity

			var bonus_info = ""
			if capacity_mult != 1.0:
				bonus_info = " [+%.0f%% capacity]" % ((capacity_mult - 1.0) * 100)

			print("Vehicle %s loaded %d %s from %s%s" % [
				vehicle.id, actual_capacity, product, source_id, bonus_info
			])


func _handle_travel(vehicle: Dictionary, connection: Dictionary, delta: float) -> void:
	"""Handle vehicle traveling along road path (one-way trip)"""

	# Check for instant delivery (testing or from research)
	if instant_delivery or _has_instant_delivery_bonus():
		# Skip travel animation - go directly to destination
		var destination = WorldManager.get_facility(connection.destination_id)
		vehicle.position = destination.world_pos
		vehicle.state = "at_destination"
		return

	var path: Array = vehicle.get("path", [])
	if path.is_empty():
		# Fallback to direct travel if no path
		_handle_direct_travel(vehicle, connection, delta)
		return

	# Get current waypoint index (one-way trip only)
	var path_index: int = vehicle.get("path_index", 0)

	# Safety check - arrived at destination
	if path_index >= path.size():
		var destination = WorldManager.get_facility(connection.destination_id)
		vehicle.state = "at_destination"
		vehicle.position = destination.world_pos
		return

	# Current waypoint position
	var current_grid_pos = path[path_index] as Vector2i
	var current_world_pos = WorldManager.cart_to_iso(Vector2(current_grid_pos.x + 0.5, current_grid_pos.y + 0.5))

	# Next waypoint position
	var next_index = path_index + 1
	var next_world_pos: Vector2
	var is_last_waypoint = false

	if next_index >= path.size():
		# Reached destination
		var destination = WorldManager.get_facility(connection.destination_id)
		next_world_pos = destination.world_pos
		is_last_waypoint = true
	else:
		var next_grid_pos = path[next_index] as Vector2i
		next_world_pos = WorldManager.cart_to_iso(Vector2(next_grid_pos.x + 0.5, next_grid_pos.y + 0.5))

	# Calculate travel time for this segment
	var segment_distance = current_world_pos.distance_to(next_world_pos)
	var speed_mult = _get_vehicle_speed_multiplier()
	var actual_speed = vehicle_speed * speed_mult
	var segment_travel_time = segment_distance / actual_speed

	# Update progress for this segment
	vehicle.travel_progress += delta / max(segment_travel_time, 0.01)

	# Interpolate position along current segment
	vehicle.position = current_world_pos.lerp(next_world_pos, clampf(vehicle.travel_progress, 0.0, 1.0))

	# Check if reached next waypoint
	if vehicle.travel_progress >= 1.0:
		vehicle.travel_progress = 0.0
		vehicle.path_index += 1

		if is_last_waypoint:
			# Arrived at destination
			var destination = WorldManager.get_facility(connection.destination_id)
			vehicle.state = "at_destination"
			vehicle.position = destination.world_pos


func _handle_direct_travel(vehicle: Dictionary, connection: Dictionary, delta: float) -> void:
	"""Fallback direct travel when no road path exists"""

	var source = WorldManager.get_facility(connection.source_id)
	var destination = WorldManager.get_facility(connection.destination_id)

	# Calculate distance with research-boosted speed
	var distance = source.world_pos.distance_to(destination.world_pos)
	var speed_mult = _get_vehicle_speed_multiplier()
	var actual_speed = vehicle_speed * speed_mult
	var travel_time = distance / actual_speed

	# Update progress
	vehicle.travel_progress += delta / max(travel_time, 0.1)

	# Update position (interpolate between source and destination)
	vehicle.position = source.world_pos.lerp(destination.world_pos, vehicle.travel_progress)

	# Check if arrived
	if vehicle.travel_progress >= 1.0:
		vehicle.state = "at_destination"
		vehicle.position = destination.world_pos


func _handle_delivery(vehicle: Dictionary, connection: Dictionary) -> bool:
	"""Handle vehicle delivery at destination facility.
	Returns true if vehicle should be removed after delivery."""

	var destination_id = connection.destination_id
	var product = connection.product

	# Deliver cargo
	if vehicle.cargo.has(product):
		var quantity = vehicle.cargo[product]
		if ProductionManager.add_item_to_facility(destination_id, product, quantity):
			vehicle.cargo.erase(product)
			print("Vehicle %s delivered %d %s to %s" % [
				vehicle.id, quantity, product, destination_id
			])

			EventBus.cargo_delivered.emit(vehicle.id, {"product": product, "quantity": quantity})

	# Vehicle is removed after delivery - new vehicles auto-dispatch when source has enough
	return true


# ========================================
# FACILITY EVENT HANDLERS
# ========================================

func _on_facility_removed(facility_id: String) -> void:
	"""Remove connections when a facility is removed"""

	var connections_to_remove: Array[String] = []

	for connection_id in connections.keys():
		var connection = connections[connection_id]
		if connection.source_id == facility_id or connection.destination_id == facility_id:
			connections_to_remove.append(connection_id)

	for connection_id in connections_to_remove:
		remove_connection(connection_id)


func _on_road_removed(grid_pos: Vector2i) -> void:
	"""Check if any connection paths are affected by road removal"""

	var connections_to_recalculate: Array[String] = []

	# Check which connections use this road tile
	for connection_id in connection_paths.keys():
		var path: Array = connection_paths[connection_id]
		for waypoint in path:
			if waypoint == grid_pos:
				connections_to_recalculate.append(connection_id)
				break

	# Recalculate paths for affected connections
	for connection_id in connections_to_recalculate:
		var connection = connections.get(connection_id, {})
		if connection.is_empty():
			continue

		# Try to find new path
		var new_path = WorldManager.find_road_path(connection.source_id, connection.destination_id)

		if new_path.is_empty():
			# No valid path - pause the connection
			connection.active = false
			print("Connection %s paused: road connection broken" % connection_id)
			EventBus.notification_posted.emit("Connection paused: road removed", "warning")
			EventBus.connection_updated.emit(connection)
		else:
			# Update the path
			connection_paths[connection_id] = new_path
			# Update all vehicles on this connection
			for vehicle in vehicles.values():
				var conn_id = vehicle.get("connection_id", "")
				if conn_id == connection_id:
					vehicle.path = new_path
					vehicle.path_index = 0
					vehicle.travel_progress = 0.0
			print("Connection %s path recalculated" % connection_id)


# ========================================
# QUERIES
# ========================================

func get_all_connections() -> Array[Dictionary]:
	"""Get all connections"""
	var result: Array[Dictionary] = []
	result.assign(connections.values())
	return result


func get_all_vehicles() -> Array[Dictionary]:
	"""Get all vehicles"""
	var result: Array[Dictionary] = []
	result.assign(vehicles.values())
	return result


func get_vehicle_count() -> int:
	"""Get total number of vehicles"""
	return vehicles.size()


func get_connection_count() -> int:
	"""Get total number of connections"""
	return connections.size()


# ========================================
# DEBUG
# ========================================

func print_logistics_status() -> void:
	"""Debug: Print logistics status"""
	print("=== Logistics Status ===")
	print("Connections: %d" % connections.size())
	print("Active Vehicles: %d" % vehicles.size())

	for connection_id in connections:
		var connection = connections[connection_id]
		var vehicle_count = get_connection_vehicles(connection_id).size()
		print("  Connection %s: %s → %s (%s) [%d vehicles]" % [
			connection_id,
			connection.source_id,
			connection.destination_id,
			connection.product,
			vehicle_count
		])

	for vehicle_id in vehicles:
		var vehicle = vehicles[vehicle_id]
		var cargo_str = ""
		for product in vehicle.cargo:
			cargo_str = "%d %s" % [vehicle.cargo[product], product]
		print("  Vehicle %s: state=%s, cargo=%s" % [
			vehicle_id,
			vehicle.state,
			cargo_str if cargo_str else "(empty)"
		])
