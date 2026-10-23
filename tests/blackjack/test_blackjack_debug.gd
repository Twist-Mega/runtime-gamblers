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


func _view(balance: int = 1000, delay: float = 0.0, seats: Array = [], hosted: bool = false) -> Control:
	var view: Control = DebugScene.instantiate()
	view.return_summary_to_host = hosted
	view.starting_balance = balance
	view.deal_delay = delay
	view.ai_first_move_delay = delay
	view.ai_next_move_delay = delay
	view.ai_seats.assign(seats)
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


func _dispose(view: Control) -> void:
	view.queue_free()
	await process_frame


func test_initial_controls_with_automatic_stake() -> bool:
	var view: Control = await _view()
	_equal(view._state.phase, "READY", "Table opens ready to start")
	_equal(view._balance_label.text, "Balance: 1000", "Development balance visible")
	_equal(view._buttons.hit.disabled, true, "Hit disabled before deal")
	_equal(view._state.selected_stake.amount, 5, "Stake five selected through controller")
	_equal(view._stake_label.text, "Stake: 5", "Stake displayed without selection controls")
	_equal(view._buttons.start_next_hand.disabled, false, "First hand available immediately")
	_equal(view._wallet.transactions.size(), 0, "Automatic selection does not charge money")
	for label in view.find_children("*", "Label", true, false):
		_check(not label.text.contains("Choose") and not label.text.contains("Fake money"), "Selection prompts and subtitle removed")
	for button in view.find_children("*", "Button", true, false):
		_check(not button.text.begins_with("Stake ") and button.text != "Unlock higher stakes", "Stake selection buttons removed")
	await _dispose(view)
	return true


func test_standalone_scaling_fits_ui_and_restores_world_settings() -> bool:
	var original_size := root.content_scale_size
	var original_mode := root.content_scale_mode
	var original_stretch := root.content_scale_stretch
	var view: Control = await _view()
	_equal(root.content_scale_size, Vector2i(1280, 720), "Debug scene uses its own UI resolution")
	_equal(root.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "UI draws at window resolution")
	_equal(root.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "UI can fit non-integer window sizes")
	_check(view.size.x >= 1280 and view.size.y >= 720, "Table receives the full debug layout area")
	for panel in view._seat_panels.values():
		_check(panel.get_global_rect().end.x <= view.get_global_rect().end.x, "Seat panel fits horizontally: %s" % panel.get_global_rect())
	await _dispose(view)
	_equal(root.content_scale_size, original_size, "Leaving restores world resolution")
	_equal(root.content_scale_mode, original_mode, "Leaving restores world rendering mode")
	_equal(root.content_scale_stretch, original_stretch, "Leaving restores world integer scaling")
	return true


func test_embedded_display_preserves_host_window_scaling() -> bool:
	var original_size := root.content_scale_size
	var original_mode := root.content_scale_mode
	var original_stretch := root.content_scale_stretch
	var host := Control.new()
	root.add_child(host)
	var view: Control = DebugScene.instantiate()
	host.add_child(view)
	await process_frame
	await _idle(view)
	_equal(root.content_scale_size, original_size, "Embedded table keeps host resolution")
	_equal(root.content_scale_mode, original_mode, "Embedded table keeps host rendering mode")
	_equal(root.content_scale_stretch, original_stretch, "Embedded table keeps host scaling")
	host.queue_free()
	await process_frame
	return true


func test_populated_table_stays_inside_view_during_playback() -> bool:
	var view: Control = await _view(1000, 0.01, ["left_2", "left_1", "right_1", "right_2"])
	view._mode.select(3)
	var overflow := ""
	for action in ["start_next_hand", "hit", "stand"]:
		view._buttons[action].pressed.emit()
		for frame in range(300):
			await process_frame
			for seat_id in view._seat_panels:
				var panel: Control = view._seat_panels[seat_id]
				if panel.get_global_rect().end.x > view.get_global_rect().end.x + 1:
					overflow = "%s extends to %s beyond viewport %s" % [seat_id, panel.get_global_rect().end.x, view.get_global_rect().end.x]
			if not view._busy:
				break
		await _idle(view)
	_equal(overflow, "", "Populated seats fit throughout dealing, hitting, and settlement")
	_equal(view._state.phase, "BETWEEN_HANDS", "Layout check plays a complete table round")
	await _dispose(view)
	return true


