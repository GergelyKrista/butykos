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
@onready var tooltip = $UI/HUD/Tooltip
@onready var help_panel = $UI/HUD/HelpPanel
@onready var production_panel = $UI/HUD/ProductionPanel
@onready var production_button = $UI/HUD/ProductionButton
@onready var mode_panel = $UI/HUD/ModePanel
@onready var mode_label = $UI/HUD/ModePanel/ModeLabel

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

# Demolish mode
var demolish_mode: bool = false

# Mouse/input state
var mouse_grid_pos: Vector2i = Vector2i.ZERO
var hovered_facility_id: String = ""

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
	production_button.pressed.connect(_toggle_production_panel)
	production_panel.get_node("MarginContainer/VBoxContainer/HeaderHBox/CloseButton").pressed.connect(_toggle_production_panel)

	# Load existing facilities (important for returning from factory interior)
	_load_existing_facilities()

	# Center camera on isometric grid
	# The center of the grid in cartesian is (25, 25), convert to isometric
	var center_cart = Vector2(WorldManager.GRID_SIZE.x / 2.0, WorldManager.GRID_SIZE.y / 2.0)
	camera.position = WorldManager.cart_to_iso(center_cart)


# ========================================
# INPUT HANDLING
# ========================================

func _input(event: InputEvent) -> void:
	# Update mouse position using proper isometric conversion
	if event is InputEventMouse:
		var world_pos = camera.get_global_mouse_position()
		mouse_grid_pos = WorldManager.world_to_grid(world_pos)

	# Placement mode input
	if placement_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				# Don't place if clicking on UI
				if not _is_mouse_over_ui():
					_try_place_facility()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_placement()

	# Route mode input (clicking handled by Area2D signals now)
	if route_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				# Don't allow clicking on UI to select facilities for routes
				if _is_mouse_over_ui():
					return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_route_mode()

	# Demolish mode input (clicking handled by Area2D signals now)
	if demolish_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				# Don't allow clicking on UI
				if _is_mouse_over_ui():
					return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_demolish_mode()

	# Cancel placement/route/demolish mode with Escape
	if event.is_action_pressed("ui_cancel"):
		if placement_mode:
			_cancel_placement()
			return  # Prevent pause menu from opening
		elif route_mode:
			_cancel_route_mode()
			return  # Prevent pause menu from opening
		elif demolish_mode:
			_cancel_demolish_mode()
			return  # Prevent pause menu from opening
		# If not in any mode, ESC will be handled by pause menu

	# Toggle help panel with F1
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_toggle_help_panel()

	# Quick save with F5
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_quick_save()

	# Quick load with F9
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_quick_load()


