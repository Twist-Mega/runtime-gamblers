extends RefCounted

## Decide preflop actions using hand tiers and wager totals in big blinds.

enum Tier { WEAK, WEAK_PLUS, SPECULATIVE, PLAYABLE, STRONG, PREMIUM }

const Rank := preload("res://scripts/holdem/holdem_hand_rank.gd")
const RANKS := "23456789TJQKA"
const MAX_CALL_BB := [0, 1, 1, 2, 4, -1] # Premium has no call limit.
const RAISE_TO_BB := [0, 0, 0, 0, 2, 3]


## Match the listed hands first, then put all remaining suited hands in Weak+.
static func hand_tier(cards: Array[int]) -> Tier:
	var first := Rank.rank(cards[0])
	var second := Rank.rank(cards[1])
	var suited := Rank.suit(cards[0]) == Rank.suit(cards[1])
	var label := RANKS[maxi(first, second) - 2] + RANKS[mini(first, second) - 2]
	if first != second:
		label += "s" if suited else "o"
	match label:
		"AA", "KK", "QQ", "AKs", "AKo":
			return Tier.PREMIUM
		"JJ", "TT", "99", "AQs", "AQo", "AJs", "KQs":
			return Tier.STRONG
		"88", "77", "66", "55", "AJo", "ATs", "KQo", "KJs", "QJs", "JTs", "KTs", "QTs", "A9s":
			return Tier.PLAYABLE
		"44", "33", "22", "A2s", "A3s", "A4s", "A5s", "A6s", "A7s", "A8s", "ATo", "KJo", "QJo", "JTo", \
		"K9s", "Q9s", "J9s", "T9s", "T8s", "98s", "97s", "87s", "86s", "76s", "75s", "65s", "64s", "54s", "53s", "43s":
			return Tier.SPECULATIVE
		"KTo", "QTo", "J9o", "T9o", "98o", "87o", "76o", "65o", "54o":
			return Tier.WEAK_PLUS
	return Tier.WEAK_PLUS if suited else Tier.WEAK


## Decide whether to continue before trying the tier's exact raise target.
static func decide(turn: Dictionary) -> Dictionary:
	var tier := hand_tier(turn.cards)
	var legal: Dictionary = turn.legal
	# Use the full bet even when the engine would accept a short all-in call.
	if legal.to_call > 0 and tier != Tier.PREMIUM:
		if turn.bet_to_match > MAX_CALL_BB[tier] * turn.big_blind:
			return {"action": "fold"}
	var target: int = RAISE_TO_BB[tier] * turn.big_blind
	if legal.can_wager and target >= legal.min_raise_to and target <= legal.max_raise_to and target < legal.all_in_to:
		return {"action": "wager", "raise_to": target}
	return {"action": "call" if legal.to_call > 0 else "check"}
