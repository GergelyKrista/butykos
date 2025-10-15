extends Node

## LogisticsManager - Routes, vehicles, and cargo transport
##
## Manages transportation of goods between facilities via routes and vehicles.
## Handles pickup, delivery, and vehicle movement.

# ========================================
# STATE
# ========================================

# Dictionary of routes: { route_id: route_data }
var routes: Dictionary = {}

# Dictionary of vehicles: { vehicle_id: vehicle_data }
var vehicles: Dictionary = {}

# Counter for generating unique IDs
var _next_route_id: int = 1
var _next_vehicle_id: int = 1

# ========================================
# CONFIGURATION
# ========================================

var vehicle_speed: float = 50.0  # pixels per second
var pickup_amount: int = 10      # units to pickup per trip
var instant_delivery: bool = false  # For testing: instant delivery

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("LogisticsManager initialized")

	# Connect to facility events
	EventBus.facility_removed.connect(_on_facility_removed)


func _process(delta: float) -> void:
	_update_vehicles(delta)


# ========================================
# ROUTE MANAGEMENT
# ========================================

func create_route(source_id: String, destination_id: String, product: String) -> String:
	"""Create a route between two facilities for a specific product"""

	# Validate facilities exist
	var source = WorldManager.get_facility(source_id)
	var destination = WorldManager.get_facility(destination_id)

	if source.is_empty() or destination.is_empty():
		push_error("Cannot create route: invalid facilities")
		return ""

	# Generate route ID
	var route_id = "route_%d" % _next_route_id
	_next_route_id += 1

	# Create route data
	var route = {
		"id": route_id,
		"source_id": source_id,
		"destination_id": destination_id,
		"product": product,
		"active": true,
		"created_date": GameManager.current_date.duplicate()
	}

	routes[route_id] = route

	# Create a vehicle for this route
	var vehicle_id = _create_vehicle(route_id, source_id, destination_id)
	route.vehicle_id = vehicle_id

	print("Route created: %s → %s (%s)" % [source_id, destination_id, product])
	EventBus.route_created.emit(route)

	return route_id


func remove_route(route_id: String) -> bool:
	"""Remove a route and its vehicle"""

	if not routes.has(route_id):
		return false

	var route = routes[route_id]

	# Remove vehicle
	if route.has("vehicle_id"):
		_remove_vehicle(route.vehicle_id)

	# Remove route
	routes.erase(route_id)

	print("Route removed: %s" % route_id)
	EventBus.route_removed.emit(route_id)

	return true


func get_route(route_id: String) -> Dictionary:
	"""Get route data"""
	return routes.get(route_id, {})


func get_routes_from_facility(facility_id: String) -> Array[Dictionary]:
	"""Get all routes originating from a facility"""
	var result: Array[Dictionary] = []
	for route in routes.values():
		if route.source_id == facility_id:
			result.append(route)
	return result


func get_routes_to_facility(facility_id: String) -> Array[Dictionary]:
	"""Get all routes going to a facility"""
	var result: Array[Dictionary] = []
	for route in routes.values():
		if route.destination_id == facility_id:
			result.append(route)
	return result


# ========================================
# VEHICLE MANAGEMENT
# ========================================

