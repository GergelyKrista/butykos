extends Control

## NetworkView - Custom drawing control for the Logistics Network panel.
##
## Slice-1 readability + interaction (2026-06-05 evening session):
##   - Each facility node is labelled with the facility's name.
##   - LMB-drag a node body = move the node on the canvas.
##   - Shift+LMB-drag = create a connection.
##   - Right-click a connection = delete it.
##
## Slice-1.5 canvas (2026-06-05 evening, second pass):
##   - Mouse wheel = zoom in/out around the cursor (canvas zoom 0.25–4x).
##   - Middle-click drag = pan the canvas.
##   - Dim background grid in canvas-space (pans/zooms with the view).
##   - All stored positions (facility_nodes, drag_current_pos) are in
##     canvas-space; rendering applies the canvas → view transform via
##     `draw_set_transform`, and hit-tests invert it.
##
## Future slices (memory: Drinkustry logistics node-editor vision):
##   - IO sockets reflecting Input Hopper / Output Depot state
##   - Group/annotate nodes
##   - Per-connection throughput control

signal facility_clicked(facility_id: String)
signal facility_drag_started(facility_id: String)
signal facility_drag_ended(target_facility_id: String)
signal connection_right_clicked(connection_id: String)

const NODE_RADIUS: float = 22.0
const LABEL_FONT_SIZE: int = 12
const LABEL_OFFSET_Y: float = NODE_RADIUS + 14.0  # gap between node bottom and label baseline

# Canvas zoom range. 1.0 = "natural" size; 0.25 = quarter scale (overview);
# 4.0 = 4x in for fine placement of nodes.
const CANVAS_ZOOM_MIN: float = 0.25
const CANVAS_ZOOM_MAX: float = 4.0
const CANVAS_ZOOM_STEP: float = 1.15  # multiplicative — feels right for wheel ticks

# Background grid (in canvas-space units).
const GRID_SPACING: float = 50.0
const GRID_COLOR_MINOR: Color = Color(1.0, 1.0, 1.0, 0.05)
const GRID_COLOR_MAJOR: Color = Color(1.0, 1.0, 1.0, 0.10)
const GRID_MAJOR_EVERY: int = 5  # every 5th line is a "major" line, slightly brighter

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

# Node positions in CANVAS-SPACE (not view-space). Cleared and rebuilt by
# update_facility_positions(); custom positions in `_custom_positions` win.
var facility_nodes: Dictionary = {}

# Player-set positions (canvas-space). HELD BY REFERENCE TO the per-corp
# state stored in LogisticsManager so the layout survives world_map scene
# reloads (e.g. trips to a brewery interior) and switches per active corp.
# Mutations propagate to LogisticsManager.network_view_state automatically.
var _custom_positions: Dictionary = {}

# Canvas view transform: canvas → view is `p * canvas_zoom + canvas_offset`.
# Inverse (view → canvas) is `(p - canvas_offset) / canvas_zoom`.
# Both are by-VALUE — explicit `_persist_view_transform()` writes them back
# to LogisticsManager state after every change.
var canvas_zoom: float = 1.0
var canvas_offset: Vector2 = Vector2.ZERO

# Interaction state
var is_connecting: bool = false   # Shift+LMB drag from a node
var is_moving: bool = false       # LMB drag on a node body
var is_panning: bool = false      # Middle-click drag
var drag_start_facility: String = ""
var drag_current_canvas_pos: Vector2 = Vector2.ZERO  # mouse position in canvas-space
var _pan_start_view_pos: Vector2 = Vector2.ZERO
var _canvas_offset_at_pan_start: Vector2 = Vector2.ZERO

# Hover state — drives node/connection highlighting
var hovered_facility: String = ""
var hovered_connection: String = ""

# Bounds (used by the auto-layout fallback when no custom position exists)
var view_bounds: Rect2 = Rect2()
var world_bounds: Rect2 = Rect2()


# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Clip drawing to the control's rect so a dragged or zoomed node can't
	# render outside the panel — nodes "escaping" the window would otherwise
	# be visually loose AND uninteractable (clicks land on whatever is
	# behind them, not the node).
	clip_contents = true

	# Adopt the per-corp view state from LogisticsManager so the layout
	# survives scene reloads (factory interior trips) and swaps per active
	# corp. Listen for live corp switches so we can swap state without
	# requiring the panel to be closed and reopened.
	EventBus.active_corp_changed.connect(_on_active_corp_changed_swap_state)
	_adopt_state_for_corp(GameManager.active_corp_id)


func _adopt_state_for_corp(corp_id: String) -> void:
	"""Bind the local view state to the per-corp record kept on
	LogisticsManager. _custom_positions is held by reference so future
	mutations write through; canvas_zoom/canvas_offset are by value (use
	_persist_view_transform after changes)."""
	var state: Dictionary = LogisticsManager.get_network_view_state_for_corp(corp_id)
	_custom_positions = state.custom_positions
	canvas_zoom = state.canvas_zoom
	canvas_offset = state.canvas_offset


func _persist_view_transform() -> void:
	"""Write canvas_zoom + canvas_offset back to LogisticsManager for the
	current corp. _custom_positions is already a by-ref alias so it's
	always in sync."""
	var state: Dictionary = LogisticsManager.get_network_view_state_for_corp(GameManager.active_corp_id)
	state.canvas_zoom = canvas_zoom
	state.canvas_offset = canvas_offset


func _on_active_corp_changed_swap_state(old_corp_id: String, new_corp_id: String) -> void:
	"""Save the outgoing corp's zoom/offset, then swap in the new corp's
	state and re-lay out. _custom_positions is by-ref so the outgoing
	corp's positions are already saved."""
	if old_corp_id == new_corp_id:
		return
	var old_state: Dictionary = LogisticsManager.get_network_view_state_for_corp(old_corp_id)
	old_state.canvas_zoom = canvas_zoom
	old_state.canvas_offset = canvas_offset
	_adopt_state_for_corp(new_corp_id)
	update_facility_positions()
	queue_redraw()


# ========================================
# COORDINATE TRANSFORMS
# ========================================

func _view_to_canvas(view_pos: Vector2) -> Vector2:
	"""view-space (raw control coords) → canvas-space (the editor's "world")."""
	return (view_pos - canvas_offset) / canvas_zoom


# ========================================
# DRAWING
# ========================================

func _draw() -> void:
	# Apply the canvas → view transform once. All subsequent draw_* calls
	# operate in canvas-space.
	draw_set_transform(canvas_offset, 0.0, Vector2(canvas_zoom, canvas_zoom))

	_draw_grid()
	_draw_connections()

	# Rubber-band line for the connection drag (Shift+LMB).
	if is_connecting and not drag_start_facility.is_empty():
		var start_pos: Vector2 = facility_nodes.get(drag_start_facility, Vector2.ZERO)
		# Line width drawn in canvas-space — divide by zoom so it stays
		# visually constant regardless of zoom level.
		draw_line(start_pos, drag_current_canvas_pos, DRAG_LINE_COLOR, 3.0 / canvas_zoom)

	_draw_facility_nodes()


func _draw_grid() -> void:
	"""Dim grid aligned to canvas-space coordinates. Pans and zooms with the
	view so it acts as a spatial reference rather than wallpaper."""
	# Compute the canvas-space rect that is currently visible in the control.
	var tl: Vector2 = _view_to_canvas(Vector2.ZERO)
	var br: Vector2 = _view_to_canvas(size)
	var spacing: float = GRID_SPACING
	var start_x: float = floor(tl.x / spacing) * spacing
	var end_x: float = ceil(br.x / spacing) * spacing
	var start_y: float = floor(tl.y / spacing) * spacing
	var end_y: float = ceil(br.y / spacing) * spacing
	# Line width stays 1px in view-space regardless of zoom.
	var line_w: float = 1.0 / canvas_zoom

	# Vertical lines
	var x: float = start_x
	while x <= end_x:
		var idx: int = int(round(x / spacing))
		var color: Color = GRID_COLOR_MAJOR if idx % GRID_MAJOR_EVERY == 0 else GRID_COLOR_MINOR
		draw_line(Vector2(x, tl.y), Vector2(x, br.y), color, line_w)
		x += spacing
	# Horizontal lines
	var y: float = start_y
	while y <= end_y:
		var idx2: int = int(round(y / spacing))
		var color2: Color = GRID_COLOR_MAJOR if idx2 % GRID_MAJOR_EVERY == 0 else GRID_COLOR_MINOR
		draw_line(Vector2(tl.x, y), Vector2(br.x, y), color2, line_w)
		y += spacing


