extends PanelContainer

## TradingScreen — Business corp's slice-1 sales surface.
##
## Matrix layout: rows = sellable products (lager only in slice 1),
## columns = outside connections currently on the map. Each cell shows the
## price that destination quotes for the product (per MarketManager's
## per-destination drift), a reachability indicator (road path exists from
## ANY Storage Warehouse to this destination), a quantity spinner, and a
## Sell button. Sell drains stock from reachable warehouses in deterministic
## order, credits the Business wallet, and emits product_sold so
## MarketManager's supply_pressure tracks the sale.
##
## Code-only UI (no .tscn). Owned by world_map.gd which adds it to its UI
## tree at startup, hidden by default, opened via the Trading Screen button
## that's gated to active_corp_id == CORP_BUSINESS.

# Products the Business player can sell in slice 1. More land as the
# production tech tree expands (per 2026-06-07 doc §7.1).
const SELLABLE_PRODUCTS: Array[String] = ["lager"]

const PRODUCT_COLUMN_WIDTH: float = 180.0
const DESTINATION_COLUMN_WIDTH: float = 170.0

const _COLOR_BUSINESS: Color = Color("#ff6ec7")
const _COLOR_REACHABLE: Color = Color("#7ee787")
const _COLOR_UNREACHABLE: Color = Color(1.0, 0.5, 0.5, 0.7)
const _COLOR_DIM: Color = Color(1.0, 1.0, 1.0, 0.6)

var _grid: GridContainer = null
var _empty_state: Label = null
# Maps "product_id:destination_id" -> SpinBox so _on_sell can read the input.
var _qty_inputs: Dictionary = {}


func _ready() -> void:
	visible = false
	# 1.5× scaled down from base 1920×1080 — same target as the Logistics
	# Network panel so in-game windows feel consistent. UX polish later.
	custom_minimum_size = Vector2(1280, 720)
	# Center on screen with KEEP_SIZE so anchors+offsets resolve to the
	# panel's natural size centered in the parent UI rect.
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Opaque panel — dev readability per 2026-06-XX playtest. Polish later.
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color("#161b22")
	bg.border_color = Color("#ff6ec7")
	bg.border_width_left = 2
	bg.border_width_right = 2
	bg.border_width_top = 2
	bg.border_width_bottom = 2
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	add_theme_stylebox_override("panel", bg)

	_build_ui()

	# Live updates: prices tick every 10s, money + stock change when sales /
	# routes move product, world layout changes when facilities are placed
	# or removed. Refresh on each so the matrix reflects current reality.
	MarketManager.prices_updated.connect(_refresh)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.facility_placed.connect(_on_facility_changed)
	EventBus.facility_removed.connect(_on_facility_removed)


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


# ========================================
# UI CONSTRUCTION
# ========================================

func _build_ui() -> void:
	var outer: MarginContainer = MarginContainer.new()
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 16)
	add_child(outer)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	outer.add_child(root)

	# Header: title + close button
	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)

	var title: Label = Label.new()
	title.text = "Trading Screen"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", _COLOR_BUSINESS)
	header.add_child(title)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn: Button = Button.new()
	close_btn.text = "  X  "
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# Subtitle
	var subtitle: Label = Label.new()
	subtitle.text = "Sell stock from Storage Warehouses to outside connections. Each destination's price drifts independently — watch the matrix."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", _COLOR_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(subtitle)

	# Matrix grid (built lazily in _refresh so columns track current world state).
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 10)
	root.add_child(_grid)

	# Empty-state label, shown when no outside connections exist (shouldn't
	# happen post world-gen, but covers the no-spawn edge case cleanly).
	_empty_state = Label.new()
	_empty_state.text = "No outside connections on the map. Start a new game to spawn them."
	_empty_state.add_theme_color_override("font_color", _COLOR_DIM)
	_empty_state.visible = false
	root.add_child(_empty_state)


# ========================================
# REFRESH
# ========================================

