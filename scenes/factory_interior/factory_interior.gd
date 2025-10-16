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
@onready var connections_renderer: Node2D = null  # Will be created dynamically
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

# Connection mode
var connection_mode: bool = false
var connection_source_machine_id: String = ""
var connection_source_visual: Node2D = null

# Connection deletion mode
var connection_delete_mode: bool = false

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

	# Create connections renderer
	connections_renderer = Node2D.new()
	connections_renderer.name = "ConnectionsRenderer"
	add_child(connections_renderer)
	connections_renderer.z_index = -1  # Draw behind machines

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
				# Don't place if clicking on UI
				if not _is_mouse_over_ui():
					_try_place_machine()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_placement()

	# Connection mode input
	elif connection_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_connection_mode_click()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_connection_mode()

	# Connection deletion mode input
	elif connection_delete_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_delete_connection_click()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_delete_connection_mode()

	# Cancel placement/connection with Escape
	if event.is_action_pressed("ui_cancel"):
		if placement_mode:
			_cancel_placement()
		elif connection_mode:
			_cancel_connection_mode()
		elif connection_delete_mode:
			_cancel_delete_connection_mode()


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

		# Update preview color based on validity
		_update_placement_preview_validity()

	# Update connection visuals every frame
	_update_connections()


func _update_placement_preview_validity() -> void:
	"""Update preview color based on whether placement is valid"""
	if not placement_preview:
		return

	var machine_def = DataManager.get_machine_data(placement_machine_id)
	var size = Vector2i(machine_def.get("size", [1, 1])[0], machine_def.get("size", [1, 1])[1])

	var can_place = FactoryManager.can_place_machine(facility_id, mouse_grid_pos, size)
	var can_afford = EconomyManager.can_afford(machine_def.get("cost", 0))

	# Set color: green if valid, red if invalid
	if can_place and can_afford:
		_modulate_preview(Color(0.5, 1.0, 0.5, 0.7))
	else:
		_modulate_preview(Color(1.0, 0.3, 0.3, 0.7))


func _modulate_preview(color: Color) -> void:
	"""Apply color modulation to all preview children (sprites or rectangles)"""
	if not placement_preview:
		return

	for child in placement_preview.get_children():
		if child is ColorRect or child is Sprite2D:
			child.modulate = color


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

	# Try to load sprite texture (machines use "sprite" field, not "icon")
	var sprite_path = machine_def.get("visual", {}).get("sprite", "")
	var texture = null
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		texture = load(sprite_path)

	# If sprite exists, use it with transparency; otherwise fall back to colored rectangles
	if texture:
		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.modulate = Color(1, 1, 1, 0.7)  # Semi-transparent for preview
		placement_preview.add_child(sprite)
	else:
		# Fallback: Create colored rectangle for each tile
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
	var cost = machine_def.get("cost", 0)

	# Check placement validity
	if not FactoryManager.can_place_machine(facility_id, mouse_grid_pos, size):
		print("Cannot place machine: invalid location")
		return

	# Check if player can afford
	if not EconomyManager.can_afford(cost):
		print("Cannot place machine: insufficient funds (need $%d)" % cost)
		return

	# Purchase machine (subtract money)
	if not EconomyManager.subtract_money(cost, "Machine: %s" % machine_def.get("name", placement_machine_id)):
		print("Cannot place machine: purchase failed")
		return

	# Place machine
	var machine_id = FactoryManager.place_machine(facility_id, placement_machine_id, mouse_grid_pos, {
		"size": size
	})

	if not machine_id.is_empty():
		print("Machine placed successfully: %s (cost: $%d)" % [machine_id, cost])
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
# CONNECTION MODE
# ========================================

func start_connection_mode() -> void:
	"""Enter connection mode - click two machines to connect them"""
	connection_mode = true
	connection_source_machine_id = ""

	if connection_source_visual:
		connection_source_visual.queue_free()
		connection_source_visual = null

	print("Connection mode started - Click first machine (source)")


