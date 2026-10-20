extends ColorRect

#listens for state change
func _ready() -> void:
	visible = false
	GameState.state_changed.connect(_on_state_changed)
	
func _on_state_changed(new_state: int) -> void:
	visible = (new_state == GameState.State.BAR)
	
func _unhandled_input(event: InputEvent) -> void:
	if GameState.state == GameState.State.BAR and event.is_action_pressed("cancel"):
		GameState.request_state(GameState.State.EXPLORING)
		get_viewport().set_input_as_handled()
