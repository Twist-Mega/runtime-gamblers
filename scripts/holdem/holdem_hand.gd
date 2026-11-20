extends RefCounted

## Runs a Hold'em hand from the shuffle through the payout. Tracks cards, chips,
## and turn order, enforces the table's betting cap, and exposes a view for the display.

const HandRank := preload("res://scripts/holdem/holdem_hand_rank.gd")
const SEAT_COUNT := 6
const PLAYER := 0
const STARTING_STACK := 50

enum Street { IDLE, PREFLOP, FLOP, TURN, RIVER, COMPLETE }

var _street := Street.IDLE
var _hand_number := 0
var _deck: Array[int] = []
var _board: Array[int] = []
var _occupied: Array[int] = []
var _seats: Dictionary = {}
# Settled balances seed the next hand. During play, bets change _seats.
var _stacks: Dictionary = {}
var _pending: Array[int] = []
# Record the wager each seat last faced to check whether later raises reopen betting.
var _acted_at: Dictionary = {}
var _button := SEAT_COUNT - 1
var _small_blind_seat := -1
var _big_blind_seat := -1
var _posted_small_blind := 0
var _posted_big_blind := 0
var _actor := -1
var _big_blind := 0
var _cap := 0
var _current_bet := 0
var _minimum_raise := 0
var _pot := 0
var _payouts: Dictionary = {}
var _pot_results: Array[Dictionary] = []
var _refunds: Dictionary = {}
var _winning_rank := ""


## Validate the lineup and stakes, carry stacks forward, then post blinds and deal.
func start(occupied_seats: Array[int], small_blind: int, big_blind: int, cap: int) -> bool:
	if _actor >= 0 or small_blind <= 0 or big_blind <= small_blind or cap < big_blind:
		return false
	if occupied_seats.size() < 2 or not occupied_seats.has(PLAYER):
		return false
	var lineup: Array[int] = []
	for seat_id in occupied_seats:
		if seat_id < 0 or seat_id >= SEAT_COUNT or occupied_seats.count(seat_id) != 1:
			return false
		if get_seat_stack(seat_id) > 0:
			lineup.append(seat_id)
	if lineup.size() < 2 or not lineup.has(PLAYER):
		return false
	lineup.sort()
	_occupied = lineup
	_big_blind = big_blind
	_cap = cap
	_hand_number += 1
	_street = Street.PREFLOP
	_board.clear()
	_payouts.clear()
	_pot_results.clear()
	_refunds.clear()
	_acted_at.clear()
	_winning_rank = ""
	_pot = 0
	_seats.clear()
	_deck.assign(range(52))
	_deck.shuffle()
	for seat_id in _occupied:
		var cards: Array[int] = []
		_seats[seat_id] = {"cards": cards, "stack": get_seat_stack(seat_id), "bet": 0, "contribution": 0, "folded": false}

	_button = _next_seat(_occupied, _button)
	_small_blind_seat = _button if _occupied.size() == 2 else _next_seat(_occupied, _button)
	_big_blind_seat = _next_seat(_occupied, _small_blind_seat)
	_posted_small_blind = mini(small_blind, get_seat_stack(_small_blind_seat))
	_posted_big_blind = mini(big_blind, get_seat_stack(_big_blind_seat))
	_pay(_small_blind_seat, _posted_small_blind)
	_pay(_big_blind_seat, _posted_big_blind)
	_current_bet = big_blind
	_minimum_raise = big_blind
	_pending = _betting_seats()
	var recipient := _button
	for card_index in range(2):
		for seat_index in range(_occupied.size()):
			recipient = _next_seat(_occupied, recipient)
			_seats[recipient].cards.append(_deck.pop_back())
	_continue_after(_big_blind_seat)
	return true


## Return the balance available to a seat at the start of its next hand.
func get_seat_stack(seat_id: int) -> int:
	return _stacks.get(seat_id, STARTING_STACK)


## Require the player and at least one opponent to have chips to play.
func can_start_hand(seats: Array[int]) -> bool:
	if get_seat_stack(PLAYER) == 0:
		return false
	for seat_id in seats:
		if seat_id != PLAYER and get_seat_stack(seat_id) > 0:
			return true
	return false