func test_automatic_stake_rejects_insufficient_funds() -> bool:
	var view: Control = await _view(4)
	_equal(view._state.selected_stake, null, "Unaffordable stake remains unselected")
	_equal(view._stake_label.text, "Stake: 5", "Required stake remains visible")
	_equal(view._buttons.start_next_hand.disabled, true, "Insufficient funds prevents starting")
	_equal(view._buttons.leave_table.disabled, false, "Leaving remains available")
	_equal(view._wallet.transactions.size(), 0, "Insufficient funds does not charge money")
	_check(view._status_label.text.contains("exceeds your balance"), "Controller explains insufficient funds")
	await _press(view, "leave_table")
	_equal(view._state.phase, "CLOSED", "Underfunded table can close")
	await _dispose(view)
	return true


func test_actual_buttons_play_push_and_conceal_dealer() -> bool:
	var view: Control = await _view()
	view._mode.select(3)
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
	_equal(view._state.phase, "READY", "New session automatically selects stake five")
	_equal(view._stake_label.text, "Stake: 5", "New session keeps the stake display")
	_equal(view._buttons.start_next_hand.disabled, false, "New session can start immediately")
	_equal(view._state.balance, 1000, "New session keeps money")
	_equal(view._state.hand_number, 0, "New hand count")
	_equal(view._card_rows.player.get_child_count(), 0, "Old cards cleared")
	_equal(view._summary_label.visible, false, "Old summary cleared")
	await _dispose(view)
	return true


func test_hosted_fifth_hand_waits_for_close_session() -> bool:
	var view: Control = await _view(1000, 0.001, [], true)
	var closed: Array = []
	view.session_closed.connect(func(summary: Dictionary): closed.append(summary))
	view._mode.select(3)
	_check(not view._buttons.acknowledge_result.visible, "Close Session hidden before play")
	for hand_number in range(1, 6):
		await _press(view, "start_next_hand")
		_check(not view._buttons.acknowledge_result.visible, "Close Session hidden during hand")
		view._buttons.stand.pressed.emit()
		_check(view._busy, "Final result playback is asynchronous")
		_check(not view._buttons.acknowledge_result.visible, "Close Session hidden during result playback")
		await _idle(view)
		_equal(view._buttons.acknowledge_result.visible, hand_number == 5, "Close Session appears only after fifth hand settles")
	_equal(view._state.phase, "COMPLETE", "Hosted fifth hand waits for acknowledgement")
	_equal(closed.size(), 0, "Host has not received a close signal")
	_check(view._result_label.text.contains("PUSH"), "Final result remains visible")
	_check(view._card_rows.player.get_child_count() > 0, "Final cards remain visible")
	await _press(view, "acknowledge_result")
	_equal(closed.size(), 1, "Close Session returns summary to host once")
	_equal(closed[0].hands_played, 5, "Host receives all five hands")
	_equal(view._state.phase, "CLOSED", "Session closes on button press")
	await _dispose(view)
	return true


