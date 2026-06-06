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
## Slice-2.0 box nodes + IO sockets (2026-06-05 evening, third pass):
##   - Nodes are boxes (Blender / Unreal-style) with a header showing the
##     facility name, input sockets stacked on the left edge, output
##     sockets stacked on the right edge.
##   - IO is currently derived from facility data's `production.input` /
##     `production.output` block. Facilities without a production block
##     (farmhouse, storage_warehouse) render as empty boxes — placeholder
##     until slice-2.1 reads Input Hopper / Output Depot state from
##     FactoryManager and lets sockets sprout per actual machine config.
##   - Connection lines now terminate at the matching product's input /
##     output socket (falls back to the first socket if no match, and to
##     box-edge midpoint when a side has no sockets).
##   - Hit-testing for node bodies is now Rect2.has_point instead of
##     circle distance.
##
## Future slices (memory: Drinkustry logistics node-editor vision):
##   - 2.1 — sockets driven by Input Hopper / Output Depot state inside
##     factories (Industrial-player edits propagate to Logistics view)
##   - 3 — group + annotate nodes, infinite-canvas niceties
##   - 4 — per-connection throughput control

signal facility_clicked(facility_id: String)
# Connection drags are now socket-initiated (slice 2.3). The signal carries
# both the facility id and the specific product that the dragged socket
# exposes, so the panel doesn't need to re-derive route compatibility.
signal facility_drag_started(facility_id: String, product: String)
signal facility_drag_ended(target_facility_id: String, product: String)
signal connection_right_clicked(connection_id: String)

const NODE_RADIUS: float = 22.0
const LABEL_FONT_SIZE: int = 12
const LABEL_OFFSET_Y: float = NODE_RADIUS + 14.0  # gap between node bottom and label baseline

# Slice-2 box geometry — all values in CANVAS-SPACE units.
const BOX_WIDTH: float = 140.0
const BOX_HEADER_HEIGHT: float = 22.0
const BOX_SOCKET_ROW_HEIGHT: float = 18.0
const BOX_PADDING_BOTTOM: float = 6.0
const SOCKET_RADIUS: float = 5.0
const SOCKET_LABEL_FONT_SIZE: int = 10
const BOX_HEADER_DIVIDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.3)

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

## Node body colors are derived from the facility's category so the network
## view reads at a glance with the same colour language as the world-map
## build menu (see world_map_ui.gd CATEGORY_COLORS — kept in sync here).
const CATEGORY_COLORS: Dictionary = {
	"tools": Color(0.5, 0.5, 0.6),
	"agriculture": Color(0.3, 0.6, 0.3),
	"processing": Color(0.6, 0.5, 0.3),
	"production": Color(0.6, 0.4, 0.3),
	"storage": Color(0.4, 0.4, 0.5),
	"other": Color(0.4, 0.4, 0.4),
}

const INACTIVE_LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)

const CONNECTION_COLOR: Color = Color(0.3, 0.7, 0.3, 0.8)
const CONNECTION_HOVER_COLOR: Color = Color(0.8, 0.3, 0.3, 0.8)
const DRAG_LINE_COLOR: Color = Color(0.5, 0.8, 0.5, 0.6)

## Explicit per-product colors. Picked to match the farm-field tints from
## the world map (barley golden, hops vibrant green) and to be visually
## distinct from each other for at-a-glance flow tracing. Unknown products
## fall through to a hash-derived hue so future content doesn't crash here.
const PRODUCT_COLORS: Dictionary = {
	# Raw crops
	"barley": Color("#d4a017"),        # golden — matches farm field tint
	"hops": Color("#5fb84a"),          # vibrant green — matches farm field tint
	"wheat": Color("#deb054"),
	"corn": Color("#f1c40f"),
	"grapes": Color("#722f7a"),
	"water": Color("#3498db"),
	# Intermediates
	"malt": Color("#a05a2c"),
	"mash": Color("#7d5a3a"),
	"fermented_wash": Color("#9c6b3a"),
	"raw_spirit": Color("#dcdcdc"),
	# Beers
	"ale": Color("#c1853b"),
	"packaged_ale": Color("#c1853b"),
	"lager": Color("#e8c060"),
	"wheat_beer": Color("#f0d080"),
	"stout": Color("#3a2418"),
	"porter": Color("#4a2e1d"),
	# Spirits / aged
	"whiskey": Color("#8b4513"),
	"vodka": Color("#e8e8e8"),
	"premium_whiskey": Color("#a0522d"),
	"aged_spirit": Color("#9c6b3a"),
	"wine": Color("#722f37"),
}

