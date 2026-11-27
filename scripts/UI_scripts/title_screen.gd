extends Control

@export_file("*.tscn") var game_scene_path: String

@onready var new_game_button: Button = $Menu/NewGameButton
@onready var load_game_button: Button = $Menu/LoadGameButton
@onready var settings_button: Button = $Menu/SettingsButton
@onready var quit_game_button: Button = $Menu/QuitButton
@onready var save_load_screen: SaveLoadScreen = %SaveLoadScreen
#@onready var settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	load_game_button.disabled = not SaveManager.any_save_exists()

	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	#settings_button.pressed.connect(_on_settings_pressed)
	quit_game_button.pressed.connect(_on_quit_game_pressed)

	save_load_screen.slot_chosen.connect(_on_slot_chosen)
	save_load_screen.closed.connect(_on_save_load_closed)
	#settings_menu.closed.connect(_on_settings_closed)

	new_game_button.grab_focus()


# --- Main menu buttons ---
func _on_new_game_pressed() -> void:
	save_load_screen.open(SaveLoadScreen.Mode.NEW)


func _on_load_game_pressed() -> void:
	save_load_screen.open(SaveLoadScreen.Mode.LOAD)

#func _on_settings_pressed() -> void:
	#settings_menu.open()

func _on_quit_game_pressed() -> void:
	get_tree().quit()


#Child screen signals
func _on_slot_chosen(slot: int, chosen_mode: SaveLoadScreen.Mode) -> void:
	if chosen_mode == SaveLoadScreen.Mode.NEW:
		SaveManager.new_game(slot)
		SaveManager.save_game()
		_start_game()
	elif SaveManager.load_game(slot):
		_start_game()

func _on_save_load_closed(closed_mode: SaveLoadScreen.Mode) -> void:
	(new_game_button if closed_mode == SaveLoadScreen.Mode.NEW else load_game_button).grab_focus()


func _on_settings_closed() -> void:
	settings_button.grab_focus()

func _start_game() -> void:
	if game_scene_path.is_empty():
		push_error("Error in TitleScreen: Game Scene Path is not set in the Inspector")
		return
	get_tree().change_scene_to_file(game_scene_path)
