extends PanelContainer

## LogisticsNetworkPanel - Visual node-based UI for creating logistics connections

signal close_requested()

@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderHBox/CloseButton
@onready var network_view: Control = $MarginContainer/VBoxContainer/NetworkView
@onready var connections_label: Label = $MarginContainer/VBoxContainer/StatsHBox/ConnectionsLabel
@onready var vehicles_label: Label = $MarginContainer/VBoxContainer/StatsHBox/VehiclesLabel

var _drag_source: String = ""


func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)

	# Connect network view signals
	network_view.facility_drag_started.connect(_on_drag_started)
	network_view.facility_drag_ended.connect(_on_drag_ended)
	network_view.connection_right_clicked.connect(_on_connection_delete)

	# Set panel style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)

	# Connect to logistics events
	EventBus.connection_created.connect(_on_logistics_changed)
	EventBus.connection_removed.connect(_on_logistics_changed)
	EventBus.facility_placed.connect(_on_logistics_changed)
	EventBus.facility_removed.connect(_on_logistics_changed)

	visible = false


func _process(_delta: float) -> void:
	if visible:
		_update_stats()


func show_panel() -> void:
	network_view.update_facility_positions()
	visible = true
	EventBus.logistics_panel_opened.emit()


func hide_panel() -> void:
	visible = false
	EventBus.logistics_panel_closed.emit()
	close_requested.emit()


func _update_stats() -> void:
	connections_label.text = "Connections: %d" % LogisticsManager.get_connection_count()
	vehicles_label.text = "Active Vehicles: %d" % LogisticsManager.get_vehicle_count()


func _on_close_pressed() -> void:
	hide_panel()


func _on_drag_started(facility_id: String) -> void:
	_drag_source = facility_id


func _on_drag_ended(target_facility_id: String) -> void:
	if _drag_source.is_empty() or target_facility_id.is_empty():
		_drag_source = ""
		return

	if _drag_source == target_facility_id:
		_drag_source = ""
		return

	# Determine product
	var product = _determine_product(_drag_source, target_facility_id)
	if product.is_empty():
		EventBus.notification_posted.emit("No compatible product!", "error")
		_drag_source = ""
		return

	# Routes are Logistics-owned in v1 (technical-architecture A7).
	var ok := GameManager.submit_action(GameManager.active_corp_id, GameManager.ACTION_CREATE_LOGISTICS_CONNECTION, {
		"source_id": _drag_source,
		"destination_id": target_facility_id,
		"product": product,
	})
	if ok:
		EventBus.notification_posted.emit("Connection: %s" % product.capitalize(), "info")

	_drag_source = ""


func _on_connection_delete(connection_id: String) -> void:
	GameManager.submit_action(GameManager.active_corp_id, GameManager.ACTION_REMOVE_LOGISTICS_CONNECTION, {
		"connection_id": connection_id,
	})


func _on_logistics_changed(_data = null) -> void:
	if visible:
		network_view.update_facility_positions()


func _determine_product(source_id: String, dest_id: String) -> String:
	var source = WorldManager.get_facility(source_id)
	var dest = WorldManager.get_facility(dest_id)
	if source.is_empty() or dest.is_empty():
		return ""

	var source_def = DataManager.get_facility_data(source.type)
	var dest_def = DataManager.get_facility_data(dest.type)

	var outputs = source_def.get("outputs", [])
	var inputs = dest_def.get("inputs", [])

	if source.type == "farmhouse":
		var crop = ProductionManager.get_farmhouse_crop_type(source_id)
		outputs = [crop if not crop.is_empty() else "barley"]

	for output in outputs:
		if output in inputs:
			return output

	if inputs.is_empty() and outputs.size() > 0:
		return outputs[0]

	return ""
