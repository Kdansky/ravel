-- "comment" — the one field the engine will not read.
--
-- A game file is the product here, and a generated one is still the product:
-- somebody opens `game/games/spellstorm.json` and asks why a line is written the
-- way it is. Until now the answer lived in the generator, where no reader of the
-- file would find it, because JSON has no comments and the validator refuses
-- fields nothing reads — correctly, since that is how a typo is caught.
--
-- So one word is exempt, everywhere, and it is exempt by *name* rather than by
-- being listed among the fields of every section: adding a field to a section
-- must still be a decision. What is tested here is mostly that it is inert.

local declaration = require("declaration")
local validate    = require("validate")
local entity      = require("entity")
local zones       = require("zones")
local flow        = require("flow")

local M = {}

-- A comment on the file, a card, a zone, a phase, a stat, a moment block, a
-- routing entry and a setup placement — every shape a field set is checked
-- against, in one game.
local GAME = [==[{
  "comment": "The file itself may carry one, which is where a game says why it is shaped as it is.",
  "title": "Commentary",
  "players": [{ "card": "one", "comment": "even a seat" }],
  "stats": [{ "key": "score", "min": 0, "max": 9, "on": ["player"], "start": 0,
              "comment": "why this ceiling and not another" }],
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.2, 0.7, 0.95, 0.95],
      "comment": "why the hand is where it is" },
    { "key": "table", "layout": "row", "pos": [0.05, 0.3, 0.95, 0.55] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand",
      "comment": "why this phase loops",
      "next": [{ "then": "act", "comment": "why it leads back to itself" }] }],
  "setup": { "place": [{ "card": "gem", "zone": "hand", "comment": "why it starts here" }] },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "gem", "text": "Gem", "comment": "why this card exists",
      "play": { "phases": ["act"], "action": ["stat_gain:score@mine.player:1"],
                "comment": "why playing it scores" } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_comment.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_comment.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

function M.test_comment_is_legal_wherever_fields_are_named(check)
	with_game(function(name)
		local G = declaration.parse(name)
		local problems = validate.check(G)
		check("a comment on every shape is no problem at all",
			#problems == 0, table.concat(problems, " | "))
	end)
end

-- The point of exempting one word by name: everything else still has to be a
-- field somebody meant. A near-miss is a typo and stays one.
function M.test_a_near_miss_is_still_a_typo(check)
	with_game(function(name)
		local G = declaration.parse(name)
		G.card_defs.gem.comments = "not the word"
		local problems = validate.check(G)
		local found = false
		for _, p in ipairs(problems) do
			if p:find("comments", 1, true) then found = true end
		end
		check("'comments' is not 'comment', and the validator says so", found,
			table.concat(problems, " | "))
	end)
end

function M.test_a_commented_game_plays_the_same(check)
	with_game(function(name)
		flow.init(name, 3)
		local gem
		for e in entity.each("card") do
			if e.def_key == "gem" then gem = e end
		end
		check("the card is where setup put it",
			gem ~= nil and entity.get(gem.zone_id).key == "hand")
		flow.play_card(gem.id, {})
		flow.settle()
		local seat
		for e in entity.each("card") do
			if e.def_key == "one" then seat = e end
		end
		check("and playing it does what its action says, and nothing its comment says",
			seat.stats.score == 1, seat.stats.score)
	end)
end

return M
