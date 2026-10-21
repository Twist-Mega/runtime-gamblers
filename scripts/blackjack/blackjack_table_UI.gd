extends ColorRect


#listens for state change
func _ready() -> void:
	visible = false
	GameState.state_changed.connect(_on_state_changed)
	
func _on_state_changed(new_state: int) -> void:
	visible = (new_state == GameState.State.TABLE)
	####TEST FOR MONEY (works - 10/21)
	#if new_state == GameState.State.TABLE:
	#	Wallet.add_money(10)
	
func _unhandled_input(event: InputEvent) -> void:
	if GameState.state == GameState.State.TABLE and event.is_action_pressed("cancel"):
		GameState.request_state(GameState.State.EXPLORING)
		get_viewport().set_input_as_handled()
