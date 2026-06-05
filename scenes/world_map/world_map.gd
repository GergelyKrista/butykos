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

# Road placement mode
var road_mode: bool = false
var road_type: String = "dirt_road"
var road_preview: Node2D = null
var road_drag_active: bool = false
var road_drag_start: Vector2i = Vector2i.ZERO
var road_previews: Array[Node2D] = []  # For drag line preview

# Field placement mode (from farmhouse UI)
var field_mode: bool = false
var field_farmhouse_id: String = ""
var field_crop_type: String = ""
var field_drag_start: Vector2i = Vector2i.ZERO
var field_drag_active: bool = false
var field_previews: Array[Node2D] = []

# Farmhouse UI
var farmhouse_ui: Control = null

# Logistics Network Panel
var logistics_panel: Control = null

# Mouse/input state
var mouse_grid_pos: Vector2i = Vector2i.ZERO
var hovered_facility_id: String = ""

# Container for farmhouse working-area overlays (semi-transparent tile tints).
# Created in _ready; populated by _show_farmhouse_overlays during farm_field
# placement mode and on farmhouse click. Cleared when leaving those modes.
var farmhouse_overlays_container: Node2D = null

# Right-click crop-selector popup for placed farm_field entities.
# Created in _ready. `crop_selector_target_field_id` remembers which field
# the popup is currently editing (set on show, cleared on pick).
var crop_selector_popup: PopupMenu = null
var crop_selector_target_field_id: String = ""

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

	# Hot-seat ergonomics: changing the active corp resets any in-progress tool
	# (build / road / demolish / route / field) so the previous player's pending
	# action does not leak into the new player's turn.
	EventBus.active_corp_changed.connect(_on_active_corp_changed_reset_modes)

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

	# Initialize farmhouse UI
	_setup_farmhouse_ui()

	# Initialize logistics network panel
	_setup_logistics_panel()

	# Container for farmhouse working-area overlays. Sits behind facility
	# sprites but above grid lines so the player can see the tinted area.
	farmhouse_overlays_container = Node2D.new()
	farmhouse_overlays_container.name = "FarmhouseWorkingAreaOverlays"
	farmhouse_overlays_container.z_index = 5
	add_child(farmhouse_overlays_container)

	# Right-click crop selector for farm_field. Two crops in slice 1
	# (barley, hops) plus a "no crop" option to take a field offline.
	crop_selector_popup = PopupMenu.new()
	crop_selector_popup.name = "CropSelectorPopup"
	crop_selector_popup.add_item("Barley", 0)
	crop_selector_popup.add_item("Hops", 1)
	crop_selector_popup.add_separator()
	crop_selector_popup.add_item("(No crop — leave field idle)", 2)
	crop_selector_popup.id_pressed.connect(_on_crop_selector_item_picked)
	add_child(crop_selector_popup)

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

	# Snapshot mode state BEFORE the mode-specific branches run — used by the
	# bare-board right-click crop-selector check below so that a right-click
	# that cancels a mode does not also fire the popup.
	var was_in_any_mode: bool = placement_mode or route_mode or demolish_mode or road_mode or field_mode

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

	# Road mode input (drag to place line of roads)
	if road_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					if not _is_mouse_over_ui():
						# Start drag
						road_drag_active = true
						road_drag_start = mouse_grid_pos
						_update_road_line_preview()
				else:
					# Mouse released - complete road placement
					if road_drag_active:
						_complete_road_placement()
						road_drag_active = false
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_road_mode()

	# Field placement mode input (from farmhouse UI)
	if field_mode:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					if not _is_mouse_over_ui():
						# Start drag selection
						field_drag_active = true
						field_drag_start = mouse_grid_pos
						_update_field_previews()
				else:
					# Mouse released - complete field placement
					if field_drag_active:
						_complete_field_placement()
						field_drag_active = false
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				_cancel_field_mode()

	# Right-click on a placed farm_field (with no mode active) opens the crop
	# selector. Uses the start-of-frame mode snapshot so that right-clicks
	# which CANCELLED a mode above don't also fire the popup.
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed \
			and not was_in_any_mode \
			and not _is_mouse_over_ui():
		var clicked_facility: Dictionary = WorldManager.get_facility_at_position(mouse_grid_pos)
		if not clicked_facility.is_empty():
			var clicked_def: Dictionary = DataManager.get_facility_data(clicked_facility.type)
			if clicked_def.get("is_farm_field", false):
				_show_crop_selector_for_field(clicked_facility.id)

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
		elif road_mode:
			_cancel_road_mode()
			return  # Prevent pause menu from opening
		elif field_mode:
			_cancel_field_mode()
			return  # Prevent pause menu from opening
		elif farmhouse_ui and farmhouse_ui.visible:
			farmhouse_ui.hide_ui()
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

	# Close farmhouse UI when clicking on empty space (not in any special mode)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not placement_mode and not route_mode and not demolish_mode and not road_mode and not field_mode:
			if not _is_mouse_over_ui() and farmhouse_ui and farmhouse_ui.visible:
				# Check if clicked on empty space (no facility at mouse position)
				var clicked_facility = WorldManager.get_facility_at_position(mouse_grid_pos)
				if clicked_facility.is_empty():
					farmhouse_ui.hide_ui()


