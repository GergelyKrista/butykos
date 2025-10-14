extends Node

## SaveManager - Save/load game state and player preferences
##
## Handles serialization of game state to disk and restoration.
## Uses JSON format for readability and easy debugging.

# ========================================
# CONSTANTS
# ========================================

const SAVE_DIR = "user://saves/"
const SAVE_EXTENSION = ".save"
const PREFERENCES_FILE = "user://preferences.cfg"

const CURRENT_SAVE_VERSION = 1

# ========================================
# STATE
# ========================================

var current_save_slot: String = ""
var auto_save_enabled: bool = true
var auto_save_interval: float = 300.0  # 5 minutes

var _auto_save_timer: float = 0.0

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("SaveManager initialized")
	_ensure_save_directory()
	load_preferences()


func _process(delta: float) -> void:
	if auto_save_enabled and GameManager.current_state == GameManager.GameState.WORLD_MAP:
		_auto_save_timer += delta
		if _auto_save_timer >= auto_save_interval:
			_auto_save_timer = 0.0
			auto_save()


# ========================================
# SAVE MANAGEMENT
# ========================================

func save_game(slot_name: String = "") -> bool:
	"""Save current game state to specified slot"""

	if slot_name.is_empty():
		slot_name = current_save_slot

	if slot_name.is_empty():
		push_error("No save slot specified")
		return false

	print("Saving game to slot: %s" % slot_name)

	EventBus.before_save.emit()

	var save_data = _gather_save_data()
	var success = _write_save_file(slot_name, save_data)

	if success:
		current_save_slot = slot_name
		print("Game saved successfully")
	else:
		push_error("Failed to save game")

	EventBus.save_completed.emit(success)
	return success


func load_game(slot_name: String) -> bool:
	"""Load game state from specified slot"""

	print("Loading game from slot: %s" % slot_name)

	var save_data = _read_save_file(slot_name)
	if save_data.is_empty():
		push_error("Failed to load save file: %s" % slot_name)
		return false

	var success = _apply_save_data(save_data)

	if success:
		current_save_slot = slot_name
		print("Game loaded successfully")
		EventBus.after_load.emit()
	else:
		push_error("Failed to apply save data")

	return success


func auto_save() -> bool:
	"""Perform an auto-save"""
	if current_save_slot.is_empty():
		return false

	var auto_save_name = current_save_slot + "_auto"
	print("Auto-saving...")
	return save_game(auto_save_name)


func delete_save(slot_name: String) -> bool:
	"""Delete a save file"""
	var file_path = _get_save_path(slot_name)

	if not FileAccess.file_exists(file_path):
		push_error("Save file does not exist: %s" % slot_name)
		return false

	var dir = DirAccess.open(SAVE_DIR)
	var error = dir.remove(file_path)

	if error == OK:
		print("Save deleted: %s" % slot_name)
		return true
	else:
		push_error("Failed to delete save: %s" % slot_name)
		return false


func list_saves() -> Array[Dictionary]:
	"""Get list of available save files"""
	var saves: Array[Dictionary] = []
	var dir = DirAccess.open(SAVE_DIR)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()

		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(SAVE_EXTENSION):
				var slot_name = file_name.trim_suffix(SAVE_EXTENSION)
				var file_path = _get_save_path(slot_name)

				saves.append({
					"slot": slot_name,
					"path": file_path,
					"modified": FileAccess.get_modified_time(file_path)
				})

			file_name = dir.get_next()

		dir.list_dir_end()

	# Sort by modified time (newest first)
	saves.sort_custom(func(a, b): return a.modified > b.modified)

	return saves


# ========================================
# PREFERENCES
# ========================================

func save_preferences() -> void:
	"""Save player preferences"""
	var config = ConfigFile.new()

	config.set_value("game", "auto_save_enabled", auto_save_enabled)
	config.set_value("game", "auto_save_interval", auto_save_interval)

	var error = config.save(PREFERENCES_FILE)
	if error != OK:
		push_error("Failed to save preferences")


func load_preferences() -> void:
	"""Load player preferences"""
	var config = ConfigFile.new()
	var error = config.load(PREFERENCES_FILE)

	if error != OK:
		print("No preferences file found, using defaults")
		return

	auto_save_enabled = config.get_value("game", "auto_save_enabled", true)
	auto_save_interval = config.get_value("game", "auto_save_interval", 300.0)


# ========================================
# PRIVATE METHODS
# ========================================

func _ensure_save_directory() -> void:
	"""Create save directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _get_save_path(slot_name: String) -> String:
	"""Get full path for a save slot"""
	return SAVE_DIR + slot_name + SAVE_EXTENSION


func _gather_save_data() -> Dictionary:
	"""Gather all game state data for saving"""
	return {
		"version": CURRENT_SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"date": GameManager.current_date,
		"game_state": GameManager.GameState.keys()[GameManager.current_state],

		# System data (will be populated by managers)
		"world": {},
		"factories": {},
		"logistics": {},
		"markets": {},
		"economy": {},
	}


func _apply_save_data(data: Dictionary) -> bool:
	"""Apply loaded save data to game state"""

	# Version check
	if not data.has("version") or data.version != CURRENT_SAVE_VERSION:
		push_error("Incompatible save version")
		return false

	# Restore game manager state
	GameManager.current_date = data.get("date", {"year": 1850, "month": 1, "day": 1})

	# Systems will listen to after_load signal and restore their state
	# from the data dictionary

	return true


func _write_save_file(slot_name: String, data: Dictionary) -> bool:
	"""Write save data to file"""
	var file_path = _get_save_path(slot_name)
	var file = FileAccess.open(file_path, FileAccess.WRITE)

	if not file:
		push_error("Failed to open save file for writing: %s" % file_path)
		return false

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()

	return true


func _read_save_file(slot_name: String) -> Dictionary:
	"""Read save data from file"""
	var file_path = _get_save_path(slot_name)

	if not FileAccess.file_exists(file_path):
		return {}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file for reading: %s" % file_path)
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)

	if error != OK:
		push_error("Failed to parse save file JSON")
		return {}

	return json.data
