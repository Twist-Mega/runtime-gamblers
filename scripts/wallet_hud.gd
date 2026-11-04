extends Label
## Show the official wallet balance while exploring.


func _ready() -> void:
	Wallet.money_changed.connect(_update_money)
	GameState.state_changed.connect(_on_state_changed)
	_update_money(Wallet.money)
	_on_state_changed(GameState.state)


func _update_money(amount: int) -> void:
	text = str(amount)


func _on_state_changed(new_state: int) -> void:
	visible = new_state == GameState.State.EXPLORING
