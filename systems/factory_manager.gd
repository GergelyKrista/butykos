extends Node

## FactoryManager - Factory interior state and machine management
##
## Manages the tactical layer: 20x20 interior grid, machine placement,
## and factory-level production optimization.

# ========================================
# CONSTANTS
# ========================================

const INTERIOR_GRID_SIZE = Vector2i(20, 20)
const INTERIOR_TILE_SIZE = 64  # pixels per tile (same as world map)

# ========================================
# STATE
# ========================================

# Dictionary of factory interiors: { facility_id: interior_data }
var factory_interiors: Dictionary = {}

# Currently active/viewing factory
var active_factory_id: String = ""

# Counter for generating unique machine IDs
var _next_machine_id: int = 1

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("FactoryManager initialized")

	# Connect to facility events
	EventBus.facility_placed.connect(_on_facility_placed)
	EventBus.facility_removed.connect(_on_facility_removed)
	EventBus.factory_entered.connect(_on_factory_entered)
	EventBus.factory_exited.connect(_on_factory_exited)


# ========================================
# FACTORY INTERIOR MANAGEMENT
# ========================================

func create_factory_interior(facility_id: String) -> Dictionary:
	"""Create interior data for a facility"""

	var interior = {
		"facility_id": facility_id,
		"grid": _initialize_interior_grid(),
		"machines": {},
		"created_date": GameManager.current_date.duplicate()
	}

	factory_interiors[facility_id] = interior
	print("Factory interior created for: %s" % facility_id)

	return interior


func get_factory_interior(facility_id: String) -> Dictionary:
	"""Get interior data for a facility"""
	if not factory_interiors.has(facility_id):
		# Create interior on first access
		return create_factory_interior(facility_id)

	return factory_interiors[facility_id]


func has_interior(facility_id: String) -> bool:
	"""Check if a facility has an interior (some facilities might not)"""
	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return false

	var facility_def = DataManager.get_facility_data(facility.type)
	return facility_def.get("has_interior", false)


func _initialize_interior_grid() -> Array:
	"""Initialize empty interior grid"""
	var grid = []
	for x in range(INTERIOR_GRID_SIZE.x):
		grid.append([])
		for y in range(INTERIOR_GRID_SIZE.y):
			grid[x].append(null)
	return grid


# ========================================
# MACHINE PLACEMENT
# ========================================

func can_place_machine(facility_id: String, grid_pos: Vector2i, machine_size: Vector2i = Vector2i(1, 1)) -> bool:
	"""Check if a machine can be placed at the given interior grid position"""

	var interior = get_factory_interior(facility_id)
	var grid = interior.grid

	# Check bounds
	if grid_pos.x < 0 or grid_pos.y < 0:
		return false
	if grid_pos.x + machine_size.x > INTERIOR_GRID_SIZE.x:
		return false
	if grid_pos.y + machine_size.y > INTERIOR_GRID_SIZE.y:
		return false

	# Check if all tiles are empty
	for x in range(machine_size.x):
		for y in range(machine_size.y):
			if grid[grid_pos.x + x][grid_pos.y + y] != null:
				return false

	return true


func place_machine(facility_id: String, machine_type: String, grid_pos: Vector2i, machine_data: Dictionary = {}) -> String:
	"""Place a machine in factory interior. Returns machine_id or empty string on failure."""

	var interior = get_factory_interior(facility_id)
	var grid = interior.grid

	var size = machine_data.get("size", Vector2i(1, 1))

	if not can_place_machine(facility_id, grid_pos, size):
		push_error("Cannot place machine at position %s" % grid_pos)
		return ""

	# Generate unique ID
	var machine_id = "machine_%d" % _next_machine_id
	_next_machine_id += 1

	# Create machine data
	# Calculate world position at center of machine (not just top-left tile)
	var center_grid_pos = Vector2(
		grid_pos.x + size.x / 2.0,
		grid_pos.y + size.y / 2.0
	)
	var world_pos = Vector2(
		center_grid_pos.x * INTERIOR_TILE_SIZE,
		center_grid_pos.y * INTERIOR_TILE_SIZE
	)

	var machine = {
		"id": machine_id,
		"type": machine_type,
		"grid_pos": grid_pos,
		"size": size,
		"world_pos": world_pos,
		"active": true,
		"created_date": GameManager.current_date.duplicate()
	}

	# Merge with provided data
	machine.merge(machine_data, true)

	# Add to machines registry
	interior.machines[machine_id] = machine

	# Occupy grid tiles
	for x in range(size.x):
		for y in range(size.y):
			grid[grid_pos.x + x][grid_pos.y + y] = machine_id

	print("Machine placed: %s at %s in factory %s" % [machine_type, grid_pos, facility_id])

	return machine_id


