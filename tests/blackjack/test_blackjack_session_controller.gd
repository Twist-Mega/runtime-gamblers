extends SceneTree

const Session = preload("res://scripts/blackjack/blackjack_session_controller.gd")
const FakeWallet = preload("res://tests/blackjack/fake_wallet.gd")
const SharedRules = preload("res://scripts/blackjack/blackjack_engine.gd")

class Unlocks extends RefCounted:
	var granted: Dictionary = {}
	func is_unlocked(unlock_id: String) -> bool:
		return granted.get(unlock_id, false)

var _failures: int = 0
var _checks: int = 0
var _current_test: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var names: Array[String] = []
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			names.append(method.name)
	names.sort()
	for test_name in names:
		_current_test = test_name
		var failures_before := _failures
		var completed: Variant = call(test_name)
		_check(completed is bool and completed == true, "Test completed without a runtime error")
		print("%s %s" % ["PASS" if failures_before == _failures else "FAIL", test_name])
	print("Blackjack sessions: %d tests, %d checks, %d failures." % [names.size(), _checks, _failures])
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


func _deck(kind: String = "win") -> Array:
	var prefixes := {
		"win": [_card(10), _card(9, "diamonds"), _card(8), _card(8, "diamonds")],
		"loss": [_card(10), _card(10, "diamonds"), _card(8), _card(9, "diamonds")],
		"push": [_card(10), _card(9, "diamonds"), _card(7), _card(8, "diamonds")],
		"natural": [_card(1), _card(9, "diamonds"), _card(13), _card(8, "diamonds")],
		"bust": [_card(10), _card(6, "diamonds"), _card(8), _card(5, "diamonds"), _card(10, "hearts")],
	}
	var cards: Array = prefixes[kind].duplicate(true)
	for suit in ["clubs", "diamonds", "hearts", "spades"]:
		for rank in range(1, 14):
			var card := _card(rank, suit)
			if card not in cards:
				cards.append(card)
	return cards


func _fixture(balance: int = 100, max_hands: int = 5) -> Dictionary:
	var wallet := FakeWallet.new(balance)
	var unlocks := Unlocks.new()
	var tables := {
		"lobby": {"max_hands": max_hands, "stake_options": [
			{"option_id": "small", "label": "Small", "amount": 5},
			{"option_id": "large", "label": "Large", "amount": 25, "unlock_id": "higher_stakes"},
		]},
		"high_roller": {"max_hands": 3, "stake_options": [
			{"option_id": "roller", "amount": 50, "unlock_id": "high_roller_stakes"},
		]},
	}
	return {"wallet": wallet, "unlocks": unlocks, "tables": tables,
		"session": Session.new(wallet, tables, unlocks.is_unlocked, 42)}


func _ready(balance: int = 100, max_hands: int = 5) -> Dictionary:
	var fixture := _fixture(balance, max_hands)
	_equal(fixture.session.open_blackjack("lobby").accepted, true, "Fixture table opens")
	_equal(fixture.session.select_stake("small").accepted, true, "Fixture stake selected")
	return fixture


func _finish_hand(session: RefCounted, kind: String = "win") -> Dictionary:
	var command: Dictionary = session.start_next_hand(_deck(kind))
	_equal(command.accepted, true, "Hand starts")
	if command.state.phase == "PLAYING":
		command = session.hit() if kind == "bust" else session.stand()
		_equal(command.accepted, true, "Finishing move accepted")
	return command


func _events_of(command: Dictionary, type: String) -> Array:
	var found: Array = []
	for event in command.events:
		if event.type == type:
			found.append(event)
	return found


func _assert_rejected(session: RefCounted, command: Dictionary, before: Dictionary, code: String) -> void:
	_equal(command.accepted, false, "Command rejected")
	_equal(command.error.code, code, "Error code")
	_equal(command.events, [], "No events on ordinary rejection")
	_equal(command.result, null, "No new settlement")
	_equal(session.get_public_state(), before, "Public state unchanged")


func _shared_fixture(balance: int = 100, max_hands: int = 5) -> Dictionary:
	var wallet := FakeWallet.new(balance)
	var session := Session.new(wallet, {"table": {"max_hands": max_hands,
		"ai_seats": ["right_1"], "stake_options": [{"option_id": "five", "amount": 5}]}}, Callable(), 42)
	session.open_blackjack("table")
	session.select_stake("five")
	return {"wallet": wallet, "session": session}


