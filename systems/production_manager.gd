extends Node

## ProductionManager - Simple production simulation
##
## Handles production cycles for facilities. Each facility produces
## resources at regular intervals based on its definition.
## Now integrates with ResearchManager for production bonuses.

# ========================================
# TARGET MAPPINGS FOR RESEARCH BONUSES
# ========================================

# Map facility types to bonus targets
const FACILITY_TARGET_MAP: Dictionary = {
	# Agriculture
	"barley_field": ["fields", "agriculture"],
	"wheat_farm": ["fields", "agriculture"],
	"corn_field": ["fields", "agriculture"],
	"hop_farm": ["fields", "agriculture"],
	"vineyard": ["fields", "agriculture"],
	"water_source": ["fields", "agriculture"],
	# Processing
	"grain_mill": ["processing", "grain_mill"],
	"industrial_mill": ["processing", "grain_mill"],
	"packaging_plant": ["processing", "packaging", "packaged"],
	"bottling_facility": ["processing", "packaging", "packaged"],
	# Production
	"brewery": ["production", "brewery", "beers"],
	"lager_brewery": ["production", "brewery", "beers"],
	"distillery": ["production", "distillery", "spirits"],
	"whiskey_distillery": ["production", "distillery", "spirits"],
	"vodka_distillery": ["production", "distillery", "spirits"],
	"winery": ["production", "winery", "wine"],
	"tavern": ["production", "commerce"],
	"trade_office": ["production", "commerce"],
	# Storage
	"storage_warehouse": ["storage"],
	"aging_cellar": ["storage", "aging", "aged_spirits"],
	"barrel_house": ["storage", "aging", "aged_spirits"],
	"distribution_depot": ["storage", "logistics"],
	"rail_depot": ["storage", "logistics"]
}

# ========================================
# STATE
# ========================================

# Facility production
# Dictionary of production timers: { facility_id: time_remaining }
var production_timers: Dictionary = {}

# Dictionary of production outputs: { facility_id: {product_id: quantity} }
var production_outputs: Dictionary = {}

# Production statistics tracking
# Dictionary of facility stats: { facility_id: { total_produced: {product: quantity}, total_consumed: {product: quantity}, total_revenue: int } }
var facility_stats: Dictionary = {}

# Machine production
# Dictionary of machine production timers: { "facility_id:machine_id": time_remaining }
var machine_timers: Dictionary = {}

# Dictionary of machine inventories: { "facility_id:machine_id": {product_id: quantity} }
# Machines now have their own inventory instead of using facility inventory
var machine_inventories: Dictionary = {}

# Farmhouse crop type tracking (LEGACY — pre per-field-crop model).
# Kept so legacy barley_field / wheat_field facilities continue to function
# until they are removed. New generic `farm_field` uses `field_crop_types` below.
var farmhouse_crop_types: Dictionary = {}

# Field production targets (LEGACY routing for crop-specific field types).
# Dictionary mapping field_id to parent farmhouse_id for inventory routing.
# `farm_field` entities skip this and use `WorldManager.find_servicing_farmhouse`
# at production time instead — output routing is dynamic, not registry-driven.
var field_production_targets: Dictionary = {}

# Per-field crop assignment for the generic `farm_field` entity.
# Dictionary { field_id: crop_type } — populated via the right-click crop selector.
# Replaces the per-farmhouse `farmhouse_crop_types` model for new fields.
var field_crop_types: Dictionary = {}

# Per-field idle-reason log throttle. Maps field_id → last reason logged
# ("no_crop" / "no_farmhouse" / ""). Prevents the tick loop from spamming
# the console with the same message every 5 seconds — a reason is logged
# once when it changes, then suppressed until the state changes again.
var _field_idle_reason: Dictionary = {}

# Per-crop production config for the generic `farm_field` entity.
# Each crop maps to { output, quantity, cycle_time }. Research yield/cycle
# multipliers are looked up by the OUTPUT product so existing
# barley/hops research bonuses apply automatically.
const FARM_FIELD_CROP_PRODUCTION: Dictionary = {
	"barley": { "output": "barley", "quantity": 10, "cycle_time": 5.0 },
	"hops":   { "output": "hops",   "quantity": 8,  "cycle_time": 6.0 },
}

# ========================================
# CONFIGURATION
# ========================================

var auto_sell_enabled: bool = true  # Auto-sell products when produced
var default_sell_price: int = 100   # Default price per product unit

# Input/Output node transfer settings
var io_node_transfer_amount: int = 10  # How much to transfer per cycle
var io_node_timer: float = 0.0  # Timer for periodic IO node operations
const IO_NODE_CYCLE_TIME: float = 2.0  # How often IO nodes transfer (seconds)

# Product pricing - now uses MarketManager for dynamic prices
# Fallback prices only used if MarketManager not available
var _fallback_prices: Dictionary = {
	"barley": 5, "wheat": 5, "corn": 6, "water": 1, "hops": 12, "grapes": 10,
	"malt": 15, "mash": 20, "fermented_wash": 40, "raw_spirit": 50,
	"ale": 100, "packaged_ale": 150, "lager": 120, "wheat_beer": 110,
	"whiskey": 200, "vodka": 180, "premium_whiskey": 300, "aged_spirit": 250,
	"wine": 160, "stout": 130, "porter": 125, "reserve_25_year": 500, "limited_edition": 400
}


