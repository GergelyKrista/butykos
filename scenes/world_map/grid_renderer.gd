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
	"""Draw the isometric diamond grid lines"""
	var grid_size = WorldManager.GRID_SIZE

	# Draw diagonal lines from top-left to bottom-right (rows)
	for y in range(grid_size.y + 1):
		var start_cart = Vector2(0, y)
		var end_cart = Vector2(grid_size.x, y)
		var start_iso = WorldManager.cart_to_iso(start_cart)
		var end_iso = WorldManager.cart_to_iso(end_cart)
		draw_line(start_iso, end_iso, grid_color, grid_line_width)

	# Draw diagonal lines from top-right to bottom-left (columns)
	for x in range(grid_size.x + 1):
		var start_cart = Vector2(x, 0)
		var end_cart = Vector2(x, grid_size.y)
		var start_iso = WorldManager.cart_to_iso(start_cart)
		var end_iso = WorldManager.cart_to_iso(end_cart)
		draw_line(start_iso, end_iso, grid_color, grid_line_width)

	# Optionally draw coordinate labels
	if show_coordinates:
		_draw_coordinates()


func _draw_coordinates() -> void:
	"""Draw coordinate labels (for debugging) in isometric space"""
	var grid_size = WorldManager.GRID_SIZE

	for x in range(0, grid_size.x, 5):
		for y in range(0, grid_size.y, 5):
			var cart_pos = Vector2(x, y)
			var iso_pos = WorldManager.cart_to_iso(cart_pos)
			iso_pos += Vector2(5, 5)  # Offset for readability
			var text = "%d,%d" % [x, y]
			draw_string(ThemeDB.fallback_font, iso_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