func _draw_connections() -> void:
	for connection in LogisticsManager.connections.values():
		var source_id: String = connection.source_id
		var dest_id: String = connection.destination_id

		if not facility_nodes.has(source_id) or not facility_nodes.has(dest_id):
			continue

		var start_pos: Vector2 = facility_nodes[source_id]
		var end_pos: Vector2 = facility_nodes[dest_id]

		var color: Color = CONNECTION_HOVER_COLOR if hovered_connection == connection.id else CONNECTION_COLOR

		draw_line(start_pos, end_pos, color, 3.0 / canvas_zoom)

		# Arrow head — sized in canvas-space, divide by zoom so it stays
		# visually constant on screen.
		var direction: Vector2 = (end_pos - start_pos).normalized()
		var arrow_pos: Vector2 = start_pos.lerp(end_pos, 0.7)
		var perpendicular := Vector2(-direction.y, direction.x)
		var arrow_size: float = 8.0 / canvas_zoom

		var arrow_points := PackedVector2Array([
			arrow_pos + direction * arrow_size,
			arrow_pos - direction * arrow_size * 0.5 + perpendicular * arrow_size * 0.6,
			arrow_pos - direction * arrow_size * 0.5 - perpendicular * arrow_size * 0.6,
		])
		draw_polygon(arrow_points, [color])


func _draw_facility_nodes() -> void:
	var font: Font = ThemeDB.fallback_font
	# Node and label sizes are constants in canvas-space; everything still
	# scales naturally with zoom.
	for facility_id in facility_nodes:
		var pos: Vector2 = facility_nodes[facility_id]
		var facility: Dictionary = WorldManager.get_facility(facility_id)
		if facility.is_empty():
			continue

		var color: Color = NODE_COLORS.get(facility.type, NODE_COLORS["default"])

		if hovered_facility == facility_id:
			color = color.lightened(0.3)
		if drag_start_facility == facility_id:
			color = Color(0.3, 0.6, 0.95) if is_moving else Color(0.3, 0.8, 0.3)

		draw_circle(pos, NODE_RADIUS, color)
		draw_arc(pos, NODE_RADIUS, 0.0, TAU, 32, Color.WHITE, 2.0 / canvas_zoom)

		# Facility name label centered below the node.
		var def: Dictionary = DataManager.get_facility_data(facility.type)
		var name_text: String = String(def.get("name", facility.type))
		var text_size: Vector2 = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var label_pos := Vector2(pos.x - text_size.x / 2.0, pos.y + LABEL_OFFSET_Y)
		# Soft drop shadow for readability over any background.
		draw_string(font, label_pos + Vector2(1, 1), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0, 0, 0, 0.7))
		draw_string(font, label_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color.WHITE)


# ========================================
# LAYOUT
# ========================================

func update_facility_positions() -> void:
	"""Lay out the facility nodes (in canvas-space). Custom positions
	(set by the player by dragging) take precedence; everything else gets an
	auto-computed position from its world-map grid coordinates."""
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

	# `view_bounds` defines the auto-layout target in canvas-space (NOT
	# view-space — canvas-space is the editor's "world"). Same numerical
	# value as the control's size minus a NODE_RADIUS padding.
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


# ========================================
# HIT-TESTING (canvas-space)
# ========================================

func get_facility_at_pos(view_pos: Vector2) -> String:
	var canvas_pos: Vector2 = _view_to_canvas(view_pos)
	for facility_id in facility_nodes:
		if canvas_pos.distance_to(facility_nodes[facility_id]) <= NODE_RADIUS:
			return facility_id
	return ""


