extends Node

signal money_changed(new_amount: int)

const STARTING_MONEY := 100
const MAX_MONEY: int = 9_223_372_036_854_775_807

var money: int = STARTING_MONEY
var _applied_transactions: Dictionary = {}

func _ready() -> void:
	add_to_group("saveable")
	
func save_key() -> String:
	return "wallet"
	
func get_save_data() -> Dictionary:
	return {"money": money}
	
func load_save_data(data: Dictionary) -> void:
	money = int(data.get("money", STARTING_MONEY))
	money_changed.emit(money)

func reset_to_defaults() -> void:
	money = STARTING_MONEY
	money_changed.emit(money)

# Negative amounts spend money; positive amounts credit it.
# A successful ID can be retried with the same amount without applying it twice.
func apply_transaction(transaction_id: String, delta: int) -> bool:
	if transaction_id.is_empty() or money < 0:
		return false
	if _applied_transactions.has(transaction_id):
		return _applied_transactions[transaction_id] == delta
	if delta < 0 and delta < -money:
		return false
	if delta > 0 and delta > MAX_MONEY - money:
		return false
	_applied_transactions[transaction_id] = delta
	money += delta
	if delta != 0:
		money_changed.emit(money)
	return true

func can_afford(amount: int) -> bool:
	return money >= amount

func add_money(amount: int) -> void:
	if amount <= 0:
		return
	money += amount
	money_changed.emit(money)

func spend_money(amount: int) -> bool:
	if amount <= 0 or not can_afford(amount):
		return false
	money -= amount
	money_changed.emit(money)
	return true
