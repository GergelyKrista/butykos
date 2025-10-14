extends Node2D

## WorldMap - Main scene for the strategic world map layer
##
## Displays the 50x50 grid, placed facilities, and handles user input
## for facility placement and selection.

# ========================================
# REFERENCES
# ========================================

@onready var grid_renderer = $GridRenderer
@onready var facilities_container = $FacilitiesContainer
@onready var camera = $Camera2D
@onready var ui = $UI

# ========================================
# STATE
# ========================================

# Current placement mode
var placement_mode: bool = false
var placement_facility_id: String = ""
var placement_preview: Node2D = null

# Route creation mode
var route_mode: bool = false
var route_source_id: String = ""
var route_destination_id: String = ""
var route_product: String = ""

# Mouse/input state
var mouse_grid_pos: Vector2i = Vector2i.ZERO

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("WorldMap scene loaded")

	# Set game state
	GameManager.change_state(GameManager.GameState.WORLD_MAP)

	# Connect signals
	EventBus.facility_placed.connect(_on_facility_placed)
	EventBus.facility_removed.connect(_on_facility_removed)
	EventBus.facility_selected.connect(_on_facility_selected)

	# Initialize UI
	_update_money_display()
	EventBus.money_changed.connect(_on_money_changed)

	# Load existing facilities (important for returning from factory interior)
	_load_existing_facilities()

	# Center camera on grid
	camera.position = Vector2(
		WorldManager.GRID_SIZE.x * WorldManager.TILE_SIZE / 2.0,
		WorldManager.GRID_SIZE.y * WorldManager.TILE_SIZE / 2.0
	)


# ========================================
# INPUT HANDLING
# ========================================

func _input(event: InputEvent) -> void:
	# Update mouse position
	if event is InputEventMouse:
		var world_pos = camera.get_global_mouse_position()
		mouse_grid_pos = WorldManager.world_to_grid(world_pos)

	# Placement mode input
	if placement_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_try_place_facility()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_placement()

	# Route mode input (clicking handled by Area2D signals now)
	if route_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_route_mode()

	# Cancel placement/route mode with Escape
	if event.is_action_pressed("ui_cancel"):
		if placement_mode:
			_cancel_placement()
		elif route_mode:
			_cancel_route_mode()


func _process(_delta: float) -> void:
	# Update placement preview position
	if placement_mode and placement_preview:
		# Get facility size to properly center the preview
		var facility_def = DataManager.get_facility_data(placement_facility_id)
		var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])

		# Calculate center position (same logic as actual placement)
		var center_grid_pos = Vector2(
			mouse_grid_pos.x + size.x / 2.0,
			mouse_grid_pos.y + size.y / 2.0
		)
		var world_pos = Vector2(
			center_grid_pos.x * WorldManager.TILE_SIZE,
			center_grid_pos.y * WorldManager.TILE_SIZE
		)

		placement_preview.position = world_pos

		# Update preview color based on validity
		_update_placement_preview_validity()


# ========================================
# FACILITY PLACEMENT
# ========================================

func start_placement_mode(facility_id: String) -> void:
	"""Enter placement mode for a specific facility type"""
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		push_error("Unknown facility: %s" % facility_id)
		return

	placement_mode = true
	placement_facility_id = facility_id

	# Create placement preview
	_create_placement_preview(facility_def)

	print("Placement mode started: %s" % facility_def.name)


func _create_placement_preview(facility_def: Dictionary) -> void:
	"""Create visual preview for placement"""
	placement_preview = Node2D.new()
	add_child(placement_preview)

	var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])
	var color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))

	# Create rectangle for each tile
	for x in range(size.x):
		for y in range(size.y):
			var rect = ColorRect.new()
			rect.size = Vector2(WorldManager.TILE_SIZE - 4, WorldManager.TILE_SIZE - 4)
			rect.position = Vector2(
				(x - size.x / 2.0) * WorldManager.TILE_SIZE + 2,
				(y - size.y / 2.0) * WorldManager.TILE_SIZE + 2
			)
			rect.color = color
			rect.color.a = 0.5
			placement_preview.add_child(rect)