func get_connection_at_pos(view_pos: Vector2) -> String:
	var canvas_pos: Vector2 = _view_to_canvas(view_pos)
	for connection in LogisticsManager.connections.values():
		if not facility_nodes.has(connection.source_id) or not facility_nodes.has(connection.destination_id):
			continue
		var start_pos: Vector2 = facility_nodes[connection.source_id]
		var end_pos: Vector2 = facility_nodes[connection.destination_id]
		# Distance threshold is in canvas-space; divide by zoom is NOT needed
		# because the threshold scales naturally with how close the click
		# lands in canvas-space.
		if _point_to_line_distance(canvas_pos, start_pos, end_pos) < 10.0:
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


# ========================================
# ZOOM AND PAN
# ========================================

func _zoom_at(view_point: Vector2, zoom_factor: float) -> void:
	"""Zoom around a view-space point so the canvas-space coordinate under
	the cursor stays under the cursor afterward."""
	var canvas_point_before: Vector2 = _view_to_canvas(view_point)
	var new_zoom: float = clampf(canvas_zoom * zoom_factor, CANVAS_ZOOM_MIN, CANVAS_ZOOM_MAX)
	if abs(new_zoom - canvas_zoom) < 0.0001:
		return
	canvas_zoom = new_zoom
	canvas_offset = view_point - canvas_point_before * canvas_zoom
	_persist_view_transform()
	queue_redraw()


func _start_pan(view_pos: Vector2) -> void:
	is_panning = true
	_pan_start_view_pos = view_pos
	_canvas_offset_at_pan_start = canvas_offset


func _update_pan(view_pos: Vector2) -> void:
	canvas_offset = _canvas_offset_at_pan_start + (view_pos - _pan_start_view_pos)
	queue_redraw()


func _end_pan() -> void:
	is_panning = false
	_persist_view_transform()


# ========================================
# INPUT
# ========================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var view_pos: Vector2 = mb.position

		# Mouse wheel = zoom around cursor.
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom_at(view_pos, CANVAS_ZOOM_STEP)
				accept_event()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_at(view_pos, 1.0 / CANVAS_ZOOM_STEP)
				accept_event()
			return

		# Middle-click drag = pan canvas.
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_start_pan(view_pos)
			else:
				_end_pan()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var facility_id: String = get_facility_at_pos(view_pos)
				if not facility_id.is_empty():
					drag_start_facility = facility_id
					drag_current_canvas_pos = _view_to_canvas(view_pos)
					# Shift = connect; bare LMB = move the node.
					is_connecting = mb.shift_pressed
					is_moving = not mb.shift_pressed
					if is_connecting:
						facility_drag_started.emit(facility_id)
			else:
				if is_connecting:
					var target: String = get_facility_at_pos(view_pos)
					facility_drag_ended.emit(target)
				elif is_moving and not drag_start_facility.is_empty():
					# Commit the move. Position is canvas-space; clamping is
					# loose (canvas is conceptually infinite, but we keep it
					# inside a generous bound so a stray drag doesn't lose
					# the node off-screen at high zoom).
					var canvas_pos: Vector2 = _view_to_canvas(view_pos)
					_custom_positions[drag_start_facility] = canvas_pos
					facility_nodes[drag_start_facility] = canvas_pos
				is_connecting = false
				is_moving = false
				drag_start_facility = ""
			queue_redraw()

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not hovered_connection.is_empty():
				connection_right_clicked.emit(hovered_connection)

	elif event is InputEventMouseMotion:
		var view_pos: Vector2 = event.position
		if is_panning:
			_update_pan(view_pos)
			# Don't update hover/drag while panning.
			return
		var canvas_pos: Vector2 = _view_to_canvas(view_pos)
		if is_connecting:
			drag_current_canvas_pos = canvas_pos
		elif is_moving and not drag_start_facility.is_empty():
			# Live-preview the node at the cursor so the move feels physical.
			facility_nodes[drag_start_facility] = canvas_pos
		hovered_facility = get_facility_at_pos(view_pos)
		hovered_connection = "" if not hovered_facility.is_empty() else get_connection_at_pos(view_pos)
		queue_redraw()
