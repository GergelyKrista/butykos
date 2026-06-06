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
	# Solid background so the network view reads as a self-contained editor
	# rather than a glass panel over the world map.
	style.bg_color = Color(0.10, 0.11, 0.14, 1.0)
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

	# Routes are Logistics-owned in v1 (technical-architecture A7); omit corp_id to take the default.
	var conn_id = LogisticsManager.create_connection(_drag_source, target_facility_id, product)
	if not conn_id.is_empty():
		EventBus.notification_posted.emit("Connection: %s" % product.capitalize(), "info")

	_drag_source = ""


func _on_connection_delete(connection_id: String) -> void:
	LogisticsManager.remove_connection(connection_id)


func _on_logistics_changed(_data = null) -> void:
	if visible:
		network_view.update_facility_positions()


func _determine_product(source_id: String, dest_id: String) -> String:
	"""Pick the product to carry on a new connection — strict match against
	the source's CURRENT outputs and the dest's CURRENT inputs (slice-2.1+
	gates farmhouse outputs by inventory and brewery I/O by hopper presence).
	Returns "" if the source doesn't actually produce anything the dest
	accepts. The caller surfaces the "No compatible product!" notification."""
	if network_view == null:
		return ""
	var src_io: Dictionary = network_view.get_node_io(source_id)
	var dst_io: Dictionary = network_view.get_node_io(dest_id)
	for output in src_io.outputs:
		if output in dst_io.inputs:
			return String(output)
	return ""
