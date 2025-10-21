extends CanvasLayer

## FactoryInteriorUI - UI overlay for factory interior view
##
## Displays factory name, back button, and machine build menu.

# ========================================
# SIGNALS
# ========================================

signal back_button_pressed()
signal machine_button_pressed(machine_id: String)
signal connect_button_pressed()
signal delete_connection_button_pressed()
signal demolish_button_pressed()

# ========================================
# REFERENCES
# ========================================

@onready var back_button: Button = $BottomBar/MarginContainer/VBoxContainer/ActionsView/ButtonsContainer/BackButton
@onready var connect_button: Button = $BottomBar/MarginContainer/VBoxContainer/ActionsView/ButtonsContainer/ConnectButton
@onready var delete_connection_button: Button = $BottomBar/MarginContainer/VBoxContainer/ActionsView/ButtonsContainer/DeleteConnectionButton
@onready var demolish_button: Button = $BottomBar/MarginContainer/VBoxContainer/ActionsView/ButtonsContainer/DemolishButton
@onready var build_machines_button: Button = $BottomBar/MarginContainer/VBoxContainer/ActionsView/ButtonsContainer/BuildMachinesButton
@onready var factory_label: Label = $HUD/FactoryLabel
@onready var actions_view: VBoxContainer = $BottomBar/MarginContainer/VBoxContainer/ActionsView
@onready var machines_view: VBoxContainer = $BottomBar/MarginContainer/VBoxContainer/MachinesView
@onready var machine_menu: HBoxContainer = $BottomBar/MarginContainer/VBoxContainer/MachinesView/ScrollContainer/HBoxContainer
@onready var machine_menu_close_button: Button = $BottomBar/MarginContainer/VBoxContainer/MachinesView/HeaderHBox/CloseButton
@onready var machine_scroll_container: ScrollContainer = $BottomBar/MarginContainer/VBoxContainer/MachinesView/ScrollContainer
@onready var bottom_bar: Panel = $BottomBar

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Connect back button
	if back_button:
		back_button.pressed.connect(_on_back_button_clicked)

	# Connect connect button
	if connect_button:
		connect_button.pressed.connect(_on_connect_button_clicked)

	# Connect delete connection button
	if delete_connection_button:
		delete_connection_button.pressed.connect(_on_delete_connection_button_clicked)

	# Connect demolish button
	if demolish_button:
		demolish_button.pressed.connect(_on_demolish_button_clicked)

	# Connect build machines button
	if build_machines_button:
		build_machines_button.pressed.connect(_on_build_machines_button_clicked)

	# Connect machine menu close button
	if machine_menu_close_button:
		machine_menu_close_button.pressed.connect(_on_machine_menu_close_clicked)

	# Update factory label
	_update_factory_label()

	# Create machine build menu (but keep it hidden initially)
	_create_machine_menu()


