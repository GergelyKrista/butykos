extends Node
## ResearchManager - Handles technology research and unlocks
## Satisfactory-style tier system: Tier 1 unlocked by default, higher tiers require product deliveries

signal research_completed(tech_id: String)
signal research_tree_loaded
signal tier_unlocked(tier: int)
signal tier_progress_updated(tier: int, product: String, delivered: int, required: int)

# Research tree data loaded from JSON
var research_tree: Dictionary = {}

# Set of unlocked technology IDs
var unlocked_techs: Dictionary = {}  # tech_id -> true

# Current highest unlocked tier (starts at 1)
var current_tier: int = 1

# Deliveries toward next tier unlock
var tier_deliveries: Dictionary = {}  # product_id -> amount delivered

# Dev mode - bypasses tier requirements
var dev_mode: bool = false

# Tier unlock requirements (product deliveries needed)
const TIER_REQUIREMENTS: Dictionary = {
	2: {"barley": 500, "wheat": 500, "malt": 100},
	3: {"ale": 200, "malt": 500, "raw_spirit": 100},
	4: {"packaged_ale": 300, "whiskey": 100, "mash": 500},
	5: {"whiskey": 500, "packaged_ale": 500, "vodka": 200}
}

# Branch definitions for UI grouping
const BRANCHES: Array[String] = [
	"agriculture",
	"grain_processing",
	"brewing",
	"distillation",
	"aging",
	"packaging",
	"logistics",
	"commerce"
]

const BRANCH_NAMES: Dictionary = {
	"agriculture": "Agriculture",
	"grain_processing": "Grain Processing",
	"brewing": "Brewing",
	"distillation": "Distillation",
	"aging": "Aging & Maturation",
	"packaging": "Packaging & Quality",
	"logistics": "Logistics",
	"commerce": "Commerce"
}

func _ready() -> void:
	_load_research_tree()
	# Connect to product sold signal to track deliveries
	EventBus.product_sold.connect(_on_product_sold)

func _load_research_tree() -> void:
	var file = FileAccess.open("res://data/research_tree.json", FileAccess.READ)
	if file:
		var json_text = file.get_as_text()
		file.close()
		var json = JSON.new()
		var error = json.parse(json_text)
		if error == OK:
			research_tree = json.data
			print("ResearchManager: Loaded %d technologies" % research_tree.size())
			research_tree_loaded.emit()
		else:
			push_error("ResearchManager: Failed to parse research_tree.json - %s" % json.get_error_message())
	else:
		push_error("ResearchManager: Could not open research_tree.json")

# ========================================
# TIER SYSTEM
# ========================================

## Get current unlocked tier
func get_current_tier() -> int:
	return current_tier

## Check if a tier is unlocked
func is_tier_unlocked(tier: int) -> bool:
	return tier <= current_tier

## Get requirements for a specific tier
func get_tier_requirements(tier: int) -> Dictionary:
	return TIER_REQUIREMENTS.get(tier, {})

## Get current delivery progress for next tier
func get_tier_progress() -> Dictionary:
	var next_tier = current_tier + 1
	if next_tier > 5:
		return {}  # Max tier reached

	var requirements = TIER_REQUIREMENTS.get(next_tier, {})
	var progress: Dictionary = {}

	for product in requirements:
		progress[product] = {
			"delivered": tier_deliveries.get(product, 0),
			"required": requirements[product]
		}

	return progress

## Check if next tier can be unlocked
func can_unlock_next_tier() -> bool:
	var next_tier = current_tier + 1
	if next_tier > 5:
		return false

	var requirements = TIER_REQUIREMENTS.get(next_tier, {})
	for product in requirements:
		var delivered = tier_deliveries.get(product, 0)
		if delivered < requirements[product]:
			return false

	return true

## Attempt to unlock the next tier
func try_unlock_next_tier() -> bool:
	if not can_unlock_next_tier():
		return false

	current_tier += 1
	print("ResearchManager: Tier %d unlocked!" % current_tier)
	tier_unlocked.emit(current_tier)

	# Clear deliveries for the tier we just unlocked (keep for next tier)
	# Actually, let's keep them - deliveries accumulate

	return true

