# Blackjack session controller

`scripts/blackjack/blackjack_session_controller.gd` manages a table visit around the
[single-hand engine](blackjack_engine.md). It selects one stake, plays up to a
configured number of hands (default five), settles each hand through an injected
wallet, and prepares the session result before closing. It has no scenes, input,
display, lobby transitions, or production wallet storage. The
[development display](blackjack_debug_display.md) provides a standalone playable
interface using this controller and a fake wallet.

## Creating a session

```gdscript
const Session = preload("res://scripts/blackjack/blackjack_session_controller.gd")

var tables = {
	"lobby_blackjack": {
		"max_hands": 5,
		"stake_options": [
			{"option_id": "starter", "label": "Starter", "amount": 5},
			{"option_id": "higher", "label": "Higher stakes", "amount": 25,
			 "unlock_id": "higher_stakes"},
		],
	},
}

# wallet_adapter extends BlackjackWalletPort (see the contract below).
# progression.is_unlocked(unlock_id: String) returns a bool without side effects.
var session = Session.new(wallet_adapter, tables, progression.is_unlocked)
var response = session.open_blackjack("lobby_blackjack")
response = session.select_stake("starter")
response = session.start_next_hand()

# Forward Hit/Stand buttons to session.hit() and session.stand().
# Play response.events in order before enabling the next input.
```

Every command must be checked for `accepted`. Use the controller's top-level
`legal_actions`, not the nested engine's actions. The controller enforces the hand
limit, wallet balance, stake availability, and departure rules.

Constructor arguments are `wallet`, optional `tables`, optional `unlock_check`,
and optional `random_seed`. Omitting tables uses the development table
`lobby_blackjack` with five hands and one unlocked `starter` option of 2 units.
The controller never supplies a starting balance; that belongs to the wallet.
An integer seed reproduces gameplay for tests; session IDs still differ.

### Table and unlock configuration

Table IDs are dictionary keys. Each configuration needs a nonempty `stake_options`
array and optionally a positive integer `max_hands`, defaulting to five. Each
option needs a unique nonempty `option_id` and a positive integer `amount` within
the engine's wager limit. `label` defaults to the amount as a string. `unlock_id`
is optional; null or an empty string means the option is always unlocked.

The table registry is copied on construction and validated when opening a table.
Odd stakes are supported. A selection fixes the stake for that entire session;
changing it requires cancelling/leaving and opening a new session.

`unlock_check(unlock_id: String) -> bool` is queried for displayed availability,
selection, and every hand start. A gated option stays locked when no callback is
provided. The callback must be synchronous and side-effect-free. Progression can
unlock options while the player is choosing. If availability is revoked after
selection, another hand cannot start, but leaving before/between hands still works.
Add another table entry for high-roller stake options; no room scene is implemented
here.

## Commands and session flow

| API | Allowed phase and behavior |
| --- | --- |
| `open_blackjack(table_id)` | From `IDLE` or `CLOSED`; create a new session in `SELECTING_STAKE`. |
| `select_stake(option_id)` | From `SELECTING_STAKE`; validate unlocks/funds, fix the stake, enter `READY`. No money is taken. |
| `start_next_hand(deck_order = [])` | From `READY` or `BETWEEN_HANDS`; recheck availability/funds, deduct one stake, and begin the hand. Optional full fixed deck for tests. |
| `hit()` / `stand()` | From `PLAYING`; resolve the move through the engine and settle any resulting outcome. |
| `leave_table()` | Before the first hand or from `BETWEEN_HANDS`. Never during an active hand or pending transfer. |
| `acknowledge_result()` | From `COMPLETE`; close the session after the summary is displayed. |
| `retry_pending_transaction()` | From `PAYOUT_PENDING` or `REFUND_PENDING`; retry the original transaction ID without replaying the hand. |
| `get_public_state()` | Return a copied public snapshot without advancing gameplay. |

Normal phases are:

`IDLE -> SELECTING_STAKE -> READY -> PLAYING -> BETWEEN_HANDS -> ... -> COMPLETE -> CLOSED`

After each financially settled hand, increment `hands_played`, including pushes,
naturals, and busts. End with `hand_limit` when the limit is reached, otherwise
`insufficient_funds` if the next stake is unaffordable. Check affordability after
crediting the payout. A balance exactly equal to the stake can fund another hand.
Funds are also rechecked immediately before starting, in case another system has
spent money between hands. If funds are then insufficient, that command completes
the session without another deduction or hand.

Leaving after completed hands prepares a summary with reason `player_left` and
enters `COMPLETE`; acknowledgement then closes it. Cancelling before the first hand
uses reason `cancelled` and closes immediately without a charge or extra summary
acknowledgement. Closed sessions can reopen with a fresh ID and cleared history.

### Responses and state

