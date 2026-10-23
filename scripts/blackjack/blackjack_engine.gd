class_name BlackjackEngine
extends RefCounted
## One round of blackjack, independent of scenes, input, money storage, and animation.
## Commands return copied public state and ordered events; they never emit callbacks.

enum Phase { BETTING, DEALING, PLAYER_TURN, AI_TURN, DEALER_TURN, SETTLED }

const SUITS = ["clubs", "diamonds", "hearts", "spades"]
const PLAYER_SEAT = "player"
const DEALER_SEAT = "dealer"
const AI_SEATS = ["left_2", "left_1", "right_1", "right_2"]
const SEAT_ORDER = ["left_2", "left_1", "player", "right_1", "right_2"]
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
var _ai_seats: Array = []
var _order: Array[String] = []
var _ai_cards: Dictionary = {}
var _seat_results: Dictionary = {}
var _stood: Dictionary = {}
var _turn_index: int = -1
var _active_seat: String = ""


## Supply an integer seed for repeatable shuffles, or omit it for random play.
func _init(random_seed: Variant = null, occupied_ai_seats: Array = []) -> void:
	_ai_seats = occupied_ai_seats.duplicate(true)
	for seat_id in SEAT_ORDER:
		if seat_id == PLAYER_SEAT or seat_id in _ai_seats:
			_order.append(seat_id)
	for seat_id in AI_SEATS:
		_ai_cards[seat_id] = []
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
	var seats_error := validate_ai_seats(_ai_seats)
	if not seats_error.is_empty():
		return _reject("invalid_seats", seats_error)
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
	_seat_results = {}
	_stood = {}
	_turn_index = -1
	_active_seat = ""
	for seat_id in AI_SEATS:
		_ai_cards[seat_id] = []
	_wager = wager
	_round_id += 1
	_event_sequence = 0

	var events: Array[Dictionary] = []
	_emit(events, "round_started", {"wager": _wager})
	_change_phase(Phase.DEALING, events)
	for pass_index in range(2):
		for seat_id in _order:
			_deal_card(seat_id, events)
		_deal_card(DEALER_SEAT, events)

	var dealer_score := _score_hand(_dealer_cards)
	if dealer_score.is_blackjack:
		_reveal_dealer(events)
		for seat_id in _order:
			if _score_hand(_cards_for(seat_id)).is_blackjack:
				_settle_seat(seat_id, "push", "both_blackjack", events)
			else:
				_settle_seat(seat_id, "loss", "dealer_blackjack", events)
		_finish_round(events)
	else:
		# Only the outcome of the peek is used. The hole card remains private.
		for seat_id in _order:
			if _score_hand(_cards_for(seat_id)).is_blackjack:
				_settle_seat(seat_id, "blackjack", "player_blackjack", events)
		_next_turn(events)
	return _accept(events)


func hit() -> Dictionary:
	if _phase != Phase.PLAYER_TURN:
		return _reject("invalid_phase", "Hit is only available during the player's turn.")
	var events: Array[Dictionary] = []
	_action(PLAYER_SEAT, "hit", false, events)
	_deal_card(PLAYER_SEAT, events)
	var score := _score_hand(_player_cards)
	if score.is_bust:
		_settle_seat(PLAYER_SEAT, "loss", "player_bust", events)
		_next_turn(events)
	elif score.total == 21:
		_action(PLAYER_SEAT, "stand", true, events)
		_stood[PLAYER_SEAT] = true
		_next_turn(events)
	return _accept(events)


func stand() -> Dictionary:
	if _phase != Phase.PLAYER_TURN:
		return _reject("invalid_phase", "Stand is only available during the player's turn.")
	var events: Array[Dictionary] = []
	_action(PLAYER_SEAT, "stand", false, events)
	_stood[PLAYER_SEAT] = true
	_next_turn(events)
	return _accept(events)


## One automatic AI decision, or the dealer's complete turn. No timers or UI.
func advance_table() -> Dictionary:
	if _phase != Phase.AI_TURN and _phase != Phase.DEALER_TURN:
		return _reject("invalid_phase", "The table only advances during an automatic turn.")
	var events: Array[Dictionary] = []
	if _phase == Phase.DEALER_TURN:
		_play_dealer(events)
	else:
		var seat_id := _active_seat
		var score := _score_hand(_cards_for(seat_id))
		if score.total < 17:
			_action(seat_id, "hit", true, events)
			_deal_card(seat_id, events)
			score = _score_hand(_cards_for(seat_id))
			if score.is_bust:
				_settle_seat(seat_id, "loss", "player_bust", events)
				_next_turn(events)
			elif score.total == 21:
				_action(seat_id, "stand", true, events)
				_stood[seat_id] = true
				_next_turn(events)
		else:
			_action(seat_id, "stand", true, events)
			_stood[seat_id] = true
			_next_turn(events)
	return _accept(events)


static func validate_ai_seats(seats: Variant) -> String:
	if not seats is Array:
		return "ai_seats must be an array of seat IDs."
	var seen: Dictionary = {}
	for seat_id in seats:
		if not seat_id is String or seat_id not in AI_SEATS or seen.has(seat_id):
			return "AI seats must be unique IDs from left_2, left_1, right_1, right_2."
		seen[seat_id] = true
	return ""