func test_hosted_insufficient_funds_waits_for_close_session() -> bool:
	var view: Control = await _view(5, 0.001, ["left_2", "left_1", "right_1", "right_2"], true)
	var closed: Array = []
	view.session_closed.connect(func(summary: Dictionary): closed.append(summary))
	view._mode.select(2)
	await _press(view, "start_next_hand")
	_equal(view._state.balance, 0, "Last stake spends remaining balance")
	_check(not view._buttons.acknowledge_result.visible, "Zero balance during play does not show Close Session")
	view._buttons.hit.pressed.emit()
	_check(view._busy, "Remaining table plays after player bust")
	_check(not view._buttons.acknowledge_result.visible, "Close Session hidden until whole round finishes")
	await _idle(view)
	_equal(view._state.phase, "COMPLETE", "Insufficient funds waits for acknowledgement")
	_equal(view._state.summary.reason, "insufficient_funds", "Session ends because next stake is unaffordable")
	_equal(closed.size(), 0, "Host does not close overlay automatically")
	_check(view._buttons.acknowledge_result.visible, "Close Session appears after round settles")
	_check(view._result_label.text.contains("LOSS"), "Final loss stays visible")
	_check(view._card_rows.player.get_child_count() > 0, "Final cards stay visible")
	await _press(view, "acknowledge_result")
	_equal(closed.size(), 1, "Close Session returns summary to host once")
	_equal(closed[0].hands_played, 1, "Summary includes the completed round")
	_equal(closed[0].ending_balance, 0, "Summary includes exhausted wallet balance")
	_equal(view._state.phase, "CLOSED", "Session closes on button press")
	await _dispose(view)
	return true


func test_hosted_leave_still_returns_directly() -> bool:
	var view: Control = await _view(1000, 0.0, [], true)
	var closed: Array = []
	view.session_closed.connect(func(summary: Dictionary): closed.append(summary))
	await _press(view, "leave_table")
	_equal(view._state.phase, "CLOSED", "Leave Table still closes hosted session directly")
	_equal(closed.size(), 1, "Leave Table returns summary to host")
	await _dispose(view)
	return true


func test_hit_to_bust_and_leave_between_hands() -> bool:
	var view: Control = await _view()
	view._mode.select(2)
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
	await _press(view, "start_next_hand")
	await _press(view, "hit")
	_equal(view._state.phase, "COMPLETE", "Low-funds loss ends session")
	_equal(view._state.balance, 0, "Balance reaches zero")
	_check(view._summary_label.text.contains("insufficient funds"), "End reason visible")
	view._reset_button.pressed.emit()
	await _idle(view)
	_equal(view._state.phase, "READY", "Reset restarts table with stake selected")
	_equal(view._stake_label.text, "Stake: 5", "Reset keeps the stake display")
	_equal(view._state.balance, 5, "Reset uses configured starting balance")
	_equal(view._state.hands_played, 0, "Reset clears history")
	_equal(view._summary_label.visible, false, "Reset clears summary")
	await _dispose(view)
	return true


func test_cancel_before_first_hand() -> bool:
	var view: Control = await _view()
	await _press(view, "leave_table")
	_equal(view._state.phase, "CLOSED", "Cancel before play closes directly")
	_equal(view._state.balance, 1000, "Cancel costs nothing")
	_equal(view._wallet.transactions.size(), 0, "No money transaction before dealing")
	await _dispose(view)
	return true


func test_dealer_bust_preset() -> bool:
	var view: Control = await _view()
	view._mode.select(4)
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


func test_full_ai_table_presets_still_demonstrate_each_human_outcome() -> bool:
	var outcomes := {1: "BLACKJACK", 2: "LOSS", 3: "PUSH", 4: "WIN"}
	for mode in outcomes:
		var view: Control = await _view(1000, 0.0, ["left_2", "left_1", "right_1", "right_2"])
		view._mode.select(mode)
		await _press(view, "start_next_hand")
		if mode == 2:
			await _press(view, "hit")
		elif mode in [3, 4]:
			await _press(view, "stand")
		_equal(view._state.phase, "BETWEEN_HANDS", "Display advances all AI and the dealer automatically")
		_check(view._result_label.text.contains(outcomes[mode]), "Preset retains its human outcome with a full table")
		for seat_id in ["left_2", "left_1", "right_1", "right_2"]:
			_equal(view._card_rows[seat_id].get_child_count(), 2, "Generic AI's completed hand is visible")
		_equal(view._wallet.transactions.size(), 2, "AI results do not add wallet transactions")
		await _dispose(view)
	return true