func _get_product_price(product: String) -> int:
	"""Get current market price for a product (uses MarketManager if available)"""
	if MarketManager:
		return MarketManager.get_price(product)
	return _fallback_prices.get(product, default_sell_price)


# ========================================
# RESEARCH BONUS HELPERS
# ========================================

func _get_facility_targets(facility_type: String) -> Array:
	"""Get all bonus targets that apply to a facility type"""
	var targets = FACILITY_TARGET_MAP.get(facility_type, [])
	# Always include the facility type itself and "all"
	var all_targets = [facility_type, "all"]
	all_targets.append_array(targets)
	return all_targets


func _get_cycle_time_multiplier(facility_type: String) -> float:
	"""Get combined cycle time multiplier from research for a facility"""
	var multiplier = 1.0
	var targets = _get_facility_targets(facility_type)

	for target in targets:
		# Check cycle_time_multiplier (lower is faster)
		multiplier *= ResearchManager.get_bonus_multiplier("cycle_time_multiplier", target)
		# speed_multiplier also affects cycle time (higher speed = lower cycle time)
		var speed_mult = ResearchManager.get_bonus_multiplier("speed_multiplier", target)
		if speed_mult > 1.0:
			multiplier /= speed_mult  # Higher speed means shorter cycle

	return multiplier


func _get_yield_multiplier(facility_type: String) -> float:
	"""Get combined yield multiplier from research for a facility"""
	var multiplier = 1.0
	var targets = _get_facility_targets(facility_type)

	for target in targets:
		multiplier *= ResearchManager.get_bonus_multiplier("yield_multiplier", target)
		# Efficiency also affects yield
		multiplier *= ResearchManager.get_bonus_multiplier("efficiency_multiplier", target)

	return multiplier


func _get_price_multiplier(product: String) -> float:
	"""Get price multiplier from research for a product"""
	var multiplier = 1.0

	# Check product-specific multipliers
	multiplier *= ResearchManager.get_bonus_multiplier("price_multiplier", product)
	multiplier *= ResearchManager.get_bonus_multiplier("price_multiplier", "all")

	# Check category-based multipliers
	if product in ["ale", "lager", "wheat_beer", "stout", "porter"]:
		multiplier *= ResearchManager.get_bonus_multiplier("price_multiplier", "beers")
	elif product in ["whiskey", "vodka", "raw_spirit", "premium_whiskey"]:
		multiplier *= ResearchManager.get_bonus_multiplier("price_multiplier", "spirits")
	elif product in ["packaged_ale"]:
		multiplier *= ResearchManager.get_bonus_multiplier("price_multiplier", "packaged")
		multiplier *= ResearchManager.get_bonus_multiplier("value_multiplier", "packaged")

	return multiplier


# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("ProductionManager initialized")

	# Connect to facility events
	EventBus.facility_placed.connect(_on_facility_placed)
	EventBus.facility_removed.connect(_on_facility_removed)
	EventBus.facility_constructed.connect(_on_facility_constructed)
	EventBus.production_changed.connect(_on_production_changed)

	# Connect to machine events
	EventBus.machine_placed.connect(_on_machine_placed)
	EventBus.machine_removed.connect(_on_machine_removed)


func _process(delta: float) -> void:
	_update_production(delta)
	_update_machine_production(delta)
	_update_io_nodes(delta)


# ========================================
# PRODUCTION UPDATES
# ========================================

func _update_production(delta: float) -> void:
	"""Update production timers for all active facilities"""

	for facility_id in production_timers.keys():
		var facility = WorldManager.get_facility(facility_id)

		# Skip if facility not found or not producing
		if facility.is_empty() or not facility.get("production_active", false):
			continue

		# Update timer
		production_timers[facility_id] -= delta

		# Check if production cycle complete
		if production_timers[facility_id] <= 0:
			_complete_production_cycle(facility_id, facility)


