class_name WizardRules
extends RefCounted

const SUITS: Array[String] = ["red", "blue", "green", "yellow"]
const SUIT_LABELS := {
	"red": "Rot",
	"blue": "Blau",
	"green": "Grün",
	"yellow": "Gelb",
	"none": "Kein Trumpf",
	"pending": "Wahl...",
	"": "Kein Trumpf"
}

static func suit_label(suit: String) -> String:
	return str(SUIT_LABELS.get(suit, suit.capitalize()))

static func create_deck() -> Array[Dictionary]:
	var deck: Array[Dictionary] = []
	var card_id := 0
	for suit in SUITS:
		for val in range(1, 14):
			deck.append({
				"id": card_id,
				"kind": "num",
				"suit": suit,
				"value": val
			})
			card_id += 1
	for i in range(4):
		deck.append({
			"id": card_id,
			"kind": "wizard",
			"suit": "",
			"value": 14
		})
		card_id += 1
	for i in range(4):
		deck.append({
			"id": card_id,
			"kind": "jester",
			"suit": "",
			"value": 0
		})
		card_id += 1
	return deck

static func shuffle_deck(deck: Array[Dictionary], rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		deck.shuffle()
		return
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp

static func total_rounds_for_players(num_players: int, quick_mode: bool = false) -> int:
	var n := clampi(num_players, 2, 6)
	var official_max := int(60 / n)
	if quick_mode:
		return mini(10, official_max)
	return official_max

static func sort_hand(hand: Array) -> Array:
	var sorted := hand.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sort_key(a) < _sort_key(b)
	)
	return sorted

static func _sort_key(card: Dictionary) -> int:
	var kind: String = card.get("kind", "num")
	if kind == "jester":
		return 500 + int(card.get("id", 0))
	if kind == "wizard":
		return 600 + int(card.get("id", 0))
	var suit_idx := SUITS.find(card.get("suit", "red"))
	if suit_idx < 0:
		suit_idx = 0
	return suit_idx * 100 + int(card.get("value", 1))

static func determine_lead_suit(trick_cards: Array) -> String:
	if trick_cards.is_empty():
		return ""
	var first_card: Dictionary = trick_cards[0].get("card", {})
	if first_card.get("kind", "") == "wizard":
		return ""
	for entry in trick_cards:
		var c: Dictionary = entry.get("card", {})
		if c.get("kind", "") == "num":
			return c.get("suit", "")
	return ""

static func get_legal_card_ids(hand: Array, trick_cards: Array) -> Array[int]:
	var legal: Array[int] = []
	var lead_suit := determine_lead_suit(trick_cards)
	var has_lead_suit := false
	if lead_suit != "":
		for c in hand:
			if c.get("kind", "") == "num" and c.get("suit", "") == lead_suit:
				has_lead_suit = true
				break
	for c in hand:
		var kind: String = c.get("kind", "")
		if not has_lead_suit or kind == "wizard" or kind == "jester" or c.get("suit", "") == lead_suit:
			legal.append(int(c.get("id", -1)))
	return legal

static func evaluate_trick_winner(trick_cards: Array, trump_suit: String) -> int:
	if trick_cards.is_empty():
		return -1
	# 1. First Wizard played always wins
	for entry in trick_cards:
		var c: Dictionary = entry.get("card", {})
		if c.get("kind", "") == "wizard":
			return int(entry.get("player_idx", -1))

	# 2. Highest Trump wins if trump exists
	if trump_suit != "" and trump_suit != "none":
		var best_trump_val := -1
		var best_trump_player := -1
		for entry in trick_cards:
			var c: Dictionary = entry.get("card", {})
			if c.get("kind", "") == "num" and c.get("suit", "") == trump_suit:
				var v := int(c.get("value", 0))
				if v > best_trump_val:
					best_trump_val = v
					best_trump_player = int(entry.get("player_idx", -1))
		if best_trump_player != -1:
			return best_trump_player

	# 3. Highest card of Lead Suit wins
	var lead_suit := determine_lead_suit(trick_cards)
	if lead_suit != "":
		var best_lead_val := -1
		var best_lead_player := -1
		for entry in trick_cards:
			var c: Dictionary = entry.get("card", {})
			if c.get("kind", "") == "num" and c.get("suit", "") == lead_suit:
				var v := int(c.get("value", 0))
				if v > best_lead_val:
					best_lead_val = v
					best_lead_player = int(entry.get("player_idx", -1))
		if best_lead_player != -1:
			return best_lead_player

	# 4. All Jesters played: first Jester wins
	return int(trick_cards[0].get("player_idx", -1))