func _shared_deck(natural: bool = true, bust: bool = false) -> Array:
	var cards: Array
	if natural:
		cards = [_card(1), _card(6), _card(6, "diamonds"), _card(13), _card(5), _card(9, "diamonds"), _card(6, "hearts"), _card(10, "hearts")]
	elif bust:
		cards = [_card(10), _card(10, "diamonds"), _card(6, "hearts"), _card(8), _card(7, "diamonds"), _card(5, "hearts"), _card(10, "spades"), _card(8, "hearts")]
	else:
		cards = [_card(10), _card(10, "diamonds"), _card(9, "hearts"), _card(8), _card(7, "diamonds"), _card(8, "hearts")]
	for suit in SharedRules.SUITS:
		for rank in range(1, 14):
			var card := _card(rank, suit)
			if card not in cards:
				cards.append(card)
	return cards


func _finish_shared_table(session: RefCounted) -> Array:
	var events: Array = []
	for step in range(64):
		if "advance_table" not in session.get_public_state().legal_actions:
			return events
		var response: Dictionary = session.advance_table()
		_check(response.accepted, "Automatic table move accepted")
		events.append_array(response.events)
	_check(false, "Automatic play terminates")
	return events


func test_early_blackjack_is_paid_once_before_table_completion() -> bool:
	var fixture := _shared_fixture()
	var session: RefCounted = fixture.session
	var start: Dictionary = session.start_next_hand(_shared_deck())
	_equal(start.state.balance, 108, "Natural credited before remaining AI moves")
	_equal(start.state.hands_played, 1, "Financial history records early payment")
	_equal(start.state.phase, "PLAYING", "Whole table is still playing")
	_equal(start.state.legal_actions, ["advance_table"], "Only table advancement is allowed")
	_equal(start.result.dealer_total, null, "Paid result keeps the hole-card total private")
	_assert_rejected(session, session.leave_table(), start.state, "invalid_phase")
	_assert_rejected(session, session.start_next_hand(), start.state, "invalid_phase")
	var later := _finish_shared_table(session)
	_equal(session.get_public_state().balance, 108, "AI results never change human wallet")
	_equal(fixture.wallet.transactions.size(), 2, "Only one human stake and one human return")
	_equal(session.get_public_state().phase, "BETWEEN_HANDS", "Departure becomes available after table completes")
	var payments: int = 0
	for event in later:
		if event.type == "hand_settled":
			payments += 1
	_equal(payments, 0, "No repeated payment when table finishes")
	return true


func test_early_bust_does_not_end_low_funds_session_until_ai_finishes() -> bool:
	var fixture := _shared_fixture(5)
	var session: RefCounted = fixture.session
	session.start_next_hand(_shared_deck(false, true))
	var bust: Dictionary = session.hit()
	_equal(bust.state.balance, 0, "Bust loses stake immediately")
	_equal(bust.result.outcome, "loss", "Player outcome is available immediately")
	_equal(bust.state.phase, "PLAYING", "Low balance does not cut off other seats")
	_equal(bust.state.summary, null, "No final summary during active table")
	_finish_shared_table(session)
	_equal(session.get_public_state().phase, "COMPLETE", "Session ends after dealer finishes")
	_equal(session.get_public_state().summary.reason, "insufficient_funds", "Correct final reason")
	_equal(fixture.wallet.transactions.size(), 2, "AI does not charge additional wagers")
	return true


func test_early_credit_retry_resumes_remaining_table_without_double_payment() -> bool:
	var fixture := _shared_fixture(100, 1)
	var session: RefCounted = fixture.session
	fixture.wallet.fail_next_credits = 1
	var start: Dictionary = session.start_next_hand(_shared_deck())
	_equal(start.state.phase, "PAYOUT_PENDING", "Failed early credit holds the table")
	_equal(start.state.hand.phase, "AI_TURN", "AI has not been discarded")
	_equal(start.state.balance, 95, "Unpaid return has not been credited")
	_assert_rejected(session, session.advance_table(), start.state, "invalid_phase")
	var retry: Dictionary = session.retry_pending_transaction()
	_equal(retry.state.phase, "PLAYING", "Retry resumes table rather than finishing session")
	_equal(retry.state.balance, 108, "Original return credited once")
	_equal(retry.state.hands_played, 1, "One human hand recorded")
	_finish_shared_table(session)
	_equal(session.get_public_state().phase, "COMPLETE", "One-hand limit waits for all seats")
	_equal(session.get_public_state().summary.ending_balance, 108, "Summary uses final human balance")
	_equal(fixture.wallet.transactions.size(), 2, "Retry and AI completion do not duplicate credit")
	return true


