extends Control
## Standalone development display. Rules and money flow stay in the controller.

const Session = preload("res://scripts/blackjack/blackjack_session_controller.gd")
const Rules = preload("res://scripts/blackjack/blackjack_engine.gd")
const FakeWallet = preload("res://tests/blackjack/fake_wallet.gd")
const TABLE_ID = "development"
const DEBUG_VIEW_SIZE = Vector2i(1280, 720)
const STAKES = [
	{"option_id": "starter", "label": "Starter", "amount": 5},
]
const DEAL_MODES = ["Shuffled", "Player blackjack", "Hit to bust", "Push (stand)", "Dealer bust (stand)"]

@export_range(0, 1000000, 1) var starting_balance: int = 1000
@export_range(1, 100, 1) var max_hands: int = 5
@export_range(0.0, 1.0, 0.05) var deal_delay: float = 0.35
@export_range(0.0, 5.0, 0.05) var ai_first_move_delay: float = 1.0
@export_range(0.0, 5.0, 0.05) var ai_next_move_delay: float = 0.75
@export_range(0.0, 1.0, 0.01) var fast_forward_delay: float = 0.07
@export var ai_seats: Array[String] = ["left_2", "left_1", "right_1", "right_2"]

var _session: Session
var _wallet: FakeWallet
var _state: Dictionary = {}
var _busy: bool = false
var _displayed_cards: Dictionary = {"player": [], "dealer": []}
var _buttons: Dictionary = {}
var _card_rows: Dictionary = {}
var _total_labels: Dictionary = {}
var _seat_panels: Dictionary = {}
var _seat_styles: Dictionary = {}
var _seat_titles: Dictionary = {}
var _highlighted_seat: String = ""
var _balance_label: Label
var _progress_label: Label
var _stake_label: Label
var _status_label: Label
var _result_label: Label
var _summary_label: Label
var _log: RichTextLabel
var _mode: OptionButton
var _reset_button: Button
var _fail_button: Button
var _fast_forward: bool = false
var _ai_moves_seen: Dictionary = {}
var _saved_window_scaling: Dictionary = {}


func _ready() -> void:
	_configure_debug_window()
	_build_ui()
	_reset_test_session()


func _configure_debug_window() -> void:
	# F6 should fit the debug UI without changing the pixel-art world's settings.
	# An embedded table must leave its host window alone.
	if get_parent() != get_tree().root:
		return
	var window := get_window()
	_saved_window_scaling = {
		"content_scale_size": window.content_scale_size,
		"content_scale_mode": window.content_scale_mode,
		"content_scale_stretch": window.content_scale_stretch,
	}
	window.content_scale_size = DEBUG_VIEW_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _exit_tree() -> void:
	if _saved_window_scaling.is_empty():
		return
	var window := get_window()
	for property in _saved_window_scaling:
		window.set(property, _saved_window_scaling[property])
	_saved_window_scaling.clear()