func _refresh() -> void:
	if not visible:
		return

	for child in _grid.get_children():
		child.queue_free()
	_qty_inputs.clear()

	var outside_connections: Array[Dictionary] = WorldManager.get_outside_connections()
	if outside_connections.is_empty():
		_grid.visible = false
		_empty_state.visible = true
		return
	_grid.visible = true
	_empty_state.visible = false

	# Stable column order so the matrix doesn't shuffle between refreshes —
	# sort by grid_pos so the player learns "left column = north edge", etc.
	outside_connections.sort_custom(func(a, b):
		var pa: Vector2i = a.grid_pos
		var pb: Vector2i = b.grid_pos
		if pa.y != pb.y:
			return pa.y < pb.y
		return pa.x < pb.x
	)

	_grid.columns = 1 + outside_connections.size()

	# Header row: empty corner + destination labels with reachability + side hint
	var corner: Label = Label.new()
	corner.text = "Product"
	corner.add_theme_font_size_override("font_size", 12)
	corner.add_theme_color_override("font_color", _COLOR_DIM)
	corner.custom_minimum_size = Vector2(PRODUCT_COLUMN_WIDTH, 0)
	_grid.add_child(corner)

	for oc in outside_connections:
		_grid.add_child(_build_destination_header(oc))

	# Product rows
	for product in SELLABLE_PRODUCTS:
		_grid.add_child(_build_product_header(product))
		for oc in outside_connections:
			_grid.add_child(_build_cell(product, oc))


func _build_destination_header(oc: Dictionary) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.custom_minimum_size = Vector2(DESTINATION_COLUMN_WIDTH, 0)

	var name_label: Label = Label.new()
	name_label.text = _connection_label(oc)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", _COLOR_BUSINESS)
	cell.add_child(name_label)

	var reachable: bool = _is_destination_reachable(oc.id)
	var status: Label = Label.new()
	status.text = "● reachable by road" if reachable else "✕ no road from any warehouse"
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", _COLOR_REACHABLE if reachable else _COLOR_UNREACHABLE)
	cell.add_child(status)

	return cell


func _build_product_header(product: String) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.custom_minimum_size = Vector2(PRODUCT_COLUMN_WIDTH, 0)

	var pname: Label = Label.new()
	var pdef: Dictionary = DataManager.get_product_data(product)
	pname.text = String(pdef.get("name", product))
	pname.add_theme_font_size_override("font_size", 16)
	pname.add_theme_color_override("font_color", DataManager.get_product_color(product))
	cell.add_child(pname)

	var stock: int = _total_stock(product)
	var stock_label: Label = Label.new()
	stock_label.text = "%d in storage" % stock
	stock_label.add_theme_font_size_override("font_size", 11)
	stock_label.add_theme_color_override("font_color", _COLOR_DIM)
	cell.add_child(stock_label)

	var base: int = MarketManager.get_base_price(product)
	var base_label: Label = Label.new()
	base_label.text = "base $%d" % base
	base_label.add_theme_font_size_override("font_size", 10)
	base_label.add_theme_color_override("font_color", _COLOR_DIM)
	cell.add_child(base_label)

	return cell


func _build_cell(product: String, oc: Dictionary) -> Control:
	var cell: VBoxContainer = VBoxContainer.new()
	cell.custom_minimum_size = Vector2(DESTINATION_COLUMN_WIDTH, 0)

	var stock: int = _total_stock(product)
	var reachable: bool = _is_destination_reachable(oc.id)
	var sellable: bool = reachable and stock > 0

	var price: int = MarketManager.get_price_at(product, oc.id)
	var base: int = MarketManager.get_base_price(product)
	var delta_pct: float = (float(price) / float(maxi(1, base)) - 1.0) * 100.0

	var price_label: Label = Label.new()
	price_label.text = "$%d / unit" % price
	price_label.add_theme_font_size_override("font_size", 16)
	if not reachable:
		price_label.add_theme_color_override("font_color", _COLOR_DIM)
	elif delta_pct > 5.0:
		price_label.add_theme_color_override("font_color", Color("#7ee787"))
	elif delta_pct < -5.0:
		price_label.add_theme_color_override("font_color", Color("#f0883e"))
	else:
		price_label.add_theme_color_override("font_color", Color.WHITE)
	cell.add_child(price_label)

	var delta_label: Label = Label.new()
	delta_label.text = "%+.1f%% vs base" % delta_pct
	delta_label.add_theme_font_size_override("font_size", 10)
	delta_label.add_theme_color_override("font_color", _COLOR_DIM)
	cell.add_child(delta_label)

	var spin: SpinBox = SpinBox.new()
	spin.min_value = 1
	spin.max_value = maxi(1, stock)
	spin.value = mini(10, maxi(1, stock))
	spin.step = 1
	spin.editable = sellable
	spin.custom_minimum_size = Vector2(0, 28)
	cell.add_child(spin)
	_qty_inputs["%s:%s" % [product, oc.id]] = spin

	var sell_btn: Button = Button.new()
	sell_btn.text = "Sell"
	sell_btn.disabled = not sellable
	sell_btn.pressed.connect(_on_sell.bind(product, String(oc.id)))
	cell.add_child(sell_btn)

	return cell


