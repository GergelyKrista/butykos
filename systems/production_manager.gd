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

# Dictionary of machine inventories: { "facility_id:machine_id": {product_id: quantity} }
# Machines now have their own inventory instead of using facility inventory
var machine_inventories: Dictionary = {}

# ========================================
# CONFIGURATION
# ========================================

var auto_sell_enabled: bool = true  # Auto-sell products when produced
var default_sell_price: int = 100   # Default price per product unit

# Input/Output node transfer settings
var io_node_transfer_amount: int = 10  # How much to transfer per cycle
var io_node_timer: float = 0.0  # Timer for periodic IO node operations
const IO_NODE_CYCLE_TIME: float = 2.0  # How often IO nodes transfer (seconds)

# Product pricing for market outlets (bootstrap income)
var product_prices: Dictionary = {
	# Raw materials (lowest value)
	"barley": 5,
	"wheat": 5,
	"corn": 5,
	"water": 1,

	# Processed materials (medium value)
	"malt": 15,
	"mash": 20,
	"fermented_wash": 40,
	"raw_spirit": 50,

	# Finished products (full value)
	"ale": 100,
	"packaged_ale": 150,  # Premium packaged version
	"lager": 120,
	"wheat_beer": 110,
	"whiskey": 200,
	"vodka": 180,
	"premium_whiskey": 300,
	"aged_spirit": 250
}

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
				# Get price for this product (use default if not in pricing table)
				var price_per_unit = product_prices.get(product, default_sell_price)
				var revenue = price_per_unit * transfer_amount

				# Add money directly (no inventory needed)
				EconomyManager.add_money(revenue, "Market Outlet: %s" % product)

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

	# Calculate revenue using product-specific pricing
	var price_per_unit = product_prices.get(product, default_sell_price)
	var revenue = price_per_unit * quantity

	# Add money
	EconomyManager.sell_product(product, quantity, price_per_unit)

	print("Sold %d %s for $%d ($%d/unit)" % [quantity, product, revenue, price_per_unit])


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
