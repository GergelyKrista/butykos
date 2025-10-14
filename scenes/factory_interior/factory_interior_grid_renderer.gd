extends Node2D

## FactoryInteriorGridRenderer - Draws the factory interior grid
##
## Renders the 20x20 interior grid for machine placement.

# ========================================
# CONFIGURATION
# ========================================

@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)
@export var grid_line_width: float = 1.0

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	queue_redraw()


# ========================================
# RENDERING
# ========================================

func _draw() -> void:
	_draw_grid()


func _draw_grid() -> void:
	"""Draw the interior grid lines"""
	var tile_size = FactoryManager.INTERIOR_TILE_SIZE
	var grid_size = FactoryManager.INTERIOR_GRID_SIZE

	# Draw vertical lines
	for x in range(grid_size.x + 1):
		var start = Vector2(x * tile_size, 0)
		var end = Vector2(x * tile_size, grid_size.y * tile_size)
		draw_line(start, end, grid_color, grid_line_width)

	# Draw horizontal lines
	for y in range(grid_size.y + 1):
		var start = Vector2(0, y * tile_size)
		var end = Vector2(grid_size.x * tile_size, y * tile_size)
		draw_line(start, end, grid_color, grid_line_width)
