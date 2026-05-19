extends Node

## MarketManager - Dynamic market pricing and contracts
##
## Manages dynamic product pricing based on supply/demand, price fluctuations,
## market trends, and delivery contracts.
## Singleton autoload for global access.

# ========================================
# SIGNALS
# ========================================

signal prices_updated
signal contract_added(contract: Dictionary)
signal contract_completed(contract: Dictionary)
signal contract_expired(contract: Dictionary)

# ========================================
# CONSTANTS
# ========================================

const PRICE_UPDATE_INTERVAL: float = 10.0  # Update prices every 10 seconds
const MAX_PRICE_VARIANCE: float = 0.3  # ±30% from base price
const SUPPLY_DECAY_RATE: float = 0.1  # How fast supply pressure decays
const TREND_CHANGE_CHANCE: float = 0.2  # Chance to change trend direction
const MAX_CONTRACTS: int = 5  # Max active contracts
const CONTRACT_GENERATION_INTERVAL: float = 60.0  # Generate new contract every 60 seconds

# ========================================
# BASE PRICES (starting values)
# ========================================

var base_prices: Dictionary = {
	# Raw materials (lowest value)
	"barley": 5,
	"wheat": 5,
	"corn": 6,
	"water": 1,
	"hops": 12,
	"grapes": 10,

	# Processed materials (medium value)
	"malt": 15,
	"mash": 20,
	"fermented_wash": 40,
	"raw_spirit": 50,

	# Finished products (full value)
	"ale": 100,
	"packaged_ale": 150,
	"lager": 120,
	"wheat_beer": 110,
	"whiskey": 200,
	"vodka": 180,
	"premium_whiskey": 300,
	"aged_spirit": 250,

	# Premium products (added via research)
	"wine": 160,
	"stout": 130,
	"porter": 125,
	"reserve_25_year": 500,
	"limited_edition": 400
}

# ========================================
# STATE
# ========================================

# Current market prices (fluctuate over time)
var current_prices: Dictionary = {}

# Price multipliers for each product (1.0 = base price)
var price_multipliers: Dictionary = {}

# Supply pressure: how much player has sold recently (drives prices down)
var supply_pressure: Dictionary = {}

# Market trends: -1 (falling), 0 (stable), 1 (rising)
var market_trends: Dictionary = {}

# Price history for each product (last 10 prices)
var price_history: Dictionary = {}
const MAX_PRICE_HISTORY: int = 10

# Active delivery contracts
var active_contracts: Array[Dictionary] = []
var _next_contract_id: int = 1

# Timers
var _price_update_timer: float = 0.0
var _contract_generation_timer: float = 30.0  # Start with a contract soon

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("MarketManager initialized")
	_initialize_market()

	# Connect to save/load events
	EventBus.before_save.connect(_on_before_save)
	EventBus.after_load.connect(_on_after_load)

	# Connect to product sales to track supply
	EventBus.product_sold.connect(_on_product_sold)


func _initialize_market() -> void:
	"""Initialize market with base prices and neutral trends"""
	for product in base_prices:
		current_prices[product] = base_prices[product]
		price_multipliers[product] = 1.0
		supply_pressure[product] = 0.0
		market_trends[product] = 0  # Start stable
		price_history[product] = [base_prices[product]]

	print("Market initialized with %d products" % base_prices.size())


# ========================================
# PROCESS
# ========================================

func _process(delta: float) -> void:
	# Update prices periodically
	_price_update_timer += delta
	if _price_update_timer >= PRICE_UPDATE_INTERVAL:
		_price_update_timer = 0.0
		_update_prices()

	# Generate contracts periodically
	_contract_generation_timer += delta
	if _contract_generation_timer >= CONTRACT_GENERATION_INTERVAL:
		_contract_generation_timer = 0.0
		_try_generate_contract()

	# Check contract expirations
	_check_contract_expirations()

	# Decay supply pressure over time
	_decay_supply_pressure(delta)


# ========================================
# PRICE MANAGEMENT
# ========================================

func get_price(product: String) -> int:
	"""Get current market price for a product"""
	if current_prices.has(product):
		return current_prices[product]

	# Unknown product, return base price or default
	return base_prices.get(product, 100)


func get_base_price(product: String) -> int:
	"""Get base (non-fluctuating) price for a product"""
	return base_prices.get(product, 100)


func get_price_trend(product: String) -> int:
	"""Get price trend for a product: -1 (falling), 0 (stable), 1 (rising)"""
	return market_trends.get(product, 0)


func get_price_change_percent(product: String) -> float:
	"""Get how much the price has changed from base (as percentage)"""
	var base = base_prices.get(product, 100)
	var current = current_prices.get(product, base)
	return ((current - base) / float(base)) * 100.0


func get_all_prices() -> Dictionary:
	"""Get all current prices"""
	return current_prices.duplicate()