static func calculate_round_score(bid: int, tricks_won: int) -> int:
	if bid == tricks_won:
		return 20 + 10 * tricks_won
	return -10 * absi(tricks_won - bid)

static func card_label(card: Dictionary) -> String:
	var kind: String = card.get("kind", "")
	if kind == "wizard":
		return "Zauberer"
	if kind == "jester":
		return "Narr"
	var suit: String = card.get("suit", "")
	return "%s %d" % [SUIT_LABELS.get(suit, suit.capitalize()), int(card.get("value", 0))]

static func choose_ai_trump(hand: Array) -> String:
	var scores := {"red": 0.0, "blue": 0.0, "green": 0.0, "yellow": 0.0}
	for c in hand:
		if c.get("kind", "") == "num":
			var s: String = c.get("suit", "")
			scores[s] = scores.get(s, 0.0) + 1.0 + float(c.get("value", 0)) / 13.0
	var best_suit := "red"
	var best_score := -1.0
	for s in SUITS:
		if scores[s] > best_score:
			best_score = scores[s]
			best_suit = s
	return best_suit

static func choose_ai_bid(hand: Array, trump_suit: String, round_num: int, forbidden_bid: int = -1) -> int:
	var expected := 0.0
	for c in hand:
		var kind: String = c.get("kind", "")
		if kind == "wizard":
			expected += 0.95
		elif kind == "num":
			var v := int(c.get("value", 0))
			if c.get("suit", "") == trump_suit:
				if v >= 10:
					expected += 0.8
				elif v >= 6:
					expected += 0.45
				else:
					expected += 0.2
			else:
				if v == 13:
					expected += 0.55
				elif v >= 11:
					expected += 0.3
	var bid := clampi(int(round(expected)), 0, round_num)
	if bid == forbidden_bid:
		if float(bid) <= expected and bid + 1 <= round_num:
			bid += 1
		elif bid - 1 >= 0:
			bid -= 1
		elif bid + 1 <= round_num:
			bid += 1
	return bid

static func choose_ai_card(hand: Array, trick_cards: Array, trump_suit: String, bid: int, tricks_won: int) -> int:
	var legal_ids := get_legal_card_ids(hand, trick_cards)
	if legal_ids.is_empty():
		return -1
	var legal_cards: Array[Dictionary] = []
	for c in hand:
		if int(c.get("id", -1)) in legal_ids:
			legal_cards.append(c)

	var want_win := tricks_won < bid
	var lead_suit := determine_lead_suit(trick_cards)

	# Rank each legal card by strength
	legal_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _card_power(a, trump_suit, lead_suit) < _card_power(b, trump_suit, lead_suit)
	)

	if want_win:
		# Pick strongest legal card if leading or can beat current winner, else dump weakest
		if trick_cards.is_empty():
			return int(legal_cards[-1].get("id", legal_ids[0]))
		var current_best := -1.0
		for entry in trick_cards:
			var p := _card_power(entry.get("card", {}), trump_suit, lead_suit)
			if p > current_best:
				current_best = p
		# Find weakest card that still beats current_best
		for c in legal_cards:
			if _card_power(c, trump_suit, lead_suit) > current_best:
				return int(c.get("id", legal_ids[0]))
		# Cannot win: dump weakest
		return int(legal_cards[0].get("id", legal_ids[0]))
	else:
		# Want to lose: pick weakest legal card (Jester first if available)
		return int(legal_cards[0].get("id", legal_ids[0]))

static func _card_power(c: Dictionary, trump_suit: String, lead_suit: String) -> float:
	var kind: String = c.get("kind", "")
	if kind == "wizard":
		return 100.0
	if kind == "jester":
		return 0.0
	var s: String = c.get("suit", "")
	var v := float(c.get("value", 0))
	if trump_suit != "" and trump_suit != "none" and s == trump_suit:
		return 50.0 + v
	if lead_suit != "" and s == lead_suit:
		return 20.0 + v
	return v
