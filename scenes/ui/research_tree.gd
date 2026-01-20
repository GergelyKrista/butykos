extends Control
## Visual Research Tree - Civ6-style horizontal tech tree with connecting lines
## Nodes are only visible if prerequisites are met (or no prerequisites)

signal research_requested(tech_id: String)

# Layout constants - spacious horizontal layout
const NODE_WIDTH: float = 180.0
const NODE_HEIGHT: float = 90.0  # Increased for unlock info
const TIER_SPACING: float = 240.0  # Horizontal space between tiers
const BRANCH_SPACING: float = 85.0  # Vertical space between branches
const MARGIN_LEFT: float = 60.0
const MARGIN_TOP: float = 60.0

# Node references
var tree_container: Control
var lines_container: Control
var nodes_container: Control

# Tech node references for drawing lines
var tech_nodes: Dictionary = {}  # tech_id -> Control node

# Branch order for vertical positioning
var BRANCH_ORDER: Array[String] = [
	"agriculture",
	"grain_processing",
	"brewing",
	"distillation",
	"aging",
	"packaging",
	"logistics",
	"commerce"
]

# Reference to ResearchManager
var _research_manager: Node

# Dev mode toggle
var dev_mode_enabled: bool = false
var dev_toggle_button: CheckButton

func _ready() -> void:
	_research_manager = get_node("/root/ResearchManager")
	_setup_containers()
	_build_tree()

	_research_manager.research_completed.connect(_on_research_completed)
	_research_manager.tier_unlocked.connect(_on_tier_unlocked)


func _setup_containers() -> void:
	# Main scroll container - horizontal scroll priority
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	# Tree container with large horizontal size for sideways scrolling
	tree_container = Control.new()
	tree_container.name = "TreeContainer"
	tree_container.custom_minimum_size = Vector2(
		MARGIN_LEFT + (5 * TIER_SPACING) + NODE_WIDTH + 100,
		MARGIN_TOP + (8 * BRANCH_SPACING) + NODE_HEIGHT + 50
	)
	scroll.add_child(tree_container)

	# Solid background - no transparency
	var bg = ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree_container.add_child(bg)

	# Lines container (drawn behind nodes)
	lines_container = Control.new()
	lines_container.name = "LinesContainer"
	lines_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines_container.draw.connect(_draw_connections)
	tree_container.add_child(lines_container)

	# Nodes container
	nodes_container = Control.new()
	nodes_container.name = "NodesContainer"
	tree_container.add_child(nodes_container)

	# Tier column headers
	_create_tier_headers()

	# Dev mode toggle button in top-right (added last to be on top)
	var dev_container = HBoxContainer.new()
	dev_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dev_container.offset_left = -220
	dev_container.offset_top = 5
	dev_container.offset_right = -10
	dev_container.offset_bottom = 35
	add_child(dev_container)

	var dev_label = Label.new()
	dev_label.text = "Dev Mode (Free Research):"
	dev_label.add_theme_font_size_override("font_size", 11)
	dev_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	dev_container.add_child(dev_label)

	dev_toggle_button = CheckButton.new()
	dev_toggle_button.text = ""
	dev_toggle_button.toggled.connect(_on_dev_mode_toggled)
	dev_container.add_child(dev_toggle_button)


func _create_tier_headers() -> void:
	var current_tier = _research_manager.get_current_tier()

	for tier in range(1, 6):
		var header = Label.new()
		header.text = "TIER %d" % tier
		header.add_theme_font_size_override("font_size", 20)
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		if tier <= current_tier:
			header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		else:
			header.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

		header.position = Vector2(
			MARGIN_LEFT + (tier - 1) * TIER_SPACING + NODE_WIDTH / 2 - 40,
			20
		)
		tree_container.add_child(header)


func _build_tree() -> void:
	tech_nodes.clear()

	# Clear existing nodes
	for child in nodes_container.get_children():
		child.queue_free()

	# Create nodes only for visible techs
	for tech_id in _research_manager.research_tree:
		var tech = _research_manager.research_tree[tech_id]

		# Check if this tech should be visible
		if _should_show_tech(tech_id, tech):
			var node = _create_tech_node(tech)
			nodes_container.add_child(node)
			tech_nodes[tech_id] = node

	# Trigger line redraw
	lines_container.queue_redraw()


func _should_show_tech(_tech_id: String, _tech: Dictionary) -> bool:
	"""Determine if a tech should be visible in the tree"""
	# Always show ALL techs - grayed out if locked
	return true


