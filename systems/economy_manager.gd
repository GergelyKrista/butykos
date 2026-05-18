extends Node

## EconomyManager - Currency, expenses, revenue tracking
##
## Manages player money, transactions, and basic economic simulation.
## Singleton autoload for global access.

# ========================================
# SIGNALS
# ========================================

signal maintenance_paid(total_cost: int, details: Array)
signal maintenance_failed(facility_id: String, shortfall: int)
signal facility_disabled(facility_id: String, reason: String)

# ========================================
# CONSTANTS
# ========================================

const STARTING_MONEY = 100000
const MAINTENANCE_INTERVAL: float = 30.0  # Pay maintenance every 30 seconds (represents 1 "day")
const MACHINE_MAINTENANCE_MULTIPLIER: float = 0.1  # Machines cost 10% of their price per maintenance cycle

# ========================================
# STATE
# ========================================

var money: int = STARTING_MONEY
var total_earned: int = 0
var total_spent: int = 0

# Transaction history (limited to last 100 transactions)
var transaction_history: Array = []
const MAX_HISTORY = 100

# Maintenance tracking
var _maintenance_timer: float = 0.0
var disabled_facilities: Dictionary = {}  # facility_id -> true (disabled due to no funds)
var total_maintenance_paid: int = 0
var last_maintenance_cost: int = 0

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("EconomyManager initialized")
	print("Starting money: $%d" % money)

	# Connect to save/load events
	EventBus.before_save.connect(_on_before_save)
	EventBus.after_load.connect(_on_after_load)


func _process(delta: float) -> void:
	# Update maintenance timer
	_maintenance_timer += delta
	if _maintenance_timer >= MAINTENANCE_INTERVAL:
		_maintenance_timer = 0.0
		_collect_maintenance()


# ========================================
# MONEY MANAGEMENT
# ========================================

func earn_money(corp_id: String, amount: int, reason: String = "") -> void:
	"""Add money to the shared wallet. corp_id prefigures per-corp wallets (v4); ignored in v1."""
	if amount <= 0:
		push_warning("Trying to add non-positive amount: %d" % amount)
		return

	money += amount
	total_earned += amount

	_record_transaction(amount, reason, "income")
	EventBus.money_changed.emit(money, amount)

	print("Money added: +$%d (%s) | Total: $%d" % [amount, reason, money])


func spend_money(corp_id: String, amount: int, reason: String = "") -> bool:
	"""Subtract money from the shared wallet. Returns false if insufficient funds.
	corp_id prefigures per-corp wallets (v4); ignored in v1."""
	var check: Dictionary = can_spend_money(corp_id, amount)
	if not check.ok:
		push_warning("spend_money rejected: %s" % check.reason)
		return false

	money -= amount
	total_spent += amount

	_record_transaction(-amount, reason, "expense")
	EventBus.money_changed.emit(money, -amount)

	print("Money spent: -$%d (%s) | Remaining: $%d" % [amount, reason, money])
	return true


func can_spend_money(corp_id: String, amount: int) -> Dictionary:
	"""Predicate for spend_money. v1: single shared wallet; corp_id ignored.
	v4 (per-corp wallets): reads money_by_corp[corp_id]."""
	if amount <= 0:
		return { "ok": false, "reason": "Amount must be positive" }
	if money < amount:
		return { "ok": false, "reason": "Insufficient funds: need $%d, have $%d" % [amount, money] }
	return { "ok": true, "reason": "" }


func can_afford(amount: int) -> bool:
	"""Deprecated wrapper kept for UI preview call sites that are rewired in sub-commit C.
	TODO(sub-commit-C): delete after all can_afford call sites in scenes/ are removed."""
	return can_spend_money(GameManager.CORP_SINGLE, amount).ok


func add_money(amount: int, reason: String = "") -> void:
	"""Deprecated wrapper kept for UI call sites rewired in sub-commit C.
	TODO(sub-commit-C): delete after factory_interior.gd:682 and world_map.gd:1071 are rewired."""
	earn_money(GameManager.CORP_SINGLE, amount, reason)


func subtract_money(amount: int, reason: String = "") -> bool:
	"""Deprecated wrapper kept for UI call sites rewired in sub-commit C.
	TODO(sub-commit-C): delete after factory_interior.gd:288, world_map.gd:1207, :1322, :1658 are rewired."""
	return spend_money(GameManager.CORP_SINGLE, amount, reason)


func set_money(amount: int) -> void:
	"""Set money directly (used for loading saves or cheats)"""
	var delta = amount - money
	money = amount
	EventBus.money_changed.emit(money, delta)


func reset_economy() -> void:
	"""Reset economy to initial state"""
	print("Resetting economy...")
	money = STARTING_MONEY
	total_earned = 0
	total_spent = 0
	transaction_history.clear()

	# Reset maintenance state
	_maintenance_timer = 0.0
	disabled_facilities.clear()
	total_maintenance_paid = 0
	last_maintenance_cost = 0

	EventBus.money_changed.emit(money, 0)