## Return the current actor's cost to call and the allowed range for a bet or raise.
## Raise bounds are street totals. A short raise is legal only if it uses the whole stack.
func legal_actions() -> Dictionary:
	if _actor < 0:
		return {}
	var seat: Dictionary = _seats[_actor]
	var target := _call_target()
	var stack_limit: int = seat.bet + seat.stack
	var max_raise := mini(_cap, stack_limit)
	var min_raise := _current_bet + _minimum_raise
	if max_raise == stack_limit:
		min_raise = mini(min_raise, max_raise)
	var reopened := not _acted_at.has(_actor) or _current_bet - int(_acted_at[_actor]) >= _minimum_raise
	var to_call := mini(target - int(seat.bet), seat.stack)
	return {
		"to_call": maxi(0, to_call),
		"min_raise_to": min_raise,
		"max_raise_to": max_raise,
		"can_wager": reopened and _betting_seats().size() > 1 and max_raise > _current_bet and min_raise <= max_raise,
		"all_in_call": to_call > 0 and to_call == seat.stack,
		"all_in_to": stack_limit,
		"opening_bet": _current_bet == 0,
	}


## Apply a legal action for the current actor, then pass the turn, advance the street,
## or award the pot. A bet or raise gives every other live seat another turn to respond.
func act(seat_id: int, action: String, raise_to: int = 0) -> bool:
	if _actor < 0 or seat_id != _actor:
		return false
	var legal := legal_actions()
	match action:
		"fold":
			if legal.to_call == 0:
				return false
			_seats[seat_id].folded = true
		"check":
			if legal.to_call != 0:
				return false
		"call":
			if legal.to_call == 0:
				return false
			_pay(seat_id, legal.to_call)
		"wager":
			if not legal.can_wager or raise_to < legal.min_raise_to or raise_to > legal.max_raise_to:
				return false
			_pay(seat_id, raise_to - _seats[seat_id].bet)
			_minimum_raise = maxi(_minimum_raise, raise_to - _current_bet)
			_current_bet = raise_to
			_pending = _betting_seats()
		_:
			return false
	_pending.erase(seat_id)
	# Checking an unopened street preserves the right to raise a later bet.
	if _current_bet > 0:
		_acted_at[seat_id] = _current_bet
	_continue_after(seat_id)
	return true


## Give the acting NPC its own cards, the full bet to match, and legal wagers.
func get_preflop_turn(seat_id: int) -> Dictionary:
	if _street != Street.PREFLOP or seat_id != _actor or seat_id <= PLAYER:
		return {}
	return {
		"cards": _seats[seat_id].cards.duplicate(),
		"big_blind": _big_blind,
		"bet_to_match": _call_target(),
		"legal": legal_actions(),
	}


## Copy a seat's dealt cards for the standalone display's optional reveal setting.
func get_debug_hole_cards(seat_id: int) -> Array[int]:
	var cards: Array[int] = []
	if _seats.has(seat_id):
		cards.assign(_seats[seat_id].cards)
	return cards


## Copy the table state for the display. Show the player's cards and reveal live NPC
## hands at showdown. Card counts let the display draw backs for concealed cards.
func get_view() -> Dictionary:
	var seats: Dictionary = {}
	for seat_id in _occupied:
		var seat: Dictionary = _seats[seat_id]
		var visible_cards: Array[int] = []
		if seat_id == PLAYER or (not _winning_rank.is_empty() and not seat.folded):
			visible_cards.assign(seat.cards)
		seats[seat_id] = {
			"cards": visible_cards,
			"card_count": 0 if seat.folded and seat_id != PLAYER else seat.cards.size(),
			"stack": seat.stack,
			"bet": seat.bet,
			"folded": seat.folded,
			"all_in": _street != Street.COMPLETE and seat.stack == 0,
		}
	return {
		"hand_number": _hand_number,
		"street": _street,
		"board": _board.duplicate(),
		"pot": _pot,
		"seats": seats,
		"button": _button if _hand_number > 0 else -1,
		"small_blind_seat": _small_blind_seat,
		"big_blind_seat": _big_blind_seat,
		"posted_small_blind": _posted_small_blind,
		"posted_big_blind": _posted_big_blind,
		"actor": _actor,
		"payouts": _payouts.duplicate(),
		"pot_results": _pot_results.duplicate(true),
		"refunds": _refunds.duplicate(),
		"winning_rank": _winning_rank,
	}


## Walk clockwise through a sorted, nonempty list of seats and wrap at the end.
func _next_seat(seats: Array[int], after: int) -> int:
	for seat_id in seats:
		if seat_id > after:
			return seat_id
	return seats[0]


## Return the occupied seats that are still in the hand.
func _live_seats() -> Array[int]:
	var live: Array[int] = []
	for seat_id in _occupied:
		if not _seats[seat_id].folded:
			live.append(seat_id)
	return live


## List the live seats that still have chips available to wager.
func _betting_seats() -> Array[int]:
	var seats: Array[int] = []
	for seat_id in _live_seats():
		if _seats[seat_id].stack > 0:
			seats.append(seat_id)
	return seats


