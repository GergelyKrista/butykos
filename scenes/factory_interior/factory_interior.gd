extends Node2D

## FactoryInterior - Factory interior view scene
##
## Tactical layer where players place and configure machines inside facilities.
## 20x20 grid for machine placement and production line optimization.

# ========================================
# REFERENCES
# ========================================

@onready var grid_renderer = $GridRenderer
@onready var machines_container = $MachinesContainer
@onready var camera = $Camera2D
@onready var ui = $UI

# ========================================
# STATE
# ========================================

var facility_id: String = ""
var interior_data: Dictionary = {}

# Machine placement mode
var placement_mode: bool = false
var placement_machine_id: String = ""
var placement_preview: Node2D = null

# Mouse/input state
var mouse_grid_pos: Vector2i = Vector2i.ZERO

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("FactoryInterior scene loaded")

	# Get facility ID from GameManager
	facility_id = GameManager.active_factory_id

	if facility_id.is_empty():
		push_error("No active factory set!")
		return

	# Load interior data
	interior_data = FactoryManager.get_factory_interior(facility_id)

	# Set game state
	GameManager.change_state(GameManager.GameState.FACTORY_VIEW)

	# Load existing machines
	_load_existing_machines()

	# Center camera
	camera.position = Vector2(
		FactoryManager.INTERIOR_GRID_SIZE.x * FactoryManager.INTERIOR_TILE_SIZE / 2.0,
		FactoryManager.INTERIOR_GRID_SIZE.y * FactoryManager.INTERIOR_TILE_SIZE / 2.0
	)

	print("Viewing factory interior for facility: %s" % facility_id)


# ========================================
# INPUT HANDLING
# ========================================

func _input(event: InputEvent) -> void:
	# Update mouse position
	if event is InputEventMouse:
		var world_pos = camera.get_global_mouse_position()
		mouse_grid_pos = FactoryManager.world_to_interior_grid(world_pos)

	# DEBUG: Print machines (Press P)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			print("DEBUG: Current machines in factory:")
			var machines = FactoryManager.get_all_machines(facility_id)
			if machines.is_empty():
				print("  (No machines placed)")
			else:
				for machine in machines:
					print("  - %s (%s) at %s" % [machine.id, machine.type, machine.grid_pos])

	# Placement mode input
	if placement_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_try_place_machine()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_placement()

	# Cancel placement with Escape
	if event.is_action_pressed("ui_cancel"):
		if placement_mode:
			_cancel_placement()


func _process(_delta: float) -> void:
	# Update placement preview position
	if placement_mode and placement_preview:
		# Get machine size to properly center the preview
		var machine_def = DataManager.get_machine_data(placement_machine_id)
		var size = Vector2i(machine_def.get("size", [1, 1])[0], machine_def.get("size", [1, 1])[1])

		# Calculate center position (same logic as actual placement)
		var center_grid_pos = Vector2(
			mouse_grid_pos.x + size.x / 2.0,
			mouse_grid_pos.y + size.y / 2.0
		)
		var world_pos = Vector2(
			center_grid_pos.x * FactoryManager.INTERIOR_TILE_SIZE,
			center_grid_pos.y * FactoryManager.INTERIOR_TILE_SIZE
		)

		placement_preview.position = world_pos


# ========================================
# MACHINE PLACEMENT
# ========================================

func start_placement_mode(machine_id: String) -> void:
	"""Enter machine placement mode"""
	var machine_def = DataManager.get_machine_data(machine_id)
	if machine_def.is_empty():
		push_error("Unknown machine: %s" % machine_id)
		return

	placement_mode = true
	placement_machine_id = machine_id

	# Create placement preview
	_create_placement_preview(machine_def)

	print("Machine placement mode started: %s" % machine_def.get("name", machine_id))


