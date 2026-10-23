extends Node

## Register as an autoload named "Inventory" in Project Settings when ready to wire up.

signal inventory_changed

const STAKE_COUPON := "stake_coupon"
const DOUBLE_OR_NOTHING := "double_or_nothing"

## Item catalog: id -> display info. Add new items here.
const CATALOG := {
	STAKE_COUPON: {
		"name": "Stake Coupon",
		"description": "Pay half the table stake to play. Wins still pay the full stake.",
	},
	DOUBLE_OR_NOTHING: {
		"name": "Double or Nothing",
		"description": "After a win, play again at double stakes. Pay double, win double.",
	},
}

var _counts: Dictionary = {}


func get_count(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


func has_item(item_id: String, amount: int = 1) -> bool:
	return get_count(item_id) >= amount


func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0 or not CATALOG.has(item_id):
		return
	_counts[item_id] = get_count(item_id) + amount
	inventory_changed.emit()


func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0 or not has_item(item_id, amount):
		return false
	var next: int = get_count(item_id) - amount
	if next <= 0:
		_counts.erase(item_id)
	else:
		_counts[item_id] = next
	inventory_changed.emit()
	return true


func get_display_name(item_id: String) -> String:
	return str(CATALOG.get(item_id, {}).get("name", item_id))
