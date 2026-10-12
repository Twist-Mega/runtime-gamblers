class_name BlackjackSessionController
extends RefCounted
## Table sessions around the single-hand engine. No scenes, UI, or wallet storage.

const Blackjack = preload("res://scripts/blackjack/blackjack_engine.gd")
const WalletPort = preload("res://scripts/blackjack/blackjack_wallet_port.gd")
const DEFAULT_TABLES = {
	"lobby_blackjack": {
		"max_hands": 5,
		"stake_options": [{"option_id": "starter", "label": "Starter", "amount": 2}],
	},
}

enum Phase {
	IDLE, SELECTING_STAKE, READY, PLAYING, BETWEEN_HANDS,
	PAYOUT_PENDING, REFUND_PENDING, COMPLETE, CLOSED,
}

var _wallet: WalletPort
var _tables: Dictionary
var _unlock_check: Callable
var _random_seed: Variant
var _engine: Blackjack
var _phase: Phase = Phase.IDLE
var _busy: bool = false
var _session_id: String = ""
var _table_id: String = ""
var _table: Dictionary = {}
var _stake: Dictionary = {}
var _starting_balance: int = 0
var _hands_started: int = 0
var _attempt: int = 0
var _sequence: int = 0
var _history: Array[Dictionary] = []
var _settled_rounds: Dictionary = {}
var _pending: Dictionary = {}
var _summary: Dictionary = {}


## tables maps table IDs to {max_hands?, stake_options: [{option_id, label?,
## amount, unlock_id?}]}. unlock_check(unlock_id) must be a side-effect-free bool.
func _init(wallet: WalletPort, tables: Dictionary = DEFAULT_TABLES,
		unlock_check: Callable = Callable(), random_seed: Variant = null) -> void:
	_wallet = wallet
	_tables = tables.duplicate(true)
	_unlock_check = unlock_check
	_random_seed = random_seed


func open_blackjack(table_id: String) -> Dictionary:
	return _execute(_open.bind(table_id))


func select_stake(option_id: String) -> Dictionary:
	return _execute(_select.bind(option_id))


## Starts the first hand or advances from BETWEEN_HANDS. Optional full test deck.
func start_next_hand(deck_order: Array = []) -> Dictionary:
	return _execute(_start.bind(deck_order))


func hit() -> Dictionary:
	return _execute(_play.bind("hit"))


func stand() -> Dictionary:
	return _execute(_play.bind("stand"))


func leave_table() -> Dictionary:
	return _execute(_leave)


## Acknowledge the session summary. The future lobby bridge observes session_closed.
func acknowledge_result() -> Dictionary:
	return _execute(_acknowledge)


## Retry a failed credit/refund with the exact same transaction ID.
func retry_pending_transaction() -> Dictionary:
	return _execute(_retry)


func get_public_state() -> Dictionary:
	var balance: Variant = _wallet.get_balance() if _wallet != null else null
	var actions: Array[String] = []
	match _phase:
		Phase.IDLE, Phase.CLOSED:
			actions.assign(["open_blackjack"])
		Phase.SELECTING_STAKE:
			actions.assign(["select_stake", "leave_table"])
		Phase.READY, Phase.BETWEEN_HANDS:
			actions.assign(["leave_table"])
			if balance >= _stake.amount and _is_unlocked(_stake):
				actions.push_front("start_next_hand")
		Phase.PLAYING:
			actions.assign(["hit", "stand"])
		Phase.PAYOUT_PENDING, Phase.REFUND_PENDING:
			actions.assign(["retry_pending_transaction"])
		Phase.COMPLETE:
			actions.assign(["acknowledge_result"])
	var options: Array[Dictionary] = []
	if not _table.is_empty():
		for option in _table.stake_options:
			var visible: Dictionary = option.duplicate(true)
			visible["unlocked"] = _is_unlocked(option)
			visible["affordable"] = balance >= option.amount
			options.append(visible)
	return {
		"session_id": _session_id,
		"table_id": _table_id,
		"phase": Phase.keys()[_phase],
		"selected_stake": _stake.duplicate(true) if not _stake.is_empty() else null,
		"stake_options": options,
		"max_hands": _table.get("max_hands", 0),
		"hand_number": _hands_started,
		"hands_played": _history.size(),
		"starting_balance": _starting_balance if not _session_id.is_empty() else null,
		"balance": balance,
		"legal_actions": actions,
		"hand": _engine.get_public_state() if _engine != null else null,
		"results": _history.duplicate(true),
		"pending_transaction": _pending.duplicate(true) if not _pending.is_empty() else null,
		"summary": _summary.duplicate(true) if not _summary.is_empty() else null,
	}


