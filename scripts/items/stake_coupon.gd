class_name StakeCoupon
extends RefCounted

## Halves buy-in; win payout stays the full table stake.
## Example: stake 10 → pay 5 with a coupon, still make 10 on a win.

const ID := "stake_coupon"


## Cost to enter a table. Halved when a coupon will be used.
static func buy_in_cost(table_stake: int, use_coupon: bool = true) -> int:
	if table_stake <= 0:
		return 0
	if use_coupon and Inventory.has_item(ID):
		return table_stake / 2
	return table_stake


## Full table stake credited on a win. Coupons never reduce this.
static func win_payout(table_stake: int) -> int:
	return maxi(table_stake, 0)


## Spends buy-in from Wallet and consumes one coupon when used.
## Returns { ok, cost, stake, used_coupon }.
static func pay_buy_in(table_stake: int, use_coupon: bool = true) -> Dictionary:
	var used_coupon: bool = use_coupon and Inventory.has_item(ID)
	var cost: int = buy_in_cost(table_stake, use_coupon)
	if table_stake <= 0:
		return {"ok": true, "cost": 0, "stake": 0, "used_coupon": false}
	if not Wallet.can_afford(cost):
		return {"ok": false, "cost": cost, "stake": table_stake, "used_coupon": false}
	Wallet.spend_money(cost)
	if used_coupon:
		Inventory.remove_item(ID)
	return {
		"ok": true,
		"cost": cost,
		"stake": table_stake,
		"used_coupon": used_coupon,
	}


## Credits a win for the full table stake (ignores what was paid to enter).
static func pay_win(table_stake: int) -> int:
	var amount: int = win_payout(table_stake)
	if amount > 0:
		Wallet.add_money(amount)
	return amount
