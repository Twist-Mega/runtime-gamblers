class_name BlackjackEngine
extends RefCounted
## One round of blackjack, independent of scenes, input, money storage, and animation.
## Commands return copied public state and ordered events; they never emit callbacks.

enum Phase { BETTING, DEALING, PLAYER_TURN, DEALER_TURN, SETTLED }

const SUITS = ["clubs", "diamonds", "hearts", "spades"]
const PLAYER_SEAT = "player"
const DEALER_SEAT = "dealer"
# Largest wager whose rounded blackjack return fits in a signed 64-bit integer.
const MAX_WAGER: int = 3_689_348_814_741_910_322

var _rng := RandomNumberGenerator.new()
var _phase: Phase = Phase.BETTING
var _round_id: int = 0
var _event_sequence: int = 0
var _wager: int = 0
var _deck: Array[Dictionary] = []
var _draw_index: int = 0
var _player_cards: Array[Dictionary] = []
var _dealer_cards: Array[Dictionary] = []
var _dealer_revealed: bool = false
var _result: Dictionary = {}


## Supply an integer seed for repeatable shuffles, or omit it for random play.
func _init(random_seed: Variant = null) -> void:
	if random_seed == null:
		_rng.randomize()
	else:
		_rng.seed = int(random_seed)


## deck_order, when provided, must contain all 52 unique rank/suit pairs.
## Its first entry is drawn first. An empty array requests a fresh shuffled deck.
func begin_round(wager: int, deck_order: Array = []) -> Dictionary:
	if _phase != Phase.BETTING and _phase != Phase.SETTLED:
		return _reject("invalid_phase", "Finish the active round before starting another.")
	if wager <= 0 or wager > MAX_WAGER:
		return _reject("invalid_wager", "Wager must be between 1 and %d." % MAX_WAGER)
	if not deck_order.is_empty():
		var deck_error := _validate_deck(deck_order)
		if not deck_error.is_empty():
			return _reject("invalid_deck", deck_error)

	# Validate first, so rejected starts preserve the previous round and RNG state.
	_deck = _make_deck() if deck_order.is_empty() else _copy_deck(deck_order)
	if deck_order.is_empty():
		_shuffle_deck()
	_draw_index = 0
	_player_cards = []
	_dealer_cards = []
	_dealer_revealed = false
	_result = {}
	_wager = wager
	_round_id += 1
	_event_sequence = 0

	var events: Array[Dictionary] = []
	_emit(events, "round_started", {"wager": _wager})
	_change_phase(Phase.DEALING, events)
	_deal_card(PLAYER_SEAT, events)
	_deal_card(DEALER_SEAT, events)
	_deal_card(PLAYER_SEAT, events)
	_deal_card(DEALER_SEAT, events)

	var player_score := _score_hand(_player_cards)
	var dealer_score := _score_hand(_dealer_cards)
	if player_score.is_blackjack or dealer_score.is_blackjack:
		_reveal_dealer(events)
		if player_score.is_blackjack and dealer_score.is_blackjack:
			_settle("push", "both_blackjack", events)
		elif player_score.is_blackjack:
			_settle("blackjack", "player_blackjack", events)
		else:
			_settle("loss", "dealer_blackjack", events)
	else:
		_change_phase(Phase.PLAYER_TURN, events)
	return _accept(events)


func hit() -> Dictionary:
	if _phase != Phase.PLAYER_TURN:
		return _reject("invalid_phase", "Hit is only available during the player's turn.")
	var events: Array[Dictionary] = []
	_action(PLAYER_SEAT, "hit", false, events)
	_deal_card(PLAYER_SEAT, events)
	var score := _score_hand(_player_cards)
	if score.is_bust:
		_reveal_dealer(events)
		_settle("loss", "player_bust", events)
	elif score.total == 21:
		_action(PLAYER_SEAT, "stand", true, events)
		_play_dealer(events)
	return _accept(events)


func stand() -> Dictionary:
	if _phase != Phase.PLAYER_TURN:
		return _reject("invalid_phase", "Stand is only available during the player's turn.")
	var events: Array[Dictionary] = []
	_action(PLAYER_SEAT, "stand", false, events)
	_play_dealer(events)
	return _accept(events)


