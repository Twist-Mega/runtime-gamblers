extends Control

enum Mode { NEW, LOAD }

@export_file("*.tscn") var game_scene_path: String

var mode := Mode.NEW
var pending_overwrite := -1

@onready var new_game_button: Button = $Menu/NewGameButton
@onready var load_game_button: Button = $Menu/LoadGameButton
@onready var settings_button: Button = $Menu/SettingsButton
@onready var settings_panel: Control = $SettingsPanel
@onready var back_button: Button = $SettingsPanel/BackButton
@onready var slot_panel: Control = $SlotPanel
@onready var slot_buttons: Array = $SlotPanel/SlotList.get_children()
@onready var slot_back_button: Button = $SlotPanel/SlotBackButton

func _ready() -> void:
	settings_panel.visible = false
	slot_panel.visible = false
	load_game_button.disabled = not SaveManager.any_save_exists()

	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	back_button.pressed.connect(_on_back_pressed)
	slot_back_button.pressed.connect(_close_slots)
	for i in slot_buttons.size():
		slot_buttons[i].pressed.connect(_on_slot_pressed.bind(i + 1))

	new_game_button.grab_focus()

# --- Main menu ---

func _on_new_game_pressed() -> void:
	_open_slots(Mode.NEW)

func _on_load_game_pressed() -> void:
	_open_slots(Mode.LOAD)

func _on_settings_pressed() -> void:
	settings_panel.visible = true
	back_button.grab_focus()

func _on_back_pressed() -> void:
	settings_panel.visible = false
	settings_button.grab_focus()

# --- Slot picker ---

func _open_slots(new_mode: Mode) -> void:
	mode = new_mode
	pending_overwrite = -1
	var first_enabled: Button = slot_back_button
	for i in slot_buttons.size():
		var slot := i + 1
		var button: Button = slot_buttons[i]
		if SaveManager.has_save(slot):
			var saved_at: String = SaveManager.get_slot_info(slot).get("saved_at", "")
			button.text = "Slot %d  %s" % [slot, saved_at.left(16)]
			button.disabled = false
		else:
			button.text = "Slot %d  Empty" % slot
			button.disabled = (mode == Mode.LOAD)
		if not button.disabled and first_enabled == slot_back_button:
			first_enabled = button
	slot_panel.visible = true
	first_enabled.grab_focus()

func _close_slots() -> void:
	slot_panel.visible = false
	pending_overwrite = -1
	(new_game_button if mode == Mode.NEW else load_game_button).grab_focus()

func _on_slot_pressed(slot: int) -> void:
	if mode == Mode.LOAD:
		if SaveManager.load_game(slot):
			_start_game()
		return
	if SaveManager.has_save(slot) and pending_overwrite != slot:
		pending_overwrite = slot
		slot_buttons[slot - 1].text = "Overwrite? Press again"
		return
	SaveManager.new_game(slot)
	SaveManager.save_game()
	_start_game()

# --- Shared ---

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if slot_panel.visible:
		_close_slots()
		get_viewport().set_input_as_handled()
	elif settings_panel.visible:
		_on_back_pressed()
		get_viewport().set_input_as_handled()

func _start_game() -> void:
	get_tree().change_scene_to_file(game_scene_path)