func _update_prices() -> void:
	"""Update all market prices based on trends and supply"""
	for product in base_prices:
		var base = base_prices[product]
		var multiplier = price_multipliers[product]
		var trend = market_trends[product]
		var supply = supply_pressure.get(product, 0.0)

		# Apply trend movement
		var trend_change = randf_range(0.01, 0.05) * trend

		# Apply supply pressure (more supply = lower prices)
		var supply_effect = -supply * 0.1

		# Random market noise
		var noise = randf_range(-0.02, 0.02)

		# Update multiplier
		multiplier += trend_change + supply_effect + noise

		# Clamp to valid range
		multiplier = clampf(multiplier, 1.0 - MAX_PRICE_VARIANCE, 1.0 + MAX_PRICE_VARIANCE)
		price_multipliers[product] = multiplier

		# Calculate new price
		var new_price = int(base * multiplier)
		new_price = max(1, new_price)  # Minimum price of 1

		# Record history
		_record_price_history(product, new_price)

		current_prices[product] = new_price

		# Possibly change trend direction
		if randf() < TREND_CHANGE_CHANCE:
			_change_trend(product)

	prices_updated.emit()


func _change_trend(product: String) -> void:
	"""Randomly change the market trend for a product"""
	var current_trend = market_trends[product]
	var multiplier = price_multipliers[product]

	# Bias towards returning to base price when far from it
	var pull_to_center = 0.0
	if multiplier > 1.1:
		pull_to_center = -0.3  # More likely to fall
	elif multiplier < 0.9:
		pull_to_center = 0.3  # More likely to rise

	var roll = randf() + pull_to_center

	if roll < 0.33:
		market_trends[product] = -1  # Falling
	elif roll < 0.66:
		market_trends[product] = 0  # Stable
	else:
		market_trends[product] = 1  # Rising


func _record_price_history(product: String, price: int) -> void:
	"""Record price in history"""
	if not price_history.has(product):
		price_history[product] = []

	price_history[product].append(price)

	# Limit history size
	if price_history[product].size() > MAX_PRICE_HISTORY:
		price_history[product].pop_front()


func _decay_supply_pressure(delta: float) -> void:
	"""Gradually reduce supply pressure over time"""
	for product in supply_pressure:
		supply_pressure[product] = maxf(0.0, supply_pressure[product] - SUPPLY_DECAY_RATE * delta)


# ========================================
# SUPPLY TRACKING
# ========================================

func _on_product_sold(product: String, quantity: int, _revenue: int) -> void:
	"""Track when products are sold to affect supply pressure"""
	if not supply_pressure.has(product):
		supply_pressure[product] = 0.0

	# Add supply pressure based on quantity sold
	var pressure_increase = quantity * 0.01  # Scale based on quantity
	supply_pressure[product] = minf(1.0, supply_pressure[product] + pressure_increase)


func add_supply_pressure(product: String, amount: float) -> void:
	"""Manually add supply pressure (for testing or events)"""
	if not supply_pressure.has(product):
		supply_pressure[product] = 0.0
	supply_pressure[product] = minf(1.0, supply_pressure[product] + amount)


# ========================================
# CONTRACT SYSTEM
# ========================================

func _try_generate_contract() -> void:
	"""Try to generate a new delivery contract"""
	if active_contracts.size() >= MAX_CONTRACTS:
		return

	var contract = _generate_random_contract()
	if contract:
		active_contracts.append(contract)
		contract_added.emit(contract)
		print("New contract: Deliver %d %s for $%d bonus (deadline: %d days)" % [
			contract.quantity,
			contract.product,
			contract.reward,
			contract.deadline_days
		])


func _generate_random_contract() -> Dictionary:
	"""Generate a random delivery contract"""
	# Only create contracts for sellable products
	var sellable_products = ["ale", "packaged_ale", "lager", "wheat_beer",
							 "whiskey", "vodka", "premium_whiskey", "aged_spirit",
							 "raw_spirit", "malt"]

	var product = sellable_products[randi() % sellable_products.size()]
	var base_price = base_prices.get(product, 100)

	# Contract parameters scale with product value
	var quantity = randi_range(10, 50) * (1 + int(base_price / 100))
	var deadline_days = randi_range(7, 30)

	# Reward is base value + 20-50% bonus
	var base_value = quantity * base_price
	var bonus_percent = randf_range(0.2, 0.5)
	var reward = int(base_value * (1.0 + bonus_percent))

	return {
		"id": _next_contract_id,
		"corp_id": GameManager.CORP_BUSINESS,    # Phase 8 step 1: contracts are Business-owned in v1.
		"product": product,
		"quantity": quantity,
		"quantity_delivered": 0,
		"reward": reward,
		"deadline_days": deadline_days,
		"created_date": GameManager.current_date.duplicate(),
		"status": "active"  # active, completed, expired
	}