func _on_connection_mode_click() -> void:
	"""Handle mouse click in connection mode"""
	# Get machine at clicked position
	var clicked_machine = FactoryManager.get_machine_at_position(facility_id, mouse_grid_pos)

	if clicked_machine.is_empty():
		print("No machine at clicked position")
		return

	var clicked_machine_id = clicked_machine.get("id", "")

	# First click - select source machine
	if connection_source_machine_id.is_empty():
		connection_source_machine_id = clicked_machine_id
		print("Source machine selected: %s" % clicked_machine_id)

		# Create visual highlight for source machine
		_create_source_highlight(clicked_machine)

	# Second click - select destination and create connection
	else:
		var destination_machine_id = clicked_machine_id

		# Can't connect machine to itself
		if destination_machine_id == connection_source_machine_id:
			print("Cannot connect machine to itself")
			return

		# Create connection
		var success = FactoryManager.create_connection(
			facility_id,
			connection_source_machine_id,
			destination_machine_id
		)

		if success:
			print("Connection created: %s → %s" % [connection_source_machine_id, destination_machine_id])

			# Reset for next connection
			connection_source_machine_id = ""
			if connection_source_visual:
				connection_source_visual.queue_free()
				connection_source_visual = null

			print("Click next source machine or press Escape to exit connection mode")
		else:
			print("Failed to create connection (may already exist)")


func _create_source_highlight(machine: Dictionary) -> void:
	"""Create visual highlight for selected source machine"""
	if connection_source_visual:
		connection_source_visual.queue_free()

	connection_source_visual = Node2D.new()
	connection_source_visual.z_index = 100  # Draw on top
	add_child(connection_source_visual)

	var machine_def = DataManager.get_machine_data(machine.type)
	var size = machine.size
	var world_pos = machine.world_pos

	# Draw yellow outline around source machine
	var outline = Polygon2D.new()
	outline.color = Color(1.0, 1.0, 0.0, 0.5)  # Yellow semi-transparent
	outline.position = world_pos

	# Create larger diamond outline
	var half_width = (size.x * FactoryManager.INTERIOR_TILE_SIZE) / 2.0 + 4
	var half_height = (size.y * FactoryManager.INTERIOR_TILE_SIZE) / 2.0 + 4

	outline.polygon = PackedVector2Array([
		Vector2(-half_width, 0),
		Vector2(0, -half_height),
		Vector2(half_width, 0),
		Vector2(0, half_height)
	])

	connection_source_visual.add_child(outline)


func _cancel_connection_mode() -> void:
	"""Cancel connection mode"""
	connection_mode = false
	connection_source_machine_id = ""

	if connection_source_visual:
		connection_source_visual.queue_free()
		connection_source_visual = null

	print("Connection mode cancelled")


# ========================================
# CONNECTION DELETION MODE
# ========================================

func start_delete_connection_mode() -> void:
	"""Enter connection deletion mode - click machines to delete their connection"""
	connection_delete_mode = true
	print("Delete connection mode started - Click first machine (source of connection)")


func _on_delete_connection_click() -> void:
	"""Handle mouse click in deletion mode - click two machines to delete their connection"""
	# Get machine at clicked position
	var clicked_machine = FactoryManager.get_machine_at_position(facility_id, mouse_grid_pos)

	if clicked_machine.is_empty():
		print("No machine at clicked position")
		return

	var clicked_machine_id = clicked_machine.get("id", "")

	# First click - select source machine
	if connection_source_machine_id.is_empty():
		connection_source_machine_id = clicked_machine_id
		print("Source machine selected: %s - Now click destination machine" % clicked_machine_id)

		# Create visual highlight for source machine
		_create_source_highlight(clicked_machine)

	# Second click - select destination and delete connection
	else:
		var destination_machine_id = clicked_machine_id

		# Try to remove connection
		var success = FactoryManager.remove_connection(
			facility_id,
			connection_source_machine_id,
			destination_machine_id
		)

		if success:
			print("Connection deleted: %s → %s" % [connection_source_machine_id, destination_machine_id])
		else:
			print("No connection found between %s → %s" % [connection_source_machine_id, destination_machine_id])

		# Reset for next deletion
		connection_source_machine_id = ""
		if connection_source_visual:
			connection_source_visual.queue_free()
			connection_source_visual = null

		print("Click next source machine or press Escape to exit deletion mode")