func _build_ui() -> void:
	theme = Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("e6edf5"))
	var background := ColorRect.new()
	background.color = Color("101b29")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	_label("Blackjack development table", content, 24)
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation", 30)
	content.add_child(stats)
	_balance_label = _label("", stats)
	_progress_label = _label("", stats)
	_stake_label = _label("", stats)
	_status_label = _label("", content)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label = _label("", content)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label = _label("", content)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HFlowContainer.new()
	content.add_child(actions)
	for entry in [
		["start_next_hand", "Start Hand"], ["hit", "Hit"], ["stand", "Stand"],
		["leave_table", "Leave Table"], ["acknowledge_result", "Close Session"],
		["open_blackjack", "New Session"], ["retry_pending_transaction", "Retry Return"],
	]:
		var button := _button(entry[1], actions, _request.bind(entry[0]))
		button.name = entry[0]
		_buttons[entry[0]] = button
	_build_seat("dealer", "Dealer", content)
	var table := HBoxContainer.new()
	content.add_child(table)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_child(left)
	_build_seat("left_2", "AI - left outer", left)
	_build_seat("left_1", "AI - left inner", left)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 1.4
	table.add_child(center)
	_build_seat("player", "You", center)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_child(right)
	_build_seat("right_1", "AI - right inner", right)
	_build_seat("right_2", "AI - right outer", right)
	_label("Testing tools", content, 18)
	var tools := HFlowContainer.new()
	content.add_child(tools)
	_label("Next deal:", tools)
	_mode = OptionButton.new()
	_mode.name = "DealMode"
	for mode in DEAL_MODES:
		_mode.add_item(mode)
	tools.add_child(_mode)
	_fail_button = _button("Fail next return once", tools, _fail_next_return)
	_reset_button = _button("Reset test money", tools, _reset_test_session)
	_label("Move and money log", content, 18)
	_log = RichTextLabel.new()
	_log.name = "EventLog"
	_log.custom_minimum_size = Vector2(0, 140)
	_log.scroll_following = true
	_log.bbcode_enabled = false
	content.add_child(_log)


