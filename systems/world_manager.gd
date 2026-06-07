extends Node

## WorldManager - World map grid, facility placement, and resource management
##
## Manages the strategic layer: 50x50 grid, facility placement, terrain, and logistics connections.
## Singleton autoload for global access.

# ========================================
# CONSTANTS
# ========================================

const GRID_SIZE = Vector2i(50, 50)
const TILE_WIDTH = 64  # Width of isometric tile (2:1 ratio)
const TILE_HEIGHT = 32  # Height of isometric tile
const TILE_SIZE = 64  # Legacy reference for compatibility (use TILE_WIDTH/HEIGHT for isometric)

# ========================================
# STATE
# ========================================

# Dictionary of all placed facilities: { facility_id: facility_data }
var facilities: Dictionary = {}

# 2D grid tracking what's at each position: grid[x][y] = facility_id or null
var grid: Array = []

# Road grid - separate layer: road_grid[x][y] = road_type_id or null
var road_grid: Array = []

# Field-to-farmhouse relationships
var field_parents: Dictionary = {}  # field_id -> farmhouse_id
var farmhouse_children: Dictionary = {}  # farmhouse_id -> [field_ids]

# Counter for generating unique facility IDs
var _next_facility_id: int = 1

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("WorldManager initialized")
	_initialize_grid()
	_initialize_road_grid()

	# Connect to save/load events
	EventBus.before_save.connect(_on_before_save)
	EventBus.after_load.connect(_on_after_load)


func _initialize_grid() -> void:
	"""Initialize empty facility grid"""
	grid.clear()
	for x in range(GRID_SIZE.x):
		grid.append([])
		for y in range(GRID_SIZE.y):
			grid[x].append(null)


func _initialize_road_grid() -> void:
	"""Initialize empty road grid"""
	road_grid.clear()
	for x in range(GRID_SIZE.x):
		road_grid.append([])
		for y in range(GRID_SIZE.y):
			road_grid[x].append(null)


# ========================================
# FACILITY PLACEMENT
# ========================================

func _can_place_facility_geometry(grid_pos: Vector2i, facility_size: Vector2i = Vector2i(1, 1)) -> bool:
	"""Geometry-only occupancy check. Used by UI preview (world_map.gd tile highlighting) and
	by can_place_facility_v2. Does NOT check corp or research unlock."""

	# Check bounds
	if grid_pos.x < 0 or grid_pos.y < 0:
		return false
	if grid_pos.x + facility_size.x > GRID_SIZE.x:
		return false
	if grid_pos.y + facility_size.y > GRID_SIZE.y:
		return false

	# Check if all tiles are empty (no facilities AND no roads)
	for x in range(facility_size.x):
		for y in range(facility_size.y):
			var check_pos = Vector2i(grid_pos.x + x, grid_pos.y + y)
			# Check for existing facility
			if grid[check_pos.x][check_pos.y] != null:
				return false
			# Check for roads - facilities cannot be placed on roads
			if road_grid[check_pos.x][check_pos.y] != null:
				return false

	return true


func can_place_facility_v2(corp_id: String, facility_type: String, grid_pos: Vector2i, facility_size: Vector2i) -> Dictionary:
	"""Predicate for ACTION_PLACE_FACILITY. v1: corp check trivially passes (single corp).
	Phase 10 fills in per-corp build-menu permissions."""
	if not _can_place_facility_geometry(grid_pos, facility_size):
		return { "ok": false, "reason": "Invalid placement: out of bounds or tile occupied" }
	var facility_def: Dictionary = DataManager.get_facility_data(facility_type)
	if facility_def.is_empty():
		return { "ok": false, "reason": "Unknown facility type: %s" % facility_type }
	if not ResearchManager.is_facility_unlocked(facility_type):
		return { "ok": false, "reason": "Facility locked: research required" }
	# Corp permission — v1 trivially passes; Phase 10 reads data/facilities.json `corp` field.
	return { "ok": true, "reason": "" }


