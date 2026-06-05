extends CanvasLayer

## WorldMapUI - UI overlay for the world map
##
## Displays money, date, and build menu.

# ========================================
# REFERENCES
# ========================================

@onready var money_label: Label = $HUD/MoneyLabel
@onready var date_label: Label = $HUD/DateLabel
@onready var maintenance_label: Label = $HUD/MaintenanceLabel
@onready var build_menu: HBoxContainer = $BottomBar/MarginContainer/VBoxContainer/ScrollContainer/HBoxContainer
@onready var build_scroll_container: ScrollContainer = $BottomBar/MarginContainer/VBoxContainer/ScrollContainer
@onready var bottom_bar: Panel = $BottomBar

# Routes panel references
@onready var routes_button: Button = $HUD/RoutesButton
@onready var routes_panel: PanelContainer = $HUD/RoutesPanel
@onready var routes_close_button: Button = $HUD/RoutesPanel/MarginContainer/VBoxContainer/HeaderHBox/CloseButton
@onready var route_list: VBoxContainer = $HUD/RoutesPanel/MarginContainer/VBoxContainer/ScrollContainer/RouteList

# Dev corp-switcher (programmatically created — see _create_corp_switcher).
# Remove when per-corp UI lands and hot-seat switching has a real driver.
var corp_switcher_panel: PanelContainer = null
var corp_switcher_dropdown: OptionButton = null

# ========================================
# SIGNALS
# ========================================

signal build_button_pressed(facility_id: String)
signal create_route_button_pressed()
signal demolish_button_pressed()
signal road_button_pressed(road_id: String)
signal logistics_network_button_pressed()

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	# Update displays
	_update_money_display()
	_update_date_display()
	_update_maintenance_display()

	# Connect signals
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.date_advanced.connect(_on_date_advanced)

	# Connect maintenance signals
	EconomyManager.maintenance_paid.connect(_on_maintenance_paid)
	EconomyManager.facility_disabled.connect(_on_facility_disabled)

	# Refresh build menu when research unlocks new facilities
	EventBus.research_completed.connect(_on_research_completed)

	# Create build menu buttons
	_create_build_menu()

	# Connect routes panel
	if routes_button:
		routes_button.pressed.connect(_on_routes_button_pressed)
	if routes_close_button:
		routes_close_button.pressed.connect(_on_routes_close_pressed)

	# Connect connection events
	EventBus.connection_created.connect(_on_connection_changed)
	EventBus.connection_removed.connect(_on_connection_removed)
	EventBus.connection_updated.connect(_on_connection_changed)

	# Dev: corp switcher (top-right). Exercises corp_id propagation through
	# the action pipe before per-corp build menus / gating land.
	_create_corp_switcher()

	# Per-corp build menu: rebuild from the top whenever the active corp changes,
	# so the previously-selected category (which may now be empty) doesn't trap
	# the player in an empty submenu.
	EventBus.active_corp_changed.connect(_on_active_corp_changed_refresh_menu)


func _process(_delta: float) -> void:
	# Update maintenance display periodically
	_update_maintenance_display()


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
# DEV: CORP SWITCHER (TEMP — DELETE WITH PER-CORP UI)
# ========================================