# Marching-arrows animation tuning.
const FLOW_ARROW_SPACING: float = 0.18  # fraction of line length between arrows
const FLOW_ARROW_SPEED: float = 0.3     # arrow positions per second (0.0–1.0 along the line)

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

# Interaction state.
# Connection drags now originate from an output SOCKET (Blender/Unreal style).
# Clicking the node body starts a move instead. Sockets are checked before
# the body on press, so a click that lands on a socket never moves the node.
var is_connecting: bool = false
var is_moving: bool = false
var is_panning: bool = false
var drag_start_facility: String = ""
var drag_source_product: String = ""              # product of the source output socket
var drag_start_canvas_pos: Vector2 = Vector2.ZERO  # source socket position (rubber-band origin)
var drag_current_canvas_pos: Vector2 = Vector2.ZERO  # cursor position in canvas-space
var _pan_start_view_pos: Vector2 = Vector2.ZERO
var _canvas_offset_at_pan_start: Vector2 = Vector2.ZERO

# Hover state — drives node/connection highlighting
var hovered_facility: String = ""
var hovered_connection: String = ""

# Time accumulator for the marching-arrows animation on active connections.
# Advances in _process while the panel is visible.
var _animation_time: float = 0.0

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

	# Continuous redraw while the panel is visible — keeps the IO sockets
	# fresh as inventory grows (farmhouse output sockets follow incoming
	# crops) and as machines are placed inside breweries (brewery sockets
	# sprout/disappear in real-time).
	set_process(true)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_animation_time += delta
		queue_redraw()


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

	# Rubber-band line for the in-progress socket-initiated connection
	# (slice 2.3). Origin is the source socket position (not the box
	# center) so the line reads as "this socket is reaching out".
	if is_connecting and not drag_start_facility.is_empty():
		var band_color: Color = _socket_color_for(drag_source_product) if not drag_source_product.is_empty() else DRAG_LINE_COLOR
		draw_line(drag_start_canvas_pos, drag_current_canvas_pos, band_color, 3.0 / canvas_zoom)

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

		# Line terminates at the matching product's socket if the side has
		# one currently, else at the box edge midpoint (a "broken" attachment).
		var product: String = String(connection.get("product", ""))
		var endpoints: Array = _get_connection_endpoints(source_id, dest_id, product)
		var start_pos: Vector2 = endpoints[0]
		var end_pos: Vector2 = endpoints[1]

		# Connection state has three visual modes besides "normal":
		#  - broken: source no longer produces the routed product. Dashed,
		#    gray, no arrows. Player needs to troubleshoot.
		#  - paused: player manually paused via routes panel (connection.active
		#    is false). Dashed, dim product color, no arrows. The route is
		#    still there, just not flowing.
		#  - normal: solid colored line, arrows. Marching arrows when at
		#    least one vehicle is dispatched on this route.
		# Hover override (red) wins over all three so "delete me" stays clear.
		var broken: bool = _is_connection_broken(connection)
		var is_active: bool = bool(connection.get("active", true))
		var is_paused: bool = is_active == false and not broken
		var product_color: Color = _socket_color_for(product)
		var color: Color
		if hovered_connection == connection.id:
			color = CONNECTION_HOVER_COLOR
		elif broken:
			color = Color(0.6, 0.6, 0.6, 0.7)
		elif is_paused:
			# Dim the product color so the route reads as "off" while
			# still hinting at what it would carry.
			color = Color(product_color.r, product_color.g, product_color.b, 0.45)
		else:
			color = product_color

		var line_w: float = 3.0 / canvas_zoom
		if broken or is_paused:
			# `draw_dashed_line` makes both off-states instantly readable.
			draw_dashed_line(start_pos, end_pos, color, line_w, 8.0 / canvas_zoom, true)
		else:
			draw_line(start_pos, end_pos, color, line_w)

		# Arrows.
		#  - Broken or paused: no arrows. The line style alone reads as
		#    "nothing's moving here."
		#  - Active traffic (a vehicle is dispatched on this route AND the
		#    route is active): marching arrows slide along the line in flow
		#    direction, looping while the panel is visible.
		#  - Idle but valid: single mid-line arrow at t=0.7.
		if not broken and not is_paused:
			var direction: Vector2 = (end_pos - start_pos).normalized()
			var arrow_size: float = 8.0 / canvas_zoom
			if is_active and _connection_has_active_traffic(String(connection.id)):
				var t_offset: float = fposmod(_animation_time * FLOW_ARROW_SPEED, FLOW_ARROW_SPACING)
				var t: float = t_offset
				while t < 1.0:
					_draw_directional_arrow(start_pos.lerp(end_pos, t), direction, arrow_size, color)
					t += FLOW_ARROW_SPACING
			else:
				_draw_directional_arrow(start_pos.lerp(end_pos, 0.7), direction, arrow_size, color)