# ========================================
# FACILITY TRANSACTIONS
# ========================================

func _purchase_facility(corp_id: String, facility_id: String) -> bool:
	"""Private helper: charge for a facility. Called only from ACTION_PLACE_FACILITY handler.
	Not pipe-exposed as a standalone action — always part of a composite."""
	var facility_def: Dictionary = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		push_error("Unknown facility: %s" % facility_id)
		return false

	var cost: int = facility_def.get("cost", 0)
	var facility_name: String = facility_def.get("name", facility_id)

	return spend_money(corp_id, cost, "Built %s" % facility_name)


func purchase_facility(facility_id: String) -> bool:
	"""Deprecated wrapper kept for UI call sites rewired in sub-commit C.
	TODO(sub-commit-C): delete after world_map.gd:440 and :577 are rewired to submit_action."""
	return _purchase_facility(GameManager.CORP_SINGLE, facility_id)


func _refund_facility(corp_id: String, facility_id: String, refund_percent: float = 0.5) -> void:
	"""Private helper: refund money when removing a facility. Called only from demolish handlers.
	Not pipe-exposed as a standalone action — always part of a composite."""
	var facility_def: Dictionary = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		return

	var cost: int = facility_def.get("cost", 0)
	var refund: int = int(cost * refund_percent)
	var facility_name: String = facility_def.get("name", facility_id)

	earn_money(corp_id, refund, "Removed %s" % facility_name)


# ========================================
# PRODUCTION REVENUE
# ========================================

func sell_product(product_id: String, quantity: int, price_per_unit: int) -> void:
	"""Record revenue from selling products. Internal — called from production tick, not user input."""
	var revenue: int = quantity * price_per_unit
	earn_money(GameManager.CORP_SINGLE, revenue, "Sold %d %s" % [quantity, product_id])
	EventBus.product_sold.emit(product_id, quantity, revenue)


# ========================================
# MAINTENANCE & OPERATING COSTS
# ========================================

func _collect_maintenance() -> void:
	"""Collect maintenance from all facilities and machines"""
	var total_cost = 0
	var details: Array = []
	var facilities_to_disable: Array = []

	# Get all placed facilities
	var facilities = WorldManager.get_all_facilities()

	for facility in facilities:
		var facility_id = facility.id
		var facility_def = DataManager.get_facility_data(facility.type)
		if facility_def.is_empty():
			continue

		var facility_cost = facility_def.get("maintenance_cost", 0)
		var facility_name = facility_def.get("name", facility.type)

		# Calculate machine maintenance for this facility
		var machine_cost = _calculate_machine_maintenance(facility_id)

		var total_facility_cost = facility_cost + machine_cost

		if total_facility_cost > 0:
			details.append({
				"facility_id": facility_id,
				"facility_name": facility_name,
				"facility_cost": facility_cost,
				"machine_cost": machine_cost,
				"total": total_facility_cost
			})
			total_cost += total_facility_cost

	# Check if we can afford maintenance
	if total_cost > 0:
		if money >= total_cost:
			# Pay all maintenance
			spend_money(GameManager.CORP_SINGLE, total_cost, "Maintenance (%d facilities)" % details.size())
			total_maintenance_paid += total_cost
			last_maintenance_cost = total_cost

			# Re-enable any previously disabled facilities
			for facility_id in disabled_facilities.keys():
				_enable_facility(facility_id)
			disabled_facilities.clear()

			maintenance_paid.emit(total_cost, details)
			print("Maintenance paid: $%d for %d facilities" % [total_cost, details.size()])
		else:
			# Can't afford - disable facilities starting from most expensive
			_handle_maintenance_shortfall(total_cost, details)

	last_maintenance_cost = total_cost


func _calculate_machine_maintenance(facility_id: String) -> int:
	"""Calculate total machine maintenance cost for a facility"""
	var total = 0

	# Get machines in this facility from FactoryManager
	var machines = FactoryManager.get_machines_in_facility(facility_id)

	for machine_id in machines:
		var machine = machines[machine_id]
		var machine_def = DataManager.get_machine_data(machine.type)
		if machine_def.is_empty():
			continue

		var machine_cost = machine_def.get("cost", 0)
		# Machine maintenance is a percentage of its cost
		var maintenance = int(machine_cost * MACHINE_MAINTENANCE_MULTIPLIER)
		total += maintenance

	return total


func _handle_maintenance_shortfall(total_cost: int, details: Array) -> void:
	"""Handle when player can't afford full maintenance"""
	var shortfall = total_cost - money
	print("Maintenance shortfall: need $%d, have $%d (short $%d)" % [total_cost, money, shortfall])

	# Sort by total cost descending (disable most expensive first)
	details.sort_custom(func(a, b): return a.total > b.total)

	var remaining_to_disable = shortfall
	var facilities_disabled_this_cycle: Array = []

	for detail in details:
		if remaining_to_disable <= 0:
			break

		var facility_id = detail.facility_id
		if not disabled_facilities.has(facility_id):
			_disable_facility(facility_id, "Cannot afford maintenance")
			facilities_disabled_this_cycle.append(facility_id)
			remaining_to_disable -= detail.total
			maintenance_failed.emit(facility_id, detail.total)

	# Pay whatever we can
	var affordable = total_cost - shortfall + remaining_to_disable
	if affordable > 0 and money >= affordable:
		spend_money(GameManager.CORP_SINGLE, affordable, "Partial maintenance")
		total_maintenance_paid += affordable

	if facilities_disabled_this_cycle.size() > 0:
		print("Disabled %d facilities due to maintenance shortfall" % facilities_disabled_this_cycle.size())


