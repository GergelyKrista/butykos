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
@onready var mode_panel = $UI/HUD/ModePanel
@onready var mode_label = $UI/HUD/ModePanel/ModeLabel

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

# Demolish mode
var demolish_mode: bool = false

# Mouse/input state
var mouse_grid_pos: Vector2i = Vector2i.ZERO

# Per-machine product selector (slice 3.2): right-click an Input Hopper /
# Output Depot to assign which product it carries. Built lazily on first use.
var _machine_product_popup: PopupMenu = null
var _machine_product_target_id: String = ""

# Marching-arrows animation tuning for factory-interior connections —
# mirrors network_view.gd so the two views read with the same visual
# language. t in [0, 1] indexes a point along the connection line; arrows
# slide along while a connection is "flowing" (source has the product to send).
const FLOW_ARROW_SPACING: float = 0.18  # fraction of line length between arrows
const FLOW_ARROW_SPEED: float = 0.3     # arrow positions per second
var _animation_time: float = 0.0

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

	# Slice 3.2: per-machine product selector + label refresh signal.
	_build_machine_product_popup()
	EventBus.machine_config_changed.connect(_on_machine_config_changed)

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
		# Convert viewport mouse position to world coordinates
		var viewport_pos = get_viewport().get_mouse_position()
		var world_pos = camera.get_canvas_transform().affine_inverse() * viewport_pos
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

	# Demolish mode input
	elif demolish_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_demolish_click()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_demolish_mode()
	# Idle (no mode active): right-click on an Input Hopper / Output Depot
	# opens the product-selector popup (slice 3.2). Skipped if any mode is
	# currently active — that case is handled above for cancel.
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed \
			and not _is_mouse_over_ui():
		var clicked: Dictionary = FactoryManager.get_machine_at_position(facility_id, mouse_grid_pos)
		if not clicked.is_empty():
			var m_def: Dictionary = DataManager.get_machine_data(clicked.type)
			if m_def.get("is_input_node", false) or m_def.get("is_output_node", false):
				_show_machine_product_selector(String(clicked.id))

	# Cancel placement/connection/demolish with Escape
	if event.is_action_pressed("ui_cancel"):
		if placement_mode:
			_cancel_placement()
		elif connection_mode:
			_cancel_connection_mode()
		elif connection_delete_mode:
			_cancel_delete_connection_mode()
		elif demolish_mode:
			_cancel_demolish_mode()

	# Quick save with F5
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_quick_save()

	# Quick load with F9
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_quick_load()


func _process(delta: float) -> void:
	# Advance the marching-arrows animation accumulator. Used by
	# _update_connections to slide arrows along active connection lines.
	_animation_time += delta

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

	# Machine corp_id is inherited from the parent facility — no need to pass active_corp_id.
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

	_update_mode_display("🔗 CONNECT MODE", Color(0.3, 0.8, 1.0))
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

	_hide_mode_display()
	print("Connection mode cancelled")


# ========================================
# CONNECTION DELETION MODE
# ========================================

func start_delete_connection_mode() -> void:
	"""Enter connection deletion mode - click machines to delete their connection"""
	connection_delete_mode = true
	_update_mode_display("✂️ DELETE CONNECTION", Color(1.0, 0.6, 0.2))
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

	_hide_mode_display()
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
	# Slice 3.2: refresh the product label for IO machines.
	_update_machine_config_label(machine_id)


# ========================================
# SLICE 3.2 — PER-MACHINE PRODUCT CONFIG
# ========================================

func _build_machine_product_popup() -> void:
	"""Build the right-click product selector once. Items list is the
	full products.json (sorted by display name) so the player can wire any
	hopper to any product, plus a "(Clear)" option at the bottom. Each
	product entry is decorated with a small color swatch matching the
	connection-line color so the hopper config visibly drives the flow."""
	_machine_product_popup = PopupMenu.new()
	_machine_product_popup.name = "MachineProductPopup"
	# Sort by display name for predictability.
	var entries: Array = []
	for product_id in DataManager.products.keys():
		var product_def: Dictionary = DataManager.products[product_id]
		entries.append({"id": String(product_id), "name": String(product_def.get("name", product_id))})
	entries.sort_custom(func(a, b): return a.name < b.name)
	for e in entries:
		var swatch: Texture2D = _create_color_swatch(DataManager.get_product_color(e.id))
		_machine_product_popup.add_icon_item(swatch, e.name)
		# Stash the product id on the item so the picker can read it back.
		_machine_product_popup.set_item_metadata(_machine_product_popup.item_count - 1, e.id)
	_machine_product_popup.add_separator()
	_machine_product_popup.add_item("(Clear)")
	_machine_product_popup.set_item_metadata(_machine_product_popup.item_count - 1, "")
	_machine_product_popup.index_pressed.connect(_on_machine_product_picked)
	add_child(_machine_product_popup)


