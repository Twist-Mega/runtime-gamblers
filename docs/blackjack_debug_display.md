# Blackjack development display

This standalone scene lets you manually play the existing engine and session
controller with textual cards and a fake wallet. It is a development tool; the
production wallet, lobby bridge, and final artwork remain separate work.

## Launch from Godot

1. Open the project in Godot.
2. In FileSystem, open `tests/blackjack/blackjack_debug.tscn`.
3. Press **F6** (Run Current Scene).
4. The table shows **Stake: 5** with the stake already selected. Click **Start Hand**.
5. Use **Hit** or **Stand**. When settled, choose **Next Hand** or **Leave Table**.
6. After five hands, or leaving, review the summary and click **Close Session**.

The window stays open for manual play. **New Session** starts another session
with the current balance. **Reset test money** recreates the fake wallet and
clears session history. **Leave Table** ends this standalone session; it does not
switch to a lobby scene. Cancelling before the first hand closes immediately.

Default setup: 1,000 fake money units, five hands per session, and a fixed stake
of 5. Launching, opening a new session, and resetting select this stake through
the controller automatically, without charging money until a hand starts.
There are no stake selection buttons or higher-stake unlock toggle.
All four AI chairs are occupied by default, with two on each side of the human.
Everyone draws from one deck and the display advances AI/dealer turns automatically.
The active seat has an amber outline, lighter background, and amber name. The
highlight follows event playback, stays on an AI during its thinking pause, and
moves to the human or dealer when their turn begins. It clears between rounds.
Dealer cards show a face-down placeholder until revealed; totals, hand progress,
individual moves, money transfers, payouts, and the final summary are displayed.
The whole page can scroll if the game window is small.

## Repeatable checks

The **Next deal** selector affects the next hand only:

| Mode | Action and expected result for stake 5 |
| --- | --- |
| Shuffled | Normal randomized blackjack; choose Hit/Stand as desired. |
| Player blackjack | Start Hand settles immediately, returning 13 and earning 8. |
| Hit to bust | Start Hand, then Hit: the player busts and loses 5. |
| Push (stand) | Start Hand, then Stand: both totals are 17 and the original 5 is returned. |
| Dealer bust (stand) | Start Hand, then Stand: dealer busts, returning 10 and earning 5. |

Preset decks exist only in this display. The core engine/controller use their
normal interfaces and rules. The selector is disabled during a hand and event
playback. It stays selected for following hands until changed.

- Use **Push (stand)** for all five hands to check the hand limit and unchanged
  balance. Next Hand becomes unavailable after the fifth hand.
- **Leave Table** is disabled during active hands and enabled between settled
  hands. Leave after one or two hands to check the summary and preserved balance.
- **Fail next return once** makes the next wallet credit fail. Finish a hand to
  reach the pending-return state, then click **Retry Return**. The original payout
  is applied once and the session continues or completes.
- To check insufficient funds, select the scene root in the editor's Scene dock,
  set exported **Starting Balance** to 5 in the Inspector, and run with F6. Use
  **Hit to bust**, Start Hand, then Hit. The balance reaches zero
  and the session ends after one hand. Restore 1,000 afterwards.

The root also exports **Max Hands** (default 5), **Deal Delay** (default 0.35
seconds for the initial deal, human/dealer cards, and dealer reveals/stands),
**Ai First Move Delay** (1 second), **Ai Next Move Delay** (0.75 seconds), and
**Fast Forward Delay** (0.07 seconds). Each AI waits before its first Hit or Stand,
then waits 0.75 seconds before every later move in that turn. Its Hit card appears
with the move, without an additional card pause. First-move timing resets for
each seat and each new round. After the human busts or receives a confirmed blackjack, the result
and chips are shown immediately and remaining play speeds up. Next Hand/Leave
wait until the entire table finishes. Payment failures still require Retry Return.

To configure chairs, select the scene root before F6 and edit **Ai Seats** in the
Inspector. Valid entries are `left_2` (outer left), `left_1` (inner left),
`right_1` (inner right), and `right_2` (outer right). Remove entries to leave empty
chairs, or empty the array for the original human-versus-dealer game. Occupancy is
copied at session creation and stays fixed across its hands. Preset deals also
work with occupied AI chairs; those fixtures give AI standing hands to preserve
the advertised human scenario. Shuffled play uses the normal AI decisions.

Fake money is recreated on each launch and never saved. To check early settlement,
use Player blackjack, or Hit to bust and then Hit: watch the result/balance update
while AI play finishes quickly. The log records every seat's cards and actions.

## Display/controller boundary

`tests/blackjack/blackjack_debug.gd` creates the interface and forwards buttons to
the [session controller](blackjack_session_controller.md). It does not calculate
scores, determine wins, or credit money itself. Testing tools operate on the
injected fake wallet and development configuration.

For each command, the display disables input, plays the ordered events, and then
renders the returned public snapshot and permitted actions. This prevents the
final dealer hand from appearing before the reveal, or a repeated click starting
an extra hand when a natural settles during the initial deal. Concealed cards are
rendered from public data only. The move/money log records the same events.

Final table visuals can use this same command/event pattern with card artwork,
seat positioning, and animation. The development scene does not modify the
project's main scene or introduce table/lobby interactions.

## Automated checks

Open `tests/blackjack/blackjack_tests.tscn` and press **F6** to run the engine,
session, and display suites. The display tests instantiate the actual scene and
exercise its button signals, including delayed playback and rejected extra input.
For detailed results, read Godot's Output panel or `.godot/blackjack-debug-tests.log`.
