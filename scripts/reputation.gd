extends Node

## Register as an autoload named "Reputation" in Project Settings when ready to wire up.
## Scale: 1–100. Unlocks stake tiers; awards points from game wins with a per-game cap.

signal reputation_changed(new_amount: int)
signal stake_tier_unlocked(tier: String)

enum StakeTier { LOW, MEDIUM, HIGH }

const MIN_REP := 1
const MAX_REP := 100
const STARTING_REP := 1

const POKER_WIN_REP := 5
const BLACKJACK_STREAK_REP := 5 ## Awarded every 2 blackjack wins in a row
const BLACKJACK_STREAK_NEEDED := 2
const MAX_REP_PER_GAME_SESSION := 15 ## Cap for one sitting; reset after playing another game once

const MED_UNLOCK_REP := 20
const HIGH_UNLOCK_REP := 40

var reputation: int = STARTING_REP

## Rep earned during the current game's sitting (poker / blackjack / etc.).
var _rep_earned_this_game: int = 0
## Which game last awarded or tracked rep ("poker", "blackjack", …).
var _active_game_id: String = ""
## Consecutive blackjack wins in the current sitting.
var _blackjack_win_streak: int = 0


func get_reputation() -> int:
	return reputation


func get_unlocked_stake_tiers() -> Array:
	var tiers: Array = [StakeTier.LOW]
	if reputation >= MED_UNLOCK_REP:
		tiers.append(StakeTier.MEDIUM)
	if reputation >= HIGH_UNLOCK_REP:
		tiers.append(StakeTier.HIGH)
	return tiers


func has_stake_tier(tier: StakeTier) -> bool:
	match tier:
		StakeTier.LOW:
			return true
		StakeTier.MEDIUM:
			return reputation >= MED_UNLOCK_REP
		StakeTier.HIGH:
			return reputation >= HIGH_UNLOCK_REP
		_:
			return false


func stake_tier_name(tier: StakeTier) -> String:
	match tier:
		StakeTier.LOW:
			return "low"
		StakeTier.MEDIUM:
			return "medium"
		StakeTier.HIGH:
			return "high"
		_:
			return "unknown"


## Call when the player sits down / starts a different game so the 15-pt cap can reset.
## Passing the same game_id again does nothing; switching games clears the cap and BJ streak.
func begin_game(game_id: String) -> void:
	if game_id.is_empty():
		return
	if game_id == _active_game_id:
		return
	_active_game_id = game_id
	_rep_earned_this_game = 0
	_blackjack_win_streak = 0


## Poker: +5 rep per win (until the 15-pt sitting cap).
func on_poker_win() -> int:
	begin_game("poker")
	return _try_add_rep(POKER_WIN_REP)


## Blackjack: track streak; every 2 wins in a row grants +5 (until the 15-pt sitting cap).
func on_blackjack_win() -> int:
	begin_game("blackjack")
	_blackjack_win_streak += 1
	if _blackjack_win_streak < BLACKJACK_STREAK_NEEDED:
		return 0
	_blackjack_win_streak = 0
	return _try_add_rep(BLACKJACK_STREAK_REP)


## Call on a blackjack loss/push so the 2-in-a-row streak resets.
func on_blackjack_streak_broken() -> void:
	if _active_game_id == "blackjack":
		_blackjack_win_streak = 0


## How much rep can still be earned this sitting before the cap.
func remaining_rep_this_game() -> int:
	return maxi(MAX_REP_PER_GAME_SESSION - _rep_earned_this_game, 0)


func _try_add_rep(amount: int) -> int:
	if amount <= 0:
		return 0
	var room_in_cap: int = remaining_rep_this_game()
	if room_in_cap <= 0:
		return 0
	var room_to_max: int = MAX_REP - reputation
	if room_to_max <= 0:
		return 0
	var granted: int = mini(amount, mini(room_in_cap, room_to_max))
	if granted <= 0:
		return 0

	var before: int = reputation
	reputation += granted
	_rep_earned_this_game += granted
	reputation_changed.emit(reputation)
	_emit_new_unlocks(before, reputation)
	return granted


func _emit_new_unlocks(before: int, after: int) -> void:
	if before < MED_UNLOCK_REP and after >= MED_UNLOCK_REP:
		stake_tier_unlocked.emit(stake_tier_name(StakeTier.MEDIUM))
	if before < HIGH_UNLOCK_REP and after >= HIGH_UNLOCK_REP:
		stake_tier_unlocked.emit(stake_tier_name(StakeTier.HIGH))