func test_partial_occupancy_shows_empty_chairs_and_keeps_config_across_hands() -> bool:
	var view: Control = await _view(1000, 0.0, ["right_1"])
	_equal(view._total_labels.left_1.text, "Empty chair", "Unoccupied seats are clearly labelled")
	view._mode.select(3)
	for hand_number in range(2):
		await _press(view, "start_next_hand")
		await _press(view, "stand")
		_equal(view._card_rows.left_1.get_child_count(), 0, "Empty chair never receives cards")
		_equal(view._card_rows.right_1.get_child_count(), 2, "Occupied chair remains across rounds")
	await _dispose(view)
	return true


func test_full_table_waits_for_human_input_before_and_after_hit() -> bool:
	var view: Control = await _view(1000, 0.01, ["left_2", "left_1", "right_1", "right_2"])
	view._mode.select(3)
	await _press(view, "start_next_hand")
	_equal(view._state.hand.phase, "PLAYER_TURN", "Left AI yields to the human")
	_equal(view._state.hand.active_seat_id, "player", "Human owns the current turn")
	_equal(view._highlighted_seat, "player", "Human seat is highlighted while awaiting input")
	_equal(view._buttons.hit.disabled, false, "Hit is available")
	_equal(view._buttons.stand.disabled, false, "Stand is available")
	var before: Dictionary = view._session.get_public_state()
	await create_timer(0.1).timeout
	_equal(view._session.get_public_state(), before, "Waiting cannot choose a move for the human")
	await _press(view, "hit")
	_equal(view._state.hand.phase, "PLAYER_TURN", "A nonterminal hit waits for another human decision")
	_equal(view._card_rows.player.get_child_count(), 3, "Only the requested card is dealt")
	_equal(view._highlighted_seat, "player", "Highlight stays with human after a nonterminal Hit")
	before = view._session.get_public_state()
	await create_timer(0.1).timeout
	_equal(view._session.get_public_state(), before, "Right AI cannot start until the human finishes")
	await _press(view, "stand")
	_equal(view._state.phase, "BETWEEN_HANDS", "Explicit Stand allows the remaining table to finish")
	_equal(view._highlighted_seat, "", "No active-seat highlight remains between hands")
	await _dispose(view)
	return true


func test_early_result_is_visible_during_fast_playback_and_input_stays_blocked() -> bool:
	var view: Control = await _view(1000, 0.03, ["right_1"])
	view.fast_forward_delay = 0.01
	view._mode.select(1)
	view._buttons.start_next_hand.pressed.emit()
	var saw_early_result := false
	for frame in range(300):
		if view._busy and view._fast_forward and view._result_label.text.contains("BLACKJACK"):
			saw_early_result = true
			break
		if not view._busy:
			break
		await process_frame
	_check(saw_early_result, "Human blackjack is shown while the remaining table animates")
	_equal(view._wallet.get_balance(), 1008, "Chips already credited while AI play finishes")
	_equal(view._buttons.leave_table.disabled, true, "Cannot leave during remaining table playback")
	_equal(view._buttons.start_next_hand.disabled, true, "Cannot overlap rounds during AI playback")
	_equal(view._event_delay({"type": "card_dealt"}), 0.01, "Remaining cards use fast-forward pacing")
	view._buttons.start_next_hand.pressed.emit()
	view._reset_button.pressed.emit()
	await _idle(view)
	_equal(view._state.hands_played, 1, "Forced repeated clicks do not start or reset another round")
	_equal(view._wallet.transactions.size(), 2, "Finishing AI does not pay blackjack twice")
	await _dispose(view)
	return true


func test_early_payout_retry_finishes_the_remaining_ai_in_the_display() -> bool:
	var view: Control = await _view(1000, 0.0, ["right_1"])
	view._mode.select(1)
	view._fail_button.pressed.emit()
	await _press(view, "start_next_hand")
	_equal(view._state.phase, "PAYOUT_PENDING", "Early credit failure shows retry")
	_equal(view._state.hand.phase, "AI_TURN", "Remaining AI survives the failed credit")
	await _press(view, "retry_pending_transaction")
	_equal(view._state.phase, "BETWEEN_HANDS", "Retry resumes and finishes AI playback")
	_equal(view._state.balance, 1008, "Exactly one natural payout")
	_equal(view._wallet.transactions.size(), 2, "No duplicated transfer")
	_equal(view._card_rows.right_1.get_child_count(), 2, "AI finishes after retry")
	await _dispose(view)
	return true


