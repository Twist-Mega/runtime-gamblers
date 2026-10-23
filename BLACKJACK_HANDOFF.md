# Blackjack handoff

Snapshot: 2026-10-23. Read this first when continuing blackjack development.
This describes the current working files; check `git status` before editing.

## Scope and current work

- Project: Runtime Gamblers, Godot 4.7 / GDScript (`.gd`), not Python.
- Branch: `blackjack`. Development and the display scaling fixes are committed
  and pushed. The approved wallet/gameworld integration and these documentation
  updates are currently uncommitted; inspect `git status` before proceeding.
- Work in small, explicitly approved pieces. Explain the proposed changes and
  ask before implementing the next piece or batch. Do not expand the scope.
- Only the right-side tables have blackjack interaction and UI. Do not add
  interaction or scripts to the left tables without the user's approval.
- The right-table green popup opens blackjack with the official Wallet. Leaving
  or reaching a session limit returns to that popup's summary and Play Again.
- Display cleanup: removed the subtitle, stake-selection prompts/buttons, and
  higher-stake unlock. The display shows `Stake: 5` and selects it automatically
  on launch, New Session, and reset. Preserve gameplay during further UI changes.

## Structure: rules, session, display

```text
Human input -> Display -> Session controller -> Engine
                             |                    |
                          Wallet port       Rules/cards/AI
                             |
                   Official Wallet / debug fake wallet

Command response -> ordered events -> visual playback -> final public snapshot
```

| File | Responsibility |
| --- | --- |
| [blackjack_engine.gd](scripts/blackjack/blackjack_engine.gd) | One shared-deck table round: cards, scoring, turns, AI decisions, outcomes. `RefCounted`; no UI, timers, wallet, or lobby. |
| [blackjack_session_controller.gd](scripts/blackjack/blackjack_session_controller.gd) | A table visit: stake selection, hand limit, legal actions, human money transactions, retries, summary, closing. Also `RefCounted`. |
| [blackjack_wallet_port.gd](scripts/blackjack/blackjack_wallet_port.gd) | Abstract wallet interface: `get_balance()` and `apply_transaction(id, delta)`. |
| [game_wallet_adapter.gd](scripts/blackjack/game_wallet_adapter.gd) + [wallet.gd](scripts/wallet.gd) | Read and transact against the official game's balance. Successful transaction IDs are recorded in Wallet for its application lifetime. |
| [blackjack_table_UI.gd](scripts/blackjack/blackjack_table_UI.gd) + [gameworld.tscn](scenes/gameworld.tscn) | Existing right-table popup, Play/Play Again, overlay lifecycle, green summary, and C exit. |
| [fake_wallet.gd](tests/blackjack/fake_wallet.gd) | Test-only balance and transaction ledger; supports simulated payment failures. |
| [blackjack_debug.tscn](tests/blackjack/blackjack_debug.tscn) + [blackjack_debug.gd](tests/blackjack/blackjack_debug.gd) | Display reused for standalone debug and gameworld play. Accepts a supplied wallet; otherwise creates a fake wallet. Displays public cards, actions, results, and logs. |
| `tests/blackjack/test_blackjack_*.gd` | Engine, session, and real debug-scene tests. |

Keep `.gd.uid` files with their scripts. `.godot/` is generated local data.
An untracked temporary Git-plugin DLL ending in `.TMP` is unrelated to blackjack;
do not include it in blackjack commits or delete it as part of UI cleanup.

## Completed behavior and agreed rules

- Original engine, session controller, fake wallet, debug display, and tests work.
- Added four optional generic AI chairs: `left_2` (outer left), `left_1` (inner
  left), `right_1` (inner right), `right_2` (outer right). The human is `player`;
  the dealer is `dealer`. Debug play fills all four AI chairs by default.
- Occupancy is configured before a session, copied, and fixed throughout it.
  Empty chairs receive no cards. AI have no persistent bankrolls or networking.
- Fresh shared 52-card deck each round, without replacement. Deal two passes in
  order `left_2 -> left_1 -> player -> right_1 -> right_2 -> dealer`, skipping empty
  chairs. AI draws affect cards available to the human and dealer.
- Turn order follows that same seating order, with the dealer last. AI hit below
  17 and stand on every 17, including soft 17. They do not inspect hidden cards.
- Human Hit/Stand remain manual; reaching 21 automatically stands. Aces adjust;
  face cards count as 10. No splitting, doubling, insurance, or surrender yet.
- Dealer blackjack resolves the table immediately. Otherwise confirmed natural
  blackjacks settle early; busts lose immediately. Remaining players continue.
  Ordinary hands settle after the dealer plays. Dealer stands on soft 17 and
  skips drawing when all wagers are already decided.