func _execute(command: Callable) -> Dictionary:
	# Wallet/unlock adapters can call back synchronously; never allow nested writes.
	if _busy:
		return _reject("busy", "Another session command is in progress.")
	_busy = true
	var response: Dictionary = command.call()
	_busy = false
	return response


func _open(table_id: String) -> Dictionary:
	if _phase != Phase.IDLE and _phase != Phase.CLOSED:
		return _reject("invalid_phase", "Close the current session before opening a table.")
	if _wallet == null or _wallet.get_balance() < 0:
		return _reject("invalid_wallet", "A wallet with a nonnegative balance is required.")
	if not _tables.has(table_id):
		return _reject("unknown_table", "Unknown blackjack table: %s." % table_id)
	var config_error := _validate_table(_tables[table_id])
	if not config_error.is_empty():
		return _reject("invalid_table", config_error)
	_table_id = table_id
	_table = _tables[table_id].duplicate(true)
	_table["max_hands"] = _table.get("max_hands", 5)
	for option in _table.stake_options:
		option["label"] = option.get("label", str(option.amount))
		option["unlock_id"] = option.get("unlock_id", null)
	_session_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_engine = Blackjack.new(_random_seed)
	_stake = {}
	_starting_balance = _wallet.get_balance()
	_hands_started = 0
	_attempt = 0
	_sequence = 0
	_history = []
	_settled_rounds = {}
	_pending = {}
	_summary = {}
	_phase = Phase.SELECTING_STAKE
	var events: Array[Dictionary] = []
	_emit(events, "session_opened", {"table_id": _table_id, "max_hands": _table.max_hands})
	return _accept(events)


func _select(option_id: String) -> Dictionary:
	if _phase != Phase.SELECTING_STAKE:
		return _reject("invalid_phase", "Select a stake once, before starting the first hand.")
	var option: Dictionary = {}
	for candidate in _table.stake_options:
		if candidate.option_id == option_id:
			option = candidate
			break
	if option.is_empty():
		return _reject("unknown_stake", "Unknown stake option: %s." % option_id)
	if not _is_unlocked(option):
		return _reject("stake_locked", "This stake option is locked.")
	if _wallet.get_balance() < option.amount:
		return _reject("insufficient_funds", "The selected stake exceeds your balance.")
	_stake = option.duplicate(true)
	_phase = Phase.READY
	var events: Array[Dictionary] = []
	_emit(events, "stake_selected", {"stake": _stake})
	return _accept(events)