func _create_corp_switcher() -> void:
	# Dev-only widget. Lets the tester swap active_corp_id at runtime so we can
	# verify corp_id propagation through the action pipe before per-corp build
	# menus and gating predicates land. Visible payoff is quiet for now.
	var hud: Node = get_node_or_null("HUD")
	if hud == null:
		return

	corp_switcher_panel = PanelContainer.new()
	corp_switcher_panel.name = "CorpSwitcherDev"
	corp_switcher_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.92)
	style.border_color = Color(0.95, 0.6, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	corp_switcher_panel.add_theme_stylebox_override("panel", style)

	# Anchor top-right. Top-left is taken by money/date/maintenance labels.
	corp_switcher_panel.anchor_left = 1.0
	corp_switcher_panel.anchor_right = 1.0
	corp_switcher_panel.anchor_top = 0.0
	corp_switcher_panel.anchor_bottom = 0.0
	corp_switcher_panel.offset_left = -260
	corp_switcher_panel.offset_right = -16
	corp_switcher_panel.offset_top = 16
	corp_switcher_panel.offset_bottom = 88
	hud.add_child(corp_switcher_panel)

	var vbox := VBoxContainer.new()
	corp_switcher_panel.add_child(vbox)

	var label := Label.new()
	label.text = "DEV — Active corp"
	label.add_theme_color_override("font_color", Color(0.95, 0.6, 0.2))
	label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(label)

	corp_switcher_dropdown = OptionButton.new()
	corp_switcher_dropdown.add_theme_font_size_override("font_size", 13)
	for corp_id in GameManager.VALID_CORP_IDS:
		corp_switcher_dropdown.add_item(corp_id)
	var idx: int = GameManager.VALID_CORP_IDS.find(GameManager.active_corp_id)
	if idx >= 0:
		corp_switcher_dropdown.select(idx)
	corp_switcher_dropdown.item_selected.connect(_on_corp_switcher_selected)
	vbox.add_child(corp_switcher_dropdown)

	# Keep dropdown in sync if active_corp_id is changed elsewhere (e.g. console).
	EventBus.active_corp_changed.connect(_on_active_corp_changed_dev)


func _on_corp_switcher_selected(index: int) -> void:
	if index < 0 or index >= GameManager.VALID_CORP_IDS.size():
		return
	var corp_id: String = GameManager.VALID_CORP_IDS[index]
	GameManager.set_active_corp(corp_id)


func _on_active_corp_changed_dev(_old_corp_id: String, new_corp_id: String) -> void:
	if corp_switcher_dropdown == null:
		return
	var idx: int = GameManager.VALID_CORP_IDS.find(new_corp_id)
	if idx >= 0 and corp_switcher_dropdown.selected != idx:
		corp_switcher_dropdown.select(idx)


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


func _update_maintenance_display() -> void:
	"""Update maintenance cost display"""
	if not maintenance_label:
		return

	var summary = EconomyManager.get_maintenance_summary()
	var total = summary.total_cost
	var disabled = summary.disabled_count

	var text = "Maintenance: $%d/cycle" % total

	# Show warning if facilities are disabled
	if disabled > 0:
		text += "\n[!] %d disabled" % disabled
		maintenance_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1))
	else:
		maintenance_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.4, 1))

	maintenance_label.text = text


func _on_money_changed(_new_amount: int, _delta: int) -> void:
	"""Handle money changed event"""
	_update_money_display()


func _on_date_advanced(_new_date: Dictionary) -> void:
	"""Handle date advanced event"""
	_update_date_display()


func _on_maintenance_paid(_total_cost: int, _details: Array) -> void:
	"""Handle maintenance paid event"""
	_update_maintenance_display()


func _on_facility_disabled(_facility_id: String, _reason: String) -> void:
	"""Handle facility disabled event"""
	_update_maintenance_display()


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
		# Skip hidden facilities in counts
		if facility_def.get("hidden_from_build_menu", false):
			continue
		# Per-corp filter: only count facilities the active corp owns.
		if not _is_visible_to_active_corp(facility_def):
			continue
		var category = facility_def.get("category", "other")
		category_counts[category] = category_counts.get(category, 0) + 1

	# Create category buttons
	for category in CATEGORY_ORDER:
		var cat_name = CATEGORY_NAMES.get(category, category.capitalize())
		var count = category_counts.get(category, 0)

		# Tools category is special - always show (Demolish is always relevant).
		if category == "tools":
			_add_category_button(category, cat_name, -1)  # -1 means don't show count
		elif count > 0:
			_add_category_button(category, cat_name, count)


func _is_visible_to_active_corp(def: Dictionary) -> bool:
	"""Per-corp build-menu filter.
	`active_corp_id == single` is the dev/legacy default — shows everything.
	Otherwise, an entity is visible to the active corp when its corp_id matches
	or is `shared` (cross-corp infra). Facilities and roads use the same field."""
	var active: String = GameManager.active_corp_id
	if active == GameManager.CORP_SINGLE:
		return true
	var owner: String = def.get("corp_id", GameManager.CORP_SINGLE)
	return owner == active or owner == GameManager.CORP_SHARED