- Returns include the deducted stake: loss `0`, push `stake`, win `2 * stake`,
  natural `stake + ceil(1.5 * stake)`. At stake 5, blackjack returns 13, profit 8.
- One selected stake per session; default limit five rounds. Deduct one human
  stake per round, never all five upfront. Leaving is allowed before play or
  between completed table rounds. Standalone debug waits for summary
  acknowledgement. Gameworld play automatically closes the session and hands
  its summary to the green popup instead.
- Human settlement and **whole-table completion are separate**. An early result
  can credit chips/count the human hand while AI still play. Next Hand, Leave,
  and session completion wait for the whole table and any pending payment.
- Display automatically advances AI/dealer turns, speeds up after the human
  result is known, and highlights the active seat with an amber outline/name
  and lighter background. Highlight follows playback, including AI thinking time.

## Approved gameworld flow

- F5, approach a right-side table, X, Play, Start Hand. Uses the official game
  Wallet (100 on a fresh launch), stake 5, up to five hands, and four AI chairs.
- Play does not charge money. Each Start Hand deducts one stake; payouts use the
  same balance shown in the game's pause menu. Play Again never resets money.
- Leave Table, the five-hand limit, or insufficient funds automatically removes
  the blackjack overlay and returns to the green popup. It shows Hands, Start,
  End, and Net, plus Play Again. Play Again is disabled below the required stake.
- Leaving before the first hand shows a zero-hand summary without a charge.
- The world stays paused while blackjack or the green summary is open. C closes
  only the green popup and resumes exploring. C does nothing inside blackjack.
- The overlay's temporary scaling is restored before showing the green popup.
  The left tables, project resolution, camera, and movement scripts are unchanged.
- Gameworld play hides Next deal, Fail next return once, Reset test money,
  New Session, the Testing tools heading, and the separate Close Session button.
  Standalone debug keeps its tools and its own 1,000 fake-money balance.
- Retry Return remains visible but disabled except during pending payments.
  No genuine payout failures have been observed; fake-wallet tests inject them.
  Showing this recovery control only when needed is an unresolved UI decision.

## Interfaces and important safeguards

- Engine: `BlackjackEngine.new(seed = null, occupied_ai_seats = [])`,
  `begin_round(wager, deck_order = [])`, `hit()`, `stand()`, `advance_table()`,
  `get_public_state()`. One `advance_table()` performs one AI decision or the
  dealer's complete turn. With no AI, existing synchronous single-player behavior
  is retained. Fixed decks for tests must contain all 52 unique cards.
- Session: `open_blackjack(table_id)`, `select_stake(option_id)`,
  `start_next_hand(deck_order = [])`, `hit()`, `stand()`, `advance_table()`,
  `leave_table()`, `acknowledge_result()`, `retry_pending_transaction()`.
- Display: call `configure_wallet(adapter)` before adding it to the tree.
  Gameworld sets `manage_window_scaling` and `return_summary_to_host` to true
  and listens for `session_closed(summary)` with a deferred connection. The view
  acknowledges COMPLETE internally in this mode, after ordered playback finishes.
- Pass table configuration explicitly: `{max_hands, ai_seats, stake_options}`.
  Debug configuration uses a fixed stake 5, selected automatically. The controller's legacy
  fallback table uses stake **2 and no AI**; do not assume its defaults match the demo.
- Session responses contain `{accepted, error, state, events, result, summary}`.
  Use **session-level `legal_actions`** to enable controls. Automatically advance
  only while `advance_table` is legal; stop for human input when Hit/Stand are legal.
- Public `state.hand` exposes seats, occupancy, status, hands/cards, active seat,
  phase, and results. Copies can be rendered without touching private engine data.
- Hidden dealer card is only `{face_up: false}`, without rank/suit/card ID.
  Hidden full totals and early results' `dealer_total` are null until reveal.
- Wallet transactions must be atomic and idempotent: a successful ID applied
  twice with the same delta credits/debits only once. Failed credits/refunds keep
  play in a pending state; Retry uses the same ID. AI never touch the human wallet.
- Engine responses can repeat an already-known human result during later AI moves.
  The session deduplicates it by round ID. Its top-level `result` represents a
  **new** financial settlement. Renderers must never apply payouts themselves.

## How a detailed animated display will connect

**The engine already produces the information an animated scene needs.** Its
results are data, not terminal output. The current plain cards are one renderer
of that data; sprites and animations can replace it without rewriting the rules.

Create a production Godot table scene with seat anchors, a deck position, card
scenes/sprites, chip visuals, and input buttons. The current display already
accepts a wallet adapter and is reused in the gameworld; extracting a separate
production renderer or accepting an existing session is not implemented yet.

For each accepted command, play its events **in order**:

