extends Node

## GameManager - Main game loop, state transitions, and global coordination
##
## Singleton that manages high-level game state, time progression,
## and coordinates between different game systems.

enum GameState {
	MENU,           ## Main menu state
	WORLD_MAP,      ## Playing on world map layer
	FACTORY_VIEW,   ## Inside factory interior
	PAUSED,         ## Game is paused
	LOADING,        ## Loading save or transitioning
}

# ========================================
# CORP OWNERSHIP CONSTANTS
# ========================================
#
# Valid corp_id values across all owned entities. See:
#   - design_docs/2026-05-07_technical_architecture.html §3
#
# Step 1 of Phase 8: every owned entity carries `corp_id` but nothing
# reads it for gating yet. All entities default to CORP_SINGLE during
# this phase. The action pipe (step 3) and predicates (step 4) come later.

const CORP_AGRI: String = "agri"
const CORP_INDUSTRIAL: String = "industrial"
const CORP_LOGISTICS: String = "logistics"
const CORP_BUSINESS: String = "business"
const CORP_SHARED: String = "shared"        # cross-corp infra (roads, utilities, shared research)
const CORP_SINGLE: String = "single"        # legacy / no-op default during step 1; replaced by real corp once action pipe lands

const VALID_CORP_IDS: Array[String] = [
	CORP_AGRI,
	CORP_INDUSTRIAL,
	CORP_LOGISTICS,
	CORP_BUSINESS,
	CORP_SHARED,
	CORP_SINGLE,
]

# ========================================
# ACTION PIPE — ACTION TYPE CONSTANTS
# ========================================
#
# Every state mutation initiated by UI (or by any code outside the manager that
# owns the data) goes through GameManager.submit_action(corp_id, action_type, payload).
# These constants ARE the network protocol. Renaming the underlying string later
# is a protocol break — pick names now and own them.
#
# Naming: snake_case, verb-first imperative. EventBus signals are past-tense
# (facility_placed); these are present-tense intents (place_facility).
#
# When adding a new mutator to any manager, add the constant here in the same
# commit and wire its dispatch in submit_action's match block.

# World / facilities
const ACTION_PLACE_FACILITY: String = "place_facility"
const ACTION_PLACE_FIELD: String = "place_field"               # composite: place + complete + register
const ACTION_DEMOLISH_FACILITY: String = "demolish_facility"
const ACTION_PLACE_ROAD: String = "place_road"                 # composite: charge + place
const ACTION_REMOVE_ROAD: String = "remove_road"               # reserved; no UI driver in v1

# Factory interiors
const ACTION_PLACE_MACHINE: String = "place_machine"
const ACTION_DEMOLISH_MACHINE: String = "demolish_machine"
const ACTION_CREATE_MACHINE_CONNECTION: String = "create_machine_connection"
const ACTION_REMOVE_MACHINE_CONNECTION: String = "remove_machine_connection"

# Logistics
const ACTION_CREATE_LOGISTICS_CONNECTION: String = "create_logistics_connection"
const ACTION_REMOVE_LOGISTICS_CONNECTION: String = "remove_logistics_connection"
const ACTION_TOGGLE_CONNECTION_ACTIVE: String = "toggle_connection_active"

# Economy (internal-use — see plan §0.4)
const ACTION_SPEND_MONEY: String = "spend_money"
const ACTION_EARN_MONEY: String = "earn_money"
const ACTION_CHEAT_ADD_MONEY: String = "cheat_add_money"        # debug

# Market / contracts
const ACTION_DELIVER_TO_CONTRACT: String = "deliver_to_contract"
const ACTION_CANCEL_CONTRACT: String = "cancel_contract"

# Research
const ACTION_RESEARCH_TECH: String = "research_tech"

# Production / farmhouse
const ACTION_SET_FARMHOUSE_CROP: String = "set_farmhouse_crop"

