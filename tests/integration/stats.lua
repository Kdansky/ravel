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
    { "key": "board", "type": "grid", "grid": [5, 1], "tags": ["activate"], "pos": [0.2, 0.1, 0.9, 0.4] },
    { "key": "hand", "type": "hand", "pos": [0.2, 0.6, 0.9, 0.9] }
  ],
  "phases": [{ "key": "act", "type": "player_input" }],
  "cards": [
    { "key": "plain",   "text": "Plain",   "card_stats": { "hp": 4 } },
    { "key": "capped",  "text": "Capped",  "card_stats": { "hp": [4, 6] } },
    { "key": "floored", "text": "Floored", "card_stats": { "hp": [2, 4, 6] } },
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

function M.test_stats_a_pair_is_current_and_ceiling(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("capped")
		check("the first number is the current value", e.stats.hp == 4)
		check("the second is the ceiling, beside it rather than in it",
			e.stat_max.hp == 6 and e.stats.hp_max == nil)

		on(e, "stat_gain:hp@self:100")
		check("which is what holds it", e.stats.hp == 6, tostring(e.stats.hp))
		on(e, "stat_damage:hp@self:100")
		check("and with no floor of its own it still falls past nothing",
			e.stats.hp == -94, tostring(e.stats.hp))
	end)
end

function M.test_stats_a_triplet_is_floor_current_and_ceiling(check)
	with_game(function(name)
		flow.init(name, 1)
		local e = card("floored")
		check("all three land where they belong",
			e.stat_min.hp == 2 and e.stats.hp == 4 and e.stat_max.hp == 6)

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

-- **A tag may carry the numbers every card wearing it starts with.**
--
-- Carrying a stat is how a card says it takes part in a number: an action skips
-- a card that has none (predicate.bearers), and an absent stat fails every
-- comparison rather than reading as zero. Both rules are load-bearing and
-- neither is worth writing out forty times — The Crew had 282 zeros in 407
-- card_stats entries and Splendor 1256 in 1662, all of them one sentence
-- repeated. The tag says it once.
local GRANTED = [==[{
  "title": "Granted",
  "stats": [
    { "key": "wear", "min": 0, "max": 9, "tags": ["hidden"] },
    { "key": "heat", "min": 0, "max": 9, "tags": ["hidden"] }
  ],
  "zones": [
    { "key": "board", "type": "grid", "grid": [6, 1], "pos": [0.1, 0.3, 0.9, 0.6] }
  ],
  "phases": [{ "key": "act", "type": "player_input" }],
  "tags": {
    "tool":  { "card_stats": { "wear": 0, "heat": 0 } },
    "spare": { "card_stats": { "wear": 0 } },
    "hot":   { "card_stats": { "heat": 3 } }
  },
  "cards": [
    { "key": "plain", "text": "Plain" },
    { "key": "hammer", "text": "Hammer", "tags": ["tool"] },
    { "key": "worn", "text": "Worn", "tags": ["tool"], "card_stats": { "wear": 5 } },
    { "key": "both", "text": "Both", "tags": ["tool", "spare"] },
    { "key": "torch", "text": "Torch", "tags": ["spare", "hot"] }
  ],
  "setup": {
    "place": [
      { "card": "plain", "zone": "board", "at": ["a1"] },
      { "card": "hammer", "zone": "board", "at": ["b1"] },
      { "card": "worn", "zone": "board", "at": ["c1"] },
      { "card": "both", "zone": "board", "at": ["d1"] },
      { "card": "torch", "zone": "board", "at": ["e1"] }
    ]
  }
}]==]

local function with_granted(fn)
	local path = "game/games/tmp_granted.json"
	local f = assert(io.open(path, "w"))
	f:write(GRANTED)
	f:close()
	local ok, err = pcall(fn, "tmp_granted.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

function M.test_stats_a_tag_may_carry_the_numbers_it_grants(check)
	with_granted(function(name)
		flow.init(name, 3)
		local function card(key)
			for e in entity.each("card") do
				if e.def_key == key and e.zone_id then return e end
			end
		end

		check("a card without the tag carries nothing", card("plain").stats.wear == nil)
		check("a card with it starts where the tag says",
			card("hammer").stats.wear == 0 and card("hammer").stats.heat == 0)
		check("and its own always wins", card("worn").stats.wear == 5,
			tostring(card("worn").stats.wear))
		check("two tags agreeing is fine", card("both").stats.wear == 0)
		check("and a tag may start a stat anywhere, not only at zero",
			card("torch").stats.heat == 3, tostring(card("torch").stats.heat))

		-- The whole point of the rule the zeros were standing in for.
		actions.execute("stat_gain:wear@each.board:1", {})
		check("the change reaches the card the tag equipped", card("hammer").stats.wear == 1)
		check("and skips the one nothing gave the stat to", card("plain").stats.wear == nil)

		check("and every card the tag equipped moved together",
			card("both").stats.wear == 1 and card("torch").stats.wear == 1)
	end)
end

-- Two tags that disagree hand over nothing at all, exactly as an ambiguous home
-- zone does: the stat is absent, which fails closed, and the parse says which
-- two to look at rather than picking whichever came first in the file.
function M.test_stats_two_tags_disagreeing_grant_nothing(check)
	local path = "game/games/tmp_granted_clash.json"
	local text = GRANTED:gsub('"hot":   { "card_stats": { "heat": 3 } }',
		'"hot":   { "card_stats": { "heat": 3 } },\n    "cold":  { "card_stats": { "heat": 1 } }')
		:gsub('"tags": %["spare", "hot"%]', '"tags": ["hot", "cold"]')
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(function()
		local G = require("declaration").parse("tmp_granted_clash.json")
		local said = table.concat(G.parse_problems or {}, "\n")
		check("the parse says which two disagree",
			said:find("start 'heat' differently") ~= nil, said)
		flow.init("tmp_granted_clash.json", 3)
		local torch
		for e in entity.each("card") do if e.def_key == "torch" then torch = e end end
		check("and the stat is absent rather than one of the two",
			torch.stats.heat == nil, tostring(torch.stats.heat))
	end)
	os.remove(path)
	if not ok then error(err, 0) end
end

return M
