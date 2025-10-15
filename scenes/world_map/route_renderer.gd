extends Node2D

## RouteRenderer - Draws route lines between facilities
##
## Visualizes logistics routes on the world map with directional arrows

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Connect to route events
	EventBus.route_created.connect(_on_route_created)
	EventBus.route_removed.connect(_on_route_removed)

	# Redraw all existing routes
	_redraw_all_routes()


# ========================================
# ROUTE VISUALIZATION
# ========================================

func _redraw_all_routes() -> void:
	"""Clear and redraw all routes"""
	# Clear existing visuals
	for child in get_children():
		child.queue_free()

	# Draw each route
	for route_id in LogisticsManager.routes:
		var route = LogisticsManager.routes[route_id]
		_create_route_visual(route_id, route)


func _create_route_visual(route_id: String, route: Dictionary) -> void:
	"""Create visual representation of a route"""
	var source_id = route.get("source", "")
	var destination_id = route.get("destination", "")

	if source_id.is_empty() or destination_id.is_empty():
		return

	var source_facility = WorldManager.get_facility(source_id)
	var destination_facility = WorldManager.get_facility(destination_id)

	if source_facility.is_empty() or destination_facility.is_empty():
		return

	# Get facility positions (center of facilities in isometric space)
	var source_pos = _get_facility_center_position(source_facility)
	var dest_pos = _get_facility_center_position(destination_facility)

	# Create route line
	var line = Line2D.new()
	line.name = "route_line_%s" % route_id
	line.width = 3.0
	line.default_color = Color(0.2, 0.6, 1.0, 0.8)  # Blue
	line.z_index = -1  # Draw behind facilities

	# Add points
	line.add_point(source_pos)
	line.add_point(dest_pos)

	add_child(line)

	# Add directional arrows along the route
	_add_route_arrows(route_id, source_pos, dest_pos)


func _add_route_arrows(route_id: String, start_pos: Vector2, end_pos: Vector2) -> void:
	"""Add directional arrow indicators along the route"""
	var direction = (end_pos - start_pos).normalized()
	var distance = start_pos.distance_to(end_pos)

	# Add arrow at 1/3 and 2/3 along the route
	var arrow_positions = [0.33, 0.66]

	for t in arrow_positions:
		var arrow_pos = start_pos.lerp(end_pos, t)

		var arrow = Polygon2D.new()
		arrow.name = "route_arrow_%s_%d" % [route_id, int(t * 100)]
		arrow.color = Color(1.0, 0.8, 0.2, 0.9)  # Orange/yellow
		arrow.position = arrow_pos
		arrow.z_index = -1

		# Create arrow shape pointing in direction
		var arrow_size = 12.0
		var angle = atan2(direction.y, direction.x)
		var tip = Vector2(arrow_size, 0).rotated(angle)
		var left = Vector2(-arrow_size / 2, -arrow_size / 2).rotated(angle)
		var right = Vector2(-arrow_size / 2, arrow_size / 2).rotated(angle)

		arrow.polygon = PackedVector2Array([tip, left, right])
		add_child(arrow)


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

func _on_route_created(route: Dictionary) -> void:
	"""Handle route creation"""
	var route_id = route.get("id", "")
	if route_id.is_empty():
		return

	_create_route_visual(route_id, route)
	print("Route visual created: %s" % route_id)


func _on_route_removed(route_id: String) -> void:
	"""Handle route removal"""
	# Remove all visuals for this route
	for child in get_children():
		if route_id in child.name:
			child.queue_free()

	print("Route visual removed: %s" % route_id)
