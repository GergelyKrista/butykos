extends Node

## ProductionManager - Simple production simulation
##
## Handles production cycles for facilities. Each facility produces
## resources at regular intervals based on its definition.

# ========================================
# STATE
# ========================================

# Facility production
# Dictionary of production timers: { facility_id: time_remaining }
var production_timers: Dictionary = {}

# Dictionary of production outputs: { facility_id: {product_id: quantity} }
var production_outputs: Dictionary = {}

# Machine production
# Dictionary of machine production timers: { "facility_id:machine_id": time_remaining }
var machine_timers: Dictionary = {}

# Dictionary of machine outputs: { "facility_id:machine_id": {product_id: quantity} }
var machine_outputs: Dictionary = {}

# ========================================
# CONFIGURATION
# ========================================

var auto_sell_enabled: bool = true  # Auto-sell products when produced
var default_sell_price: int = 100   # Default price per product unit

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

	var production_data = facility_def.get("production", {})
	if production_data.is_empty():
		return

	var output_product = production_data.get("output", "")
	var output_quantity = production_data.get("quantity", 0)
	var cycle_time = production_data.get("cycle_time", 5.0)

	if output_product.is_empty() or output_quantity == 0:
		return

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
			# Reset timer to try again
			production_timers[facility_id] = cycle_time
			return

		# Consume inputs
		_remove_from_inventory(facility_id, input_product, input_quantity)
		print("Consumed %d %s for production" % [input_quantity, input_product])

	# Add output to inventory
	_add_to_inventory(facility_id, output_product, output_quantity)

	# Reset timer
	production_timers[facility_id] = cycle_time

	print("Production complete: %s produced %d %s" % [
		facility_def.get("name", facility.type),
		output_quantity,
		output_product
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

	# Check if machine requires inputs
	var input_product = production_data.get("input", "")
	var input_quantity = production_data.get("input_quantity", 0)

	if not input_product.is_empty() and input_quantity > 0:
		# Check facility inventory for input materials
		var current_input = get_inventory_item(facility_id, input_product)
		if current_input < input_quantity:
			# Not enough inputs, can't produce
			print("Machine production blocked: %s needs %d %s from facility (has %d)" % [
				machine_def.get("name", machine.type),
				input_quantity,
				input_product,
				current_input
			])
			# Reset timer to try again
			var machine_key = "%s:%s" % [facility_id, machine_id]
			machine_timers[machine_key] = cycle_time
			return

		# Consume inputs from facility inventory
		_remove_from_inventory(facility_id, input_product, input_quantity)
		print("Machine consumed %d %s from facility inventory" % [input_quantity, input_product])

	# Add output to facility inventory (machines feed facility)
	_add_to_inventory(facility_id, output_product, output_quantity)

	# Reset timer
	var machine_key = "%s:%s" % [facility_id, machine_id]
	machine_timers[machine_key] = cycle_time

	print("Machine production complete: %s produced %d %s" % [
		machine_def.get("name", machine.type),
		output_quantity,
		output_product
	])

	# Auto-sell if enabled and product is final
	if auto_sell_enabled and _should_auto_sell(output_product):
		_sell_product(facility_id, output_product, output_quantity)


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
# SELLING
# ========================================

func _should_auto_sell(product: String) -> bool:
	"""Check if a product should be auto-sold (is it a final product?)"""
	# Final products that can be sold directly
	var final_products = ["ale", "lager", "wheat_beer", "whiskey", "vodka", "premium_whiskey"]
	return product in final_products


func _sell_product(facility_id: String, product: String, quantity: int) -> void:
	"""Sell product to market"""

	# Remove from inventory
	if not _remove_from_inventory(facility_id, product, quantity):
		return

	# Calculate revenue
	var price_per_unit = default_sell_price
	var revenue = price_per_unit * quantity

	# Add money
	EconomyManager.sell_product(product, quantity, price_per_unit)

	print("Sold %d %s for $%d" % [quantity, product, revenue])


# ========================================
# FACILITY EVENT HANDLERS
# ========================================

func _on_facility_placed(facility: Dictionary) -> void:
	"""Handle facility placement"""
	var facility_id = facility.id

	# Initialize production timer
	var facility_def = DataManager.get_facility_data(facility.type)
	var production_data = facility_def.get("production", {})
	var cycle_time = production_data.get("cycle_time", 5.0)

	production_timers[facility_id] = cycle_time
	production_outputs[facility_id] = {}


func _on_facility_removed(facility_id: String) -> void:
	"""Handle facility removal"""
	production_timers.erase(facility_id)
	production_outputs.erase(facility_id)


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
	"""Handle machine placement - initialize production timer"""
	var machine_id = machine_data.get("id", "")
	if machine_id.is_empty():
		return

	var machine_type = machine_data.get("type", "")
	var machine_def = DataManager.get_machine_data(machine_type)
	if machine_def.is_empty():
		return

	var production_data = machine_def.get("production", {})
	if production_data.is_empty():
		# This machine doesn't produce anything (e.g., conveyor belt, input hopper)
		return

	var cycle_time = production_data.get("cycle_time", 5.0)
	var machine_key = "%s:%s" % [factory_id, machine_id]

	# Initialize production timer
	machine_timers[machine_key] = cycle_time
	machine_outputs[machine_key] = {}

	print("Machine production initialized: %s in facility %s (cycle: %.1fs)" % [
		machine_def.get("name", machine_type),
		factory_id,
		cycle_time
	])


func _on_machine_removed(factory_id: String, machine_id: String) -> void:
	"""Handle machine removal - cleanup timers and outputs"""
	var machine_key = "%s:%s" % [factory_id, machine_id]

	machine_timers.erase(machine_key)
	machine_outputs.erase(machine_key)

	print("Machine production removed: %s from facility %s" % [machine_id, factory_id])


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
