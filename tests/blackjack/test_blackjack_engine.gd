extends SceneTree
## Dependency-free headless runner. Any assertion or incomplete test exits nonzero.

const Blackjack = preload("res://scripts/blackjack/blackjack_engine.gd")

var _failures: int = 0
var _checks: int = 0
var _current_test: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_names: Array[String] = []
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			test_names.append(method.name)
	test_names.sort()
	for test_name in test_names:
		_current_test = test_name
		var failures_before := _failures
		var completed: Variant = call(test_name)
		_check(completed is bool and completed == true, "Test reached its end without a runtime error")
		print("%s %s" % ["PASS" if _failures == failures_before else "FAIL", test_name])
	print("Blackjack: %d tests, %d checks, %d failures." % [test_names.size(), _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("%s: %s" % [_current_test, message])


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _card(rank: int, suit: String = "clubs") -> Dictionary:
	return {"rank": rank, "suit": suit}


# Prefixes make scenarios readable; fill the rest with every unused standard card.
func _deck(prefix: Array = []) -> Array:
	var cards := prefix.duplicate(true)
	for suit in ["clubs", "diamonds", "hearts", "spades"]:
		for rank in range(1, 14):
			var card := _card(rank, suit)
			if card not in cards:
				cards.append(card)
	return cards


func _started(prefix: Array, wager: int = 5) -> RefCounted:
	var engine := Blackjack.new(42)
	var command: Dictionary = engine.begin_round(wager, _deck(prefix))
	_check(command.accepted, "Fixture starts successfully: %s" % str(command.error))
	return engine


func _hand(state: Dictionary, seat_id: String = "player") -> Dictionary:
	for seat in state.seats:
		if seat.seat_id == seat_id:
			return seat.hands[0]
	return {}


func _events_of(command: Dictionary, type: String) -> Array:
	var found: Array = []
	for event in command.events:
		if event.type == type:
			found.append(event)
	return found


func _assert_rejected(engine: RefCounted, command: Dictionary, before: Dictionary, code: String) -> void:
	_equal(command.accepted, false, "Command rejected")
	_equal(command.error.code, code, "Error code")
	_equal(command.events, [], "Rejected command emits no events")
	_equal(command.result, null, "Rejected command produces no settlement")
	_equal(command.state, before, "Returned state is unchanged")
	_equal(engine.get_public_state(), before, "Engine state is unchanged")


func test_initial_state_and_actions_before_deal() -> bool:
	var engine := Blackjack.new()
	var state := engine.get_public_state()
	_equal(state.phase, "BETTING", "Initial phase")
	_equal(state.round_id, 0, "No round started")
	_equal(state.legal_actions, ["begin_round"], "Initial legal command")
	_equal(state.result, null, "No initial result")
	_equal(_hand(state).cards, [], "Player has no cards")
	_assert_rejected(engine, engine.hit(), state, "invalid_phase")
	_assert_rejected(engine, engine.stand(), state, "invalid_phase")
	return true


func test_initial_deal_order_and_visible_totals() -> bool:
	var engine := Blackjack.new()
	var command := engine.begin_round(5, _deck([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")]))
	_equal(command.accepted, true, "Start accepted")
	_equal(command.error, null, "Successful command has no error")
	_equal(command.state.phase, "PLAYER_TURN", "Player acts after dealing")
	_equal(command.state.active_seat_id, "player", "Player is active")
	_equal(command.state.legal_actions, ["hit", "stand"], "Player actions")
	_equal(_hand(command.state).total, 18, "Player total")
	_equal(_hand(command.state, "dealer").visible_total, 9, "Only upcard is counted publicly")
	var deals := _events_of(command, "card_dealt")
	_equal(deals.size(), 4, "Four initial deals")
	var seats: Array = []
	var positions: Array = []
	for event in deals:
		seats.append(event.seat_id)
		positions.append(event.card_index)
		_equal(event.hand_id, _hand(command.state, event.seat_id).hand_id, "Event targets a stable hand")
	_equal(seats, ["player", "dealer", "player", "dealer"], "Alternating deal order")
	_equal(positions, [0, 0, 1, 1], "Card positions within hands")
	return true


func test_hidden_card_does_not_leak_through_state_or_events() -> bool:
	var engine := Blackjack.new()
	var command := engine.begin_round(5, _deck([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds"), _card(2, "hearts")]))
	var dealer := _hand(command.state, "dealer")
	_equal(dealer.cards[1], {"face_up": false}, "Hidden card has no identity or metadata")
	for field in ["total", "is_soft", "is_blackjack", "is_bust"]:
		_equal(dealer[field], null, "Hidden full-hand field: %s" % field)
	_equal(_events_of(command, "card_dealt")[3].card, {"face_up": false}, "Deal event also conceals card")
	command = engine.hit()
	_equal(command.state.phase, "PLAYER_TURN", "Player can continue below 21")
	_equal(_hand(command.state, "dealer").cards[1], {"face_up": false}, "Hit does not reveal dealer")
	_equal(_events_of(command, "dealer_card_revealed").size(), 0, "No reveal while player acts")
	command = engine.stand()
	_equal(_hand(command.state, "dealer").total, 17, "Full total available after reveal")
	_equal(_events_of(command, "dealer_card_revealed")[0].card.rank, 8, "Reveal identifies hole card")
	return true


func test_face_cards_count_as_ten() -> bool:
	for rank in [11, 12, 13]:
		var engine := _started([_card(rank), _card(9, "diamonds"), _card(8), _card(8, "diamonds")])
		_equal(_hand(engine.get_public_state()).total, 18, "Face-card value for rank %d" % rank)
	return true


func test_ace_changes_from_soft_to_hard_after_hit() -> bool:
	var engine := _started([_card(1), _card(9, "diamonds"), _card(6), _card(8, "diamonds"), _card(10, "hearts")])
	_equal(_hand(engine.get_public_state()).total, 17, "Ace starts as 11")
	_equal(_hand(engine.get_public_state()).is_soft, true, "Initial soft hand")
	var command: Dictionary = engine.hit()
	_equal(_hand(command.state).total, 17, "Ace reduces to 1 after drawing ten")
	_equal(_hand(command.state).is_soft, false, "Hand becomes hard")
	_equal(command.state.phase, "PLAYER_TURN", "Ace adjustment prevents bust")
	return true


func test_multiple_aces_adjust_without_premature_bust() -> bool:
	var engine := _started([_card(1), _card(10, "diamonds"), _card(1, "diamonds"), _card(7, "diamonds"), _card(1, "hearts"), _card(9)])
	_equal(_hand(engine.get_public_state()).total, 12, "Two aces score 12")
	var command: Dictionary = engine.hit()
	_equal(_hand(command.state).total, 13, "Three aces score 13")
	_equal(_hand(command.state).is_soft, true, "One ace still counts as 11")
	command = engine.hit()
	_equal(_hand(command.state).total, 12, "All three aces reduce after nine")
	_equal(_hand(command.state).is_soft, false, "All aces now count as 1")
	_equal(command.state.phase, "PLAYER_TURN", "Multiple aces do not bust")
	return true


func test_player_natural_settles_immediately() -> bool:
	var engine := Blackjack.new()
	var command := engine.begin_round(10, _deck([_card(1), _card(9, "diamonds"), _card(13), _card(8, "diamonds")]))
	_equal(command.state.phase, "SETTLED", "Natural skips player turn")
	_equal(command.result.outcome, "blackjack", "Natural outcome")
	_equal(command.result.returned_amount, 25, "Even stake pays exact 3:2 plus stake")
	_equal(command.result.net_change, 15, "Natural profit")
	_equal(_events_of(command, "card_dealt").size(), 4, "Dealer does not draw after player natural")
	_equal(_events_of(command, "dealer_card_revealed").size(), 1, "Hole card revealed at settlement")
	return true


func test_odd_natural_payouts_round_up_using_exact_integers() -> bool:
	var cases := [
		[1, 3], [3, 8], [5, 13], [7, 18], [9, 23], [11, 28], [1001, 2503],
		[9_007_199_254_740_993, 22_517_998_136_852_483],
		[Blackjack.MAX_WAGER, 9_223_372_036_854_775_805],
	]
	for item in cases:
		var engine := _started([_card(1), _card(9, "diamonds"), _card(13), _card(8, "diamonds")], item[0])
		var result: Dictionary = engine.get_public_state().result
		_equal(result.returned_amount, item[1], "Rounded return for stake %d" % item[0])
		_equal(result.net_change, item[1] - item[0], "Net profit excludes stake")
	return true


func test_dealer_natural_ends_round_before_player_can_hit() -> bool:
	var engine := _started([_card(10), _card(1, "diamonds"), _card(9), _card(13, "diamonds")])
	var state: Dictionary = engine.get_public_state()
	_equal(state.phase, "SETTLED", "Dealer natural checked before player actions")
	_equal(state.result.reason, "dealer_blackjack", "Dealer natural reason")
	_equal(state.result.outcome, "loss", "Player loses")
	_equal(state.result.returned_amount, 0, "No stake returned")
	_equal(state.result.net_change, -5, "Stake lost")
	_assert_rejected(engine, engine.hit(), state, "invalid_phase")
	return true


func test_both_naturals_push() -> bool:
	var engine := _started([_card(1), _card(1, "diamonds"), _card(13), _card(13, "diamonds")])
	var result: Dictionary = engine.get_public_state().result
	_equal(result.outcome, "push", "Both naturals push")
	_equal(result.reason, "both_blackjack", "Both-natural reason")
	_equal(result.returned_amount, 5, "Original stake returned")
	_equal(result.net_change, 0, "No profit or loss")
	return true


func test_natural_beats_dealer_potential_multicard_twenty_one() -> bool:
	var engine := Blackjack.new()
	var command := engine.begin_round(5, _deck([_card(1), _card(6, "diamonds"), _card(13), _card(5, "diamonds"), _card(10, "hearts")]))
	_equal(command.result.outcome, "blackjack", "Natural paid without dealer drawing toward 21")
	_equal(command.result.dealer_total, 11, "Dealer remains at initial total")
	_equal(_events_of(command, "card_dealt").size(), 4, "No extra card dealt")
	return true


func test_hit_to_twenty_one_automatically_stands_with_ordinary_payout() -> bool:
	var engine := _started([_card(10), _card(10, "diamonds"), _card(5), _card(7, "diamonds"), _card(6, "hearts")])
	var command: Dictionary = engine.hit()
	_equal(command.state.phase, "SETTLED", "21 triggers dealer and settlement")
	_equal(_hand(command.state).total, 21, "Three-card 21")
	_equal(_hand(command.state).is_blackjack, false, "Three-card 21 is not a natural")
	_equal(command.result.outcome, "win", "Ordinary win")
	_equal(command.result.returned_amount, 10, "1:1 rather than natural payout")
	var actions := _events_of(command, "action_taken")
	_equal(actions[1].action, "stand", "Automatic stand follows hit")
	_equal(actions[1].automatic, true, "Stand marked automatic")
	return true


func test_player_bust_ends_round_without_dealer_draws() -> bool:
	var engine := _started([_card(10), _card(6, "diamonds"), _card(8), _card(5, "diamonds"), _card(10, "hearts")])
	var command: Dictionary = engine.hit()
	_equal(command.result.reason, "player_bust", "Bust loss")
	_equal(command.result.returned_amount, 0, "Lost stake")
	_equal(_hand(command.state).is_bust, true, "Bust visible in player hand")
	_equal(_hand(command.state, "dealer").cards.size(), 2, "Dealer does not draw after player bust")
	_equal(_events_of(command, "dealer_card_revealed").size(), 1, "Reveal before result")
	_equal(_events_of(command, "round_finished").size(), 1, "One settlement event")
	return true


func test_dealer_stands_on_hard_seventeen() -> bool:
	var engine := _started([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")])
	var command: Dictionary = engine.stand()
	_equal(command.result.dealer_total, 17, "Dealer total")
	_equal(_events_of(command, "card_dealt").size(), 0, "No draw on hard 17")
	_equal(command.result.outcome, "win", "18 beats 17")
	return true


func test_dealer_stands_on_soft_seventeen() -> bool:
	var engine := _started([_card(10), _card(1, "diamonds"), _card(8), _card(6, "diamonds")])
	var command: Dictionary = engine.stand()
	_equal(_hand(command.state, "dealer").total, 17, "Dealer soft total")
	_equal(_hand(command.state, "dealer").is_soft, true, "Dealer hand is soft")
	_equal(_events_of(command, "card_dealt").size(), 0, "No draw on soft 17")
	return true


func test_dealer_draws_multiple_times_until_seventeen() -> bool:
	var engine := _started([_card(10), _card(2, "diamonds"), _card(8), _card(3, "diamonds"), _card(4, "diamonds"), _card(8, "diamonds")])
	var command: Dictionary = engine.stand()
	_equal(command.result.dealer_total, 17, "Dealer draws from 5 to 9 to 17")
	_equal(_hand(command.state, "dealer").cards.size(), 4, "Both draws retained")
	_equal(_events_of(command, "card_dealt").size(), 2, "Both draws emitted")
	return true


func test_dealer_draws_to_soft_seventeen_then_stops() -> bool:
	var engine := _started([_card(9), _card(1, "diamonds"), _card(9, "hearts"), _card(5, "diamonds"), _card(1)])
	var command: Dictionary = engine.stand()
	_equal(command.result.dealer_total, 17, "Ace plus five plus ace is soft 17")
	_equal(_hand(command.state, "dealer").is_soft, true, "Drawn ace remains soft")
	_equal(_events_of(command, "card_dealt").size(), 1, "Only one draw")
	return true


func test_dealer_adjusts_aces_and_keeps_drawing() -> bool:
	var engine := _started([_card(10), _card(1, "diamonds"), _card(8), _card(5, "diamonds"), _card(10, "hearts"), _card(1)])
	var command: Dictionary = engine.stand()
	_equal(command.result.dealer_total, 17, "Dealer adjusts ace after ten and draws again")
	_equal(_hand(command.state, "dealer").is_soft, false, "Both aces count as one")
	_equal(_events_of(command, "card_dealt").size(), 2, "Dealer must draw twice")
	return true


func test_regular_outcomes_and_odd_stake_returns() -> bool:
	var cases := [
		{"prefix": [_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")], "outcome": "win", "reason": "higher_total", "returned": 10},
		{"prefix": [_card(10), _card(10, "diamonds"), _card(8), _card(9, "diamonds")], "outcome": "loss", "reason": "lower_total", "returned": 0},
		{"prefix": [_card(10), _card(9, "diamonds"), _card(7), _card(8, "diamonds")], "outcome": "push", "reason": "equal_total", "returned": 5},
		{"prefix": [_card(10), _card(10, "diamonds"), _card(8), _card(6, "diamonds"), _card(10, "hearts")], "outcome": "win", "reason": "dealer_bust", "returned": 10},
	]
	for item in cases:
		var engine := _started(item.prefix)
		var command: Dictionary = engine.stand()
		_equal(command.result.outcome, item.outcome, "Outcome: %s" % item.reason)
		_equal(command.result.reason, item.reason, "Resolution reason")
		_equal(command.result.returned_amount, item.returned, "Returned stake and winnings")
		_equal(command.result.net_change, item.returned - 5, "Net change")
		_equal(command.state.result, command.result, "State and command agree on result")
	return true


func test_dealer_multicard_twenty_one_is_not_blackjack() -> bool:
	var engine := _started([_card(1), _card(6, "diamonds"), _card(8), _card(5, "diamonds"), _card(10, "hearts")])
	var command: Dictionary = engine.stand()
	_equal(command.result.outcome, "loss", "Dealer 21 beats player 19")
	_equal(command.result.reason, "lower_total", "Resolved by total rather than natural")
	_equal(_hand(command.state, "dealer").is_blackjack, false, "Three-card 21 is ordinary")
	return true


func test_rejected_wagers_leave_state_unchanged() -> bool:
	var engine := Blackjack.new()
	for wager in [0, -1, Blackjack.MAX_WAGER + 1]:
		var before := engine.get_public_state()
		_assert_rejected(engine, engine.begin_round(wager), before, "invalid_wager")
	_equal(engine.begin_round(1).accepted, true, "Positive odd stake accepted; table limits belong elsewhere")
	return true


func test_invalid_fixed_decks_are_rejected_atomically() -> bool:
	var engine := Blackjack.new()
	var invalid_decks: Array = [[_card(1)]]
	var duplicate := _deck()
	duplicate[1] = duplicate[0].duplicate(true)
	invalid_decks.append(duplicate)
	for bad_card in [null, 5, {}, {"rank": 0, "suit": "clubs"}, {"rank": 14, "suit": "clubs"}, {"rank": 1.0, "suit": "clubs"}, {"rank": 1}, {"rank": 1, "suit": "stars"}, {"rank": 1, "suit": 0}]:
		var malformed := _deck()
		malformed[0] = bad_card
		invalid_decks.append(malformed)
	for deck_order in invalid_decks:
		var before := engine.get_public_state()
		_assert_rejected(engine, engine.begin_round(5, deck_order), before, "invalid_deck")
	return true


func test_duplicate_start_does_not_replace_active_hand() -> bool:
	var engine := _started([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")])
	var before: Dictionary = engine.get_public_state()
	_assert_rejected(engine, engine.begin_round(9), before, "invalid_phase")
	return true


func test_actions_after_settlement_do_not_repeat_result() -> bool:
	var engine := _started([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")])
	var command: Dictionary = engine.stand()
	_equal(_events_of(command, "round_finished").size(), 1, "Initial settlement emitted once")
	var before: Dictionary = engine.get_public_state()
	_assert_rejected(engine, engine.stand(), before, "invalid_phase")
	_assert_rejected(engine, engine.hit(), before, "invalid_phase")
	return true


func test_new_round_clears_previous_result_and_uses_fresh_deck() -> bool:
	var prefix := [_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")]
	var engine := _started(prefix)
	engine.stand()
	var old_state: Dictionary = engine.get_public_state()
	var command: Dictionary = engine.begin_round(7, _deck(prefix))
	_equal(command.state.round_id, old_state.round_id + 1, "New round identifier")
	_equal(command.state.wager, 7, "New round accepts a new wager; session will enforce fixed stake")
	_equal(command.result, null, "Previous command result cleared")
	_equal(command.state.result, null, "Previous state result cleared")
	_equal(_hand(command.state, "dealer").cards[1], {"face_up": false}, "New dealer card concealed again")
	_equal(_hand(command.state).cards.size(), 2, "Previous player cards removed")
	_check(_hand(command.state).hand_id != _hand(old_state).hand_id, "New hand identifier")
	_equal(_hand(command.state).cards[0].rank, 10, "Draw index reset to first card")
	_equal(command.events[0].sequence, 1, "Event numbering restarts within new round")
	return true


func test_rejected_restart_preserves_finished_result() -> bool:
	var engine := _started([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")])
	engine.stand()
	var before: Dictionary = engine.get_public_state()
	_assert_rejected(engine, engine.begin_round(0), before, "invalid_wager")
	_assert_rejected(engine, engine.begin_round(5, [_card(1)]), before, "invalid_deck")
	return true


func test_callers_cannot_mutate_state_events_or_result() -> bool:
	var engine := Blackjack.new()
	var command := engine.begin_round(5, _deck([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")]))
	var before := engine.get_public_state()
	command.state.seats[0].hands[0].cards[0].rank = 1
	command.state.legal_actions.clear()
	_events_of(command, "card_dealt")[0].card.rank = 2
	_equal(engine.get_public_state(), before, "Command output is detached from engine")
	var snapshot := engine.get_public_state()
	snapshot.seats.clear()
	_equal(engine.get_public_state(), before, "Getter output is also detached")
	command = engine.stand()
	before = engine.get_public_state()
	command.result.returned_amount = 999
	command.state.result.returned_amount = 888
	_events_of(command, "round_finished")[0].result.returned_amount = 777
	_equal(engine.get_public_state(), before, "Settlement copies do not alias stored result")
	_equal(command.result.returned_amount, 999, "Command result does not alias event/state result")
	return true


func test_fixed_deck_input_is_copied_and_extra_metadata_is_ignored() -> bool:
	var engine := Blackjack.new()
	var deck_order := _deck([_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds"), _card(2, "hearts")])
	deck_order[0]["private_note"] = "not public card data"
	var command := engine.begin_round(5, deck_order)
	_check(not _hand(command.state).cards[0].has("private_note"), "Only normalized card data is exposed")
	deck_order[4].rank = 13
	deck_order.clear()
	command = engine.hit()
	_equal(_hand(command.state).cards[2].rank, 2, "Input mutation cannot change later draws")
	return true


func test_seeded_engines_reproduce_multiple_rounds() -> bool:
	var first := Blackjack.new(123456)
	var second := Blackjack.new(123456)
	for round_index in range(10):
		_equal(first.begin_round(5), second.begin_round(5), "Seeded initial deal %d" % round_index)
		while first.get_public_state().phase == "PLAYER_TURN":
			var state := first.get_public_state()
			var action := "hit" if _hand(state).total < 16 else "stand"
			_equal(first.call(action), second.call(action), "Seeded action %s" % action)
		_equal(first.get_public_state(), second.get_public_state(), "Seeded final state")
	return true


func test_rejected_commands_do_not_advance_seeded_shuffle() -> bool:
	var first := Blackjack.new(123456)
	var second := Blackjack.new(123456)
	first.begin_round(0)
	first.begin_round(5, [_card(1)])
	_equal(first.begin_round(5), second.begin_round(5), "Invalid starts consume neither RNG nor round IDs")
	return true


func test_event_sequence_and_reveal_before_dealer_actions() -> bool:
	var engine := Blackjack.new()
	var start := engine.begin_round(5, _deck([_card(10), _card(2, "diamonds"), _card(8), _card(3, "diamonds"), _card(4, "diamonds"), _card(8, "diamonds")]))
	var finish := engine.stand()
	var events: Array = start.events + finish.events
	var reveal_index: int = -1
	var settlement_index: int = -1
	for index in range(events.size()):
		var event: Dictionary = events[index]
		_equal(event.sequence, index + 1, "Sequence spans command batches")
		_equal(event.round_id, start.state.round_id, "All events belong to this round")
		if event.type == "dealer_card_revealed":
			reveal_index = index
		if event.type == "action_taken" and event.seat_id == "dealer":
			_check(reveal_index >= 0 and reveal_index < index, "Dealer action follows reveal")
		if event.type == "round_finished":
			settlement_index = index
	_equal(settlement_index, events.size() - 1, "Final event is settlement")
	return true


func test_events_can_reconstruct_cards_for_a_future_display() -> bool:
	var engine := Blackjack.new()
	var commands: Array = []
	commands.append(engine.begin_round(5, _deck([_card(8), _card(6, "diamonds"), _card(5), _card(5, "diamonds"), _card(3, "hearts"), _card(7, "diamonds")])))
	commands.append(engine.hit())
	commands.append(engine.stand())
	var displayed := {"player": [], "dealer": []}
	for command in commands:
		for event in command.events:
			if event.type == "card_dealt":
				_equal(event.card_index, displayed[event.seat_id].size(), "Deal targets next display slot")
				displayed[event.seat_id].append(event.card.duplicate(true))
			elif event.type == "dealer_card_revealed":
				displayed[event.seat_id][event.card_index] = event.card.duplicate(true)
		for seat_id in ["player", "dealer"]:
			_equal(displayed[seat_id], _hand(command.state, seat_id).cards, "Events reconstruct %s cards" % seat_id)
	return true


func test_many_seeded_hands_finish_without_duplicate_cards() -> bool:
	var engine := Blackjack.new(987654)
	for round_index in range(100):
		var command := engine.begin_round(5)
		var action_count: int = 0
		while command.state.phase == "PLAYER_TURN" and action_count < 24:
			command = engine.hit() if _hand(command.state).total < 17 else engine.stand()
			action_count += 1
		_equal(command.state.phase, "SETTLED", "Round %d terminates" % round_index)
		var seen: Dictionary = {}
		for seat in command.state.seats:
			for card in seat.hands[0].cards:
				_equal(card.face_up, true, "All cards visible at settlement")
				_check(not seen.has(card.card_id), "Cards drawn without replacement")
				seen[card.card_id] = true
		_equal(_events_of(command, "round_finished").size(), 1, "Exactly one finishing event")
	return true


func _finish_table(engine: RefCounted) -> Array:
	var events: Array = []
	for step in range(64):
		var state: Dictionary = engine.get_public_state()
		if state.phase == "SETTLED":
			return events
		var command: Dictionary
		if state.phase == "PLAYER_TURN":
			command = engine.hit() if _hand(state).total < 17 else engine.stand()
		else:
			command = engine.advance_table()
		_check(command.accepted, "Table action accepted")
		events.append_array(command.events)
	_check(false, "Table terminates within 64 moves")
	return events


func test_shared_deal_order_empty_chairs_and_ai_card_consumption() -> bool:
	var engine := Blackjack.new(42, ["right_1", "left_1"])
	var start := engine.begin_round(5, _deck([
		_card(10), _card(9), _card(8), _card(6, "diamonds"),
		_card(7), _card(9, "hearts"), _card(8, "hearts"), _card(5, "diamonds"),
		_card(10, "hearts"), _card(10, "diamonds"),
	]))
	var dealt: Array = []
	for event in _events_of(start, "card_dealt"):
		dealt.append(event.seat_id)
	_equal(dealt, ["left_1", "player", "right_1", "dealer", "left_1", "player", "right_1", "dealer"], "Seat order is fixed, not caller array order")
	_equal(start.state.active_seat_id, "left_1", "Left AI goes first")
	_equal(_hand(start.state, "left_2").cards, [], "Empty chair receives no cards")
	_assert_rejected(engine, engine.hit(), start.state, "invalid_phase")
	_assert_rejected(engine, engine.begin_round(5), start.state, "invalid_phase")
	_equal(engine.advance_table().state.phase, "PLAYER_TURN", "AI stands at 17 before player acts")
	var stand := engine.stand()
	_equal(stand.state.active_seat_id, "right_1", "Right AI follows the player")
	var hit := engine.advance_table()
	_equal(_hand(hit.state, "right_1").cards[-1].rank, 10, "AI consumes the next shared card")
	_equal(hit.state.phase, "DEALER_TURN", "Busted AI yields to dealer")
	var finish := engine.advance_table()
	_equal(_hand(finish.state, "dealer").cards[-1].suit, "diamonds", "Dealer gets the card after the AI draw")
	_equal(finish.result.outcome, "loss", "Dealer's shared-deck 21 beats the player")
	return true


func test_early_blackjack_keeps_hole_card_private_and_other_seats_play() -> bool:
	var engine := Blackjack.new(42, ["right_1"])
	var start := engine.begin_round(5, _deck([
		_card(1), _card(6), _card(6, "diamonds"),
		_card(13), _card(5), _card(9, "diamonds"),
		_card(6, "hearts"), _card(10, "hearts"),
	]))
	_equal(start.result.returned_amount, 13, "Player natural resolves before AI acts")
	_equal(start.result.dealer_total, null, "Early result cannot expose hole-card total")
	_equal(start.state.phase, "AI_TURN", "Table remains active after player blackjack")
	_equal(_hand(start.state, "dealer").cards[1], {"face_up": false}, "Hole card remains hidden")
	_equal(_events_of(start, "dealer_card_revealed"), [], "No premature reveal event")
	_equal(_events_of(start, "round_finished"), [], "Player outcome is not table completion")
	var later := _finish_table(engine)
	_equal(engine.get_public_state().result.returned_amount, 13, "Later dealer bust does not change natural payout")
	_equal(_hand(engine.get_public_state(), "right_1").total, 17, "AI finishes its hand")
	var repeated: int = 0
	for event in later:
		if event.type == "seat_settled" and event.seat_id == "player":
			repeated += 1
	_equal(repeated, 0, "Player result is never emitted again")
	_equal(start.result.dealer_total, null, "Previously returned result remains concealed after reveal")
	return true


func test_busted_player_waits_for_ai_and_dealer_without_changing_loss() -> bool:
	var engine := Blackjack.new(42, ["right_1"])
	engine.begin_round(5, _deck([_card(10), _card(10, "diamonds"), _card(6, "hearts"),
		_card(8), _card(7, "diamonds"), _card(5, "hearts"), _card(10, "spades"), _card(8, "hearts")]))
	var bust := engine.hit()
	_equal(bust.result.reason, "player_bust", "Bust resolves immediately")
	_equal(bust.state.phase, "AI_TURN", "AI still has a turn")
	_equal(bust.result.dealer_total, null, "Bust result does not leak dealer's hidden total")
	_assert_rejected(engine, engine.stand(), bust.state, "invalid_phase")
	_finish_table(engine)
	_equal(_hand(engine.get_public_state(), "dealer").cards.size(), 3, "Dealer draws for surviving AI")
	_equal(engine.get_public_state().result.returned_amount, 0, "Player remains busted")
	return true


func test_all_players_bust_skips_unnecessary_dealer_draws() -> bool:
	var engine := Blackjack.new(42, ["right_1"])
	engine.begin_round(5, _deck([_card(10), _card(10, "diamonds"), _card(6, "hearts"),
		_card(8), _card(6, "diamonds"), _card(5, "hearts"), _card(10, "spades"), _card(10, "hearts")]))
	engine.hit()
	var finish := engine.advance_table()
	_equal(finish.state.phase, "SETTLED", "Last bust finishes the table")
	_equal(_hand(finish.state, "dealer").cards.size(), 2, "No dealer draws when every wager is decided")
	_equal(_events_of(finish, "round_finished").size(), 1, "One table completion")
	return true


func test_dealer_blackjack_settles_every_occupied_seat_immediately() -> bool:
	var engine := Blackjack.new(42, ["left_1", "right_1"])
	var finish := engine.begin_round(5, _deck([_card(1), _card(10), _card(9), _card(1, "diamonds"),
		_card(13), _card(8), _card(7), _card(13, "diamonds")]))
	_equal(finish.state.phase, "SETTLED", "Dealer natural stops all turns")
	_equal(_events_of(finish, "seat_settled").size(), 3, "Each occupied player has exactly one result")
	_equal(_events_of(finish, "action_taken"), [], "No AI or player hits against dealer blackjack")
	_equal(finish.state.seats[2].result, null, "Empty outer chair has no wager result")
	_equal(finish.result.outcome, "loss", "Human loses to dealer natural")
	for seat in finish.state.seats:
		if seat.seat_id == "left_1":
			_equal(seat.result.outcome, "push", "AI natural pushes against dealer natural")
	return true


func test_ai_stands_on_soft_seventeen_and_cannot_peek() -> bool:
	for hole_rank in [8, 10]:
		var engine := Blackjack.new(42, ["right_1"])
		engine.begin_round(5, _deck([_card(10), _card(1), _card(9, "diamonds"),
			_card(8), _card(6), _card(hole_rank, "diamonds")]))
		engine.stand()
		var ai := engine.advance_table()
		_equal(_events_of(ai, "action_taken")[0].action, "stand", "Same AI decision regardless of hole card")
		_equal(_events_of(ai, "card_dealt"), [], "Soft 17 does not hit")
		_equal(_hand(ai.state, "dealer").cards[1], {"face_up": false}, "Dealer remains concealed through AI's turn")
	return true


func test_invalid_ai_seats_are_rejected_before_dealing() -> bool:
	for seats in [["player"], ["right_1", "right_1"], ["unknown"], [1]]:
		var engine := Blackjack.new(42, seats)
		var before := engine.get_public_state()
		_assert_rejected(engine, engine.begin_round(5), before, "invalid_seats")
	return true


func test_ai_configuration_and_public_results_are_copied() -> bool:
	var seats := ["right_1"]
	var engine := Blackjack.new(42, seats)
	seats.clear()
	var start := engine.begin_round(5)
	_equal(_hand(start.state, "right_1").cards.size(), 2, "Input mutation cannot empty an occupied chair")
	var before := engine.get_public_state()
	_hand(start.state, "right_1").cards[0].rank = 99
	_equal(engine.get_public_state(), before, "AI card snapshots do not alias engine data")
	_finish_table(engine)
	var final := engine.get_public_state()
	var original := engine.get_public_state()
	for seat in final.seats:
		if seat.result != null:
			seat.result.returned_amount = 999
	_equal(engine.get_public_state(), original, "AI result snapshots do not alias engine data")
	return true


func test_seeded_full_tables_terminate_and_reconstruct_all_cards() -> bool:
	var first := Blackjack.new(91823, Blackjack.AI_SEATS)
	var second := Blackjack.new(91823, Blackjack.AI_SEATS)
	for round_index in range(60):
		var start := first.begin_round(5)
		_equal(start, second.begin_round(5), "Full-table seeded deal is repeatable")
		var events: Array = start.events.duplicate(true)
		for step in range(64):
			var state := first.get_public_state()
			if state.phase == "SETTLED":
				break
			var action := "advance_table"
			if state.phase == "PLAYER_TURN":
				action = "hit" if _hand(state).total < 17 else "stand"
			var command: Dictionary = first.call(action)
			_equal(command, second.call(action), "Full-table seeded action is repeatable")
			events.append_array(command.events)
		_equal(first.get_public_state().phase, "SETTLED", "Full table always terminates")
		var displayed: Dictionary = {}
		var seen: Dictionary = {}
		var player_results: int = 0
		var table_results: int = 0
		for index in range(events.size()):
			var event: Dictionary = events[index]
			_equal(event.sequence, index + 1, "One ordered stream across all seats")
			if event.type == "card_dealt":
				if not displayed.has(event.seat_id):
					displayed[event.seat_id] = []
				displayed[event.seat_id].append(event.card)
			elif event.type == "dealer_card_revealed":
				displayed.dealer[event.card_index] = event.card
			elif event.type == "seat_settled" and event.seat_id == "player":
				player_results += 1
			elif event.type == "round_finished":
				table_results += 1
		_equal(player_results, 1, "One player outcome per table round")
		_equal(table_results, 1, "One completion per table round")
		for seat in first.get_public_state().seats:
			_equal(displayed[seat.seat_id], seat.hands[0].cards, "Events reconstruct every seat")
			for card in seat.hands[0].cards:
				_check(not seen.has(card.card_id), "All seats share a deck without replacement")
				seen[card.card_id] = true
	return true
