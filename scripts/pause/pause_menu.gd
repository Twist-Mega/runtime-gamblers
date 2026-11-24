extends CanvasLayer

const TITLE_PATH := 'res://scenes/title_screen.tscn'

#for displaying money in pause menu
@onready var money_label: Label = %MoneyLabel
@onready var resume_button: Button = %ResumeButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton

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
	#Wallet updating correctly 11/23
	_update_money(Wallet.money)
	quit_button.pressed.connect(_on_quit_button_pressed)

func _on_state_changed(new_state: int) -> void:
	visible = (new_state == GameState.State.MENU)

func _on_resume_button_pressed() -> void:
	GameState.request_state(GameState.State.EXPLORING)
	
func _on_quit_button_pressed() -> void:
	get_tree().change_scene_to_file(TITLE_PATH)

#currently can exit menu via pressing the menu button again (z) or through the cancel button (c)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if GameState.state == GameState.State.MENU:
			GameState.request_state(GameState.State.EXPLORING)
		else:
			GameState.request_state(GameState.State.MENU)
		get_viewport().set_input_as_handled()
	elif GameState.state == GameState.State.MENU and event.is_action_pressed("cancel"):
		GameState.request_state(GameState.State.EXPLORING)
		get_viewport().set_input_as_handled()
