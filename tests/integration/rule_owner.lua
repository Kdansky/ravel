-- A rule runs as its owner: "mine" is the seat the card belongs to, never whoever
-- is up. It used to be held to the owner moment by moment — a death, an aim, a
-- reaction — and every moment nobody had thought of read the active seat.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")
local cards   = require("cards")
local harness = require("harness")

local M = {}

local GAME = [==[{
  "title": "Rule Owner",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "subject": "score@mine.player" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "table", "layout": "row", "status": "board", "copies": "per_seat",
      "pos": [[0.20, 0.55, 0.80, 0.70], [0.20, 0.30, 0.80, 0.45]] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "score": 0 } },
    { "key": "tithe", "text": "Tithe", "round": { "action": ["stat_gain:score@mine.player:1"] } },
    { "key": "summons", "text": "Summons",
      "play": { "action": ["set_priority:enemy.player", "stat_gain:score@mine.player:1", "clear_priority"] } }
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

local function score(seat)
	for e in entity.each("card") do
		if e.def_key == seat then return e.stats.score end
	end
end

-- The round's tick runs every card on the table on one seat's turn, and the
-- other seat's cards pay their own owner.
function M.test_rule_owner_a_round_pays_the_cards_owner(check)
	with_game(function(name)
		flow.init(name, 3)
		check("one is up", zones.active_seat() == "one", zones.active_seat())
		local theirs = zones.add(zones.find("table", "enemy"), "tithe")
		actions.run(cards.def(theirs).on_round, { card_id = theirs.id, targets = {} })
		check("two's tithe paid two", score("two") == 1, score("two"))
		check("and not one", score("one") == 0, score("one"))
	end)
end

-- Handing priority across mid-list moves who answers, not whose "mine" it is.
function M.test_rule_owner_priority_does_not_move_mine(check)
	with_game(function(name)
		flow.init(name, 3)
		local s = zones.add(zones.find("hand", "mine"), "summons")
		check("it is played", flow.play_card(s.id, {}))
		check("the card's owner scored", score("one") == 1, score("one"))
		check("and the seat holding priority did not", score("two") == 0, score("two"))
	end)
end

return M