# ========================================
# QUERIES
# ========================================

func _connection_label(oc: Dictionary) -> String:
	"""Compass-side label so the player can map columns to map edges. Reading
	left→right after the y-then-x sort: north entries first, then east edges,
	then south, then west."""
	var pos: Vector2i = oc.grid_pos
	if pos.y == 0:
		return "Outside N @ %d" % pos.x
	if pos.y == WorldManager.GRID_SIZE.y - 1:
		return "Outside S @ %d" % pos.x
	if pos.x == 0:
		return "Outside W @ %d" % pos.y
	if pos.x == WorldManager.GRID_SIZE.x - 1:
		return "Outside E @ %d" % pos.y
	return "Outside (%d,%d)" % [pos.x, pos.y]


func _total_stock(product: String) -> int:
	"""Sum of `product` across all storage_warehouse facilities (slice-1
	scope). When settlements + selling points land in slice 1.5, this
	expands to include their buffers."""
	var total: int = 0
	for warehouse in WorldManager.get_facilities_by_type("storage_warehouse"):
		total += ProductionManager.get_inventory_item(String(warehouse.id), product)
	return total


func _is_destination_reachable(destination_id: String) -> bool:
	"""True iff AT LEAST ONE storage warehouse has a road path to this
	destination. Per design doc §6.3, road-reachability is the gate."""
	for warehouse in WorldManager.get_facilities_by_type("storage_warehouse"):
		if not WorldManager.find_road_path(String(warehouse.id), destination_id).is_empty():
			return true
	return false


# ========================================
# SELL
# ========================================

func _on_sell(product: String, destination_id: String) -> void:
	var key: String = "%s:%s" % [product, destination_id]
	var spin: SpinBox = _qty_inputs.get(key, null)
	if spin == null:
		return
	var requested: int = int(spin.value)
	if requested <= 0:
		return
	_execute_sale(product, destination_id, requested)


func _execute_sale(product: String, destination_id: String, requested: int) -> void:
	"""Drain `requested` units of `product` from reachable Storage Warehouses
	(in WorldManager iteration order — deterministic), credit Business at
	the destination's quoted price, emit product_sold so MarketManager's
	supply_pressure tracks the sale."""
	var price: int = MarketManager.get_price_at(product, destination_id)
	if price <= 0:
		return

	var remaining: int = requested
	var drained: int = 0
	for warehouse in WorldManager.get_facilities_by_type("storage_warehouse"):
		if remaining <= 0:
			break
		var warehouse_id: String = String(warehouse.id)
		# Skip warehouses with no road path to this destination — same
		# reachability gate as the matrix UI.
		if WorldManager.find_road_path(warehouse_id, destination_id).is_empty():
			continue
		var available: int = ProductionManager.get_inventory_item(warehouse_id, product)
		if available <= 0:
			continue
		var take: int = mini(remaining, available)
		if ProductionManager.remove_item_from_facility(warehouse_id, product, take):
			drained += take
			remaining -= take

	if drained <= 0:
		push_warning("Trading Screen: nothing drained (stock exhausted between click and dispatch?)")
		return

	var revenue: int = price * drained
	var reason: String = "Sold %d %s to %s @ $%d" % [drained, product, destination_id, price]
	EconomyManager.earn_money(GameManager.CORP_BUSINESS, revenue, reason)
	# product_sold drives MarketManager.supply_pressure — selling at a
	# destination pushes the GLOBAL price down (Phase 11 will refine to
	# per-destination pressure if it matters).
	EventBus.product_sold.emit(product, drained, revenue)

	_refresh()


# ========================================
# SIGNAL HANDLERS
# ========================================

func _on_money_changed(_new_amount: int, _delta: int) -> void:
	if visible:
		_refresh()


func _on_facility_changed(_facility: Dictionary) -> void:
	if visible:
		_refresh()


func _on_facility_removed(_facility_id: String) -> void:
	if visible:
		_refresh()
