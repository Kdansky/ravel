-- `becomes`: a card starting to wear a tag, which is how a death is heard.
--
-- In most card games death is not a move but a state — a number at nought that the rules then resolve —
-- and the corpse still standing knows which slot it fell in and whose it was. So the engine does not
-- learn what dying is. The game says it once as a computed tag, and a card or a keyword says what
-- happens when a card starts wearing it.

local entity = require("entity")
local flow = require("flow")
local actions = require("actions")
local shape = require("shape")
local harness = require("harness")

local M = {}

local GAME = [==[{
  "title": "Becomes",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "deaths", "min": 0, "max": 40, "on": ["player"], "start": 0 },
    { "key": "rattles", "min": 0, "max": 9999, "on": ["player"], "start": 0 },
    { "key": "hp", "min": 0, "max": 9, "on": ["unit"] }
  ],
  "computed_tags": { "dead": { "needs": { "req": ["hp@self < 1"] } } },
  "tags": {
    "unit": { "becomes": { "dead": { "action": ["stat_gain:deaths@mine.player:1", "destroy:self"] } } },
    "blessed": { "buffs": { "hp": 1 } }
  },
  "zones": [
    { "key": "army", "layout": "row", "status": "board", "copies": "per_seat",
      "pos": [[0.05, 0.55, 0.9, 0.12], [0.05, 0.2, 0.9, 0.12]] },
    { "key": "shrine", "layout": "row", "status": "board", "copies": "per_seat", "applies": ["blessed"],
      "pos": [[0.05, 0.4, 0.9, 0.12], [0.05, 0.05, 0.9, 0.12]] },
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.05, 0.68, 0.6, 0.12], [0.05, 0.82, 0.6, 0.12]] },
    { "key": "discard", "layout": "stack", "status": "grave", "copies": "per_seat",
      "pos": [[0.68, 0.68, 0.1, 0.12], [0.68, 0.82, 0.1, 0.12]] }
  ],
  "phases": [
    { "key": "deal", "type": "automatic",
      "actions": ["set_active_seat:seat_one", "create:mine.army:grunt:1", "create:mine.army:bomber:1",
                  "create:mine.army:knight:1", "create:mine.army:troll:1", "create:mine.army:coward:1",
                  "create:mine.army:sapper:1"],
      "next": [{ "then": "main" }] },
    { "key": "main", "type": "player_input", "zone": "hand", "next": [{ "then": "main" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "grunt", "text": "Grunt", "tags": ["unit", "grunt"], "card_stats": { "hp": 2 } },
    { "key": "bomber", "text": "Bomber", "tags": ["unit"], "card_stats": { "hp": 2 },
      "becomes": { "dead": { "action": ["stat_gain:rattles@mine.player:1"] } } },
    { "key": "knight", "text": "Knight", "tags": ["unit"], "card_stats": { "hp": 2 },
      "becomes": { "dead": { "action": ["move_to:mine.hand"] } } },
    { "key": "troll", "text": "Troll", "tags": ["unit"], "card_stats": { "hp": 2 },
      "becomes": { "dead": { "action": ["stat_gain:hp@self:2"] } } },
    { "key": "sapper", "text": "Sapper", "tags": ["unit"], "card_stats": { "hp": 2 },
      "becomes": { "dead": { "needs": { "theirs": "their_turn@self" },
                             "action": ["theirs? stat_gain:rattles@mine.player:100", "!theirs? stat_gain:rattles@mine.player:1000"] } } },
    { "key": "coward", "text": "Coward", "tags": ["unit"], "card_stats": { "hp": 2 },
      "becomes": { "dead": { "needs": { "req": ["count@mine.army.grunt >= 1"] },
                             "action": ["stat_gain:rattles@mine.player:10"] } } }
  ],
  "setup": { "place": [{ "card": "one", "zone": "army" }, { "card": "two", "zone": "army" }] }
}]==]

local function with_game(fn, text)
	local path = "game/games/" .. harness.tmp("becomes")
	local f = assert(io.open(path, "w"))
	f:write(text or GAME)
	f:close()
	local ok, err = pcall(fn, harness.tmp("becomes"))
	os.remove(path)
	if not ok then error(err, 0) end
end

local function zone(key)
	for z in entity.each("zone") do
		if z.key == key and z.seat == "one" then return z end
	end
end
local function find(key, zkey)
	for _, id in ipairs(zone(zkey).cards) do
		local e = entity.get(id)
		if e.def_key == key then return e end
	end
end
local function seat() return find("one", "army") end
local function hit(key, n)
	actions.run({ "stat_damage:hp@self:" .. n }, { card_id = find(key, "army").id, targets = {} })
	flow.settle()
end

-- Damage writes a number and moves nothing, which is why it was the road a death trigger never heard.
function M.test_becomes_damage_to_nought_is_a_death(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("grunt", 2)
		check("the keyword's death ran", seat().stats.deaths == 1, tostring(seat().stats.deaths))
		check("and carried it off", find("grunt", "discard") ~= nil)
	end)
end

-- The card's own and its keyword's add up: a death rattle is said on top of dying, not instead of it.
function M.test_becomes_a_card_and_its_tag_both_answer(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("bomber", 5)
		check("its own rattle", seat().stats.rattles == 1, tostring(seat().stats.rattles))
		check("and the unit's death", seat().stats.deaths == 1 and find("bomber", "discard") ~= nil)
	end)
end

