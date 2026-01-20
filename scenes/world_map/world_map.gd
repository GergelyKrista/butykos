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
@onready var market_panel = $UI/HUD/MarketPanel
@onready var market_button = $UI/HUD/MarketButton
@onready var research_panel = $UI/HUD/ResearchPanel
@onready var research_button = $UI/HUD/ResearchButton
@onready var mode_panel = $UI/HUD/ModePanel
@onready var mode_label = $UI/HUD/ModePanel/ModeLabel

# ========================================
# STATE
# ========================================

# Current placement mode
var placement_mode: bool = false
var placement_facility_id: String = ""
var placement_preview: Node2D = null

# Drag-to-place mode (for fields)
var drag_mode: bool = false
var drag_start_grid_pos: Vector2i = Vector2i.ZERO
var drag_previews: Array[Node2D] = []
var is_field_type: bool = false  # Whether current placement is a field

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
	market_button.pressed.connect(_toggle_market_panel)
	market_panel.get_node("MarginContainer/VBoxContainer/HeaderHBox/CloseButton").pressed.connect(_toggle_market_panel)

	# Connect to market price updates
	MarketManager.prices_updated.connect(_on_prices_updated)

	# Research panel
	research_button.pressed.connect(_toggle_research_panel)
	research_panel.get_node("MarginContainer/VBoxContainer/HeaderHBox/CloseButton").pressed.connect(_toggle_research_panel)
	ResearchManager.research_completed.connect(_on_research_completed)
	ResearchManager.tier_unlocked.connect(_on_tier_unlocked)
	ResearchManager.tier_progress_updated.connect(_on_tier_progress_updated)

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
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					# Mouse button down
					if not _is_mouse_over_ui():
						if is_field_type:
							# Start drag mode for fields
							drag_mode = true
							drag_start_grid_pos = mouse_grid_pos
							_update_drag_previews()
						else:
							# Single placement for non-fields
							_try_place_facility()
				else:
					# Mouse button released
					if drag_mode:
						# Complete drag placement
						_complete_drag_placement()
						drag_mode = false
					# Note: Single placement happens on press, not release
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

	# Cancel panels/modes with Escape - only open pause menu if nothing was active
	if event.is_action_pressed("ui_cancel"):
		# Close any open panels first
		if research_panel.visible:
			research_panel.visible = false
			return  # Prevent pause menu from opening
		elif production_panel.visible:
			production_panel.visible = false
			return
		elif market_panel.visible:
			market_panel.visible = false
			return
		elif help_panel.visible:
			help_panel.visible = false
			return
		# Then cancel any active modes
		elif placement_mode:
			_cancel_placement()
			return  # Prevent pause menu from opening
		elif route_mode:
			_cancel_route_mode()
			return  # Prevent pause menu from opening
		elif demolish_mode:
			_cancel_demolish_mode()
			return  # Prevent pause menu from opening
		# If no panels or modes active, ESC will be handled by pause menu

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
	# Update drag previews if in drag mode
	if drag_mode:
		_update_drag_previews()

	# Update placement preview position
	if placement_mode and placement_preview and not drag_mode:
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

	# Update barley field animations based on production progress
	_update_barley_field_animations()


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

	# Check if this is a field type (agriculture category)
	is_field_type = facility_def.get("category", "") == "agriculture"

	# Create placement preview
	_create_placement_preview(facility_def)

	print("Placement mode started: %s (field: %s)" % [facility_def.name, is_field_type])


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
		sprite.centered = false  # Use manual positioning for proper isometric alignment

		# Position sprite so its bottom-center aligns with the isometric footprint
		var footprint_width = (size.x + size.y) * WorldManager.TILE_WIDTH / 2.0
		var footprint_height = (size.x + size.y) * WorldManager.TILE_HEIGHT / 2.0

		var sprite_width = texture.get_width()
		var sprite_height = texture.get_height()
		sprite.position = Vector2(-sprite_width / 2.0, -sprite_height + footprint_height / 2.0)

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
	is_field_type = false

	if placement_preview:
		placement_preview.queue_free()
		placement_preview = null

	# Clear drag state
	_clear_drag_previews()
	drag_mode = false

	print("Placement mode cancelled")