func can_remove_facility(corp_id: String, facility_id: String) -> Dictionary:
	"""Predicate for ACTION_DEMOLISH_FACILITY. v1: trivially ok if facility exists."""
	if not facilities.has(facility_id):
		return { "ok": false, "reason": "Facility not found: %s" % facility_id }
	# v1: corp ownership not gated. Phase 10 adds:
	# var facility = facilities[facility_id]
	# if facility.corp_id != corp_id and facility.corp_id != GameManager.CORP_SHARED:
	#     return { "ok": false, "reason": "Corp %s does not own %s" % [corp_id, facility_id] }
	return { "ok": true, "reason": "" }


# Keep the old public name as a passthrough so UI preview code in world_map.gd that calls
# can_place_facility(grid_pos, size) for tile highlighting still compiles until sub-commit C
# rewires those call sites.
# TODO(sub-commit-C): delete after world_map.gd preview call sites are rewired.
func can_place_facility(grid_pos: Vector2i, facility_size: Vector2i = Vector2i(1, 1)) -> bool:
	return _can_place_facility_geometry(grid_pos, facility_size)


func place_facility(facility_type: String, grid_pos: Vector2i, facility_data: Dictionary = {}, corp_id: String = GameManager.CORP_SINGLE) -> String:
	"""Place a facility on the world map. Returns facility_id or empty string on failure."""

	var size = facility_data.get("size", Vector2i(1, 1))

	if not _can_place_facility_geometry(grid_pos, size):
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
		"corp_id": corp_id,            # Phase 8 step 1: ownership field. No gating yet.
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

	print("Facility placed: %s at %s with size %s (grid tiles occupied: %d)" % [facility_type, grid_pos, size, size.x * size.y])
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
# OUTSIDE CONNECTIONS — WORLD GEN
# ========================================

# Deterministic perimeter slots for outside connections. Mid-edges of all four
# sides plus one extra on the north — five total. Picked away from corners so
# the icons read clearly and road-pathing has room. Order is stable so saves
# stay coherent across versions.
const _OUTSIDE_CONNECTION_SPAWN_POSITIONS: Array[Vector2i] = [
	Vector2i(25, 0),    # north mid
	Vector2i(49, 25),   # east mid
	Vector2i(25, 49),   # south mid
	Vector2i(0, 25),    # west mid
	Vector2i(37, 0),    # north-east (extra)
]


func spawn_outside_connections_if_needed() -> int:
	"""Slice-1 Business corp: spawn outside connections at map perimeter on a
	fresh game. Idempotent — if any outside_connection facility already
	exists (loaded from save), returns 0 without spawning. Returns the
	number of newly spawned connections."""
	if not get_facilities_by_type("outside_connection").is_empty():
		return 0

	# Per-product price modifiers initialized to small random offsets so the
	# matrix in the Trading Screen reads as visibly different per destination
	# from tick zero. MarketManager walks these on its 10s tick.
	var spawned: int = 0
	for pos in _OUTSIDE_CONNECTION_SPAWN_POSITIONS:
		var modifiers: Dictionary = {}
		for product in MarketManager.base_prices.keys():
			modifiers[product] = randf_range(0.85, 1.15)
		var facility_id: String = place_facility(
			"outside_connection",
			pos,
			{
				"size": Vector2i(1, 1),
				"price_modifiers": modifiers,
				"constructed": true,             # No build time; ready immediately.
				"production_active": false,      # No production cycle.
			},
			GameManager.CORP_SHARED,
		)
		if not facility_id.is_empty():
			spawned += 1
	if spawned > 0:
		print("World gen: spawned %d outside connections" % spawned)
	return spawned


func get_outside_connections() -> Array[Dictionary]:
	"""All outside_connection facilities currently on the map."""
	return get_facilities_by_type("outside_connection")


# ========================================
# ROAD MANAGEMENT
# ========================================