func _process(_delta: float) -> void:
	# Update placement preview position
	if placement_mode and placement_preview:
		# Get facility size to properly center the preview
		var facility_def = DataManager.get_facility_data(placement_facility_id)
		var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])

		# Calculate center position using isometric coordinates
		var center_grid_pos = Vector2(
			mouse_grid_pos.x + size.x / 2.0,
			mouse_grid_pos.y + size.y / 2.0
		)
		var world_pos = WorldManager.cart_to_iso(center_grid_pos)

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
	"""Create visual preview for placement using isometric tiles"""
	placement_preview = Node2D.new()
	add_child(placement_preview)

	var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])
	var color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))

	# Try to load sprite texture
	var sprite_path = facility_def.get("visual", {}).get("icon", "")
	var texture = null
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		texture = load(sprite_path)

	# If sprite exists, use it with transparency; otherwise fall back to colored diamonds
	if texture:
		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.modulate = Color(1, 1, 1, 0.7)  # Semi-transparent for preview
		placement_preview.add_child(sprite)
	else:
		# Fallback: Create diamond-shaped preview for each tile
		for x in range(size.x):
			for y in range(size.y):
				var polygon = Polygon2D.new()

				# Create isometric diamond shape (center tiles at 0.5 offset for grid alignment)
				var tile_offset_cart = Vector2(x - size.x / 2.0 + 0.5, y - size.y / 2.0 + 0.5)
				var tile_center_iso = WorldManager.cart_to_iso(tile_offset_cart)

				# Define diamond vertices (isometric tile shape)
				var half_width = WorldManager.TILE_WIDTH / 2.0
				var half_height = WorldManager.TILE_HEIGHT / 2.0
				polygon.polygon = PackedVector2Array([
					tile_center_iso + Vector2(0, -half_height),      # Top
					tile_center_iso + Vector2(half_width, 0),        # Right
					tile_center_iso + Vector2(0, half_height),       # Bottom
					tile_center_iso + Vector2(-half_width, 0)        # Left
				])

				polygon.color = color
				polygon.color.a = 0.5
				placement_preview.add_child(polygon)


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
	"""Apply color modulation to all preview children (sprites or polygons)"""
	if not placement_preview:
		return

	for child in placement_preview.get_children():
		if child is Polygon2D or child is Sprite2D:
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
	"""Create a visual node for a facility with clickable area (isometric)"""
	var area = Area2D.new()
	area.name = facility.id
	area.position = facility.world_pos

	var facility_def = DataManager.get_facility_data(facility.type)
	var size = facility.size
	var color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))

	# Try to load sprite texture
	var sprite_path = facility_def.get("visual", {}).get("icon", "")
	var texture = null
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		texture = load(sprite_path)

	# If sprite exists, use it; otherwise fall back to colored diamonds
	if texture:
		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		area.add_child(sprite)
	else:
		# Fallback: Create isometric diamond for each tile
		for x in range(size.x):
			for y in range(size.y):
				var polygon = Polygon2D.new()

				# Calculate tile position in isometric space (center tiles at 0.5 offset for grid alignment)
				var tile_offset_cart = Vector2(x - size.x / 2.0 + 0.5, y - size.y / 2.0 + 0.5)
				var tile_center_iso = WorldManager.cart_to_iso(tile_offset_cart)

				# Define diamond vertices (isometric tile shape)
				var half_width = WorldManager.TILE_WIDTH / 2.0
				var half_height = WorldManager.TILE_HEIGHT / 2.0
				polygon.polygon = PackedVector2Array([
					tile_center_iso + Vector2(0, -half_height),      # Top
					tile_center_iso + Vector2(half_width, 0),        # Right
					tile_center_iso + Vector2(0, half_height),       # Bottom
					tile_center_iso + Vector2(-half_width, 0)        # Left
				])

				polygon.color = color
				area.add_child(polygon)

	# Add collision shape covering entire facility (approximate with rectangle for now)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	# Approximate size in isometric space
	var iso_width = (size.x + size.y) * WorldManager.TILE_WIDTH / 2.0
	var iso_height = (size.x + size.y) * WorldManager.TILE_HEIGHT / 2.0
	shape.size = Vector2(iso_width, iso_height)
	collision.shape = shape
	area.add_child(collision)

	# Add label above facility
	var label = Label.new()
	label.text = facility_def.get("name", facility.type)
	# Position label at top of facility
	var top_offset = -(size.x + size.y) * WorldManager.TILE_HEIGHT / 2.0 - 20
	label.position = Vector2(-50, top_offset)  # Center label approximately
	label.add_theme_font_size_override("font_size", 12)
	area.add_child(label)

	# Set Z-index for proper rendering order (facilities further back render first)
	area.z_index = facility.grid_pos.y * 100 + facility.grid_pos.x

	# Connect signals
	area.input_event.connect(_on_facility_clicked.bind(facility.id))
	area.mouse_entered.connect(_on_facility_mouse_entered.bind(facility.id))
	area.mouse_exited.connect(_on_facility_mouse_exited.bind(facility.id))

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

		# Demolish mode: delete facility
		if event.pressed and demolish_mode:
			_demolish_facility(facility_id)
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
	# Cancel current placement mode if already in one
	if placement_mode:
		_cancel_placement()

	# Cancel route mode if active
	if route_mode:
		_cancel_route_mode()

	# Cancel demolish mode if active
	if demolish_mode:
		_cancel_demolish_mode()

	start_placement_mode(facility_id)


# ========================================
# ROUTE CREATION
# ========================================

func start_route_mode() -> void:
	"""Enter route creation mode"""
	route_mode = true
	route_source_id = ""
	route_destination_id = ""
	_update_mode_display("📦 ROUTE MODE", Color(0.3, 0.8, 1.0))
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
	_hide_mode_display()
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
	# Cancel placement mode if active
	if placement_mode:
		_cancel_placement()

	start_route_mode()


# ========================================
# DEMOLISH MODE
# ========================================

func start_demolish_mode() -> void:
	"""Enter demolish mode"""
	demolish_mode = true
	_update_mode_display("🔨 DEMOLISH MODE", Color(1.0, 0.3, 0.3))
	print("Demolish mode started - Click any facility to demolish it")


