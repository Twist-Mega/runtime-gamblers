extends Node

signal money_changed(new_amount: int)

const STARTING_MONEY := 100

var money: int = STARTING_MONEY

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