func _complete_production_cycle(facility_id: String, facility: Dictionary) -> void:
	"""Complete a production cycle for a facility"""

	var facility_def = DataManager.get_facility_data(facility.type)
	if facility_def.is_empty():
		return

	# Generic farm_field has no static `production` block — production is dynamic
	# based on the per-field crop assignment + the field's servicing farmhouse.
	if facility_def.get("is_farm_field", false):
		_complete_farm_field_cycle(facility_id, facility, facility_def)
		return

	var production_data = facility_def.get("production", {})
	if production_data.is_empty():
		return

	var output_product = production_data.get("output", "")
	var base_output_quantity = production_data.get("quantity", 0)
	var base_cycle_time = production_data.get("cycle_time", 5.0)

	if output_product.is_empty() or base_output_quantity == 0:
		return

	# Apply research bonuses
	var yield_mult = _get_yield_multiplier(facility.type)
	var cycle_mult = _get_cycle_time_multiplier(facility.type)

	var output_quantity = int(base_output_quantity * yield_mult)
	var cycle_time = base_cycle_time * cycle_mult

	# Check if facility requires inputs
	var input_product = production_data.get("input", "")
	var input_quantity = production_data.get("input_quantity", 0)

	if not input_product.is_empty() and input_quantity > 0:
		# Check if we have enough input materials
		var current_input = get_inventory_item(facility_id, input_product)
		if current_input < input_quantity:
			# Not enough inputs, can't produce
			print("Production blocked: %s needs %d %s (has %d)" % [
				facility_def.get("name", facility.type),
				input_quantity,
				input_product,
				current_input
			])
			# Reset timer to try again (with research bonus)
			production_timers[facility_id] = cycle_time
			return

		# Consume inputs
		_remove_from_inventory(facility_id, input_product, input_quantity)
		_track_consumption(facility_id, input_product, input_quantity)
		print("Consumed %d %s for production" % [input_quantity, input_product])

	# Check if this field should route output to a farmhouse
	var target_facility_id = facility_id
	var farmhouse_id = field_production_targets.get(facility_id, "")
	if not farmhouse_id.is_empty():
		target_facility_id = farmhouse_id

	# Add output to inventory (with yield bonus) - either field's or farmhouse's
	_add_to_inventory(target_facility_id, output_product, output_quantity)
	_track_production(facility_id, output_product, output_quantity)

	# Reset timer (with cycle time bonus)
	production_timers[facility_id] = cycle_time

	# Show bonus info if any bonuses are active
	var bonus_info = ""
	if yield_mult != 1.0 or cycle_mult != 1.0:
		bonus_info = " [Research: %.0f%% yield, %.0f%% speed]" % [(yield_mult - 1.0) * 100, (1.0 - cycle_mult) * 100]

	print("Production complete: %s produced %d %s%s" % [
		facility_def.get("name", facility.type),
		output_quantity,
		output_product,
		bonus_info
	])

	# Auto-sell if enabled (only if this is a final product with no downstream use)
	if auto_sell_enabled and _should_auto_sell(output_product):
		_sell_product(facility_id, output_product, output_quantity)


# ========================================
# MACHINE PRODUCTION UPDATES
# ========================================

func _update_machine_production(delta: float) -> void:
	"""Update production timers for all active machines"""

	for machine_key in machine_timers.keys():
		# Parse composite key "facility_id:machine_id"
		var parts = machine_key.split(":", false)
		if parts.size() != 2:
			continue

		var facility_id = parts[0]
		var machine_id = parts[1]

		# Get machine data
		var machine = FactoryManager.get_machine(facility_id, machine_id)
		if machine.is_empty():
			continue

		# Check if machine should be producing (facility must be operational)
		var facility = WorldManager.get_facility(facility_id)
		if facility.is_empty() or not facility.get("production_active", false):
			continue

		# Update timer
		machine_timers[machine_key] -= delta

		# Check if production cycle complete
		if machine_timers[machine_key] <= 0:
			_complete_machine_production_cycle(facility_id, machine_id, machine)


func _complete_machine_production_cycle(facility_id: String, machine_id: String, machine: Dictionary) -> void:
	"""Complete a production cycle for a machine"""

	var machine_def = DataManager.get_machine_data(machine.type)
	if machine_def.is_empty():
		return

	var production_data = machine_def.get("production", {})
	if production_data.is_empty():
		return

	var output_product = production_data.get("output", "")
	var output_quantity = production_data.get("quantity", 0)
	var cycle_time = production_data.get("cycle_time", 5.0)

	if output_product.is_empty() or output_quantity == 0:
		return

	var machine_key = "%s:%s" % [facility_id, machine_id]

	# Check if machine requires inputs
	var input_product = production_data.get("input", "")
	var input_quantity = production_data.get("input_quantity", 0)

	if not input_product.is_empty() and input_quantity > 0:
		# Check machine's own inventory for input materials
		var current_input = get_machine_inventory_item(facility_id, machine_id, input_product)
		if current_input < input_quantity:
			# Not enough inputs, can't produce
			print("Machine production blocked: %s needs %d %s (has %d)" % [
				machine_def.get("name", machine.type),
				input_quantity,
				input_product,
				current_input
			])
			# Reset timer to try again
			machine_timers[machine_key] = cycle_time
			return

		# Consume inputs from machine's own inventory
		_remove_from_machine_inventory(facility_id, machine_id, input_product, input_quantity)
		print("Machine consumed %d %s from own inventory" % [input_quantity, input_product])

	# Add output to machine's own inventory
	_add_to_machine_inventory(facility_id, machine_id, output_product, output_quantity)

	# Reset timer
	machine_timers[machine_key] = cycle_time

	print("Machine production complete: %s produced %d %s" % [
		machine_def.get("name", machine.type),
		output_quantity,
		output_product
	])

	# Try to transfer output to adjacent machines
	_try_transfer_to_adjacent(facility_id, machine_id, machine)


# ========================================
# INVENTORY MANAGEMENT
# ========================================

func _add_to_inventory(facility_id: String, product: String, quantity: int) -> void:
	"""Add product to facility inventory"""

	if not production_outputs.has(facility_id):
		production_outputs[facility_id] = {}

	var current = production_outputs[facility_id].get(product, 0)
	production_outputs[facility_id][product] = current + quantity


func _remove_from_inventory(facility_id: String, product: String, quantity: int) -> bool:
	"""Remove product from facility inventory. Returns false if insufficient."""

	if not production_outputs.has(facility_id):
		return false

	var current = production_outputs[facility_id].get(product, 0)
	if current < quantity:
		return false

	production_outputs[facility_id][product] = current - quantity
	return true


func get_inventory(facility_id: String) -> Dictionary:
	"""Get facility inventory"""
	return production_outputs.get(facility_id, {})