func _demolish_facility(facility_id: String) -> void:
	"""Demolish a facility and refund partial cost"""
	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return

	var facility_def = DataManager.get_facility_data(facility.type)
	var refund = facility_def.get("cost", 0) / 2  # Refund 50% of cost

	print("Demolishing facility: %s (refund: $%d)" % [facility_id, refund])

	# Refund money
	if refund > 0:
		EconomyManager.add_money(refund)

	# Remove facility from WorldManager (this will emit facility_removed signal)
	WorldManager.remove_facility(facility_id)

	# Hide tooltip if it was showing for this facility
	if hovered_facility_id == facility_id:
		hovered_facility_id = ""
		_hide_tooltip()


func _cancel_demolish_mode() -> void:
	"""Cancel demolish mode"""
	demolish_mode = false
	_hide_mode_display()
	print("Demolish mode cancelled")


func _on_demolish_button_pressed() -> void:
	"""Handle demolish button press from UI"""
	# Cancel placement mode if active
	if placement_mode:
		_cancel_placement()

	# Cancel route mode if active
	if route_mode:
		_cancel_route_mode()

	start_demolish_mode()


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
		# Reload world map scene to visualize loaded data
		get_tree().reload_current_scene()
	else:
		print("✗ Load failed")


func _is_in_mode() -> bool:
	"""Check if we're in placement or route mode (for pause menu)"""
	return placement_mode or route_mode


func _is_mouse_over_ui() -> bool:
	"""Check if mouse is over UI elements"""
	var mouse_pos = get_viewport().get_mouse_position()

	# Check if mouse is over bottom bar (build menu)
	var bottom_bar = ui.get_node_or_null("BottomBar")
	if bottom_bar:
		var bottom_bar_rect = Rect2(
			bottom_bar.global_position,
			bottom_bar.size
		)
		if bottom_bar_rect.has_point(mouse_pos):
			return true

	# Check if mouse is over help panel
	if help_panel and help_panel.visible:
		var help_rect = Rect2(
			help_panel.global_position,
			help_panel.size
		)
		if help_rect.has_point(mouse_pos):
			return true

	return false


# ========================================
# TOOLTIP SYSTEM
# ========================================

func _on_facility_mouse_entered(facility_id: String) -> void:
	"""Show tooltip when mouse enters facility"""
	hovered_facility_id = facility_id

	# Visual feedback for demolish mode
	if demolish_mode:
		_highlight_facility(facility_id, Color(1.0, 0.3, 0.3, 1.0))  # Red highlight

	# Only show tooltip if not in demolish mode
	if not demolish_mode:
		_show_facility_tooltip(facility_id)


func _on_facility_mouse_exited(facility_id: String) -> void:
	"""Hide tooltip when mouse exits facility"""
	# Remove highlight
	if demolish_mode:
		_unhighlight_facility(facility_id)

	hovered_facility_id = ""
	_hide_tooltip()


func _show_facility_tooltip(facility_id: String) -> void:
	"""Display tooltip with facility information"""
	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return

	var facility_def = DataManager.get_facility_data(facility.type)

	# Update tooltip content
	tooltip.get_node("MarginContainer/VBoxContainer/FacilityName").text = facility_def.get("name", facility.type)
	tooltip.get_node("MarginContainer/VBoxContainer/FacilityType").text = "Type: %s" % facility.type

	# Production status
	var production_active = facility.get("production_active", false)
	var status_text = "Production: Active" if production_active else "Production: Inactive"
	tooltip.get_node("MarginContainer/VBoxContainer/ProductionStatus").text = status_text

	# Inventory
	var inventory = facility.get("inventory", {})
	var inventory_text = ""
	if inventory.is_empty():
		inventory_text = "  (empty)"
	else:
		for product in inventory:
			var amount = inventory[product]
			inventory_text += "  %s: %d\n" % [product, amount]

	tooltip.get_node("MarginContainer/VBoxContainer/InventoryList").text = inventory_text.strip_edges()

	# Position tooltip near mouse
	var mouse_pos = tooltip.get_viewport().get_mouse_position()
	tooltip.position = mouse_pos + Vector2(20, 20)

	# Make sure tooltip stays on screen
	var tooltip_size = tooltip.size
	var viewport_size = tooltip.get_viewport_rect().size
	if tooltip.position.x + tooltip_size.x > viewport_size.x:
		tooltip.position.x = mouse_pos.x - tooltip_size.x - 20
	if tooltip.position.y + tooltip_size.y > viewport_size.y:
		tooltip.position.y = mouse_pos.y - tooltip_size.y - 20

	tooltip.visible = true