func _draw_facility_nodes() -> void:
	var font: Font = ThemeDB.fallback_font
	for facility_id in facility_nodes:
		var pos: Vector2 = facility_nodes[facility_id]
		var facility: Dictionary = WorldManager.get_facility(facility_id)
		if facility.is_empty():
			continue
		var def: Dictionary = DataManager.get_facility_data(facility.type)
		var rect: Rect2 = _get_node_rect(facility_id)

		# Body color = build-menu category color so the network reads with
		# the same colour language as the world-map build menu.
		var category: String = String(def.get("category", "other"))
		var color: Color = CATEGORY_COLORS.get(category, CATEGORY_COLORS["other"])
		if hovered_facility == facility_id:
			color = color.lightened(0.3)
		if drag_start_facility == facility_id:
			color = Color(0.3, 0.6, 0.95) if is_moving else Color(0.3, 0.8, 0.3)

		# Box body + border. Border width is divided by zoom so it stays
		# visually constant.
		draw_rect(rect, color, true)
		draw_rect(rect, Color.WHITE, false, 2.0 / canvas_zoom)

		# Header divider between title and socket rows.
		var header_y: float = rect.position.y + BOX_HEADER_HEIGHT
		draw_line(
			Vector2(rect.position.x, header_y),
			Vector2(rect.position.x + rect.size.x, header_y),
			BOX_HEADER_DIVIDER_COLOR,
			1.0 / canvas_zoom,
		)

		# Centered title in the header strip.
		var name_text: String = String(def.get("name", facility.type))
		var title_size: Vector2 = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var title_pos := Vector2(pos.x - title_size.x / 2.0, rect.position.y + BOX_HEADER_HEIGHT - 6.0)
		draw_string(font, title_pos + Vector2(1, 1), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(0, 0, 0, 0.7))
		draw_string(font, title_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color.WHITE)

		# IO sockets — inputs on the left edge, outputs on the right edge.
		# Both sides start one row-half below the header so they're vertically
		# centered within their row.
		var io: Dictionary = get_node_io(facility_id)

		# Empty box → render an italic-feeling status hint so the player knows
		# WHY there are no sockets (farmhouse: no production; brewery: no
		# input hopper / output depot inside; etc.).
		if io.inputs.is_empty() and io.outputs.is_empty():
			var hint: String = _get_inactive_reason(facility_id)
			if not hint.is_empty():
				var hint_size: Vector2 = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, SOCKET_LABEL_FONT_SIZE)
				var hint_y: float = rect.position.y + BOX_HEADER_HEIGHT + (rect.size.y - BOX_HEADER_HEIGHT) / 2.0 + 3.0
				var hint_pos := Vector2(pos.x - hint_size.x / 2.0, hint_y)
				draw_string(font, hint_pos, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, SOCKET_LABEL_FONT_SIZE, INACTIVE_LABEL_COLOR)

		for i in range(io.inputs.size()):
			var socket_pos: Vector2 = _get_input_socket_pos(facility_id, i)
			var socket_color: Color = _socket_color_for(io.inputs[i])
			draw_circle(socket_pos, SOCKET_RADIUS, socket_color)
			draw_arc(socket_pos, SOCKET_RADIUS, 0.0, TAU, 16, Color.WHITE, 1.0 / canvas_zoom)
			# Product label, left-aligned inside the box.
			var in_lbl_pos := Vector2(socket_pos.x + SOCKET_RADIUS + 4.0, socket_pos.y + 3.0)
			draw_string(font, in_lbl_pos, io.inputs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, SOCKET_LABEL_FONT_SIZE, Color(1, 1, 1, 0.85))
		for i in range(io.outputs.size()):
			var socket_pos2: Vector2 = _get_output_socket_pos(facility_id, i)
			var socket_color2: Color = _socket_color_for(io.outputs[i])
			draw_circle(socket_pos2, SOCKET_RADIUS, socket_color2)
			draw_arc(socket_pos2, SOCKET_RADIUS, 0.0, TAU, 16, Color.WHITE, 1.0 / canvas_zoom)
			# Product label, right-aligned inside the box.
			var out_lbl_size: Vector2 = font.get_string_size(io.outputs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, SOCKET_LABEL_FONT_SIZE)
			var out_lbl_pos := Vector2(socket_pos2.x - SOCKET_RADIUS - 4.0 - out_lbl_size.x, socket_pos2.y + 3.0)
			draw_string(font, out_lbl_pos, io.outputs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, SOCKET_LABEL_FONT_SIZE, Color(1, 1, 1, 0.85))


