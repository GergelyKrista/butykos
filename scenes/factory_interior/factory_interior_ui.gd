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

# ========================================
# REFERENCES
# ========================================

@onready var back_button: Button = $BackButton
@onready var connect_button: Button = $ConnectButton
@onready var factory_label: Label = $FactoryLabel
@onready var machine_menu: HBoxContainer = $BottomBar/MarginContainer/VBoxContainer/ScrollContainer/HBoxContainer

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

	# Update factory label
	_update_factory_label()

	# Create machine build menu
	_create_machine_menu()


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


# ========================================
# MACHINE BUILD MENU
# ========================================

func _create_machine_menu() -> void:
	"""Create buttons for buildable machines"""
	if not machine_menu:
		return

	# Get facility type to filter machines
	var facility_id = GameManager.active_factory_id
	if facility_id.is_empty():
		return

	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return

	var facility_type = facility.type

	# Get machines available for this facility type
	var machines = DataManager.get_machines_for_facility(facility_type)

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
