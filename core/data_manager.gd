extends Node

## DataManager - Load and cache game data from JSON files
##
## Singleton that loads facility, machine, product, and recipe definitions.
## Data is cached after first load for performance.

# ========================================
# CACHED DATA
# ========================================

var facilities: Dictionary = {}
var products: Dictionary = {}
var recipes: Dictionary = {}
var machines: Dictionary = {}

# ========================================
# DATA PATHS
# ========================================

const DATA_DIR = "res://data/"
const FACILITIES_FILE = DATA_DIR + "facilities.json"
const PRODUCTS_FILE = DATA_DIR + "products.json"
const RECIPES_FILE = DATA_DIR + "recipes.json"
const MACHINES_FILE = DATA_DIR + "machines.json"

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("DataManager initialized")
	load_all_data()


func load_all_data() -> void:
	"""Load all game data from JSON files"""
	facilities = _load_json_file(FACILITIES_FILE)
	products = _load_json_file(PRODUCTS_FILE)
	recipes = _load_json_file(RECIPES_FILE)
	machines = _load_json_file(MACHINES_FILE)

	print("Data loaded: %d facilities, %d products, %d recipes, %d machines" % [
		facilities.size(),
		products.size(),
		recipes.size(),
		machines.size()
	])


# ========================================
# DATA ACCESS
# ========================================

func get_facility_data(facility_id: String) -> Dictionary:
	"""Get facility definition by ID"""
	return facilities.get(facility_id, {})


func get_product_data(product_id: String) -> Dictionary:
	"""Get product definition by ID"""
	return products.get(product_id, {})


func get_recipe_data(recipe_id: String) -> Dictionary:
	"""Get recipe definition by ID"""
	return recipes.get(recipe_id, {})


func get_machine_data(machine_id: String) -> Dictionary:
	"""Get machine definition by ID"""
	return machines.get(machine_id, {})


func get_all_facilities() -> Dictionary:
	"""Get all facility definitions"""
	return facilities.duplicate()


func get_facilities_by_category(category: String) -> Dictionary:
	"""Get all facilities of a specific category"""
	var result = {}
	for facility_id in facilities:
		var facility = facilities[facility_id]
		if facility.get("category", "") == category:
			result[facility_id] = facility
	return result


# ========================================
# PRIVATE METHODS
# ========================================

func _load_json_file(file_path: String) -> Dictionary:
	"""Load and parse a JSON file"""

	if not FileAccess.file_exists(file_path):
		push_warning("Data file not found: %s" % file_path)
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open data file: %s" % file_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_error("Failed to parse JSON file %s: %s" % [file_path, json.get_error_message()])
		return {}

	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("JSON root must be a dictionary: %s" % file_path)
		return {}

	return json.data


# ========================================
# VALIDATION
# ========================================

func validate_facility_requirements(facility_id: String, player_money: int, built_facilities: Dictionary) -> Dictionary:
	"""Check if player meets requirements to build a facility. Returns {can_build: bool, reason: String}"""

	var facility_def = get_facility_data(facility_id)
	if facility_def.is_empty():
		return {"can_build": false, "reason": "Unknown facility type"}

	# Check money
	var cost = facility_def.get("cost", 0)
	if player_money < cost:
		return {"can_build": false, "reason": "Insufficient funds"}

	# Check unlock requirements
	var requirements = facility_def.get("unlock_requirements", {})

	# Check money requirement
	if requirements.has("money") and player_money < requirements.money:
		return {"can_build": false, "reason": "Unlock requirement: $%d" % requirements.money}

	# Check facility requirements
	if requirements.has("facilities_built"):
		for required_facility in requirements.facilities_built:
			var required_count = requirements.facilities_built[required_facility]
			var actual_count = built_facilities.get(required_facility, 0)
			if actual_count < required_count:
				return {
					"can_build": false,
					"reason": "Requires %d %s" % [required_count, get_facility_data(required_facility).get("name", required_facility)]
				}

	return {"can_build": true, "reason": ""}