## Dealer totals/flags are null while a card is hidden. visible_total is safe to show.
func get_public_state() -> Dictionary:
	var actions: Array[String] = []
	if _phase == Phase.PLAYER_TURN:
		actions.assign(["hit", "stand"])
	elif _phase == Phase.BETTING or _phase == Phase.SETTLED:
		actions.assign(["begin_round"])
	return {
		"round_id": _round_id,
		"phase": Phase.keys()[_phase],
		"wager": _wager,
		"active_seat_id": PLAYER_SEAT if _phase == Phase.PLAYER_TURN else null,
		"legal_actions": actions,
		"seats": [
			{"seat_id": PLAYER_SEAT, "role": "player", "hands": [_public_hand(PLAYER_SEAT)]},
			{"seat_id": DEALER_SEAT, "role": "dealer", "hands": [_public_hand(DEALER_SEAT)]},
		],
		"result": _result.duplicate(true) if not _result.is_empty() else null,
	}


func _make_deck() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for suit in SUITS:
		for rank in range(1, 14):
			cards.append(_make_card(rank, suit))
	return cards


func _make_card(rank: int, suit: String) -> Dictionary:
	return {"rank": rank, "suit": suit, "card_id": "%s_%d" % [suit, rank]}


func _copy_deck(cards: Array) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for card in cards:
		copied.append(_make_card(card.rank, card.suit))
	return copied


func _validate_deck(cards: Array) -> String:
	if cards.size() != 52:
		return "A fixed deck must contain exactly 52 cards."
	var seen: Dictionary = {}
	for card in cards:
		if not card is Dictionary:
			return "Each card must be a dictionary containing rank and suit."
		if not card.get("rank") is int or card.rank < 1 or card.rank > 13:
			return "Card ranks must be integers from 1 (ace) through 13 (king)."
		if not card.get("suit") is String or card.suit not in SUITS:
			return "Card suits must be clubs, diamonds, hearts, or spades."
		var card_id := "%s_%d" % [card.suit, card.rank]
		if seen.has(card_id):
			return "A fixed deck cannot contain duplicate cards."
		seen[card_id] = true
	return ""


func _shuffle_deck() -> void:
	# Fisher-Yates uses this engine's RNG, leaving Godot's global RNG untouched.
	for index in range(_deck.size() - 1, 0, -1):
		var other_index := _rng.randi_range(0, index)
		var card := _deck[index]
		_deck[index] = _deck[other_index]
		_deck[other_index] = card


func _score_hand(cards: Array[Dictionary]) -> Dictionary:
	var total: int = 0
	var high_aces: int = 0
	for card in cards:
		if card.rank == 1:
			total += 11
			high_aces += 1
		else:
			total += mini(card.rank, 10)
	while total > 21 and high_aces > 0:
		total -= 10
		high_aces -= 1
	return {
		"total": total,
		"is_soft": high_aces > 0,
		"is_blackjack": cards.size() == 2 and total == 21,
		"is_bust": total > 21,
	}


func _hand_id(seat_id: String) -> String:
	return "%d:%s:0" % [_round_id, seat_id]


func _public_card(card: Dictionary, face_up: bool) -> Dictionary:
	if not face_up:
		# Even card_id would reveal the hidden rank/suit, so omit it entirely.
		return {"face_up": false}
	var visible := card.duplicate(true)
	visible["face_up"] = true
	return visible


func _public_hand(seat_id: String) -> Dictionary:
	var cards := _player_cards if seat_id == PLAYER_SEAT else _dealer_cards
	var public_cards: Array[Dictionary] = []
	var visible_cards: Array[Dictionary] = []
	var has_hidden_card: bool = false
	for index in range(cards.size()):
		var face_up := seat_id != DEALER_SEAT or index != 1 or _dealer_revealed
		public_cards.append(_public_card(cards[index], face_up))
		if face_up:
			visible_cards.append(cards[index])
		else:
			has_hidden_card = true
	var visible_score := _score_hand(visible_cards)
	return {
		"hand_id": _hand_id(seat_id),
		"cards": public_cards,
		"visible_total": visible_score.total,
		"total": null if has_hidden_card else visible_score.total,
		"is_soft": null if has_hidden_card else visible_score.is_soft,
		"is_blackjack": null if has_hidden_card else visible_score.is_blackjack,
		"is_bust": null if has_hidden_card else visible_score.is_bust,
	}