# ========================================
# NODE GEOMETRY + IO HELPERS
# ========================================

func get_node_io(facility_id: String) -> Dictionary:
	"""Return { inputs: Array[String], outputs: Array[String] } for a facility.

	Slice 2.1 sources:
	- Farmhouse → output socket per unique product in its current inventory.
	  No inventory = no sockets (the box renders an "(inactive)" label).
	  Inputs always empty — farmhouses are the gather node, not a consumer.
	- Facilities with `has_interior` (brewery, distillery, etc.) → IO sockets
	  appear ONLY when there are corresponding machines placed inside (Input
	  Hopper for input, Output Depot for output). Product labels still come
	  from the facility's `production` block until per-hopper product config
	  ships (slice 2.2).
	- Everything else → static IO from the facility's `production.input` /
	  `production.output` block (slice 2.0 behaviour).
	"""
	var facility: Dictionary = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return {"inputs": [], "outputs": []}
	var def: Dictionary = DataManager.get_facility_data(facility.type)

	# Farmhouse: socket per unique inventory product.
	if facility.type == "farmhouse":
		var inv: Dictionary = ProductionManager.get_inventory(facility_id)
		var fh_outputs: Array[String] = []
		for product in inv.keys():
			fh_outputs.append(String(product))
		return {"inputs": [], "outputs": fh_outputs}

	# Interior-having facility: sockets derive from each Input Hopper's /
	# Output Depot's `configured_product` (slice 3.2). An unconfigured
	# machine contributes no socket. Multiple hoppers configured for the
	# same product collapse to one socket on the node.
	var has_interior: bool = bool(def.get("has_interior", false))
	if has_interior and FactoryManager.has_interior(facility_id):
		var gated_inputs: Array[String] = []
		var gated_outputs: Array[String] = []
		var seen_inputs: Dictionary = {}
		var seen_outputs: Dictionary = {}
		var machines: Array = FactoryManager.get_all_machines(facility_id)
		for m in machines:
			var product: String = String(m.get("configured_product", ""))
			if product.is_empty():
				continue
			var m_def: Dictionary = DataManager.get_machine_data(m.type)
			if m_def.get("is_input_node", false):
				if not seen_inputs.has(product):
					gated_inputs.append(product)
					seen_inputs[product] = true
			elif m_def.get("is_output_node", false):
				if not seen_outputs.has(product):
					gated_outputs.append(product)
					seen_outputs[product] = true
		return {"inputs": gated_inputs, "outputs": gated_outputs}

	# Default: static IO from the facility data.
	var production: Dictionary = def.get("production", {})
	var inputs: Array[String] = []
	var outputs: Array[String] = []
	var inp: String = String(production.get("input", ""))
	if not inp.is_empty():
		inputs.append(inp)
	var out: String = String(production.get("output", ""))
	if not out.is_empty():
		outputs.append(out)
	return {"inputs": inputs, "outputs": outputs}


func _get_inactive_reason(facility_id: String) -> String:
	"""Human-readable status string for a node that has no IO sockets.
	Empty string means the node is producing / has sockets and no overlay
	is needed."""
	var io: Dictionary = get_node_io(facility_id)
	if io.inputs.size() > 0 or io.outputs.size() > 0:
		return ""
	var facility: Dictionary = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return ""
	if facility.type == "farmhouse":
		return "(no production yet)"
	var def: Dictionary = DataManager.get_facility_data(facility.type)
	if bool(def.get("has_interior", false)):
		return "(no I/O placed inside)"
	return "(idle)"


