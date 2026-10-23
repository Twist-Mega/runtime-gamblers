extends ColorRect

const BlackjackScene = preload("res://tests/blackjack/blackjack_debug.tscn")
const GameWallet = preload("res://scripts/blackjack/game_wallet_adapter.gd")

var _blackjack_view: Control
var _blackjack_layer: CanvasLayer

#listens for state change
func _ready() -> void:
	visible = false
	GameState.state_changed.connect(_on_state_changed)
	$PlayButton.pressed.connect(_on_play_pressed)
	
func _on_state_changed(new_state: int) -> void:
	visible = new_state == GameState.State.TABLE and not is_instance_valid(_blackjack_view)
	if visible:
		$Label.text = "Blackjack\n\nPress C to exit"
		$PlayButton.text = "Play"
		$PlayButton.disabled = not Wallet.can_afford(5)
	####TEST FOR MONEY (works - 10/21)
	#if new_state == GameState.State.TABLE:
	#	Wallet.add_money(10)
	
func _unhandled_input(event: InputEvent) -> void:
	if visible and GameState.state == GameState.State.TABLE and event.is_action_pressed("cancel"):
		GameState.request_state(GameState.State.EXPLORING)
		get_viewport().set_input_as_handled()


func _on_play_pressed() -> void:
	if GameState.state != GameState.State.TABLE or is_instance_valid(_blackjack_view) or not Wallet.can_afford(5):
		return
	_blackjack_view = BlackjackScene.instantiate()
	_blackjack_view.configure_wallet(GameWallet.new(Wallet))
	_blackjack_view.process_mode = Node.PROCESS_MODE_ALWAYS
	_blackjack_view.manage_window_scaling = true
	_blackjack_view.return_summary_to_host = true
	_blackjack_view.session_closed.connect(_on_blackjack_closed, CONNECT_DEFERRED)
	_blackjack_layer = CanvasLayer.new()
	_blackjack_layer.layer = 10
	_blackjack_layer.add_child(_blackjack_view)
	visible = false
	get_tree().root.add_child(_blackjack_layer)


func _on_blackjack_closed(summary: Dictionary) -> void:
	if is_instance_valid(_blackjack_layer):
		_blackjack_layer.free()
	_blackjack_layer = null
	_blackjack_view = null
	var net := ("+" if summary.net_change > 0 else "") + str(summary.net_change)
	$Label.text = "Game Summary\nHands: %d\nStart: %d\nEnd: %d\nNet: %s\n\nPress C to exit" % [
		summary.hands_played, summary.starting_balance, summary.ending_balance, net]
	$PlayButton.text = "Play Again"
	$PlayButton.disabled = not Wallet.can_afford(5)
	visible = true


func _exit_tree() -> void:
	if is_instance_valid(_blackjack_layer):
		_blackjack_layer.free()