func _on_active_corp_changed_refresh_menu(_old_corp_id: String, _new_corp_id: String) -> void:
	"""Rebuild the build menu from the category view when the active corp
	changes. The previously-selected category may now be empty, so always
	pop back to the top-level category view."""
	_show_categories()


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
	"""Add tool buttons (Logistics Network, Create Route, Demolish, Roads).
	Per-corp gating:
	  - Logistics Network and Create Route: logistics (+ single dev fallback)
	  - Demolish: every corp (ownership is enforced in the predicate)
	  - Roads: filtered per road's corp_id"""
	var active: String = GameManager.active_corp_id
	var is_logistics_or_dev: bool = active == GameManager.CORP_LOGISTICS or active == GameManager.CORP_SINGLE

	# Logistics Network button (node-based connection UI)
	if is_logistics_or_dev:
		var logistics_button = Button.new()
		logistics_button.text = "Logistics\nNetwork"
		logistics_button.custom_minimum_size = Vector2(100, 60)
		logistics_button.pressed.connect(_on_logistics_network_button_clicked)
		# Style with green color for connections
		var logistics_style = StyleBoxFlat.new()
		logistics_style.bg_color = Color(0.2, 0.4, 0.3)
		logistics_style.border_width_bottom = 4
		logistics_style.border_color = Color(0.3, 0.7, 0.4)
		logistics_style.corner_radius_top_left = 4
		logistics_style.corner_radius_top_right = 4
		logistics_style.corner_radius_bottom_left = 4
		logistics_style.corner_radius_bottom_right = 4
		logistics_button.add_theme_stylebox_override("normal", logistics_style)
		var logistics_hover_style = logistics_style.duplicate()
		logistics_hover_style.bg_color = Color(0.25, 0.5, 0.35)
		logistics_button.add_theme_stylebox_override("hover", logistics_hover_style)
		build_menu.add_child(logistics_button)

		var route_button = Button.new()
		route_button.text = "Create\nRoute"
		route_button.custom_minimum_size = Vector2(100, 60)
		route_button.pressed.connect(_on_create_route_button_clicked)
		build_menu.add_child(route_button)

	# Demolish is available to every corp — each corp only demolishes what
	# it owns (ownership predicate already exists in WorldManager).
	var demolish_button = Button.new()
	demolish_button.text = "Demolish"
	demolish_button.custom_minimum_size = Vector2(100, 60)
	demolish_button.pressed.connect(_on_demolish_button_clicked)
	build_menu.add_child(demolish_button)

	# Add road buttons filtered by corp ownership. Skip the "Roads:" header
	# entirely if no roads are visible to the active corp.
	var visible_roads: Array = []
	var roads = DataManager.get_all_roads()
	for road_id in roads:
		var road_def = roads[road_id]
		if not _is_visible_to_active_corp(road_def):
			continue
		visible_roads.append([road_id, road_def])

	if visible_roads.size() > 0:
		var road_sep = VSeparator.new()
		road_sep.custom_minimum_size = Vector2(2, 50)
		build_menu.add_child(road_sep)

		var road_label = Label.new()
		road_label.text = "Roads:"
		road_label.add_theme_font_size_override("font_size", 12)
		road_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		build_menu.add_child(road_label)

		for road_pair in visible_roads:
			_create_road_button(road_pair[0], road_pair[1])


func _add_category_buildings(category: String) -> void:
	"""Add all unlocked buildings in a category, filtered by active corp."""
	var facilities = DataManager.get_all_facilities()

	for facility_id in facilities:
		var facility_def = facilities[facility_id]
		if facility_def.get("category", "other") != category:
			continue

		# Skip hidden facilities (fields are placed via farmhouse UI)
		if facility_def.get("hidden_from_build_menu", false):
			continue

		# Only show unlocked facilities
		if not ResearchManager.is_facility_unlocked(facility_id):
			continue

		# Per-corp filter
		if not _is_visible_to_active_corp(facility_def):
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


func _on_logistics_network_button_clicked() -> void:
	"""Handle logistics network button click"""
	print("Logistics Network button clicked")
	logistics_network_button_pressed.emit()


func _create_road_button(road_id: String, road_def: Dictionary) -> void:
	"""Create a button for a road type"""
	var button = Button.new()
	var road_name = road_def.get("name", road_id)
	var cost = road_def.get("cost", 25)

	button.text = "%s\n$%d" % [road_name, cost]
	button.custom_minimum_size = Vector2(100, 60)
	button.pressed.connect(_on_road_button_clicked.bind(road_id))

	# Style with road color
	var visual = road_def.get("visual", {})
	var color = Color(visual.get("color", "#8B7355"))
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = color.darkened(0.4)
	stylebox.border_width_bottom = 4
	stylebox.border_color = color
	stylebox.corner_radius_top_left = 4
	stylebox.corner_radius_top_right = 4
	stylebox.corner_radius_bottom_left = 4
	stylebox.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", stylebox)

	var hover_style = stylebox.duplicate()
	hover_style.bg_color = color.darkened(0.2)
	button.add_theme_stylebox_override("hover", hover_style)

	# Check unlock requirements (for cobblestone_road, etc.)
	var unlock_reqs = road_def.get("unlock_requirements", {})
	if unlock_reqs.has("research"):
		var required_research = unlock_reqs.research
		var is_unlocked = true
		for tech_id in required_research:
			if not ResearchManager.is_unlocked(tech_id):
				is_unlocked = false
				break
		if not is_unlocked:
			button.disabled = true
			button.tooltip_text = "Requires research"

	build_menu.add_child(button)


