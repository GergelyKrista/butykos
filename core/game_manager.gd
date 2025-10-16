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
