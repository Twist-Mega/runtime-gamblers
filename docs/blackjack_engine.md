# Blackjack engine

`scripts/blackjack/blackjack_engine.gd` resolves **one table round** with one human,
up to four generic AI players, and a dealer sharing one deck. It has no scene nodes, input handling, printing, animations, wallet, or
table/session dependencies. It can run in a headless test or behind a graphical
display using the same API.

## Usage

```gdscript
const Blackjack = preload("res://scripts/blackjack/blackjack_engine.gd")

var blackjack = Blackjack.new(12345, ["left_1", "right_1"])
var response = blackjack.begin_round(5)

# Display response.events in order, then use response.state for the final view.
# Only enable actions once that display playback has finished.
if response.state.phase == "PLAYER_TURN":
	response = blackjack.hit() # Or blackjack.stand().

# The caller advances automatic turns after playing each batch of events.
while "advance_table" in response.state.legal_actions:
	response = blackjack.advance_table()

if response.result != null:
	# Example only: a session controller applies this return once.
	var returned_amount = response.result.returned_amount
```

The caller must check `accepted` on each command. Never change displayed cards or
apply money changes on a rejected command.

## Commands and responses

| API | Behavior |
| --- | --- |
| `Blackjack.new(random_seed = null, occupied_ai_seats = [])` | Independent RNG and copied seat configuration. An integer seed reproduces the shuffle; omitting seats retains single-player play. |
| `begin_round(wager: int, deck_order: Array = [])` | Start from `BETTING` or `SETTLED`. Validate first, reset the hand, deal, and check naturals. |
| `hit()` | Deal one human card during `PLAYER_TURN`. Bust settles that seat immediately; 21 automatically stands. |
| `stand()` | End the human turn and advance to the next occupied seat. With no AI, resolve the dealer synchronously as before. |
| `advance_table()` | During `AI_TURN`, perform one AI decision. During `DEALER_TURN`, reveal and complete the dealer, then finish the round. No timers. |
| `get_public_state()` | Return a fresh public snapshot without changing the game. |

Every command returns a dictionary with:

- `accepted`: whether the command changed the game.
- `error`: `null` on success, otherwise `{code, message}`. Codes are
  `invalid_phase`, `invalid_wager`, `invalid_deck`, and `invalid_seats`.
- `state`: the public snapshot after the command.
- `events`: ordered changes caused by this command; empty on rejection.
- `result`: the human outcome once known, otherwise `null`. After an early bust
  or natural, successful AI commands can return this same outcome again; callers
  must deduplicate by round ID. The session controller does so. A rejection returns null.

State, events, results, and fixed-deck inputs do not alias the engine's stored data.
Changing a returned dictionary or array does not change game logic.

### State

Top-level fields are `round_id`, `phase`, `wager`, `active_seat_id`,
`legal_actions`, `seats`, and `result`.

- Phases: `BETTING`, `DEALING`, `PLAYER_TURN`, `AI_TURN`, `DEALER_TURN`, `SETTLED`.
  Dealing and the dealer's complete play are synchronous command batches.
- `active_seat_id` identifies the current human, AI, or dealer, otherwise null.
- `legal_actions` is `["hit", "stand"]` during that turn, or `["begin_round"]`
  before the first round and after settlement. A session controller must
  filter this against session limits, funds, and table rules. Automatic turns
  expose only `advance_table`.
- Each seat has `seat_id`, `role` (`player`, `dealer`, `ai`), `occupied`, `status`,
  `result`, and a `hands` array. The original player/dealer entries remain first,
  followed by `left_2`, `left_1`, `right_1`, `right_2`. Empty chairs have no cards
  or result. Occupancy is copied at construction and fixed for all rounds.
- Each hand has `hand_id`, `cards`, `visible_total`, `total`, `is_soft`,
  `is_blackjack`, and `is_bust`.
- Face-up cards have integer `rank`, string `suit`, `card_id`, and `face_up: true`.
  Ranks are 1 = ace, 2–10 = numbers, 11 = jack, 12 = queen, 13 = king.
  Suits are `clubs`, `diamonds`, `hearts`, and `spades`.
- A hidden card is only `{face_up: false}`. It has no rank, suit, or card ID.
  While the dealer has a hidden card, their full `total` and scoring flags are
  `null`; `visible_total` counts only visible cards. Early seat results also have
  `dealer_total: null`. Player busts and naturals do not reveal the dealer while
  other players still need to act. The hole card is revealed at dealer play or
  table completion, and final result snapshots then include the dealer total.

`round_id` increases per engine instance. `hand_id` combines that round ID, seat,
and hand slot. A session controller should combine its own session ID with
`round_id` when tracking settlement across engine instances.

