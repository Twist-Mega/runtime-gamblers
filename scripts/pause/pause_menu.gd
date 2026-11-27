extends CanvasLayer

const TITLE_PATH := 'res://scenes/title_screen.tscn'

#for displaying money in pause menu
@onready var money_label: Label = %MoneyLabel
@onready var resume_button: Button = %ResumeButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var save_load_screen: SaveLoadScreen = %SaveLoadScreen
#@onready var settings_menu: SettingsMenu = %SettingsMenu

#updates money label in pause menu
func _update_money(amount: int) -> void:
	money_label.text = "$%d" % amount

#listens for state change
func _ready() -> void:
	visible = false
	GameState.state_changed.connect(_on_state_changed)
	Wallet.money_changed.connect(_update_money)
	#resume button working 11/23
	resume_button.pressed.connect(_on_resume_button_pressed)
	save_button.pressed.connect(_on_save_pressed)
	load_button.pressed.connect(_on_load_pressed)
	#Wallet updating correctly 11/23
	_update_money(Wallet.money)
	quit_button.pressed.connect(_on_quit_button_pressed)
	save_load_screen.slot_chosen.connect(_on_slot_chosen)
	save_load_screen.closed.connect(_on_save_load_closed)
	#settings_button.pressed.connect(_on_settings_pressed)
	#settings_menu.closed.connect(_on_settings_closed)

func _on_state_changed(new_state: int) -> void:
	visible = (new_state == GameState.State.MENU)
	if visible:
		resume_button.grab_focus()
	else:
		save_load_screen.close()
		#settings_menu.close()

#RESUME
func _on_resume_button_pressed() -> void:
	GameState.request_state(GameState.State.EXPLORING)

#SAVE
func _on_save_pressed() -> void:
	print("load pressed")
	save_load_screen.open(SaveLoadScreen.Mode.SAVE)
	print("visible: ", save_load_screen.visible,
		" in tree: ", save_load_screen.is_visible_in_tree(),
		" rect: ", save_load_screen.get_global_rect())

#LOAD
func _on_load_pressed() -> void:
	print("load pressed")
	save_load_screen.open(SaveLoadScreen.Mode.LOAD)
	print("visible: ", save_load_screen.visible,
		" in tree: ", save_load_screen.is_visible_in_tree(),
		" rect: ", save_load_screen.get_global_rect())
	
func _on_slot_chosen(slot: int, chosen_mode: SaveLoadScreen.Mode) -> void:
	if chosen_mode == SaveLoadScreen.Mode.SAVE:
		SaveManager.save_to_slot(slot)
		save_button.grab_focus()
	elif SaveManager.load_game(slot):
		GameState.request_state(GameState.State.EXPLORING)

func _on_save_load_closed(closed_mode: SaveLoadScreen.Mode) -> void:
	(save_button if closed_mode == SaveLoadScreen.Mode.SAVE else load_button).grab_focus()

#OPTIONS
#func _on_settings_pressed() -> void:
	#settings_menu.open()

#QUIT
func _on_quit_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_PATH)
	
func _overlay_open() -> bool:
	return save_load_screen.visible #or settings_menu.visible

#currently can exit menu via pressing the menu button again (z) or through the cancel button (c)
func _unhandled_input(event: InputEvent) -> void:
	if _overlay_open():
		return
	if event.is_action_pressed("menu"):
		if GameState.state == GameState.State.MENU:
			GameState.request_state(GameState.State.EXPLORING)
		else:
			GameState.request_state(GameState.State.MENU)
		get_viewport().set_input_as_handled()
	elif GameState.state == GameState.State.MENU and event.is_action_pressed("cancel"):
		GameState.request_state(GameState.State.EXPLORING)
		get_viewport().set_input_as_handled()
