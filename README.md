# runtime-gamblers
A casino RPG made in Godot for Capstone II
#rachel push test
#Brendan is pushing >:{
#Hunter is now pushing...

## Blackjack

The standalone GDScript engine handles one shared-deck table round with optional
generic AI players and exposes copied
state and ordered events for a future display. See [the engine API and tests](docs/blackjack_engine.md).

The [session controller](docs/blackjack_session_controller.md) manages selectable
stakes, up to five hands, leaving between hands, unlocks, and transactions through
a wallet interface. Its tests use a fake wallet. A
[development display](docs/blackjack_debug_display.md) supports manual play.
The gameworld reuses that display through an adapter to the official Wallet.
Final artwork and saving money across application launches remain future work.

## Play blackjack in the gameworld

1. Press **F5** to run the gameworld.
2. Approach a **right-side blackjack table** and press **X** to open the green popup.
3. Check the stake shown in the popup, then click **Play** and **Start Hand**.
4. Use **Hit** or **Stand**, then **Next Hand** to continue.
5. **Leave Table**, five completed hands, or insufficient funds returns you to
   the green popup with a summary: **Hands, Start, End, and Net**.
6. Choose **Play Again** to start a new session with the current balance, or
   press **C** on the green popup to resume exploring.

| Right-side table | Stake per hand |
| --- | --- |
| Bottom | 5 |
| Middle | 10 |
| Top | 20 |

Each table's stake stays fixed for its session. **Play Again** uses that same
table and stake; both Play and Play Again require enough money for that stake.
The blackjack display and green summary also show the selected table's stake.

The left tables have no blackjack interaction or UI yet. Gameworld play uses
the official Wallet, which starts at 100 on a fresh launch and also supplies the
pause menu's balance. Opening Play takes no money; Start Hand deducts one stake.
Play Again is disabled when another stake is unaffordable. Leaving before the
first hand returns a zero-hand summary without a charge.

The world stays paused through blackjack and the green summary. C only exits
the green popup; it does not abandon an active blackjack display. The overlay
temporarily uses a 1280 x 720 UI layout and restores world scaling when it closes.
Testing controls and New Session are hidden in gameworld play. **Retry Return**
remains visible but is enabled only for a pending payout or refund.

## Play the development blackjack table

Open `tests/blackjack/blackjack_debug.tscn` in Godot and press **F6**. The stake
is already set to **5**. Click **Start Hand**, and use **Hit** or **Stand**. Between hands,
choose **Next Hand** or **Leave Table**. Review the summary, then **Close Session**.

Four AI chairs are occupied by default, two on each side. Their Hit/Stand moves
advance automatically. The saved scene waits 2 seconds before an AI's first move
and 1 second before later moves in its turn. Busts and confirmed blackjacks settle immediately, with
faster playback until the rest of the table finishes. Other hands settle after
the dealer. Edit the root's **Ai Seats** array in the Inspector before F6 to
configure occupancy; an empty array gives the original single-player game.

You start with 1,000 fake money units. **New Session** keeps that balance;
**Reset test money** starts over. The testing tools include preset deals and
a one-time failed return to check retry behavior. See the
[manual testing instructions](docs/blackjack_debug_display.md) for expected results.

## Run blackjack tests in Godot

1. Open this project in Godot.
2. In the FileSystem dock, open `tests/blackjack/blackjack_tests.tscn`.
3. Press **F6** (Run Current Scene), then open the **Output** panel at the bottom.

The scene runs all three suites automatically using your current Godot executable.
The test window closes when finished; the results stay in the editor's Output.
You do not need a terminal command, PATH setup, or a main scene for this.

Currently, successful output ends with:

```text
Blackjack: 42 tests, 6391 checks, 0 failures.
Blackjack sessions: 42 tests, 724 checks, 0 failures.
Blackjack display: 21 tests, 280 checks, 0 failures.
Blackjack tests: ALL SUITES PASSED.
```

If a test fails, look for `FAIL` or `SCRIPT ERROR` above the final failure message.
Assertion failures include the test name and expected/actual values. Fix the
reported problem, save, and run the test scene with F6 again. Complete suite logs
are also saved in `.godot/blackjack-tests.log`, `.godot/blackjack-session-tests.log`,
and `.godot/blackjack-debug-tests.log`.

Run these tests after changing blackjack rules, payouts, stakes, or session flow.
They exercise the engine, session, and display automatically. For manual play,
use `tests/blackjack/blackjack_debug.tscn`.

The three suites above do not cover the complete gameworld interaction. Also
manually check each right table -> X -> Play -> hand -> green summary -> Play Again/C.
Confirm bottom/middle/top use 5/10/20, the stake carries over on Play Again, and
the official balance agrees with the summary and pause menu.