func _can_place_road_geometry(grid_pos: Vector2i) -> bool:
	"""Geometry-only road placement check. Used by UI preview and can_place_road predicate."""
	if not is_valid_grid_position(grid_pos):
		return false

	# Already has a road
	if road_grid[grid_pos.x][grid_pos.y] != null:
		return false

	# Check if there's a building (non-field facility).
	# grid[x][y] stores facility_id (String) when occupied, null when empty — keep the var untyped.
	var facility_id = grid[grid_pos.x][grid_pos.y]
	if facility_id != null:
		var facility: Dictionary = facilities.get(facility_id, {})
		var facility_def: Dictionary = DataManager.get_facility_data(facility.get("type", ""))
		# Allow placing road over fields only (will destroy the field with refund)
		if not facility_def.get("is_field", false):
			return false

	return true


func can_place_road_v2(corp_id: String, grid_pos: Vector2i) -> Dictionary:
	"""Predicate for ACTION_PLACE_ROAD. Roads are CORP_SHARED; corp check trivially passes in v1."""
	if not _can_place_road_geometry(grid_pos):
		return { "ok": false, "reason": "Cannot place road: out of bounds, occupied by building, or already a road" }
	return { "ok": true, "reason": "" }


# Legacy UI preview call sites use `can_place_road(grid_pos) -> bool` (single-arg, bool return).
# Keep this compat wrapper until sub-commit C rewires those sites to _can_place_road_geometry.
# TODO(sub-commit-C): delete after world_map.gd road-preview call sites are rewired.
func can_place_road(grid_pos: Vector2i) -> bool:
	return _can_place_road_geometry(grid_pos)


func can_remove_road(corp_id: String, grid_pos: Vector2i) -> Dictionary:
	"""Predicate for ACTION_REMOVE_ROAD."""
	if not is_valid_grid_position(grid_pos):
		return { "ok": false, "reason": "Out of bounds" }
	if road_grid[grid_pos.x][grid_pos.y] == null:
		return { "ok": false, "reason": "No road at position" }
	return { "ok": true, "reason": "" }


func place_road(grid_pos: Vector2i, road_type: String = "dirt_road") -> bool:
	"""Place a road tile. Returns true on success."""
	if not _can_place_road_geometry(grid_pos):
		return false

	# If there's a field here, remove it first (with partial refund)
	var existing_facility_id = grid[grid_pos.x][grid_pos.y]
	if existing_facility_id != null:
		_remove_field_for_road(existing_facility_id, grid_pos)

	road_grid[grid_pos.x][grid_pos.y] = road_type
	print("Road placed: %s at %s" % [road_type, grid_pos])
	EventBus.road_placed.emit(grid_pos, road_type)
	return true


func _remove_field_for_road(facility_id: String, grid_pos: Vector2i) -> void:
	"""Remove a field that's being replaced by a road"""
	var facility = facilities.get(facility_id, {})
	if facility.is_empty():
		return

	# Only remove if this is the only tile of the facility at this position
	# For multi-tile facilities, we need to check if the whole facility should be removed
	var size = facility.get("size", Vector2i(1, 1))

	# Check if this grid_pos is part of the facility
	var is_part_of_facility = false
	for x in range(size.x):
		for y in range(size.y):
			if Vector2i(facility.grid_pos.x + x, facility.grid_pos.y + y) == grid_pos:
				is_part_of_facility = true
				break

	if is_part_of_facility:
		# Give partial refund (50%) — internal compositional call, stays direct per action-pipe §0.4
		var facility_def: Dictionary = DataManager.get_facility_data(facility.type)
		var refund_cost: int = int(facility_def.get("cost", 0) * 0.5)
		var refund_name: String = facility_def.get("name", facility.type)
		EconomyManager.earn_money(GameManager.CORP_SINGLE, refund_cost, "Removed %s" % refund_name)

		# Unregister from farmhouse if applicable
		if field_parents.has(facility_id):
			_unregister_field_from_farmhouse(facility_id)

		# Remove the entire facility
		remove_facility(facility_id)
		print("Field removed for road placement: %s" % facility_id)


