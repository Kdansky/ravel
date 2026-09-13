-- reset:<scope>[:<stat>] — put the numbers back to what the card is printed with.
--
-- Codex is the customer and eighteen copies of it: a hero comes back from the
-- command zone, and its summon spelled out six stat_sets restoring values that
-- sit in its own card_stats three lines above. Saying it twice is how a new hero
-- number becomes eighteen edits, and how two of them come to disagree.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Reset",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "hp", "label": "Life", "min": 0, "max": 9, "on": ["unit"], "tags": ["hidden"] },
    { "key": "atk", "label": "Attack", "min": 0, "max": 9, "on": ["unit"], "tags": ["hidden"] },
    { "key": "armor", "min": 0, "max": 9, "on": ["unit"], "start": 0, "tags": ["hidden"] },
    { "key": "score", "label": "Score", "subject": "score@mine.player", "min": 0, "max": 9, "on": ["player"], "start": 0 }
  ],
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [3, 1], "status": "board",
      "pos": [0.05, 0.1, 0.9, 0.3] },
    { "key": "hand", "layout": "row", "copies": "per_seat", "pos": [[0.05, 0.5, 0.7, 0.2]] }
  ],
  "phases": [{ "key": "turn", "type": "player_input", "zone": "hand" }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "ogre", "text": "Ogre", "tags": ["unit"],
      "card_stats": { "atk": 3, "hp": { "value": 4, "max": 4 } } },
    { "key": "wisp", "text": "Wisp", "tags": ["unit"], "card_stats": { "atk": 1, "hp": 1 } }
  ],
  "setup": {
    "place": [{ "card": "one", "zone": "board", "at": ["c1"] },
      { "card": "ogre", "zone": "board", "at": ["a1"] },
      { "card": "wisp", "zone": "board", "at": ["b1"] }]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_reset.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_reset.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

-- Everything the template declares, in one word.
function M.test_reset_puts_every_printed_number_back(check)
	with_game(function(name)
		flow.init(name, 3)
		local o = card("ogre")
		actions.run({ "stat_damage:hp@self:3", "stat_gain:atk@self:2", "stat_gain:armor@self:4" },
			{ card_id = o.id, targets = {} })
		check("the numbers moved", o.stats.hp == 1 and o.stats.atk == 5 and o.stats.armor == 4,
			o.stats.hp .. "/" .. o.stats.atk .. "/" .. o.stats.armor)
		actions.run({ "reset:self" }, { card_id = o.id, targets = {} })
		check("life is printed again", o.stats.hp == 4, tostring(o.stats.hp))
		check("attack too", o.stats.atk == 3, tostring(o.stats.atk))
		check("and a stat the card never wrote, restored from the stat's own start",
			o.stats.armor == 0, tostring(o.stats.armor))
	end)
end

-- One number by name, because a rule that heals is not a rule that un-buffs.
function M.test_reset_may_name_one_stat(check)
	with_game(function(name)
		flow.init(name, 3)
		local o = card("ogre")
		actions.run({ "stat_damage:hp@self:3", "stat_gain:atk@self:2" },
			{ card_id = o.id, targets = {} })
		actions.run({ "reset:self:hp" }, { card_id = o.id, targets = {} })
		check("the named one is back", o.stats.hp == 4, tostring(o.stats.hp))
		check("and the others are left where the game put them", o.stats.atk == 5,
			tostring(o.stats.atk))
	end)
end

-- The ceiling is printed on the card too, so a raised one comes back down.
function M.test_reset_brings_the_ceiling_back_with_the_value(check)
	with_game(function(name)
		flow.init(name, 3)
		local o = card("ogre")
		actions.run({ "stat_boost:hp@self:3" }, { card_id = o.id, targets = {} })
		actions.run({ "stat_gain:hp@self:9" }, { card_id = o.id, targets = {} })
		check("it grew past its printed maximum", o.stats.hp == 7, tostring(o.stats.hp))
		actions.run({ "reset:self" }, { card_id = o.id, targets = {} })
		check("the value is printed again", o.stats.hp == 4, tostring(o.stats.hp))
		actions.run({ "stat_gain:hp@self:9" }, { card_id = o.id, targets = {} })
		check("and the ceiling is the printed one, so it cannot grow past it again",
			o.stats.hp == 4, tostring(o.stats.hp))
	end)
end

-- It is a scope like any other, so it reaches a pool and not only the asker.
function M.test_reset_takes_a_pool(check)
	with_game(function(name)
		flow.init(name, 3)
		local o, w = card("ogre"), card("wisp")
		actions.run({ "stat_damage:hp@each.unit:1" }, { card_id = o.id, targets = {} })
		check("both were hurt", o.stats.hp == 3 and w.stats.hp == 0,
			o.stats.hp .. "/" .. w.stats.hp)
		actions.run({ "reset:each.board.unit" }, { card_id = o.id, targets = {} })
		check("both are printed again", o.stats.hp == 4 and w.stats.hp == 1,
			o.stats.hp .. "/" .. w.stats.hp)
	end)
end

-- A seat is a card, and its numbers are printed the same way.
function M.test_reset_reaches_a_seat_card(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "stat_gain:score@mine.player:5" }, {})
		local seat = card("one")
		check("the score moved", seat.stats.score == 5, tostring(seat.stats.score))
		actions.run({ "reset:mine.player" }, {})
		check("and comes back to what the seat is printed with", seat.stats.score == 0,
			tostring(seat.stats.score))
	end)
end

return M