func _update_drag_previews() -> void:
	"""Update drag placement previews for field facilities"""
	if not drag_mode:
		return

	# Clear old previews
	_clear_drag_previews()

	# Calculate drag rectangle
	var min_x = mini(drag_start_grid_pos.x, mouse_grid_pos.x)
	var max_x = maxi(drag_start_grid_pos.x, mouse_grid_pos.x)
	var min_y = mini(drag_start_grid_pos.y, mouse_grid_pos.y)
	var max_y = maxi(drag_start_grid_pos.y, mouse_grid_pos.y)

	var facility_def = DataManager.get_facility_data(placement_facility_id)
	var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])
	var cost = facility_def.get("cost", 0)
	var color = Color(facility_def.get("visual", {}).get("color", "#ffffff"))

	# Create preview for each position in rectangle
	for grid_x in range(min_x, max_x + 1):
		for grid_y in range(min_y, max_y + 1):
			var grid_pos = Vector2i(grid_x, grid_y)

			# Check if can place
			var can_place = WorldManager.can_place_facility(grid_pos, size)
			var can_afford = EconomyManager.can_afford(cost)

			# Create preview node
			var preview = Node2D.new()
			add_child(preview)

			# Calculate world position
			var center_grid_pos = Vector2(
				grid_pos.x + size.x / 2.0,
				grid_pos.y + size.y / 2.0
			)
			var world_pos = WorldManager.cart_to_iso(center_grid_pos)
			preview.position = world_pos

			# Create diamond polygons for preview
			for x in range(size.x):
				for y in range(size.y):
					var polygon = Polygon2D.new()

					var tile_offset_cart = Vector2(x - size.x / 2.0 + 0.5, y - size.y / 2.0 + 0.5)
					var tile_center_iso = WorldManager.cart_to_iso(tile_offset_cart)

					var half_width = WorldManager.TILE_WIDTH / 2.0
					var half_height = WorldManager.TILE_HEIGHT / 2.0
					polygon.polygon = PackedVector2Array([
						tile_center_iso + Vector2(0, -half_height),
						tile_center_iso + Vector2(half_width, 0),
						tile_center_iso + Vector2(0, half_height),
						tile_center_iso + Vector2(-half_width, 0)
					])

					# Set color based on validity (green if valid, red if not)
					if can_place and can_afford:
						polygon.color = Color(0.5, 1.0, 0.5, 0.5)  # Semi-transparent green
					else:
						polygon.color = Color(1.0, 0.3, 0.3, 0.5)  # Semi-transparent red

					preview.add_child(polygon)

			drag_previews.append(preview)


func _clear_drag_previews() -> void:
	"""Clear all drag placement previews"""
	for preview in drag_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	drag_previews.clear()