func _cancel_delete_connection_mode() -> void:
	"""Cancel connection deletion mode"""
	connection_delete_mode = false
	connection_source_machine_id = ""

	if connection_source_visual:
		connection_source_visual.queue_free()
		connection_source_visual = null

	print("Delete connection mode cancelled")


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

	# Try to load sprite texture (machines use "sprite" field, not "icon")
	var sprite_path = machine_def.get("visual", {}).get("sprite", "")
	var texture = null
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		texture = load(sprite_path)

	# If sprite exists, use it; otherwise fall back to colored tiles
	if texture:
		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		node.add_child(sprite)
	else:
		# Fallback: Create colored tile for each grid cell
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
	# Cancel current placement mode if already in one
	if placement_mode:
		_cancel_placement()

	start_placement_mode(machine_id)


func _on_connect_button_pressed() -> void:
	"""Handle connect button press from UI"""
	start_connection_mode()


func _on_delete_connection_button_pressed() -> void:
	"""Handle delete connection button press from UI"""
	start_delete_connection_mode()


# ========================================
# CONNECTION VISUALIZATION
# ========================================

func _update_connections() -> void:
	"""Draw lines showing manual connections between machines"""
	if not connections_renderer:
		return

	# Clear previous connections (remove all children)
	for child in connections_renderer.get_children():
		child.queue_free()

	# Get all manual connections from FactoryManager
	var connections = FactoryManager.get_connections(facility_id)

	# Draw each connection
	for conn in connections:
		var from_machine_id = conn.get("from", "")
		var to_machine_id = conn.get("to", "")

		var from_machine = FactoryManager.get_machine(facility_id, from_machine_id)
		var to_machine = FactoryManager.get_machine(facility_id, to_machine_id)

		if from_machine.is_empty() or to_machine.is_empty():
			continue

		var from_pos = from_machine.get("world_pos", Vector2.ZERO)
		var to_pos = to_machine.get("world_pos", Vector2.ZERO)

		# Calculate direction for arrow
		var direction = (to_pos - from_pos).normalized()

		_draw_connection_line(from_pos, to_pos, direction)


func _draw_connection_line(from_pos: Vector2, to_pos: Vector2, direction: Vector2) -> void:
	"""Draw a single connection line with an arrow"""
	var line = Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.3, 0.8, 1.0, 0.8)  # Light blue
	line.add_point(from_pos)
	line.add_point(to_pos)
	connections_renderer.add_child(line)

	# Draw arrow at midpoint
	var midpoint = (from_pos + to_pos) / 2.0
	var arrow = _create_arrow(midpoint, direction)
	connections_renderer.add_child(arrow)


func _create_arrow(position: Vector2, direction: Vector2) -> Polygon2D:
	"""Create an arrow polygon pointing in the given direction"""
	var arrow = Polygon2D.new()
	arrow.color = Color(1.0, 0.8, 0.2, 0.9)  # Orange/yellow
	arrow.position = position

	# Arrow size
	var arrow_size = 12.0

	# Create arrow shape (triangle pointing in direction)
	var angle = atan2(direction.y, direction.x)
	var tip = Vector2(arrow_size, 0).rotated(angle)
	var left = Vector2(-arrow_size / 2, -arrow_size / 2).rotated(angle)
	var right = Vector2(-arrow_size / 2, arrow_size / 2).rotated(angle)

	arrow.polygon = PackedVector2Array([tip, left, right])

	return arrow


# ========================================
# UI HELPERS
# ========================================

func _is_mouse_over_ui() -> bool:
	"""Check if mouse is over UI elements"""
	var mouse_pos = get_viewport().get_mouse_position()

	# Check if mouse is over machine menu (right panel)
	var machine_menu = ui.get_node_or_null("MachineMenu")
	if machine_menu and machine_menu.visible:
		var menu_rect = Rect2(
			machine_menu.global_position,
			machine_menu.size
		)
		if menu_rect.has_point(mouse_pos):
			return true

	# Check if mouse is over top bar (back button, etc)
	var top_bar = ui.get_node_or_null("TopBar")
	if top_bar:
		var top_bar_rect = Rect2(
			top_bar.global_position,
			top_bar.size
		)
		if top_bar_rect.has_point(mouse_pos):
			return true

	return false
