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
@onready var save_load_dialog = $SaveLoadDialog
@onready var main_menu_container = $CenterContainer

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

	# Connect dialog signals
	if save_load_dialog:
		save_load_dialog.load_completed.connect(_on_load_completed)
		save_load_dialog.dialog_closed.connect(_on_dialog_closed)

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

	# Reset game state using GameManager
	GameManager.reset_game()

	# Load world map scene
	get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn")


func _on_load_pressed() -> void:
	"""Open load game dialog"""
	print("Opening load game dialog...")
	if save_load_dialog:
		main_menu_container.hide()  # Hide main menu while dialog is open
		save_load_dialog.open_in_load_mode()


func _on_settings_pressed() -> void:
	"""Open settings menu (not implemented yet)"""
	print("Settings menu not implemented yet")
	# TODO: Create settings scene


func _on_exit_pressed() -> void:
	"""Exit game"""
	print("Exiting game...")
	get_tree().quit()


# ========================================
# DIALOG HANDLERS
# ========================================

func _on_load_completed(slot_name: String) -> void:
	"""Handle load completion"""
	print("Load completed: %s" % slot_name)
	# Transition to world map (load already restored state)
	get_tree().change_scene_to_file("res://scenes/world_map/world_map.tscn")


func _on_dialog_closed() -> void:
	"""Handle dialog closed without action"""
	print("Dialog closed")
	main_menu_container.show()  # Show main menu again