func _start(deck_order: Array) -> Dictionary:
	if _phase != Phase.READY and _phase != Phase.BETWEEN_HANDS:
		return _reject("invalid_phase", "A hand can only start before play or between hands.")
	if not _is_unlocked(_stake):
		return _reject("stake_locked", "This stake option is no longer unlocked.")
	var events: Array[Dictionary] = []
	if _wallet.get_balance() < _stake.amount:
		_finish_session("insufficient_funds", events)
		return _accept(events)
	_attempt += 1
	var transaction_prefix := "%s:hand:%d:attempt:%d" % [_session_id, _hands_started + 1, _attempt]
	var debit_id := transaction_prefix + ":stake"
	if not _wallet.apply_transaction(debit_id, -_stake.amount):
		return _reject("wallet_rejected", "The wallet could not deduct the stake; no hand was started.")
	var engine_response := _engine.begin_round(_stake.amount, deck_order)
	if not engine_response.accepted:
		var refund_id := transaction_prefix + ":refund"
		if _wallet.apply_transaction(refund_id, _stake.amount):
			return _reject(engine_response.error.code, engine_response.error.message)
		_pending = {"kind": "refund", "transaction_id": refund_id, "delta": _stake.amount,
			"resume_phase": _phase, "cause": engine_response.error.duplicate(true)}
		_phase = Phase.REFUND_PENDING
		_wallet_event(events, debit_id, -_stake.amount)
		_emit(events, "wallet_transaction_pending", {"transaction": _pending})
		return _reject("refund_pending", "Hand setup failed and its stake refund must be retried.", events)
	_hands_started += 1
	_phase = Phase.PLAYING
	_wallet_event(events, debit_id, -_stake.amount)
	_emit(events, "hand_started", {"wager": _stake.amount})
	_append_engine_events(events, engine_response.events)
	var result: Variant = _process_result(engine_response.result, events)
	return _accept(events, result)


func _play(action: String) -> Dictionary:
	if _phase != Phase.PLAYING:
		return _reject("invalid_phase", "Player actions require an active hand.")
	var engine_response: Dictionary = _engine.call(action)
	if not engine_response.accepted:
		return _reject(engine_response.error.code, engine_response.error.message)
	var events: Array[Dictionary] = []
	_append_engine_events(events, engine_response.events)
	var result: Variant = _process_result(engine_response.result, events)
	return _accept(events, result)


func _process_result(engine_result: Variant, events: Array[Dictionary]) -> Variant:
	if engine_result == null or _settled_rounds.has(engine_result.round_id):
		return null
	var result: Dictionary = engine_result.duplicate(true)
	result["session_id"] = _session_id
	result["hand_number"] = _hands_started
	var return_id := "%s:round:%d:return" % [_session_id, result.round_id]
	if not _wallet.apply_transaction(return_id, result.returned_amount):
		_pending = {"kind": "payout", "transaction_id": return_id,
			"delta": result.returned_amount, "result": result}
		_phase = Phase.PAYOUT_PENDING
		_emit(events, "wallet_transaction_pending", {"transaction": _pending})
		return null
	_wallet_event(events, return_id, result.returned_amount)
	_record_result(result, events)
	return result.duplicate(true)


func _record_result(result: Dictionary, events: Array[Dictionary]) -> void:
	_settled_rounds[result.round_id] = true
	_history.append(result.duplicate(true))
	_pending = {}
	_emit(events, "hand_settled", {"result": result})
	if _history.size() >= _table.max_hands:
		_finish_session("hand_limit", events)
	elif _wallet.get_balance() < _stake.amount:
		_finish_session("insufficient_funds", events)
	else:
		_phase = Phase.BETWEEN_HANDS


func _retry() -> Dictionary:
	if _phase != Phase.PAYOUT_PENDING and _phase != Phase.REFUND_PENDING:
		return _reject("invalid_phase", "No wallet transaction is waiting for a retry.")
	if not _wallet.apply_transaction(_pending.transaction_id, _pending.delta):
		return _reject("wallet_rejected", "The wallet transaction is still pending.")
	var events: Array[Dictionary] = []
	_wallet_event(events, _pending.transaction_id, _pending.delta)
	if _pending.kind == "refund":
		_phase = _pending.resume_phase
		_pending = {}
		return _accept(events)
	var result: Dictionary = _pending.result.duplicate(true)
	_record_result(result, events)
	return _accept(events, result)


func _leave() -> Dictionary:
	if _phase != Phase.SELECTING_STAKE and _phase != Phase.READY and _phase != Phase.BETWEEN_HANDS:
		return _reject("invalid_phase", "Leave before the first hand or between settled hands.")
	var events: Array[Dictionary] = []
	var cancelled := _hands_started == 0
	_finish_session("cancelled" if cancelled else "player_left", events)
	if cancelled:
		_close_session(events)
	return _accept(events)


