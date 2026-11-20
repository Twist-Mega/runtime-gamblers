extends Control

## Builds the standalone Hold'em screen and sends player and NPC actions to the
## hand engine. Displays the engine's table state, card reveals, and payouts.
## In Wallet mode, the buy-in funds a table visit and cash-out returns the settled stack.

const Hand := preload("res://scripts/holdem/holdem_hand.gd")
const Preflop := preload("res://scripts/holdem/holdem_preflop.gd")
const GameWallet := preload("res://scripts/wallet.gd")
const Rank := Hand.HandRank
const VIEW_SIZE := Vector2i(1280, 720)
const PLAYER := Hand.PLAYER
const TABLES := [
	{"name": "Low stakes", "small_blind": 1, "big_blind": 2, "cap": 10},
	{"name": "Mid stakes", "small_blind": 2, "big_blind": 4, "cap": 20},
	{"name": "High stakes", "small_blind": 4, "big_blind": 8, "cap": 40},
]
const STREETS := ["Between hands", "Preflop", "Flop", "Turn", "River", "Hand complete"]
const RANK_TEXT := "23456789TJQKA"
const TEXT_COLOR := Color("e6edf5")
const ACTIVE_COLOR := Color("f2c66d")
const FOLDED_CARD_TINT := Color(0.55, 0.55, 0.55)
const FONT := preload("res://assets/fonts/Tiny5-Regular.ttf")
const CARD_FRONT := preload("res://assets/cards/ui_card_front.png")
const CARD_BACK := preload("res://assets/cards/ui_card_back.png")
const CARD_SUITS := preload("res://assets/cards/card_suits.png")

@export var occupied_ai_seats: Array[int] = [1, 2, 3, 4, 5]
@export var use_game_wallet := true
## Show hidden NPC cards and dim folded hands during standalone playtesting.
@export var debug_reveal_npc_cards := false
@export_range(0.0, 2.0, 0.05) var ai_action_delay := 0.35
@export_range(0.0, 1.0, 0.05) var deal_delay := 0.20

var _hand := Hand.new()
var _lineup: Array[int] = [PLAYER]
var _busy := false
var _seats: Dictionary = {}
var _board: Array[Dictionary] = []
var _suit_icons: Array[AtlasTexture] = []
var _normal_seat: StyleBoxFlat
var _active_seat: StyleBoxFlat
var _table_picker: OptionButton
var _stakes_label: Label
var _pot_label: Label
var _stage_label: Label
var _status_label: Label
var _history: RichTextLabel
var _start: Button
var _buy_in: Button
var _cash_out: Button
var _wallet_label: Label
var _wallet_status: Label
var _wallet: GameWallet
var _seated := false
# Transaction IDs stay stable for retries and change after a successful cash-out.
var _visit_number := 0
var _fold: Button
var _check_call: Button
var _bet: Button
var _amount: SpinBox
var _saved_scaling: Dictionary = {}


## Build the controls and show the initial table when Godot opens the scene.
func _ready() -> void:
	_configure_window()
	_build_table()
	if use_game_wallet:
		_wallet = get_tree().root.get_node("Wallet") as GameWallet
		_wallet.money_changed.connect(_wallet_changed)
		_wallet_changed(_wallet.money)
	_refresh(_hand.get_view())


## Save the window settings and apply the standalone table's 1280 by 720 layout.
func _configure_window() -> void:
	if get_parent() != get_tree().root:
		return
	var window := get_window()
	_saved_scaling = {
		"content_scale_size": window.content_scale_size,
		"content_scale_mode": window.content_scale_mode,
		"content_scale_stretch": window.content_scale_stretch,
	}
	window.content_scale_size = VIEW_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


## Restore the saved window settings when the table closes.
func _exit_tree() -> void:
	var window := get_window()
	for property in _saved_scaling:
		window.set(property, _saved_scaling[property])