func get_active_contracts() -> Array[Dictionary]:
	"""Get all active contracts"""
	return active_contracts.filter(func(c): return c.status == "active")


func can_deliver_to_contract(corp_id: String, contract_id: int, product: String, quantity: int) -> Dictionary:
	"""Predicate for ACTION_DELIVER_TO_CONTRACT."""
	for contract in active_contracts:
		if contract.id == contract_id:
			if contract.status != "active":
				return { "ok": false, "reason": "Contract is not active (status: %s)" % contract.status }
			if contract.product != product:
				return { "ok": false, "reason": "Contract is for %s, not %s" % [contract.product, product] }
			if quantity <= 0:
				return { "ok": false, "reason": "Quantity must be positive" }
			return { "ok": true, "reason": "" }
	return { "ok": false, "reason": "Contract not found" }


func can_cancel_contract(corp_id: String, contract_id: int) -> Dictionary:
	"""Predicate for ACTION_CANCEL_CONTRACT."""
	for contract in active_contracts:
		if contract.id == contract_id:
			if contract.status != "active":
				return { "ok": false, "reason": "Contract is not active" }
			return { "ok": true, "reason": "" }
	return { "ok": false, "reason": "Contract not found" }


func deliver_to_contract(contract_id: int, product: String, quantity: int) -> int:
	"""Deliver products to a contract. Returns quantity actually delivered."""
	for contract in active_contracts:
		if contract.id == contract_id and contract.status == "active":
			if contract.product != product:
				return 0

			var needed = contract.quantity - contract.quantity_delivered
			var to_deliver = min(quantity, needed)

			contract.quantity_delivered += to_deliver

			# Check if contract is complete
			if contract.quantity_delivered >= contract.quantity:
				_complete_contract(contract)

			return to_deliver

	return 0


func _complete_contract(contract: Dictionary) -> void:
	"""Complete a contract and pay reward"""
	contract.status = "completed"

	# Pay reward
	EconomyManager.earn_money(GameManager.CORP_SINGLE, contract.reward, "Contract: %d %s" % [contract.quantity, contract.product])

	contract_completed.emit(contract)
	print("Contract completed! Reward: $%d" % contract.reward)


func _check_contract_expirations() -> void:
	"""Check for expired contracts"""
	var current_day = GameManager.current_date.get("day", 1)

	for contract in active_contracts:
		if contract.status != "active":
			continue

		var created_day = contract.created_date.get("day", 1)
		var days_elapsed = current_day - created_day

		if days_elapsed > contract.deadline_days:
			contract.status = "expired"
			contract_expired.emit(contract)
			print("Contract expired: %d %s" % [contract.quantity, contract.product])


func cancel_contract(contract_id: int) -> bool:
	"""Cancel a contract (no penalty for now)"""
	for contract in active_contracts:
		if contract.id == contract_id and contract.status == "active":
			contract.status = "cancelled"
			return true
	return false


# ========================================
# SAVE/LOAD
# ========================================

func _on_before_save() -> void:
	"""Prepare data for saving"""
	pass


func _on_after_load() -> void:
	"""Restore state after loading"""
	pass


func get_save_data() -> Dictionary:
	"""Get market data for saving"""
	return {
		"current_prices": current_prices.duplicate(),
		"price_multipliers": price_multipliers.duplicate(),
		"supply_pressure": supply_pressure.duplicate(),
		"market_trends": market_trends.duplicate(),
		"active_contracts": active_contracts.duplicate(true),
		"next_contract_id": _next_contract_id
	}


func load_save_data(data: Dictionary) -> void:
	"""Load market data from save"""
	if data.has("current_prices"):
		current_prices = data.current_prices
	if data.has("price_multipliers"):
		price_multipliers = data.price_multipliers
	if data.has("supply_pressure"):
		supply_pressure = data.supply_pressure
	if data.has("market_trends"):
		market_trends = data.market_trends
	if data.has("active_contracts"):
		active_contracts.assign(data.active_contracts)
	if data.has("next_contract_id"):
		_next_contract_id = data.next_contract_id


# ========================================
# DEBUG
# ========================================

func print_market_status() -> void:
	"""Debug: Print current market status"""
	print("=== Market Status ===")
	for product in current_prices:
		var base = base_prices[product]
		var current = current_prices[product]
		var trend = market_trends[product]
		var trend_str = "↑" if trend > 0 else ("↓" if trend < 0 else "→")
		var change = get_price_change_percent(product)
		print("  %s: $%d (base: $%d, %+.1f%%) %s" % [product, current, base, change, trend_str])

	print("\nActive Contracts: %d" % get_active_contracts().size())
	for contract in get_active_contracts():
		print("  - %d/%d %s for $%d (%d days left)" % [
			contract.quantity_delivered,
			contract.quantity,
			contract.product,
			contract.reward,
			contract.deadline_days
		])
