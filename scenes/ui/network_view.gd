extends Control

## NetworkView - Custom drawing control for the Logistics Network panel.
##
## Slice-1 readability + interaction (2026-06-05 evening session):
##   - Each facility node is now labelled with the facility's name.
##   - LMB-drag a node body = move the node on the canvas. The new position
##     is persisted in `_custom_positions` and survives subsequent
##     update_facility_positions() calls (signalled by facility add/remove).
##   - Shift+LMB-drag = create a connection (the previous default — kept so
##     the panel still works as a route-creation surface).
##   - Right-click a connection = delete it.
##
## Future slices (memory: Drinkustry logistics node-editor vision):
##   - Real-time IO sockets reflecting Input Hopper / Output Depot state
##   - Group/annotate nodes; pan/zoom infinite canvas
##   - Per-connection throughput control

signal facility_clicked(facility_id: String)
signal facility_drag_started(facility_id: String)
signal facility_drag_ended(target_facility_id: String)
signal connection_right_clicked(connection_id: String)

const NODE_RADIUS: float = 22.0
const LABEL_FONT_SIZE: int = 12
const LABEL_OFFSET_Y: float = NODE_RADIUS + 14.0  # gap between node bottom and label baseline

const NODE_COLORS: Dictionary = {
	"barley_field": Color(0.8, 0.7, 0.3),
	"wheat_farm": Color(0.9, 0.75, 0.4),
	"grain_mill": Color(0.6, 0.5, 0.4),
	"brewery": Color(0.4, 0.3, 0.2),
	"distillery": Color(0.5, 0.35, 0.25),
	"packaging_plant": Color(0.3, 0.5, 0.7),
	"storage_warehouse": Color(0.5, 0.5, 0.5),
	"farmhouse": Color(0.6, 0.4, 0.3),
	"default": Color(0.4, 0.4, 0.4),
}

const CONNECTION_COLOR: Color = Color(0.3, 0.7, 0.3, 0.8)
const CONNECTION_HOVER_COLOR: Color = Color(0.8, 0.3, 0.3, 0.8)
const DRAG_LINE_COLOR: Color = Color(0.5, 0.8, 0.5, 0.6)

# Node positions currently rendered: { facility_id: Vector2 }.
# Cleared and rebuilt by update_facility_positions(); custom overrides
# from `_custom_positions` take precedence.
var facility_nodes: Dictionary = {}

# Player-set positions, persisted across update_facility_positions calls
# (which run when facilities are added/removed via EventBus). Cleared per
# facility when that facility is removed.
var _custom_positions: Dictionary = {}

# Interaction state
# Connection drag (Shift+LMB): a temporary "rubber band" line is drawn from
# the source node to the cursor; on release on another node, a connection is
# created via the panel's facility_drag_ended handler.
var is_connecting: bool = false
# Move drag (LMB): the node itself follows the cursor; on release the
# release position is committed to `_custom_positions`.
var is_moving: bool = false
# Common drag bookkeeping
var drag_start_facility: String = ""
var drag_current_pos: Vector2 = Vector2.ZERO

# Hover state — drives node/connection highlighting
var hovered_facility: String = ""
var hovered_connection: String = ""

# Bounds (used by the auto-layout fallback when no custom position exists)
var view_bounds: Rect2 = Rect2()
var world_bounds: Rect2 = Rect2()


func _draw() -> void:
	_draw_connections()

	# Rubber-band line for the connection drag (Shift+LMB).
	if is_connecting and not drag_start_facility.is_empty():
		var start_pos: Vector2 = facility_nodes.get(drag_start_facility, Vector2.ZERO)
		draw_line(start_pos, drag_current_pos, DRAG_LINE_COLOR, 3.0)

	_draw_facility_nodes()


func _draw_connections() -> void:
	for connection in LogisticsManager.connections.values():
		var source_id: String = connection.source_id
		var dest_id: String = connection.destination_id

		if not facility_nodes.has(source_id) or not facility_nodes.has(dest_id):
			continue

		var start_pos: Vector2 = facility_nodes[source_id]
		var end_pos: Vector2 = facility_nodes[dest_id]

		var color: Color = CONNECTION_HOVER_COLOR if hovered_connection == connection.id else CONNECTION_COLOR

		draw_line(start_pos, end_pos, color, 3.0)

		# Arrow head
		var direction: Vector2 = (end_pos - start_pos).normalized()
		var arrow_pos: Vector2 = start_pos.lerp(end_pos, 0.7)
		var perpendicular := Vector2(-direction.y, direction.x)
		var arrow_size: float = 8.0

		var arrow_points := PackedVector2Array([
			arrow_pos + direction * arrow_size,
			arrow_pos - direction * arrow_size * 0.5 + perpendicular * arrow_size * 0.6,
			arrow_pos - direction * arrow_size * 0.5 - perpendicular * arrow_size * 0.6,
		])
		draw_polygon(arrow_points, [color])


