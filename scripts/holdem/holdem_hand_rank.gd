extends RefCounted

## Ranks a Hold'em hand by scoring all 21 ways to choose five of the seven cards.
## Each score has six base-15 slots. The hand category comes first, followed by
## up to five ranks used to break ties. Unused slots are zero. The highest score
## represents the best five-card hand, and matching scores tie.

const CATEGORY_NAMES := [
	"High card", "Pair", "Two pair", "Three of a kind", "Straight", "Flush",
	"Full house", "Four of a kind", "Straight flush",
]
const CATEGORY_PLACE := 759375 # 15 to the fifth power


# Card IDs 0 through 51 are grouped into clubs, diamonds, hearts, and spades.
# Each group has 13 cards ordered from 2 through ace.

## The remainder is the position within the suit. Add 2 to get a rank from 2 to 14.
static func rank(card: int) -> int:
	return card % 13 + 2


## Integer division drops the remainder and returns the suit index from 0 to 3.
@warning_ignore("integer_division")
static func suit(card: int) -> int:
	return card / 13


## Score every five-card combination and return the highest score.
static func best_of_seven(cards: Array[int]) -> int:
	var best := -1
	# Every five-card hand leaves exactly two of the seven cards unused.
	for first in range(6):
		for second in range(first + 1, 7):
			var five := cards.duplicate()
			five.remove_at(second)
			five.remove_at(first)
			best = maxi(best, _score_five(five))
	return best


## Look up the display name for the category stored in a hand score.
@warning_ignore("integer_division")
static func category_name(score: int) -> String:
	return CATEGORY_NAMES[score / CATEGORY_PLACE]


## Find the strongest category for five cards, then score its ranks in tiebreak order.
static func _score_five(cards: Array[int]) -> int:
	var counts := PackedInt32Array()
	counts.resize(15)
	var flush := true
	var ranks: Array[int] = []
	for card in cards:
		var value := rank(card)
		counts[value] += 1
		ranks.append(value)
		flush = flush and suit(card) == suit(cards[0])
	ranks.sort()
	ranks.reverse()

	var four := 0
	var three := 0
	var pairs: Array[int] = []
	var singles: Array[int] = []
	for value in range(14, 1, -1):
		match counts[value]:
			4: four = value
			3: three = value
			2: pairs.append(value)
			1: singles.append(value)
	var straight := 0
	if singles.size() == 5:
		if ranks == [14, 5, 4, 3, 2]:
			straight = 5
		elif ranks[0] - ranks[4] == 4:
			straight = ranks[0]

	if flush and straight > 0:
		return _score(8, [straight])
	if four > 0:
		return _score(7, [four, singles[0]])
	if three > 0 and not pairs.is_empty():
		return _score(6, [three, pairs[0]])
	if flush:
		return _score(5, ranks)
	if straight > 0:
		return _score(4, [straight])
	if three > 0:
		return _score(3, [three, singles[0], singles[1]])
	if pairs.size() == 2:
		return _score(2, [pairs[0], pairs[1], singles[0]])
	if pairs.size() == 1:
		return _score(1, [pairs[0], singles[0], singles[1], singles[2]])
	return _score(0, ranks)


## Build a base-15 score with the category first and five slots for tiebreakers.
static func _score(category: int, tiebreakers: Array) -> int:
	var score := category
	for index in range(5):
		score *= 15
		if index < tiebreakers.size():
			score += tiebreakers[index]
	return score