func get_inventory_item(facility_id: String, product: String) -> int:
	"""Get quantity of a specific product in facility inventory"""
	if not production_outputs.has(facility_id):
		return 0
	return production_outputs[facility_id].get(product, 0)


func add_item_to_facility(facility_id: String, product: String, quantity: int) -> bool:
	"""Add items to facility from external source (logistics). Returns true if successful."""
	if not WorldManager.get_facility(facility_id):
		return false

	_add_to_inventory(facility_id, product, quantity)
	print("Delivered %d %s to facility %s" % [quantity, product, facility_id])
	return true


func remove_item_from_facility(facility_id: String, product: String, quantity: int) -> bool:
	"""Remove items from facility for logistics. Returns true if successful."""
	return _remove_from_inventory(facility_id, product, quantity)


# ========================================
# FARMHOUSE MANAGEMENT
# ========================================

func can_set_farmhouse_crop(corp_id: String, farmhouse_id: String, crop_type: String) -> Dictionary:
	"""Predicate for ACTION_SET_FARMHOUSE_CROP."""
	var facility: Dictionary = WorldManager.get_facility(farmhouse_id)
	if facility.is_empty():
		return { "ok": false, "reason": "Farmhouse not found" }
	var facility_def: Dictionary = DataManager.get_facility_data(facility.type)
	var supported: Array = facility_def.get("supported_crops", [])
	if crop_type not in supported:
		return { "ok": false, "reason": "Crop %s not supported by %s" % [crop_type, facility.type] }
	return { "ok": true, "reason": "" }


func set_farmhouse_crop_type(farmhouse_id: String, crop_type: String) -> void:
	"""Set the crop type for a farmhouse (LEGACY model — still used by the
	farmhouse UI for legacy barley_field/wheat_field entities)."""
	farmhouse_crop_types[farmhouse_id] = crop_type
	print("Farmhouse %s crop type set to: %s" % [farmhouse_id, crop_type])


func get_farmhouse_crop_type(farmhouse_id: String) -> String:
	"""Get the crop type for a farmhouse (LEGACY)."""
	return farmhouse_crop_types.get(farmhouse_id, "")


func set_field_crop_type(field_id: String, crop_type: String) -> void:
	"""Assign a crop to a generic `farm_field`. The field will start producing
	this crop on its next cycle, provided a farmhouse currently services it
	(see `WorldManager.find_servicing_farmhouse`). Empty `crop_type` clears the
	assignment (field returns to idle)."""
	if crop_type.is_empty():
		field_crop_types.erase(field_id)
	else:
		field_crop_types[field_id] = crop_type
	# Reset the production timer so a freshly-assigned crop kicks in quickly
	# (otherwise the field might idle for up to a full cycle before noticing).
	if production_timers.has(field_id):
		var cfg: Dictionary = FARM_FIELD_CROP_PRODUCTION.get(crop_type, {})
		production_timers[field_id] = float(cfg.get("cycle_time", 5.0))
	# Clear any prior idle-reason record so the next cycle re-evaluates fresh.
	_field_idle_reason.erase(field_id)
	print("Field %s crop set to: %s" % [field_id, crop_type if not crop_type.is_empty() else "(none)"])
	EventBus.field_crop_changed.emit(field_id, crop_type)


func _complete_farm_field_cycle(facility_id: String, facility: Dictionary, _facility_def: Dictionary) -> void:
	"""Cycle handler for the generic farm_field. Idles (resets timer, no output)
	if no crop is assigned, no farmhouse services the field, or the crop is
	unknown. Otherwise, produces into the servicing farmhouse's inventory.
	Idle reasons are logged ONCE per field (throttled via `_field_idle_reason`)
	so the tick loop doesn't spam the console with the same message."""
	var crop: String = field_crop_types.get(facility_id, "")
	if crop.is_empty():
		if _field_idle_reason.get(facility_id, "") != "no_crop":
			_field_idle_reason[facility_id] = "no_crop"
			print("Farm field %s idle: no crop assigned (right-click the field to choose)" % facility_id)
		production_timers[facility_id] = 5.0
		return
	var farmhouse_id: String = WorldManager.find_servicing_farmhouse(facility_id)
	if farmhouse_id.is_empty():
		# Field is placed but not connected/in-range — idle until the player
		# fixes the topology (build a road, place a farmhouse, etc.).
		if _field_idle_reason.get(facility_id, "") != "no_farmhouse":
			_field_idle_reason[facility_id] = "no_farmhouse"
			print("Farm field %s idle: no servicing farmhouse (must be inside a farmhouse's working area AND touching it OR connected by road)" % facility_id)
		production_timers[facility_id] = 5.0
		return
	var crop_cfg: Dictionary = FARM_FIELD_CROP_PRODUCTION.get(crop, {})
	if crop_cfg.is_empty():
		push_warning("farm_field %s has unknown crop '%s'" % [facility_id, crop])
		production_timers[facility_id] = 5.0
		return
	var output_product: String = String(crop_cfg.get("output", ""))
	var base_quantity: int = int(crop_cfg.get("quantity", 0))
	var base_cycle: float = float(crop_cfg.get("cycle_time", 5.0))
	# Research bonuses are keyed by output product (existing barley/hops bonuses
	# still apply to farm_field outputs).
	var yield_mult: float = _get_yield_multiplier(output_product)
	var cycle_mult: float = _get_cycle_time_multiplier(output_product)
	var output_quantity: int = int(base_quantity * yield_mult)
	var cycle_time: float = base_cycle * cycle_mult
	_add_to_inventory(farmhouse_id, output_product, output_quantity)
	_track_production(facility_id, output_product, output_quantity)
	production_timers[facility_id] = cycle_time
	# Successful production clears any prior idle-reason record for this field.
	_field_idle_reason.erase(facility_id)
	print("Farm field %s produced %d %s -> farmhouse %s" % [facility_id, output_quantity, output_product, farmhouse_id])


