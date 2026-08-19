-- "@owner_of.<scope>" — the seats that own what a scope names.
--
-- Every other way of naming a seat is written down in advance: "mine" and
-- "enemy" are relative to whoever is up, and a seat key reaches its own card
-- because the game file tagged it with its own name. None of them can say
-- *whoever owns this particular card*, which is the question a trick winner, a
-- captured piece and a card played out of somebody's hand all ask.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local geometry = require("geometry")

local M = {}

local GAME = [==[{
  "title": "Owner Scope",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "subject": "score@mine.player" }],
  "zones": [
    { "key": "board", "type": "grid", "grid": [4, 1], "tags": ["activate"],
      "pos": [0.05, 0.40, 0.95, 0.60] },
    { "key": "commons", "type": "pile", "pos": [0.30, 0.70, 0.45, 0.90] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "board", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "score": 0 } },
    { "key": "piece", "text": "Piece", "tags": ["piece"] }
  ],
  "setup": {
    "place": [
      { "card": "piece", "owner": "one", "zone": "board", "at": ["a1", "b1"] },
      { "card": "piece", "owner": "two", "zone": "board", "at": ["c1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_owner_scope.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_owner_scope.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- The piece standing on a square, by its algebraic name.
local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("board"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

function M.test_owner_scope_reads_the_seat_a_card_belongs_to(check)
	with_game(function(name)
		flow.init(name, 3)
		seat("one").stats.score = 3
		seat("two").stats.score = 7
		check("the first seat is up", zones.active_seat() == "one", tostring(zones.active_seat()))

		local theirs = { targets = { at("c1").id } }
		check("the target's owner answers, not the seat whose turn it is",
			predicate.total("score@owner_of.target", theirs) == 7,
			tostring(predicate.total("score@owner_of.target", theirs)))

		local mine = { targets = { at("a1").id } }
		check("and it follows the card rather than the chair",
			predicate.total("score@owner_of.target", mine) == 3)
	end)
end

-- The trick-winner shape: score whoever owns the card that won, without the
-- rule knowing which seat that is.
function M.test_owner_scope_a_rule_can_pay_the_owner_of_a_card(check)
	with_game(function(name)
		flow.init(name, 3)
		local ctx = { targets = { at("c1").id } }
		actions.execute("stat_gain:score@owner_of.target:5", ctx)
		check("the owner of the chosen card was paid", seat("two").stats.score == 5,
			tostring(seat("two").stats.score))
		check("and the seat that is up was not", seat("one").stats.score == 0,
			tostring(seat("one").stats.score))
	end)
end

-- Two cards, one owner, one seat. A seat counted once per card it owns would
-- pay a player twice for holding two pieces, which is the sort of wrong answer
-- that reads as a rules decision.
function M.test_owner_scope_answers_each_seat_once(check)
	with_game(function(name)
		flow.init(name, 3)
		seat("one").stats.score = 4
		check("two pieces of one seat are still one seat",
			predicate.total("sum:score@owner_of.piece", {}) == 4,
			tostring(predicate.total("sum:score@owner_of.piece", {})))
		check("and both seats together are both scores",
			predicate.total("count:player@owner_of.anyone.piece", {}) == 2,
			tostring(predicate.total("count:player@owner_of.anyone.piece", {})))
	end)
end

-- Written inside the prefix the owner word picks the cards; written before it,
-- it filters the seats that come back. Each word is about what stands beside it.
function M.test_owner_scope_an_owner_word_means_where_it_stands(check)
	with_game(function(name)
		flow.init(name, 3)
		seat("one").stats.score = 3
		seat("two").stats.score = 7

		check("inside, it chooses whose cards are asked",
			predicate.total("score@owner_of.enemy.piece", {}) == 7,
			tostring(predicate.total("score@owner_of.enemy.piece", {})))

		local theirs = { targets = { at("c1").id } }
		check("outside, it keeps only the seats that answer to it",
			predicate.total("score@mine.owner_of.target", theirs) == 0,
			tostring(predicate.total("score@mine.owner_of.target", theirs)))
		local mine = { targets = { at("a1").id } }
		check("so my own target's owner is me", predicate.total("score@mine.owner_of.target", mine) == 3)
	end)
end

-- On its own it is the acting card's seat — the one thing a card could never
-- name about itself, since "mine" is whoever is up rather than whose it is.
function M.test_owner_scope_bare_is_the_acting_cards_own_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		seat("two").stats.score = 7
		local ctx = { card_id = at("c1").id }
		check("the card asks about its own owner",
			predicate.total("score@owner_of", ctx) == 7,
			tostring(predicate.total("score@owner_of", ctx)))
	end)
end

-- A card nobody owns names nobody, rather than falling back to whoever is up.
-- That is the same rule "mine" keeps: unowned is not a quiet synonym for mine.
function M.test_owner_scope_an_unowned_card_names_nobody(check)
	with_game(function(name)
		flow.init(name, 3)
		local loose = zones.add(zones.find("commons"), "piece")
		check("born in a shared zone it is nobody's", predicate.owner_of(loose) == nil)
		local ctx = { targets = { loose.id } }
		check("so it answers with no seat at all",
			predicate.total("count:player@owner_of.target", ctx) == 0,
			tostring(predicate.total("count:player@owner_of.target", ctx)))
	end)
end

return M