func _complete_drag_placement() -> void:
	"""Place all facilities in the drag area"""
	if not drag_mode:
		return

	# Calculate drag rectangle
	var min_x = mini(drag_start_grid_pos.x, mouse_grid_pos.x)
	var max_x = maxi(drag_start_grid_pos.x, mouse_grid_pos.x)
	var min_y = mini(drag_start_grid_pos.y, mouse_grid_pos.y)
	var max_y = maxi(drag_start_grid_pos.y, mouse_grid_pos.y)

	var facility_def = DataManager.get_facility_data(placement_facility_id)
	var size = Vector2i(facility_def.get("size", [1, 1])[0], facility_def.get("size", [1, 1])[1])
	var cost = facility_def.get("cost", 0)

	# Track placed facilities for timer synchronization
	var placed_facilities: Array[String] = []

	# Place all valid facilities
	for grid_x in range(min_x, max_x + 1):
		for grid_y in range(min_y, max_y + 1):
			var grid_pos = Vector2i(grid_x, grid_y)

			# Check if can place
			if not WorldManager.can_place_facility(grid_pos, size):
				continue

			# Check if can afford
			if not EconomyManager.can_afford(cost):
				print("Not enough money to place all fields")
				break

			# Purchase and place
			if EconomyManager.purchase_facility(placement_facility_id):
				var facility_id = WorldManager.place_facility(placement_facility_id, grid_pos, {
					"size": size
				})

				if facility_id:
					WorldManager.complete_construction(facility_id)
					placed_facilities.append(facility_id)

	# Synchronize production timers for all placed fields
	if placed_facilities.size() > 0:
		ProductionManager.synchronize_production_timers(placed_facilities)
		print("Placed %d fields with synchronized timers" % placed_facilities.size())

	# Clear previews
	_clear_drag_previews()


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

	# Special handling for barley field with growth animation
	if facility.type == "barley_field":
		var animated_sprite = _create_barley_field_animation(size)
		if animated_sprite:
			area.add_child(animated_sprite)
			# Store reference for updating animation based on production progress
			area.set_meta("animated_sprite", animated_sprite)
		else:
			# Fallback to colored diamonds if animation creation fails
			_create_facility_diamonds(area, size, color)
	else:
		# Try to load sprite texture for other facilities
		var sprite_path = facility_def.get("visual", {}).get("icon", "")
		var texture = null
		if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
			texture = load(sprite_path)

		# If sprite exists, use it; otherwise fall back to colored diamonds
		if texture:
			var sprite = Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false  # Use manual positioning for proper isometric alignment

			# Position sprite so its bottom-center aligns with the isometric footprint
			# Isometric footprint width/height based on facility size
			var footprint_width = (size.x + size.y) * WorldManager.TILE_WIDTH / 2.0
			var footprint_height = (size.x + size.y) * WorldManager.TILE_HEIGHT / 2.0

			# Sprite offset: bottom-center of sprite should be at center of isometric footprint
			var sprite_width = texture.get_width()
			var sprite_height = texture.get_height()
			sprite.position = Vector2(-sprite_width / 2.0, -sprite_height + footprint_height / 2.0)

			area.add_child(sprite)
		else:
			# Fallback to colored diamonds
			_create_facility_diamonds(area, size, color)

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


func _create_barley_field_animation(size: Vector2i) -> AnimatedSprite2D:
	"""Create animated sprite for barley field with growth stages"""
	# Animation frame paths
	var animation_base_path = "res://assets/sprites/animations/animation_barley_field/"
	var frame_paths = [
		animation_base_path + "sprite_animation_barley_field_stage0.png",
		animation_base_path + "sprite_animation_barley_field_stage1.png",
		animation_base_path + "sprite_animation_barley_field_stage2.png",
		animation_base_path + "sprite_animation_barley_field_stage3.png",
		animation_base_path + "sprite_animation_barley_field_stage4.png",
		animation_base_path + "sprite_animation_barley_field_stage5.png"
	]

	# Check if first frame exists
	if not ResourceLoader.exists(frame_paths[0]):
		print("Barley field animation frames not found")
		return null

	# Create SpriteFrames resource
	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("grow")

	# Load all frames
	for i in range(frame_paths.size()):
		if ResourceLoader.exists(frame_paths[i]):
			var texture = load(frame_paths[i])
			sprite_frames.add_frame("grow", texture, i)
		else:
			print("Warning: Missing barley animation frame: %s" % frame_paths[i])
			return null

	# Create AnimatedSprite2D
	var animated_sprite = AnimatedSprite2D.new()
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.animation = "grow"
	animated_sprite.frame = 0  # Start at stage 0
	animated_sprite.centered = false  # Use manual positioning like static sprites

	# Position sprite using same bottom-center alignment as static sprites
	var footprint_width = (size.x + size.y) * WorldManager.TILE_WIDTH / 2.0
	var footprint_height = (size.x + size.y) * WorldManager.TILE_HEIGHT / 2.0

	# Get first frame to determine sprite dimensions
	var first_texture = sprite_frames.get_frame_texture("grow", 0)
	var sprite_width = first_texture.get_width()
	var sprite_height = first_texture.get_height()
	animated_sprite.position = Vector2(-sprite_width / 2.0, -sprite_height + footprint_height / 2.0)

	print("Barley field animation created with %d frames" % sprite_frames.get_frame_count("grow"))
	return animated_sprite


func _create_facility_diamonds(area: Area2D, size: Vector2i, color: Color) -> void:
	"""Create colored diamond polygons for facility (fallback when no sprite)"""
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