func register_field_with_farmhouse(field_id: String, farmhouse_id: String) -> void:
	"""Register a field to route production to a farmhouse"""
	field_production_targets[field_id] = farmhouse_id
	print("Field %s registered with farmhouse %s" % [field_id, farmhouse_id])


func unregister_field_from_farmhouse(field_id: String) -> void:
	"""Unregister a field from its parent farmhouse"""
	field_production_targets.erase(field_id)


func get_field_production_target(field_id: String) -> String:
	"""Get the farmhouse ID that a field sends production to"""
	return field_production_targets.get(field_id, "")


func get_field_crop_type(field_id: String) -> String:
	"""Get the crop type for a field based on its parent farmhouse"""
	var farmhouse_id = field_production_targets.get(field_id, "")
	if farmhouse_id.is_empty():
		return ""
	return get_farmhouse_crop_type(farmhouse_id)


# ========================================
# MACHINE INVENTORY MANAGEMENT
# ========================================

func _add_to_machine_inventory(facility_id: String, machine_id: String, product: String, quantity: int) -> void:
	"""Add product to machine's inventory"""
	var machine_key = "%s:%s" % [facility_id, machine_id]

	if not machine_inventories.has(machine_key):
		machine_inventories[machine_key] = {}

	var current = machine_inventories[machine_key].get(product, 0)
	machine_inventories[machine_key][product] = current + quantity


func _remove_from_machine_inventory(facility_id: String, machine_id: String, product: String, quantity: int) -> bool:
	"""Remove product from machine's inventory. Returns false if insufficient."""
	var machine_key = "%s:%s" % [facility_id, machine_id]

	if not machine_inventories.has(machine_key):
		return false

	var current = machine_inventories[machine_key].get(product, 0)
	if current < quantity:
		return false

	machine_inventories[machine_key][product] = current - quantity
	return true


func get_machine_inventory(facility_id: String, machine_id: String) -> Dictionary:
	"""Get machine's inventory"""
	var machine_key = "%s:%s" % [facility_id, machine_id]
	return machine_inventories.get(machine_key, {})


func get_machine_inventory_item(facility_id: String, machine_id: String, product: String) -> int:
	"""Get quantity of a specific product in machine's inventory"""
	var machine_key = "%s:%s" % [facility_id, machine_id]
	if not machine_inventories.has(machine_key):
		return 0
	return machine_inventories[machine_key].get(product, 0)


# ========================================
# MANUAL CONNECTION TRANSFER
# ========================================

func _try_transfer_to_adjacent(facility_id: String, machine_id: String, machine: Dictionary) -> void:
	"""Try to transfer machine's output through manual connections"""

	# Get machine's current inventory
	var inventory = get_machine_inventory(facility_id, machine_id)
	if inventory.is_empty():
		return

	# Get all connections FROM this machine
	var connections = FactoryManager.get_connections_from(facility_id, machine_id)
	if connections.is_empty():
		return

	# Try to transfer each product in our inventory
	for product in inventory.keys():
		var available_quantity = inventory[product]
		if available_quantity <= 0:
			continue

		# Try each connection
		for conn in connections:
			var destination_machine_id = conn.get("to", "")
			if destination_machine_id.is_empty():
				continue

			var destination_machine = FactoryManager.get_machine(facility_id, destination_machine_id)
			if destination_machine.is_empty():
				continue

			# Check if destination machine needs this product
			if _machine_needs_product(destination_machine, product):
				# Try to transfer (transfer up to half of available, min 1)
				var transfer_amount = max(1, available_quantity / 2)

				if _remove_from_machine_inventory(facility_id, machine_id, product, transfer_amount):
					_add_to_machine_inventory(facility_id, destination_machine_id, product, transfer_amount)

					print("Transferred %d %s: %s → %s" % [
						transfer_amount,
						product,
						machine_id,
						destination_machine_id
					])

					# Update available quantity for next transfer
					available_quantity -= transfer_amount
					if available_quantity <= 0:
						break


func _machine_needs_product(machine: Dictionary, product: String) -> bool:
	"""Check if a machine needs a specific product as input"""

	var machine_def = DataManager.get_machine_data(machine.type)
	if machine_def.is_empty():
		return false

	var production_data = machine_def.get("production", {})
	if production_data.is_empty():
		return false

	var input_product = production_data.get("input", "")
	return input_product == product


# ========================================
# INPUT/OUTPUT NODE OPERATIONS
# ========================================

