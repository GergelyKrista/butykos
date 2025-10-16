extends Control

## MainMenu - Main menu screen with Start, Load, Settings, Exit

# ========================================
# REFERENCES
# ========================================

@onready var start_button = $CenterContainer/VBoxContainer/StartButton
@onready var load_button = $CenterContainer/VBoxContainer/LoadButton
@onready var settings_button = $CenterContainer/VBoxContainer/SettingsButton
@onready var exit_button = $CenterContainer/VBoxContainer/ExitButton
@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("Main Menu loaded")

	# Connect button signals
	start_button.pressed.connect(_on_start_pressed)
	load_button.pressed.connect(_on_load_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	# Disable load button if no saves exist
	_update_load_button()


func _update_load_button() -> void:
	"""Enable/disable load button based on save file existence"""
	var saves = SaveManager.list_saves()
	load_button.disabled = saves.is_empty()


# ========================================
# BUTTON HANDLERS
# ========================================

func _on_start_pressed() -> void:
	"""Start new game"""
	print("Starting new game...")

	# Reset game state
	_reset_game_state()

	# Load world map scene
	get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn")


func _on_load_pressed() -> void:
	"""Load game from quicksave slot"""
	print("Loading game...")

	var success = SaveManager.load_game("quicksave")
	if success:
		print("✓ Game loaded! Loading world map...")
		# Load world map scene (it will visualize the loaded data)
		get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn")
	else:
		print("✗ Failed to load game")


func _on_settings_pressed() -> void:
	"""Open settings menu (not implemented yet)"""
	print("Settings menu not implemented yet")
	# TODO: Create settings scene


func _on_exit_pressed() -> void:
	"""Exit game"""
	print("Exiting game...")
	get_tree().quit()


# ========================================
# HELPER FUNCTIONS
# ========================================

func _reset_game_state() -> void:
	"""Reset all game state for new game"""
	print("Resetting game state...")

	# Clear world
	WorldManager.facilities.clear()
	WorldManager._initialize_grid()
	WorldManager._next_facility_id = 1

	# Clear factories
	FactoryManager.factory_interiors.clear()

	# Clear logistics
	LogisticsManager.routes.clear()
	LogisticsManager.vehicles.clear()
	LogisticsManager._next_route_id = 1
	LogisticsManager._next_vehicle_id = 1

	# Reset economy
	EconomyManager.money = 5000

	# Reset date
	GameManager.current_date = {"year": 1850, "month": 1, "day": 1}

	print("Game state reset complete")