func test_ordinary_hand_waits_for_dealer_before_payment() -> bool:
	var fixture := _shared_fixture()
	var session: RefCounted = fixture.session
	session.start_next_hand(_shared_deck(false))
	var stand: Dictionary = session.stand()
	_equal(stand.result, null, "Standing is not a win yet")
	_equal(stand.state.balance, 95, "No return at the end of the human's turn")
	_equal(stand.state.hands_played, 0, "Unresolved hand is not financially settled")
	var ai: Dictionary = session.advance_table()
	_equal(ai.state.hand.phase, "DEALER_TURN", "Dealer plays after AI stands")
	_equal(ai.state.balance, 95, "Still waiting for dealer outcome")
	var finish: Dictionary = session.advance_table()
	_equal(finish.result.returned_amount, 10, "Ordinary win returned after dealer finishes")
	_equal(finish.state.balance, 105, "Only human payout changes wallet")
	_assert_rejected(session, session.advance_table(), finish.state, "invalid_phase")
	return true


func test_five_shared_rounds_keep_occupancy_and_wait_before_summary() -> bool:
	var fixture := _shared_fixture()
	var session: RefCounted = fixture.session
	for hand_number in range(1, 6):
		var start: Dictionary = session.start_next_hand(_shared_deck())
		_equal(start.state.phase, "PLAYING", "Even the last natural leaves AI in play")
		_equal(start.state.hands_played, hand_number, "Each natural counts once")
		_equal(start.state.hand.seats[4].occupied, true, "Right inner AI stays for the entire visit")
		_finish_shared_table(session)
	_equal(session.get_public_state().phase, "COMPLETE", "Exactly five full table rounds")
	_equal(session.get_public_state().balance, 140, "Only five human natural payouts")
	_equal(fixture.wallet.transactions.size(), 10, "Two human transactions per hand")
	return true


func test_invalid_ai_table_configuration_rejected_without_charge() -> bool:
	for seats in ["right_1", ["player"], ["left_1", "left_1"], [false]]:
		var wallet := FakeWallet.new(100)
		var session := Session.new(wallet, {"table": {"ai_seats": seats,
			"stake_options": [{"option_id": "five", "amount": 5}]}})
		var before := session.get_public_state()
		_assert_rejected(session, session.open_blackjack("table"), before, "invalid_table")
		_equal(wallet.transactions.size(), 0, "Invalid seats cannot charge a wager")
	return true


func test_open_and_stake_selection_do_not_charge_upfront() -> bool:
	var fixture := _fixture()
	var session: RefCounted = fixture.session
	_equal(session.get_public_state().phase, "IDLE", "Initial phase")
	var command: Dictionary = session.open_blackjack("lobby")
	_equal(command.state.phase, "SELECTING_STAKE", "Stake selection before play")
	_equal(command.state.max_hands, 5, "Five hands configured")
	_equal(command.state.balance, 100, "Opening does not charge")
	_check(not command.state.session_id.is_empty(), "Session gets an identifier")
	command = session.select_stake("small")
	_equal(command.state.phase, "READY", "Ready for first hand")
	_equal(command.state.selected_stake.amount, 5, "Odd stake selected")
	_equal(command.state.hands_played, 0, "No hand counted for selection")
	_equal(fixture.wallet.transactions.size(), 0, "No upfront buy-in transaction")
	_equal(command.state.legal_actions, ["start_next_hand", "leave_table"], "Initial actions")
	return true


func test_default_table_has_five_hands_and_starter_stake() -> bool:
	var wallet := FakeWallet.new()
	var session := Session.new(wallet)
	var command := session.open_blackjack("lobby_blackjack")
	_equal(command.accepted, true, "Default table opens")
	_equal(command.state.max_hands, 5, "Default hand limit")
	_equal(command.state.stake_options[0].amount, 2, "Development stake")
	_equal(session.select_stake("starter").accepted, true, "Default stake can be selected")
	return true


func test_stake_deducted_once_per_hand_and_repeated_start_rejected() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	var command: Dictionary = session.start_next_hand(_deck())
	_equal(command.state.balance, 95, "Only one stake deducted")
	_equal(command.state.hand_number, 1, "First hand index")
	_equal(command.state.hands_played, 0, "Active hand not yet completed")
	_equal(command.state.legal_actions, ["hit", "stand"], "Only player moves during hand")
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.start_next_hand(_deck()), before, "invalid_phase")
	_equal(fixture.wallet.transactions.size(), 1, "Repeated start did not charge")
	command = session.stand()
	_equal(command.state.balance, 105, "Win pays back stake and winnings")
	_equal(command.state.phase, "BETWEEN_HANDS", "Between hands after settlement")
	_equal(command.state.hands_played, 1, "Completed hand counted once")
	_equal(fixture.wallet.transactions.size(), 2, "One deduction and one payout")
	_equal(command.result.wager, 5, "Result uses selected stake")
	return true


func test_selected_stake_cannot_change_before_or_between_hands() -> bool:
	var fixture := _ready()
	fixture.unlocks.granted["higher_stakes"] = true
	var session: RefCounted = fixture.session
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.select_stake("large"), before, "invalid_phase")
	_finish_hand(session)
	before = session.get_public_state()
	_assert_rejected(session, session.select_stake("large"), before, "invalid_phase")
	var command := _finish_hand(session)
	_equal(command.result.wager, 5, "Second hand still uses original stake")
	_equal(command.state.balance, 110, "No larger buy-in applied")
	return true