# Set of all valid action types — used by submit_action for validation
const VALID_ACTION_TYPES: Array[String] = [
	ACTION_PLACE_FACILITY,
	ACTION_PLACE_FIELD,
	ACTION_DEMOLISH_FACILITY,
	ACTION_PLACE_ROAD,
	ACTION_REMOVE_ROAD,
	ACTION_PLACE_MACHINE,
	ACTION_DEMOLISH_MACHINE,
	ACTION_CREATE_MACHINE_CONNECTION,
	ACTION_REMOVE_MACHINE_CONNECTION,
	ACTION_CREATE_LOGISTICS_CONNECTION,
	ACTION_REMOVE_LOGISTICS_CONNECTION,
	ACTION_TOGGLE_CONNECTION_ACTIVE,
	ACTION_SPEND_MONEY,
	ACTION_EARN_MONEY,
	ACTION_CHEAT_ADD_MONEY,
	ACTION_DELIVER_TO_CONTRACT,
	ACTION_CANCEL_CONTRACT,
	ACTION_RESEARCH_TECH,
	ACTION_SET_FARMHOUSE_CROP,
]

# Required payload keys per action_type. Add an entry when adding a new action.
const _ACTION_PAYLOAD_SCHEMA: Dictionary = {
	ACTION_PLACE_FACILITY:               ["facility_type", "grid_pos", "size"],
	ACTION_PLACE_FIELD:                  ["field_type", "grid_pos", "farmhouse_id"],
	ACTION_DEMOLISH_FACILITY:            ["facility_id"],
	ACTION_PLACE_ROAD:                   ["grid_pos", "road_type"],
	ACTION_REMOVE_ROAD:                  ["grid_pos"],
	ACTION_PLACE_MACHINE:                ["facility_id", "machine_type", "grid_pos", "size"],
	ACTION_DEMOLISH_MACHINE:             ["facility_id", "machine_id"],
	ACTION_CREATE_MACHINE_CONNECTION:    ["facility_id", "from_machine_id", "to_machine_id"],
	ACTION_REMOVE_MACHINE_CONNECTION:    ["facility_id", "from_machine_id", "to_machine_id"],
	ACTION_CREATE_LOGISTICS_CONNECTION:  ["source_id", "destination_id", "product"],
	ACTION_REMOVE_LOGISTICS_CONNECTION:  ["connection_id"],
	ACTION_TOGGLE_CONNECTION_ACTIVE:     ["connection_id"],
	ACTION_SPEND_MONEY:                  ["amount", "reason"],
	ACTION_EARN_MONEY:                   ["amount", "reason"],
	ACTION_CHEAT_ADD_MONEY:              ["amount"],
	ACTION_DELIVER_TO_CONTRACT:          ["contract_id", "product", "quantity"],
	ACTION_CANCEL_CONTRACT:              ["contract_id"],
	ACTION_RESEARCH_TECH:                ["tech_id"],
	ACTION_SET_FARMHOUSE_CROP:           ["farmhouse_id", "crop_type"],
}

# ========================================
# GAME STATE
# ========================================

var current_state: GameState = GameState.MENU
var is_paused: bool = false

# Current game time (simulated date)
var current_date: Dictionary = {
	"year": 1850,
	"month": 1,
	"day": 1
}

# Time progression settings
var game_speed: float = 1.0  # Multiplier for time progression
var days_per_second: float = 0.5  # Default: 1 day per 2 seconds

# Active factory being viewed (null when on world map)
var active_factory_id: String = ""

# Currently active corp (hot-seat: which corp the player is acting as).
# Step 1 default: CORP_SINGLE. Real corp switching arrives with the hot-seat
# corp-switcher UI in a later step (per technical-architecture §3.1).
var active_corp_id: String = CORP_SINGLE

# ========================================
# CORP MANAGEMENT
# ========================================

func set_active_corp(corp_id: String) -> void:
	"""Switch the active corp. In step 1 this is only called manually for testing.
	The hot-seat switcher UI hooks into this in a later step."""
	if corp_id == active_corp_id:
		return
	if corp_id not in VALID_CORP_IDS:
		push_error("Invalid corp_id: %s" % corp_id)
		return

	var old_corp_id := active_corp_id
	active_corp_id = corp_id
	EventBus.active_corp_changed.emit(old_corp_id, corp_id)
	print("Active corp: %s -> %s" % [old_corp_id, corp_id])