func _get_node_box_size(facility_id: String) -> Vector2:
	"""Box height grows with the max(inputs, outputs) socket count so all
	sockets fit. Minimum one row's worth so empty boxes still look like
	boxes."""
	var io: Dictionary = get_node_io(facility_id)
	var rows: int = maxi(maxi(io.inputs.size(), io.outputs.size()), 1)
	var body_height: float = BOX_HEADER_HEIGHT + float(rows) * BOX_SOCKET_ROW_HEIGHT + BOX_PADDING_BOTTOM
	return Vector2(BOX_WIDTH, body_height)


func _get_node_rect(facility_id: String) -> Rect2:
	"""Canvas-space rect of the node box. `facility_nodes[id]` is treated as
	the box CENTER so dragging behaves naturally (cursor stays in the middle
	of the box)."""
	var center: Vector2 = facility_nodes.get(facility_id, Vector2.ZERO)
	var box_size: Vector2 = _get_node_box_size(facility_id)
	return Rect2(center - box_size / 2.0, box_size)


func _socket_y_for(facility_id: String, index: int) -> float:
	var rect: Rect2 = _get_node_rect(facility_id)
	return rect.position.y + BOX_HEADER_HEIGHT + BOX_SOCKET_ROW_HEIGHT / 2.0 + float(index) * BOX_SOCKET_ROW_HEIGHT


func _get_input_socket_pos(facility_id: String, index: int) -> Vector2:
	var rect: Rect2 = _get_node_rect(facility_id)
	return Vector2(rect.position.x, _socket_y_for(facility_id, index))


func _get_output_socket_pos(facility_id: String, index: int) -> Vector2:
	var rect: Rect2 = _get_node_rect(facility_id)
	return Vector2(rect.position.x + rect.size.x, _socket_y_for(facility_id, index))


func _get_connection_endpoints(source_id: String, dest_id: String, product: String) -> Array:
	"""Return [source_pos, dest_pos] for the line endpoints. Attaches to the
	matching product's socket if the side currently exposes one. Falls back
	to the box's right-/left-edge midpoint if no matching socket exists —
	this makes "broken" connections (source no longer produces the product,
	dest no longer accepts it) visually obvious instead of silently
	re-attaching to the wrong socket as the IO list shifts."""
	var src_io: Dictionary = get_node_io(source_id)
	var dst_io: Dictionary = get_node_io(dest_id)
	var src_pos: Vector2
	var src_idx: int = src_io.outputs.find(product)
	if src_idx >= 0:
		src_pos = _get_output_socket_pos(source_id, src_idx)
	else:
		# Broken on source side — attach to box right-edge midpoint.
		var r: Rect2 = _get_node_rect(source_id)
		src_pos = Vector2(r.position.x + r.size.x, r.position.y + r.size.y / 2.0)
	var dst_pos: Vector2
	var dst_idx: int = dst_io.inputs.find(product)
	if dst_idx >= 0:
		dst_pos = _get_input_socket_pos(dest_id, dst_idx)
	else:
		# Broken on dest side — attach to box left-edge midpoint.
		var r2: Rect2 = _get_node_rect(dest_id)
		dst_pos = Vector2(r2.position.x, r2.position.y + r2.size.y / 2.0)
	return [src_pos, dst_pos]


func _is_connection_broken(connection: Dictionary) -> bool:
	"""A connection is "broken" if its routed product is not currently in
	the source's outputs (the source no longer produces it). Player needs
	to troubleshoot: assign the right crop, place hopper, etc."""
	var product: String = String(connection.get("product", ""))
	if product.is_empty():
		return true
	var src_io: Dictionary = get_node_io(String(connection.get("source_id", "")))
	return not (product in src_io.outputs)