func _input(event: InputEvent) -> void:
	"""Handle input events for navbar scrolling"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Check if mouse is over the machine scroll area (not the header)
			if _is_mouse_over_machine_scroll():
				# Handle horizontal scrolling
				_handle_navbar_scroll(event)
				# Consume the event to prevent camera zoom
				get_viewport().set_input_as_handled()


func _is_mouse_over_machine_scroll() -> bool:
	"""Check if mouse is over the machine scroll container (excluding header)"""
	if not machine_scroll_container or not machine_scroll_container.visible:
		return false

	var mouse_pos = get_viewport().get_mouse_position()
	var scroll_rect = Rect2(machine_scroll_container.global_position, machine_scroll_container.size)
	return scroll_rect.has_point(mouse_pos)


func _handle_navbar_scroll(event: InputEventMouseButton) -> void:
	"""Handle horizontal scrolling in the machine menu"""
	if not machine_scroll_container:
		return

	# Scroll amount (pixels per wheel tick)
	var scroll_amount = 50.0

	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		# Scroll left
		machine_scroll_container.scroll_horizontal -= int(scroll_amount)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# Scroll right
		machine_scroll_container.scroll_horizontal += int(scroll_amount)


# ========================================
# UI UPDATES
# ========================================

func _update_factory_label() -> void:
	"""Update factory name display"""
	if not factory_label:
		return

	var facility_id = GameManager.active_factory_id
	var facility = WorldManager.get_facility(facility_id)

	if facility.is_empty():
		factory_label.text = "Factory Interior"
		return

	var facility_def = DataManager.get_facility_data(facility.type)
	factory_label.text = facility_def.get("name", "Factory") + " Interior"


# ========================================
# EVENT HANDLERS
# ========================================

func _on_back_button_clicked() -> void:
	"""Handle back button click"""
	print("Back button clicked")
	back_button_pressed.emit()


func _on_connect_button_clicked() -> void:
	"""Handle connect button click"""
	print("Connect button clicked")
	connect_button_pressed.emit()


func _on_delete_connection_button_clicked() -> void:
	"""Handle delete connection button click"""
	print("Delete connection button clicked")
	delete_connection_button_pressed.emit()


func _on_demolish_button_clicked() -> void:
	"""Handle demolish button click"""
	print("Demolish button clicked")
	demolish_button_pressed.emit()


func _on_build_machines_button_clicked() -> void:
	"""Handle build machines button click"""
	print("Build machines button clicked")
	_show_machine_menu()


func _on_machine_menu_close_clicked() -> void:
	"""Handle machine menu close button click"""
	_hide_machine_menu()


# ========================================
# MACHINE BUILD MENU
# ========================================

func _show_machine_menu() -> void:
	"""Show the machine build menu (swap views)"""
	if actions_view and machines_view:
		actions_view.visible = false
		machines_view.visible = true


func _hide_machine_menu() -> void:
	"""Hide the machine build menu (swap back to actions)"""
	if actions_view and machines_view:
		actions_view.visible = true
		machines_view.visible = false

func _create_machine_menu() -> void:
	"""Create buttons for buildable machines"""
	if not machine_menu:
		print("ERROR: machine_menu is null!")
		return

	# Get facility type to filter machines
	var facility_id = GameManager.active_factory_id
	if facility_id.is_empty():
		print("ERROR: No active factory ID")
		return

	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		print("ERROR: Facility not found: %s" % facility_id)
		return

	var facility_type = facility.type
	print("Creating machine menu for facility type: %s" % facility_type)

	# Get machines available for this facility type
	var machines = DataManager.get_machines_for_facility(facility_type)
	print("Found %d machines for %s" % [machines.size(), facility_type])

	# Group machines by category
	var categories = {}
	for machine_id in machines:
		var machine_def = machines[machine_id]
		var category = machine_def.get("category", "other")
		if not categories.has(category):
			categories[category] = []
		categories[category].append({"id": machine_id, "def": machine_def})

	# Create buttons organized by category
	for category in categories:
		# Add category label
		if categories.size() > 1:
			var label = Label.new()
			label.text = category.capitalize()
			label.add_theme_font_size_override("font_size", 14)
			machine_menu.add_child(label)

		# Add machines in this category
		for machine_data in categories[category]:
			_create_machine_button(machine_data.id, machine_data.def)

		# Add separator between categories
		if category != categories.keys()[-1]:
			var separator = VSeparator.new()
			machine_menu.add_child(separator)


func _create_machine_button(machine_id: String, machine_def: Dictionary) -> void:
	"""Create a build button for a machine"""
	var button = Button.new()
	var name = machine_def.get("name", machine_id)
	var cost = machine_def.get("cost", 0)

	# Multi-line button text
	button.text = "%s\n$%d" % [name, cost]
	button.custom_minimum_size = Vector2(120, 60)
	button.pressed.connect(_on_machine_button_clicked.bind(machine_id))

	machine_menu.add_child(button)


func _on_machine_button_clicked(machine_id: String) -> void:
	"""Handle machine button click"""
	print("Machine button clicked: %s" % machine_id)
	machine_button_pressed.emit(machine_id)