func _update_placement_preview_validity() -> void:
	"""Update preview color based on whether placement is valid"""
	if not placement_preview:
		return

	var facility_def = DataManager.get_facility_data(placement_facility_id)
	var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])

	var can_place = WorldManager.can_place_facility(mouse_grid_pos, size)
	var can_afford = EconomyManager.can_afford(facility_def.get("cost", 0))

	# Set color: green if valid, red if invalid
	var base_color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))
	if can_place and can_afford:
		modulate_preview(Color(0.5, 1.0, 0.5, 0.7))
	else:
		modulate_preview(Color(1.0, 0.3, 0.3, 0.7))


func modulate_preview(color: Color) -> void:
	"""Apply color modulation to all preview rectangles"""
	if not placement_preview:
		return

	for child in placement_preview.get_children():
		if child is ColorRect:
			child.modulate = color


func _try_place_facility() -> void:
	"""Attempt to place facility at current mouse position"""
	var facility_def = DataManager.get_facility_data(placement_facility_id)
	var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])
	var cost = facility_def.get("cost", 0)

	# Check placement validity
	if not WorldManager.can_place_facility(mouse_grid_pos, size):
		print("Cannot place facility: invalid location")
		return

	# Check if player can afford
	if not EconomyManager.can_afford(cost):
		print("Cannot place facility: insufficient funds")
		return

	# Purchase and place facility
	if EconomyManager.purchase_facility(placement_facility_id):
		var facility_id = WorldManager.place_facility(placement_facility_id, mouse_grid_pos, {
			"size": size
		})

		if facility_id:
			# Mark as constructed immediately for now (no construction time in MVP)
			WorldManager.complete_construction(facility_id)
			print("Facility placed successfully: %s" % facility_id)


func _cancel_placement() -> void:
	"""Cancel placement mode"""
	placement_mode = false
	placement_facility_id = ""

	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	print("Placement mode cancelled")


# ========================================
# FACILITY VISUALIZATION
# ========================================

func _load_existing_facilities() -> void:
	"""Load and visualize all existing facilities from WorldManager"""
	var facilities = WorldManager.get_all_facilities()

	print("Loading %d existing facilities" % facilities.size())

	for facility in facilities:
		var facility_node = _create_facility_node(facility)
		facilities_container.add_child(facility_node)


func _on_facility_placed(facility: Dictionary) -> void:
	"""Create visual representation of a placed facility"""
	var facility_node = _create_facility_node(facility)
	facilities_container.add_child(facility_node)


func _create_facility_node(facility: Dictionary) -> Area2D:
	"""Create a visual node for a facility with clickable area"""
	var area = Area2D.new()
	area.name = facility.id
	area.position = facility.world_pos

	var facility_def = DataManager.get_facility_data(facility.type)
	var size = facility.size
	var color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))

	# Create sprite for each tile (placeholder - can be replaced with real sprites)
	for x in range(size.x):
		for y in range(size.y):
			var sprite = Sprite2D.new()
			sprite.texture = _create_placeholder_texture(WorldManager.TILE_SIZE - 4, color)
			# Sprite2D positions from center, so add TILE_SIZE/2 offset
			sprite.position = Vector2(
				(x - size.x / 2.0) * WorldManager.TILE_SIZE + WorldManager.TILE_SIZE / 2.0,
				(y - size.y / 2.0) * WorldManager.TILE_SIZE + WorldManager.TILE_SIZE / 2.0
			)
			area.add_child(sprite)

	# Add collision shape covering entire facility for click detection
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(
		size.x * WorldManager.TILE_SIZE - 8,
		size.y * WorldManager.TILE_SIZE - 8
	)
	collision.shape = shape
	area.add_child(collision)

	# Add label
	var label = Label.new()
	label.text = facility_def.get("name", facility.type)
	label.position = Vector2(-WorldManager.TILE_SIZE / 2, -size.y * WorldManager.TILE_SIZE / 2 - 20)
	label.add_theme_font_size_override("font_size", 12)
	area.add_child(label)

	# Connect click signal
	area.input_event.connect(_on_facility_clicked.bind(facility.id))

	return area


func _create_placeholder_texture(tile_size: int, color: Color) -> ImageTexture:
	"""Create a simple colored square texture as placeholder for sprites"""
	var image = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _on_facility_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, facility_id: String) -> void:
	"""Handle facility being clicked"""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Check for double-click first (has higher priority)
		if event.double_click and FactoryManager.has_interior(facility_id):
			print("Double-click detected on facility: %s" % facility_id)
			_enter_factory(facility_id)
			return

		# Check for shift+click (also high priority)
		if event.pressed and event.shift_pressed and FactoryManager.has_interior(facility_id):
			print("Shift+click detected on facility: %s" % facility_id)
			_enter_factory(facility_id)
			return

		# Regular click: route mode
		if event.pressed and route_mode:
			_select_facility_for_route(facility_id)
			return


