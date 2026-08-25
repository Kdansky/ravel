-- A stat is a number with a floor and a ceiling, and the whole of that is
-- decided once, when the stat is first attached to a card.
--
-- The point of doing it there is what the rest of the engine gets to *not* do:
-- `e.stats[key]` is the current value everywhere it ever was, and the two
-- bounds sit beside it in tables of their own. Nothing downstream asks which
-- form the game file wrote, and no bound is a stat in its own right — the old
-- `hp_max` convention meant a card carried a number that counting, spending and
-- the tooltip could all reach as readily as `hp` itself.

local entity = require("entity")
local cards = require("cards")
local flow = require("flow")
local actions = require("actions")
local validate = require("validate")
local declaration = require("declaration")

local M = {}

local GAME = [==[{
  "title": "Bounds",
  "stats": [
    { "key": "grit", "min": 0, "max": 9, "tags": ["hidden"] }
  ],
  "computed_tags": {
    "damaged": { "stat": "hp", "less_than_max": true }
  },
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [5, 1], "pos": [0.2, 0.1, 0.9, 0.4] },
    { "key": "hand", "layout": "row", "pos": [0.2, 0.6, 0.9, 0.9] }
  ],
  "phases": [{ "key": "act", "type": "player_input" }],
  "cards": [
    { "key": "plain",   "text": "Plain",   "card_stats": { "hp": 4 } },
    { "key": "capped",  "text": "Capped",  "card_stats": { "hp": { "value": 4, "max": 6 } } },
    { "key": "floored", "text": "Floored", "card_stats": { "hp": { "value": 2, "min": 2, "max": 6 } } },
    { "key": "gritty",  "text": "Gritty",  "card_stats": { "grit": 5 } }
  ],
  "setup": {
    "place": [
      { "card": "plain", "zone": "board", "at": ["a1"] },
      { "card": "capped", "zone": "board", "at": ["b1"] },
      { "card": "floored", "zone": "board", "at": ["c1"] },
      { "card": "gritty", "zone": "board", "at": ["d1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_stats.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_stats.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- Run an action against one card, as its own doing.
local function on(e, str)
	actions.execute(str, { card_id = e.id, targets = {} })
end

function M.test_stats_one_number_is_a_current_value(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("plain")
		check("the number is where every reader already looks", e.stats.hp == 4)
		check("and it has no ceiling", e.stat_max.hp == nil)
		check("nor a floor", e.stat_min.hp == nil)

		on(e, "stat_gain:hp@self:100")
		check("so it grows without limit", e.stats.hp == 104, tostring(e.stats.hp))
		on(e, "stat_damage:hp@self:200")
		check("and goes below nothing, which is what carries an overkill",
			e.stats.hp == -96, tostring(e.stats.hp))
	end)
end

function M.test_stats_a_value_and_a_ceiling(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("capped")
		check("value is the current value", e.stats.hp == 4)
		check("max is the ceiling, beside it rather than in it",
			e.stat_max.hp == 6 and e.stats.hp_max == nil)

		on(e, "stat_gain:hp@self:100")
		check("which is what holds it", e.stats.hp == 6, tostring(e.stats.hp))
		on(e, "stat_damage:hp@self:100")
		check("and with no floor of its own it still falls past nothing",
			e.stats.hp == -94, tostring(e.stats.hp))
	end)
end

function M.test_stats_all_three_bounds_by_name(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("floored")
		check("all three land where they belong",
			e.stat_min.hp == 2 and e.stats.hp == 2 and e.stat_max.hp == 6)

		on(e, "stat_damage:hp@self:100")
		check("and the floor holds", e.stats.hp == 2, tostring(e.stats.hp))
		on(e, "stat_gain:hp@self:100")
		check("as does the ceiling", e.stats.hp == 6, tostring(e.stats.hp))
	end)
end

-- The bound a card leaves out is the one the game already stated once.
function M.test_stats_a_missing_bound_falls_back_to_the_global_rule(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("gritty")
		check("a bare number declares neither bound itself",
			e.stat_max.grit == nil and e.stat_min.grit == nil)

		on(e, "stat_gain:grit@self:100")
		check("but the stats entry's ceiling still holds it", e.stats.grit == 9, tostring(e.stats.grit))
		on(e, "stat_damage:grit@self:100")
		check("and its floor", e.stats.grit == 0, tostring(e.stats.grit))
	end)
end

function M.test_stats_boost_moves_the_ceiling(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("capped")
		on(e, "stat_boost:hp@self:3")
		check("the ceiling rises", e.stat_max.hp == 9)
		check("and the current value stays where it was — a bigger cup is not a full one",
			e.stats.hp == 4)
		on(e, "stat_gain:hp@self:100")
		check("though it can now be filled to the new one", e.stats.hp == 9)

		-- The one case where the current has to come along: it cannot be left
		-- standing above its own maximum, which is exactly what used to happen.
		on(e, "stat_damage:hp@self:0")
		on(e, "stat_boost:hp@self:-6")
		check("lowering it under what is there brings the number down with it",
			e.stat_max.hp == 3 and e.stats.hp == 3,
			("max %s, hp %s"):format(tostring(e.stat_max.hp), tostring(e.stats.hp)))
	end)
end

-- A stat with no ceiling has nothing to boost, and saying so is better than
-- inventing one silently.
function M.test_stats_boost_does_nothing_to_an_unbounded_stat(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("plain")
		on(e, "stat_boost:hp@self:5")
		check("no ceiling appears", e.stat_max.hp == nil)
		check("and the current value is untouched", e.stats.hp == 4)
	end)
end

function M.test_stats_set_is_the_way_past_every_bound(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("floored")
		on(e, "stat_set:hp@self:99")
		check("it writes what it is told", e.stats.hp == 99, tostring(e.stats.hp))
		check("without moving the bounds", e.stat_min.hp == 2 and e.stat_max.hp == 6)
		-- And the next ordinary change puts it back inside them, which is why it
		-- is an authoring tool and not a rule.
		on(e, "stat_gain:hp@self:0")
		check("the next ordinary change pulls it back in", e.stats.hp == 6, tostring(e.stats.hp))
	end)
end

-- "damaged" is the commonest computed tag there is, and it used to be written
-- less_than_stat: hp_max — which only worked while a ceiling was a stat.
function M.test_stats_a_tag_can_read_a_cards_own_ceiling(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("capped")
		local tags = require("tags")
		check("a card below its ceiling is damaged", tags.entity_has(e, "damaged"))
		on(e, "stat_gain:hp@self:2")
		check("and one filled to it is not", tags.entity_has(e, "damaged") == false)
		check("a card with no ceiling can never be damaged",
			tags.entity_has(card("plain"), "damaged") == false)
	end)
end

-- Undo and the network both carry whole entities, so a bound that lived outside
-- one would be lost by the first snapshot.
function M.test_stats_the_bounds_travel_with_the_card(check)
	with_game(function(name)
		flow.init(name, 1)
		local snap = entity.snapshot()
		local e = card("floored")
		on(e, "stat_boost:hp@self:4")
		check("the ceiling moved", e.stat_max.hp == 10)
		entity.restore(snap)
		check("and a restored state has the one it was taken with",
			card("floored").stat_max.hp == 6, tostring(card("floored").stat_max.hp))
	end)
end

-- **A stat says whose number it is, and where they start.**
--
-- Carrying a stat is how a card says it takes part in a number: an action skips
-- a card that has none (predicate.bearers), and an absent stat fails every
-- comparison rather than reading as zero. Both rules are load-bearing, and both
-- used to mean a deck of forty declared the same zero forty times — The Crew
-- had 282 zeros in 407 card_stats entries and Splendor 1,256 in 1,662. Said in
-- the stats section instead, beside the floor and the ceiling of the same
-- number, which is where the rest of what a stat *is* already lives.
local GRANTED = [==[{
  "title": "Granted",
  "stats": [
    { "key": "wear", "min": 0, "max": 9, "tags": ["hidden"], "on": ["tool"], "start": 0 },
    { "key": "heat", "min": 0, "max": 9, "tags": ["hidden"], "on": ["hot"], "start": 3 },
    { "key": "edge", "min": 0, "max": 9, "tags": ["hidden"], "on": ["tool"] }
  ],
  "zones": [
    { "key": "board", "layout": "grid", "grid": [6, 1], "pos": [0.1, 0.3, 0.9, 0.6] }
  ],
  "phases": [{ "key": "act", "type": "player_input" }],
  "cards": [
    { "key": "plain", "text": "Plain" },
    { "key": "hammer", "text": "Hammer", "tags": ["tool"], "card_stats": { "edge": 1 } },
    { "key": "worn", "text": "Worn", "tags": ["tool"], "card_stats": { "wear": 5, "edge": 2 } },
    { "key": "torch", "text": "Torch", "tags": ["tool", "hot"], "card_stats": { "edge": 3 } }
  ],
  "setup": {
    "place": [
      { "card": "plain", "zone": "board", "at": ["a1"] },
      { "card": "hammer", "zone": "board", "at": ["b1"] },
      { "card": "worn", "zone": "board", "at": ["c1"] },
      { "card": "torch", "zone": "board", "at": ["d1"] }
    ]
  }
}]==]

local function with_granted(text, fn)
	local path = "game/games/tmp_granted.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_granted.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

function M.test_stats_a_stat_says_whose_number_it_is(check)
	with_granted(GRANTED, function(name)
		flow.init(name, 3)
		check("a card the stat never named carries nothing", card("plain").stats.wear == nil)
		check("one it named starts where it said", card("hammer").stats.wear == 0)
		check("and the card's own still wins", card("worn").stats.wear == 5,
			tostring(card("worn").stats.wear))
		check("a stat may start anywhere, not only at zero", card("torch").stats.heat == 3,
			tostring(card("torch").stats.heat))
		check("and only on the cards it named", card("hammer").stats.heat == nil)

		-- The whole point of the rule the zeros were standing in for.
		actions.execute("stat_gain:wear@each.board:1", {})
		check("the change reaches every card the stat equipped",
			card("hammer").stats.wear == 1 and card("torch").stats.wear == 1)
		check("and skips the one nothing gave it to", card("plain").stats.wear == nil)
	end)
end

-- A stat that names its cards and says no `start` is one each of them declares:
-- "a creature has hp, and every creature says how much". Nothing is handed out,
-- and forgetting is an authoring error rather than a card quietly absent from
-- an arithmetic that is about it.
function M.test_stats_a_stat_may_require_rather_than_grant(check)
	with_granted(GRANTED, function(name)
		flow.init(name, 3)
		check("each card said its own", card("hammer").stats.edge == 1
			and card("worn").stats.edge == 2 and card("torch").stats.edge == 3)
		check("and nothing was handed out", card("plain").stats.edge == nil)
		check("the file is clean", #validate.check(declaration.parse(name)) == 0)
	end)

	local missing = GRANTED:gsub('"tags": %["tool"%], "card_stats": { "edge": 1 }', '"tags": ["tool"]')
	with_granted(missing, function(name)
		local problems = table.concat(validate.check(declaration.parse(name)), "\n")
		check("a card that forgets is named", problems:find("'hammer' never says") ~= nil, problems)
		check("and only that one", select(2, problems:gsub("never says", "")) == 1, problems)
	end)

	-- Saying where a stat starts without saying whose it is knows nobody.
	local orphan = GRANTED:gsub('"on": %["hot"%], "start": 3', '"start": 3')
	with_granted(orphan, function(name)
		local problems = table.concat(validate.check(declaration.parse(name)), "\n")
		check("a start with nobody to start is refused",
			problems:find("says where it starts but not whose it is") ~= nil, problems)
	end)
end

return M