func _update_barley_field_animations() -> void:
	"""Update barley field animation frames based on production progress"""
	if not facilities_container:
		return

	for facility_node in facilities_container.get_children():
		# Check if this facility has an animated sprite (stored as metadata)
		if facility_node.has_meta("animated_sprite"):
			var animated_sprite = facility_node.get_meta("animated_sprite") as AnimatedSprite2D
			if not animated_sprite:
				continue

			# Get facility data from WorldManager
			var facility_id = facility_node.name
			var facilities = WorldManager.get_all_facilities()
			var facility_data = null
			for fac in facilities:
				if fac.id == facility_id:
					facility_data = fac
					break

			if not facility_data:
				continue

			# Get production progress from ProductionManager
			var progress = ProductionManager.get_production_progress(facility_id)

			# Map progress (0.0-1.0) to animation frames (0-5)
			# 6 frames total distributed evenly:
			# Frame 0: 0-16%, Frame 1: 16-33%, Frame 2: 33-50%
			# Frame 3: 50-66%, Frame 4: 66-83%, Frame 5: 83-100%
			var frame_index = int(progress * 6.0)
			frame_index = clampi(frame_index, 0, 5)  # Ensure valid range (max frame is 5)

			# Update animation frame
			if animated_sprite.frame != frame_index:
				animated_sprite.frame = frame_index


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
	# Close research panel if open
	if research_panel.visible:
		research_panel.visible = false

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
	# Close research panel if open
	if research_panel.visible:
		research_panel.visible = false

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
	# Close research panel if open
	if research_panel.visible:
		research_panel.visible = false

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
	"""Check if we're in any mode or have panels open (for pause menu)"""
	# Check active modes
	if placement_mode or route_mode or demolish_mode:
		return true
	# Check open panels
	if research_panel.visible or production_panel.visible or market_panel.visible or help_panel.visible:
		return true
	return false


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
# MARKET PANEL
# ========================================

func _toggle_market_panel() -> void:
	"""Toggle market prices panel"""
	market_panel.visible = not market_panel.visible

	if market_panel.visible:
		_update_market_panel()


func _on_prices_updated() -> void:
	"""Handle market price updates"""
	if market_panel.visible:
		_update_market_panel()


func _update_market_panel() -> void:
	"""Update market panel with current prices and contracts"""
	var price_list = market_panel.get_node("MarginContainer/VBoxContainer/ScrollContainer/PriceList")

	# Clear existing items
	for child in price_list.get_children():
		child.queue_free()

	# Add active contracts section first
	var contracts = MarketManager.get_active_contracts()
	if contracts.size() > 0:
		var contracts_header = Label.new()
		contracts_header.text = "ACTIVE CONTRACTS"
		contracts_header.add_theme_font_size_override("font_size", 14)
		contracts_header.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		price_list.add_child(contracts_header)

		for contract in contracts:
			var contract_item = _create_contract_item(contract)
			price_list.add_child(contract_item)

		var contract_sep = HSeparator.new()
		price_list.add_child(contract_sep)
		var spacer = Control.new()
		spacer.custom_minimum_size.y = 10
		price_list.add_child(spacer)

	# Group products by category
	var categories = {
		"Raw Materials": ["barley", "wheat", "corn", "water"],
		"Processed Materials": ["malt", "mash", "fermented_wash", "raw_spirit"],
		"Finished Products": ["ale", "packaged_ale", "lager", "wheat_beer", "whiskey", "vodka", "premium_whiskey", "aged_spirit"]
	}

	for category_name in categories:
		# Category header
		var header = Label.new()
		header.text = category_name
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", Color(0.8, 0.8, 1.0))
		price_list.add_child(header)

		# Products in category
		for product in categories[category_name]:
			var item = _create_price_item(product)
			price_list.add_child(item)

		# Separator between categories
		var sep = HSeparator.new()
		price_list.add_child(sep)