func _create_color_swatch(color: Color, px: int = 16) -> Texture2D:
	"""Small solid-color square texture used as a popup-item icon. White
	border edge keeps the swatch readable against any popup background."""
	var image: Image = Image.create(px, px, false, Image.FORMAT_RGBA8)
	image.fill(color)
	# 1px white border for contrast.
	for x in range(px):
		image.set_pixel(x, 0, Color.WHITE)
		image.set_pixel(x, px - 1, Color.WHITE)
	for y in range(px):
		image.set_pixel(0, y, Color.WHITE)
		image.set_pixel(px - 1, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _show_machine_product_selector(machine_id: String) -> void:
	_machine_product_target_id = machine_id
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	_machine_product_popup.position = Vector2i(mouse_pos)
	_machine_product_popup.popup()


func _on_machine_product_picked(index: int) -> void:
	if _machine_product_target_id.is_empty():
		return
	var product_id: String = String(_machine_product_popup.get_item_metadata(index))
	FactoryManager.set_machine_configured_product(facility_id, _machine_product_target_id, product_id)
	_machine_product_target_id = ""


func _on_machine_config_changed(factory_id: String, machine_id: String) -> void:
	"""Refresh the machine's product label so the change reads instantly."""
	if factory_id != facility_id:
		return
	_update_machine_config_label(machine_id)


func _update_machine_config_label(machine_id: String) -> void:
	"""Render a small label above the machine. IO machines show their
	configured product (or no label if unset); all other machines show
	their type name so placed machinery is identifiable at a glance."""
	var node: Node = machines_container.get_node_or_null(machine_id)
	if node == null:
		return
	var machine: Dictionary = FactoryManager.get_machine(facility_id, machine_id)
	if machine.is_empty():
		return
	var def: Dictionary = DataManager.get_machine_data(machine.type)
	var is_io: bool = bool(def.get("is_input_node", false)) or bool(def.get("is_output_node", false))
	var label: Label = node.get_node_or_null("ConfigLabel") as Label

	var label_text: String = ""
	if is_io:
		var product: String = String(machine.get("configured_product", ""))
		if not product.is_empty():
			var product_def: Dictionary = DataManager.products.get(product, {})
			label_text = String(product_def.get("name", product))
	else:
		label_text = String(def.get("name", machine.type))

	if label_text.is_empty():
		if label != null:
			label.queue_free()
		return

	if label == null:
		label = Label.new()
		label.name = "ConfigLabel"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 2)
		label.z_index = 50
		node.add_child(label)
	label.text = label_text
	var size: Vector2i = machine.get("size", Vector2i(1, 1))
	label.position = Vector2(0, -size.y * FactoryManager.INTERIOR_TILE_SIZE / 2.0 - 18)


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

	# Label (machine name or configured product) is added by
	# _update_machine_config_label after the node is mounted.
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

	# Cancel connection mode if active
	if connection_mode:
		_cancel_connection_mode()

	# Cancel connection delete mode if active
	if connection_delete_mode:
		_cancel_delete_connection_mode()

	# Cancel demolish mode if active
	if demolish_mode:
		_cancel_demolish_mode()

	start_placement_mode(machine_id)


func _on_connect_button_pressed() -> void:
	"""Handle connect button press from UI"""
	# Cancel other modes
	if placement_mode:
		_cancel_placement()
	if connection_delete_mode:
		_cancel_delete_connection_mode()
	if demolish_mode:
		_cancel_demolish_mode()

	start_connection_mode()


func _on_delete_connection_button_pressed() -> void:
	"""Handle delete connection button press from UI"""
	# Cancel other modes
	if placement_mode:
		_cancel_placement()
	if connection_mode:
		_cancel_connection_mode()
	if demolish_mode:
		_cancel_demolish_mode()

	start_delete_connection_mode()


func _on_demolish_button_pressed() -> void:
	"""Handle demolish button press from UI"""
	# Cancel other modes
	if placement_mode:
		_cancel_placement()
	if connection_mode:
		_cancel_connection_mode()
	if connection_delete_mode:
		_cancel_delete_connection_mode()

	start_demolish_mode()


# ========================================
# DEMOLISH MODE
# ========================================

func start_demolish_mode() -> void:
	"""Enter demolish mode - click machines to demolish them"""
	demolish_mode = true
	_update_mode_display("🔨 DEMOLISH MODE", Color(1.0, 0.3, 0.3))
	print("Demolish mode started - Click any machine to demolish it")