func _process(_delta: float) -> void:
	# Update drag previews if in drag mode
	if drag_mode:
		_update_drag_previews()

	# Update road preview position (single tile or line during drag)
	if road_mode:
		if road_drag_active:
			_update_road_line_preview()
		elif road_preview:
			_update_road_preview()

	# Update field placement previews
	if field_mode and field_drag_active:
		_update_field_previews()

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
	# Close farmhouse UI if open
	if farmhouse_ui and farmhouse_ui.visible:
		farmhouse_ui.hide_ui()

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

	# When placing the generic farm_field, light up every farmhouse's working
	# rectangle so the player can see where their drag will actually produce.
	if facility_def.get("is_farm_field", false):
		_show_all_farmhouse_overlays(Color(0.5, 0.85, 0.45, 0.22))

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
		}, GameManager.active_corp_id)

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

	# Clear any farmhouse working-area overlays from farm_field placement mode.
	_clear_farmhouse_overlays()

	print("Placement mode cancelled")


func _on_active_corp_changed_reset_modes(_old_corp_id: String, _new_corp_id: String) -> void:
	"""Cancel any in-progress tool when the active corp changes.
	Guards each cancel by its mode flag so the no-op case stays quiet (the
	individual cancel functions print, which would otherwise spam the console
	on every corp switch)."""
	if placement_mode:
		_cancel_placement()
	if route_mode:
		_cancel_route_mode()
	if demolish_mode:
		_cancel_demolish_mode()
	if road_mode:
		_cancel_road_mode()
	if field_mode:
		_cancel_field_mode()


# ========================================
# FARMHOUSE WORKING-AREA OVERLAYS
# ========================================

func _clear_farmhouse_overlays() -> void:
	"""Remove every farmhouse working-area overlay diamond from the map."""
	if farmhouse_overlays_container == null:
		return
	for child in farmhouse_overlays_container.get_children():
		child.queue_free()


func _draw_farmhouse_overlay(farmhouse_id: String, fill: Color) -> void:
	"""Render one farmhouse's working rectangle as a grid of semi-transparent
	isometric diamonds inside farmhouse_overlays_container."""
	if farmhouse_overlays_container == null:
		return
	var rect: Rect2i = WorldManager.get_farmhouse_working_rect(farmhouse_id)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var half_w: float = WorldManager.TILE_WIDTH / 2.0
	var half_h: float = WorldManager.TILE_HEIGHT / 2.0
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			# Skip tiles outside the playable grid.
			if not WorldManager.is_valid_grid_position(Vector2i(x, y)):
				continue
			# Tile centers sit at half-integer cartesian coords (CLAUDE.md isometric rules §1).
			var tile_center_cart := Vector2(x + 0.5, y + 0.5)
			var tile_center_iso: Vector2 = WorldManager.cart_to_iso(tile_center_cart)
			var poly := Polygon2D.new()
			poly.polygon = PackedVector2Array([
				tile_center_iso + Vector2(0, -half_h),
				tile_center_iso + Vector2(half_w, 0),
				tile_center_iso + Vector2(0, half_h),
				tile_center_iso + Vector2(-half_w, 0),
			])
			poly.color = fill
			farmhouse_overlays_container.add_child(poly)


func _show_all_farmhouse_overlays(fill: Color) -> void:
	"""Clear then redraw working-area overlays for every farmhouse on the map.
	Called when entering farm_field placement mode."""
	_clear_farmhouse_overlays()
	for fh_id in WorldManager.get_all_farmhouse_ids():
		_draw_farmhouse_overlay(fh_id, fill)