func _create_price_item(product: String) -> HBoxContainer:
	"""Create a single price item display"""
	var hbox = HBoxContainer.new()

	# Product name
	var name_label = Label.new()
	name_label.text = product.capitalize().replace("_", " ")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(name_label)

	# Current price
	var current_price = MarketManager.get_price(product)
	var base_price = MarketManager.get_base_price(product)
	var price_label = Label.new()
	price_label.text = "$%d" % current_price
	price_label.add_theme_font_size_override("font_size", 12)
	price_label.custom_minimum_size.x = 50
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(price_label)

	# Price change indicator
	var change_percent = MarketManager.get_price_change_percent(product)
	var trend = MarketManager.get_price_trend(product)

	var trend_label = Label.new()
	if change_percent > 0:
		trend_label.text = "+%.0f%%" % change_percent
		trend_label.add_theme_color_override("font_color", Color.GREEN)
	elif change_percent < 0:
		trend_label.text = "%.0f%%" % change_percent
		trend_label.add_theme_color_override("font_color", Color.RED)
	else:
		trend_label.text = "0%"
		trend_label.add_theme_color_override("font_color", Color.GRAY)

	trend_label.add_theme_font_size_override("font_size", 11)
	trend_label.custom_minimum_size.x = 45
	trend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(trend_label)

	# Trend arrow
	var arrow_label = Label.new()
	if trend > 0:
		arrow_label.text = "↑"
		arrow_label.add_theme_color_override("font_color", Color.GREEN)
	elif trend < 0:
		arrow_label.text = "↓"
		arrow_label.add_theme_color_override("font_color", Color.RED)
	else:
		arrow_label.text = "→"
		arrow_label.add_theme_color_override("font_color", Color.GRAY)

	arrow_label.add_theme_font_size_override("font_size", 14)
	arrow_label.custom_minimum_size.x = 20
	hbox.add_child(arrow_label)

	return hbox


func _create_contract_item(contract: Dictionary) -> VBoxContainer:
	"""Create a contract display item"""
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Contract info line
	var info_hbox = HBoxContainer.new()

	var product_name = contract.product.capitalize().replace("_", " ")
	var info_label = Label.new()
	info_label.text = "Deliver %d %s" % [contract.quantity, product_name]
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.add_theme_font_size_override("font_size", 12)
	info_hbox.add_child(info_label)

	var reward_label = Label.new()
	reward_label.text = "$%d" % contract.reward
	reward_label.add_theme_font_size_override("font_size", 12)
	reward_label.add_theme_color_override("font_color", Color.GOLD)
	info_hbox.add_child(reward_label)

	vbox.add_child(info_hbox)

	# Progress line
	var progress_hbox = HBoxContainer.new()

	var progress_label = Label.new()
	var progress_percent = float(contract.quantity_delivered) / contract.quantity * 100
	progress_label.text = "Progress: %d/%d (%.0f%%)" % [contract.quantity_delivered, contract.quantity, progress_percent]
	progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_label.add_theme_font_size_override("font_size", 10)
	progress_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	progress_hbox.add_child(progress_label)

	var deadline_label = Label.new()
	deadline_label.text = "%d days" % contract.deadline_days
	deadline_label.add_theme_font_size_override("font_size", 10)
	deadline_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.6))
	progress_hbox.add_child(deadline_label)

	vbox.add_child(progress_hbox)

	return vbox


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


# ========================================
# RESEARCH PANEL
# ========================================

var visual_research_tree: Control = null
const ResearchTreeScene = preload("res://scenes/ui/research_tree.tscn")

func _toggle_research_panel() -> void:
	"""Toggle research tree panel"""
	research_panel.visible = not research_panel.visible

	if research_panel.visible:
		_setup_visual_research_tree()


func _setup_visual_research_tree() -> void:
	"""Setup the visual research tree in the panel"""
	var branch_list = research_panel.get_node("MarginContainer/VBoxContainer/ScrollContainer/BranchList")

	# Clear old content
	for child in branch_list.get_children():
		child.queue_free()

	# Add tier progress header
	var tier_section = _create_tier_progress_section()
	branch_list.add_child(tier_section)

	# Create visual tree if not exists
	if visual_research_tree != null:
		visual_research_tree.queue_free()

	visual_research_tree = ResearchTreeScene.instantiate()
	visual_research_tree.research_requested.connect(_on_visual_research_requested)

	# Add to container - fills available space
	var tree_holder = Control.new()
	tree_holder.custom_minimum_size = Vector2(1400, 800)
	tree_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_holder.add_child(visual_research_tree)
	branch_list.add_child(tree_holder)


