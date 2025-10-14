extends Node2D

## GridRenderer - Draws the world map grid
##
## Renders the 50x50 grid with customizable colors and line thickness.

# ========================================
# CONFIGURATION
# ========================================

@export var grid_color: Color = Color(0.4, 0.4, 0.4, 0.8)
@export var grid_line_width: float = 2.0
@export var show_coordinates: bool = false

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
	"""Draw the grid lines"""
	var tile_size = WorldManager.TILE_SIZE
	var grid_size = WorldManager.GRID_SIZE

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

	# Optionally draw coordinate labels
	if show_coordinates:
		_draw_coordinates()


func _draw_coordinates() -> void:
	"""Draw coordinate labels (for debugging)"""
	var tile_size = WorldManager.TILE_SIZE
	var grid_size = WorldManager.GRID_SIZE

	for x in range(0, grid_size.x, 5):
		for y in range(0, grid_size.y, 5):
			var pos = Vector2(x * tile_size + 5, y * tile_size + 15)
			var text = "%d,%d" % [x, y]
			draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