func _update_io_nodes(delta: float) -> void:
	"""Update input/output nodes periodically"""

	io_node_timer += delta
	if io_node_timer < IO_NODE_CYCLE_TIME:
		return

	io_node_timer = 0.0

	# Process all facilities that have interiors
	for facility_id in WorldManager.facilities.keys():
		if not FactoryManager.has_interior(facility_id):
			continue

		var machines = FactoryManager.get_all_machines(facility_id)
		for machine in machines:
			var machine_def = DataManager.get_machine_data(machine.type)
			if machine_def.is_empty():
				continue

			# Handle Input Hoppers: Facility → Machine network
			if machine_def.get("is_input_node", false):
				_process_input_hopper(facility_id, machine)

			# Handle Output Depots: Machine network → Facility
			elif machine_def.get("is_output_node", false):
				_process_output_depot(facility_id, machine)

			# Handle Market Outlets: Machine network → Sell for reduced profit
			elif machine_def.get("is_market_outlet", false):
				_process_market_outlet(facility_id, machine)

			# Handle Storage Buffers: Actively transfer stored products to connected machines
			elif machine_def.get("is_storage_buffer", false):
				_process_storage_buffer(facility_id, machine)


func _process_input_hopper(facility_id: String, hopper: Dictionary) -> void:
	"""Input hopper pulls materials from facility inventory and distributes to connected machines"""

	var hopper_id = hopper.get("id", "")

	# Get all connections FROM this input hopper
	var connections = FactoryManager.get_connections_from(facility_id, hopper_id)
	if connections.is_empty():
		return

	# For each connected machine, check what it needs
	for conn in connections:
		var destination_machine_id = conn.get("to", "")
		if destination_machine_id.is_empty():
			continue

		var destination_machine = FactoryManager.get_machine(facility_id, destination_machine_id)
		if destination_machine.is_empty():
			continue

		var machine_def = DataManager.get_machine_data(destination_machine.type)
		if machine_def.is_empty():
			continue

		var production_data = machine_def.get("production", {})
		if production_data.is_empty():
			continue

		# Get what the connected machine needs
		var input_product = production_data.get("input", "")
		if input_product.is_empty():
			continue

		# Check if facility has this product
		var facility_stock = get_inventory_item(facility_id, input_product)
		if facility_stock <= 0:
			continue

		# Transfer from facility to connected machine
		var transfer_amount = min(io_node_transfer_amount, facility_stock)
		if _remove_from_inventory(facility_id, input_product, transfer_amount):
			_add_to_machine_inventory(facility_id, destination_machine_id, input_product, transfer_amount)

			print("Input Hopper: %d %s (facility → %s)" % [
				transfer_amount,
				input_product,
				destination_machine_id
			])


func _process_output_depot(facility_id: String, depot: Dictionary) -> void:
	"""Output depot collects materials from connected machines and sends to facility inventory"""

	var depot_id = depot.get("id", "")

	# Get all connections TO this output depot
	var connections = FactoryManager.get_connections_to(facility_id, depot_id)
	if connections.is_empty():
		return

	# Collect from each connected machine
	for conn in connections:
		var source_machine_id = conn.get("from", "")
		if source_machine_id.is_empty():
			continue

		# Get machine's inventory
		var machine_inventory = get_machine_inventory(facility_id, source_machine_id)
		if machine_inventory.is_empty():
			continue

		# Transfer all products from machine to facility
		for product in machine_inventory.keys():
			var quantity = machine_inventory[product]
			if quantity <= 0:
				continue

			# Transfer up to io_node_transfer_amount
			var transfer_amount = min(io_node_transfer_amount, quantity)
			if _remove_from_machine_inventory(facility_id, source_machine_id, product, transfer_amount):
				_add_to_inventory(facility_id, product, transfer_amount)

				print("Output Depot: %d %s (%s → facility)" % [
					transfer_amount,
					product,
					source_machine_id
				])

				# Check if product should be auto-sold
				if auto_sell_enabled and _should_auto_sell(product):
					_sell_product(facility_id, product, transfer_amount)


func _process_market_outlet(facility_id: String, outlet: Dictionary) -> void:
	"""Market outlet collects materials from connected machines and sells them for reduced profit"""

	var outlet_id = outlet.get("id", "")

	# Get all connections TO this market outlet
	var connections = FactoryManager.get_connections_to(facility_id, outlet_id)
	if connections.is_empty():
		return

	# Collect from each connected machine and sell immediately
	for conn in connections:
		var source_machine_id = conn.get("from", "")
		if source_machine_id.is_empty():
			continue

		# Get machine's inventory
		var machine_inventory = get_machine_inventory(facility_id, source_machine_id)
		if machine_inventory.is_empty():
			continue

		# Sell all products from machine inventory
		for product in machine_inventory.keys():
			var quantity = machine_inventory[product]
			if quantity <= 0:
				continue

			# Transfer up to io_node_transfer_amount
			var transfer_amount = min(io_node_transfer_amount, quantity)
			if _remove_from_machine_inventory(facility_id, source_machine_id, product, transfer_amount):
				# Get dynamic market price + research bonus
				var base_price = _get_product_price(product)
				var price_mult = _get_price_multiplier(product)
				var price_per_unit = int(base_price * price_mult)
				var revenue = price_per_unit * transfer_amount

				# Track revenue for this facility
				_track_revenue(facility_id, revenue)

				# Add money and emit product_sold signal for market tracking
				EconomyManager.earn_money(GameManager.CORP_SINGLE, revenue, "Market Outlet: %s" % product)
				EventBus.product_sold.emit(product, transfer_amount, revenue)

				print("Market Outlet: Sold %d %s for $%d ($%d/unit)" % [
					transfer_amount,
					product,
					revenue,
					price_per_unit
				])