Commands return `{accepted, error, state, events, result, summary}`. Errors are
`{code, message}`; successful commands have `error: null`. `result` is a **newly
financially settled** hand result, otherwise null. `summary` is the session summary
on a successful command after completion; historical copies are also in state.
Neither value instructs a display to credit money: the controller already did so.

Public state fields:

- Identity/status: `session_id`, `table_id`, `phase`, `legal_actions`.
- Stakes: `selected_stake` and `stake_options`; each option includes `unlocked`
  and `affordable` independently.
- Progress: `max_hands`, `hand_number` (hands successfully started), `hands_played`
  (financially settled), and `results`.
- Money: `starting_balance`, current `balance`, and `pending_transaction`.
- Game/display: `hand`, the engine's public snapshot including concealed cards.
- Completion: `summary`, containing session/table IDs, end reason, hands played,
  limit, selected stake, starting/ending balances, and `net_change`.

Hand results retain engine fields and add `session_id` and `hand_number`. Summary
`net_change` sums those hand results; it excludes unrelated wallet changes during
the visit. Balances are actual wallet balances. Snapshots, events, results,
summaries, and input configurations do not alias stored controller/engine data.

Normal rejection codes are `invalid_phase`, `busy`, `invalid_wallet`,
`unknown_table`, `invalid_table`, `unknown_stake`, `stake_locked`,
`insufficient_funds`, `wallet_rejected`, and engine setup errors such as
`invalid_deck`. Ordinary rejections do not change public state or emit events.
The exceptional `refund_pending` rejection means setup failed **and its refund
failed**: money is still owed, state changes to `REFUND_PENDING`, and events explain
the pending refund. Always inspect the returned state even after a rejection.

## Wallet adapter contract

Implement `scripts/blackjack/blackjack_wallet_port.gd`, an abstract `RefCounted`
interface with two synchronous methods:

- `get_balance() -> int`: current nonnegative balance in integer money units.
- `apply_transaction(transaction_id: String, delta: int) -> bool`: atomically
  deduct a negative delta or credit a nonnegative delta. Reject insufficient
  funds or integer overflow without changing balance. Zero deltas are valid.

For an already successful ID with the same delta, return true **without applying
it again**. The same ID with a different delta must return false. False means the
transaction was not applied. The production adapter must store successful IDs in
the same lifetime/storage as its balance.

Each session gets a random 128-bit ID. Deductions/refunds have distinct attempt
IDs; payouts are identified by session and engine round. Failed setup is refunded
before another hand can start; another setup attempt gets a new deduction ID.
Reentrant mutation from wallet/unlock callbacks is rejected as `busy`.

If a payout fails, enter `PAYOUT_PENDING` and retain the engine outcome. The hand
has finished, but its result is not added to settled history until the transfer
succeeds. The only permitted command is retry; successful retry credits once,
records the hand, and then checks whether the session should finish. A failed
setup refund similarly blocks play/departure until refunded, then restores the
pre-start phase without counting a hand. These are in-memory retries, not a
save-game or crash-recovery system.

`tests/blackjack/fake_wallet.gd` implements this contract solely for tests, including
an idempotent ledger and injected transfer failures. No production wallet is added.

## Events and future lobby/display integration

Events have a session-wide `sequence`, `session_id`, `hand_number`, `type`, and
`source` (`session` or `engine`). Engine events retain their original payload,
including `round_id`; their original sequence becomes `round_sequence`. This keeps
card/action/reveal playback intact across multiple hands without leaking hidden
dealer cards.

Session event types:

| Type | Payload |
| --- | --- |
| `session_opened` | `table_id`, `max_hands` |
| `stake_selected` | `stake` |
| `hand_started` | `wager` |
| `wallet_transaction` | `transaction_id`, signed `delta`, balance immediately after that transaction |
| `wallet_transaction_pending` | `transaction` describing the retry |
| `hand_settled` | financially settled `result` |
| `session_finished` | `summary` |
| `session_closed` | `summary` |

Animate each command's events before enabling its next actions. A future scene
bridge can hide/disable the lobby on opening and restore it on `session_closed`.
The controller itself does not pause scenes, switch cameras, or return the player.

## Tests

To run all suites without commands, open `tests/blackjack/blackjack_tests.tscn`
in Godot, press **F6**, and read the **Output** panel. See the
[editor testing instructions](../README.md#run-blackjack-tests-in-godot).

From the repository root:

```powershell
godot --headless --path . --log-file .godot/blackjack-session-tests.log --script res://tests/blackjack/test_blackjack_session_controller.gd
```

Replace `godot` with `& 'C:\path\to\Godot_console.exe'` if it is not on `PATH`.
The runner exits nonzero on failure. Tests use the actual engine and a fake wallet
to cover fixed stakes, limits, outcomes, funds, unlocks, departure, repeated
commands, setup refunds, payout retries, data isolation, and forwarded events.