func _create_vehicle(route_id: String, source_id: String, destination_id: String) -> String:
	"""Create a vehicle for a route"""

	var vehicle_id = "vehicle_%d" % _next_vehicle_id
	_next_vehicle_id += 1

	var source = WorldManager.get_facility(source_id)
	var destination = WorldManager.get_facility(destination_id)

	var vehicle = {
		"id": vehicle_id,
		"route_id": route_id,
		"source_id": source_id,
		"destination_id": destination_id,
		"state": "at_source",  # at_source, traveling, at_destination
		"position": source.world_pos,
		"cargo": {},
		"travel_progress": 0.0  # 0.0 to 1.0
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

	for vehicle_id in vehicles.keys():
		var vehicle = vehicles[vehicle_id]
		var route = routes.get(vehicle.route_id, {})

		if route.is_empty() or not route.get("active", false):
			continue

		match vehicle.state:
			"at_source":
				_handle_pickup(vehicle, route)
			"traveling":
				_handle_travel(vehicle, route, delta)
			"at_destination":
				_handle_delivery(vehicle, route)


func _handle_pickup(vehicle: Dictionary, route: Dictionary) -> void:
	"""Handle vehicle pickup at source facility"""

	var source_id = route.source_id
	var product = route.product

	# Check if source has product available
	var available = ProductionManager.get_inventory_item(source_id, product)

	if available >= pickup_amount:
		# Pickup cargo
		if ProductionManager.remove_item_from_facility(source_id, product, pickup_amount):
			vehicle.cargo[product] = pickup_amount
			vehicle.state = "traveling"
			vehicle.travel_progress = 0.0
			print("Vehicle %s picked up %d %s from %s" % [
				vehicle.id, pickup_amount, product, source_id
			])


func _handle_travel(vehicle: Dictionary, route: Dictionary, delta: float) -> void:
	"""Handle vehicle traveling between facilities"""

	if instant_delivery:
		# Skip travel animation for testing
		vehicle.travel_progress = 1.0

	var source = WorldManager.get_facility(route.source_id)
	var destination = WorldManager.get_facility(route.destination_id)

	# Calculate distance
	var distance = source.world_pos.distance_to(destination.world_pos)
	var travel_time = distance / vehicle_speed

	# Update progress
	vehicle.travel_progress += delta / max(travel_time, 0.1)

	# Update position (interpolate between source and destination)
	vehicle.position = source.world_pos.lerp(destination.world_pos, vehicle.travel_progress)

	# Check if arrived
	if vehicle.travel_progress >= 1.0:
		vehicle.state = "at_destination"
		vehicle.position = destination.world_pos


func _handle_delivery(vehicle: Dictionary, route: Dictionary) -> void:
	"""Handle vehicle delivery at destination facility"""

	var destination_id = route.destination_id
	var product = route.product

	# Deliver cargo
	if vehicle.cargo.has(product):
		var quantity = vehicle.cargo[product]
		if ProductionManager.add_item_to_facility(destination_id, product, quantity):
			vehicle.cargo.erase(product)
			print("Vehicle %s delivered %d %s to %s" % [
				vehicle.id, quantity, product, destination_id
			])

			EventBus.cargo_delivered.emit(vehicle.id, {"product": product, "quantity": quantity})

	# Return to source
	vehicle.state = "at_source"
	vehicle.travel_progress = 0.0

	var source = WorldManager.get_facility(route.source_id)
	vehicle.position = source.world_pos


# ========================================
# FACILITY EVENT HANDLERS
# ========================================

func _on_facility_removed(facility_id: String) -> void:
	"""Remove routes when a facility is removed"""

	var routes_to_remove: Array[String] = []

	for route_id in routes.keys():
		var route = routes[route_id]
		if route.source_id == facility_id or route.destination_id == facility_id:
			routes_to_remove.append(route_id)

	for route_id in routes_to_remove:
		remove_route(route_id)


# ========================================
# QUERIES
# ========================================

func get_all_routes() -> Array[Dictionary]:
	"""Get all routes"""
	var result: Array[Dictionary] = []
	result.assign(routes.values())
	return result


func get_all_vehicles() -> Array[Dictionary]:
	"""Get all vehicles"""
	var result: Array[Dictionary] = []
	result.assign(vehicles.values())
	return result


func get_vehicle_count() -> int:
	"""Get total number of vehicles"""
	return vehicles.size()


func get_route_count() -> int:
	"""Get total number of routes"""
	return routes.size()


# ========================================
# DEBUG
# ========================================

func print_logistics_status() -> void:
	"""Debug: Print logistics status"""
	print("=== Logistics Status ===")
	print("Routes: %d" % routes.size())
	print("Vehicles: %d" % vehicles.size())

	for route_id in routes:
		var route = routes[route_id]
		print("  Route %s: %s → %s (%s)" % [
			route_id,
			route.source_id,
			route.destination_id,
			route.product
		])

	for vehicle_id in vehicles:
		var vehicle = vehicles[vehicle_id]
		print("  Vehicle %s: state=%s, cargo=%s, progress=%.1f%%" % [
			vehicle_id,
			vehicle.state,
			str(vehicle.cargo),
			vehicle.travel_progress * 100
		])
