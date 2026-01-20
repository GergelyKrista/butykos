extends PanelContainer

## FarmhouseUI - Panel for managing farmhouse fields and crop selection
##
## Displays crop type selector, field placement button, field count, and inventory.

# ========================================
# SIGNALS
# ========================================

signal place_field_requested(farmhouse_id: String, crop_type: String)
signal crop_type_changed(farmhouse_id: String, crop_type: String)
signal close_requested()

# ========================================
# REFERENCES
# ========================================

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderHBox/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderHBox/CloseButton
@onready var crop_selector: OptionButton = $MarginContainer/VBoxContainer/CropSection/CropSelector
@onready var place_field_button: Button = $MarginContainer/VBoxContainer/CropSection/PlaceFieldButton
@onready var field_count_label: Label = $MarginContainer/VBoxContainer/StatsSection/FieldCountLabel
@onready var inventory_label: Label = $MarginContainer/VBoxContainer/InventorySection/InventoryLabel

# ========================================
# STATE
# ========================================

var current_farmhouse_id: String = ""
var supported_crops: Array = []

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	place_field_button.pressed.connect(_on_place_field_pressed)
	crop_selector.item_selected.connect(_on_crop_selected)

	# Set solid background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	visible = false


# ========================================
# PUBLIC METHODS
# ========================================

func show_for_farmhouse(farmhouse_id: String) -> void:
	"""Show the UI for a specific farmhouse"""
	current_farmhouse_id = farmhouse_id

	# Get farmhouse data
	var facility = WorldManager.get_facility(farmhouse_id)
	if facility.is_empty():
		push_error("FarmhouseUI: Invalid farmhouse ID")
		return

	var facility_def = DataManager.get_facility_data(facility.type)

	# Update title
	title_label.text = facility_def.get("name", "Farmhouse")

	# Get supported crops
	supported_crops = facility_def.get("supported_crops", ["barley", "wheat"])

	# Populate crop selector
	_populate_crop_selector()

	# Update stats
	_update_stats()

	# Show panel
	visible = true

	# Emit signal
	EventBus.farmhouse_ui_opened.emit(farmhouse_id)


func hide_ui() -> void:
	"""Hide the farmhouse UI"""
	if visible and not current_farmhouse_id.is_empty():
		EventBus.farmhouse_ui_closed.emit(current_farmhouse_id)

	visible = false
	current_farmhouse_id = ""


func refresh() -> void:
	"""Refresh the UI display"""
	if not current_farmhouse_id.is_empty():
		_update_stats()


# ========================================
# PRIVATE METHODS
# ========================================

func _populate_crop_selector() -> void:
	"""Populate the crop type dropdown"""
	crop_selector.clear()

	for crop in supported_crops:
		var crop_name = crop.capitalize()
		crop_selector.add_item(crop_name)

	# Select current crop type for this farmhouse
	var current_crop = ProductionManager.get_farmhouse_crop_type(current_farmhouse_id)
	if current_crop.is_empty() and supported_crops.size() > 0:
		current_crop = supported_crops[0]
		ProductionManager.set_farmhouse_crop_type(current_farmhouse_id, current_crop)

	# Find and select the current crop
	for i in range(supported_crops.size()):
		if supported_crops[i] == current_crop:
			crop_selector.select(i)
			break


func _update_stats() -> void:
	"""Update field count and inventory display"""
	# Get field count
	var children = WorldManager.get_farmhouse_children(current_farmhouse_id)
	field_count_label.text = "Fields: %d" % children.size()

	# Get inventory
	var inventory = ProductionManager.get_inventory(current_farmhouse_id)
	if inventory.is_empty():
		inventory_label.text = "(empty)"
	else:
		var inv_text = ""
		for product in inventory:
			var amount = inventory[product]
			inv_text += "%s: %d\n" % [product.capitalize(), amount]
		inventory_label.text = inv_text.strip_edges()


# ========================================
# EVENT HANDLERS
# ========================================

func _on_close_pressed() -> void:
	"""Handle close button"""
	hide_ui()
	close_requested.emit()


func _on_place_field_pressed() -> void:
	"""Handle place field button"""
	var selected_index = crop_selector.selected
	if selected_index >= 0 and selected_index < supported_crops.size():
		var crop_type = supported_crops[selected_index]
		place_field_requested.emit(current_farmhouse_id, crop_type)


func _on_crop_selected(index: int) -> void:
	"""Handle crop type selection change"""
	if index >= 0 and index < supported_crops.size():
		var crop_type = supported_crops[index]
		ProductionManager.set_farmhouse_crop_type(current_farmhouse_id, crop_type)
		crop_type_changed.emit(current_farmhouse_id, crop_type)
		EventBus.farmhouse_crop_changed.emit(current_farmhouse_id, crop_type)
