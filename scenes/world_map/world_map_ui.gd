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

	# Create build menu buttons
	_create_build_menu()


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

func _create_build_menu() -> void:
	"""Create buttons for buildable facilities"""
	if not build_menu:
		return

	# Add "Create Route" button first
	var route_button = Button.new()
	route_button.text = "📦 Create Route"
	route_button.custom_minimum_size = Vector2(150, 60)
	route_button.pressed.connect(_on_create_route_button_clicked)
	build_menu.add_child(route_button)

	# Add "Demolish" button
	var demolish_button = Button.new()
	demolish_button.text = "🔨 Demolish"
	demolish_button.custom_minimum_size = Vector2(150, 60)
	demolish_button.pressed.connect(_on_demolish_button_clicked)
	build_menu.add_child(demolish_button)

	# Add separator
	var separator = VSeparator.new()
	build_menu.add_child(separator)

	# Get all facility definitions
	var facilities = DataManager.get_all_facilities()

	for facility_id in facilities:
		var facility_def = facilities[facility_id]
		_create_build_button(facility_id, facility_def)


func _create_build_button(facility_id: String, facility_def: Dictionary) -> void:
	"""Create a build button for a facility"""
	var button = Button.new()
	var name = facility_def.get("name", facility_id)
	var cost = facility_def.get("cost", 0)

	# Multi-line button text
	button.text = "%s\n$%d" % [name, cost]
	button.custom_minimum_size = Vector2(120, 60)
	button.pressed.connect(_on_build_button_clicked.bind(facility_id))

	build_menu.add_child(button)


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