func _create_tech_node(tech: Dictionary) -> PanelContainer:
	var tech_id = tech.get("id", "")
	var tier = tech.get("tier", 1)
	var branch = tech.get("branch", "")
	var branch_index = BRANCH_ORDER.find(branch)
	if branch_index == -1:
		branch_index = 0

	# Calculate position
	var pos_x = MARGIN_LEFT + (tier - 1) * TIER_SPACING
	var pos_y = MARGIN_TOP + branch_index * BRANCH_SPACING

	# Create main panel - this can later hold a TextureRect for sprites
	var panel = PanelContainer.new()
	panel.name = tech_id
	panel.position = Vector2(pos_x, pos_y)
	panel.custom_minimum_size = Vector2(NODE_WIDTH, NODE_HEIGHT)

	# Style based on state
	var stylebox = StyleBoxFlat.new()
	stylebox.corner_radius_top_left = 6
	stylebox.corner_radius_top_right = 6
	stylebox.corner_radius_bottom_left = 6
	stylebox.corner_radius_bottom_right = 6
	stylebox.border_width_left = 3
	stylebox.border_width_right = 3
	stylebox.border_width_top = 3
	stylebox.border_width_bottom = 3
	stylebox.content_margin_left = 10
	stylebox.content_margin_right = 10
	stylebox.content_margin_top = 8
	stylebox.content_margin_bottom = 8

	var is_unlocked = _research_manager.is_unlocked(tech_id)
	var can_research = _research_manager.can_research(tech_id)
	var is_tier_locked = _research_manager.is_tier_locked(tech_id)
	var prerequisites = tech.get("prerequisites", [])

	# Check if all prerequisites are researched
	var prereqs_done = true
	for prereq in prerequisites:
		if not _research_manager.is_unlocked(prereq):
			prereqs_done = false
			break

	# No prerequisites means prereqs are "done"
	if prerequisites.size() == 0:
		prereqs_done = true

	if is_unlocked:
		# Researched - green
		stylebox.bg_color = Color(0.1, 0.35, 0.15, 0.95)
		stylebox.border_color = Color(0.3, 0.8, 0.3)
	elif can_research:
		# Available - blue highlight
		stylebox.bg_color = Color(0.15, 0.2, 0.35, 0.95)
		stylebox.border_color = Color(0.4, 0.6, 1.0)
	elif prereqs_done and is_tier_locked:
		# Prerequisites done but tier locked - show name, dark red
		stylebox.bg_color = Color(0.15, 0.08, 0.08, 0.7)
		stylebox.border_color = Color(0.4, 0.25, 0.25)
	else:
		# Prerequisites NOT done - fully locked, very dark
		stylebox.bg_color = Color(0.08, 0.08, 0.1, 0.6)
		stylebox.border_color = Color(0.25, 0.25, 0.28)

	panel.add_theme_stylebox_override("panel", stylebox)

	# Content container - VBox for icon area + text
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Icon placeholder - this TextureRect can later hold a sprite
	var icon_holder = Panel.new()
	icon_holder.custom_minimum_size = Vector2(0, 0)  # Will expand with content
	# Could add: icon_holder.add_child(TextureRect) for sprites later

	# Tech name - only show if unlocked OR prerequisites are done
	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_unlocked or can_research or prereqs_done:
		# Show actual name
		name_label.text = tech.get("name", tech_id)
		if is_unlocked:
			name_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
		elif can_research:
			name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			name_label.add_theme_color_override("font_color", Color(0.5, 0.4, 0.4))
	else:
		# Hide name - show locked placeholder
		name_label.text = "???"
		name_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))

	vbox.add_child(name_label)

	# Status/Cost label
	var status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if is_unlocked:
		status_label.text = "RESEARCHED"
		status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	elif can_research:
		var cost = tech.get("cost", 0)
		status_label.text = "$%d - Click to Research" % cost
		status_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	elif prereqs_done and is_tier_locked:
		# Prerequisites done but tier locked - show tier requirement
		status_label.text = "Requires Tier %d" % tier
		status_label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
	else:
		# Prerequisites NOT done - research locked
		status_label.text = "Research Locked"
		status_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))

	vbox.add_child(status_label)

	# Unlock summary line
	var unlock_summary = _get_unlock_summary(tech)
	if unlock_summary != "" and (is_unlocked or can_research or prereqs_done):
		var unlock_label = Label.new()
		unlock_label.add_theme_font_size_override("font_size", 10)
		unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlock_label.text = unlock_summary
		if is_unlocked:
			unlock_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
		else:
			unlock_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
		vbox.add_child(unlock_label)

	# Make clickable if can research (including dev mode)
	var can_click = can_research or (dev_mode_enabled and prereqs_done and not is_unlocked)
	if can_click:
		panel.gui_input.connect(_on_node_clicked.bind(tech_id))
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	return panel