func _on_visual_research_requested(tech_id: String) -> void:
	"""Handle click on visual tree node"""
	var success = ResearchManager.research(tech_id)
	if success:
		_setup_visual_research_tree()
		_update_money_display()


func _on_research_completed(_tech_id: String) -> void:
	"""Handle research completion"""
	if research_panel.visible:
		_setup_visual_research_tree()
	_update_money_display()


func _on_tier_unlocked(tier: int) -> void:
	"""Handle tier unlock"""
	print("Tier %d unlocked!" % tier)
	if research_panel.visible:
		_setup_visual_research_tree()


func _on_tier_progress_updated(_tier: int, _product: String, _delivered: int, _required: int) -> void:
	"""Handle tier progress update"""
	if research_panel.visible:
		_setup_visual_research_tree()


func _update_research_panel() -> void:
	"""Update research panel with current tech tree state"""
	var branch_list = research_panel.get_node("MarginContainer/VBoxContainer/ScrollContainer/BranchList")
	var progress_label = research_panel.get_node("MarginContainer/VBoxContainer/HeaderHBox/ProgressLabel")

	# Update progress counter with tier info
	var unlocked = ResearchManager.get_unlocked_count()
	var total = ResearchManager.get_total_count()
	var current_tier = ResearchManager.get_current_tier()
	progress_label.text = "Tier %d | %d/%d" % [current_tier, unlocked, total]

	# Clear existing items
	for child in branch_list.get_children():
		child.queue_free()

	# Add tier progress section at top
	var tier_section = _create_tier_progress_section()
	branch_list.add_child(tier_section)

	# Add each branch
	for branch in ResearchManager.BRANCHES:
		var branch_container = _create_branch_section(branch)
		branch_list.add_child(branch_container)


func _create_tier_progress_section() -> VBoxContainer:
	"""Create the tier progress section showing requirements for next tier"""
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var current_tier = ResearchManager.get_current_tier()

	# Header
	var header = Label.new()
	if current_tier >= 5:
		header.text = "MAX TIER REACHED"
		header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	else:
		header.text = "TIER %d REQUIREMENTS" % (current_tier + 1)
		header.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	# Show requirements for next tier as sprite placeholders side by side
	if current_tier < 5:
		var items_hbox = HBoxContainer.new()
		items_hbox.add_theme_constant_override("separation", 20)

		var progress = ResearchManager.get_tier_progress()
		for product in progress:
			var info = progress[product]
			var delivered = info["delivered"]
			var required = info["required"]
			var is_complete = delivered >= required

			# Container for each requirement item
			var item_container = Control.new()
			item_container.custom_minimum_size = Vector2(80, 100)

			# Product name label on top
			var name_label = Label.new()
			name_label.text = product.capitalize().replace("_", " ")
			name_label.add_theme_font_size_override("font_size", 11)
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.position = Vector2(0, 0)
			name_label.size = Vector2(80, 20)
			if is_complete:
				name_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			else:
				name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			item_container.add_child(name_label)

			# Sprite placeholder panel (center)
			var sprite_panel = Panel.new()
			sprite_panel.position = Vector2(8, 22)
			sprite_panel.size = Vector2(64, 64)

			var sprite_style = StyleBoxFlat.new()
			sprite_style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
			sprite_style.border_width_left = 2
			sprite_style.border_width_right = 2
			sprite_style.border_width_top = 2
			sprite_style.border_width_bottom = 2
			sprite_style.corner_radius_top_left = 4
			sprite_style.corner_radius_top_right = 4
			sprite_style.corner_radius_bottom_left = 4
			sprite_style.corner_radius_bottom_right = 4

			if is_complete:
				sprite_style.border_color = Color(0.3, 0.8, 0.3)
			else:
				sprite_style.border_color = Color(0.4, 0.4, 0.5)

			sprite_panel.add_theme_stylebox_override("panel", sprite_style)

			# Placeholder text inside sprite panel
			var placeholder_label = Label.new()
			placeholder_label.text = "?"
			placeholder_label.add_theme_font_size_override("font_size", 28)
			placeholder_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
			placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			placeholder_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			sprite_panel.add_child(placeholder_label)

			item_container.add_child(sprite_panel)

			# Amount label in bottom right corner of sprite
			var amount_label = Label.new()
			amount_label.text = "%d/%d" % [delivered, required]
			amount_label.add_theme_font_size_override("font_size", 10)
			amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			amount_label.position = Vector2(8, 70)
			amount_label.size = Vector2(64, 16)

			if is_complete:
				amount_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
			else:
				amount_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))

			item_container.add_child(amount_label)

			items_hbox.add_child(item_container)

		vbox.add_child(items_hbox)

		# Hint text
		var hint = Label.new()
		hint.text = "Sell these products to unlock Tier %d" % (current_tier + 1)
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(hint)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 8
	vbox.add_child(spacer)

	return vbox