# ========================================
# ACTION PIPE
# ========================================

func submit_action(corp_id: String, action_type: String, payload: Dictionary) -> bool:
	"""Single entry point for every state mutation in the game.
	Returns true on success, false on rejection. Rejection reason is push_warning-logged
	by the manager's predicate; UI uses the bool return to decide whether to update.

	Phase 8 step 3: in-process dispatch only. Phase 12 will swap the transport for a
	networked one without changing this signature.

	Phase 12 TODO: widen return to Dictionary { accepted, reason, action_id } when
	network sequencing arrives. Step 3 collapses to bool because there's no consumer
	of the richer shape yet."""

	# 1. Validate corp_id
	if corp_id not in VALID_CORP_IDS:
		push_error("submit_action: invalid corp_id '%s'" % corp_id)
		return false

	# 2. Validate action_type
	if action_type not in VALID_ACTION_TYPES:
		push_error("submit_action: unknown action_type '%s'" % action_type)
		return false

	# 3. Validate payload has all required keys for this action_type
	if not _validate_action_payload(action_type, payload):
		return false

	# 4. Dispatch by action_type. Each handler:
	#    a. Calls the manager's can_<action> predicate
	#    b. If ok, calls the manager's mutator
	#    c. Returns bool reflecting mutator success
	match action_type:
		ACTION_SPEND_MONEY:
			return _action_spend_money(corp_id, payload)
		ACTION_EARN_MONEY:
			return _action_earn_money(corp_id, payload)
		ACTION_CHEAT_ADD_MONEY:
			return _action_cheat_add_money(corp_id, payload)
		ACTION_PLACE_FACILITY, ACTION_PLACE_FIELD, ACTION_DEMOLISH_FACILITY, \
		ACTION_PLACE_ROAD, ACTION_REMOVE_ROAD, ACTION_PLACE_MACHINE, \
		ACTION_DEMOLISH_MACHINE, ACTION_CREATE_MACHINE_CONNECTION, \
		ACTION_REMOVE_MACHINE_CONNECTION, ACTION_CREATE_LOGISTICS_CONNECTION, \
		ACTION_REMOVE_LOGISTICS_CONNECTION, ACTION_TOGGLE_CONNECTION_ACTIVE, \
		ACTION_DELIVER_TO_CONTRACT, ACTION_CANCEL_CONTRACT, \
		ACTION_RESEARCH_TECH, ACTION_SET_FARMHOUSE_CROP:
			push_error("submit_action: action_type '%s' is not yet wired — arrives in sub-commit B" % action_type)
			return false
		_:
			push_error("submit_action: action_type '%s' is in VALID_ACTION_TYPES but has no dispatch handler — code bug" % action_type)
			return false


func _validate_action_payload(action_type: String, payload: Dictionary) -> bool:
	var required: Array = _ACTION_PAYLOAD_SCHEMA.get(action_type, [])
	for key in required:
		if not payload.has(key):
			push_error("submit_action: action '%s' missing required payload key '%s'" % [action_type, key])
			return false
	return true


# ============================================================
# ACTION HANDLERS — money actions (sub-commit A). Other handlers arrive in sub-commit B.
# ============================================================

func _action_spend_money(corp_id: String, payload: Dictionary) -> bool:
	return EconomyManager.spend_money(corp_id, int(payload.amount), String(payload.reason))


func _action_earn_money(corp_id: String, payload: Dictionary) -> bool:
	EconomyManager.earn_money(corp_id, int(payload.amount), String(payload.reason))
	return true


func _action_cheat_add_money(corp_id: String, payload: Dictionary) -> bool:
	EconomyManager.cheat_add_money(int(payload.amount))
	return true


# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("GameManager initialized")
	process_mode = Node.PROCESS_MODE_ALWAYS  # Continue processing when paused