func test_five_hand_limit_and_result_acknowledgement() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	var command: Dictionary = {}
	for number in range(1, 6):
		command = _finish_hand(session)
		_equal(command.state.hands_played, number, "Completed hand count")
		_equal(command.result.hand_number, number, "Hand result index")
		_equal(command.state.phase, "COMPLETE" if number == 5 else "BETWEEN_HANDS", "Session phase")
	_equal(command.summary.reason, "hand_limit", "Five-hand completion reason")
	_equal(command.summary.starting_balance, 100, "Starting balance recorded")
	_equal(command.summary.ending_balance, 125, "Ending balance recorded")
	_equal(command.summary.net_change, 25, "Session profit")
	_equal(command.state.legal_actions, ["acknowledge_result"], "Summary before lobby return")
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.start_next_hand(), before, "invalid_phase")
	_equal(fixture.wallet.transactions.size(), 10, "Five deductions and five payouts")
	command = session.acknowledge_result()
	_equal(command.state.phase, "CLOSED", "Acknowledgement closes session")
	_equal(_events_of(command, "session_closed").size(), 1, "One signal event for future lobby bridge")
	before = session.get_public_state()
	_assert_rejected(session, session.acknowledge_result(), before, "invalid_phase")
	_equal(fixture.wallet.transactions.size(), 10, "Acknowledgement does not pay again")
	return true


func test_pushes_and_naturals_each_consume_a_hand() -> bool:
	for kind in ["push", "natural"]:
		var fixture := _ready(100, 2)
		var session: RefCounted = fixture.session
		_finish_hand(session, kind)
		var command := _finish_hand(session, kind)
		_equal(command.state.hands_played, 2, "Both completed hands counted: %s" % kind)
		_equal(command.summary.reason, "hand_limit", "Limit applies to %s" % kind)
		_equal(command.state.balance, 100 if kind == "push" else 116, "Push or rounded natural credits")
	return true


func test_custom_hand_limit() -> bool:
	var fixture := _ready(100, 1)
	var command := _finish_hand(fixture.session)
	_equal(command.state.phase, "COMPLETE", "One-hand configured session ends immediately")
	_equal(command.summary.max_hands, 1, "Configured limit in summary")
	return true


func test_leaving_between_hands_preserves_settled_money() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	_finish_hand(session)
	_finish_hand(session, "loss")
	var command: Dictionary = session.leave_table()
	_equal(command.state.phase, "COMPLETE", "Leave presents summary")
	_equal(command.summary.reason, "player_left", "Voluntary departure")
	_equal(command.summary.hands_played, 2, "Only completed hands included")
	_equal(command.summary.net_change, 0, "Win and loss cancel")
	_equal(command.state.balance, 100, "Settled balance preserved")
	_equal(fixture.wallet.transactions.size(), 4, "Leave does not charge remaining hands")
	_equal(session.acknowledge_result().state.phase, "CLOSED", "Leave can return after summary acknowledgement")
	return true


func test_cancel_before_first_hand_closes_without_a_charge() -> bool:
	for select_first in [false, true]:
		var fixture := _fixture()
		var session: RefCounted = fixture.session
		session.open_blackjack("lobby")
		if select_first:
			session.select_stake("small")
		var command: Dictionary = session.leave_table()
		_equal(command.state.phase, "CLOSED", "Cancellation closes immediately")
		_equal(command.summary.reason, "cancelled", "Cancellation reason")
		_equal(command.summary.hands_played, 0, "No hands played")
		_equal(command.state.balance, 100, "Cancellation costs nothing")
		_equal(fixture.wallet.transactions.size(), 0, "No cancellation transaction")
		_equal(_events_of(command, "session_closed").size(), 1, "Lobby bridge can observe cancellation")
	return true


func test_leaving_or_acknowledging_during_active_hand_is_rejected() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	session.start_next_hand(_deck())
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.leave_table(), before, "invalid_phase")
	_assert_rejected(session, session.acknowledge_result(), before, "invalid_phase")
	_equal(fixture.wallet.transactions.size(), 1, "No refund or payout for blocked departure")
	return true


func test_insufficient_balance_blocks_stake_selection() -> bool:
	var fixture := _fixture(4)
	var session: RefCounted = fixture.session
	session.open_blackjack("lobby")
	var before: Dictionary = session.get_public_state()
	_equal(before.stake_options[0].affordable, false, "Display sees unaffordable option")
	_assert_rejected(session, session.select_stake("small"), before, "insufficient_funds")
	_equal(fixture.wallet.transactions.size(), 0, "No money taken")
	return true


