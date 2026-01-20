extends CanvasLayer

## WorldMapUI - UI overlay for the world map
##
## Displays money, date, and build menu.

# ========================================
# REFERENCES
# ========================================

@onready var money_label: Label = $HUD/MoneyLabel
@onready var date_label: Label = $HUD/DateLabel
@onready var build_menu: HBoxContainer = $BottomBar/MarginContainer/VBoxContainer/ScrollContainer/HBoxContainer
@onready var build_scroll_container: ScrollContainer = $BottomBar/MarginContainer/VBoxContainer/ScrollContainer
@onready var bottom_bar: Panel = $BottomBar

# ========================================
# SIGNALS
# ========================================

signal build_button_pressed(facility_id: String)
signal create_route_button_pressed()
signal demolish_button_pressed()

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Update displays
	_update_money_display()
	_update_date_display()

	# Connect signals
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.date_advanced.connect(_on_date_advanced)

	# Refresh build menu when research unlocks new facilities
	EventBus.research_completed.connect(_on_research_completed)

	# Create build menu buttons
	_create_build_menu()


func _on_research_completed(_tech_id: String) -> void:
	"""Handle research completion - refresh build menu"""
	refresh_build_menu()


func _input(event: InputEvent) -> void:
	"""Handle input events for navbar scrolling"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if mouse is over the bottom bar (navbar)
			if _is_mouse_over_navbar():
				# Handle horizontal scrolling
				_handle_navbar_scroll(event)
				# Consume the event to prevent map zoom
				get_viewport().set_input_as_handled()


func _is_mouse_over_navbar() -> bool:
	"""Check if mouse is over the bottom navbar"""
	if not bottom_bar:
		return false

	var mouse_pos = get_viewport().get_mouse_position()
	var bar_rect = Rect2(bottom_bar.global_position, bottom_bar.size)
	return bar_rect.has_point(mouse_pos)


func _handle_navbar_scroll(event: InputEventMouseButton) -> void:
	"""Handle horizontal scrolling in the navbar"""
	if not build_scroll_container:
		return

	# Scroll amount (pixels per wheel tick)
	var scroll_amount = 50.0

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		# Scroll left
		build_scroll_container.scroll_horizontal -= int(scroll_amount)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# Scroll right
		build_scroll_container.scroll_horizontal += int(scroll_amount)


# ========================================
# UI UPDATES
# ========================================

func _update_money_display() -> void:
	"""Update money display"""
	if money_label:
		money_label.text = "Money: $%d" % EconomyManager.money


func _update_date_display() -> void:
	"""Update date display"""
	if date_label:
		date_label.text = "Date: %s" % GameManager.get_date_string()


func _on_money_changed(_new_amount: int, _delta: int) -> void:
	"""Handle money changed event"""
	_update_money_display()


func _on_date_advanced(_new_date: Dictionary) -> void:
	"""Handle date advanced event"""
	_update_date_display()


# ========================================
# BUILD MENU
# ========================================

# Category display order and names
const CATEGORY_ORDER: Array[String] = ["tools", "agriculture", "processing", "production", "storage"]
const CATEGORY_NAMES: Dictionary = {
	"tools": "Tools",
	"agriculture": "Agriculture",
	"processing": "Processing",
	"production": "Production",
	"storage": "Storage"
}

const CATEGORY_COLORS: Dictionary = {
	"tools": Color(0.5, 0.5, 0.6),
	"agriculture": Color(0.3, 0.6, 0.3),
	"processing": Color(0.6, 0.5, 0.3),
	"production": Color(0.6, 0.4, 0.3),
	"storage": Color(0.4, 0.4, 0.5)
}

# Current menu state
var current_category: String = ""  # Empty = showing categories, otherwise showing buildings in category


func _create_build_menu() -> void:
	"""Create build menu - shows categories at top level"""
	if not build_menu:
		return

	_clear_build_menu()
	current_category = ""
	_show_categories()


func _clear_build_menu() -> void:
	"""Clear all children from build menu"""
	for child in build_menu.get_children():
		child.queue_free()


func _show_categories() -> void:
	"""Show category buttons at top level"""
	_clear_build_menu()
	current_category = ""

	# Get facility counts per category for display
	var facilities = DataManager.get_all_facilities()
	var category_counts: Dictionary = {}

	for facility_id in facilities:
		if not ResearchManager.is_facility_unlocked(facility_id):
			continue
		var facility_def = facilities[facility_id]
		var category = facility_def.get("category", "other")
		category_counts[category] = category_counts.get(category, 0) + 1

	# Create category buttons
	for category in CATEGORY_ORDER:
		var cat_name = CATEGORY_NAMES.get(category, category.capitalize())
		var count = category_counts.get(category, 0)

		# Tools category is special - always show
		if category == "tools":
			_add_category_button(category, cat_name, -1)  # -1 means don't show count
		elif count > 0:
			_add_category_button(category, cat_name, count)


func _add_category_button(category: String, display_name: String, count: int) -> void:
	"""Add a category button to the build menu"""
	var button = Button.new()

	if count >= 0:
		button.text = "%s\n(%d)" % [display_name, count]
	else:
		button.text = display_name

	button.custom_minimum_size = Vector2(120, 60)
	button.pressed.connect(_on_category_clicked.bind(category))

	# Style with category color
	var color = CATEGORY_COLORS.get(category, Color(0.5, 0.5, 0.5))
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = color.darkened(0.3)
	stylebox.border_width_bottom = 4
	stylebox.border_color = color
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", stylebox)

	var hover_style = stylebox.duplicate()
	hover_style.bg_color = color.darkened(0.1)
	button.add_theme_stylebox_override("hover", hover_style)

	build_menu.add_child(button)


func _on_category_clicked(category: String) -> void:
	"""Handle category button click - show buildings in category"""
	current_category = category
	_show_category_contents(category)


func _show_category_contents(category: String) -> void:
	"""Show all buildings in a category with back button"""
	_clear_build_menu()

	# Back button
	var back_button = Button.new()
	back_button.text = "< Back"
	back_button.custom_minimum_size = Vector2(80, 60)
	back_button.pressed.connect(_on_back_clicked)

	var back_style = StyleBoxFlat.new()
	back_style.bg_color = Color(0.3, 0.3, 0.35)
	back_style.corner_radius_top_left = 4
	back_style.corner_radius_top_right = 4
	back_style.corner_radius_bottom_left = 4
	back_style.corner_radius_bottom_right = 4
	back_button.add_theme_stylebox_override("normal", back_style)
	build_menu.add_child(back_button)

	# Category label
	var cat_name = CATEGORY_NAMES.get(category, category.capitalize())
	var label = Label.new()
	label.text = cat_name
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", CATEGORY_COLORS.get(category, Color(0.8, 0.8, 0.8)))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(100, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_menu.add_child(label)

	# Separator
	var separator = VSeparator.new()
	separator.custom_minimum_size = Vector2(2, 50)
	build_menu.add_child(separator)

	# Show content based on category
	if category == "tools":
		_add_tool_buttons()
	else:
		_add_category_buildings(category)


func _on_back_clicked() -> void:
	"""Return to category view"""
	_show_categories()


func _add_tool_buttons() -> void:
	"""Add tool buttons (Create Route, Demolish)"""
	var route_button = Button.new()
	route_button.text = "Create\nRoute"
	route_button.custom_minimum_size = Vector2(100, 60)
	route_button.pressed.connect(_on_create_route_button_clicked)
	build_menu.add_child(route_button)

	var demolish_button = Button.new()
	demolish_button.text = "Demolish"
	demolish_button.custom_minimum_size = Vector2(100, 60)
	demolish_button.pressed.connect(_on_demolish_button_clicked)
	build_menu.add_child(demolish_button)


func _add_category_buildings(category: String) -> void:
	"""Add all unlocked buildings in a category"""
	var facilities = DataManager.get_all_facilities()

	for facility_id in facilities:
		var facility_def = facilities[facility_id]
		if facility_def.get("category", "other") != category:
			continue

		# Only show unlocked facilities
		if not ResearchManager.is_facility_unlocked(facility_id):
			continue

		_create_build_button(facility_id, facility_def)


func _create_build_button(facility_id: String, facility_def: Dictionary) -> void:
	"""Create a build button for a facility"""
	var button = Button.new()
	var fname = facility_def.get("name", facility_id)
	var cost = facility_def.get("cost", 0)

	button.text = "%s\n$%d" % [fname, cost]
	button.custom_minimum_size = Vector2(100, 60)
	button.pressed.connect(_on_build_button_clicked.bind(facility_id))

	build_menu.add_child(button)


func refresh_build_menu() -> void:
	"""Refresh build menu (call after research completion)"""
	if current_category == "":
		_show_categories()
	else:
		_show_category_contents(current_category)


func _on_build_button_clicked(facility_id: String) -> void:
	"""Handle build button click"""
	print("Build button clicked: %s" % facility_id)
	build_button_pressed.emit(facility_id)


func _on_create_route_button_clicked() -> void:
	"""Handle create route button click"""
	print("Create route button clicked")
	create_route_button_pressed.emit()


func _on_demolish_button_clicked() -> void:
	"""Handle demolish button click"""
	print("Demolish button clicked")
	demolish_button_pressed.emit()
