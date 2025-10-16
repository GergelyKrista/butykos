extends PanelContainer

## SaveLoadDialog - Unified save and load game dialog
##
## Can be used in both Save and Load modes.
## Shows save slots with timestamps and allows save/load/delete operations.

# ========================================
# SIGNALS
# ========================================

signal save_completed(slot_name: String)
signal load_completed(slot_name: String)
signal dialog_closed()

# ========================================
# REFERENCES
# ========================================

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderHBox/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderHBox/CloseButton
@onready var save_mode_button: Button = $MarginContainer/VBoxContainer/ModeTabContainer/SaveModeButton
@onready var load_mode_button: Button = $MarginContainer/VBoxContainer/ModeTabContainer/LoadModeButton
@onready var save_slots_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/SaveSlotsList
@onready var no_saves_label: Label = $MarginContainer/VBoxContainer/NoSavesLabel
@onready var save_name_panel: PanelContainer = $MarginContainer/VBoxContainer/SaveNamePanel
@onready var save_name_input: LineEdit = $MarginContainer/VBoxContainer/SaveNamePanel/HBoxContainer/SaveNameInput
@onready var delete_button: Button = $MarginContainer/VBoxContainer/ButtonsHBox/DeleteButton
@onready var action_button: Button = $MarginContainer/VBoxContainer/ButtonsHBox/ActionButton

# ========================================
# STATE
# ========================================

enum Mode { SAVE, LOAD }
var current_mode: Mode = Mode.LOAD
var selected_slot: String = ""
var save_slot_buttons: Dictionary = {}  # slot_name -> Button

# ========================================
# INITIALIZATION
# ========================================

func _ready() -> void:
	hide()
	_update_button_states()

	# Connect save name input text changes to update button states
	if save_name_input:
		save_name_input.text_changed.connect(_on_save_name_changed)


# ========================================
# PUBLIC API
# ========================================

func open_in_save_mode() -> void:
	"""Open dialog in save mode"""
	current_mode = Mode.SAVE
	_update_ui()
	_populate_save_slots()
	show()


func open_in_load_mode() -> void:
	"""Open dialog in load mode"""
	current_mode = Mode.LOAD
	_update_ui()
	_populate_save_slots()
	show()


# ========================================
# UI UPDATES
# ========================================

func _update_ui() -> void:
	"""Update UI based on current mode"""
	if current_mode == Mode.SAVE:
		title_label.text = "Save Game"
		action_button.text = "SAVE"
		save_name_panel.visible = true
		# Hide mode switching tabs - user shouldn't switch modes
		if save_mode_button and load_mode_button:
			save_mode_button.get_parent().visible = false
	else:  # LOAD
		title_label.text = "Load Game"
		action_button.text = "LOAD"
		save_name_panel.visible = false
		# Hide mode switching tabs - user shouldn't switch modes
		if save_mode_button and load_mode_button:
			save_mode_button.get_parent().visible = false

	_update_button_states()


func _update_button_states() -> void:
	"""Update button enabled/disabled states"""
	var has_selection = not selected_slot.is_empty()

	# Action button requires selection in load mode, or save name in save mode
	if current_mode == Mode.SAVE:
		var has_save_name = save_name_input and not save_name_input.text.strip_edges().is_empty()
		if action_button:
			action_button.disabled = not has_save_name
	else:  # LOAD
		if action_button:
			action_button.disabled = not has_selection

	# Delete button requires selection
	if delete_button:
		delete_button.disabled = not has_selection


# ========================================
# SAVE SLOT MANAGEMENT
# ========================================

func _populate_save_slots() -> void:
	"""Populate save slot list"""
	_clear_save_slots()

	var saves = SaveManager.list_saves()

	if saves.is_empty():
		no_saves_label.visible = true
		return

	no_saves_label.visible = false

	# Note: saves are already sorted by modified time (newest first)

	# Create button for each save
	for save_data in saves:
		_create_save_slot_button(save_data)

	# In save mode, add "New Save Slot" button
	if current_mode == Mode.SAVE:
		_create_new_slot_button()