func _deal_card(seat_id: String, events: Array[Dictionary]) -> void:
	var cards := _player_cards if seat_id == PLAYER_SEAT else _dealer_cards
	var card := _deck[_draw_index]
	_draw_index += 1
	var card_index := cards.size()
	cards.append(card)
	var face_up := seat_id != DEALER_SEAT or card_index != 1 or _dealer_revealed
	_emit(events, "card_dealt", {
		"seat_id": seat_id,
		"hand_id": _hand_id(seat_id),
		"card_index": card_index,
		"card": _public_card(card, face_up),
	})


func _reveal_dealer(events: Array[Dictionary]) -> void:
	if _dealer_revealed:
		return
	_dealer_revealed = true
	_emit(events, "dealer_card_revealed", {
		"seat_id": DEALER_SEAT,
		"hand_id": _hand_id(DEALER_SEAT),
		"card_index": 1,
		"card": _public_card(_dealer_cards[1], true),
	})


func _play_dealer(events: Array[Dictionary]) -> void:
	_change_phase(Phase.DEALER_TURN, events)
	_reveal_dealer(events)
	var dealer_score := _score_hand(_dealer_cards)
	while dealer_score.total < 17:
		_action(DEALER_SEAT, "hit", true, events)
		_deal_card(DEALER_SEAT, events)
		dealer_score = _score_hand(_dealer_cards)
	if dealer_score.is_bust:
		_settle("win", "dealer_bust", events)
		return
	_action(DEALER_SEAT, "stand", true, events)
	var player_score := _score_hand(_player_cards)
	if player_score.total > dealer_score.total:
		_settle("win", "higher_total", events)
	elif player_score.total < dealer_score.total:
		_settle("loss", "lower_total", events)
	else:
		_settle("push", "equal_total", events)


func _settle(outcome: String, reason: String, events: Array[Dictionary]) -> void:
	var returned_amount: int = 0
	match outcome:
		"win":
			returned_amount = _wager * 2
		"push":
			returned_amount = _wager
		"blackjack":
			# Stake + ceil(3 * stake / 2), with exact integer arithmetic.
			@warning_ignore("integer_division")
			returned_amount = _wager * 2 + _wager / 2 + _wager % 2
	_result = {
		"round_id": _round_id,
		"outcome": outcome,
		"reason": reason,
		"wager": _wager,
		"returned_amount": returned_amount,
		"net_change": returned_amount - _wager,
		"player_total": _score_hand(_player_cards).total,
		"dealer_total": _score_hand(_dealer_cards).total,
	}
	_change_phase(Phase.SETTLED, events)
	_emit(events, "round_finished", {"result": _result})


func _change_phase(phase: Phase, events: Array[Dictionary]) -> void:
	_phase = phase
	_emit(events, "phase_changed", {"phase": Phase.keys()[_phase]})


func _action(seat_id: String, action: String, automatic: bool, events: Array[Dictionary]) -> void:
	_emit(events, "action_taken", {
		"seat_id": seat_id,
		"hand_id": _hand_id(seat_id),
		"action": action,
		"automatic": automatic,
	})


func _emit(events: Array[Dictionary], type: String, payload: Dictionary) -> void:
	_event_sequence += 1
	var event := payload.duplicate(true)
	event.merge({"type": type, "round_id": _round_id, "sequence": _event_sequence})
	events.append(event)


func _accept(events: Array[Dictionary]) -> Dictionary:
	return {
		"accepted": true,
		"error": null,
		"state": get_public_state(),
		"events": events,
		"result": _result.duplicate(true) if not _result.is_empty() else null,
	}


func _reject(code: String, message: String) -> Dictionary:
	return {
		"accepted": false,
		"error": {"code": code, "message": message},
		"state": get_public_state(),
		"events": [],
		# Rejections never return a new settlement for a caller to apply.
		"result": null,
	}
