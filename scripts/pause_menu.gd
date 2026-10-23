extends ColorRect

#for displaying money in pause menu
@onready var money_label: Label = $MoneyLabel

#updates money label in pause menu
func _update_money(amount: int) -> void:
	money_label.text = "$%d" % amount

#listens for state change
func _ready() -> void:
	visible = false
	GameState.state_changed.connect(_on_state_changed)
	Wallet.money_changed.connect(_update_money)
	_update_money(Wallet.money)
	
func _on_state_changed(new_state: int) -> void:
	visible = (new_state == GameState.State.MENU)

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