func _disable_facility(facility_id: String, reason: String) -> void:
	"""Disable a facility due to maintenance issues"""
	disabled_facilities[facility_id] = true

	# Stop production for this facility
	WorldManager.stop_production(facility_id)

	facility_disabled.emit(facility_id, reason)
	print("Facility disabled: %s (%s)" % [facility_id, reason])


func _enable_facility(facility_id: String) -> void:
	"""Re-enable a previously disabled facility"""
	if disabled_facilities.has(facility_id):
		disabled_facilities.erase(facility_id)

		# Restart production
		WorldManager.start_production(facility_id)
		print("Facility re-enabled: %s" % facility_id)


func is_facility_disabled(facility_id: String) -> bool:
	"""Check if a facility is disabled due to maintenance"""
	return disabled_facilities.has(facility_id)


func get_maintenance_summary() -> Dictionary:
	"""Get maintenance cost summary"""
	var facilities = WorldManager.get_all_facilities()
	var total_facility_cost = 0
	var total_machine_cost = 0
	var facility_count = 0

	for facility in facilities:
		var facility_id = facility.id
		var facility_def = DataManager.get_facility_data(facility.type)
		if facility_def.is_empty():
			continue

		var cost = facility_def.get("maintenance_cost", 0)
		total_facility_cost += cost
		total_machine_cost += _calculate_machine_maintenance(facility_id)
		facility_count += 1

	return {
		"facility_cost": total_facility_cost,
		"machine_cost": total_machine_cost,
		"total_cost": total_facility_cost + total_machine_cost,
		"facility_count": facility_count,
		"interval_seconds": MAINTENANCE_INTERVAL,
		"disabled_count": disabled_facilities.size(),
		"last_paid": last_maintenance_cost,
		"total_paid": total_maintenance_paid
	}


func pay_maintenance(facility_id: String) -> bool:
	"""Pay maintenance cost for a single facility. Returns false if can't afford."""
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		return false

	var cost = facility_def.get("maintenance_cost", 0)
	if cost == 0:
		return true

	var facility_name: String = facility_def.get("name", facility_id)
	return spend_money(GameManager.CORP_SINGLE, cost, "Maintenance: %s" % facility_name)


# ========================================
# STATISTICS
# ========================================

func get_net_worth() -> int:
	"""Calculate net worth (money + value of assets)"""
	# TODO: Add value of facilities and inventory
	return money


func get_profit() -> int:
	"""Get total profit (earned - spent)"""
	return total_earned - total_spent


func get_balance_summary() -> Dictionary:
	"""Get financial summary"""
	return {
		"money": money,
		"total_earned": total_earned,
		"total_spent": total_spent,
		"profit": get_profit(),
		"net_worth": get_net_worth()
	}


# ========================================
# TRANSACTION HISTORY
# ========================================

func _record_transaction(amount: int, reason: String, type: String) -> void:
	"""Record a transaction in history"""
	var transaction = {
		"amount": amount,
		"reason": reason,
		"type": type,  # "income" or "expense"
		"date": GameManager.current_date.duplicate(),
		"balance_after": money
	}

	transaction_history.append(transaction)

	# Limit history size
	if transaction_history.size() > MAX_HISTORY:
		transaction_history.pop_front()


func get_recent_transactions(count: int = 10) -> Array:
	"""Get recent transactions"""
	var start_index = max(0, transaction_history.size() - count)
	var result: Array = []
	for i in range(start_index, transaction_history.size()):
		result.append(transaction_history[i])
	return result


# ========================================
# SAVE/LOAD
# ========================================

func _on_before_save() -> void:
	"""Prepare data for saving"""
	# Data will be gathered by SaveManager
	pass


func _on_after_load() -> void:
	"""Restore state after loading"""
	# TODO: Restore economy state from save data
	pass


# ========================================
# DEBUG
# ========================================

func print_balance() -> void:
	"""Debug: Print current balance"""
	print("=== Economy Status ===")
	print("Money: $%d" % money)
	print("Total earned: $%d" % total_earned)
	print("Total spent: $%d" % total_spent)
	print("Profit: $%d" % get_profit())
	print("Transactions: %d" % transaction_history.size())


func cheat_add_money(amount: int) -> void:
	"""Debug: Add money without recording it properly"""
	money += amount
	EventBus.money_changed.emit(money, amount)
	print("Cheat: Added $%d" % amount)