func remove_road(grid_pos: Vector2i) -> bool:
	"""Remove a road tile"""
	if not is_valid_grid_position(grid_pos):
		return false
	if road_grid[grid_pos.x][grid_pos.y] == null:
		return false

	var road_type = road_grid[grid_pos.x][grid_pos.y]
	road_grid[grid_pos.x][grid_pos.y] = null
	print("Road removed at %s" % grid_pos)
	EventBus.road_removed.emit(grid_pos)
	return true


func has_road_at(grid_pos: Vector2i) -> bool:
	"""Check if there's a road at the position"""
	if not is_valid_grid_position(grid_pos):
		return false
	return road_grid[grid_pos.x][grid_pos.y] != null


func get_road_type_at(grid_pos: Vector2i) -> String:
	"""Get the road type at position"""
	if not is_valid_grid_position(grid_pos):
		return ""
	var road_type = road_grid[grid_pos.x][grid_pos.y]
	return road_type if road_type else ""


func get_adjacent_positions(pos: Vector2i) -> Array[Vector2i]:
	"""Get 4-directional adjacent positions"""
	var result: Array[Vector2i] = []
	var offsets = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for offset in offsets:
		var adj = pos + offset
		if is_valid_grid_position(adj):
			result.append(adj)
	return result


# ========================================
# FARMHOUSE-FIELD RELATIONSHIPS
# ========================================

func register_field_with_farmhouse(field_id: String, farmhouse_id: String) -> void:
	"""Register a field as belonging to a farmhouse"""
	field_parents[field_id] = farmhouse_id

	if not farmhouse_children.has(farmhouse_id):
		farmhouse_children[farmhouse_id] = []
	farmhouse_children[farmhouse_id].append(field_id)

	print("Field %s registered with farmhouse %s" % [field_id, farmhouse_id])
	EventBus.field_placed_for_farmhouse.emit(field_id, farmhouse_id)


func _unregister_field_from_farmhouse(field_id: String) -> void:
	"""Remove field from farmhouse registry"""
	if field_parents.has(field_id):
		var farmhouse_id = field_parents[field_id]
		field_parents.erase(field_id)

		if farmhouse_children.has(farmhouse_id):
			farmhouse_children[farmhouse_id].erase(field_id)


func get_farmhouse_for_field(field_id: String) -> String:
	"""Get the farmhouse ID that owns a field"""
	return field_parents.get(field_id, "")


func get_fields_for_farmhouse(farmhouse_id: String) -> Array:
	"""Get all field IDs belonging to a farmhouse"""
	return farmhouse_children.get(farmhouse_id, [])


func get_farmhouse_children(farmhouse_id: String) -> Array:
	"""Alias for get_fields_for_farmhouse"""
	return get_fields_for_farmhouse(farmhouse_id)


func get_farmhouse_working_rect(farmhouse_id: String) -> Rect2i:
	"""Tile rectangle (in grid space) covered by a farmhouse's working area.
	Computed from facility data's `working_radius` field: the catchment
	extends `radius` tiles beyond the footprint in every direction. For a
	3x3 farmhouse with radius 5, the rect is (3 + 5 + 5) = 13x13.
	A farm_field tile produces only if it sits inside SOME farmhouse's rect
	(per the artist's 2026-06-05 design call). See
	`find_servicing_farmhouse_with_tile_count` for the per-tile rule."""
	var farmhouse: Dictionary = facilities.get(farmhouse_id, {})
	if farmhouse.is_empty():
		return Rect2i()
	var def: Dictionary = DataManager.get_facility_data(farmhouse.type)
	var radius: int = int(def.get("working_radius", 5))
	var fh_size: Vector2i = farmhouse.size
	var fh_pos: Vector2i = farmhouse.grid_pos
	return Rect2i(
		fh_pos.x - radius,
		fh_pos.y - radius,
		fh_size.x + radius * 2,
		fh_size.y + radius * 2,
	)


