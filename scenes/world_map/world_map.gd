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

	# Cancel placement with Escape
	if event.is_action_pressed("ui_cancel"):
		if placement_mode:
			_cancel_placement()


func _process(_delta: float) -> void:
	# Update placement preview position
	if placement_mode and placement_preview:
		var world_pos = WorldManager.grid_to_world(mouse_grid_pos)
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

func _on_facility_placed(facility: Dictionary) -> void:
	"""Create visual representation of a placed facility"""
	var facility_node = _create_facility_node(facility)
	facilities_container.add_child(facility_node)


func _create_facility_node(facility: Dictionary) -> Node2D:
	"""Create a visual node for a facility"""
	var node = Node2D.new()
	node.name = facility.id
	node.position = facility.world_pos

	var facility_def = DataManager.get_facility_data(facility.type)
	var size = facility.size
	var color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))

	# Create colored rectangle
	for x in range(size.x):
		for y in range(size.y):
			var rect = ColorRect.new()
			rect.size = Vector2(WorldManager.TILE_SIZE - 4, WorldManager.TILE_SIZE - 4)
			rect.position = Vector2(
				(x - size.x / 2.0) * WorldManager.TILE_SIZE + 2,
				(y - size.y / 2.0) * WorldManager.TILE_SIZE + 2
			)
			rect.color = color
			node.add_child(rect)

	# Add label
	var label = Label.new()
	label.text = facility_def.get("name", facility.type)
	label.position = Vector2(-WorldManager.TILE_SIZE / 2, -WorldManager.TILE_SIZE / 2 - 20)
	label.add_theme_font_size_override("font_size", 12)
	node.add_child(label)

	return node


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