func _next_turn(events: Array[Dictionary]) -> void:
	_turn_index += 1
	while _turn_index < _order.size():
		_active_seat = _order[_turn_index]
		if not _seat_results.has(_active_seat):
			_change_phase(Phase.PLAYER_TURN if _active_seat == PLAYER_SEAT else Phase.AI_TURN, events)
			return
		_turn_index += 1
	_active_seat = DEALER_SEAT
	if _seat_results.size() == _order.size():
		_finish_round(events)
	elif _ai_seats.is_empty():
		# Preserve the single-player API: Stand resolves the dealer synchronously.
		_play_dealer(events)
	else:
		_change_phase(Phase.DEALER_TURN, events)


func _cards_for(seat_id: String) -> Array:
	if seat_id == PLAYER_SEAT:
		return _player_cards
	if seat_id == DEALER_SEAT:
		return _dealer_cards
	return _ai_cards.get(seat_id, [])


## Dealer totals/flags are null while a card is hidden. visible_total is safe to show.
func get_public_state() -> Dictionary:
	var actions: Array[String] = []
	if _phase == Phase.PLAYER_TURN:
		actions.assign(["hit", "stand"])
	elif _phase == Phase.AI_TURN or _phase == Phase.DEALER_TURN:
		actions.assign(["advance_table"])
	elif _phase == Phase.BETTING or _phase == Phase.SETTLED:
		actions.assign(["begin_round"])
	var seats: Array[Dictionary] = []
	# Keep the original player/dealer entries first for existing consumers.
	for seat_id in [PLAYER_SEAT, DEALER_SEAT] + AI_SEATS:
		var occupied: bool = seat_id in _order or seat_id == DEALER_SEAT
		var result: Variant = _seat_results.get(seat_id)
		var status := "EMPTY" if not occupied else "WAITING"
		if seat_id == DEALER_SEAT and _phase == Phase.SETTLED:
			var score := _score_hand(_dealer_cards)
			status = "BUST" if score.is_bust else "BLACKJACK" if score.is_blackjack else "FINISHED"
		if _stood.has(seat_id):
			status = "STOOD"
		if seat_id == _active_seat:
			status = "PLAYING"
		if result != null:
			status = "BUST" if result.reason == "player_bust" else result.outcome.to_upper()
		seats.append({"seat_id": seat_id, "role": "dealer" if seat_id == DEALER_SEAT else "player" if seat_id == PLAYER_SEAT else "ai",
			"occupied": occupied, "status": status, "hands": [_public_hand(seat_id)],
			"result": result.duplicate(true) if result != null else null})
	return {
		"round_id": _round_id,
		"phase": Phase.keys()[_phase],
		"wager": _wager,
		"active_seat_id": _active_seat if not _active_seat.is_empty() else null,
		"legal_actions": actions,
		"seats": seats,
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


func _score_hand(cards: Array) -> Dictionary:
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
	var cards := _cards_for(seat_id)
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
	var cards := _cards_for(seat_id)
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
	_active_seat = DEALER_SEAT
	if _phase != Phase.DEALER_TURN:
		_change_phase(Phase.DEALER_TURN, events)
	_reveal_dealer(events)
	var dealer_score := _score_hand(_dealer_cards)
	while dealer_score.total < 17:
		_action(DEALER_SEAT, "hit", true, events)
		_deal_card(DEALER_SEAT, events)
		dealer_score = _score_hand(_dealer_cards)
	if not dealer_score.is_bust:
		_action(DEALER_SEAT, "stand", true, events)
	for seat_id in _order:
		if _seat_results.has(seat_id):
			continue
		var score := _score_hand(_cards_for(seat_id))
		if dealer_score.is_bust:
			_settle_seat(seat_id, "win", "dealer_bust", events)
		elif score.total > dealer_score.total:
			_settle_seat(seat_id, "win", "higher_total", events)
		elif score.total < dealer_score.total:
			_settle_seat(seat_id, "loss", "lower_total", events)
		else:
			_settle_seat(seat_id, "push", "equal_total", events)
	_finish_round(events)


func _settle_seat(seat_id: String, outcome: String, reason: String, events: Array[Dictionary]) -> void:
	if _seat_results.has(seat_id):
		return
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
	var result := {
		"round_id": _round_id,
		"seat_id": seat_id,
		"outcome": outcome,
		"reason": reason,
		"wager": _wager,
		"returned_amount": returned_amount,
		"net_change": returned_amount - _wager,
		"player_total": _score_hand(_cards_for(seat_id)).total,
		"dealer_total": _score_hand(_dealer_cards).total if _dealer_revealed else null,
	}
	_seat_results[seat_id] = result
	if seat_id == PLAYER_SEAT:
		_result = result
	_emit(events, "seat_settled", {"seat_id": seat_id, "result": result})


func _finish_round(events: Array[Dictionary]) -> void:
	_reveal_dealer(events)
	for result in _seat_results.values():
		result.dealer_total = _score_hand(_dealer_cards).total
	_active_seat = ""
	_change_phase(Phase.SETTLED, events)
	_emit(events, "round_finished", {"result": _result})


func _change_phase(phase: Phase, events: Array[Dictionary]) -> void:
	_phase = phase
	_emit(events, "phase_changed", {"phase": Phase.keys()[_phase], "active_seat_id": _active_seat})


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