-- Carried off by its own block, it has answered the death: the keyword's destroy does not follow it.
function M.test_becomes_a_card_that_leaves_replaces_the_death(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("knight", 2)
		check("it went home", find("knight", "hand") ~= nil)
		check("and did not die", seat().stats.deaths == 0, tostring(seat().stats.deaths))
	end)
end

-- Healed by its own block, it is no longer dead — and the next death is a second change, heard again.
function M.test_becomes_a_card_that_heals_replaces_the_death_every_time(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("troll", 2)
		check("it stands", find("troll", "army") ~= nil and find("troll", "army").stats.hp == 2)
		check("nobody died", seat().stats.deaths == 0)
		hit("troll", 2)
		check("it stands again", find("troll", "army") ~= nil and find("troll", "army").stats.hp == 2)
		check("still nobody died", seat().stats.deaths == 0)
	end)
end

-- Nothing is written to the card when a buff runs out, and it dies all the same.
function M.test_becomes_losing_a_buff_is_a_death(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt", "army")
		actions.run({ "move:self:mine.shrine" }, { card_id = g.id, targets = {} })
		actions.run({ "stat_damage:hp@self:2" }, { card_id = g.id, targets = {} })
		flow.settle()
		check("blessed, it stands on the buff", find("grunt", "shrine") ~= nil and seat().stats.deaths == 0)
		actions.run({ "move:self:mine.army" }, { card_id = g.id, targets = {} })
		flow.settle()
		check("out of the shrine it dies", seat().stats.deaths == 1 and find("grunt", "discard") ~= nil)
	end)
end

-- Heard while the corpse still stands, so the rule reads the board it died on — here, its own row.
function M.test_becomes_needs_reads_the_board_the_card_died_on(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("coward", 2)
		check("the grunt beside it was counted", seat().stats.rattles == 10, tostring(seat().stats.rattles))
	end)
end

-- Dying is not something whoever is up chose, so the rattle speaks for the card's own side.
function M.test_becomes_is_heard_as_the_owner(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "set_active_seat:seat_two" }, {})
		hit("bomber", 2)
		check("the bomber's owner gained, on the other seat's turn", seat().stats.rattles == 1,
			tostring(seat().stats.rattles))
	end)
end

-- Which is why a death asks whose turn it is with its own word: "mine" is already the owner.
function M.test_becomes_asks_whose_turn_it_died_on(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("sapper", 2)
		check("on its owner's turn", seat().stats.rattles == 1000, tostring(seat().stats.rattles))
	end)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "set_active_seat:seat_two" }, {})
		hit("sapper", 2)
		check("on the other seat's", seat().stats.rattles == 100, tostring(seat().stats.rattles))
	end)
end

-- A card off the table cannot be dead, whatever its number says.
function M.test_becomes_in_play_scopes_a_state_to_the_table(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt", "army")
		check("in play", require("predicate").meets_all({ "in_play@self" }, { card_id = g.id }))
		actions.run({ "move:self:mine.hand" }, { card_id = g.id, targets = {} })
		check("not in a hand", not require("predicate").meets_all({ "in_play@self" }, { card_id = g.id }))
	end)
end

-- Two deaths in one action list are one settle, and each is heard once.
function M.test_becomes_many_deaths_at_once(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "stat_damage:hp@each.mine.army.unit:5" }, { card_id = seat().id, targets = {} })
		flow.settle()
		-- grunt, bomber, coward and sapper die; knight goes home; troll heals.
		check("four deaths", seat().stats.deaths == 4, tostring(seat().stats.deaths))
		check("the rattles, and the coward's ten with the grunt still standing beside it",
			seat().stats.rattles == 1011, tostring(seat().stats.rattles))
	end)
end

-- A card leaving play is a new card: its printed numbers back, nothing remembered. Without it a unit
-- bounced at nought would come back still dead, and never be heard dying again.
function M.test_becomes_leaving_play_forgets_the_death(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("knight", 2)
		local k = find("knight", "hand")
		check("its health is printed again", k.stats.hp == 2, tostring(k.stats.hp))
		check("and it remembers nothing", k.wore == nil)
		actions.run({ "move:self:mine.army" }, { card_id = k.id, targets = {} })
		hit("knight", 2)
		check("so dying again is heard again", find("knight", "hand") ~= nil and find("knight", "army") == nil)
	end)
end

-- What a card wore travels as state, so it must pass the shape a peer's card is held to.
function M.test_becomes_what_a_card_wore_is_state_a_peer_accepts(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt", "army")
		g.wore = { dead = true }
		check("the shape takes it", shape.check(g, shape.ENTITY.card, "card") == nil,
			tostring(shape.check(g, shape.ENTITY.card, "card")))
	end)
end

function M.test_becomes_a_tag_nothing_wears_is_reported(check)
	local path = "game/games/" .. harness.tmp("becomes_bad")
	local f = assert(io.open(path, "w"))
	f:write((GAME:gsub('"becomes": { "dead": { "action": %["stat_gain:rattles', '"becomes": { "ded": { "action": ["stat_gain:rattles', 1)))
	f:close()
	local ok, G = pcall(require("declaration").parse, harness.tmp("becomes_bad"))
	os.remove(path)
	if not ok then error(G, 2) end
	local said = table.concat(require("validate").check(G), "; ")
	check("it names the tag and the likely one", said:find("becomes 'ded': listens for a tag nothing wears", 1, true)
		and said:find("dead", 1, true), said)
end

return M