func _create_placement_preview(machine_def: Dictionary) -> void:
	"""Create visual preview for machine placement"""
	placement_preview = Node2D.new()
	add_child(placement_preview)

	var size = Vector2i(machine_def.get("size", [1, 1])[0], machine_def.get("size", [1, 1])[1])
	var color = Color(machine_def.get("visual", {}).get("color", "#aaaaaa"))

	# Create sprite for each tile (using ColorRect for semi-transparent preview)
	for x in range(size.x):
		for y in range(size.y):
			var rect = ColorRect.new()
			rect.size = Vector2(FactoryManager.INTERIOR_TILE_SIZE - 4, FactoryManager.INTERIOR_TILE_SIZE - 4)
			rect.position = Vector2(
				(x - size.x / 2.0) * FactoryManager.INTERIOR_TILE_SIZE + 2,
				(y - size.y / 2.0) * FactoryManager.INTERIOR_TILE_SIZE + 2
			)
			rect.color = color
			rect.color.a = 0.5
			placement_preview.add_child(rect)


func _try_place_machine() -> void:
	"""Attempt to place machine at current mouse position"""
	var machine_def = DataManager.get_machine_data(placement_machine_id)
	var size = Vector2i(machine_def.get("size", [1, 1])[0], machine_def.get("size", [1, 1])[1])

	# Check placement validity
	if not FactoryManager.can_place_machine(facility_id, mouse_grid_pos, size):
		print("Cannot place machine: invalid location")
		return

	# Place machine
	var machine_id = FactoryManager.place_machine(facility_id, placement_machine_id, mouse_grid_pos, {
		"size": size
	})

	if not machine_id.is_empty():
		print("Machine placed successfully: %s" % machine_id)
		_create_machine_visual(machine_id)


func _cancel_placement() -> void:
	"""Cancel placement mode"""
	placement_mode = false
	placement_machine_id = ""

	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	print("Machine placement cancelled")


# ========================================
# MACHINE VISUALIZATION
# ========================================

func _load_existing_machines() -> void:
	"""Load and visualize all existing machines in this factory"""
	var machines = FactoryManager.get_all_machines(facility_id)

	for machine in machines:
		_create_machine_visual(machine.id)


func _create_machine_visual(machine_id: String) -> void:
	"""Create visual representation of a machine"""
	var machine = FactoryManager.get_machine(facility_id, machine_id)
	if machine.is_empty():
		return

	var machine_node = _create_machine_node(machine)
	machines_container.add_child(machine_node)


func _create_machine_node(machine: Dictionary) -> Node2D:
	"""Create a visual node for a machine"""
	var node = Node2D.new()
	node.name = machine.id
	node.position = machine.world_pos

	var machine_def = DataManager.get_machine_data(machine.type)
	var size = machine.size
	var color = Color(machine_def.get("visual", {}).get("color", "#aaaaaa"))

	# Create sprite for each tile (placeholder - can be replaced with real sprites)
	for x in range(size.x):
		for y in range(size.y):
			var sprite = Sprite2D.new()
			sprite.texture = _create_placeholder_texture(FactoryManager.INTERIOR_TILE_SIZE - 4, color)
			# Sprite2D positions from center, so add TILE_SIZE/2 offset
			sprite.position = Vector2(
				(x - size.x / 2.0) * FactoryManager.INTERIOR_TILE_SIZE + FactoryManager.INTERIOR_TILE_SIZE / 2.0,
				(y - size.y / 2.0) * FactoryManager.INTERIOR_TILE_SIZE + FactoryManager.INTERIOR_TILE_SIZE / 2.0
			)
			node.add_child(sprite)

	# Add label
	var label = Label.new()
	label.text = machine_def.get("name", machine.type)
	label.position = Vector2(-FactoryManager.INTERIOR_TILE_SIZE / 2, -size.y * FactoryManager.INTERIOR_TILE_SIZE / 2 - 20)
	label.add_theme_font_size_override("font_size", 10)
	node.add_child(label)

	return node


func _create_placeholder_texture(tile_size: int, color: Color) -> ImageTexture:
	"""Create a simple colored square texture as placeholder for sprites"""
	var image = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


# ========================================
# NAVIGATION
# ========================================

func _on_back_button_pressed() -> void:
	"""Return to world map"""
	exit_factory()


func exit_factory() -> void:
	"""Exit factory interior and return to world map"""
	print("Exiting factory interior: %s" % facility_id)
	GameManager.exit_factory_view()

	# Load world map scene
	get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn")


func _on_machine_button_pressed(machine_id: String) -> void:
	"""Handle machine button press from UI"""
	start_placement_mode(machine_id)
