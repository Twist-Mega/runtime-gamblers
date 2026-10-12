extends SceneTree
## Exercise the actual display scene and its buttons, including queued playback.

const DebugScene = preload("res://tests/blackjack/blackjack_debug.tscn")

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
		var completed: Variant = await call(test_name)
		_check(completed is bool and completed == true, "Test completed without a runtime error")
		print("%s %s" % ["PASS" if _failures == failures_before else "FAIL", test_name])
	print("Blackjack display: %d tests, %d checks, %d failures." % [names.size(), _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("%s: %s" % [_current_test, message])


func _equal(actual: Variant, expected: Variant, message: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _view(balance: int = 1000, delay: float = 0.0) -> Control:
	var view: Control = DebugScene.instantiate()
	view.starting_balance = balance
	view.deal_delay = delay
	root.add_child(view)
	await process_frame
	await _idle(view)
	return view


func _idle(view: Control) -> void:
	# Bound the wait so broken playback fails rather than hanging the suite.
	for frame in range(300):
		if not view._busy:
			return
		await process_frame
	_check(false, "Display finished event playback")


func _press(view: Control, action: String) -> void:
	_check(not view._buttons[action].disabled, "Button enabled: " + action)
	view._buttons[action].pressed.emit()
	await _idle(view)


func _choose_starter(view: Control) -> void:
	_check(not view._stake_buttons.starter.disabled, "Starter stake selectable")
	view._stake_buttons.starter.pressed.emit()
	await _idle(view)


func _dispose(view: Control) -> void:
	view.queue_free()
	await process_frame


func test_initial_controls_and_stake_unlock() -> bool:
	var view: Control = await _view()
	_equal(view._state.phase, "SELECTING_STAKE", "Table opened on launch")
	_equal(view._balance_label.text, "Balance: 1000", "Development balance visible")
	_equal(view._buttons.hit.disabled, true, "Hit disabled before deal")
	_equal(view._buttons.start_next_hand.disabled, true, "Stake must be selected first")
	_equal(view._stake_buttons.higher.disabled, true, "Higher stake starts locked")
	view._unlock.button_pressed = true
	_equal(view._stake_buttons.higher.disabled, false, "Testing unlock enables higher stake")
	view._stake_buttons.higher.pressed.emit()
	await _idle(view)
	_equal(view._state.selected_stake.amount, 25, "Button selects higher stake through controller")
	_equal(view._buttons.start_next_hand.disabled, false, "First hand now available")
	_equal(view._unlock.disabled, true, "Unlock control fixed during session")
	await _dispose(view)
	return true


func test_actual_buttons_play_push_and_conceal_dealer() -> bool:
	var view: Control = await _view()
	view._mode.select(3)
	await _choose_starter(view)
	await _press(view, "start_next_hand")
	_equal(view._state.phase, "PLAYING", "Playable hand started")
	_equal(view._displayed_cards.dealer[1], {"face_up": false}, "Hidden dealer card remains concealed")
	_equal(view._card_rows.dealer.get_child(1).get_child(0).text, "Face\ndown", "Hidden card rendered as a card back")
	_check(view._total_labels.dealer.text.begins_with("Visible: 9"), "Full dealer total not exposed")
	_equal(view._buttons.leave_table.disabled, true, "Cannot leave an active hand")
	_equal(view._mode.disabled, true, "Preset cannot change mid-hand")
	await _press(view, "stand")
	_equal(view._state.phase, "BETWEEN_HANDS", "Stand settles hand")
	_equal(view._displayed_cards.dealer[1].face_up, true, "Dealer revealed after stand")
	_equal(view._state.balance, 1000, "Push returns stake")
	_check(view._result_label.text.contains("PUSH"), "Outcome shown")
	_equal(view._buttons.leave_table.disabled, false, "Can leave between hands")
	_equal(view._buttons.start_next_hand.text, "Next Hand", "Next hand button label")
	await _dispose(view)
	return true


func test_odd_stake_blackjack_displays_rounded_return() -> bool:
	var view: Control = await _view()
	view._mode.select(1)
	await _choose_starter(view)
	await _press(view, "start_next_hand")
	_equal(view._state.phase, "BETWEEN_HANDS", "Natural finishes during initial deal")
	_equal(view._state.balance, 1008, "Odd-stake blackjack earns eight")
	_check(view._result_label.text.contains("BLACKJACK"), "Natural outcome shown")
	_check(view._result_label.text.contains("Returned: 13"), "Rounded stake plus winnings shown")
	_equal(view._buttons.hit.disabled, true, "No actions after natural")
	await _dispose(view)
	return true


func test_all_five_hands_summary_and_new_session() -> bool:
	var view: Control = await _view()
	view._mode.select(3)
	await _choose_starter(view)
	for hand_number in range(1, 6):
		await _press(view, "start_next_hand")
		_equal(view._result_label.text, "", "Previous result cleared during the next active hand")
		await _press(view, "stand")
		_equal(view._state.hands_played, hand_number, "Displayed completed hand count")
	_equal(view._state.phase, "COMPLETE", "Fifth hand ends session")
	_equal(view._buttons.start_next_hand.disabled, true, "Sixth hand unavailable")
	_check(view._summary_label.visible, "Session summary visible")
	_check(view._summary_label.text.contains("Hands: 5"), "Summary includes hand count")
	await _press(view, "acknowledge_result")
	_equal(view._state.phase, "CLOSED", "Close session button works")
	await _press(view, "open_blackjack")
	_equal(view._state.phase, "SELECTING_STAKE", "New session ready for a new stake")
	_equal(view._state.balance, 1000, "New session keeps money")
	_equal(view._state.hand_number, 0, "New hand count")
	_equal(view._card_rows.player.get_child_count(), 0, "Old cards cleared")
	_equal(view._summary_label.visible, false, "Old summary cleared")
	await _dispose(view)
	return true


func test_hit_to_bust_and_leave_between_hands() -> bool:
	var view: Control = await _view()
	view._mode.select(2)
	await _choose_starter(view)
	await _press(view, "start_next_hand")
	await _press(view, "hit")
	_equal(view._state.balance, 995, "Bust loses only one stake")
	_check(view._result_label.text.contains("LOSS"), "Loss displayed")
	_equal(view._state.phase, "BETWEEN_HANDS", "Leave allowed after bust")
	await _press(view, "leave_table")
	_equal(view._state.phase, "COMPLETE", "Leaving shows summary")
	_check(view._summary_label.text.contains("left the table"), "Departure summary shown")
	await _press(view, "acknowledge_result")
	_equal(view._state.balance, 995, "Leaving and closing preserve money")
	await _dispose(view)
	return true


func test_low_funds_session_and_reset() -> bool:
	var view: Control = await _view(5)
	view._mode.select(2)
	await _choose_starter(view)
	await _press(view, "start_next_hand")
	await _press(view, "hit")
	_equal(view._state.phase, "COMPLETE", "Low-funds loss ends session")
	_equal(view._state.balance, 0, "Balance reaches zero")
	_check(view._summary_label.text.contains("insufficient funds"), "End reason visible")
	view._reset_button.pressed.emit()
	await _idle(view)
	_equal(view._state.phase, "SELECTING_STAKE", "Reset restarts table")
	_equal(view._state.balance, 5, "Reset uses configured starting balance")
	_equal(view._state.hands_played, 0, "Reset clears history")
	_equal(view._summary_label.visible, false, "Reset clears summary")
	await _dispose(view)
	return true


func test_cancel_before_first_hand() -> bool:
	var view: Control = await _view()
	await _choose_starter(view)
	await _press(view, "leave_table")
	_equal(view._state.phase, "CLOSED", "Cancel before play closes directly")
	_equal(view._state.balance, 1000, "Cancel costs nothing")
	_equal(view._wallet.transactions.size(), 0, "No money transaction before dealing")
	await _dispose(view)
	return true


func test_dealer_bust_preset() -> bool:
	var view: Control = await _view()
	view._mode.select(4)
	await _choose_starter(view)
	await _press(view, "start_next_hand")
	await _press(view, "stand")
	_equal(view._state.results[0].reason, "dealer_bust", "Preset reaches dealer bust")
	_equal(view._state.balance, 1005, "Ordinary win pays 1:1")
	_equal(view._displayed_cards.dealer.size(), 3, "Dealer draw appears on table")
	await _dispose(view)
	return true


func test_pending_return_button_and_retry() -> bool:
	var view: Control = await _view()
	view._mode.select(1)
	await _choose_starter(view)
	view._fail_button.pressed.emit()
	await _press(view, "start_next_hand")
	_equal(view._state.phase, "PAYOUT_PENDING", "Testing tool triggers failed return")
	_check(view._result_label.text.contains("Return pending: 13"), "Pending result explains the owed return")
	_equal(view._buttons.retry_pending_transaction.disabled, false, "Retry button available")
	_equal(view._buttons.leave_table.disabled, true, "Cannot leave before money is settled")
	_equal(view._state.balance, 995, "Credit has not yet occurred")
	await _press(view, "retry_pending_transaction")
	_equal(view._state.balance, 1008, "Original payout applied once")
	_equal(view._state.phase, "BETWEEN_HANDS", "Play can continue")
	_check(view._result_label.text.contains("Returned: 13"), "Result appears after successful return")
	await _dispose(view)
	return true


func test_playback_blocks_double_clicks_and_reset() -> bool:
	var view: Control = await _view(1000, 0.03)
	view._mode.select(1)
	await _choose_starter(view)
	view._buttons.start_next_hand.pressed.emit()
	_equal(view._busy, true, "Event playback is in progress")
	_equal(view._buttons.start_next_hand.disabled, true, "Start disabled during playback")
	_equal(view._reset_button.disabled, true, "Reset disabled during playback")
	# Signal emission bypasses widget disabling; the adapter's guard must still hold.
	view._buttons.start_next_hand.pressed.emit()
	view._reset_button.pressed.emit()
	await _idle(view)
	_equal(view._state.hands_played, 1, "Repeated request did not start another natural hand")
	_equal(view._wallet.transactions.size(), 2, "Only one stake and one payout applied")
	_equal(view._state.balance, 1008, "No reset or second charge during playback")
	await _dispose(view)
	return true
