extends Node

## WorldManager - World map grid, facility placement, and resource management
##
## Manages the strategic layer: 50x50 grid, facility placement, terrain, and logistics connections.
## Singleton autoload for global access.

# ========================================
# CONSTANTS
# ========================================

const GRID_SIZE = Vector2i(50, 50)
const TILE_WIDTH = 32  # Width of isometric tile (2:1 ratio)
const TILE_HEIGHT = 16  # Height of isometric tile
const TILE_SIZE = 64  # Legacy reference for compatibility (use TILE_WIDTH/HEIGHT for isometric)

# ========================================
# STATE
# ========================================

# Dictionary of all placed facilities: { facility_id: facility_data }
var facilities: Dictionary = {}

# 2D grid tracking what's at each position: grid[x][y] = facility_id or null
var grid: Array = []

# Counter for generating unique facility IDs
var _next_facility_id: int = 1

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("WorldManager initialized")
	_initialize_grid()

	# Connect to save/load events
	EventBus.before_save.connect(_on_before_save)
	EventBus.after_load.connect(_on_after_load)


func _initialize_grid() -> void:
	"""Initialize empty grid"""
	grid.clear()
	for x in range(GRID_SIZE.x):
		grid.append([])
		for y in range(GRID_SIZE.y):
			grid[x].append(null)


# ========================================
# FACILITY PLACEMENT
# ========================================

func can_place_facility(grid_pos: Vector2i, facility_size: Vector2i = Vector2i(1, 1)) -> bool:
	"""Check if a facility can be placed at the given grid position"""

	# Check bounds
	if grid_pos.x < 0 or grid_pos.y < 0:
		return false
	if grid_pos.x + facility_size.x > GRID_SIZE.x:
		return false
	if grid_pos.y + facility_size.y > GRID_SIZE.y:
		return false

	# Check if all tiles are empty
	for x in range(facility_size.x):
		for y in range(facility_size.y):
			if grid[grid_pos.x + x][grid_pos.y + y] != null:
				return false

	return true


func place_facility(facility_type: String, grid_pos: Vector2i, facility_data: Dictionary = {}) -> String:
	"""Place a facility on the world map. Returns facility_id or empty string on failure."""

	var size = facility_data.get("size", Vector2i(1, 1))

	if not can_place_facility(grid_pos, size):
		push_error("Cannot place facility at position %s" % grid_pos)
		return ""

	# Generate unique ID
	var facility_id = "facility_%d" % _next_facility_id
	_next_facility_id += 1

	# Create facility data
	# Calculate world position at center of facility using isometric coordinates
	var center_grid_pos = Vector2(
		grid_pos.x + size.x / 2.0,
		grid_pos.y + size.y / 2.0
	)
	var world_pos = cart_to_iso(center_grid_pos)

	var facility = {
		"id": facility_id,
		"type": facility_type,
		"grid_pos": grid_pos,
		"size": size,
		"world_pos": world_pos,
		"constructed": false,
		"construction_progress": 0.0,
		"production_active": false,
		"inventory": {},
		"created_date": GameManager.current_date.duplicate(),
	}

	# Merge with provided data
	facility.merge(facility_data, true)

	# Add to facilities registry
	facilities[facility_id] = facility

	# Occupy grid tiles
	for x in range(size.x):
		for y in range(size.y):
			grid[grid_pos.x + x][grid_pos.y + y] = facility_id

	print("Facility placed: %s at %s" % [facility_type, grid_pos])
	EventBus.facility_placed.emit(facility)

	return facility_id


func remove_facility(facility_id: String) -> bool:
	"""Remove a facility from the world map"""

	if not facilities.has(facility_id):
		push_error("Facility not found: %s" % facility_id)
		return false

	var facility = facilities[facility_id]
	var grid_pos = facility.grid_pos
	var size = facility.size

	# Clear grid tiles
	for x in range(size.x):
		for y in range(size.y):
			grid[grid_pos.x + x][grid_pos.y + y] = null

	# Remove from registry
	facilities.erase(facility_id)

	print("Facility removed: %s" % facility_id)
	EventBus.facility_removed.emit(facility_id)

	return true


# ========================================
# FACILITY QUERIES
# ========================================

func get_facility(facility_id: String) -> Dictionary:
	"""Get facility data by ID"""
	return facilities.get(facility_id, {})