func _draw_facility_nodes() -> void:
	var font: Font = ThemeDB.fallback_font
	for facility_id in facility_nodes:
		var pos: Vector2 = facility_nodes[facility_id]
		var facility: Dictionary = WorldManager.get_facility(facility_id)
		if facility.is_empty():
			continue

		var color: Color = NODE_COLORS.get(facility.type, NODE_COLORS["default"])

		if hovered_facility == facility_id:
			color = color.lightened(0.3)
		if drag_start_facility == facility_id:
			# Different tints for the two drag intents so the player can tell
			# which mode they're in at a glance.
			color = Color(0.3, 0.6, 0.95) if is_moving else Color(0.3, 0.8, 0.3)

		draw_circle(pos, NODE_RADIUS, color)
		draw_arc(pos, NODE_RADIUS, 0.0, TAU, 32, Color.WHITE, 2.0)

		# Facility name label centered below the node.
		var def: Dictionary = DataManager.get_facility_data(facility.type)
		var name_text: String = String(def.get("name", facility.type))
		var text_size: Vector2 = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var label_pos := Vector2(pos.x - text_size.x / 2.0, pos.y + LABEL_OFFSET_Y)
		# Soft drop shadow for readability over busy backgrounds.
		draw_string(font, label_pos + Vector2(1, 1), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0, 0, 0, 0.7))
		draw_string(font, label_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color.WHITE)


func update_facility_positions() -> void:
	"""Lay out the facility nodes. Custom positions (set by the player by
	dragging nodes) take precedence; everything else gets an auto-computed
	position from its world-map grid coordinates."""
	# Drop custom positions for facilities that no longer exist.
	for fid in _custom_positions.keys():
		if not WorldManager.facilities.has(fid):
			_custom_positions.erase(fid)

	facility_nodes.clear()

	var facilities: Array = WorldManager.facilities.values().filter(func(f):
		var facility_def: Dictionary = DataManager.get_facility_data(f.type)
		return not facility_def.get("is_field", false)
	)

	if facilities.is_empty():
		return

	# Compute world bounds for the auto-layout fallback.
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)

	for facility in facilities:
		var grid_pos := Vector2(facility.grid_pos)
		min_pos.x = min(min_pos.x, grid_pos.x)
		min_pos.y = min(min_pos.y, grid_pos.y)
		max_pos.x = max(max_pos.x, grid_pos.x)
		max_pos.y = max(max_pos.y, grid_pos.y)

	min_pos -= Vector2(2, 2)
	max_pos += Vector2(2, 2)
	world_bounds = Rect2(min_pos, max_pos - min_pos)

	var padding: float = NODE_RADIUS + 10.0
	view_bounds = Rect2(Vector2(padding, padding), size - Vector2(padding * 2.0, padding * 2.0))

	for facility in facilities:
		var fid: String = facility.id
		if _custom_positions.has(fid):
			facility_nodes[fid] = _custom_positions[fid]
		else:
			facility_nodes[fid] = _world_to_panel(Vector2(facility.grid_pos))


func _world_to_panel(world_pos: Vector2) -> Vector2:
	if world_bounds.size.x == 0 or world_bounds.size.y == 0:
		return view_bounds.position + view_bounds.size / 2.0
	var normalized: Vector2 = (world_pos - world_bounds.position) / world_bounds.size
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
		var start_pos: Vector2 = facility_nodes[connection.source_id]
		var end_pos: Vector2 = facility_nodes[connection.destination_id]
		if _point_to_line_distance(local_pos, start_pos, end_pos) < 10.0:
			return connection.id
	return ""


func _point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec: Vector2 = line_end - line_start
	var point_vec: Vector2 = point - line_start
	var line_len: float = line_vec.length()
	if line_len == 0.0:
		return point_vec.length()
	var t: float = clampf(point_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	return point.distance_to(line_start + line_vec * t)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var local_pos: Vector2 = mb.position

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var facility_id: String = get_facility_at_pos(local_pos)
				if not facility_id.is_empty():
					drag_start_facility = facility_id
					drag_current_pos = local_pos
					# Shift = connect; bare LMB = move the node.
					is_connecting = mb.shift_pressed
					is_moving = not mb.shift_pressed
					if is_connecting:
						facility_drag_started.emit(facility_id)
			else:
				if is_connecting:
					var target: String = get_facility_at_pos(local_pos)
					facility_drag_ended.emit(target)
				elif is_moving and not drag_start_facility.is_empty():
					# Commit the move. Clamp to the panel rect so a node can't
					# disappear off-screen on a careless drag.
					var clamped := Vector2(
						clampf(local_pos.x, NODE_RADIUS, size.x - NODE_RADIUS),
						clampf(local_pos.y, NODE_RADIUS, size.y - NODE_RADIUS),
					)
					_custom_positions[drag_start_facility] = clamped
					facility_nodes[drag_start_facility] = clamped
				is_connecting = false
				is_moving = false
				drag_start_facility = ""
			queue_redraw()

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not hovered_connection.is_empty():
				connection_right_clicked.emit(hovered_connection)

	elif event is InputEventMouseMotion:
		var local_pos: Vector2 = event.position
		if is_connecting:
			drag_current_pos = local_pos
		elif is_moving and not drag_start_facility.is_empty():
			# Live-preview the node at the cursor so the move feels physical.
			facility_nodes[drag_start_facility] = local_pos
		hovered_facility = get_facility_at_pos(local_pos)
		hovered_connection = "" if not hovered_facility.is_empty() else get_connection_at_pos(local_pos)
		queue_redraw()
