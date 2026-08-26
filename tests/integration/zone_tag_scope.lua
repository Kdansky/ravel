-- "@<zone>.<tag>" — the cards in one place that are also one kind.
--
-- A target spec could always say this: "tags" beside "zones" in the same block.
-- A scope could not, so the same question had two spellings and only one of them
-- worked in a condition, a cost or an action. What it buys is the search a bare
-- tag refuses to do — a bare tag means the board, on purpose, so that most rules
-- cannot read a hand they are not allowed to see. Naming the hand is the way to
-- say you mean it.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local declaration = require("declaration")

local M = {}

local GAME = [==[{
  "title": "Zone Tag Scope",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "subject": "score@mine.player" }],
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.05, 0.05, 0.9, 0.3] },
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.4, 0.9, 0.2], [0.05, 0.62, 0.9, 0.2]] },
    { "key": "vault", "layout": "stack", "pos": [0.05, 0.7, 0.2, 0.25] }
  ],
  "phases": [
    { "key": "deal", "type": "automatic",
      "actions": ["set_active_seat:seat_one", "fill:mine.hand:ruby:1", "fill:mine.hand:opal:1",
                  "fill:mine.hand:brick:1",
                  "set_active_seat:seat_two", "fill:mine.hand:opal:1",
                  "set_active_seat:seat_one"],
      "next": [{ "then": "act" }] },
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "score": 0 } },
    { "key": "ruby", "text": "Ruby", "tags": ["thing", "gem", "red"], "card_stats": { "value": 3 } },
    { "key": "opal", "text": "Opal", "tags": ["thing", "gem"], "card_stats": { "value": 1 } },
    { "key": "brick", "text": "Brick", "tags": ["thing", "junk"], "card_stats": { "value": 0 } }
  ],
  "setup": {
    "place": [
      { "card": "ruby", "zone": "board", "at": ["a1"] },
      { "card": "brick", "zone": "board", "at": ["b1"] },
      { "card": "ruby", "zone": "vault" },
      { "card": "ruby", "zone": "vault" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_zone_tag_scope.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_zone_tag_scope.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function total(s) return predicate.total(s, {}) end

function M.test_zone_tag_scope_narrows_a_zone_to_one_kind(check)
	with_game(function(name)
		flow.init(name, 3)
		check("a zone on its own is everything in it", total("count:thing@mine.hand") == 3,
			tostring(total("count:thing@mine.hand")))
		check("and the tag narrows it", total("count:gem@mine.hand") == 2,
			tostring(total("count:gem@mine.hand")))
		check("a measure reads the narrowed set, not the zone",
			total("sum:value@mine.hand.gem") == 4, tostring(total("sum:value@mine.hand.gem")))
		check("the same tag in another place answers for that place",
			total("count:gem@vault") == 2 and total("count:gem@enemy.hand") == 1,
			total("count:gem@vault") .. " / " .. total("count:gem@enemy.hand"))
	end)
end

-- The point of it: a bare tag means the board and nothing else, which is what
-- stops most rules reading a hand. Naming the zone is how a rule says it means to.
function M.test_zone_tag_scope_reaches_where_a_bare_tag_will_not(check)
	with_game(function(name)
		flow.init(name, 3)
		check("a bare tag sees the board alone", total("count:gem") == 1,
			tostring(total("count:gem")))
		check("naming a hand reaches into it", total("count:gem@mine.hand") == 2)
		check("and an opponent's, which no bare tag ever could",
			total("count:gem@enemy.hand") == 1)
	end)
end

-- The owner word still sits beside what it is about, so all three narrowings
-- read left to right: whose, where, which.
function M.test_zone_tag_scope_stacks_with_the_owner_word(check)
	with_game(function(name)
		flow.init(name, 3)
		check("mine, in hand, and a gem", total("count:gem@mine.hand") == 2)
		check("theirs, in hand, and a gem", total("count:gem@enemy.hand") == 1)
		check("either hand, and a gem", total("count:gem@anyone.hand") == 3,
			tostring(total("count:gem@anyone.hand")))
		check("and a second tag narrows again where a card wears both",
			total("count:red@mine.hand") == 1, tostring(total("count:red@mine.hand")))
	end)
end

-- A place that is not there answers nothing. Falling back to the tag alone would
-- turn a typo into a wider search than the one that was asked for, silently.
function M.test_zone_tag_scope_a_missing_zone_answers_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		check("no zone, no cards", total("count:gem@cellar.gem") == 0)
		check("and it does not fall back to the tag", total("count:gem@cellar.gem") ~= total("count:gem"))
	end)
end

-- Actions take it as readily as measures do: it is one scope grammar, not two.
function M.test_zone_tag_scope_works_where_an_action_names_a_scope(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "destroy:mine.hand.gem" }, {})
		check("the gems went", total("count:gem@mine.hand") == 0,
			tostring(total("count:gem@mine.hand")))
		check("and the brick stayed", total("count:junk@mine.hand") == 1)
		check("as did the gems everywhere else",
			total("count:gem@enemy.hand") == 1 and total("count:gem@vault") == 2)
	end)
end

return M
