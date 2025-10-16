extends CanvasLayer

## PauseMenu - Pause menu overlay with Save, Load, Exit to Menu

# ========================================
# REFERENCES
# ========================================

@onready var panel = $Panel
@onready var save_button = $Panel/CenterContainer/VBoxContainer/SaveButton
@onready var load_button = $Panel/CenterContainer/VBoxContainer/LoadButton
@onready var resume_button = $Panel/CenterContainer/VBoxContainer/ResumeButton
@onready var exit_button = $Panel/CenterContainer/VBoxContainer/ExitButton

# ========================================
# STATE
# ========================================

var is_paused: bool = false

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	print("Pause Menu initialized")

	# Start hidden
	hide()
	is_paused = false

	# Connect button signals
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	resume_button.pressed.connect(_on_resume_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func _input(event: InputEvent) -> void:
	# Toggle pause with ESC key (but only if not in placement/route mode)
	if event.is_action_pressed("ui_cancel"):
		# Check if world map is in a mode that should handle ESC first
		var world_map = get_tree().current_scene
		if world_map.has_method("_is_in_mode"):
			if world_map._is_in_mode():
				return  # Let world map handle it

		toggle_pause()


# ========================================
# PAUSE CONTROL
# ========================================

func toggle_pause() -> void:
	"""Toggle pause state"""
	if is_paused:
		unpause()
	else:
		pause()


func pause() -> void:
	"""Pause the game and show menu"""
	is_paused = true
	show()
	get_tree().paused = true
	print("Game paused")


func unpause() -> void:
	"""Unpause the game and hide menu"""
	is_paused = false
	hide()
	get_tree().paused = false
	print("Game resumed")


# ========================================
# BUTTON HANDLERS
# ========================================

func _on_save_pressed() -> void:
	"""Save game to quicksave slot"""
	print("Saving game...")
	var success = SaveManager.save_game("quicksave")
	if success:
		print("✓ Game saved!")
	else:
		print("✗ Save failed")


func _on_load_pressed() -> void:
	"""Load game from quicksave slot"""
	print("Loading game...")

	# Unpause first
	unpause()

	var success = SaveManager.load_game("quicksave")
	if success:
		print("✓ Game loaded! Reloading scene...")
		# Reload world map scene to visualize loaded data
		get_tree().paused = false  # Make sure we're not paused
		get_tree().reload_current_scene()
	else:
		print("✗ Load failed")


func _on_resume_pressed() -> void:
	"""Resume game"""
	unpause()


func _on_exit_pressed() -> void:
	"""Exit to main menu"""
	print("Exiting to main menu...")

	# Unpause and return to main menu
	get_tree().paused = false
	is_paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