func _select_facility_for_route(facility_id: String) -> void:
	"""Select a facility for route creation"""
	# First click: select source
	if route_source_id.is_empty():
		route_source_id = facility_id
		print("Route source selected: %s - Now click destination" % facility_id)
		_highlight_facility(facility_id, Color.YELLOW)
		return

	# Second click: select destination
	if facility_id == route_source_id:
		print("Cannot create route to same facility")
		return

	route_destination_id = facility_id
	print("Route destination selected: %s" % facility_id)

	# Determine what product to transport
	var product = _determine_route_product(route_source_id, route_destination_id)

	if product.is_empty():
		print("No compatible product found for this route")
		_cancel_route_mode()
		return

	# Create the route
	var route_id = LogisticsManager.create_route(route_source_id, route_destination_id, product)

	if not route_id.is_empty():
		print("Route created: %s" % route_id)

	_cancel_route_mode()


func _on_facility_removed(facility_id: String) -> void:
	"""Remove visual representation of a facility"""
	var facility_node = facilities_container.get_node_or_null(facility_id)
	if facility_node:
		facility_node.queue_free()


func _on_facility_selected(facility_id: String) -> void:
	"""Handle facility selection"""
	print("Facility selected: %s" % facility_id)


# ========================================
# UI UPDATES
# ========================================

func _update_money_display() -> void:
	"""Update money display in UI"""
	if ui and ui.has_node("MoneyLabel"):
		ui.get_node("MoneyLabel").text = "$%d" % EconomyManager.money


func _on_money_changed(_new_amount: int, _delta: int) -> void:
	"""Handle money changed event"""
	_update_money_display()


# ========================================
# BUILD MENU
# ========================================

func _on_build_button_pressed(facility_id: String) -> void:
	"""Handle build button press from UI"""
	start_placement_mode(facility_id)


# ========================================
# ROUTE CREATION
# ========================================

func start_route_mode() -> void:
	"""Enter route creation mode"""
	route_mode = true
	route_source_id = ""
	route_destination_id = ""
	print("Route mode started - Click any facility to start")


func _determine_route_product(source_id: String, dest_id: String) -> String:
	"""Determine what product should be transported on this route"""
	var source = WorldManager.get_facility(source_id)
	var dest = WorldManager.get_facility(dest_id)

	var source_def = DataManager.get_facility_data(source.type)
	var dest_def = DataManager.get_facility_data(dest.type)

	# Get what the source produces
	var source_output = source_def.get("production", {}).get("output", "")

	# Get what the destination needs
	var dest_input = dest_def.get("production", {}).get("input", "")

	# Match output to input
	if not source_output.is_empty() and source_output == dest_input:
		return source_output

	# Default to source output if destination doesn't specify
	if not source_output.is_empty():
		return source_output

	return ""


func _cancel_route_mode() -> void:
	"""Cancel route creation mode"""
	if not route_source_id.is_empty():
		_unhighlight_facility(route_source_id)

	route_mode = false
	route_source_id = ""
	route_destination_id = ""
	route_product = ""
	print("Route mode cancelled")


func _highlight_facility(facility_id: String, color: Color) -> void:
	"""Highlight a facility"""
	var facility_node = facilities_container.get_node_or_null(facility_id)
	if facility_node:
		facility_node.modulate = color


func _unhighlight_facility(facility_id: String) -> void:
	"""Remove highlight from a facility"""
	var facility_node = facilities_container.get_node_or_null(facility_id)
	if facility_node:
		facility_node.modulate = Color.WHITE


func _on_create_route_button_pressed() -> void:
	"""Handle create route button press from UI"""
	start_route_mode()


# ========================================
# FACTORY INTERIOR TRANSITION
# ========================================

func _enter_factory(facility_id: String) -> void:
	"""Enter factory interior view"""
	print("Entering factory interior for: %s" % facility_id)

	# Set active factory in GameManager
	GameManager.enter_factory_view(facility_id)

	# Load factory interior scene
	get_tree().change_scene_to_file("res://scenes/factory_interior/factory_interior.tscn")