func test_ai_decision_delays_reset_per_seat_and_round() -> bool:
	var view: Control = await _view()
	view.deal_delay = 0.35
	view.ai_first_move_delay = 1.0
	view.ai_next_move_delay = 0.75
	var hit := {"type": "action_taken", "seat_id": "left_1", "action": "hit", "automatic": true}
	var stand := {"type": "action_taken", "seat_id": "left_1", "action": "stand", "automatic": true}
	_equal(view._ai_action_delay(hit), 1.0, "AI thinks one second before its first Hit")
	_equal(view._ai_action_delay(stand), 1.0, "AI also thinks one second if its first move is Stand")
	# Exercise the real playback bookkeeping without spending seconds on timers.
	view._fast_forward = true
	view.fast_forward_delay = 0.0
	await view._play_events([hit])
	view._fast_forward = false
	_equal(view._ai_action_delay(hit), 0.75, "A second Hit uses the same-turn delay")
	_equal(view._ai_action_delay(stand), 0.75, "Stand after a Hit uses the same-turn delay")
	_equal(view._ai_action_delay({"type": "action_taken", "seat_id": "right_1", "action": "stand"}), 1.0, "The next AI gets a fresh first-move delay")
	_equal(view._event_delay({"type": "card_dealt", "seat_id": "left_1", "card_index": 0}), 0.35, "Initial dealing pace is preserved")
	_equal(view._event_delay({"type": "card_dealt", "seat_id": "left_1", "card_index": 2}), 0.0, "A Hit's card adds no second pause")
	_equal(view._event_delay(stand), 0.0, "AI Stand adds no after-action pause")
	_equal(view._ai_action_delay({"type": "action_taken", "seat_id": "player", "action": "hit"}), 0.0, "Human actions get no AI thinking delay")
	view._fast_forward = true
	view.fast_forward_delay = 0.07
	_equal(view._ai_action_delay(hit), 0.07, "Known human outcome still fast-forwards AI")
	await view._play_events([{"type": "round_started"}])
	_equal(view._ai_action_delay(hit), 1.0, "A new round resets first-move timing")
	await _dispose(view)
	return true


func test_ai_stand_waits_before_announcing_the_move() -> bool:
	var view: Control = await _view(1000, 0.0, ["left_1"])
	var normal_style: StyleBox = view._seat_panels.left_1.get_theme_stylebox("panel")
	view.ai_first_move_delay = 0.03
	view._mode.select(3)
	view._buttons.start_next_hand.pressed.emit()
	_equal(view._busy, true, "Playback is waiting on the AI decision")
	_equal(view._state.hand.active_seat_id, "left_1", "Display keeps the AI turn active during its wait")
	_equal(view._highlighted_seat, "left_1", "AI is highlighted during its thinking pause")
	_check(view._seat_panels.left_1.get_theme_stylebox("panel") != normal_style, "Active AI has a distinct visible panel style")
	_check(not view._log.get_parsed_text().contains("Left 1: stand"), "AI's Stand is not announced before the wait")
	_equal(view._buttons.hit.disabled, true, "Human input stays disabled during the AI wait")
	await _idle(view)
	_check(view._log.get_parsed_text().contains("Left 1: stand"), "Stand is announced after the wait: %s" % view._log.get_parsed_text())
	_equal(view._state.hand.active_seat_id, "player", "AI yields to the human after its move")
	_equal(view._seat_panels.left_1.get_theme_stylebox("panel"), normal_style, "Previous AI highlight clears on handoff")
	_equal(view._buttons.hit.disabled, false, "Human can then choose a move")
	await _dispose(view)
	return true
