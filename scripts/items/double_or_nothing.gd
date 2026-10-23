class_name DoubleOrNothing
extends RefCounted

## After a win, offer a rematch at 2x stakes.
## Example: won a $10 game → pay $20 to play again, win pays $20.

const ID := "double_or_nothing"


static func doubled_stake(won_stake: int) -> int:
	return maxi(won_stake, 0) * 2


## True when the player has the item and can afford the doubled buy-in.
static func can_offer(won_stake: int) -> bool:
	var stake: int = doubled_stake(won_stake)
	return stake > 0 and Inventory.has_item(ID) and Wallet.can_afford(stake)


## UI-facing offer details after a win.
## Returns { available, has_item, cost, stake, can_afford }.
static func offer_info(won_stake: int) -> Dictionary:
	var stake: int = doubled_stake(won_stake)
	var has_item: bool = Inventory.has_item(ID)
	var can_afford: bool = stake > 0 and Wallet.can_afford(stake)
	return {
		"available": has_item and can_afford and stake > 0,
		"has_item": has_item,
		"cost": stake,
		"stake": stake,
		"can_afford": can_afford,
	}


## Full doubled stake credited on a win.
static func win_payout(doubled_table_stake: int) -> int:
	return maxi(doubled_table_stake, 0)


## Spends the doubled buy-in and consumes one Double or Nothing.
## Call when the player accepts the post-win offer.
## Returns { ok, cost, stake, used_item }.
static func accept(won_stake: int) -> Dictionary:
	var stake: int = doubled_stake(won_stake)
	if stake <= 0:
		return {"ok": false, "cost": 0, "stake": 0, "used_item": false}
	if not Inventory.has_item(ID):
		return {"ok": false, "cost": stake, "stake": stake, "used_item": false}
	if not Wallet.can_afford(stake):
		return {"ok": false, "cost": stake, "stake": stake, "used_item": false}
	Wallet.spend_money(stake)
	Inventory.remove_item(ID)
	return {
		"ok": true,
		"cost": stake,
		"stake": stake,
		"used_item": true,
	}


## Credits a win for the doubled table stake.
static func pay_win(doubled_table_stake: int) -> int:
	var amount: int = win_payout(doubled_table_stake)
	if amount > 0:
		Wallet.add_money(amount)
	return amount