## Handle product sales - track deliveries for tier progression
func _on_product_sold(product_type: String, quantity: int, _revenue: int) -> void:
	# Only track if we haven't maxed out tiers
	if current_tier >= 5:
		return

	var next_tier = current_tier + 1
	var requirements = TIER_REQUIREMENTS.get(next_tier, {})

	# Check if this product is needed for next tier
	if product_type in requirements:
		var previous = tier_deliveries.get(product_type, 0)
		tier_deliveries[product_type] = previous + quantity

		var required = requirements[product_type]
		var delivered = tier_deliveries[product_type]

		print("ResearchManager: Delivered %d %s (%d/%d for Tier %d)" % [quantity, product_type, delivered, required, next_tier])
		tier_progress_updated.emit(next_tier, product_type, delivered, required)

		# Auto-check if tier can be unlocked
		if can_unlock_next_tier():
			try_unlock_next_tier()

## Manually deliver products (for UI button or testing)
func deliver_product(product_type: String, quantity: int) -> bool:
	# Check if player has the product in any facility
	var total_available = 0
	for facility_id in ProductionManager.production_outputs:
		var inventory = ProductionManager.production_outputs[facility_id]
		total_available += inventory.get(product_type, 0)

	if total_available < quantity:
		return false

	# Remove from facilities (take from first available)
	var remaining = quantity
	for facility_id in ProductionManager.production_outputs:
		if remaining <= 0:
			break
		var inventory = ProductionManager.production_outputs[facility_id]
		var available = inventory.get(product_type, 0)
		var take = mini(available, remaining)
		if take > 0:
			ProductionManager.remove_item_from_facility(facility_id, product_type, take)
			remaining -= take

	# Track delivery
	var previous = tier_deliveries.get(product_type, 0)
	tier_deliveries[product_type] = previous + quantity

	var next_tier = current_tier + 1
	var requirements = TIER_REQUIREMENTS.get(next_tier, {})
	if product_type in requirements:
		tier_progress_updated.emit(next_tier, product_type, tier_deliveries[product_type], requirements[product_type])

	# Check for tier unlock
	if can_unlock_next_tier():
		try_unlock_next_tier()

	return true

# ========================================
# TECHNOLOGY RESEARCH
# ========================================

## Check if a technology is unlocked
func is_unlocked(tech_id: String) -> bool:
	return unlocked_techs.has(tech_id)

## Check if a technology can be researched (tier unlocked, prerequisites met, has funds)
func can_research(tech_id: String) -> bool:
	if is_unlocked(tech_id):
		return false

	var tech = research_tree.get(tech_id)
	if not tech:
		return false

	# Check tier requirement (skip in dev mode)
	var tech_tier = tech.get("tier", 1)
	if not dev_mode and tech_tier > current_tier:
		return false

	# Check prerequisites
	for prereq in tech.get("prerequisites", []):
		if not is_unlocked(prereq):
			return false

	# Dev mode bypasses money requirements
	if dev_mode:
		return true

	# Check funds
	var cost = tech.get("cost", 0)
	return EconomyManager.money >= cost

## Get list of missing prerequisites for a tech
func get_missing_prerequisites(tech_id: String) -> Array:
	var missing: Array = []
	var tech = research_tree.get(tech_id)
	if not tech:
		return missing

	for prereq in tech.get("prerequisites", []):
		if not is_unlocked(prereq):
			missing.append(prereq)

	return missing

## Check if tech is locked due to tier (not prerequisites)
func is_tier_locked(tech_id: String) -> bool:
	# Dev mode bypasses tier locks
	if dev_mode:
		return false

	var tech = research_tree.get(tech_id)
	if not tech:
		return true

	var tech_tier = tech.get("tier", 1)
	return tech_tier > current_tier


## Set dev mode (bypasses tier requirements for testing)
func set_dev_mode(enabled: bool) -> void:
	dev_mode = enabled
	print("ResearchManager: Dev mode %s" % ("enabled" if enabled else "disabled"))

## Attempt to research a technology
func research(tech_id: String) -> bool:
	if not can_research(tech_id):
		return false

	var tech = research_tree.get(tech_id)
	var cost = tech.get("cost", 0)

	# Deduct cost (skip in dev mode)
	if not dev_mode:
		EconomyManager.subtract_money(cost, "Research: %s" % tech.get("name", tech_id))

	# Unlock tech
	unlocked_techs[tech_id] = true

	print("ResearchManager: Unlocked %s%s" % [tech.get("name", tech_id), " (DEV MODE)" if dev_mode else ""])
	research_completed.emit(tech_id)
	EventBus.research_completed.emit(tech_id)

	return true

## Get technology data by ID
func get_tech(tech_id: String) -> Dictionary:
	return research_tree.get(tech_id, {})

## Get tech name (for display)
func get_tech_name(tech_id: String) -> String:
	var tech = research_tree.get(tech_id, {})
	return tech.get("name", tech_id)