func _label(text: String, parent: Node, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_seat(seat_id: String, title: String, parent: Node) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d3044")
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6 if seat_id in Rules.AI_SEATS else 8
	style.content_margin_bottom = 6 if seat_id in Rules.AI_SEATS else 8
	var active_style: StyleBoxFlat = style.duplicate()
	active_style.bg_color = Color("30485b")
	active_style.border_color = Color("f2c66d")
	active_style.set_border_width_all(2)
	_seat_panels[seat_id] = panel
	_seat_styles[seat_id] = {"normal": style, "active": active_style}
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	# Stack and wrap headings so longer totals cannot widen the whole table.
	var heading := VBoxContainer.new()
	column.add_child(heading)
	var label := _label(title, heading, 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seat_titles[seat_id] = label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total_labels[seat_id] = _label("No cards", heading)
	_total_labels[seat_id].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cards := HFlowContainer.new()
	cards.custom_minimum_size.x = 64 if seat_id in Rules.AI_SEATS else 82
	cards.custom_minimum_size.y = 72 if seat_id in Rules.AI_SEATS else 88
	cards.add_theme_constant_override("h_separation", 8)
	column.add_child(cards)
	_card_rows[seat_id] = cards
	_displayed_cards[seat_id] = []


func _reset_test_session() -> void:
	if _busy:
		return
	_wallet = FakeWallet.new(starting_balance)
	_mode.select(0)
	_session = Session.new(_wallet, {TABLE_ID: {"max_hands": max_hands, "stake_options": STAKES,
		"ai_seats": ai_seats}})
	_state = _session.get_public_state()
	_reset_cards()
	_result_label.text = ""
	_summary_label.text = ""
	_log.clear()
	_request("open_blackjack")


func _fail_next_return() -> void:
	if _busy:
		return
	_wallet.fail_next_credits = 1
	_log_line("Testing: the next wallet return will fail once. Use Retry Return afterwards.")


func _request(action: String) -> void:
	if _busy:
		return
	_busy = true
	_sync_controls()
	var response: Dictionary
	match action:
		"open_blackjack":
			response = _session.open_blackjack(TABLE_ID)
		"start_next_hand":
			response = _session.start_next_hand(_scenario_deck())
		_:
			response = _session.call(action)
	while true:
		await _play_events(response.events)
		_state = response.state
		_refresh_view()
		if response.accepted and _state.phase == "SELECTING_STAKE":
			# Keep stake validation in the session, without a selection step in the UI.
			response = _session.select_stake("starter")
			continue
		if not response.accepted or "advance_table" not in _state.legal_actions:
			break
		# Timers belong to playback, not the engine or wallet/controller.
		response = _session.advance_table()
	if not response.accepted:
		_status_label.text = response.error.message
		_log_line("Request rejected: " + response.error.message)
	_busy = false
	_sync_controls()


func _play_events(events: Array) -> void:
	for event in events:
		# Let each AI think before its action appears. A Hit's card is shown
		# immediately afterwards; its next decision has its own separate wait.
		var action_delay := _ai_action_delay(event)
		if action_delay > 0:
			await get_tree().create_timer(action_delay).timeout
		match event.type:
			"session_opened":
				_reset_cards()
				_result_label.text = ""
				_result_label.visible = false
				_summary_label.text = ""
				_log_line("Table opened.")
			"stake_selected":
				_log_line("Stake selected: %d per hand." % event.stake.amount)
			"hand_started":
				_progress_label.text = "Hand %d / %d | Completed: %d" % [event.hand_number, _state.max_hands, _state.hands_played]
			"round_started":
				_reset_cards()
				_fast_forward = false
				_ai_moves_seen.clear()
				_result_label.text = ""
				for label in _total_labels.values():
					label.text = "Dealing..."
				_draw_cards()
			"phase_changed":
				_set_active_seat(event.active_seat_id if event.phase in ["PLAYER_TURN", "AI_TURN", "DEALER_TURN"] else "")
				_status_label.text = "Dealing..." if event.phase == "DEALING" else "Turn: " + str(event.active_seat_id)
			"card_dealt":
				_displayed_cards[event.seat_id].append(event.card.duplicate(true))
				_total_labels[event.seat_id].text = "Dealing..."
				_draw_cards()
				_log_line("%s receives %s." % [event.seat_id.capitalize(), _card_text(event.card)])
			"dealer_card_revealed":
				_displayed_cards[event.seat_id][event.card_index] = event.card.duplicate(true)
				_total_labels[event.seat_id].text = "Revealed; resolving..."
				_draw_cards()
				_log_line("Dealer reveals %s." % _card_text(event.card))
			"action_taken":
				if event.seat_id in Rules.AI_SEATS:
					_ai_moves_seen[event.seat_id] = true
				_log_line("%s: %s%s." % [event.seat_id.capitalize(), event.action,
					" (automatic)" if event.automatic else ""])
			"seat_settled":
				_total_labels[event.seat_id].text = "%s | Total: %d" % [event.result.outcome.to_upper(), event.result.player_total]
				if event.seat_id == "player":
					_fast_forward = true
					_result_label.text = "You: " + event.result.outcome.to_upper()
					_result_label.visible = true
			"wallet_transaction":
				_balance_label.text = "Balance: %d" % event.balance
				_log_line("Money %s | balance %d." % [_signed(event.delta), event.balance])
			"hand_settled":
				_show_hand_result(event.result)
				_log_line(_result_label.text)
			"wallet_transaction_pending":
				_log_line("Wallet return pending. Retry Return is available after playback.")
			"session_finished":
				_log_line("Session finished: " + _finish_reason(event.summary.reason))
			"session_closed":
				_log_line("Session closed. New Session keeps this balance; Reset test money starts over.")
		var delay := _event_delay(event)
		if delay > 0:
			await get_tree().create_timer(delay).timeout


func _reset_cards() -> void:
	_set_active_seat("")
	for seat_id in _card_rows:
		_displayed_cards[seat_id] = []


func _set_active_seat(seat_id: String) -> void:
	_highlighted_seat = seat_id
	for id in _seat_panels:
		var active: bool = id == seat_id
		var panel: PanelContainer = _seat_panels[id]
		panel.add_theme_stylebox_override("panel", _seat_styles[id].active if active else _seat_styles[id].normal)
		var title: Label = _seat_titles[id]
		title.add_theme_color_override("font_color", Color("f2c66d") if active else Color("e6edf5"))


func _event_delay(event: Dictionary) -> float:
	if event.type == "card_dealt" and event.get("seat_id", "") in Rules.AI_SEATS and event.get("card_index", 0) >= 2:
		return 0.0
	var timed: bool = event.type in ["card_dealt", "dealer_card_revealed"]
	if event.type == "action_taken" and event.seat_id == "dealer" and event.action == "stand":
		timed = true
	if not timed:
		return 0.0
	return minf(deal_delay, fast_forward_delay) if _fast_forward else deal_delay


func _ai_action_delay(event: Dictionary) -> float:
	if event.type != "action_taken" or event.seat_id not in Rules.AI_SEATS:
		return 0.0
	var delay := ai_next_move_delay if _ai_moves_seen.has(event.seat_id) else ai_first_move_delay
	return minf(delay, fast_forward_delay) if _fast_forward else delay


func _refresh_view() -> void:
	var active_seat: String = ""
	if _state.phase == "PLAYING" and _state.hand != null and _state.hand.phase in ["PLAYER_TURN", "AI_TURN", "DEALER_TURN"]:
		active_seat = _state.hand.active_seat_id
	_set_active_seat(active_seat)
	_balance_label.text = "Balance: %d" % _state.balance
	_progress_label.text = "Hand %d / %d | Completed: %d" % [_state.hand_number, _state.max_hands, _state.hands_played]
	_stake_label.text = "Stake: %d" % STAKES[0].amount
	var prompts := {
		"SELECTING_STAKE": "Insufficient funds for the stake. Leave the table or reset the test money.",
		"READY": "Start the first hand when ready.",
		"PLAYING": "Your turn: Hit or Stand.",
		"BETWEEN_HANDS": "Hand settled. Play the next hand or leave the table.",
		"PAYOUT_PENDING": "The hand is finished. Retry Return to finish its wallet transfer.",
		"REFUND_PENDING": "Hand setup failed. Retry Return to restore its stake.",
		"COMPLETE": "Session finished. Review the summary, then Close Session.",
		"CLOSED": "Session closed. Open a New Session or reset the test money.",
	}
	_status_label.text = prompts.get(_state.phase, "")
	if _state.phase == "PLAYING" and "advance_table" in _state.legal_actions:
		_status_label.text = "Table finishing quickly..." if _fast_forward else "Other seats are playing..."
	if _state.hand != null:
		for seat in _state.hand.seats:
			var hand: Dictionary = seat.hands[0]
			_displayed_cards[seat.seat_id] = hand.cards.duplicate(true)
			if not seat.occupied:
				_total_labels[seat.seat_id].text = "Empty chair"
			elif hand.cards.is_empty():
				_total_labels[seat.seat_id].text = "No cards"
			else:
				_total_labels[seat.seat_id].text = "Visible: %d | hidden card" % hand.visible_total if hand.total == null else "Total: %d%s | %s" % [hand.total, " (soft)" if hand.is_soft else "", seat.status]
	_draw_cards()
	if _state.phase == "PAYOUT_PENDING":
		var pending_result: Dictionary = _state.pending_transaction.result
		_result_label.text = "Hand %d: %s | Return pending: %d" % [pending_result.hand_number,
			pending_result.outcome.to_upper(), pending_result.returned_amount]
	elif not _state.results.is_empty() and _state.results[-1].hand_number == _state.hand_number:
		_show_hand_result(_state.results[-1])
	else:
		_result_label.text = ""
	_result_label.visible = not _result_label.text.is_empty()
	if _state.summary != null:
		var summary: Dictionary = _state.summary
		_summary_label.text = "Session: %s | Hands: %d | Start: %d | End: %d | Net: %s" % [
			_finish_reason(summary.reason), summary.hands_played, summary.starting_balance,
			summary.ending_balance, _signed(summary.net_change)]
	_summary_label.visible = _state.summary != null


func _sync_controls() -> void:
	var legal: Array = _state.get("legal_actions", [])
	for action in _buttons:
		_buttons[action].disabled = _busy or action not in legal
	_buttons.start_next_hand.text = "Start Hand" if _state.get("hand_number", 0) == 0 else "Next Hand"
	_mode.disabled = _busy or _state.get("phase") not in ["SELECTING_STAKE", "READY", "BETWEEN_HANDS", "CLOSED"]
	_reset_button.disabled = _busy
	_fail_button.disabled = _busy or _state.get("phase") not in ["READY", "PLAYING", "BETWEEN_HANDS"]


func _draw_cards() -> void:
	for seat_id in _card_rows:
		var row: HFlowContainer = _card_rows[seat_id]
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		for card in _displayed_cards[seat_id]:
			var panel := PanelContainer.new()
			panel.custom_minimum_size = Vector2(64, 72) if seat_id in Rules.AI_SEATS else Vector2(82, 82)
			var style := StyleBoxFlat.new()
			style.bg_color = Color("f0eee6") if card.face_up else Color("365779")
			style.set_corner_radius_all(6)
			panel.add_theme_stylebox_override("panel", style)
			row.add_child(panel)
			var label := _label(_card_text(card), panel, 14 if seat_id in Rules.AI_SEATS else 18)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", Color("18283b") if card.face_up else Color("ffffff"))


func _card_text(card: Dictionary) -> String:
	if not card.face_up:
		return "Face\ndown"
	var ranks := {1: "A", 11: "J", 12: "Q", 13: "K"}
	return "%s\n%s" % [ranks.get(card.rank, str(card.rank)), card.suit.capitalize()]


func _show_hand_result(result: Dictionary) -> void:
	_result_label.visible = true
	_result_label.text = "Hand %d: %s | Stake: %d | Returned: %d | Net: %s" % [
		result.hand_number, result.outcome.to_upper(), result.wager,
		result.returned_amount, _signed(result.net_change)]


func _finish_reason(reason: String) -> String:
	return {"hand_limit": "hand limit reached", "player_left": "left the table",
		"insufficient_funds": "insufficient funds", "cancelled": "cancelled before play"}.get(reason, reason)


func _signed(amount: int) -> String:
	return ("+" if amount > 0 else "") + str(amount)


func _log_line(text: String) -> void:
	_log.append_text(text.replace("\n", " ") + "\n")


func _scenario_deck() -> Array:
	if _mode.selected == 0:
		return []
	# Known development fixtures; these never enter the core rules or controller.
	var prefixes := [
		[],
		[_card(1), _card(9, "diamonds"), _card(13), _card(8, "diamonds")],
		[_card(10), _card(6, "diamonds"), _card(8), _card(5, "diamonds"), _card(10, "hearts")],
		[_card(10), _card(9, "diamonds"), _card(7), _card(8, "diamonds")],
		[_card(10), _card(10, "diamonds"), _card(8), _card(6, "diamonds"), _card(10, "hearts")],
	]
	var original: Array = prefixes[_mode.selected].duplicate(true)
	var reserved: Array = original.duplicate(true)
	var initial: Dictionary = {"player": [original[0], original[2]], "dealer": [original[1], original[3]]}
	for seat_id in Rules.SEAT_ORDER:
		if seat_id not in ai_seats:
			continue
		var pair: Array = []
		for rank in [12, 7, 8, 9]:
			for suit in ["clubs", "diamonds", "hearts", "spades"]:
				var candidate := _card(rank, suit)
				if candidate not in reserved:
					pair.append(candidate)
					reserved.append(candidate)
					break
			if pair.size() == 2:
				break
		initial[seat_id] = pair
	var cards: Array = []
	for pass_index in range(2):
		for seat_id in Rules.SEAT_ORDER:
			if initial.has(seat_id):
				cards.append(initial[seat_id][pass_index])
		cards.append(initial.dealer[pass_index])
	for index in range(4, original.size()):
		cards.append(original[index])
	for suit in ["clubs", "diamonds", "hearts", "spades"]:
		for rank in range(1, 14):
			var card := _card(rank, suit)
			if card not in cards:
				cards.append(card)
	return cards


func _card(rank: int, suit: String = "clubs") -> Dictionary:
	return {"rank": rank, "suit": suit}