## Create the table layout, collect the occupied seats, and connect the controls.
func _build_table() -> void:
	theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", TEXT_COLOR)
	for suit_id in range(4):
		var icon := AtlasTexture.new()
		icon.atlas = CARD_SUITS
		# The sprite sheet runs spades, hearts, diamonds, clubs.
		icon.region = Rect2((3 - suit_id) * 8, 0, 8, 8)
		_suit_icons.append(icon)
	var background := ColorRect.new()
	background.color = Color("101b29")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	_label(header, "Texas Hold'em", 30).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet_label = _label(header, "")
	_wallet_label.visible = use_game_wallet
	_stakes_label = _label(header, "")
	_table_picker = OptionButton.new()
	_table_picker.name = "TablePicker"
	for table in TABLES:
		_table_picker.add_item(table.name)
	_table_picker.item_selected.connect(_change_table)
	header.add_child(_table_picker)

	_normal_seat = _panel_style(Color("1d3044"), Color("365779"), 10)
	_active_seat = _panel_style(Color("30485b"), ACTIVE_COLOR, 10)
	var opponents := HBoxContainer.new()
	opponents.add_theme_constant_override("separation", 8)
	content.add_child(opponents)
	for seat_id in range(1, Hand.SEAT_COUNT):
		var occupied := seat_id in occupied_ai_seats
		_build_seat(opponents, seat_id, occupied)
		if occupied:
			_lineup.append(seat_id)

	var felt := PanelContainer.new()
	felt.add_theme_stylebox_override("panel", _panel_style(Color("17353f"), Color("365779"), 12))
	content.add_child(felt)
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 8)
	felt.add_child(center)
	_label(center, "Dealer", 18).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label = _label(center, "Between hands")
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var community := HBoxContainer.new()
	community.alignment = BoxContainer.ALIGNMENT_CENTER
	community.add_theme_constant_override("separation", 8)
	center.add_child(community)
	for card_index in range(5):
		_board.append(_card_slot(community))
	_pot_label = _label(center, "Pot 0", 20)
	_pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var player_area := HBoxContainer.new()
	player_area.add_theme_constant_override("separation", 12)
	content.add_child(player_area)
	_build_seat(player_area, PLAYER, true)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_stretch_ratio = 3.0
	controls.add_theme_constant_override("separation", 8)
	player_area.add_child(controls)
	_status_label = _label(controls, "", 22)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wallet_status = _label(controls, "")
	_wallet_status.hide()
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	controls.add_child(actions)
	_buy_in = _button(actions, "BuyIn", "Buy In (%d)" % Hand.STARTING_STACK, _sit_down)
	_cash_out = _button(actions, "CashOut", "Cash Out", _leave_table)
	_start = _button(actions, "StartHand", "Start Hand", _start_hand)
	_fold = _button(actions, "Fold", "Fold", _player_action.bind("fold"))
	_check_call = _button(actions, "CheckCall", "Check / Call", _player_action.bind("passive"))
	_amount = SpinBox.new()
	_amount.name = "WagerAmount"
	_amount.custom_minimum_size.x = 96
	_amount.update_on_text_changed = true
	_amount.tooltip_text = "Total bet this street, including chips you already put in."
	_amount.value_changed.connect(_update_wager_caption)
	actions.add_child(_amount)
	_bet = _button(actions, "Wager", "Bet", _player_action.bind("wager"))

	_label(content, "Hand history", 18)
	_history = RichTextLabel.new()
	_history.name = "HandHistory"
	_history.custom_minimum_size.y = 100
	_history.scroll_following = true
	content.add_child(_history)


## Create one seat panel and save its controls for later updates.
func _build_seat(parent: Control, seat_id: int, occupied: bool) -> void:
	var panel := PanelContainer.new()
	panel.name = "Seat%d" % seat_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _normal_seat)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var seat_name := "You" if seat_id == PLAYER else "NPC %d" % seat_id
	var title := _label(column, seat_name if occupied else "Empty seat", 18)
	var chips := _label(column, "")
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	column.add_child(cards)
	_seats[seat_id] = {
		"name": seat_name,
		"panel": panel,
		"title": title,
		"chips": chips,
		"cards": [_card_slot(cards), _card_slot(cards)],
	}