func _create_save_slot_button(save_data: Dictionary) -> void:
	"""Create a button for a save slot"""
	# save_data contains: slot, path, modified (from SaveManager.list_saves())
	var slot_name = save_data.get("slot", "unknown")
	var modified_time = save_data.get("modified", 0)

	# Format modified timestamp
	var datetime = Time.get_datetime_dict_from_unix_time(modified_time)
	var date_str = "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

	# Try to read the save file to get game date (optional - if fails, just show modified time)
	var game_date_str = ""
	var save_file_path = save_data.get("path", "")
	if FileAccess.file_exists(save_file_path):
		var file = FileAccess.open(save_file_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(json_string) == OK:
				var data = json.data
				if data is Dictionary and data.has("date"):
					var game_date = data.date
					game_date_str = " | Game: %04d-%02d-%02d" % [
						game_date.get("year", 1850),
						game_date.get("month", 1),
						game_date.get("day", 1)
					]

	# Create button
	var button = Button.new()
	button.text = "%s\nSaved: %s%s" % [slot_name, date_str, game_date_str]
	button.custom_minimum_size = Vector2(0, 70)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(_on_slot_selected.bind(slot_name))

	save_slots_list.add_child(button)
	save_slot_buttons[slot_name] = button


func _create_new_slot_button() -> void:
	"""Create a 'New Save Slot' button for save mode"""
	var button = Button.new()
	button.text = "+ New Save Slot"
	button.custom_minimum_size = Vector2(0, 60)
	button.pressed.connect(_on_new_slot_selected)

	save_slots_list.add_child(button)


func _clear_save_slots() -> void:
	"""Clear all save slot buttons"""
	for child in save_slots_list.get_children():
		child.queue_free()
	save_slot_buttons.clear()
	selected_slot = ""
	_update_button_states()


func _on_slot_selected(slot_name: String) -> void:
	"""Handle save slot selection"""
	print("Selected slot: %s" % slot_name)
	selected_slot = slot_name

	# In save mode, fill the save name input
	if current_mode == Mode.SAVE and save_name_input:
		save_name_input.text = slot_name

	# Highlight selected button
	for slot in save_slot_buttons:
		var button = save_slot_buttons[slot]
		if slot == slot_name:
			button.modulate = Color(1.2, 1.2, 1.2)
		else:
			button.modulate = Color(1, 1, 1)

	_update_button_states()


func _on_new_slot_selected() -> void:
	"""Handle new slot selection"""
	selected_slot = ""

	# Clear all highlights
	for button in save_slot_buttons.values():
		button.modulate = Color(1, 1, 1)

	# Clear and focus save name input
	if save_name_input:
		save_name_input.text = ""
		save_name_input.grab_focus()

	_update_button_states()


# ========================================
# BUTTON HANDLERS
# ========================================

func _on_save_mode_pressed() -> void:
	"""Switch to save mode"""
	current_mode = Mode.SAVE
	_update_ui()
	_populate_save_slots()


func _on_load_mode_pressed() -> void:
	"""Switch to load mode"""
	current_mode = Mode.LOAD
	_update_ui()
	_populate_save_slots()


func _on_action_pressed() -> void:
	"""Handle Save or Load button press"""
	if current_mode == Mode.SAVE:
		_do_save()
	else:  # LOAD
		_do_load()


func _do_save() -> void:
	"""Perform save operation"""
	if not save_name_input:
		print("ERROR: save_name_input is null!")
		return

	var slot_name = save_name_input.text.strip_edges()

	if slot_name.is_empty():
		print("ERROR: Save name cannot be empty")
		return

	print("Saving to slot: %s" % slot_name)
	var success = SaveManager.save_game(slot_name)

	if success:
		print("✓ Save successful!")
		save_completed.emit(slot_name)
		hide()
		dialog_closed.emit()
	else:
		print("✗ Save failed!")
		# TODO: Show error message


func _do_load() -> void:
	"""Perform load operation"""
	if selected_slot.is_empty():
		print("ERROR: No slot selected")
		return

	print("Loading from slot: %s" % selected_slot)
	var success = SaveManager.load_game(selected_slot)

	if success:
		print("✓ Load successful!")
		load_completed.emit(selected_slot)
		hide()
		dialog_closed.emit()
	else:
		print("✗ Load failed!")
		# TODO: Show error message


func _on_delete_pressed() -> void:
	"""Delete selected save"""
	if selected_slot.is_empty():
		return

	print("Deleting save: %s" % selected_slot)
	SaveManager.delete_save(selected_slot)

	# Refresh list
	selected_slot = ""
	_populate_save_slots()
	_update_button_states()


func _on_close_pressed() -> void:
	"""Close dialog"""
	hide()
	dialog_closed.emit()


func _on_save_name_changed(_new_text: String) -> void:
	"""Handle save name input text change"""
	_update_button_states()