func test_loss_ends_session_when_next_stake_is_unaffordable() -> bool:
	var fixture := _ready(10)
	var session: RefCounted = fixture.session
	var first := _finish_hand(session, "loss")
	_equal(first.state.phase, "BETWEEN_HANDS", "Balance equal to next stake is sufficient")
	var second := _finish_hand(session, "loss")
	_equal(second.state.phase, "COMPLETE", "Funds exhausted after second loss")
	_equal(second.summary.reason, "insufficient_funds", "Automatic end reason")
	_equal(second.summary.hands_played, 2, "No extra hand charged")
	_equal(second.state.balance, 0, "Balance never negative")
	_equal(second.summary.net_change, -10, "Session losses counted")
	return true


func test_affordability_checked_after_payout_not_before() -> bool:
	var fixture := _ready(5)
	var command := _finish_hand(fixture.session, "natural")
	_equal(command.state.balance, 13, "Last available stake wins rounded return")
	_equal(command.state.phase, "BETWEEN_HANDS", "Payout finances next hand")
	return true


func test_external_spending_before_next_hand_ends_without_deduction() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	_finish_hand(session)
	fixture.wallet.balance = 4
	var count: int = fixture.wallet.transactions.size()
	_equal(session.get_public_state().legal_actions, ["leave_table"], "Next hand unavailable after external spending")
	var command: Dictionary = session.start_next_hand()
	_equal(command.state.phase, "COMPLETE", "Funds rechecked at start")
	_equal(command.summary.reason, "insufficient_funds", "No new hand can start")
	_equal(command.summary.hands_played, 1, "No extra completed hand")
	_equal(command.summary.net_change, 5, "Session profit excludes external wallet changes")
	_equal(fixture.wallet.transactions.size(), count, "No new transaction")
	return true


func test_funds_lost_after_selection_can_end_with_zero_hands() -> bool:
	var fixture := _ready()
	fixture.wallet.balance = 4
	var command: Dictionary = fixture.session.start_next_hand()
	_equal(command.state.phase, "COMPLETE", "Session ends if first stake becomes unaffordable")
	_equal(command.summary.hands_played, 0, "No first hand counted")
	_equal(fixture.wallet.transactions.size(), 0, "No deduction")
	return true


func test_locked_options_and_live_unlocks() -> bool:
	var fixture := _fixture()
	var session: RefCounted = fixture.session
	session.open_blackjack("lobby")
	var before: Dictionary = session.get_public_state()
	_equal(before.stake_options[1].unlocked, false, "Higher stake visible but locked")
	_assert_rejected(session, session.select_stake("large"), before, "stake_locked")
	fixture.unlocks.granted["higher_stakes"] = true
	_equal(session.get_public_state().stake_options[1].unlocked, true, "Progression unlock reflected")
	var command: Dictionary = session.select_stake("large")
	_equal(command.accepted, true, "Unlocked stake selectable")
	_equal(command.state.selected_stake.amount, 25, "Higher stake selected")
	_equal(fixture.wallet.transactions.size(), 0, "Unlock/selection does not charge")
	return true


func test_unlock_check_revalidated_before_hand_start() -> bool:
	var fixture := _fixture()
	fixture.unlocks.granted["higher_stakes"] = true
	var session: RefCounted = fixture.session
	session.open_blackjack("lobby")
	session.select_stake("large")
	fixture.unlocks.granted["higher_stakes"] = false
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.start_next_hand(_deck()), before, "stake_locked")
	_equal(fixture.wallet.transactions.size(), 0, "Locked stake not deducted")
	return true


func test_no_unlock_provider_keeps_gated_options_locked() -> bool:
	var fixture := _fixture()
	var session := Session.new(fixture.wallet, fixture.tables)
	session.open_blackjack("lobby")
	_equal(session.get_public_state().stake_options[0].unlocked, true, "Ungated option available")
	var before := session.get_public_state()
	_assert_rejected(session, session.select_stake("large"), before, "stake_locked")
	return true


func test_high_roller_table_has_its_own_options_and_limit() -> bool:
	var fixture := _fixture()
	fixture.unlocks.granted["high_roller_stakes"] = true
	var session: RefCounted = fixture.session
	var command: Dictionary = session.open_blackjack("high_roller")
	_equal(command.state.max_hands, 3, "Room-specific limit")
	_equal(command.state.stake_options.size(), 1, "Room-specific option list")
	_equal(command.state.stake_options[0].amount, 50, "Room-specific stake")
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.select_stake("small"), before, "unknown_stake")
	_equal(session.select_stake("roller").accepted, true, "Room stake selectable")
	return true


