extends Control

## NetworkView - Custom drawing control for logistics network visualization

signal facility_clicked(facility_id: String)
signal facility_drag_started(facility_id: String)
signal facility_drag_ended(target_facility_id: String)
signal connection_right_clicked(connection_id: String)

const NODE_RADIUS: float = 20.0
const NODE_COLORS: Dictionary = {
	"barley_field": Color(0.8, 0.7, 0.3),
	"wheat_farm": Color(0.9, 0.75, 0.4),
	"grain_mill": Color(0.6, 0.5, 0.4),
	"brewery": Color(0.4, 0.3, 0.2),
	"distillery": Color(0.5, 0.35, 0.25),
	"packaging_plant": Color(0.3, 0.5, 0.7),
	"storage_warehouse": Color(0.5, 0.5, 0.5),
	"farmhouse": Color(0.6, 0.4, 0.3),
	"default": Color(0.4, 0.4, 0.4)
}

const CONNECTION_COLOR: Color = Color(0.3, 0.7, 0.3, 0.8)
const CONNECTION_HOVER_COLOR: Color = Color(0.8, 0.3, 0.3, 0.8)
const DRAG_LINE_COLOR: Color = Color(0.5, 0.8, 0.5, 0.6)

# Node positions: { facility_id: Vector2 }
var facility_nodes: Dictionary = {}

# Drag state
var is_dragging: bool = false
var drag_start_facility: String = ""
var drag_current_pos: Vector2 = Vector2.ZERO

# Hover state
var hovered_facility: String = ""
var hovered_connection: String = ""

# Bounds
var view_bounds: Rect2 = Rect2()
var world_bounds: Rect2 = Rect2()


func _draw() -> void:
	# Draw connections first
	_draw_connections()

	# Draw drag line
	if is_dragging and not drag_start_facility.is_empty():
		var start_pos = facility_nodes.get(drag_start_facility, Vector2.ZERO)
		draw_line(start_pos, drag_current_pos, DRAG_LINE_COLOR, 3.0)

	# Draw facility nodes
	_draw_facility_nodes()


func _draw_connections() -> void:
	for connection in LogisticsManager.connections.values():
		var source_id = connection.source_id
		var dest_id = connection.destination_id

		if not facility_nodes.has(source_id) or not facility_nodes.has(dest_id):
			continue

		var start_pos = facility_nodes[source_id]
		var end_pos = facility_nodes[dest_id]

		var color = CONNECTION_HOVER_COLOR if hovered_connection == connection.id else CONNECTION_COLOR

		draw_line(start_pos, end_pos, color, 3.0)

		# Arrow head
		var direction = (end_pos - start_pos).normalized()
		var arrow_pos = start_pos.lerp(end_pos, 0.7)
		var perpendicular = Vector2(-direction.y, direction.x)
		var arrow_size = 8.0

		var arrow_points = PackedVector2Array([
			arrow_pos + direction * arrow_size,
			arrow_pos - direction * arrow_size * 0.5 + perpendicular * arrow_size * 0.6,
			arrow_pos - direction * arrow_size * 0.5 - perpendicular * arrow_size * 0.6
		])
		draw_polygon(arrow_points, [color])


func _draw_facility_nodes() -> void:
	for facility_id in facility_nodes:
		var pos = facility_nodes[facility_id]
		var facility = WorldManager.get_facility(facility_id)
		if facility.is_empty():
			continue

		var color = NODE_COLORS.get(facility.type, NODE_COLORS["default"])

		if hovered_facility == facility_id:
			color = color.lightened(0.3)
		if drag_start_facility == facility_id:
			color = Color(0.3, 0.8, 0.3)

		draw_circle(pos, NODE_RADIUS, color)
		draw_arc(pos, NODE_RADIUS, 0, TAU, 32, Color.WHITE, 2.0)


func update_facility_positions() -> void:
	facility_nodes.clear()

	var facilities = WorldManager.facilities.values().filter(func(f):
		var facility_def = DataManager.get_facility_data(f.type)
		return not facility_def.get("is_field", false)
	)

	if facilities.is_empty():
		return

	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)

	for facility in facilities:
		var grid_pos = Vector2(facility.grid_pos)
		min_pos.x = min(min_pos.x, grid_pos.x)
		min_pos.y = min(min_pos.y, grid_pos.y)
		max_pos.x = max(max_pos.x, grid_pos.x)
		max_pos.y = max(max_pos.y, grid_pos.y)

	min_pos -= Vector2(2, 2)
	max_pos += Vector2(2, 2)
	world_bounds = Rect2(min_pos, max_pos - min_pos)

	var padding = NODE_RADIUS + 10
	view_bounds = Rect2(Vector2(padding, padding), size - Vector2(padding * 2, padding * 2))

	for facility in facilities:
		var grid_pos = Vector2(facility.grid_pos)
		facility_nodes[facility.id] = _world_to_panel(grid_pos)


func _world_to_panel(world_pos: Vector2) -> Vector2:
	if world_bounds.size.x == 0 or world_bounds.size.y == 0:
		return view_bounds.position + view_bounds.size / 2
	var normalized = (world_pos - world_bounds.position) / world_bounds.size
	return view_bounds.position + normalized * view_bounds.size


func get_facility_at_pos(local_pos: Vector2) -> String:
	for facility_id in facility_nodes:
		if local_pos.distance_to(facility_nodes[facility_id]) <= NODE_RADIUS:
			return facility_id
	return ""


func get_connection_at_pos(local_pos: Vector2) -> String:
	for connection in LogisticsManager.connections.values():
		if not facility_nodes.has(connection.source_id) or not facility_nodes.has(connection.destination_id):
			continue
		var start_pos = facility_nodes[connection.source_id]
		var end_pos = facility_nodes[connection.destination_id]
		if _point_to_line_distance(local_pos, start_pos, end_pos) < 10.0:
			return connection.id
	return ""


func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len = line_vec.length()
	if line_len == 0:
		return point_vec.length()
	var t = clampf(point_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	return point.distance_to(line_start + line_vec * t)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var local_pos = event.position

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var facility_id = get_facility_at_pos(local_pos)
				if not facility_id.is_empty():
					is_dragging = true
					drag_start_facility = facility_id
					drag_current_pos = local_pos
					facility_drag_started.emit(facility_id)
			else:
				if is_dragging:
					var target = get_facility_at_pos(local_pos)
					facility_drag_ended.emit(target)
					is_dragging = false
					drag_start_facility = ""
			queue_redraw()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not hovered_connection.is_empty():
				connection_right_clicked.emit(hovered_connection)

	elif event is InputEventMouseMotion:
		var local_pos = event.position
		if is_dragging:
			drag_current_pos = local_pos
		hovered_facility = get_facility_at_pos(local_pos)
		hovered_connection = "" if not hovered_facility.is_empty() else get_connection_at_pos(local_pos)
		queue_redraw()