func _create_branch_section(branch: String) -> VBoxContainer:
	"""Create a section for one research branch"""
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Branch header with progress
	var header_hbox = HBoxContainer.new()

	var branch_name = ResearchManager.BRANCH_NAMES.get(branch, branch.capitalize())
	var header = Label.new()
	header.text = branch_name
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(header)

	# Branch progress
	var branch_unlocked = ResearchManager.get_branch_unlocked_count(branch)
	var branch_total = ResearchManager.get_branch_total_count(branch)
	var progress = Label.new()
	progress.text = "[%d/%d]" % [branch_unlocked, branch_total]
	progress.add_theme_font_size_override("font_size", 12)
	progress.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	header_hbox.add_child(progress)

	vbox.add_child(header_hbox)

	# Get techs in this branch (sorted by era)
	var techs = ResearchManager.get_branch_techs(branch)

	# Create tech items
	for tech in techs:
		var tech_item = _create_tech_item(tech)
		vbox.add_child(tech_item)

	# Separator after branch
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	return vbox


func _create_tech_item(tech: Dictionary) -> HBoxContainer:
	"""Create a single tech item with research button"""
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var tech_id = tech.get("id", "")
	var is_unlocked = ResearchManager.is_unlocked(tech_id)
	var can_research = ResearchManager.can_research(tech_id)
	var is_tier_locked = ResearchManager.is_tier_locked(tech_id)

	# Tier indicator
	var tier_label = Label.new()
	tier_label.text = "T%d" % tech.get("tier", 1)
	tier_label.add_theme_font_size_override("font_size", 10)
	tier_label.custom_minimum_size.x = 25
	if is_unlocked:
		tier_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	elif is_tier_locked:
		tier_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))  # Red for tier-locked
	else:
		tier_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hbox.add_child(tier_label)

	# Tech name
	var name_label = Label.new()
	name_label.text = tech.get("name", tech_id)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_unlocked:
		name_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	elif can_research:
		name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	elif is_tier_locked:
		name_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))  # Darker for tier-locked
	else:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	hbox.add_child(name_label)

	# Cost / Status
	var cost = tech.get("cost", 0)
	if is_unlocked:
		var status_label = Label.new()
		status_label.text = "DONE"
		status_label.add_theme_font_size_override("font_size", 11)
		status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
		status_label.custom_minimum_size.x = 70
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(status_label)
	elif can_research:
		# Research button
		var research_btn = Button.new()
		research_btn.text = "$%d" % cost
		research_btn.custom_minimum_size.x = 70
		research_btn.pressed.connect(_on_research_button_pressed.bind(tech_id))
		hbox.add_child(research_btn)
	else:
		# Show cost grayed out with appropriate lock icon
		var cost_label = Label.new()
		if is_tier_locked:
			# Tier locked - show tier requirement
			cost_label.text = "T%d" % tech.get("tier", 1)
			cost_label.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
		else:
			# Prerequisite locked
			var missing = ResearchManager.get_missing_prerequisites(tech_id)
			if missing.size() > 0:
				cost_label.text = "🔒 $%d" % cost
			else:
				cost_label.text = "$%d" % cost
			cost_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.custom_minimum_size.x = 70
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(cost_label)

	return hbox


func _on_research_button_pressed(tech_id: String) -> void:
	"""Handle research button press"""
	var success = ResearchManager.research(tech_id)
	if success:
		_update_research_panel()
		_update_money_display()