func _acknowledge() -> Dictionary:
	if _phase != Phase.COMPLETE:
		return _reject("invalid_phase", "There is no completed session summary to acknowledge.")
	var events: Array[Dictionary] = []
	_close_session(events)
	return _accept(events)


func _finish_session(reason: String, events: Array[Dictionary]) -> void:
	var net_change: int = 0
	for result in _history:
		net_change += result.net_change
	_summary = {"session_id": _session_id, "table_id": _table_id, "reason": reason,
		"hands_played": _history.size(), "max_hands": _table.max_hands,
		"selected_stake": _stake.duplicate(true) if not _stake.is_empty() else null,
		"starting_balance": _starting_balance, "ending_balance": _wallet.get_balance(),
		"net_change": net_change}
	_phase = Phase.COMPLETE
	_emit(events, "session_finished", {"summary": _summary})


func _close_session(events: Array[Dictionary]) -> void:
	_phase = Phase.CLOSED
	_emit(events, "session_closed", {"summary": _summary})


func _is_unlocked(option: Dictionary) -> bool:
	var unlock_id: Variant = option.get("unlock_id")
	if unlock_id == null or unlock_id == "":
		return true
	return _unlock_check.is_valid() and _unlock_check.call(unlock_id) == true


func _validate_table(config: Variant) -> String:
	if not config is Dictionary:
		return "A table configuration must be a dictionary."
	var max_hands: Variant = config.get("max_hands", 5)
	if not max_hands is int or max_hands <= 0:
		return "max_hands must be a positive integer."
	var options: Variant = config.get("stake_options")
	if not options is Array or options.is_empty():
		return "A table must have at least one stake option."
	var seen: Dictionary = {}
	for option in options:
		if not option is Dictionary:
			return "Each stake option must be a dictionary."
		var option_id: Variant = option.get("option_id")
		if not option_id is String or option_id.is_empty() or seen.has(option_id):
			return "Stake option IDs must be nonempty unique strings."
		seen[option_id] = true
		var amount: Variant = option.get("amount")
		if not amount is int or amount < 1 or amount > Blackjack.MAX_WAGER:
			return "Stake amounts must be positive integers within the engine's wager limit."
		if option.has("label") and not option.label is String:
			return "Stake labels must be strings."
		if option.get("unlock_id") != null and not option.unlock_id is String:
			return "Unlock IDs must be strings or null."
	return ""


func _append_engine_events(events: Array[Dictionary], engine_events: Array) -> void:
	for event in engine_events:
		var forwarded: Dictionary = event.duplicate(true)
		forwarded["round_sequence"] = event.sequence
		_emit(events, event.type, forwarded, "engine")


func _wallet_event(events: Array[Dictionary], transaction_id: String, delta: int) -> void:
	_emit(events, "wallet_transaction", {"transaction_id": transaction_id,
		"delta": delta, "balance": _wallet.get_balance()})


func _emit(events: Array[Dictionary], type: String, payload: Dictionary, source: String = "session") -> void:
	_sequence += 1
	var event := payload.duplicate(true)
	event["type"] = type
	event["source"] = source
	event["session_id"] = _session_id
	event["hand_number"] = _hands_started
	event["sequence"] = _sequence
	events.append(event)


func _accept(events: Array[Dictionary], result: Variant = null) -> Dictionary:
	return {"accepted": true, "error": null, "state": get_public_state(), "events": events,
		"result": result, "summary": _summary.duplicate(true) if not _summary.is_empty() else null}


func _reject(code: String, message: String, events: Array[Dictionary] = []) -> Dictionary:
	return {"accepted": false, "error": {"code": code, "message": message},
		"state": get_public_state(), "events": events, "result": null, "summary": null}