# ========================================
# RIGHT-CLICK CROP SELECTOR (farm_field)
# ========================================

func _show_crop_selector_for_field(field_id: String) -> void:
	"""Open the right-click crop popup over `field_id`. The popup pre-checks
	the field's current crop so the player can see what's already assigned."""
	crop_selector_target_field_id = field_id
	# Sync the check marks to the current crop so the player can see assignment.
	var current_crop: String = ProductionManager.field_crop_types.get(field_id, "")
	crop_selector_popup.set_item_checked(crop_selector_popup.get_item_index(0), current_crop == "barley")
	crop_selector_popup.set_item_checked(crop_selector_popup.get_item_index(1), current_crop == "hops")
	# Position popup at the current mouse position in viewport space.
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	crop_selector_popup.position = Vector2i(mouse_pos)
	crop_selector_popup.popup()


func _on_crop_selector_item_picked(id: int) -> void:
	"""Handle a crop choice from the right-click popup."""
	if crop_selector_target_field_id.is_empty():
		return
	var crop: String = ""
	match id:
		0:
			crop = "barley"
		1:
			crop = "hops"
		2:
			crop = ""  # explicit "no crop" — field goes idle
		_:
			return
	ProductionManager.set_field_crop_type(crop_selector_target_field_id, crop)
	crop_selector_target_field_id = ""


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
				}, GameManager.active_corp_id)

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

	print("DEBUG: Creating visual for %s (type: %s) with size %s" % [facility.id, facility.type, size])

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

	# Add label above facility (skip for fields to avoid clutter)
	if not facility_def.get("is_field", false):
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
	"""Create animated sprite for barley field with growth stages (scaled to fit 1x1 tile)"""
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
	animated_sprite.centered = true  # Center the sprite

	# Get first frame to determine sprite dimensions
	var first_texture = sprite_frames.get_frame_texture("grow", 0)
	var sprite_width = first_texture.get_width()
	var sprite_height = first_texture.get_height()

	# Scale sprite to fit a 1x1 isometric tile (64x32 base)
	# The sprite is designed for 2x2, so scale to 0.5
	var target_width = WorldManager.TILE_WIDTH  # 64 pixels
	var scale_factor = target_width / float(sprite_width)
	animated_sprite.scale = Vector2(scale_factor, scale_factor)

	print("DEBUG: Barley sprite %dx%d, target=%d, scale=%.3f" % [sprite_width, sprite_height, target_width, scale_factor])

	# Position at center of the tile (sprite is centered)
	animated_sprite.position = Vector2.ZERO

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
	"""Update barley field animation frames based on global time (synchronized across all fields)"""
	if not facilities_container:
		return

	# Use global game time for synchronized animation across all fields
	# This simulates all crops being on the same growing season
	var cycle_time_ms = 5000.0  # Base production cycle time in milliseconds (5 seconds)
	var elapsed_ms = Time.get_ticks_msec()
	var global_progress = fmod(float(elapsed_ms), cycle_time_ms) / cycle_time_ms

	# Map progress (0.0-1.0) to animation frames (0-5)
	var frame_index = int(global_progress * 6.0)
	frame_index = clampi(frame_index, 0, 5)  # Ensure valid range (max frame is 5)

	for facility_node in facilities_container.get_children():
		# Check if this facility has an animated sprite (stored as metadata)
		if facility_node.has_meta("animated_sprite"):
			var animated_sprite = facility_node.get_meta("animated_sprite") as AnimatedSprite2D
			if not animated_sprite:
				continue

			# Update animation frame (all fields use same frame for sync)
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
		# Get facility data to check type
		var facility = WorldManager.get_facility(facility_id)

		# Check if facility still exists (may have been removed, e.g., by road placement)
		if facility.is_empty():
			return

		var facility_def = DataManager.get_facility_data(facility.type)

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

		# Regular click on farmhouse: open farmhouse UI + light up its working rect.
		if event.pressed and facility_def.get("has_farmhouse_ui", false):
			print("Opening farmhouse UI for: %s" % facility_id)
			_open_farmhouse_ui(facility_id)
			_clear_farmhouse_overlays()
			_draw_farmhouse_overlay(facility_id, Color(0.5, 0.85, 0.45, 0.30))
			return

		# Clicked on non-farmhouse facility: hide farmhouse UI if open, clear overlay.
		if event.pressed and farmhouse_ui and farmhouse_ui.visible:
			farmhouse_ui.hide_ui()
			_clear_farmhouse_overlays()


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

	# Routes are Logistics-owned in v1 (technical-architecture A7); omit corp_id to take the default.
	var connection_id = LogisticsManager.create_connection(route_source_id, route_destination_id, product)

	if not connection_id.is_empty():
		print("Connection created: %s" % connection_id)

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

	# Cancel road mode if active
	if road_mode:
		_cancel_road_mode()

	start_placement_mode(facility_id)


