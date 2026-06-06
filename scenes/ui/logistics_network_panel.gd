extends PanelContainer

## LogisticsNetworkPanel - Visual node-based UI for creating logistics connections

signal close_requested()

@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderHBox/CloseButton
@onready var network_view: Control = $MarginContainer/VBoxContainer/NetworkView
@onready var connections_label: Label = $MarginContainer/VBoxContainer/StatsHBox/ConnectionsLabel
@onready var vehicles_label: Label = $MarginContainer/VBoxContainer/StatsHBox/VehiclesLabel

var _drag_source: String = ""
# Product of the output socket the connection drag started from. The route's
# carried product is THIS, not something the panel re-derives — set by the
# updated `facility_drag_started` signal contract (slice 2.3).
var _drag_source_product: String = ""


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


func _on_drag_started(facility_id: String, product: String) -> void:
	_drag_source = facility_id
	_drag_source_product = product


func _on_drag_ended(target_facility_id: String, target_product: String) -> void:
	# Cancelled (released on empty space / node body, not on an input socket).
	if target_facility_id.is_empty():
		_drag_source = ""
		_drag_source_product = ""
		return
	if _drag_source.is_empty():
		_drag_source_product = ""
		return
	if _drag_source == target_facility_id:
		_drag_source = ""
		_drag_source_product = ""
		return
	# Slice-2.3: socket products must match. The dragged source product is
	# the route's carried product; if the dropped input socket expects a
	# different product, refuse and explain.
	if target_product != _drag_source_product:
		EventBus.notification_posted.emit(
			"Sockets don't match: %s → %s" % [_drag_source_product, target_product],
			"error",
		)
		_drag_source = ""
		_drag_source_product = ""
		return
	# Routes are Logistics-owned in v1 (technical-architecture A7); omit
	# corp_id to take the default.
	var conn_id := LogisticsManager.create_connection(_drag_source, target_facility_id, _drag_source_product)
	if not conn_id.is_empty():
		EventBus.notification_posted.emit("Connection: %s" % _drag_source_product.capitalize(), "info")
	_drag_source = ""
	_drag_source_product = ""


func _on_connection_delete(connection_id: String) -> void:
	LogisticsManager.remove_connection(connection_id)


func _on_logistics_changed(_data = null) -> void:
	if visible:
		network_view.update_facility_positions()