## Use actual wagers when there is nobody left who can match the nominal big blind.
func _call_target() -> int:
	if _betting_seats().size() > 1:
		return _current_bet
	var target := 0
	for seat_id in _live_seats():
		target = maxi(target, _seats[seat_id].bet)
	return target


## Skip all-in seats and run out the board once no further betting is possible.
func _continue_after(seat_id: int) -> void:
	var live := _live_seats()
	if live.size() == 1:
		_settle({live[0]: 0})
		return
	var betting := _betting_seats()
	if betting.size() < 2:
		_pending.clear()
		if betting.size() == 1 and _seats[betting[0]].bet < _call_target():
			_pending.append(betting[0])
	if _pending.is_empty():
		_advance_street(live)
	else:
		_actor = _next_seat(_pending, seat_id)


## Move chips from a seat's stack into the pot and record its contribution this street.
func _pay(seat_id: int, amount: int) -> void:
	_seats[seat_id].stack -= amount
	_seats[seat_id].bet += amount
	_seats[seat_id].contribution += amount
	_pot += amount


## Burn and deal the next board cards, then reset street betting. After the river,
## send the remaining players to showdown.
func _advance_street(live: Array[int]) -> void:
	if _street == Street.RIVER:
		_showdown(live)
		return
	_deck.pop_back() # Burn one card before each community deal.
	var deal_count := 3 if _street == Street.PREFLOP else 1
	for card_index in range(deal_count):
		_board.append(_deck.pop_back())
	_street += 1
	for seat_id in _occupied:
		_seats[seat_id].bet = 0
	_current_bet = 0
	_minimum_raise = _big_blind
	_acted_at.clear()
	_pending = _betting_seats()
	_continue_after(_button)


## Score each remaining player's seven cards for use in all pots they can win.
func _showdown(live: Array[int]) -> void:
	var scores: Dictionary = {}
	var best := -1
	for seat_id in live:
		var cards := _board.duplicate()
		cards.append_array(_seats[seat_id].cards)
		var score := HandRank.best_of_seven(cards)
		scores[seat_id] = score
		best = maxi(best, score)
	_winning_rank = HandRank.category_name(best)
	_settle(scores)


## Build pots from contribution levels, return unmatched chips, and finish the hand.
func _settle(scores: Dictionary) -> void:
	var levels: Array[int] = []
	for seat_id in _occupied:
		var total: int = _seats[seat_id].contribution
		if total > 0 and not levels.has(total):
			levels.append(total)
	levels.sort()
	var lower := 0
	var pots: Array[Dictionary] = []
	# Each tier counts only the chips between two contribution levels. Folded
	# seats still fund the tier, and the showdown scores determine eligibility.
	for level in levels:
		var contributors: Array[int] = []
		var eligible: Array[int] = []
		for seat_id in _occupied:
			if _seats[seat_id].contribution >= level:
				contributors.append(seat_id)
				if scores.has(seat_id):
					eligible.append(seat_id)
		var amount := (level - lower) * contributors.size()
		lower = level
		if contributors.size() == 1:
			var recipient := contributors[0]
			_seats[recipient].stack += amount
			_refunds[recipient] = amount
		elif not pots.is_empty() and pots.back().eligible == eligible:
			pots.back().amount += amount
		else:
			pots.append({"amount": amount, "eligible": eligible})
	for pot in pots:
		var winners: Array[int] = []
		var best := -1
		for seat_id in pot.eligible:
			var score: int = scores[seat_id]
			if score > best:
				best = score
				winners.clear()
			if score == best:
				winners.append(seat_id)
		# A player can win uncontested even if they contributed zero before the folds.
		if winners.is_empty() and scores.size() == 1:
			winners.assign(scores.keys())
		_award_pot(pot.amount, winners)
	for seat_id in _occupied:
		_seats[seat_id].bet = 0
		_stacks[seat_id] = _seats[seat_id].stack
	_pot = 0
	_actor = -1
	_street = Street.COMPLETE


## Split one pot among its winners, giving odd chips clockwise from the button.
func _award_pot(amount: int, winners: Array[int]) -> void:
	@warning_ignore("integer_division")
	var share := amount / winners.size()
	var extra_chips := amount % winners.size()
	var winner := _button
	var paid: Dictionary = {}
	# Split pots start left of the button for any indivisible chip.
	for index in range(winners.size()):
		winner = _next_seat(winners, winner)
		var payout := share + int(index < extra_chips)
		_seats[winner].stack += payout
		_payouts[winner] = _payouts.get(winner, 0) + payout
		paid[winner] = payout
	_pot_results.append({"amount": amount, "payouts": paid})