func _process_storage_buffer(facility_id: String, storage: Dictionary) -> void:
	"""Storage buffer actively transfers stored products to connected machines (like Market Outlet)"""

	var storage_id = storage.get("id", "")

	# Get storage's inventory
	var storage_inventory = get_machine_inventory(facility_id, storage_id)
	if storage_inventory.is_empty():
		return

	# Get all connections FROM this storage
	var connections = FactoryManager.get_connections_from(facility_id, storage_id)
	if connections.is_empty():
		return

	# Try to transfer each product to connected machines
	for product in storage_inventory.keys():
		var available_quantity = storage_inventory[product]
		if available_quantity <= 0:
			continue

		# Try each connection
		for conn in connections:
			var destination_machine_id = conn.get("to", "")
			if destination_machine_id.is_empty():
				continue

			var destination_machine = FactoryManager.get_machine(facility_id, destination_machine_id)
			if destination_machine.is_empty():
				continue

			# Transfer up to io_node_transfer_amount
			var transfer_amount = min(io_node_transfer_amount, available_quantity)

			if _remove_from_machine_inventory(facility_id, storage_id, product, transfer_amount):
				_add_to_machine_inventory(facility_id, destination_machine_id, product, transfer_amount)

				print("Storage Buffer: Transferred %d %s (%s → %s)" % [
					transfer_amount,
					product,
					storage_id,
					destination_machine_id
				])

				# Update available quantity for next transfer
				available_quantity -= transfer_amount
				if available_quantity <= 0:
					break


# ========================================
# SELLING
# ========================================

func _should_auto_sell(product: String) -> bool:
	"""Check if a product should be auto-sold (is it a final product?)"""
	# Final products that can be sold directly
	var final_products = [
		"ale",
		"packaged_ale",  # Premium packaged ale
		"lager",
		"wheat_beer",
		"whiskey",
		"vodka",
		"premium_whiskey",
		"aged_spirit"
	]
	return product in final_products


func _sell_product(facility_id: String, product: String, quantity: int) -> void:
	"""Sell product to market"""

	# Remove from inventory
	if not _remove_from_inventory(facility_id, product, quantity):
		return

	# Calculate revenue using dynamic market pricing + research bonus
	var base_price = _get_product_price(product)
	var price_mult = _get_price_multiplier(product)
	var price_per_unit = int(base_price * price_mult)
	var revenue = price_per_unit * quantity

	# Track revenue for this facility
	_track_revenue(facility_id, revenue)

	# Add money (EconomyManager.sell_product emits product_sold signal)
	EconomyManager.sell_product(product, quantity, price_per_unit)

	var bonus_info = ""
	if price_mult != 1.0:
		bonus_info = " [+%.0f%% research bonus]" % ((price_mult - 1.0) * 100)
	print("Sold %d %s for $%d ($%d/unit)%s" % [quantity, product, revenue, price_per_unit, bonus_info])


# ========================================
# FACILITY EVENT HANDLERS
# ========================================

func _on_facility_placed(facility: Dictionary) -> void:
	"""Handle facility placement"""
	var facility_id = facility.id

	# Initialize production timer with research bonus
	var facility_def = DataManager.get_facility_data(facility.type)
	var production_data = facility_def.get("production", {})
	var base_cycle_time = production_data.get("cycle_time", 5.0)

	# Apply cycle time multiplier from research
	var cycle_mult = _get_cycle_time_multiplier(facility.type)
	var cycle_time = base_cycle_time * cycle_mult

	production_timers[facility_id] = cycle_time
	production_outputs[facility_id] = {}


func _on_facility_removed(facility_id: String) -> void:
	"""Handle facility removal"""
	production_timers.erase(facility_id)
	production_outputs.erase(facility_id)
	# Clean up per-field state for the generic farm_field.
	field_crop_types.erase(facility_id)
	_field_idle_reason.erase(facility_id)


func _on_facility_constructed(facility_id: String) -> void:
	"""Handle facility construction completion"""
	# Start production automatically
	WorldManager.start_production(facility_id)
	print("Production started for facility: %s" % facility_id)


func _on_production_changed(facility_id: String, is_producing: bool) -> void:
	"""Handle production state change"""
	if is_producing:
		print("Production enabled for: %s" % facility_id)
	else:
		print("Production disabled for: %s" % facility_id)


func _on_machine_placed(factory_id: String, machine_data: Dictionary) -> void:
	"""Handle machine placement - initialize production timer and inventory"""
	var machine_id = machine_data.get("id", "")
	if machine_id.is_empty():
		return

	var machine_type = machine_data.get("type", "")
	var machine_def = DataManager.get_machine_data(machine_type)
	if machine_def.is_empty():
		return

	var machine_key = "%s:%s" % [factory_id, machine_id]

	# Initialize machine inventory (all machines have inventory)
	machine_inventories[machine_key] = {}

	# Initialize production timer if machine produces
	var production_data = machine_def.get("production", {})
	if not production_data.is_empty():
		var cycle_time = production_data.get("cycle_time", 5.0)
		machine_timers[machine_key] = cycle_time

		print("Machine production initialized: %s in facility %s (cycle: %.1fs)" % [
			machine_def.get("name", machine_type),
			factory_id,
			cycle_time
		])
	else:
		print("Machine placed: %s in facility %s (non-producing)" % [
			machine_def.get("name", machine_type),
			factory_id
		])