func test_invalid_tables_and_unknown_ids_are_rejected() -> bool:
	var fixture := _fixture()
	var session: RefCounted = fixture.session
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.open_blackjack("missing"), before, "unknown_table")
	var invalid_configs: Array = [null, {}, {"max_hands": 0, "stake_options": [{"option_id": "x", "amount": 5}]},
		{"max_hands": 1.5, "stake_options": [{"option_id": "x", "amount": 5}]}, {"stake_options": []}, {"stake_options": 5}]
	for bad_option in [null, {}, {"option_id": "", "amount": 5}, {"option_id": "x", "amount": 0},
		{"option_id": "x", "amount": 5.0}, {"option_id": "x", "amount": 5, "label": 5},
		{"option_id": "x", "amount": 5, "unlock_id": 5}]:
		invalid_configs.append({"stake_options": [bad_option]})
	invalid_configs.append({"stake_options": [{"option_id": "x", "amount": 5}, {"option_id": "x", "amount": 7}]})
	for config in invalid_configs:
		var invalid := Session.new(fixture.wallet, {"bad": config})
		before = invalid.get_public_state()
		_assert_rejected(invalid, invalid.open_blackjack("bad"), before, "invalid_table")
	_equal(fixture.wallet.transactions.size(), 0, "Config errors never charge")
	return true


func test_missing_wallet_is_rejected() -> bool:
	var session := Session.new(null)
	var before := session.get_public_state()
	_assert_rejected(session, session.open_blackjack("lobby_blackjack"), before, "invalid_wallet")
	return true


func test_configured_default_hand_limit_and_label() -> bool:
	var wallet := FakeWallet.new()
	var session := Session.new(wallet, {"custom": {"stake_options": [{"option_id": "odd", "amount": 7}]}})
	var command := session.open_blackjack("custom")
	_equal(command.state.max_hands, 5, "Omitted max_hands defaults to five")
	_equal(command.state.stake_options[0].label, "7", "Default stake label")
	_equal(session.select_stake("odd").accepted, true, "Odd configured stake accepted")
	return true


func test_duplicate_open_and_actions_before_hand_are_rejected() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.open_blackjack("high_roller"), before, "invalid_phase")
	_assert_rejected(session, session.hit(), before, "invalid_phase")
	_assert_rejected(session, session.stand(), before, "invalid_phase")
	_assert_rejected(session, session.retry_pending_transaction(), before, "invalid_phase")
	return true


func test_debit_failure_starts_no_hand_and_can_be_retried() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	fixture.wallet.fail_next_debits = 1
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.start_next_hand(_deck()), before, "wallet_rejected")
	_equal(fixture.wallet.transactions.size(), 0, "Failed debit changed no money")
	var command := _finish_hand(session)
	_equal(command.state.balance, 105, "Retry charges and settles normally")
	_equal(command.state.hands_played, 1, "No failed attempt counted")
	return true


func test_setup_failure_refunds_stake_and_retry_uses_new_transaction() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.start_next_hand([_card(1)]), before, "invalid_deck")
	_equal(fixture.wallet.balance, 100, "Failed setup refunded immediately")
	_equal(fixture.wallet.transactions.size(), 2, "Deduction and compensating refund")
	var command := _finish_hand(session)
	_equal(command.state.balance, 105, "New attempt actually deducts a fresh stake")
	_equal(fixture.wallet.transactions.size(), 4, "Retry uses fresh deduction ID")
	_equal(command.state.hand_number, 1, "Setup failure consumed no hand")
	return true


func test_setup_refund_failure_blocks_play_until_retry_succeeds() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	fixture.wallet.fail_next_credits = 1
	var command: Dictionary = session.start_next_hand([_card(1)])
	_equal(command.accepted, false, "Bad setup rejected")
	_equal(command.error.code, "refund_pending", "Refund needs retry")
	_equal(command.state.phase, "REFUND_PENDING", "Hold session while stake is owed")
	_equal(command.state.balance, 95, "Stake still deducted until refund works")
	_equal(command.state.hands_played, 0, "No hand played")
	var refund_id: String = command.state.pending_transaction.transaction_id
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.leave_table(), before, "invalid_phase")
	_assert_rejected(session, session.start_next_hand(), before, "invalid_phase")
	fixture.wallet.fail_next_credits = 1
	_assert_rejected(session, session.retry_pending_transaction(), before, "wallet_rejected")
	command = session.retry_pending_transaction()
	_equal(command.state.phase, "READY", "Refund restores original phase")
	_equal(command.state.balance, 100, "Stake restored once")
	_equal(command.state.pending_transaction, null, "Refund no longer pending")
	_equal(fixture.wallet.attempts[-1].transaction_id, refund_id, "Same refund ID on every retry")
	_equal(_finish_hand(session).state.balance, 105, "Play can resume after refund")
	return true