# ========================================
# ROUTE CREATION
# ========================================

func start_route_mode() -> void:
	"""Enter route creation mode"""
	# Close farmhouse UI if open
	if farmhouse_ui and farmhouse_ui.visible:
		farmhouse_ui.hide_ui()

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

	# Special handling for farmhouse - it collects from fields based on crop type
	if source_def.get("has_farmhouse_ui", false):
		var crop_type = ProductionManager.get_farmhouse_crop_type(source_id)
		if not crop_type.is_empty():
			source_output = crop_type  # barley or wheat

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

	# Cancel road mode if active
	if road_mode:
		_cancel_road_mode()

	# Cancel demolish mode if active
	if demolish_mode:
		_cancel_demolish_mode()

	start_route_mode()


# ========================================
# DEMOLISH MODE
# ========================================

func start_demolish_mode() -> void:
	"""Enter demolish mode"""
	# Close farmhouse UI if open
	if farmhouse_ui and farmhouse_ui.visible:
		farmhouse_ui.hide_ui()

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

	# Cancel road mode if active
	if road_mode:
		_cancel_road_mode()

	start_demolish_mode()


# ========================================
# ROAD PLACEMENT MODE
# ========================================

func start_road_mode(road_id: String = "dirt_road") -> void:
	"""Enter road placement mode"""
	# Close farmhouse UI if open
	if farmhouse_ui and farmhouse_ui.visible:
		farmhouse_ui.hide_ui()

	road_mode = true
	road_type = road_id

	# Create preview
	_create_road_preview()

	var road_def = DataManager.get_road_data(road_id)
	var road_name = road_def.get("name", road_id)
	_update_mode_display("🛤️ ROAD MODE: %s" % road_name, Color(0.6, 0.5, 0.3))
	print("Road mode started - Click to place %s" % road_name)


func _create_road_preview() -> void:
	"""Create visual preview for road placement"""
	if road_preview:
		road_preview.queue_free()

	road_preview = Node2D.new()
	add_child(road_preview)
	road_preview.z_index = 1000  # Render above facilities

	# Get road color from data
	var road_def = DataManager.get_road_data(road_type)
	var color = Color("#8B7355")  # Default brown
	if not road_def.is_empty():
		var visual = road_def.get("visual", {})
		color = Color(visual.get("color", "#8B7355"))

	# Create diamond polygon for 1x1 tile
	var polygon = Polygon2D.new()
	var half_width = WorldManager.TILE_WIDTH / 2.0
	var half_height = WorldManager.TILE_HEIGHT / 2.0

	polygon.polygon = PackedVector2Array([
		Vector2(0, -half_height),      # Top
		Vector2(half_width, 0),        # Right
		Vector2(0, half_height),       # Bottom
		Vector2(-half_width, 0)        # Left
	])

	polygon.color = color
	polygon.color.a = 0.6
	road_preview.add_child(polygon)


func _update_road_preview() -> void:
	"""Update road preview position and validity color"""
	if not road_preview:
		return

	# Position at mouse grid position (center of tile)
	var center_cart = Vector2(mouse_grid_pos.x + 0.5, mouse_grid_pos.y + 0.5)
	var world_pos = WorldManager.cart_to_iso(center_cart)
	road_preview.position = world_pos

	# Get road data for cost check
	var road_def = DataManager.get_road_data(road_type)
	var cost = road_def.get("cost", 25)

	# Update color based on validity
	var can_place = WorldManager.can_place_road(mouse_grid_pos)
	var can_afford = EconomyManager.can_afford(cost)

	var polygon = road_preview.get_child(0) as Polygon2D
	if polygon:
		if can_place and can_afford:
			polygon.color = Color(0.5, 1.0, 0.5, 0.6)  # Green
		else:
			polygon.color = Color(1.0, 0.3, 0.3, 0.6)  # Red


