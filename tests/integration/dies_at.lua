-- `dies_at`: a stat that says its card dies at a number. The game says what kills; the engine says
-- when — at rest, in play, everything that fell at once together — and kills as `destroy` does.

local entity = require("entity")
local flow = require("flow")
local actions = require("actions")
local harness = require("harness")

local M = {}

local GAME = [==[{
  "title": "Dies at",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "rattles", "min": 0, "max": 99, "on": ["player"], "start": 0 },
    { "key": "hp", "min": 0, "max": 9, "on": ["unit"], "dies_at": 0 },
    { "key": "life", "min": 0, "max": 9, "on": ["hero"], "dies_at": 0 },
    { "key": "atk", "min": 0, "max": 9, "on": ["unit"], "start": 1 }
  ],
  "computed_tags": { "hurt": { "needs": { "req": ["hp@self < 1"] } } },
  "tags": {
    "unit": { "leaves": { "into": "discard", "action": ["stat_gain:rattles@mine.player:1"] } },
    "hero": { "grave": "command" },
    "blessed": { "buffs": { "hp": 1 } }
  },
  "zones": [
    { "key": "army", "layout": "row", "status": "board", "copies": "per_seat",
      "pos": [[0.05, 0.55, 0.9, 0.12], [0.05, 0.2, 0.9, 0.12]] },
    { "key": "shrine", "layout": "row", "status": "board", "copies": "per_seat", "applies": ["blessed"],
      "pos": [[0.05, 0.4, 0.9, 0.12], [0.05, 0.05, 0.9, 0.12]] },
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.05, 0.68, 0.6, 0.12], [0.05, 0.82, 0.6, 0.12]] },
    { "key": "command", "layout": "row", "copies": "per_seat",
      "pos": [[0.8, 0.55, 0.1, 0.12], [0.8, 0.2, 0.1, 0.12]] },
    { "key": "discard", "layout": "stack", "status": "grave", "copies": "per_seat",
      "pos": [[0.68, 0.68, 0.1, 0.12], [0.68, 0.82, 0.1, 0.12]] }
  ],
  "phases": [
    { "key": "deal", "type": "automatic",
      "actions": ["set_active_seat:seat_one", "create:mine.army:grunt:2", "create:mine.army:troll:1",
                  "create:mine.army:champion:1", "create:mine.hand:grunt:1", "create:mine.shrine:grunt:1"],
      "next": [{ "then": "main" }] },
    { "key": "main", "type": "player_input", "zone": "hand", "next": [{ "then": "main" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"], "card_stats": { "hp": 1 } },
    { "key": "troll", "text": "Troll", "tags": ["unit"], "card_stats": { "hp": 2 },
      "becomes": { "hurt": { "action": ["stat_gain:hp@self:2"] } } },
    { "key": "champion", "text": "Champion", "tags": ["hero"], "card_stats": { "life": 3 } }
  ],
  "setup": { "place": [{ "card": "one", "zone": "army" }, { "card": "two", "zone": "army" }] }
}]==]

local function with_game(fn)
	local path = "game/games/" .. harness.tmp("dies_at")
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, harness.tmp("dies_at"))
	os.remove(path)
	if not ok then error(err, 0) end
end

local function cards_in(zkey, key)
	local out = {}
	for z in entity.each("zone") do
		if z.key == zkey and z.seat == "one" then
			for _, id in ipairs(z.cards) do
				local e = entity.get(id)
				if not key or e.def_key == key then out[#out + 1] = e end
			end
		end
	end
	return out
end
local function seat() return cards_in("army", "one")[1] end
local function run(list, card)
	actions.run(list, { card_id = card and card.id, targets = {} })
	flow.settle()
end

function M.test_dies_at_a_card_at_nought_dies_into_its_grave(check)
	with_game(function(name)
		flow.init(name, 3)
		run({ "stat_damage:hp@self:1" }, cards_in("army", "grunt")[1])
		check("one grunt is left standing", #cards_in("army", "grunt") == 1, tostring(#cards_in("army", "grunt")))
		check("the other is in the discard", #cards_in("discard", "grunt") == 1)
		check("and its leaves was heard", seat().stats.rattles == 1, tostring(seat().stats.rattles))
	end)
end

-- Everything due is gathered before the first moves, so a sweep kills every card it brought to nought.
function M.test_dies_at_cards_that_fall_together_die_together(check)
	with_game(function(name)
		flow.init(name, 3)
		run({ "stat_damage:hp@each.mine.army.unit:1" })
		check("both grunts died", #cards_in("discard", "grunt") == 2, tostring(#cards_in("discard", "grunt")))
		check("the troll is still standing on one", #cards_in("army", "troll") == 1)
	end)
end

function M.test_dies_at_only_in_play(check)
	with_game(function(name)
		flow.init(name, 3)
		local held = cards_in("hand", "grunt")[1]
		run({ "stat_damage:hp@self:1" }, held)
		check("a card in hand at nought stays in hand", cards_in("hand", "grunt")[1] == held)
	end)
end

-- Nothing is written when a buff stops applying, and it kills all the same.
function M.test_dies_at_losing_a_buff_is_a_death(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = cards_in("shrine", "grunt")[1]
		run({ "stat_damage:hp@self:1" }, g)
		check("borrowed health holds it up", cards_in("shrine", "grunt")[1] == g)
		run({ "move:self:mine.army" }, g)
		check("out of the shrine it dies", cards_in("discard", "grunt")[1] == g)
	end)
end

-- `becomes` is heard first, so a block that heals the card has answered the death.
function M.test_dies_at_waits_for_becomes(check)
	with_game(function(name)
		flow.init(name, 3)
		local t = cards_in("army", "troll")[1]
		run({ "stat_damage:hp@self:2" }, t)
		check("the troll got up again", cards_in("army", "troll")[1] == t and t.stats.hp == 2, tostring(t.stats.hp))
	end)
end

-- Each kind of card dies of its own stat, to its own grave.
function M.test_dies_at_a_second_stat_kills_to_its_own_grave(check)
	with_game(function(name)
		flow.init(name, 3)
		run({ "stat_damage:life@self:3" }, cards_in("army", "champion")[1])
		check("the hero went back to command", #cards_in("command", "champion") == 1)
	end)
end

-- A stat without the word is only a number.
function M.test_dies_at_a_stat_without_it_kills_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = cards_in("army", "grunt")[1]
		run({ "stat_damage:atk@self:1" }, g)
		check("no attack is not death", cards_in("army", "grunt")[1] == g)
	end)
end

return M
