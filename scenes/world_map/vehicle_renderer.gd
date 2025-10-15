extends Node2D

## VehicleRenderer - Visualizes vehicles moving along routes
##
## Creates sprite representations of vehicles and animates them along route paths

# Dictionary of vehicle visuals: { vehicle_id: vehicle_node }
var vehicle_visuals: Dictionary = {}

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Connect to vehicle events
	EventBus.vehicle_spawned.connect(_on_vehicle_spawned)
	EventBus.vehicle_removed.connect(_on_vehicle_removed)

	# Create visuals for existing vehicles
	_create_existing_vehicle_visuals()


func _process(_delta: float) -> void:
	# Update vehicle positions based on LogisticsManager state
	_update_vehicle_positions()


# ========================================
# VEHICLE VISUAL CREATION
# ========================================

func _create_existing_vehicle_visuals() -> void:
	"""Create visuals for all existing vehicles"""
	for vehicle_id in LogisticsManager.vehicles:
		var vehicle = LogisticsManager.vehicles[vehicle_id]
		_create_vehicle_visual(vehicle_id, vehicle)


func _create_vehicle_visual(vehicle_id: String, vehicle: Dictionary) -> void:
	"""Create a visual representation of a vehicle"""
	if vehicle_visuals.has(vehicle_id):
		return  # Already exists

	var vehicle_node = Node2D.new()
	vehicle_node.name = "vehicle_%s" % vehicle_id

	# Create sprite (using colored rectangle as placeholder)
	var sprite = _create_vehicle_sprite()
	vehicle_node.add_child(sprite)

	# Add label showing cargo
	var label = Label.new()
	label.text = ""  # Will be updated in _update_vehicle_positions
	label.position = Vector2(-20, -30)
	label.add_theme_font_size_override("font_size", 10)
	vehicle_node.add_child(label)

	vehicle_visuals[vehicle_id] = vehicle_node
	add_child(vehicle_node)

	print("Vehicle visual created: %s" % vehicle_id)


func _create_vehicle_sprite() -> Polygon2D:
	"""Create a simple vehicle sprite (placeholder)"""
	var vehicle = Polygon2D.new()
	vehicle.color = Color(0.9, 0.7, 0.2, 1.0)  # Yellow/orange

	# Simple truck shape (rectangle with cab)
	var points = PackedVector2Array([
		Vector2(-12, -6),   # Back left
		Vector2(-12, 6),    # Back right
		Vector2(8, 6),      # Front right bottom
		Vector2(8, 3),      # Cab right
		Vector2(12, 3),     # Cab front right
		Vector2(12, -3),    # Cab front left
		Vector2(8, -3),     # Cab left
		Vector2(8, -6),     # Front left bottom
	])

	vehicle.polygon = points
	vehicle.z_index = 5  # Draw above routes and facilities

	return vehicle


# ========================================
# VEHICLE POSITION UPDATES
# ========================================

func _update_vehicle_positions() -> void:
	"""Update all vehicle positions based on their current state"""
	for vehicle_id in vehicle_visuals.keys():
		var vehicle = LogisticsManager.vehicles.get(vehicle_id, {})
		if vehicle.is_empty():
			continue

		var vehicle_node = vehicle_visuals[vehicle_id]
		var label = vehicle_node.get_child(1) if vehicle_node.get_child_count() > 1 else null

		# Get vehicle state
		var state = vehicle.get("state", "")
		var route_id = vehicle.get("route_id", "")

		# Update position based on state
		match state:
			"at_source":
				_position_at_facility(vehicle_node, vehicle, route_id, true)
				if label:
					label.text = "Loading..."

			"traveling":
				_position_traveling(vehicle_node, vehicle, route_id)
				var cargo = vehicle.get("cargo", {})
				if label and not cargo.is_empty():
					var product = cargo.keys()[0]
					var quantity = cargo[product]
					label.text = "%d %s" % [quantity, product]

			"at_destination":
				_position_at_facility(vehicle_node, vehicle, route_id, false)
				if label:
					label.text = "Unloading..."


func _position_at_facility(vehicle_node: Node2D, vehicle: Dictionary, route_id: String, is_source: bool) -> void:
	"""Position vehicle at a facility"""
	var route = LogisticsManager.routes.get(route_id, {})
	if route.is_empty():
		return

	var facility_id = route.get("source" if is_source else "destination", "")
	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return

	# Position at facility center with small offset
	var facility_pos = _get_facility_center_position(facility)
	vehicle_node.position = facility_pos + Vector2(20, 20)  # Offset so not overlapping facility


func _position_traveling(vehicle_node: Node2D, vehicle: Dictionary, route_id: String) -> void:
	"""Position vehicle traveling along route"""
	var route = LogisticsManager.routes.get(route_id, {})
	if route.is_empty():
		return

	var source_facility = WorldManager.get_facility(route.get("source", ""))
	var dest_facility = WorldManager.get_facility(route.get("destination", ""))

	if source_facility.is_empty() or dest_facility.is_empty():
		return

	var source_pos = _get_facility_center_position(source_facility)
	var dest_pos = _get_facility_center_position(dest_facility)

	# Get travel progress (0.0 to 1.0)
	var travel_timer = vehicle.get("travel_timer", 0.0)
	var travel_time = vehicle.get("travel_time", 1.0)
	var progress = 1.0 - (travel_timer / travel_time) if travel_time > 0 else 0.0

	# Interpolate position along route
	vehicle_node.position = source_pos.lerp(dest_pos, progress)

	# Rotate vehicle to face direction of travel
	var direction = (dest_pos - source_pos).normalized()
	var angle = atan2(direction.y, direction.x)
	vehicle_node.rotation = angle


func _get_facility_center_position(facility: Dictionary) -> Vector2:
	"""Get the center position of a facility in world space"""
	var grid_pos = facility.get("grid_pos", Vector2i.ZERO)
	var facility_def = DataManager.get_facility_data(facility.type)
	var size = Vector2i(
		facility_def.get("size", [1, 1])[0],
		facility_def.get("size", [1, 1])[1]
	)

	# Calculate center in grid coordinates
	var center_grid_pos = Vector2(
		grid_pos.x + size.x / 2.0,
		grid_pos.y + size.y / 2.0
	)

	# Convert to isometric world space
	return WorldManager.grid_to_world(center_grid_pos)


# ========================================
# EVENT HANDLERS
# ========================================

func _on_vehicle_spawned(vehicle: Dictionary) -> void:
	"""Handle vehicle spawn"""
	var vehicle_id = vehicle.get("id", "")
	if vehicle_id.is_empty():
		return

	_create_vehicle_visual(vehicle_id, vehicle)


func _on_vehicle_removed(vehicle_id: String) -> void:
	"""Handle vehicle removal"""
	if vehicle_visuals.has(vehicle_id):
		vehicle_visuals[vehicle_id].queue_free()
		vehicle_visuals.erase(vehicle_id)
		print("Vehicle visual removed: %s" % vehicle_id)