### Events for a future display

Every event has `type`, `round_id`, and a `sequence` starting at 1 for each round
and continuing across that round's command batches.

| Type | Additional fields |
| --- | --- |
| `round_started` | `wager` |
| `phase_changed` | `phase` |
| `card_dealt` | `seat_id`, `hand_id`, zero-based `card_index`, `card` |
| `action_taken` | `seat_id`, `hand_id`, `action` (`hit` or `stand`), `automatic` |
| `dealer_card_revealed` | `seat_id`, `hand_id`, `card_index`, revealed `card` |
| `seat_settled` | `seat_id`, that seat's `result`; emitted once when its outcome is known |
| `round_finished` | `result` |

Reset the displayed table on `round_started`, append cards on `card_dealt`, and
replace the concealed slot on `dealer_card_revealed`. Ordered events supply the
individual moves; the snapshot is the final state after all of those moves.
Avoid rendering the final snapshot before playing its events, which would show
the completed dealer hand before its reveal animation.

The engine does not wait for animations or emit signals. A future scene/controller
can forward these responses through signals and queue animations, while a terminal
adapter can print the same events immediately.

## Rules and payouts

Each round uses a fresh shared shuffled 52-card deck without replacement. For each
of two dealing passes, deal to occupied seats in order `left_2`, `left_1`, `player`,
`right_1`, `right_2`, then the dealer. Skip empty chairs. The dealer's second card is hidden.
Face cards count as 10; aces adjust to the highest non-busting total. Only an
initial two-card 21 is a natural blackjack.

Dealer blackjack ends the round immediately; any player natural pushes against it.
Otherwise naturals are paid early and skipped in turn order. Each AI uses only its
own score: hit below 17 and stand on every 17, including soft 17. There are no
persistent AI bankrolls; their displayed wagers match the human's stake.
The human can hit or stand; 21 automatically stands and a bust loses immediately.
Other occupied seats continue after the human's outcome is known. The dealer
draws only when an unresolved wager requires it, hits below 17 and stands on every 17, including
soft 17. Dealer busts lose; otherwise higher total wins and equal totals push.
There is no split, double down, insurance, or surrender.

The engine accepts every positive integer wager up to `MAX_WAGER`; stake options,
unlock checks, affordability, and table minimums belong to the session controller.
The upper bound ensures even the largest blackjack return fits in a signed
64-bit integer. **Odd wagers are allowed.**

Each seat result contains `round_id`, `seat_id`, `outcome`, `reason`, `wager`, `returned_amount`,
`net_change`, `player_total`, and `dealer_total`.

| Outcome | Returned amount, assuming the stake was already deducted |
| --- | --- |
| `loss` | 0 |
| `push` | Original stake |
| `win` | Stake + equal winnings |
| `blackjack` | Stake + 3:2 winnings rounded **up** to a whole integer |

For a stake of 5, a natural returns 13 total: 5 stake + 8 winnings.
`net_change` is always `returned_amount - wager`. Calculations use exact integer
arithmetic, including for large wagers.

Reasons are `both_blackjack`, `player_blackjack`, `dealer_blackjack`, `player_bust`,
`dealer_bust`, `higher_total`, `lower_total`, or `equal_total`.

The engine never deducts or credits money. The [session controller](blackjack_session_controller.md)
handles five-hand limits, a stake fixed across hands, leaving between hands, stake
unlocks, and wallet transactions through an injected adapter. Lobby transitions
remain separate future work. The same engine instance can start another round
after settlement, with a fresh deck and cleared result.

## Deterministic tests

To run all suites without commands, open `tests/blackjack/blackjack_tests.tscn`
in Godot, press **F6**, and read the **Output** panel. See the
[editor testing instructions](../README.md#run-blackjack-tests-in-godot).

Run from the repository root using a Godot 4 executable:

```powershell
godot --headless --path . --log-file .godot/blackjack-tests.log --script res://tests/blackjack/test_blackjack_engine.gd
```

If Godot is not on `PATH`, replace `godot` with `& 'C:\path\to\Godot_console.exe'`.
The dependency-free runner prints each test and exits with code 1 on failure.

For an exact scenario, pass a full 52-card `deck_order` to `begin_round`.
Each entry needs `{rank, suit}`; extra fields are discarded. Cards are drawn in
array order, and malformed or duplicate cards are rejected before any state
changes. An empty array uses the normal shuffle. The tests build complete decks
from short scenario prefixes and fill in unused cards.

Coverage includes scoring and ace adjustments, all outcomes, dealer behavior,
integer payout rounding, rejected commands, repeated rounds, data isolation,
hidden-card protection, seeded play without replacement, and reconstructing cards
from events for a future display.
