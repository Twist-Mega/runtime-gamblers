# Blackjack development display

This standalone scene lets you manually play the existing engine and session
controller with textual cards and a fake wallet. It is a development tool; the
production wallet, lobby bridge, and final artwork remain separate work.

## Launch from Godot

1. Open the project in Godot.
2. In FileSystem, open `tests/blackjack/blackjack_debug.tscn`.
3. Press **F6** (Run Current Scene).
4. Click **Stake 5**, then **Start Hand**.
5. Use **Hit** or **Stand**. When settled, choose **Next Hand** or **Leave Table**.
6. After five hands, or leaving, review the summary and click **Close Session**.

The window stays open for manual play. **New Session** starts another session
with the current balance. **Reset test money** recreates the fake wallet and
clears session history. **Leave Table** ends this standalone session; it does not
switch to a lobby scene. Cancelling before the first hand closes immediately.

Default setup: 1,000 fake money units, five hands per session, an unlocked stake
of 5, and a locked stake of 25. The chosen stake remains fixed for the session.
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
- **Unlock higher stakes** enables Stake 25 before selection. The testing toggle
  is disabled once a stake is selected; the controller still validates the choice.
- **Fail next return once** makes the next wallet credit fail. Finish a hand to
  reach the pending-return state, then click **Retry Return**. The original payout
  is applied once and the session continues or completes.
- To check insufficient funds, select the scene root in the editor's Scene dock,
  set exported **Starting Balance** to 5 in the Inspector, and run with F6. Use
  **Hit to bust**, choose Stake 5, Start Hand, then Hit. The balance reaches zero
  and the session ends after one hand. Restore 1,000 afterwards.

The root also exports **Max Hands** (default 5) and **Deal Delay** (default 0.2
seconds per deal/reveal). Fake money is recreated on each launch and never saved.

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
