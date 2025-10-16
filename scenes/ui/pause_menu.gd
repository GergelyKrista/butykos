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
@onready var save_load_dialog = $SaveLoadDialog

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

	# Connect dialog signals
	if save_load_dialog:
		save_load_dialog.save_completed.connect(_on_save_completed)
		save_load_dialog.load_completed.connect(_on_load_completed)
		save_load_dialog.dialog_closed.connect(_on_dialog_closed)


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
	"""Open save dialog"""
	print("Opening save dialog...")
	if save_load_dialog:
		panel.hide()  # Hide pause menu while dialog is open
		save_load_dialog.open_in_save_mode()


func _on_load_pressed() -> void:
	"""Open load dialog"""
	print("Opening load dialog...")
	if save_load_dialog:
		panel.hide()  # Hide pause menu while dialog is open
		save_load_dialog.open_in_load_mode()


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


# ========================================
# DIALOG HANDLERS
# ========================================

func _on_save_completed(slot_name: String) -> void:
	"""Handle save completion"""
	print("Save completed: %s" % slot_name)
	panel.show()  # Show pause menu again


func _on_load_completed(slot_name: String) -> void:
	"""Handle load completion"""
	print("Load completed: %s" % slot_name)
	# Unpause and reload scene to show loaded data
	get_tree().paused = false
	is_paused = false
	get_tree().reload_current_scene()


func _on_dialog_closed() -> void:
	"""Handle dialog closed without action"""
	print("Dialog closed")
	panel.show()  # Show pause menu again