func _socket_color_for(product: String) -> Color:
	"""Stable color per product. Hits the curated PRODUCT_COLORS map for
	all known slice-1 products (barley = golden, hops = green, etc.).
	Falls back to a hash-derived hue for any product not yet listed —
	when new content lands and the color matters, add it to the map."""
	if product.is_empty():
		return Color(0.5, 0.5, 0.5)
	if PRODUCT_COLORS.has(product):
		return PRODUCT_COLORS[product]
	var h: float = float(absi(product.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.92)


func _connection_has_active_traffic(connection_id: String) -> bool:
	"""True iff at least one vehicle is currently dispatched on this
	connection. Drives the marching-arrows animation in _draw_connections."""
	if connection_id.is_empty():
		return false
	for vehicle in LogisticsManager.vehicles.values():
		if String(vehicle.get("connection_id", "")) == connection_id:
			return true
	return false


func _draw_directional_arrow(at_pos: Vector2, direction: Vector2, half_size: float, color: Color) -> void:
	"""Filled triangle pointing along `direction`. Used by both the static
	mid-arrow and the marching-arrows animation."""
	var perpendicular := Vector2(-direction.y, direction.x)
	var arrow_points := PackedVector2Array([
		at_pos + direction * half_size,
		at_pos - direction * half_size * 0.5 + perpendicular * half_size * 0.6,
		at_pos - direction * half_size * 0.5 - perpendicular * half_size * 0.6,
	])
	draw_polygon(arrow_points, [color])


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
	# view-space — canvas-space is the editor's "world"). Pad by half a box
	# so the auto-laid-out boxes don't clip the control's edge.
	var padding: float = BOX_WIDTH / 2.0 + 10.0
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
		var rect: Rect2 = _get_node_rect(facility_id)
		if rect.has_point(canvas_pos):
			return facility_id
	return ""


func get_socket_at_pos(view_pos: Vector2) -> Dictionary:
	"""Return socket info (facility_id, type "input"/"output", index, product)
	if the cursor is over a socket dot, else {}. Hit zone is a bit larger
	than the visual radius so the player doesn't have to be pixel-precise."""
	var canvas_pos: Vector2 = _view_to_canvas(view_pos)
	var hit_radius: float = SOCKET_RADIUS * 1.6
	for facility_id in facility_nodes:
		var io: Dictionary = get_node_io(facility_id)
		for i in range(io.inputs.size()):
			if canvas_pos.distance_to(_get_input_socket_pos(facility_id, i)) <= hit_radius:
				return {"facility_id": facility_id, "type": "input", "index": i, "product": io.inputs[i]}
		for i in range(io.outputs.size()):
			if canvas_pos.distance_to(_get_output_socket_pos(facility_id, i)) <= hit_radius:
				return {"facility_id": facility_id, "type": "output", "index": i, "product": io.outputs[i]}
	return {}


func get_connection_at_pos(view_pos: Vector2) -> String:
	var canvas_pos: Vector2 = _view_to_canvas(view_pos)
	for connection in LogisticsManager.connections.values():
		if not facility_nodes.has(connection.source_id) or not facility_nodes.has(connection.destination_id):
			continue
		var product: String = String(connection.get("product", ""))
		var endpoints: Array = _get_connection_endpoints(connection.source_id, connection.destination_id, product)
		# Distance threshold is in canvas-space; matches the slice-1.5
		# behaviour — clicks scale naturally with zoom.
		if _point_to_line_distance(canvas_pos, endpoints[0], endpoints[1]) < 10.0:
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
				# Sockets win over the box body — Blender / Unreal style.
				# Output socket = start connection drag. Input socket = no-op
				# for now (slice 2.3 only supports source→destination drags;
				# input-initiated reverse drags can come later if needed).
				var socket: Dictionary = get_socket_at_pos(view_pos)
				if not socket.is_empty():
					if String(socket.type) == "output":
						is_connecting = true
						drag_start_facility = String(socket.facility_id)
						drag_source_product = String(socket.product)
						drag_start_canvas_pos = _get_output_socket_pos(drag_start_facility, int(socket.index))
						drag_current_canvas_pos = _view_to_canvas(view_pos)
						facility_drag_started.emit(drag_start_facility, drag_source_product)
				else:
					var facility_id: String = get_facility_at_pos(view_pos)
					if not facility_id.is_empty():
						drag_start_facility = facility_id
						drag_current_canvas_pos = _view_to_canvas(view_pos)
						is_moving = true
			else:
				if is_connecting:
					# Strict drop target: a matching input socket. Releasing
					# on a node body / empty space cancels.
					var release_socket: Dictionary = get_socket_at_pos(view_pos)
					if not release_socket.is_empty() and String(release_socket.type) == "input":
						facility_drag_ended.emit(String(release_socket.facility_id), String(release_socket.product))
					else:
						facility_drag_ended.emit("", "")
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
				drag_source_product = ""
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
