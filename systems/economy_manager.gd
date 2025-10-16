extends Node

## EconomyManager - Currency, expenses, revenue tracking
##
## Manages player money, transactions, and basic economic simulation.
## Singleton autoload for global access.

# ========================================
# CONSTANTS
# ========================================

const STARTING_MONEY = 5000

# ========================================
# STATE
# ========================================

var money: int = STARTING_MONEY
var total_earned: int = 0
var total_spent: int = 0

# Transaction history (limited to last 100 transactions)
var transaction_history: Array[Dictionary] = []
const MAX_HISTORY = 100

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("EconomyManager initialized")
	print("Starting money: $%d" % money)

	# Connect to save/load events
	EventBus.before_save.connect(_on_before_save)
	EventBus.after_load.connect(_on_after_load)


# ========================================
# MONEY MANAGEMENT
# ========================================

func add_money(amount: int, reason: String = "") -> void:
	"""Add money to player account"""
	if amount <= 0:
		push_warning("Trying to add non-positive amount: %d" % amount)
		return

	money += amount
	total_earned += amount

	_record_transaction(amount, reason, "income")
	EventBus.money_changed.emit(money, amount)

	print("Money added: +$%d (%s) | Total: $%d" % [amount, reason, money])


func subtract_money(amount: int, reason: String = "") -> bool:
	"""Subtract money from player account. Returns false if insufficient funds."""
	if amount <= 0:
		push_warning("Trying to subtract non-positive amount: %d" % amount)
		return false

	if money < amount:
		push_warning("Insufficient funds: need $%d, have $%d" % [amount, money])
		return false

	money -= amount
	total_spent += amount

	_record_transaction(-amount, reason, "expense")
	EventBus.money_changed.emit(money, -amount)

	print("Money spent: -$%d (%s) | Remaining: $%d" % [amount, reason, money])
	return true


func can_afford(amount: int) -> bool:
	"""Check if player has enough money"""
	return money >= amount


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
	EventBus.money_changed.emit(money, 0)


# ========================================
# FACILITY TRANSACTIONS
# ========================================

func purchase_facility(facility_id: String) -> bool:
	"""Purchase a facility. Returns true if successful."""
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		push_error("Unknown facility: %s" % facility_id)
		return false

	var cost = facility_def.get("cost", 0)
	var name = facility_def.get("name", facility_id)

	if subtract_money(cost, "Built %s" % name):
		return true

	return false


func refund_facility(facility_id: String, refund_percent: float = 0.5) -> void:
	"""Refund money when removing a facility (default 50%)"""
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		return

	var cost = facility_def.get("cost", 0)
	var refund = int(cost * refund_percent)
	var name = facility_def.get("name", facility_id)

	add_money(refund, "Removed %s" % name)


# ========================================
# PRODUCTION REVENUE
# ========================================

func sell_product(product_id: String, quantity: int, price_per_unit: int) -> void:
	"""Record revenue from selling products"""
	var revenue = quantity * price_per_unit
	add_money(revenue, "Sold %d %s" % [quantity, product_id])
	EventBus.product_sold.emit(product_id, quantity, revenue)


# ========================================
# MAINTENANCE & OPERATING COSTS
# ========================================

func pay_maintenance(facility_id: String) -> bool:
	"""Pay maintenance cost for a facility. Returns false if can't afford."""
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		return false

	var cost = facility_def.get("maintenance_cost", 0)
	if cost == 0:
		return true

	var name = facility_def.get("name", facility_id)
	return subtract_money(cost, "Maintenance: %s" % name)


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


func get_recent_transactions(count: int = 10) -> Array[Dictionary]:
	"""Get recent transactions"""
	var start_index = max(0, transaction_history.size() - count)
	var result: Array[Dictionary] = []
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