## Get all technologies in a branch
func get_branch_techs(branch: String) -> Array:
	var techs: Array = []
	for tech_id in research_tree:
		var tech = research_tree[tech_id]
		if tech.get("branch") == branch:
			techs.append(tech)

	# Sort by tier
	techs.sort_custom(func(a, b): return a.get("tier", 0) < b.get("tier", 0))
	return techs

## Get all technologies in a tier
func get_tier_techs(tier: int) -> Array:
	var techs: Array = []
	for tech_id in research_tree:
		var tech = research_tree[tech_id]
		if tech.get("tier") == tier:
			techs.append(tech)
	return techs

## Get count of unlocked techs
func get_unlocked_count() -> int:
	return unlocked_techs.size()

## Get total tech count
func get_total_count() -> int:
	return research_tree.size()

## Get count of unlocked techs in a branch
func get_branch_unlocked_count(branch: String) -> int:
	var count = 0
	for tech_id in unlocked_techs:
		var tech = research_tree.get(tech_id, {})
		if tech.get("branch") == branch:
			count += 1
	return count

## Get count of total techs in a branch
func get_branch_total_count(branch: String) -> int:
	var count = 0
	for tech_id in research_tree:
		var tech = research_tree[tech_id]
		if tech.get("branch") == branch:
			count += 1
	return count

## Check if building upgrade is unlocked
func is_building_upgrade_unlocked(upgrade_id: String) -> bool:
	for tech_id in unlocked_techs:
		var tech = research_tree.get(tech_id, {})
		var unlocks = tech.get("unlocks", {})
		var building_upgrades = unlocks.get("building_upgrades", [])
		if upgrade_id in building_upgrades:
			return true
	return false


## Check if a facility is unlocked (based on research requirements in facilities.json)
func is_facility_unlocked(facility_id: String) -> bool:
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		return false

	var unlock_reqs = facility_def.get("unlock_requirements", {})
	var required_research = unlock_reqs.get("research", [])

	# No research requirement = always unlocked
	if required_research.is_empty():
		return true

	# Check if all required research is unlocked
	for tech_id in required_research:
		if not is_unlocked(tech_id):
			return false

	return true


## Get missing research requirements for a facility
func get_facility_missing_research(facility_id: String) -> Array:
	var missing: Array = []
	var facility_def = DataManager.get_facility_data(facility_id)
	if facility_def.is_empty():
		return missing

	var unlock_reqs = facility_def.get("unlock_requirements", {})
	var required_research = unlock_reqs.get("research", [])

	for tech_id in required_research:
		if not is_unlocked(tech_id):
			missing.append(tech_id)

	return missing


## Get all active bonuses from unlocked research
func get_active_bonuses() -> Array:
	var bonuses: Array = []
	for tech_id in unlocked_techs:
		var tech = research_tree.get(tech_id, {})
		var unlocks = tech.get("unlocks", {})
		var tech_bonuses = unlocks.get("bonuses", [])
		for bonus in tech_bonuses:
			bonus["source"] = tech_id
			bonuses.append(bonus)
	return bonuses

## Get specific bonus value (e.g., price multiplier for all products)
func get_bonus_multiplier(bonus_type: String, target: String) -> float:
	var multiplier = 1.0
	for tech_id in unlocked_techs:
		var tech = research_tree.get(tech_id, {})
		var unlocks = tech.get("unlocks", {})
		var bonuses = unlocks.get("bonuses", [])
		for bonus in bonuses:
			if bonus.get("type") == bonus_type:
				var bonus_target = bonus.get("target", "")
				if bonus_target == target or bonus_target == "all":
					var value = bonus.get("value", 1.0)
					if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
						multiplier *= value
	return multiplier

# ========================================
# SAVE/LOAD
# ========================================

func get_save_data() -> Dictionary:
	return {
		"unlocked_techs": unlocked_techs.keys(),
		"current_tier": current_tier,
		"tier_deliveries": tier_deliveries
	}

func load_save_data(data: Dictionary) -> void:
	unlocked_techs.clear()
	var techs = data.get("unlocked_techs", [])
	for tech_id in techs:
		unlocked_techs[tech_id] = true

	current_tier = data.get("current_tier", 1)
	tier_deliveries = data.get("tier_deliveries", {})

	print("ResearchManager: Loaded %d unlocked technologies, Tier %d" % [unlocked_techs.size(), current_tier])

func clear_data() -> void:
	unlocked_techs.clear()
	current_tier = 1
	tier_deliveries.clear()
