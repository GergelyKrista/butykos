extends Node2D

## RoadRenderer - Renders road tiles on the world map
##
## Creates isometric diamond visuals for road tiles.
## Listens to road events to update visuals dynamically.

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	EventBus.road_placed.connect(_on_road_placed)
	EventBus.road_removed.connect(_on_road_removed)
	EventBus.after_load.connect(_on_after_load)

	# Draw any existing roads (in case loaded from save)
	_redraw_all_roads()


# ========================================
# ROAD RENDERING
# ========================================

func _redraw_all_roads() -> void:
	"""Redraw all roads from WorldManager's road grid"""
	# Clear existing road visuals
	for child in get_children():
		child.queue_free()

	# Draw all roads
	for x in range(WorldManager.GRID_SIZE.x):
		for y in range(WorldManager.GRID_SIZE.y):
			var road_type = WorldManager.get_road_type_at(Vector2i(x, y))
			if not road_type.is_empty():
				_create_road_tile(Vector2i(x, y), road_type)


func _create_road_tile(grid_pos: Vector2i, road_type: String) -> void:
	"""Create visual for a single road tile"""
	var road_node = Node2D.new()
	road_node.name = "road_%d_%d" % [grid_pos.x, grid_pos.y]

	# Get road color from data (or use default)
	var road_def = DataManager.get_road_data(road_type)
	var color = Color("#8B7355")  # Default brown
	if not road_def.is_empty():
		var visual = road_def.get("visual", {})
		color = Color(visual.get("color", "#8B7355"))

	# Center position for this tile (using tile center)
	var center_cart = Vector2(grid_pos.x + 0.5, grid_pos.y + 0.5)
	var center_iso = WorldManager.cart_to_iso(center_cart)
	road_node.position = center_iso

	# Create isometric diamond polygon
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
	road_node.add_child(polygon)

	# Add a subtle border/outline
	var border = Line2D.new()
	border.width = 1.5
	border.default_color = color.darkened(0.3)
	border.closed = true
	border.add_point(Vector2(0, -half_height))
	border.add_point(Vector2(half_width, 0))
	border.add_point(Vector2(0, half_height))
	border.add_point(Vector2(-half_width, 0))
	road_node.add_child(border)

	# Z-index below facilities but above grid
	road_node.z_index = -1

	add_child(road_node)


func _remove_road_tile(grid_pos: Vector2i) -> void:
	"""Remove visual for a road tile"""
	var node_name = "road_%d_%d" % [grid_pos.x, grid_pos.y]
	var node = get_node_or_null(node_name)
	if node:
		node.queue_free()


# ========================================
# EVENT HANDLERS
# ========================================

func _on_road_placed(grid_pos: Vector2i, road_type: String) -> void:
	"""Handle road placement"""
	_create_road_tile(grid_pos, road_type)


func _on_road_removed(grid_pos: Vector2i) -> void:
	"""Handle road removal"""
	_remove_road_tile(grid_pos)


func _on_after_load() -> void:
	"""Redraw roads after loading a save"""
	_redraw_all_roads()
