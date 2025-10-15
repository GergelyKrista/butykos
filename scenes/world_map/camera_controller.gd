extends Camera2D

## CameraController - Camera controls for the world map
##
## Handles panning (middle mouse drag) and zooming (mouse wheel).

# ========================================
# CONFIGURATION
# ========================================

@export var zoom_min: float = 0.25
@export var zoom_max: float = 2.0
@export var zoom_step: float = 0.1

@export var pan_speed: float = 1.0
@export var edge_pan_enabled: bool = false
@export var edge_pan_margin: float = 20.0
@export var edge_pan_speed: float = 500.0

# ========================================
# STATE
# ========================================

var is_panning: bool = false
var pan_start_position: Vector2 = Vector2.ZERO
var camera_position_at_pan_start: Vector2 = Vector2.ZERO

# ========================================
# INPUT HANDLING
# ========================================

func _input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()

		# Middle mouse button panning
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_start_pan()
			else:
				_end_pan()

	# Mouse motion for panning
	if event is InputEventMouseMotion and is_panning:
		_update_pan(event.relative)


func _process(delta: float) -> void:
	# Edge panning (optional)
	if edge_pan_enabled and not is_panning:
		_handle_edge_pan(delta)

	# Clamp camera to grid bounds
	_clamp_camera_position()


# ========================================
# ZOOM
# ========================================

func zoom_in() -> void:
	"""Zoom in by zoom_step"""
	var new_zoom = zoom.x + zoom_step
	new_zoom = clamp(new_zoom, zoom_min, zoom_max)
	zoom = Vector2(new_zoom, new_zoom)


func zoom_out() -> void:
	"""Zoom out by zoom_step"""
	var new_zoom = zoom.x - zoom_step
	new_zoom = clamp(new_zoom, zoom_min, zoom_max)
	zoom = Vector2(new_zoom, new_zoom)


func set_zoom_level(level: float) -> void:
	"""Set zoom to specific level"""
	level = clamp(level, zoom_min, zoom_max)
	zoom = Vector2(level, level)


# ========================================
# PANNING
# ========================================

func _start_pan() -> void:
	"""Start panning with middle mouse button"""
	is_panning = true
	pan_start_position = get_viewport().get_mouse_position()
	camera_position_at_pan_start = position


func _update_pan(relative_motion: Vector2) -> void:
	"""Update camera position while panning"""
	position -= relative_motion / zoom.x


func _end_pan() -> void:
	"""End panning"""
	is_panning = false


func _handle_edge_pan(delta: float) -> void:
	"""Pan camera when mouse is near screen edges"""
	var viewport = get_viewport()
	if not viewport:
		return

	var mouse_pos = viewport.get_mouse_position()
	var viewport_size = viewport.get_visible_rect().size

	var pan_direction = Vector2.ZERO

	# Check edges
	if mouse_pos.x < edge_pan_margin:
		pan_direction.x = -1
	elif mouse_pos.x > viewport_size.x - edge_pan_margin:
		pan_direction.x = 1

	if mouse_pos.y < edge_pan_margin:
		pan_direction.y = -1
	elif mouse_pos.y > viewport_size.y - edge_pan_margin:
		pan_direction.y = 1

	# Apply panning
	if pan_direction != Vector2.ZERO:
		position += pan_direction.normalized() * edge_pan_speed * delta / zoom.x


# ========================================
# BOUNDS
# ========================================

func _clamp_camera_position() -> void:
	"""Keep camera within isometric grid bounds"""
	var grid_size = WorldManager.GRID_SIZE
	var viewport_size = get_viewport_rect().size / zoom

	# Calculate isometric grid bounds
	# Top corner (0,0) -> iso (0,0)
	# Right corner (50,0) -> iso (800, 400)
	# Left corner (0,50) -> iso (-800, 400)
	# Bottom corner (50,50) -> iso (0, 800)
	var iso_half_width = grid_size.x * WorldManager.TILE_WIDTH / 2.0
	var iso_half_height = grid_size.y * WorldManager.TILE_HEIGHT / 2.0
	var iso_total_height = (grid_size.x + grid_size.y) * WorldManager.TILE_HEIGHT / 2.0

	# Calculate bounds with viewport padding
	var min_x = -iso_half_width + viewport_size.x / 2.0
	var max_x = iso_half_width - viewport_size.x / 2.0
	var min_y = viewport_size.y / 2.0
	var max_y = iso_total_height - viewport_size.y / 2.0

	# Clamp position
	position.x = clamp(position.x, min_x, max_x)
	position.y = clamp(position.y, min_y, max_y)


# ========================================
# UTILITY
# ========================================

func focus_on_position(world_pos: Vector2, zoom_level: float = 1.0) -> void:
	"""Move camera to focus on a specific world position"""
	position = world_pos
	set_zoom_level(zoom_level)


func focus_on_grid_position(grid_pos: Vector2i, zoom_level: float = 1.0) -> void:
	"""Move camera to focus on a specific grid position"""
	var world_pos = WorldManager.grid_to_world(grid_pos)
	focus_on_position(world_pos, zoom_level)
