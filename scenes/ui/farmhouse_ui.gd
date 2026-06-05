extends PanelContainer

## FarmhouseUI - Info panel for a farmhouse.
##
## Slice-1+ design (2026-06-05): the farmhouse has no settings of its own.
## Crops are assigned per-field via right-click on a placed farm_field
## (see scenes/world_map/world_map.gd:_show_crop_selector_for_field). Field
## placement is its own build-menu tool, not driven from this panel.
##
## This panel now just shows the farmhouse's name, field count, and inventory.
## The legacy crop-selector + place-field-button nodes live in the .tscn but
## are hidden — kept in the scene so old saves and the existing signal
## connections don't break, and so re-enabling for testing is a one-liner.

# ========================================
# SIGNALS
# ========================================

# Legacy — emitted by the now-hidden Place Field button. Kept for the
# connection in world_map.gd but never fires under the new design.
signal place_field_requested(farmhouse_id: String, crop_type: String)
# Legacy — same as above for the now-hidden crop dropdown.
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

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)

	# Hide the legacy crop-selector + place-field row entirely. The whole
	# CropSection container is hidden so its child labels/spacing collapse.
	var crop_section: Node = get_node_or_null("MarginContainer/VBoxContainer/CropSection")
	if crop_section and crop_section is CanvasItem:
		(crop_section as CanvasItem).visible = false

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
	"""Show the read-only info panel for a specific farmhouse."""
	current_farmhouse_id = farmhouse_id

	var facility = WorldManager.get_facility(farmhouse_id)
	if facility.is_empty():
		push_error("FarmhouseUI: Invalid farmhouse ID")
		return

	var facility_def = DataManager.get_facility_data(facility.type)
	title_label.text = facility_def.get("name", "Farmhouse")

	_update_stats()
	visible = true

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

func _update_stats() -> void:
	"""Update field count and inventory display.
	Field count counts both legacy registered fields and any farm_field that
	currently lists this farmhouse as its servicing farmhouse — that way the
	panel reflects the new field-discovery model."""
	# Legacy registered children (barley_field/wheat_field placed via the
	# old farmhouse-driven flow).
	var legacy_children: Array = WorldManager.get_farmhouse_children(current_farmhouse_id)
	var serviced_count: int = 0
	for facility in WorldManager.get_all_facilities():
		var def: Dictionary = DataManager.get_facility_data(facility.type)
		if not def.get("is_farm_field", false):
			continue
		if WorldManager.find_servicing_farmhouse(facility.id) == current_farmhouse_id:
			serviced_count += 1
	field_count_label.text = "Fields: %d" % (legacy_children.size() + serviced_count)

	# Inventory
	var inventory: Dictionary = ProductionManager.get_inventory(current_farmhouse_id)
	if inventory.is_empty():
		inventory_label.text = "(empty)"
	else:
		var inv_text: String = ""
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
