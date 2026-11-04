extends "res://scripts/blackjack/blackjack_wallet_port.gd"
## Forward blackjack payments to the official wallet without owning a balance.

var _wallet: Node


func _init(wallet: Node) -> void:
	_wallet = wallet


func get_balance() -> int:
	return _wallet.money


func apply_transaction(transaction_id: String, delta: int) -> bool:
	return _wallet.apply_transaction(transaction_id, delta)