func get_facility_at_position(grid_pos: Vector2i) -> Dictionary:
	"""Get facility at a specific grid position"""
	if not is_valid_grid_position(grid_pos):
		return {}

	var facility_id = grid[grid_pos.x][grid_pos.y]
	if facility_id:
		return facilities.get(facility_id, {})

	return {}


func get_facilities_by_type(facility_type: String) -> Array[Dictionary]:
	"""Get all facilities of a specific type"""
	var result: Array[Dictionary] = []
	for facility in facilities.values():
		if facility.type == facility_type:
			result.append(facility)
	return result


func get_all_facilities() -> Array[Dictionary]:
	"""Get all facilities"""
	var result: Array[Dictionary] = []
	result.assign(facilities.values())
	return result


# ========================================
# PRODUCTION MANAGEMENT
# ========================================

func start_production(facility_id: String) -> bool:
	"""Start production at a facility"""
	if not facilities.has(facility_id):
		return false

	var facility = facilities[facility_id]

	if not facility.constructed:
		push_error("Cannot start production: facility not constructed")
		return false

	facility.production_active = true
	EventBus.production_changed.emit(facility_id, true)
	return true


func stop_production(facility_id: String) -> bool:
	"""Stop production at a facility"""
	if not facilities.has(facility_id):
		return false

	var facility = facilities[facility_id]
	facility.production_active = false
	EventBus.production_changed.emit(facility_id, false)
	return true


func complete_construction(facility_id: String) -> void:
	"""Mark a facility as fully constructed"""
	if facilities.has(facility_id):
		facilities[facility_id].constructed = true
		facilities[facility_id].construction_progress = 1.0
		EventBus.facility_constructed.emit(facility_id)
		print("Facility constructed: %s" % facility_id)


# ========================================
# COORDINATE CONVERSION
# ========================================

func cart_to_iso(cart_pos: Vector2) -> Vector2:
	"""Convert cartesian (grid) coordinates to isometric screen coordinates"""
	var iso_x = (cart_pos.x - cart_pos.y) * (TILE_WIDTH / 2.0)
	var iso_y = (cart_pos.x + cart_pos.y) * (TILE_HEIGHT / 2.0)
	return Vector2(iso_x, iso_y)


func iso_to_cart(iso_pos: Vector2) -> Vector2:
	"""Convert isometric screen coordinates to cartesian (grid) coordinates"""
	var cart_x = (iso_pos.x / (TILE_WIDTH / 2.0) + iso_pos.y / (TILE_HEIGHT / 2.0)) / 2.0
	var cart_y = (iso_pos.y / (TILE_HEIGHT / 2.0) - iso_pos.x / (TILE_WIDTH / 2.0)) / 2.0
	return Vector2(cart_x, cart_y)


func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid coordinates to world pixel coordinates (isometric)"""
	# Convert to cartesian float first for accurate isometric conversion
	var cart_pos = Vector2(grid_pos.x, grid_pos.y)
	return cart_to_iso(cart_pos)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world pixel coordinates to grid coordinates (isometric)"""
	var cart_pos = iso_to_cart(world_pos)
	return Vector2i(
		int(floor(cart_pos.x)),
		int(floor(cart_pos.y))
	)


func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	"""Check if grid position is within bounds"""
	return (grid_pos.x >= 0 and grid_pos.x < GRID_SIZE.x and
			grid_pos.y >= 0 and grid_pos.y < GRID_SIZE.y)


# ========================================
# SAVE/LOAD
# ========================================

func _on_before_save() -> void:
	"""Prepare data for saving"""
	# Save data will be gathered by SaveManager
	pass


func _on_after_load() -> void:
	"""Restore state after loading"""
	# TODO: Restore facilities from save data
	pass


# ========================================
# DEBUG
# ========================================

func print_grid_info() -> void:
	"""Debug: Print grid statistics"""
	print("=== World Grid Info ===")
	print("Grid size: %s" % GRID_SIZE)
	print("Total facilities: %d" % facilities.size())
	print("Occupied tiles: %d / %d" % [_count_occupied_tiles(), GRID_SIZE.x * GRID_SIZE.y])


func _count_occupied_tiles() -> int:
	var count = 0
	for x in range(GRID_SIZE.x):
		for y in range(GRID_SIZE.y):
			if grid[x][y] != null:
				count += 1
	return count