func _on_machine_removed(factory_id: String, machine_id: String) -> void:
	"""Handle machine removal - cleanup timers and inventory"""
	var machine_key = "%s:%s" % [factory_id, machine_id]

	machine_timers.erase(machine_key)
	machine_inventories.erase(machine_key)

	print("Machine removed: %s from facility %s" % [machine_id, factory_id])


# ========================================
# STATISTICS
# ========================================

func get_total_produced(product: String) -> int:
	"""Get total quantity of a product across all facilities"""
	var total = 0
	for facility_id in production_outputs:
		total += production_outputs[facility_id].get(product, 0)
	return total


func get_active_production_count() -> int:
	"""Get number of facilities actively producing"""
	var count = 0
	for facility_id in production_timers:
		var facility = WorldManager.get_facility(facility_id)
		if facility.get("production_active", false):
			count += 1
	return count


func _track_production(facility_id: String, product: String, quantity: int) -> void:
	"""Track production for a facility"""
	if not facility_stats.has(facility_id):
		facility_stats[facility_id] = {
			"total_produced": {},
			"total_consumed": {},
			"total_revenue": 0
		}

	if not facility_stats[facility_id]["total_produced"].has(product):
		facility_stats[facility_id]["total_produced"][product] = 0

	facility_stats[facility_id]["total_produced"][product] += quantity


func _track_consumption(facility_id: String, product: String, quantity: int) -> void:
	"""Track consumption for a facility"""
	if not facility_stats.has(facility_id):
		facility_stats[facility_id] = {
			"total_produced": {},
			"total_consumed": {},
			"total_revenue": 0
		}

	if not facility_stats[facility_id]["total_consumed"].has(product):
		facility_stats[facility_id]["total_consumed"][product] = 0

	facility_stats[facility_id]["total_consumed"][product] += quantity


func _track_revenue(facility_id: String, revenue: int) -> void:
	"""Track revenue for a facility"""
	if not facility_stats.has(facility_id):
		facility_stats[facility_id] = {
			"total_produced": {},
			"total_consumed": {},
			"total_revenue": 0
		}

	facility_stats[facility_id]["total_revenue"] += revenue


func get_facility_stats(facility_id: String) -> Dictionary:
	"""Get production statistics for a facility"""
	return facility_stats.get(facility_id, {
		"total_produced": {},
		"total_consumed": {},
		"total_revenue": 0
	})


func get_production_rate(facility_id: String) -> String:
	"""Get production rate for a facility (e.g., '8 malt/5s') with research bonuses"""
	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return "N/A"

	var facility_def = DataManager.get_facility_data(facility.type)
	var production_data = facility_def.get("production", {})

	var output = production_data.get("output", "")
	var base_quantity = production_data.get("quantity", 0)
	var base_cycle_time = production_data.get("cycle_time", 5.0)

	if output.is_empty() or base_quantity == 0:
		return "N/A"

	# Apply research bonuses
	var yield_mult = _get_yield_multiplier(facility.type)
	var cycle_mult = _get_cycle_time_multiplier(facility.type)

	var quantity = int(base_quantity * yield_mult)
	var cycle_time = base_cycle_time * cycle_mult

	return "%d %s/%.1fs" % [quantity, output, cycle_time]


func get_production_progress(facility_id: String) -> float:
	"""Get production progress for a facility (0.0 to 1.0)"""
	if not production_timers.has(facility_id):
		return 0.0

	var facility = WorldManager.get_facility(facility_id)
	if facility.is_empty():
		return 0.0

	var facility_def = DataManager.get_facility_data(facility.type)
	var production_data = facility_def.get("production", {})
	var cycle_time = production_data.get("cycle_time", 5.0)

	var time_remaining = production_timers[facility_id]
	var time_elapsed = cycle_time - time_remaining

	# Calculate progress (0.0 = just started, 1.0 = complete)
	var progress = time_elapsed / cycle_time
	return clampf(progress, 0.0, 1.0)


func synchronize_production_timers(facility_ids: Array[String]) -> void:
	"""Synchronize production timers for multiple facilities (for batch placement)"""
	if facility_ids.is_empty():
		return

	# Get the cycle time from the first facility (all should be same type)
	var first_facility = WorldManager.get_facility(facility_ids[0])
	if first_facility.is_empty():
		return

	var facility_def = DataManager.get_facility_data(first_facility.type)
	var production_data = facility_def.get("production", {})
	var cycle_time = production_data.get("cycle_time", 5.0)

	# Set all facilities to the same timer value (start of cycle)
	for facility_id in facility_ids:
		if production_timers.has(facility_id):
			production_timers[facility_id] = cycle_time

	print("Synchronized %d production timers to %.1fs" % [facility_ids.size(), cycle_time])


# ========================================
# DEBUG
# ========================================

func print_production_status() -> void:
	"""Debug: Print production status"""
	print("=== Production Status ===")
	print("Active producers: %d" % get_active_production_count())
	print("Total facilities: %d" % production_timers.size())

	for facility_id in production_timers:
		var facility = WorldManager.get_facility(facility_id)
		if facility.is_empty():
			continue

		var timer = production_timers[facility_id]
		var inventory = production_outputs.get(facility_id, {})

		print("  %s: timer=%.1fs, inventory=%s" % [
			facility.type,
			timer,
			str(inventory)
		])