func get_all_farmhouse_ids() -> Array[String]:
	"""Return every facility id that is a farmhouse, for overlay drawing
	and field-servicing lookups."""
	var result: Array[String] = []
	for fid in facilities:
		var f: Dictionary = facilities[fid]
		if f.get("type", "") == "farmhouse":
			result.append(fid)
	return result


func _is_field_edge_adjacent_to_facility(field_id: String, facility_id: String) -> bool:
	"""True if any tile of the field is 4-direction-adjacent to any tile of the facility.
	Field is typically 1x1 today (farm_field); generalized just in case."""
	var field: Dictionary = facilities.get(field_id, {})
	var facility: Dictionary = facilities.get(facility_id, {})
	if field.is_empty() or facility.is_empty():
		return false
	# Build set of facility tile coords for quick lookup.
	var facility_tiles: Dictionary = {}
	for x in range(facility.size.x):
		for y in range(facility.size.y):
			facility_tiles[Vector2i(facility.grid_pos.x + x, facility.grid_pos.y + y)] = true
	# For each field tile, check 4-neighbors.
	for fx in range(field.size.x):
		for fy in range(field.size.y):
			var pos := Vector2i(field.grid_pos.x + fx, field.grid_pos.y + fy)
			for neighbor in get_adjacent_positions(pos):
				if facility_tiles.has(neighbor):
					return true
	return false


func find_servicing_farmhouse(field_id: String) -> String:
	"""Return the farmhouse id that services this field, or "" if none does.
	Convenience wrapper around find_servicing_farmhouse_with_tile_count;
	preserved for any callers that don't care about the productive tile count."""
	return find_servicing_farmhouse_with_tile_count(field_id).get("farmhouse_id", "")


func find_servicing_farmhouse_with_tile_count(field_id: String) -> Dictionary:
	"""Return { farmhouse_id: String, tile_count: int } for the farmhouse that
	services this field.
	Rule (per artist 2026-06-05): a tile of the field is productive iff it sits
	inside SOME farmhouse's working rect. The farmhouse with the most field
	tiles inside its rect wins; ties broken by closest farmhouse center.
	`tile_count` is the count of THIS field's tiles inside the chosen farmhouse's
	rect — this is the productive-tile multiplier ProductionManager uses.
	If no farmhouse covers any tile, returns { "", 0 }."""
	var field: Dictionary = facilities.get(field_id, {})
	if field.is_empty():
		return {"farmhouse_id": "", "tile_count": 0}
	var field_center := Vector2(
		field.grid_pos.x + field.size.x / 2.0,
		field.grid_pos.y + field.size.y / 2.0,
	)
	var best_id: String = ""
	var best_count: int = 0
	var best_dist: float = INF
	for fh_id in get_all_farmhouse_ids():
		var rect: Rect2i = get_farmhouse_working_rect(fh_id)
		# Count how many of this field's tiles fall inside this farmhouse's rect.
		var count: int = 0
		for fx in range(field.size.x):
			for fy in range(field.size.y):
				if rect.has_point(Vector2i(field.grid_pos.x + fx, field.grid_pos.y + fy)):
					count += 1
		if count == 0:
			continue
		var fh: Dictionary = facilities[fh_id]
		var fh_center := Vector2(
			fh.grid_pos.x + fh.size.x / 2.0,
			fh.grid_pos.y + fh.size.y / 2.0,
		)
		var dist: float = field_center.distance_to(fh_center)
		# Prefer farmhouse with more productive tiles; tie-break by closer center.
		if count > best_count or (count == best_count and dist < best_dist):
			best_count = count
			best_dist = dist
			best_id = fh_id
	return {"farmhouse_id": best_id, "tile_count": best_count}


