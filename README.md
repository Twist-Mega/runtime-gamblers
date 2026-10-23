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
The production wallet adapter, lobby integration, and final artwork remain future work.

## Play the development blackjack table

Open `tests/blackjack/blackjack_debug.tscn` in Godot and press **F6**. The stake
is already set to **5**. Click **Start Hand**, and use **Hit** or **Stand**. Between hands,
choose **Next Hand** or **Leave Table**. Review the summary, then **Close Session**.

Four AI chairs are occupied by default, two on each side. Their Hit/Stand moves
advance automatically, waiting 1 second before an AI's first move and 0.75 seconds
before later moves in its turn. Busts and confirmed blackjacks settle immediately, with
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
