extends Node2D

## RouteRenderer - Draws connection lines between facilities
##
## Visualizes logistics connections on the world map with directional arrows

# TODO(Phase 10 catchment work): rename file route_renderer.gd → connection_renderer.gd as part of visual-layer restructure.

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Connect to connection events
	EventBus.connection_created.connect(_on_connection_created)
	EventBus.connection_removed.connect(_on_connection_removed)

	# Routes are a Logistics-corp surface — non-Logistics corps don't see them
	# on the world map. Listen for corp changes and refresh visibility.
	EventBus.active_corp_changed.connect(_on_active_corp_changed)
	_apply_corp_visibility()

	# Redraw all existing connections
	_redraw_all_connections()


# ========================================
# CORP VISIBILITY
# ========================================

func _apply_corp_visibility() -> void:
	"""Show route lines only to the Logistics corp (and to `single`, the
	dev/legacy default, so testing without the corp switcher still works)."""
	var active: String = GameManager.active_corp_id
	visible = active == GameManager.CORP_LOGISTICS or active == GameManager.CORP_SINGLE


func _on_active_corp_changed(_old_corp_id: String, _new_corp_id: String) -> void:
	_apply_corp_visibility()


# ========================================
# CONNECTION VISUALIZATION
# ========================================

func _redraw_all_connections() -> void:
	"""Clear and redraw all connections"""
	# Clear existing visuals
	for child in get_children():
		child.queue_free()

	# Draw each connection
	for connection_id in LogisticsManager.connections:
		var connection = LogisticsManager.connections[connection_id]
		_create_connection_visual(connection_id, connection)


func _create_connection_visual(connection_id: String, connection: Dictionary) -> void:
	"""Create visual representation of a connection"""
	var source_id = connection.get("source_id", "")
	var destination_id = connection.get("destination_id", "")

	if source_id.is_empty() or destination_id.is_empty():
		return

	var source_facility = WorldManager.get_facility(source_id)
	var destination_facility = WorldManager.get_facility(destination_id)

	if source_facility.is_empty() or destination_facility.is_empty():
		return

	# Get facility positions (center of facilities in isometric space)
	var source_pos = _get_facility_center_position(source_facility)
	var dest_pos = _get_facility_center_position(destination_facility)

	# Create connection line
	var line = Line2D.new()
	line.name = "connection_line_%s" % connection_id
	line.width = 3.0
	line.default_color = Color(0.2, 0.6, 1.0, 0.8)  # Blue
	line.z_index = -1  # Draw behind facilities

	# Add points
	line.add_point(source_pos)
	line.add_point(dest_pos)

	add_child(line)

	# Add directional arrows along the connection
	_add_connection_arrows(connection_id, source_pos, dest_pos)


func _add_connection_arrows(connection_id: String, start_pos: Vector2, end_pos: Vector2) -> void:
	"""Add directional arrow indicators along the connection"""
	var direction = (end_pos - start_pos).normalized()
	var distance = start_pos.distance_to(end_pos)

	# Add arrow at 1/3 and 2/3 along the connection
	var arrow_positions = [0.33, 0.66]

	for t in arrow_positions:
		var arrow_pos = start_pos.lerp(end_pos, t)

		var arrow = Polygon2D.new()
		arrow.name = "connection_arrow_%s_%d" % [connection_id, int(t * 100)]
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

func _on_connection_created(connection: Dictionary) -> void:
	"""Handle connection creation"""
	var connection_id = connection.get("id", "")
	if connection_id.is_empty():
		return

	_create_connection_visual(connection_id, connection)
	print("Connection visual created: %s" % connection_id)


func _on_connection_removed(connection_id: String) -> void:
	"""Handle connection removal"""
	# Remove all visuals for this connection
	for child in get_children():
		if connection_id in child.name:
			child.queue_free()

	print("Connection visual removed: %s" % connection_id)