func _draw_connections() -> void:
	# Draw lines between visible connected techs
	for tech_id in tech_nodes:
		var tech = _research_manager.research_tree[tech_id]
		var prerequisites = tech.get("prerequisites", [])

		var target_node = tech_nodes[tech_id]
		var target_pos = target_node.position + Vector2(0, NODE_HEIGHT / 2)

		for prereq_id in prerequisites:
			# Only draw line if prereq is also visible
			if prereq_id not in tech_nodes:
				continue

			var source_node = tech_nodes[prereq_id]
			var source_pos = source_node.position + Vector2(NODE_WIDTH, NODE_HEIGHT / 2)

			# Line color based on state
			var color: Color
			var is_unlocked = _research_manager.is_unlocked(tech_id)
			var prereq_unlocked = _research_manager.is_unlocked(prereq_id)

			if is_unlocked:
				color = Color(0.3, 0.7, 0.3, 0.9)
			elif prereq_unlocked:
				color = Color(0.4, 0.6, 1.0, 0.9)
			else:
				color = Color(0.4, 0.4, 0.4, 0.6)

			_draw_connection_line(source_pos, target_pos, color)


func _draw_connection_line(from: Vector2, to: Vector2, color: Color) -> void:
	var mid_x = from.x + (to.x - from.x) * 0.5

	# Draw path: horizontal -> vertical -> horizontal
	var points: PackedVector2Array = [
		from,
		Vector2(mid_x, from.y),
		Vector2(mid_x, to.y),
		to
	]

	for i in range(points.size() - 1):
		lines_container.draw_line(points[i], points[i + 1], color, 3.0, true)

	# Arrow at end
	var arrow_size = 10.0
	var dir = (to - points[points.size() - 2]).normalized()
	var arrow_p1 = to - dir * arrow_size + dir.rotated(PI / 2) * arrow_size * 0.5
	var arrow_p2 = to - dir * arrow_size - dir.rotated(PI / 2) * arrow_size * 0.5
	lines_container.draw_polygon([to, arrow_p1, arrow_p2], [color])


func _on_node_clicked(event: InputEvent, tech_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		research_requested.emit(tech_id)


func _on_research_completed(_tech_id: String) -> void:
	_refresh_tree()


func _on_tier_unlocked(_tier: int) -> void:
	_refresh_tree()


func _refresh_tree() -> void:
	# Clear and rebuild
	for child in nodes_container.get_children():
		child.queue_free()

	# Update tier headers
	for child in tree_container.get_children():
		if child is Label and child.text.begins_with("TIER"):
			var tier = int(child.text.replace("TIER ", ""))
			var current_tier = _research_manager.get_current_tier()
			if tier <= current_tier or dev_mode_enabled:
				child.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
			else:
				child.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))

	# Rebuild nodes
	call_deferred("_build_tree")


func _on_dev_mode_toggled(button_pressed: bool) -> void:
	"""Toggle dev mode which bypasses tier requirements"""
	dev_mode_enabled = button_pressed
	_research_manager.set_dev_mode(button_pressed)
	_refresh_tree()


func _get_unlock_summary(tech: Dictionary) -> String:
	"""Get a short summary of what this tech unlocks"""
	var unlocks = tech.get("unlocks", {})
	var parts: Array[String] = []

	# New facilities
	var facilities = unlocks.get("new_facilities", [])
	if facilities.size() > 0:
		parts.append("+%d Building%s" % [facilities.size(), "s" if facilities.size() > 1 else ""])

	# New machines
	var machines = unlocks.get("new_machines", [])
	if machines.size() > 0:
		parts.append("+%d Machine%s" % [machines.size(), "s" if machines.size() > 1 else ""])

	# New products
	var products = unlocks.get("new_products", [])
	if products.size() > 0:
		parts.append("+%d Product%s" % [products.size(), "s" if products.size() > 1 else ""])

	# Bonuses
	var bonuses = unlocks.get("bonuses", [])
	if bonuses.size() > 0:
		parts.append("+%d Bonus%s" % [bonuses.size(), "es" if bonuses.size() > 1 else ""])

	# Building upgrades
	var upgrades = unlocks.get("building_upgrades", [])
	if upgrades.size() > 0:
		parts.append("+%d Upgrade%s" % [upgrades.size(), "s" if upgrades.size() > 1 else ""])

	if parts.size() == 0:
		return ""

	return ", ".join(parts)