## Create a reusable panel style with the given colors and padding.
func _panel_style(background: Color, border: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		style.set_content_margin(side, margin)
	return style


## Add a label to the given container and return it for further setup.
func _label(parent: Control, caption: String, font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


## Add a button and connect its pressed signal to the supplied function.
func _button(parent: Control, node_name: String, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## Build an empty card slot with separate controls for the texture, rank, and suit.
func _card_slot(parent: Control) -> Dictionary:
	var slot := ColorRect.new()
	slot.color = Color("122431")
	slot.custom_minimum_size = Vector2(48, 64)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	var face := TextureRect.new()
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rank := _label(face, "", 20)
	rank.position = Vector2(8, 2)
	rank.add_theme_color_override("font_color", Color("18283b"))
	var suit := TextureRect.new()
	suit.position = Vector2(16, 28)
	suit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	suit.size = Vector2(16, 16)
	suit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(suit)
	return {"face": face, "rank": rank, "suit": suit}


## Show a card face for a valid ID, or show a back or empty slot for a negative ID.
func _draw_card(slot: Dictionary, card: int, face_down: bool = false) -> void:
	if card >= 0:
		slot.face.texture = CARD_FRONT
		var value := Rank.rank(card)
		slot.rank.text = "10" if value == 10 else RANK_TEXT[value - 2]
		slot.suit.texture = _suit_icons[Rank.suit(card)]
	else:
		slot.face.texture = CARD_BACK if face_down else null
	slot.rank.visible = card >= 0
	slot.suit.visible = card >= 0


## Start a fresh practice table with the selected stakes between hands.
func _change_table(_index: int) -> void:
	if _busy or _seated or _hand.get_view().actor >= 0:
		return
	_hand = Hand.new()
	_history.clear()
	_refresh(_hand.get_view())


## Update the shared balance independently of chips committed to this table.
func _wallet_changed(balance: int) -> void:
	_wallet_label.text = "Wallet %d" % balance
	_buy_in.disabled = _busy or _lineup.size() < 2 or balance < Hand.STARTING_STACK


## Debit the fixed buy-in before allowing the engine to deal a hand.
func _sit_down() -> void:
	if not use_game_wallet or _busy or _seated or _lineup.size() < 2:
		return
	_busy = true
	var transaction_id := "holdem:%d:%d:buy-in" % [get_instance_id(), _visit_number]
	if _wallet.apply_transaction(transaction_id, -Hand.STARTING_STACK):
		_seated = true
		_wallet_status.hide()
	else:
		_wallet_status.text = "Buy-in failed. Check your Wallet balance."
		_wallet_status.show()
	_busy = false
	_refresh(_hand.get_view())


## Return the player's settled stack before opening another table visit.
func _leave_table() -> void:
	if not _seated or _busy or _hand.get_view().actor >= 0:
		return
	_busy = true
	var chips := _hand.get_seat_stack(PLAYER)
	var transaction_id := "holdem:%d:%d:cash-out" % [get_instance_id(), _visit_number]
	if _wallet.apply_transaction(transaction_id, chips):
		_seated = false
		_visit_number += 1
		_hand = Hand.new()
		_wallet_status.text = "Cashed out %d chips." % chips
	else:
		_wallet_status.text = "Cash-out failed. Select Cash Out to retry."
	_wallet_status.show()
	_busy = false
	_refresh(_hand.get_view())


## Deal with the selected stakes, log the blinds, and play any opening NPC turns.
func _start_hand() -> void:
	var table: Dictionary = TABLES[_table_picker.selected]
	if _busy or (use_game_wallet and not _seated):
		return
	if not _hand.start(_lineup, table.small_blind, table.big_blind, table.cap):
		return
	_busy = true
	var view := _hand.get_view()
	_history.clear()
	_log("%s · Small blind %d" % [_seats[view.small_blind_seat].name, view.posted_small_blind])
	_log("%s · Big blind %d" % [_seats[view.big_blind_seat].name, view.posted_big_blind])
	await _present_turn(view, 0)
	await _take_npc_turns()
	_busy = false
	_refresh(_hand.get_view())


## Translate a button press into an engine action and play any NPC turns that follow.
func _player_action(action: String) -> void:
	if _busy or _hand.get_view().actor != PLAYER:
		return
	_busy = true
	if action == "passive":
		action = "call" if _hand.legal_actions().to_call > 0 else "check"
	await _play_turn(PLAYER, action, int(_amount.value))
	await _take_npc_turns()
	_busy = false
	_refresh(_hand.get_view())


## Apply the preflop rules, then check or call on later streets.
func _take_npc_turns() -> void:
	var actor: int = _hand.get_view().actor
	while actor > PLAYER:
		if ai_action_delay > 0.0:
			await get_tree().create_timer(ai_action_delay).timeout
		var turn := _hand.get_preflop_turn(actor)
		if turn.is_empty():
			var action := "call" if _hand.legal_actions().to_call > 0 else "check"
			await _play_turn(actor, action)
		else:
			var decision := Preflop.decide(turn)
			await _play_turn(actor, decision.action, decision.get("raise_to", 0))
		actor = _hand.get_view().actor


## Submit one action to the hand engine, log the result, and reveal new board cards in order.
func _play_turn(seat_id: int, action: String, raise_to: int = 0) -> void:
	var before := _hand.get_view()
	var legal := _hand.legal_actions()
	if not _hand.act(seat_id, action, raise_to):
		return
	var caption := action.capitalize()
	if action == "call":
		caption = "Call %d" % legal.to_call
		if legal.all_in_call:
			caption += " all-in"
	elif action == "wager":
		caption = ("Bet %d" if legal.opening_bet else "Raise to %d") % raise_to
		if raise_to == legal.all_in_to:
			caption += " all-in"
	_log("%s · %s" % [_seats[seat_id].name, caption])
	await _present_turn(_hand.get_view(), before.board.size())


## Play community cards in order before revealing showdown cards and pot results.
func _present_turn(view: Dictionary, previous_board_size: int) -> void:
	var playing_view := view
	if view.street == Hand.Street.COMPLETE and view.board.size() > previous_board_size:
		playing_view = view.duplicate(true)
		playing_view.street = Hand.Street.PREFLOP
		playing_view.winning_rank = ""
		for seat_id in playing_view.seats:
			var returned: int = view.payouts.get(seat_id, 0) + view.refunds.get(seat_id, 0)
			var seat: Dictionary = playing_view.seats[seat_id]
			seat.stack -= returned
			seat.all_in = seat.stack == 0
			playing_view.pot += returned
			if seat_id != PLAYER:
				seat.cards.clear()
	_refresh(playing_view, previous_board_size)
	for index in range(previous_board_size, view.board.size()):
		match index:
			0: _show_dealt_street(view.hand_number, "Flop")
			3: _show_dealt_street(view.hand_number, "Turn")
			4: _show_dealt_street(view.hand_number, "River")
		if deal_delay > 0.0:
			await get_tree().create_timer(deal_delay).timeout
		_draw_card(_board[index], view.board[index])
	if view.street == Hand.Street.COMPLETE:
		_refresh(view)
		for index in range(view.pot_results.size()):
			var pot: Dictionary = view.pot_results[index]
			var title := "Main pot" if index == 0 else "Side pot %d" % index
			_log("%s (%d) · %s" % [title, pot.amount, _payout_text(pot.payouts)])
		for seat_id in view.refunds:
			_log("%s · %d uncalled chips returned" % [_seats[seat_id].name, view.refunds[seat_id]])
		_log(_result_text(view))


## Announce a new street as its first community card is dealt.
func _show_dealt_street(hand_number: int, street: String) -> void:
	_stage_label.text = "Hand %d · %s" % [hand_number, street]
	_log(street)


## Update the screen from a hand snapshot, allowing new board cards to stay hidden during playback.
func _refresh(view: Dictionary, visible_board_cards: int = 5) -> void:
	var table: Dictionary = TABLES[_table_picker.selected]
	_stakes_label.text = "%d/%d blinds  ·  %d cap per street" % [
		table.small_blind, table.big_blind, table.cap,
	]
	var stage: String = STREETS[view.street]
	if not view.winning_rank.is_empty():
		stage = "Showdown"
	_stage_label.text = "Hand %d · %s" % [view.hand_number, stage] if view.hand_number else stage
	_pot_label.text = "Pot %d" % view.pot
	for index in range(_board.size()):
		var card: int = view.board[index] if index < mini(view.board.size(), visible_board_cards) else -1
		_draw_card(_board[index], card)
	for seat_id in _lineup:
		var chips := _hand.get_seat_stack(seat_id)
		if use_game_wallet and not _seated and seat_id == PLAYER:
			chips = 0
		_refresh_seat(seat_id, view, chips)

	if view.actor == PLAYER:
		_status_label.text = "Your turn"
	elif view.actor > PLAYER:
		_status_label.text = "%s is acting" % _seats[view.actor].name
	elif view.street == Hand.Street.COMPLETE:
		_status_label.text = _result_text(view)
		if not _hand.can_start_hand(_lineup):
			var reason := "You're out of chips." if _hand.get_seat_stack(PLAYER) == 0 else "No opponents have chips left."
			_status_label.text += "\n" + reason
	elif _lineup.size() < 2:
		_status_label.text = "Seat at least one NPC in the Inspector to deal."
	elif use_game_wallet and not _seated:
		_status_label.text = "Buy in to take a seat."
	elif _busy:
		_status_label.text = "Dealing remaining cards…"
	else:
		_status_label.text = "Table chips carry over between hands."
	_sync_actions(view)


## Update one seat's turn highlight, role, chips, and visible cards.
func _refresh_seat(seat_id: int, view: Dictionary, starting_stack: int) -> void:
	var seat: Dictionary = _seats[seat_id]
	var data: Dictionary = view.seats.get(seat_id, {})
	var active: bool = seat_id == view.actor
	seat.panel.add_theme_stylebox_override("panel", _active_seat if active else _normal_seat)
	seat.title.add_theme_color_override("font_color", ACTIVE_COLOR if active else TEXT_COLOR)
	var roles: PackedStringArray = []
	if seat_id == view.button:
		roles.append("D")
	if seat_id == view.small_blind_seat:
		roles.append("SB")
	if seat_id == view.big_blind_seat:
		roles.append("BB")
	seat.title.text = seat.name if roles.is_empty() else "%s [%s]" % [seat.name, "/".join(roles)]
	var chip_text := "%d chips" % data.get("stack", starting_stack)
	if use_game_wallet and seat_id == PLAYER:
		chip_text = "Table chips %d" % data.get("stack", starting_stack)
	if data.get("folded", false):
		chip_text += " · Folded"
	elif data.get("all_in", false):
		chip_text += " · All-in"
	elif (not data.is_empty() or seat_id != PLAYER) and data.get("stack", starting_stack) == 0:
		chip_text += " · Out of chips"
	elif data.get("bet", 0) > 0:
		chip_text += " · Bet %d" % data.bet
	seat.chips.text = chip_text
	var cards: Array = data.get("cards", [])
	# Use the debug cards only for rendering. The regular view keeps its concealment rules.
	if debug_reveal_npc_cards and seat_id != PLAYER:
		cards = _hand.get_debug_hole_cards(seat_id)
	var tint := FOLDED_CARD_TINT if debug_reveal_npc_cards and data.get("folded", false) else Color.WHITE
	for index in range(seat.cards.size()):
		var card: int = cards[index] if index < cards.size() else -1
		_draw_card(seat.cards[index], card, index < int(data.get("card_count", 0)))
		seat.cards[index].face.modulate = tint


## Show and enable controls based on whose turn it is, legal wagers, and playback.
func _sync_actions(view: Dictionary) -> void:
	var hand_active: bool = view.actor >= 0
	_table_picker.disabled = _busy or hand_active or _seated
	_buy_in.visible = use_game_wallet and not _seated
	_cash_out.visible = _seated and not hand_active and not _busy
	if use_game_wallet:
		_wallet_changed(_wallet.money)
	_start.visible = not hand_active and not _busy and (not use_game_wallet or _seated)
	_start.disabled = _busy or _lineup.size() < 2
	if not hand_active and not _hand.can_start_hand(_lineup):
		_start.disabled = true
	_start.text = "Next Hand" if view.street == Hand.Street.COMPLETE else "Start Hand"
	for control in [_fold, _check_call, _amount, _bet]:
		control.visible = hand_active
	var legal := _hand.legal_actions() if view.actor == PLAYER else {}
	var to_call: int = legal.get("to_call", 0)
	var can_act: bool = not _busy and view.actor == PLAYER
	var can_wager: bool = can_act and legal.can_wager
	_fold.disabled = not can_act or to_call == 0
	_check_call.text = "Call %d" % to_call if to_call > 0 else "Check"
	if legal.get("all_in_call", false):
		_check_call.text = "Call %d all-in" % to_call
	_check_call.disabled = not can_act
	_amount.editable = can_wager
	_bet.disabled = not can_wager
	if can_wager:
		_amount.max_value = legal.max_raise_to
		_amount.min_value = legal.min_raise_to
		_amount.set_value_no_signal(legal.min_raise_to)
	_update_wager_caption(_amount.value)


## Label a selected wager as all-in when it commits the player's remaining chips.
func _update_wager_caption(amount: float) -> void:
	if _bet == null:
		return
	var legal := _hand.legal_actions()
	_bet.text = "Bet" if legal.get("opening_bet", false) else "Raise to"
	if not _bet.disabled and int(amount) == int(legal.get("all_in_to", -1)):
		_bet.text = "All-in"


## Format the winners, chip payouts, and showdown category for the display.
func _result_text(view: Dictionary) -> String:
	var result := "Winner · "
	if view.pot_results.size() > 1:
		result = "Payouts · "
	elif view.payouts.size() > 1:
		result = "Split pot · "
	result += _payout_text(view.payouts)
	if not view.winning_rank.is_empty():
		result += " · " + view.winning_rank
	return result


## Format the seat names and amounts paid for a pot or the whole hand.
func _payout_text(paid: Dictionary) -> String:
	var payouts: PackedStringArray = []
	for seat_id in paid:
		payouts.append("%s +%d" % [_seats[seat_id].name, paid[seat_id]])
	return " / ".join(payouts)


## Append one line to the visible hand history.
func _log(line: String) -> void:
	_history.add_text(line + "\n")