func _on_demolish_click() -> void:
	"""Handle mouse click in demolish mode"""
	# Get machine at clicked position
	var clicked_machine = FactoryManager.get_machine_at_position(facility_id, mouse_grid_pos)

	if clicked_machine.is_empty():
		print("No machine at clicked position")
		return

	var machine_id = clicked_machine.get("id", "")
	_demolish_machine(machine_id)


func _demolish_machine(machine_id: String) -> void:
	"""Demolish a machine and refund partial cost"""
	var machine = FactoryManager.get_machine(facility_id, machine_id)
	if machine.is_empty():
		return

	var machine_def = DataManager.get_machine_data(machine.type)
	var refund = machine_def.get("cost", 0) / 2  # Refund 50% of cost

	print("Demolishing machine: %s (refund: $%d)" % [machine_id, refund])

	# Refund money
	if refund > 0:
		EconomyManager.add_money(refund)

	# Remove machine visual
	var machine_node = machines_container.get_node_or_null(machine_id)
	if machine_node:
		machine_node.queue_free()

	# Remove machine from FactoryManager (this will also remove connections)
	FactoryManager.remove_machine(facility_id, machine_id)


func _cancel_demolish_mode() -> void:
	"""Cancel demolish mode"""
	demolish_mode = false
	_hide_mode_display()
	print("Demolish mode cancelled")


# ========================================
# CONNECTION VISUALIZATION
# ========================================

func _update_connections() -> void:
	"""Redraw all manual machine-to-machine connections this frame. Lines
	and arrows are colored by the product flowing through the connection
	(matched to the hopper config swatches + network-view socket colors).
	When the source machine has the product available right now, arrows
	march along the line; otherwise a single mid-line arrow indicates the
	connection's direction but signals "nothing flowing yet"."""
	if not connections_renderer:
		return

	for child in connections_renderer.get_children():
		child.queue_free()

	var connections = FactoryManager.get_connections(facility_id)
	for conn in connections:
		var from_machine_id: String = String(conn.get("from", ""))
		var to_machine_id: String = String(conn.get("to", ""))

		var from_machine: Dictionary = FactoryManager.get_machine(facility_id, from_machine_id)
		var to_machine: Dictionary = FactoryManager.get_machine(facility_id, to_machine_id)
		if from_machine.is_empty() or to_machine.is_empty():
			continue

		var from_pos: Vector2 = from_machine.get("world_pos", Vector2.ZERO)
		var to_pos: Vector2 = to_machine.get("world_pos", Vector2.ZERO)
		var direction: Vector2 = (to_pos - from_pos).normalized()

		var product: String = _get_connection_product(from_machine_id)
		var color: Color = DataManager.get_product_color(product)
		var flowing: bool = _is_connection_flowing(from_machine_id, to_machine_id, product)

		_draw_connection_line(from_pos, to_pos, direction, color, flowing)


func _get_connection_product(source_machine_id: String) -> String:
	"""Return the product carried by a connection sourced at source_machine_id.
	IO nodes carry their `configured_product`; single-input producers carry
	their production.output; recipe-based producers carry the recipe's first
	output. Empty string means "unknown" — connection renders in neutral gray."""
	var machine: Dictionary = FactoryManager.get_machine(facility_id, source_machine_id)
	if machine.is_empty():
		return ""
	var def: Dictionary = DataManager.get_machine_data(machine.type)
	if def.get("is_input_node", false) or def.get("is_output_node", false):
		return String(machine.get("configured_product", ""))
	var production: Dictionary = def.get("production", {})
	var output: String = String(production.get("output", ""))
	if not output.is_empty():
		return output
	var recipe_id: String = String(def.get("recipe_id", ""))
	if not recipe_id.is_empty():
		var recipe: Dictionary = DataManager.get_recipe_data(recipe_id)
		var outputs: Array = recipe.get("outputs", [])
		if outputs.size() > 0:
			return String(outputs[0].get("product", ""))
	return ""