| Event | Possible animation |
| --- | --- |
| `round_started` | Clear old cards/results and prepare occupied chairs. |
| `phase_changed` | Highlight `active_seat_id`; show the current turn. |
| `action_taken` | Show Hit/Stand text or character gesture, with AI thinking delays. |
| `card_dealt` | Spawn a card at the deck; Tween it to the target `seat_id` / `hand_id` / `card_index`. Use rank/suit artwork only if `face_up` is true. |
| `dealer_card_revealed` | Flip the existing hidden card and apply the newly supplied face. |
| `seat_settled` | Show that seat's outcome, including the human's early bust/blackjack. |
| `wallet_transaction` | Update the displayed balance/animate human chips. Money is already handled by the session. |
| `round_finished` | Present the finished table. Allow next-round actions only when the session permits them. |
| `session_finished` / `session_closed` | Standalone summary/acknowledgement, or automatic return to the gameworld's green summary popup. |

The response snapshot is the state **after the entire command**, sometimes after
several dealer draws. Do not render it before its event animations: that could
reveal the dealer's final cards too early. Maintain visual state while playing
events, await each animation, then reconcile with `response.state` and unlock
legal controls. Session events have a global `sequence`; forwarded engine events
also retain `round_sequence` and `round_id`. Stable IDs identify the correct cards.

The current adapter examples are `_request`, `_play_events`, `_refresh_view`, and
`_set_active_seat` in `blackjack_debug.gd`. Keep timing, sounds, Tweens, and sprites
in the view/adapter. Engine/session commands stay synchronous and testable.

The official wallet adapter, gameworld overlay, and green summary/return flow
are implemented. Cross-launch wallet persistence, a separate production renderer,
and final artwork remain future work. The engine/session do not change scenes.

## Running, timing, and tests

- **Play:** open `tests/blackjack/blackjack_debug.tscn`, press **F6**. This branch
  now uses development's gameworld as its main scene for F5. Click Start Hand,
  then Hit/Stand. AI turns run automatically around yours.
- Standalone debug play overrides window scaling to a 1280 × 720 canvas-item
  layout, restoring previous settings on exit. Development's 320 × 180 world
  resolution and project pixel font remain unchanged. The gameworld overlay
  explicitly opts into the same temporary scaling override; other embedded
  displays leave their host window alone.
- Seat headings/totals stack and wrap; cards wrap within reserved column widths.
  Populating hands must not expand the table beyond the viewport.
- **Test:** open `tests/blackjack/blackjack_tests.tscn`, press **F6**, read Output.
  It runs automated tests and closes; it is not the playable scene.
- Last verified suites: engine **42 tests / 6391 checks**, session **42 / 724**,
  display **21 / 280**, all passing. Tests cover populated-table bounds during
  dealing/hitting/settlement, standalone scaling/restoration,
  embedded host settings, automatic stake selection,
  insufficient starting funds, shared-deck order, manual input,
  hidden-card privacy, early payment/retry, limits, event playback, pacing, and highlighting.
- The user verified the gameworld flow manually on 2026-10-23: right-table Play,
  official balance, green summary, Play Again, C exit, and pause-menu balance.
- Additional local checks passed for wallet transactions, the adapter, supplied
  wallet/display behavior, 107 green-summary checks (including five-hand and
  insufficient-funds endings), and 15 testing-control visibility checks. Their
  helper scripts/logs are under ignored `.godot/`; they are not permanent tests
  in the three committed suites. Do not claim the runner covers gameworld flow.
- Optional terminal command, when Godot is on PATH:
  `godot --headless --path . res://tests/blackjack/blackjack_tests.tscn`
- Inspector exports on `BlackjackDebug`: starting balance, max hands, AI seats,
  deal delay, first/subsequent AI move delays, fast-forward delay,
  manage-window-scaling and return-summary-to-host switches.
- **Script defaults:** deal 0.35 s; AI waits 1 s before its first move and 0.75 s
  before later moves in that turn; fast-forward 0.07 s once human outcome is known.
  AI Hit cards appear with the action without another card delay.
- **Saved scene overrides at this snapshot:** first AI move **2 s**, later AI moves
  **1 s**, set by the user while testing. Scene overrides win over script defaults;
  preserve them unless requested otherwise.
- Debug-only options currently include shuffled/preset deals,
  fail-next-credit, wallet reset, and New Session. Presets deliberately give AI
  standing hands to preserve the advertised human outcome; use Shuffled to observe
  varied AI moves. Update affected display tests when simplifying these controls.

More detail: [engine](docs/blackjack_engine.md),
[session/wallet](docs/blackjack_session_controller.md),
[debug display](docs/blackjack_debug_display.md). Keep this handoff current when
interfaces, scope, or accepted behavior change.