func _try_place_road() -> void:
	"""Attempt to place road at current mouse position"""
	var road_def = DataManager.get_road_data(road_type)
	var cost = road_def.get("cost", 25)

	# Check placement validity
	if not WorldManager.can_place_road(mouse_grid_pos):
		print("Cannot place road: invalid location")
		return

	# Check if player can afford
	if not EconomyManager.can_afford(cost):
		print("Cannot place road: insufficient funds")
		return

	# Deduct cost and place road
	EconomyManager.subtract_money(cost, "road_placement")
	WorldManager.place_road(mouse_grid_pos, road_type)
	print("Road placed at %s" % mouse_grid_pos)


func _cancel_road_mode() -> void:
	"""Cancel road placement mode"""
	road_mode = false
	road_type = "dirt_road"
	road_drag_active = false

	if road_preview:
		road_preview.queue_free()
		road_preview = null

	_clear_road_previews()
	_hide_mode_display()
	print("Road mode cancelled")


func _get_road_line_positions(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	"""Get all grid positions along a line from start to end (horizontal or vertical)"""
	var positions: Array[Vector2i] = []

	# Determine if horizontal or vertical line (or diagonal - pick dominant axis)
	var dx = end.x - start.x
	var dy = end.y - start.y

	if abs(dx) >= abs(dy):
		# Horizontal line (or horizontal dominant)
		var step = 1 if dx >= 0 else -1
		for x in range(start.x, end.x + step, step):
			positions.append(Vector2i(x, start.y))
	else:
		# Vertical line
		var step = 1 if dy >= 0 else -1
		for y in range(start.y, end.y + step, step):
			positions.append(Vector2i(start.x, y))

	return positions


func _update_road_line_preview() -> void:
	"""Update road line preview during drag"""
	_clear_road_previews()

	var positions = _get_road_line_positions(road_drag_start, mouse_grid_pos)
	var road_def = DataManager.get_road_data(road_type)
	var cost = road_def.get("cost", 25)
	var running_cost = 0

	for pos in positions:
		var can_place = WorldManager.can_place_road(pos)
		if can_place:
			running_cost += cost
		var can_afford = EconomyManager.can_afford(running_cost) if can_place else false

		# Create preview node
		var preview = Node2D.new()
		add_child(preview)
		preview.z_index = 1000  # Render above facilities

		# Calculate world position
		var center_cart = Vector2(pos.x + 0.5, pos.y + 0.5)
		var world_pos = WorldManager.cart_to_iso(center_cart)
		preview.position = world_pos

		# Create diamond polygon
		var polygon = Polygon2D.new()
		var half_width = WorldManager.TILE_WIDTH / 2.0
		var half_height = WorldManager.TILE_HEIGHT / 2.0

		polygon.polygon = PackedVector2Array([
			Vector2(0, -half_height),
			Vector2(half_width, 0),
			Vector2(0, half_height),
			Vector2(-half_width, 0)
		])

		# Set color based on validity
		if can_place and can_afford:
			polygon.color = Color(0.5, 1.0, 0.5, 0.6)  # Green
		else:
			polygon.color = Color(1.0, 0.3, 0.3, 0.6)  # Red

		preview.add_child(polygon)
		road_previews.append(preview)


func _clear_road_previews() -> void:
	"""Clear all road line previews"""
	for preview in road_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	road_previews.clear()


func _complete_road_placement() -> void:
	"""Complete road placement for the dragged line"""
	var positions = _get_road_line_positions(road_drag_start, mouse_grid_pos)
	var road_def = DataManager.get_road_data(road_type)
	var cost = road_def.get("cost", 25)
	var placed_count = 0

	for pos in positions:
		# Check validity
		if not WorldManager.can_place_road(pos):
			continue

		# Check affordability
		if not EconomyManager.can_afford(cost):
			print("Not enough money to place more roads")
			break

		# Purchase and place
		EconomyManager.subtract_money(cost, "road_placement")
		WorldManager.place_road(pos, road_type)
		placed_count += 1

	print("Placed %d road tiles" % placed_count)
	_clear_road_previews()


func _on_road_button_pressed(road_id: String) -> void:
	"""Handle road button press from UI"""
	# Close research panel if open
	if research_panel.visible:
		research_panel.visible = false

	# Cancel placement mode if active
	if placement_mode:
		_cancel_placement()

	# Cancel route mode if active
	if route_mode:
		_cancel_route_mode()

	# Cancel demolish mode if active
	if demolish_mode:
		_cancel_demolish_mode()

	# Cancel existing road mode if switching types
	if road_mode:
		_cancel_road_mode()

	start_road_mode(road_id)


# ========================================
# FARMHOUSE UI
# ========================================

const FarmhouseUIScene = preload("res://scenes/ui/farmhouse_ui.tscn")

func _setup_farmhouse_ui() -> void:
	"""Initialize the farmhouse UI panel"""
	farmhouse_ui = FarmhouseUIScene.instantiate()
	farmhouse_ui.position = Vector2(50, 100)
	farmhouse_ui.visible = false
	ui.add_child(farmhouse_ui)

	# Connect signals
	farmhouse_ui.place_field_requested.connect(_on_place_field_requested)
	farmhouse_ui.close_requested.connect(_on_farmhouse_ui_closed)


func _open_farmhouse_ui(farmhouse_id: String) -> void:
	"""Open the farmhouse UI for a specific farmhouse"""
	# Cancel any active modes
	if placement_mode:
		_cancel_placement()
	if route_mode:
		_cancel_route_mode()
	if demolish_mode:
		_cancel_demolish_mode()
	if road_mode:
		_cancel_road_mode()
	if field_mode:
		_cancel_field_mode()

	farmhouse_ui.show_for_farmhouse(farmhouse_id)


func _on_place_field_requested(farmhouse_id: String, crop_type: String) -> void:
	"""Handle place field request from farmhouse UI"""
	# Keep farmhouse UI visible during field placement
	# Enter field placement mode
	_start_field_mode(farmhouse_id, crop_type)


func _on_farmhouse_ui_closed() -> void:
	"""Handle farmhouse UI close — clear the working-area overlay."""
	_clear_farmhouse_overlays()


# ========================================
# LOGISTICS NETWORK PANEL
# ========================================

const LogisticsNetworkPanelScene = preload("res://scenes/ui/logistics_network_panel.tscn")

func _setup_logistics_panel() -> void:
	"""Initialize the logistics network panel"""
	logistics_panel = LogisticsNetworkPanelScene.instantiate()
	logistics_panel.visible = false
	ui.add_child(logistics_panel)

	# Connect close signal
	logistics_panel.close_requested.connect(_on_logistics_panel_closed)


func _toggle_logistics_panel() -> void:
	"""Toggle the logistics network panel visibility"""
	if logistics_panel.visible:
		logistics_panel.hide_panel()
	else:
		# Cancel any active modes
		if placement_mode:
			_cancel_placement()
		if route_mode:
			_cancel_route_mode()
		if demolish_mode:
			_cancel_demolish_mode()
		if road_mode:
			_cancel_road_mode()
		if field_mode:
			_cancel_field_mode()
		if farmhouse_ui and farmhouse_ui.visible:
			farmhouse_ui.hide_ui()

		logistics_panel.show_panel()


func _on_logistics_network_button_pressed() -> void:
	"""Handle logistics network button press from UI"""
	# Close research panel if open
	if research_panel.visible:
		research_panel.visible = false

	_toggle_logistics_panel()


func _on_logistics_panel_closed() -> void:
	"""Handle logistics panel close"""
	pass


# ========================================
# FIELD PLACEMENT MODE
# ========================================

func _start_field_mode(farmhouse_id: String, crop_type: String) -> void:
	"""Start field placement mode from a farmhouse"""
	field_mode = true
	field_farmhouse_id = farmhouse_id
	field_crop_type = crop_type
	field_drag_active = false

	# Determine field type based on crop
	var field_type = "barley_field" if crop_type == "barley" else "wheat_field"
	var field_def = DataManager.get_facility_data(field_type)
	var cost = field_def.get("cost", 100)

	_update_mode_display("🌾 FIELD MODE: %s ($%d each)" % [crop_type.capitalize(), cost], Color(0.5, 0.7, 0.3))
	print("Field mode started for farmhouse %s, crop: %s" % [farmhouse_id, crop_type])


func _update_field_previews() -> void:
	"""Update field placement previews during drag"""
	# Clear old previews
	_clear_field_previews()

	# Calculate drag rectangle
	var min_x = mini(field_drag_start.x, mouse_grid_pos.x)
	var max_x = maxi(field_drag_start.x, mouse_grid_pos.x)
	var min_y = mini(field_drag_start.y, mouse_grid_pos.y)
	var max_y = maxi(field_drag_start.y, mouse_grid_pos.y)

	# Get field definition
	var field_type = "barley_field" if field_crop_type == "barley" else "wheat_field"
	var field_def = DataManager.get_facility_data(field_type)
	var cost = field_def.get("cost", 100)

	# Simulate sequential placement to determine which tiles would be valid
	var valid_positions = _simulate_field_placement(min_x, max_x, min_y, max_y)

	# Create preview for each grid position
	var running_cost = 0
	for grid_x in range(min_x, max_x + 1):
		for grid_y in range(min_y, max_y + 1):
			var grid_pos = Vector2i(grid_x, grid_y)

			# Check validity based on simulation
			var can_place = grid_pos in valid_positions
			if can_place:
				running_cost += cost
			var can_afford = EconomyManager.can_afford(running_cost) if can_place else false

			# Create preview node
			var preview = Node2D.new()
			add_child(preview)

			# Calculate world position
			var center_cart = Vector2(grid_pos.x + 0.5, grid_pos.y + 0.5)
			var world_pos = WorldManager.cart_to_iso(center_cart)
			preview.position = world_pos

			# Create diamond polygon
			var polygon = Polygon2D.new()
			var half_width = WorldManager.TILE_WIDTH / 2.0
			var half_height = WorldManager.TILE_HEIGHT / 2.0

			polygon.polygon = PackedVector2Array([
				Vector2(0, -half_height),
				Vector2(half_width, 0),
				Vector2(0, half_height),
				Vector2(-half_width, 0)
			])

			# Set color based on validity
			if can_place and can_afford:
				polygon.color = Color(0.5, 1.0, 0.5, 0.5)  # Green
			else:
				polygon.color = Color(1.0, 0.3, 0.3, 0.5)  # Red

			preview.add_child(polygon)
			field_previews.append(preview)


func _simulate_field_placement(min_x: int, max_x: int, min_y: int, max_y: int) -> Array[Vector2i]:
	"""Simulate sequential field placement to find all valid positions.
	This accounts for tiles that become valid after earlier tiles are placed."""
	var valid_positions: Array[Vector2i] = []

	# Build initial network positions (farmhouse + existing fields)
	var network_positions: Array[Vector2i] = []

	var farmhouse = WorldManager.facilities.get(field_farmhouse_id, {})
	if farmhouse.is_empty():
		return valid_positions

	var farmhouse_def = DataManager.get_facility_data(farmhouse.type)
	var max_distance = farmhouse_def.get("max_field_distance", 10)

	# Add farmhouse positions to network
	var fh_size = farmhouse.size
	var fh_pos = farmhouse.grid_pos
	for x in range(fh_size.x):
		for y in range(fh_size.y):
			network_positions.append(Vector2i(fh_pos.x + x, fh_pos.y + y))

	# Add existing field positions to network
	var existing_children = WorldManager.farmhouse_children.get(field_farmhouse_id, [])
	for child_id in existing_children:
		var child = WorldManager.facilities.get(child_id, {})
		if child.is_empty():
			continue
		var child_size = child.size
		var child_pos = child.grid_pos
		for x in range(child_size.x):
			for y in range(child_size.y):
				network_positions.append(Vector2i(child_pos.x + x, child_pos.y + y))

	# Calculate farmhouse center for distance check
	var farmhouse_center = Vector2(fh_pos.x + fh_size.x / 2.0, fh_pos.y + fh_size.y / 2.0)

	# Iteratively find valid positions - keep looping until no new positions found
	var found_new = true
	while found_new:
		found_new = false
		for grid_x in range(min_x, max_x + 1):
			for grid_y in range(min_y, max_y + 1):
				var grid_pos = Vector2i(grid_x, grid_y)

				# Skip if already valid
				if grid_pos in valid_positions:
					continue

				# Check basic placement validity
				if not WorldManager.can_place_facility(grid_pos, Vector2i(1, 1)):
					continue

				# Check no roads
				if WorldManager.has_road_at(grid_pos):
					continue

				# Check within max distance
				var field_center = Vector2(grid_pos.x + 0.5, grid_pos.y + 0.5)
				if field_center.distance_to(farmhouse_center) > max_distance:
					continue

				# Check adjacency to network (farmhouse, existing fields, or previously valid positions)
				var is_adjacent = false
				for neighbor in WorldManager.get_adjacent_positions(grid_pos):
					if neighbor in network_positions:
						is_adjacent = true
						break

				if is_adjacent:
					valid_positions.append(grid_pos)
					network_positions.append(grid_pos)
					found_new = true

	return valid_positions


func _clear_field_previews() -> void:
	"""Clear all field placement previews"""
	for preview in field_previews:
		if is_instance_valid(preview):
			preview.queue_free()
	field_previews.clear()


func _complete_field_placement() -> void:
	"""Complete field placement for the dragged area"""
	# Calculate drag rectangle
	var min_x = mini(field_drag_start.x, mouse_grid_pos.x)
	var max_x = maxi(field_drag_start.x, mouse_grid_pos.x)
	var min_y = mini(field_drag_start.y, mouse_grid_pos.y)
	var max_y = maxi(field_drag_start.y, mouse_grid_pos.y)

	# Get field definition
	var field_type = "barley_field" if field_crop_type == "barley" else "wheat_field"
	var field_def = DataManager.get_facility_data(field_type)
	var cost = field_def.get("cost", 100)

	var placed_count = 0
	var out_of_money = false

	# Use iterative placement - keep trying until no new fields can be placed
	# This ensures tiles that become valid after earlier placements are not skipped
	var placed_new = true
	while placed_new and not out_of_money:
		placed_new = false
		for grid_x in range(min_x, max_x + 1):
			for grid_y in range(min_y, max_y + 1):
				var grid_pos = Vector2i(grid_x, grid_y)

				# Check validity
				if not WorldManager.can_place_field_for_farmhouse(grid_pos, Vector2i(1, 1), field_farmhouse_id):
					continue

				# Check affordability
				if not EconomyManager.can_afford(cost):
					print("Not enough money to place more fields")
					out_of_money = true
					break

				# Purchase and place
				EconomyManager.subtract_money(cost, "field_placement")

				print("DEBUG: Placing field at %s with size (1, 1)" % grid_pos)
				var field_id = WorldManager.place_facility(field_type, grid_pos, {
					"size": Vector2i(1, 1)
				}, GameManager.active_corp_id)

				if field_id:
					var placed_facility = WorldManager.facilities[field_id]
					print("DEBUG: Field %s placed with size %s" % [field_id, placed_facility.size])
					WorldManager.complete_construction(field_id)

					# Register field with farmhouse
					WorldManager.register_field_with_farmhouse(field_id, field_farmhouse_id)
					ProductionManager.register_field_with_farmhouse(field_id, field_farmhouse_id)

					placed_count += 1
					placed_new = true

			if out_of_money:
				break

	print("Placed %d fields for farmhouse %s" % [placed_count, field_farmhouse_id])

	# Clear previews
	_clear_field_previews()

	# Return to farmhouse UI
	farmhouse_ui.show_for_farmhouse(field_farmhouse_id)
	farmhouse_ui.refresh()

	# Exit field mode
	field_mode = false
	field_farmhouse_id = ""
	field_crop_type = ""
	_hide_mode_display()


func _cancel_field_mode() -> void:
	"""Cancel field placement mode"""
	field_mode = false
	field_farmhouse_id = ""
	field_crop_type = ""
	field_drag_active = false

	_clear_field_previews()
	_hide_mode_display()

	# Re-open farmhouse UI if we had a farmhouse selected
	if not field_farmhouse_id.is_empty():
		farmhouse_ui.show_for_farmhouse(field_farmhouse_id)

	print("Field mode cancelled")


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
	if placement_mode or route_mode or demolish_mode or road_mode or field_mode:
		return true
	# Check open panels
	if research_panel.visible or production_panel.visible or market_panel.visible or help_panel.visible:
		return true
	# Check farmhouse UI
	if farmhouse_ui and farmhouse_ui.visible:
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

	# Check if mouse is over farmhouse UI
	if farmhouse_ui and farmhouse_ui.visible:
		var farmhouse_rect = Rect2(
			farmhouse_ui.global_position,
			farmhouse_ui.size
		)
		if farmhouse_rect.has_point(mouse_pos):
			return true

	# Check if mouse is over logistics network panel
	if logistics_panel and logistics_panel.visible:
		var logistics_rect = Rect2(
			logistics_panel.global_position,
			logistics_panel.size
		)
		if logistics_rect.has_point(mouse_pos):
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