func find_largest_clear_rect_in(outer: Rect2i) -> Rect2i:
	"""Largest axis-aligned sub-rectangle of `outer` whose every tile is
	placeable (in-bounds, no facility, no road). Used to shrink a drag
	rectangle that overlaps obstacles down to the biggest clear region
	per the artist's "option B" overlap rule (2026-06-05).

	Implementation: classic largest-rectangle-in-histogram. For each row
	we build a histogram of consecutive clear cells in each column ending
	at this row, then run the O(w) stack-based max-area-in-histogram per
	row. Worst-case complexity O(w * h); for a 50x50 grid the upper bound
	is ~2500 ops per call — trivial.

	Returns an empty Rect2i (size 0) if no tile in `outer` is placeable."""
	var w: int = outer.size.x
	var h: int = outer.size.y
	if w <= 0 or h <= 0:
		return Rect2i()
	var heights: Array[int] = []
	for x in range(w):
		heights.append(0)
	var best_area: int = 0
	var best_rect := Rect2i()
	for y in range(h):
		# Update column heights for this row.
		for x in range(w):
			var gp := Vector2i(outer.position.x + x, outer.position.y + y)
			if can_place_farm_field(gp):
				heights[x] += 1
			else:
				heights[x] = 0
		# Largest rectangle in this row's histogram (stack-based).
		var stack: Array[int] = []
		for x in range(w + 1):
			var cur_h: int = 0 if x == w else heights[x]
			while not stack.is_empty() and heights[stack[stack.size() - 1]] > cur_h:
				var top_idx: int = stack[stack.size() - 1]
				stack.pop_back()
				var top_h: int = heights[top_idx]
				var left: int = -1 if stack.is_empty() else stack[stack.size() - 1]
				var width: int = x - left - 1
				var area: int = top_h * width
				if area > best_area:
					best_area = area
					best_rect = Rect2i(
						outer.position.x + left + 1,
						outer.position.y + y - top_h + 1,
						width,
						top_h,
					)
			stack.append(x)
	return best_rect


func can_place_farm_field(grid_pos: Vector2i) -> bool:
	"""Placement check for the generic `farm_field` entity. Fields may be placed
	ANYWHERE on the map — no farmhouse required at placement time. Production
	gating (see `find_servicing_farmhouse`) decides whether a placed field
	actually produces. Returns false if the tile is off-grid, on a road, or
	already occupied by another facility."""
	if not is_valid_grid_position(grid_pos):
		return false
	if has_road_at(grid_pos):
		return false
	if not get_facility_at_position(grid_pos).is_empty():
		return false
	return true


func can_place_field_for_farmhouse(grid_pos: Vector2i, field_size: Vector2i, farmhouse_id: String) -> bool:
	"""Check if a field can be placed adjacent to a farmhouse or its fields"""
	var farmhouse = facilities.get(farmhouse_id, {})
	if farmhouse.is_empty():
		return false

	# Check basic placement validity
	if not _can_place_facility_geometry(grid_pos, field_size):
		return false

	# Check no roads in the way
	for x in range(field_size.x):
		for y in range(field_size.y):
			if has_road_at(Vector2i(grid_pos.x + x, grid_pos.y + y)):
				return false

	# Check within max distance from farmhouse
	var farmhouse_pos = farmhouse.grid_pos
	var farmhouse_def = DataManager.get_facility_data(farmhouse.type)
	var max_distance = farmhouse_def.get("max_field_distance", 10)

	var field_center = Vector2(grid_pos.x + field_size.x / 2.0, grid_pos.y + field_size.y / 2.0)
	var farmhouse_size = farmhouse.size
	var farmhouse_center = Vector2(
		farmhouse_pos.x + farmhouse_size.x / 2.0,
		farmhouse_pos.y + farmhouse_size.y / 2.0
	)

	if field_center.distance_to(farmhouse_center) > max_distance:
		return false

	# Check adjacency (must touch farmhouse or another field of this farmhouse)
	return _is_adjacent_to_farmhouse_network(grid_pos, field_size, farmhouse_id)