func test_payout_failure_retries_once_without_replaying_hand() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	session.start_next_hand(_deck())
	fixture.wallet.fail_next_credits = 1
	var command: Dictionary = session.stand()
	_equal(command.accepted, true, "Move resolved despite pending wallet credit")
	_equal(command.state.phase, "PAYOUT_PENDING", "Payout must complete first")
	_equal(command.state.balance, 95, "Credit not yet applied")
	_equal(command.result, null, "No financially settled result yet")
	_equal(command.state.hands_played, 0, "Pending hand not counted as paid")
	_equal(_events_of(command, "round_finished").size(), 1, "Engine finished once")
	_equal(_events_of(command, "hand_settled").size(), 0, "No settled event before credit")
	var return_id: String = command.state.pending_transaction.transaction_id
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.leave_table(), before, "invalid_phase")
	_assert_rejected(session, session.start_next_hand(), before, "invalid_phase")
	_assert_rejected(session, session.stand(), before, "invalid_phase")
	fixture.wallet.fail_next_credits = 1
	_assert_rejected(session, session.retry_pending_transaction(), before, "wallet_rejected")
	command = session.retry_pending_transaction()
	_equal(command.state.phase, "BETWEEN_HANDS", "Retry completes hand")
	_equal(command.state.balance, 105, "Full return credited exactly once")
	_equal(command.state.hands_played, 1, "One completed hand")
	_equal(command.result.returned_amount, 10, "Original payout retained")
	_equal(fixture.wallet.attempts[-1].transaction_id, return_id, "Stable payout ID")
	_equal(_events_of(command, "round_finished").size(), 0, "Retry does not rerun dealer or engine")
	before = session.get_public_state()
	_assert_rejected(session, session.retry_pending_transaction(), before, "invalid_phase")
	_equal(fixture.wallet.transactions.size(), 2, "Exactly two successful transfers")
	return true


func test_final_natural_waits_for_credit_before_session_completion() -> bool:
	var fixture := _ready(100, 1)
	var session: RefCounted = fixture.session
	fixture.wallet.fail_next_credits = 1
	var command: Dictionary = session.start_next_hand(_deck("natural"))
	_equal(command.state.phase, "PAYOUT_PENDING", "Natural can finish inside start command")
	_equal(command.summary, null, "Final summary waits for payout")
	var before: Dictionary = session.get_public_state()
	_assert_rejected(session, session.acknowledge_result(), before, "invalid_phase")
	command = session.retry_pending_transaction()
	_equal(command.state.phase, "COMPLETE", "Final payout ends session")
	_equal(command.summary.reason, "hand_limit", "Configured final hand")
	_equal(command.summary.ending_balance, 108, "Rounded natural credited before summary")
	return true


func test_loss_with_zero_return_can_settle_after_wallet_retry() -> bool:
	var fixture := _ready(5)
	var session: RefCounted = fixture.session
	session.start_next_hand(_deck("loss"))
	fixture.wallet.fail_next_credits = 1
	_equal(session.stand().state.phase, "PAYOUT_PENDING", "Zero return still has settlement identity")
	var command: Dictionary = session.retry_pending_transaction()
	_equal(command.state.phase, "COMPLETE", "Retry counts loss and ends for insufficient funds")
	_equal(command.result.returned_amount, 0, "No loss refund")
	_equal(command.state.balance, 0, "No money manufactured by retry")
	return true


func test_player_bust_settles_through_controller() -> bool:
	var fixture := _ready()
	var command := _finish_hand(fixture.session, "bust")
	_equal(command.result.reason, "player_bust", "Hit can finish a hand")
	_equal(command.state.phase, "BETWEEN_HANDS", "Bust moves session between hands")
	_equal(command.state.balance, 95, "Bust loses stake")
	return true


func test_closed_session_can_reopen_with_fresh_history_and_ids() -> bool:
	var fixture := _ready(100, 1)
	var session: RefCounted = fixture.session
	var previous := _finish_hand(session)
	session.acknowledge_result()
	var command: Dictionary = session.open_blackjack("lobby")
	_check(command.state.session_id != previous.state.session_id, "New session identity")
	_equal(command.state.starting_balance, 105, "New session starts from updated wallet")
	_equal(command.state.hand_number, 0, "Hand counter reset")
	_equal(command.state.results, [], "Old results cleared")
	_equal(command.state.summary, null, "Old summary cleared")
	session.select_stake("small")
	command = _finish_hand(session)
	_equal(command.state.balance, 110, "New session transactions do not collide")
	_equal(fixture.wallet.transactions.size(), 4, "Both sessions charged and settled")
	return true