func remove_machine(facility_id: String, machine_id: String) -> bool:
	"""Remove a machine from factory interior"""

	var interior = get_factory_interior(facility_id)

	if not interior.machines.has(machine_id):
		push_error("Machine not found: %s" % machine_id)
		return false

	var machine = interior.machines[machine_id]
	var grid = interior.grid
	var grid_pos = machine.grid_pos
	var size = machine.size

	# Clear grid tiles
	for x in range(size.x):
		for y in range(size.y):
			grid[grid_pos.x + x][grid_pos.y + y] = null

	# Remove from registry
	interior.machines.erase(machine_id)

	print("Machine removed: %s from factory %s" % [machine_id, facility_id])
	EventBus.machine_removed.emit(facility_id, machine_id)

	return true


# ========================================
# MACHINE QUERIES
# ========================================

func get_machine(facility_id: String, machine_id: String) -> Dictionary:
	"""Get machine data by ID"""
	var interior = get_factory_interior(facility_id)
	return interior.machines.get(machine_id, {})


func get_machine_at_position(facility_id: String, grid_pos: Vector2i) -> Dictionary:
	"""Get machine at a specific interior grid position"""
	var interior = get_factory_interior(facility_id)
	var grid = interior.grid

	if grid_pos.x < 0 or grid_pos.x >= INTERIOR_GRID_SIZE.x:
		return {}
	if grid_pos.y < 0 or grid_pos.y >= INTERIOR_GRID_SIZE.y:
		return {}

	var machine_id = grid[grid_pos.x][grid_pos.y]
	if machine_id:
		return interior.machines.get(machine_id, {})

	return {}


func get_all_machines(facility_id: String) -> Array[Dictionary]:
	"""Get all machines in a factory"""
	var interior = get_factory_interior(facility_id)
	var result: Array[Dictionary] = []
	result.assign(interior.machines.values())
	return result


# ========================================
# COORDINATE CONVERSION
# ========================================

func interior_grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert interior grid coordinates to world pixel coordinates (center of tile)"""
	return Vector2(
		grid_pos.x * INTERIOR_TILE_SIZE + INTERIOR_TILE_SIZE / 2.0,
		grid_pos.y * INTERIOR_TILE_SIZE + INTERIOR_TILE_SIZE / 2.0
	)


func world_to_interior_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world pixel coordinates to interior grid coordinates"""
	return Vector2i(
		int(world_pos.x / INTERIOR_TILE_SIZE),
		int(world_pos.y / INTERIOR_TILE_SIZE)
	)


func is_valid_interior_grid_position(grid_pos: Vector2i) -> bool:
	"""Check if interior grid position is within bounds"""
	return (grid_pos.x >= 0 and grid_pos.x < INTERIOR_GRID_SIZE.x and
			grid_pos.y >= 0 and grid_pos.y < INTERIOR_GRID_SIZE.y)


# ========================================
# FACILITY EVENT HANDLERS
# ========================================

func _on_facility_placed(facility: Dictionary) -> void:
	"""Handle facility placement - create interior if needed"""
	if has_interior(facility.id):
		create_factory_interior(facility.id)


func _on_facility_removed(facility_id: String) -> void:
	"""Handle facility removal - cleanup interior"""
	if factory_interiors.has(facility_id):
		factory_interiors.erase(facility_id)
		print("Factory interior removed for: %s" % facility_id)


func _on_factory_entered(facility_id: String) -> void:
	"""Handle entering factory interior view"""
	active_factory_id = facility_id
	print("Entered factory interior: %s" % facility_id)


func _on_factory_exited(facility_id: String) -> void:
	"""Handle exiting factory interior view"""
	active_factory_id = ""
	print("Exited factory interior: %s" % facility_id)


# ========================================
# DEBUG
# ========================================

func print_factory_info(facility_id: String) -> void:
	"""Debug: Print factory interior info"""
	var interior = get_factory_interior(facility_id)

	print("=== Factory Interior Info ===")
	print("Facility ID: %s" % facility_id)
	print("Grid size: %s" % INTERIOR_GRID_SIZE)
	print("Total machines: %d" % interior.machines.size())

	for machine_id in interior.machines:
		var machine = interior.machines[machine_id]
		print("  Machine %s: %s at %s" % [machine_id, machine.type, machine.grid_pos])
