extends "res://scripts/blackjack/blackjack_wallet_port.gd"
## Test-only wallet with an idempotent ledger and injectable transfer failures.

const MAX_BALANCE: int = 9_223_372_036_854_775_807

var balance: int
var transactions: Dictionary = {}
var attempts: Array[Dictionary] = []
var fail_next_debits: int = 0
var fail_next_credits: int = 0
var on_transaction: Callable


func _init(starting_balance: int = 100) -> void:
	balance = starting_balance


func get_balance() -> int:
	return balance


func apply_transaction(transaction_id: String, delta: int) -> bool:
	attempts.append({"transaction_id": transaction_id, "delta": delta})
	if on_transaction.is_valid():
		on_transaction.call()
	if transactions.has(transaction_id):
		return transactions[transaction_id] == delta
	if delta < 0 and fail_next_debits > 0:
		fail_next_debits -= 1
		return false
	if delta >= 0 and fail_next_credits > 0:
		fail_next_credits -= 1
		return false
	if delta < 0 and delta < -balance:
		return false
	if delta > 0 and delta > MAX_BALANCE - balance:
		return false
	balance += delta
	transactions[transaction_id] = delta
	return true