# ========================================
# GAME STATE MANAGEMENT
# ========================================

func change_state(new_state: GameState) -> void:
	"""Change the current game state"""
	if current_state == new_state:
		return

	var old_state = current_state
	current_state = new_state

	print("Game state changed: %s -> %s" % [
		GameState.keys()[old_state],
		GameState.keys()[new_state]
	])

	_handle_state_transition(old_state, new_state)


func _handle_state_transition(from: GameState, to: GameState) -> void:
	"""Handle logic when transitioning between states"""

	# Exiting factory view
	if from == GameState.FACTORY_VIEW and to == GameState.WORLD_MAP:
		EventBus.factory_exited.emit(active_factory_id)
		active_factory_id = ""

	# Entering factory view
	if from == GameState.WORLD_MAP and to == GameState.FACTORY_VIEW:
		EventBus.factory_entered.emit(active_factory_id)

	# Pausing
	if to == GameState.PAUSED:
		pause_game()
	elif from == GameState.PAUSED:
		unpause_game()


func pause_game() -> void:
	"""Pause game simulation"""
	if is_paused:
		return

	is_paused = true
	get_tree().paused = true
	EventBus.game_paused.emit(true)
	print("Game paused")


func unpause_game() -> void:
	"""Resume game simulation"""
	if not is_paused:
		return

	is_paused = false
	get_tree().paused = false
	EventBus.game_paused.emit(false)
	print("Game unpaused")


# ========================================
# FACTORY VIEW MANAGEMENT
# ========================================

func enter_factory_view(factory_id: String) -> void:
	"""Enter factory interior view for a specific facility"""
	active_factory_id = factory_id
	change_state(GameState.FACTORY_VIEW)


func exit_factory_view() -> void:
	"""Return to world map from factory interior"""
	change_state(GameState.WORLD_MAP)


# ========================================
# TIME MANAGEMENT
# ========================================

func set_game_speed(speed: float) -> void:
	"""Set game speed multiplier (0 = paused, 1 = normal, 2 = fast, etc.)"""
	game_speed = clamp(speed, 0.0, 5.0)

	if game_speed == 0.0:
		pause_game()
	else:
		if is_paused:
			unpause_game()


func advance_date(days: int = 1) -> void:
	"""Advance the game date by specified number of days"""
	for i in range(days):
		current_date.day += 1

		# Check month overflow
		var days_in_month = _get_days_in_month(current_date.month, current_date.year)
		if current_date.day > days_in_month:
			current_date.day = 1
			current_date.month += 1

			# Check year overflow
			if current_date.month > 12:
				current_date.month = 1
				current_date.year += 1

	EventBus.date_advanced.emit(current_date)


func _get_days_in_month(month: int, year: int) -> int:
	"""Get number of days in a given month"""
	match month:
		2:  # February
			return 29 if _is_leap_year(year) else 28
		4, 6, 9, 11:  # April, June, September, November
			return 30
		_:
			return 31


func _is_leap_year(year: int) -> bool:
	"""Check if year is a leap year"""
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


func get_date_string() -> String:
	"""Get formatted date string"""
	return "%04d-%02d-%02d" % [current_date.year, current_date.month, current_date.day]


# ========================================
# GAME INITIALIZATION
# ========================================

func reset_game() -> void:
	"""Reset game to initial state for a new game"""
	print("Resetting game to initial state...")

	# Reset date
	current_date = {
		"year": 1850,
		"month": 1,
		"day": 1
	}

	# Reset state
	current_state = GameState.WORLD_MAP
	is_paused = false
	active_factory_id = ""
	active_corp_id = CORP_SINGLE
	game_speed = 1.0

	# Reset economy
	EconomyManager.reset_economy()

	# Clear world state (will be done by individual managers)
	EventBus.game_reset.emit()


# ========================================
# UTILITY
# ========================================

func quit_game() -> void:
	"""Quit the game"""
	print("Quitting game...")
	get_tree().quit()