func _is_connection_flowing(source_machine_id: String, dest_machine_id: String, product: String) -> bool:
	"""True iff product can actually move on this connection right now.
	Requires BOTH (a) the source has the product (facility inventory for
	Input Hoppers, machine inventory otherwise) AND (b) the destination has
	buffer room — Output Depots write to facility inventory which is
	unbounded so they always have room. When the destination buffer is
	full, the arrows stop marching so the player can see exactly where the
	chain is stalled."""
	if product.is_empty():
		return false
	var source_machine: Dictionary = FactoryManager.get_machine(facility_id, source_machine_id)
	if source_machine.is_empty():
		return false
	var src_def: Dictionary = DataManager.get_machine_data(source_machine.type)

	# Source has product?
	var has_product: bool
	if src_def.get("is_input_node", false):
		has_product = ProductionManager.get_inventory_item(facility_id, product) > 0
	else:
		has_product = ProductionManager.get_machine_inventory_item(facility_id, source_machine_id, product) > 0
	if not has_product:
		return false

	# Destination has room? Output Depots feed the unbounded facility
	# inventory so they're always a valid sink.
	var dest_machine: Dictionary = FactoryManager.get_machine(facility_id, dest_machine_id)
	if dest_machine.is_empty():
		return false
	var dst_def: Dictionary = DataManager.get_machine_data(dest_machine.type)
	if dst_def.get("is_output_node", false):
		return true
	return ProductionManager._machine_remaining_capacity(facility_id, dest_machine_id, product) > 0


func _draw_connection_line(from_pos: Vector2, to_pos: Vector2, direction: Vector2, color: Color, flowing: bool) -> void:
	"""Draw a line + arrow(s) for one connection. Color encodes the product;
	`flowing` toggles between marching arrows and a single idle arrow."""
	var line := Line2D.new()
	line.width = 3.0
	# Slightly more saturated/transparent line vs. arrow body so the arrows
	# pop on top of the line in the same hue.
	line.default_color = Color(color.r, color.g, color.b, 0.75)
	line.add_point(from_pos)
	line.add_point(to_pos)
	connections_renderer.add_child(line)

	var arrow_size: float = 12.0
	if flowing:
		var t_offset: float = fposmod(_animation_time * FLOW_ARROW_SPEED, FLOW_ARROW_SPACING)
		var t: float = t_offset
		while t < 1.0:
			var arrow := _create_arrow(from_pos.lerp(to_pos, t), direction, color, arrow_size)
			connections_renderer.add_child(arrow)
			t += FLOW_ARROW_SPACING
	else:
		var arrow := _create_arrow(from_pos.lerp(to_pos, 0.7), direction, color, arrow_size)
		connections_renderer.add_child(arrow)


func _create_arrow(position: Vector2, direction: Vector2, color: Color, size: float = 12.0) -> Polygon2D:
	"""Triangle pointing along `direction`, colored to match the line."""
	var arrow := Polygon2D.new()
	arrow.color = color
	arrow.position = position

	var angle: float = atan2(direction.y, direction.x)
	var tip: Vector2 = Vector2(size, 0).rotated(angle)
	var left: Vector2 = Vector2(-size / 2, -size / 2).rotated(angle)
	var right: Vector2 = Vector2(-size / 2, size / 2).rotated(angle)
	arrow.polygon = PackedVector2Array([tip, left, right])
	return arrow


# ========================================
# MODE DISPLAY
# ========================================

func _update_mode_display(text: String, color: Color) -> void:
	"""Show mode indicator panel"""
	if mode_panel and mode_label:
		mode_label.text = text
		mode_label.add_theme_color_override("font_color", color)
		mode_panel.visible = true


func _hide_mode_display() -> void:
	"""Hide mode indicator panel"""
	if mode_panel:
		mode_panel.visible = false


# ========================================
# UI HELPERS
# ========================================

func _is_mouse_over_ui() -> bool:
	"""Check if mouse is over UI elements"""
	var mouse_pos = get_viewport().get_mouse_position()

	# Check if mouse is over bottom bar (navbar with machine buttons)
	var bottom_bar = ui.get_node_or_null("BottomBar")
	if bottom_bar:
		var bottom_bar_rect = Rect2(
			bottom_bar.global_position,
			bottom_bar.size
		)
		if bottom_bar_rect.has_point(mouse_pos):
			return true

	# Check if mouse is over HUD elements
	var hud = ui.get_node_or_null("HUD")
	if hud:
		# Check all visible children of HUD
		for child in hud.get_children():
			if child.visible and child is Control:
				var child_rect = Rect2(
					child.global_position,
					child.size
				)
				if child_rect.has_point(mouse_pos):
					return true

	return false


# ========================================
# SAVE/LOAD
# ========================================

func _quick_save() -> void:
	"""Quick save to slot 'quicksave'"""
	print("Quick saving...")
	var success = SaveManager.save_game("quicksave")
	if success:
		print("✓ Game saved!")
	else:
		print("✗ Save failed")


func _quick_load() -> void:
	"""Quick load from slot 'quicksave'"""
	print("Quick loading...")
	var success = SaveManager.load_game("quicksave")
	if success:
		print("✓ Game loaded! Reloading scene...")
		# Return to world map (load will restore factory state)
		get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn")
	else:
		print("✗ Load failed")