func _on_road_button_clicked(road_id: String) -> void:
	"""Handle road button click"""
	print("Road button clicked: %s" % road_id)
	road_button_pressed.emit(road_id)


# ========================================
# ROUTES PANEL
# ========================================

func _on_routes_button_pressed() -> void:
	"""Toggle routes panel visibility"""
	if routes_panel:
		routes_panel.visible = not routes_panel.visible
		if routes_panel.visible:
			_update_routes_panel()


func _on_routes_close_pressed() -> void:
	"""Close routes panel"""
	if routes_panel:
		routes_panel.visible = false


func _on_connection_changed(_connection_data: Dictionary) -> void:
	"""Update routes panel when connections change"""
	if routes_panel and routes_panel.visible:
		_update_routes_panel()


func _on_connection_removed(_connection_id: String) -> void:
	"""Update routes panel when a connection is removed"""
	if routes_panel and routes_panel.visible:
		_update_routes_panel()


func _update_routes_panel() -> void:
	"""Update the routes panel with current routes"""
	if not route_list:
		return

	# Clear existing entries
	for child in route_list.get_children():
		child.queue_free()

	# Get all connections
	var routes = LogisticsManager.get_all_connections()

	if routes.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No routes created yet.\nUse 'Create Route' in the Tools menu."
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		route_list.add_child(empty_label)
		return

	# Create entry for each route
	for route in routes:
		_create_route_entry(route)


func _create_route_entry(route: Dictionary) -> void:
	"""Create a UI entry for a route"""
	var entry = HBoxContainer.new()
	entry.custom_minimum_size = Vector2(0, 40)

	# Route info label
	var info_label = Label.new()
	var source = WorldManager.get_facility(route.source_id)
	var dest = WorldManager.get_facility(route.destination_id)

	var source_name = "Unknown"
	var dest_name = "Unknown"
	if not source.is_empty():
		var source_def = DataManager.get_facility_data(source.type)
		source_name = source_def.get("name", source.type)
	if not dest.is_empty():
		var dest_def = DataManager.get_facility_data(dest.type)
		dest_name = dest_def.get("name", dest.type)

	var product_name = route.product.capitalize().replace("_", " ")
	var status = "Active" if route.active else "Paused"
	var status_color = Color(0.5, 1.0, 0.5) if route.active else Color(1.0, 0.5, 0.5)

	info_label.text = "%s → %s\n%s" % [source_name, dest_name, product_name]
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(info_label)

	# Status label
	var status_label = Label.new()
	status_label.text = status
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", status_color)
	status_label.custom_minimum_size = Vector2(50, 0)
	entry.add_child(status_label)

	# Pause/Resume button
	var pause_button = Button.new()
	pause_button.text = "▶" if not route.active else "⏸"
	pause_button.tooltip_text = "Resume" if not route.active else "Pause"
	pause_button.custom_minimum_size = Vector2(35, 30)
	pause_button.pressed.connect(_on_route_pause_pressed.bind(route.id))
	entry.add_child(pause_button)

	# Delete button
	var delete_button = Button.new()
	delete_button.text = "🗑"
	delete_button.tooltip_text = "Delete Route"
	delete_button.custom_minimum_size = Vector2(35, 30)
	delete_button.pressed.connect(_on_route_delete_pressed.bind(route.id))
	entry.add_child(delete_button)

	route_list.add_child(entry)

	# Add separator
	var separator = HSeparator.new()
	route_list.add_child(separator)


func _on_route_pause_pressed(connection_id: String) -> void:
	"""Toggle connection pause state"""
	LogisticsManager.toggle_connection_active(connection_id)
	_update_routes_panel()


func _on_route_delete_pressed(connection_id: String) -> void:
	"""Delete a connection"""
	LogisticsManager.remove_connection(connection_id)
	_update_routes_panel()
