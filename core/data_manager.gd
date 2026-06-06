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
var roads: Dictionary = {}

# ========================================
# DATA PATHS
# ========================================

const DATA_DIR = "res://data/"
const FACILITIES_FILE = DATA_DIR + "facilities.json"
const PRODUCTS_FILE = DATA_DIR + "products.json"
const RECIPES_FILE = DATA_DIR + "recipes.json"
const MACHINES_FILE = DATA_DIR + "machines.json"
const ROADS_FILE = DATA_DIR + "roads.json"

# Per-product color palette. Single source of truth for the logistics network
# view (socket + connection lines), the factory interior (connection lines +
# hopper-config popup icons), and any future UI that needs to color-code
# products. Picked to read at a glance: barley golden, hops vibrant green,
# water blue, finished beers warm gold. Unknown products fall back to a
# hash-derived hue in `get_product_color`.
const PRODUCT_COLORS: Dictionary = {
	# Raw crops
	"barley": Color("#d4a017"),
	"hops": Color("#5fb84a"),
	"wheat": Color("#deb054"),
	"corn": Color("#f1c40f"),
	"grapes": Color("#722f7a"),
	"water": Color("#3498db"),
	"bottles": Color("#a0d8e8"),
	# Intermediates (general)
	"malt": Color("#a05a2c"),
	"mash": Color("#7d5a3a"),
	"fermented_wash": Color("#9c6b3a"),
	"raw_spirit": Color("#dcdcdc"),
	# Intermediates (lager chain, slice 3.x)
	"grist": Color("#c8a060"),
	"wort": Color("#d49850"),
	"boiled_wort": Color("#b87a3a"),
	"cleaned_wort": Color("#e0a460"),
	"cooled_wort": Color("#dca858"),
	"green_beer": Color("#c8d650"),
	"matured_beer": Color("#d8b850"),
	"finished_beer": Color("#e8c060"),
	# Beers
	"ale": Color("#c1853b"),
	"packaged_ale": Color("#c1853b"),
	"lager": Color("#e8c060"),
	"wheat_beer": Color("#f0d080"),
	"stout": Color("#3a2418"),
	"porter": Color("#4a2e1d"),
	# Spirits / aged
	"whiskey": Color("#8b4513"),
	"vodka": Color("#e8e8e8"),
	"premium_whiskey": Color("#a0522d"),
	"aged_spirit": Color("#9c6b3a"),
	"wine": Color("#722f37"),
	"reserve_25_year": Color("#5c2818"),
	"limited_edition": Color("#8a4a78"),
}

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
	roads = _load_json_file(ROADS_FILE)

	print("Data loaded: %d facilities, %d products, %d recipes, %d machines, %d roads" % [
		facilities.size(),
		products.size(),
		recipes.size(),
		machines.size(),
		roads.size()
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


func get_road_data(road_id: String) -> Dictionary:
	"""Get road definition by ID"""
	return roads.get(road_id, {})


func get_product_color(product_id: String) -> Color:
	"""Stable per-product color. Hits PRODUCT_COLORS for curated products;
	unknown products fall through to a hash-derived hue so new content
	doesn't crash here — when it ships, add the proper color to the map."""
	if product_id.is_empty():
		return Color(0.5, 0.5, 0.5)
	if PRODUCT_COLORS.has(product_id):
		return PRODUCT_COLORS[product_id]
	var h: float = float(absi(product_id.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.92)


func get_all_roads() -> Dictionary:
	"""Get all road definitions"""
	return roads.duplicate()


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


func get_all_machines() -> Dictionary:
	"""Get all machine definitions"""
	return machines.duplicate()


func get_machines_by_category(category: String) -> Dictionary:
	"""Get all machines of a specific category"""
	var result = {}
	for machine_id in machines:
		var machine = machines[machine_id]
		if machine.get("category", "") == category:
			result[machine_id] = machine
	return result


func get_machines_for_facility(facility_type: String) -> Dictionary:
	"""Get all machines that can be placed in a specific facility type"""
	var result = {}
	for machine_id in machines:
		var machine = machines[machine_id]
		var required_facilities = machine.get("requires_facility", [])
		if required_facilities.is_empty() or facility_type in required_facilities:
			result[machine_id] = machine
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