func _hide_tooltip() -> void:
	"""Hide the tooltip"""
	tooltip.visible = false


# ========================================
# HELP PANEL
# ========================================

func _toggle_help_panel() -> void:
	"""Toggle the help panel visibility"""
	help_panel.visible = not help_panel.visible


# ========================================
# PRODUCTION PANEL
# ========================================

func _toggle_production_panel() -> void:
	"""Toggle production statistics panel"""
	production_panel.visible = not production_panel.visible

	if production_panel.visible:
		_update_production_panel()


func _update_production_panel() -> void:
	"""Update production panel with current facility stats"""
	var facility_list = production_panel.get_node("MarginContainer/VBoxContainer/ScrollContainer/FacilityList")

	# Clear existing items
	for child in facility_list.get_children():
		child.queue_free()

	# Get all facilities
	var facilities = WorldManager.get_all_facilities()

	if facilities.is_empty():
		var label = Label.new()
		label.text = "No facilities placed yet"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		facility_list.add_child(label)
		return

	# Add each facility as a list item
	for facility in facilities:
		var facility_def = DataManager.get_facility_data(facility.type)
		var item = _create_production_item(facility, facility_def)
		facility_list.add_child(item)


func _create_production_item(facility: Dictionary, facility_def: Dictionary) -> PanelContainer:
	"""Create a single production item display"""
	var panel = PanelContainer.new()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	# Facility name
	var name_label = Label.new()
	name_label.text = "%s (%s)" % [facility_def.get("name", facility.type), facility.id]
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)

	# Production status
	var status_label = Label.new()
	var is_active = facility.get("production_active", false)
	status_label.text = "Status: %s" % ("Active" if is_active else "Inactive")
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color.GREEN if is_active else Color.GRAY)
	vbox.add_child(status_label)

	# Production rate
	var rate = ProductionManager.get_production_rate(facility.id)
	if rate != "N/A":
		var rate_label = Label.new()
		rate_label.text = "Rate: %s" % rate
		rate_label.add_theme_font_size_override("font_size", 11)
		rate_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		vbox.add_child(rate_label)

	# Get production statistics
	var stats = ProductionManager.get_facility_stats(facility.id)

	# Input/Output summary
	var production_data = facility_def.get("production", {})
	var input_product = production_data.get("input", "")
	var output_product = production_data.get("output", "")

	if not input_product.is_empty():
		var consumed = stats.get("total_consumed", {})
		var consumed_amount = consumed.get(input_product, 0)
		if consumed_amount > 0:
			var input_label = Label.new()
			input_label.text = "Input: %d %s consumed" % [consumed_amount, input_product]
			input_label.add_theme_font_size_override("font_size", 11)
			input_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
			vbox.add_child(input_label)

	if not output_product.is_empty():
		var produced = stats.get("total_produced", {})
		var produced_amount = produced.get(output_product, 0)
		if produced_amount > 0:
			var output_label = Label.new()
			output_label.text = "Output: %d %s produced" % [produced_amount, output_product]
			output_label.add_theme_font_size_override("font_size", 11)
			output_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			vbox.add_child(output_label)

	# Revenue
	var revenue = stats.get("total_revenue", 0)
	if revenue > 0:
		var revenue_label = Label.new()
		revenue_label.text = "Revenue: $%d" % revenue
		revenue_label.add_theme_font_size_override("font_size", 11)
		revenue_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		vbox.add_child(revenue_label)

	# Current inventory
	var inventory = facility.get("inventory", {})
	if not inventory.is_empty():
		var separator = HSeparator.new()
		vbox.add_child(separator)

		var inv_title = Label.new()
		inv_title.text = "Current Inventory:"
		inv_title.add_theme_font_size_override("font_size", 10)
		inv_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(inv_title)

		for product in inventory:
			var amount = inventory[product]
			var item_label = Label.new()
			item_label.text = "  %s: %d" % [product, amount]
			item_label.add_theme_font_size_override("font_size", 10)
			vbox.add_child(item_label)

	return panel


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
# FACILITY DELETION (FOR TESTING)
# ========================================

func _delete_facility(facility_id: String) -> void:
	"""Delete a facility (for testing/debugging)"""
	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return

	print("Deleting facility: %s" % facility_id)

	# Remove from WorldManager (this will emit facility_removed signal)
	WorldManager.remove_facility(facility_id)

	# Hide tooltip if it was showing for this facility
	if hovered_facility_id == facility_id:
		hovered_facility_id = ""
		_hide_tooltip()