func _is_adjacent_to_farmhouse_network(grid_pos: Vector2i, field_size: Vector2i, farmhouse_id: String) -> bool:
	"""Check if the field position is adjacent to farmhouse or its connected fields"""
	var farmhouse = facilities.get(farmhouse_id, {})
	if farmhouse.is_empty():
		return false

	var children = farmhouse_children.get(farmhouse_id, [])

	# Collect all grid positions of farmhouse and its children
	var network_positions: Array[Vector2i] = []

	# Add farmhouse positions
	var fh_size = farmhouse.size
	for x in range(fh_size.x):
		for y in range(fh_size.y):
			network_positions.append(Vector2i(farmhouse.grid_pos.x + x, farmhouse.grid_pos.y + y))

	# Add existing field positions
	for child_id in children:
		var child = facilities.get(child_id, {})
		if child.is_empty():
			continue
		var child_size = child.size
		for x in range(child_size.x):
			for y in range(child_size.y):
				network_positions.append(Vector2i(child.grid_pos.x + x, child.grid_pos.y + y))

	# Check if new field position is adjacent to any network position
	for x in range(field_size.x):
		for y in range(field_size.y):
			var pos = Vector2i(grid_pos.x + x, grid_pos.y + y)
			for neighbor in get_adjacent_positions(pos):
				if neighbor in network_positions:
					return true

	return false


# ========================================
# A* PATHFINDING FOR ROADS
# ========================================

func find_road_path(start_facility_id: String, end_facility_id: String) -> Array[Vector2i]:
	"""Find path along roads between two facilities using A*"""
	var start_facility = facilities.get(start_facility_id, {})
	var end_facility = facilities.get(end_facility_id, {})

	if start_facility.is_empty() or end_facility.is_empty():
		return []

	# Find road tiles adjacent to facilities
	var start_roads = _get_adjacent_road_tiles(start_facility)
	var end_roads = _get_adjacent_road_tiles(end_facility)

	if start_roads.is_empty() or end_roads.is_empty():
		return []  # No road connection possible

	# Try to find path from any start road to any end road
	var best_path: Array[Vector2i] = []
	var best_length = INF

	for start_road in start_roads:
		for end_road in end_roads:
			var path = _astar_pathfind(start_road, end_road)
			if not path.is_empty() and path.size() < best_length:
				best_path = path
				best_length = path.size()

	return best_path


func _get_adjacent_road_tiles(facility: Dictionary) -> Array[Vector2i]:
	"""Get road tiles adjacent to a facility (must be directly next to facility)"""
	var result: Array[Vector2i] = []
	var grid_pos = facility.grid_pos
	var size = facility.size

	# Check all tiles directly adjacent to facility edges
	for x in range(-1, size.x + 1):
		for y in range(-1, size.y + 1):
			# Skip tiles inside the facility
			if x >= 0 and x < size.x and y >= 0 and y < size.y:
				continue

			var check_pos = Vector2i(grid_pos.x + x, grid_pos.y + y)
			if has_road_at(check_pos):
				result.append(check_pos)

	return result


func _astar_pathfind(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	"""A* pathfinding on road grid"""
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}

	while not open_set.is_empty():
		# Find node with lowest f_score
		var current = open_set[0]
		var lowest_f = f_score.get(current, INF)
		for node in open_set:
			var f = f_score.get(node, INF)
			if f < lowest_f:
				lowest_f = f
				current = node

		if current == goal:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		for neighbor in _get_road_neighbors(current):
			var tentative_g = g_score.get(current, INF) + 1

			if tentative_g < g_score.get(neighbor, INF):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)

				if neighbor not in open_set:
					open_set.append(neighbor)

	return []  # No path found


func _get_road_neighbors(pos: Vector2i) -> Array[Vector2i]:
	"""Get adjacent road tiles"""
	var result: Array[Vector2i] = []
	for neighbor in get_adjacent_positions(pos):
		if has_road_at(neighbor):
			result.append(neighbor)
	return result


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	"""Manhattan distance heuristic"""
	return abs(a.x - b.x) + abs(a.y - b.y)


func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	"""Reconstruct path from A* result"""
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


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