func test_controller_instances_share_wallet_without_id_collisions() -> bool:
	var fixture := _ready()
	var first: RefCounted = fixture.session
	var second := Session.new(fixture.wallet, fixture.tables, fixture.unlocks.is_unlocked, 42)
	second.open_blackjack("lobby")
	second.select_stake("small")
	_check(first.get_public_state().session_id != second.get_public_state().session_id, "Independent session IDs")
	first.start_next_hand(_deck())
	second.start_next_hand(_deck())
	first.stand()
	second.stand()
	_equal(fixture.wallet.balance, 110, "Both stakes and payouts applied")
	_equal(fixture.wallet.transactions.size(), 4, "Four distinct transaction IDs")
	return true


func test_copied_configs_states_events_and_results() -> bool:
	var fixture := _fixture()
	fixture.tables.lobby.max_hands = 1
	fixture.tables.lobby.stake_options[0].amount = 99
	var session: RefCounted = fixture.session
	var command: Dictionary = session.open_blackjack("lobby")
	_equal(command.state.max_hands, 5, "Constructor copied table configuration")
	_equal(command.state.stake_options[0].amount, 5, "Constructor copied nested options")
	command.state.stake_options[0].amount = 50
	session.select_stake("small")
	command = session.start_next_hand(_deck())
	command.state.selected_stake.amount = 100
	command.state.hand.seats[0].hands[0].cards[0].rank = 1
	_events_of(command, "card_dealt")[0].card.rank = 1
	_equal(session.get_public_state().selected_stake.amount, 5, "Output stake changes do not affect controller")
	_equal(session.get_public_state().hand.seats[0].hands[0].cards[0].rank, 10, "Output card changes do not affect engine")
	command = session.stand()
	command.result.returned_amount = 999
	command.state.results[0].returned_amount = 888
	_events_of(command, "hand_settled")[0].result.returned_amount = 777
	_equal(session.get_public_state().results[0].returned_amount, 10, "Stored hand result protected")
	command = session.leave_table()
	command.summary.ending_balance = 1
	_events_of(command, "session_finished")[0].summary.ending_balance = 2
	_equal(session.get_public_state().summary.ending_balance, 105, "Stored summary protected")
	return true


func test_forwarded_events_preserve_visibility_and_session_order() -> bool:
	var fixture := _fixture(100, 1)
	var session: RefCounted = fixture.session
	var commands: Array = [session.open_blackjack("lobby"), session.select_stake("small"), session.start_next_hand(_deck())]
	var initial: Dictionary = commands[-1]
	_equal(_events_of(initial, "card_dealt")[3].card, {"face_up": false}, "Controller does not leak hole card")
	commands.append(session.stand())
	commands.append(session.acknowledge_result())
	var sequence: int = 0
	for command in commands:
		for event in command.events:
			sequence += 1
			_equal(event.sequence, sequence, "Sequence spans all session commands")
			_equal(event.session_id, initial.state.session_id, "Stable session identity on events")
			if event.source == "engine":
				_equal(event.hand_number, 1, "Engine event targets correct session hand")
				_check(event.has("round_sequence"), "Original engine sequence retained")
	_equal(commands[-1].events[-1].type, "session_closed", "Closure follows summary acknowledgement")
	return true


func test_synchronous_wallet_callback_cannot_start_another_hand() -> bool:
	var fixture := _ready()
	var session: RefCounted = fixture.session
	var responses: Array = []
	fixture.wallet.on_transaction = func() -> void:
		responses.append(session.start_next_hand(_deck()))
	var command: Dictionary = session.start_next_hand(_deck())
	fixture.wallet.on_transaction = Callable()
	_equal(command.accepted, true, "Outer start succeeds")
	_equal(responses.size(), 1, "Wallet callback ran")
	_equal(responses[0].error.code, "busy", "Nested start rejected")
	_equal(fixture.wallet.transactions.size(), 1, "Reentrancy did not double-charge")
	return true


func test_fake_wallet_enforces_idempotence_and_funds() -> bool:
	var wallet := FakeWallet.new(10)
	_equal(wallet.apply_transaction("debit", -5), true, "Initial debit")
	_equal(wallet.apply_transaction("debit", -5), true, "Same transaction can be acknowledged again")
	_equal(wallet.balance, 5, "Duplicate debit not applied again")
	_equal(wallet.apply_transaction("debit", -4), false, "Same ID cannot have a different amount")
	_equal(wallet.apply_transaction("too_much", -6), false, "Balance cannot go negative")
	_equal(wallet.apply_transaction("return", 10), true, "Payout")
	_equal(wallet.apply_transaction("return", 10), true, "Duplicate payout")
	_equal(wallet.balance, 15, "Payout applied once")
	wallet.balance = FakeWallet.MAX_BALANCE
	_equal(wallet.apply_transaction("overflow", 1), false, "Credit cannot overflow")
	return true
