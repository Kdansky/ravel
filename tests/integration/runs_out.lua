-- "runs_out" — what a draw from an empty pile does. The moment, not the remedy:
-- a deckbuilder shuffles its discard back in, Codex does that once a turn, Magic
-- loses, Hearthstone takes fatigue. One block, four lists.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")
local harness = require("harness")

local M = {}

local GAME = [==[{
  "title": "Runs Out",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "health", "label": "Health", "subject": "health@mine.player" },
    { "key": "fatigue", "min": 0, "display": "offscreen", "on": ["player"], "start": 0 },
    { "key": "decked", "min": 0, "display": "offscreen", "on": ["player"], "start": 0 },
    { "key": "reshuffled", "min": 0, "max": 1, "display": "offscreen", "on": ["player"], "start": 0 }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "discard", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "deck", "layout": "stack", "copies": "per_seat",
      "pos": [[0.75, 0.80, 0.85, 0.95], [0.75, 0.05, 0.85, 0.20]],
      "runs_out": { "action": ["move:mine.discard:mine.deck", "shuffle:mine.deck"] } },
    { "key": "capped", "layout": "stack", "copies": "per_seat",
      "pos": [[0.05, 0.40, 0.15, 0.50], [0.05, 0.50, 0.15, 0.60]],
      "runs_out": { "needs": { "req": ["reshuffled@mine.player == 0"] },
        "action": ["stat_gain:reshuffled@mine.player:1", "move:mine.discard:mine.capped", "shuffle:mine.capped"] } },
    { "key": "library", "layout": "stack", "copies": "per_seat",
      "pos": [[0.20, 0.40, 0.30, 0.50], [0.20, 0.50, 0.30, 0.60]],
      "runs_out": { "action": ["stat_gain:decked@mine.player:1"] } },
    { "key": "tired", "layout": "stack", "copies": "per_seat",
      "pos": [[0.35, 0.40, 0.45, 0.50], [0.35, 0.50, 0.45, 0.60]],
      "runs_out": { "action": ["stat_gain:fatigue@mine.player:1", "stat_damage:health@mine.player:sum:fatigue@mine.player"] } }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "health": 30 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "health": 30 } },
    { "key": "coin", "text": "Coin" }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/" .. harness.tmp()
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, harness.tmp())
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key then return e end
	end
end

local function zone(key, s)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == s then return z end
	end
end

function M.test_runs_out_shuffles_the_discard_back_in(check)
	with_game(function(name)
		flow.init(name, 3)
		for _ = 1, 3 do zones.add(zone("discard", "one"), "coin") end
		actions.execute("draw_from:mine.deck:mine.hand:2", {})
		check("two were drawn", #zone("hand", "one").cards == 2, #zone("hand", "one").cards)
		check("out of the discard, by way of the deck", #zone("deck", "one").cards == 1, #zone("deck", "one").cards)
		check("which is empty now", #zone("discard", "one").cards == 0)
	end)
end

-- Codex: once a turn. The second time the gate refuses and the draw comes up short.
function M.test_runs_out_a_refused_needs_draws_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone("discard", "one"), "coin")
		actions.execute("draw_from:mine.capped:mine.hand:1", {})
		check("the first reshuffle draws", #zone("hand", "one").cards == 1)
		zones.add(zone("discard", "one"), "coin")
		actions.execute("draw_from:mine.capped:mine.hand:1", {})
		check("the second does not", #zone("hand", "one").cards == 1, #zone("hand", "one").cards)
		check("and the discard stays put", #zone("discard", "one").cards == 1)
	end)
end

function M.test_runs_out_decking_out(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:mine.library:mine.hand:1", {})
		check("drawing from nothing marks the drawer", seat("one").stats.decked == 1, seat("one").stats.decked)
	end)
end

-- Every card asks on its own: three missing cards are 1 + 2 + 3.
function M.test_runs_out_fatigue_counts_each_card(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("draw_from:mine.tired:mine.hand:3", {})
		check("three blows", seat("one").stats.fatigue == 3, seat("one").stats.fatigue)
		check("each one harder", seat("one").stats.health == 24, seat("one").stats.health)
	end)
end

-- The pile is @self, so "mine" is whose pile it is, not who made the draw happen.
function M.test_runs_out_is_the_piles_owners(check)
	with_game(function(name)
		flow.init(name, 3)
		check("one is up", zones.active_seat() == "one", zones.active_seat())
		actions.execute("draw_from:enemy.library:enemy.hand:1", {})
		check("their deck ran out on them", seat("two").stats.decked == 1, seat("two").stats.decked)
		check("not on whoever made them draw", seat("one").stats.decked == 0, seat("one").stats.decked)
	end)
end

return M
