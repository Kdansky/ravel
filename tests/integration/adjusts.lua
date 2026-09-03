-- A game's own word for a moment, and the aura that watches for it.
--
-- `stat_damage` is a mechanism and not a meaning. Poison and a sword both take
-- hp, and armour stops one of them; a plane losing altitude is neither. So a
-- game declares the moments it means — "damage", "poison" — and an aura may
-- watch a declared verb and never an engine one.
--
-- That rule is what makes being interfered with something a game opts into. The
-- bookkeeping a combat does with raw stat_damage is unreachable, because nothing
-- is able to name it.

local entity  = require("entity")
local flow    = require("flow")
local zones   = require("zones")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Adjusts",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "hp", "on": ["unit"], "start": 10, "min": 0, "max": 10 },
    { "key": "altitude", "on": ["plane"], "start": 9, "min": 0, "max": 9 },
    { "key": "tally", "on": ["unit"], "start": 0, "min": 0, "max": 99 }
  ],
  "verbs": [
    { "key": "damage", "does": "stat_damage", "tooltip": "Damage — armour stops some of it." },
    { "key": "poison", "does": "stat_damage", "tooltip": "Poison — armour does not stop it." },
    { "key": "mend",   "does": "stat_gain" }
  ],
  "tags": {
    "armoured": {
      "tooltip": "Armour 1 — takes 1 less damage, but not from poison.",
      "adjusts": [{ "key": "armour", "verb": "damage", "stat": "hp", "covers": "self", "by": -1 }]
    },
    "anthem": {
      "adjusts": [{ "key": "anthem", "verb": "damage", "stat": "hp", "covers": "each.unit", "by": -1 }]
    },
    "warded": {
      "adjusts": [{ "key": "ward", "verb": "damage", "stat": "hp", "covers": "self", "by": -2,
        "when": ["tagged:witch@source"] }]
    },
    "blessed": {
      "adjusts": [{ "key": "bless", "verb": "mend", "stat": "hp", "covers": "self", "by": 1 }]
    }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "knight", "text": "Knight", "tags": ["unit", "armoured"] },
    { "key": "saint", "text": "Saint", "tags": ["unit", "armoured", "blessed"] },
    { "key": "shrouded", "text": "Shrouded", "tags": ["unit", "warded"] },
    { "key": "banner", "text": "Banner", "tags": ["unit", "anthem"] },
    { "key": "plane", "text": "Plane", "tags": ["plane"] },
    { "key": "witch", "text": "Witch", "tags": ["unit", "witch"] },
    { "key": "sword", "text": "Sword",
      "play": { "target": { "type": "card", "tags": ["unit"], "count": 1 }, "action": ["damage:hp@target:3"] } },
    { "key": "venom", "text": "Venom",
      "play": { "target": { "type": "card", "tags": ["unit"], "count": 1 }, "action": ["poison:hp@target:3"] } },
    { "key": "salve", "text": "Salve",
      "play": { "target": { "type": "card", "tags": ["unit"], "count": 1 }, "action": ["mend:hp@target:1"] } }
  ],
  "setup": {
    "place": [
      { "card": "grunt", "zone": "field" }, { "card": "knight", "zone": "field" },
      { "card": "saint", "zone": "field" }, { "card": "shrouded", "zone": "field" },
      { "card": "plane", "zone": "field" }, { "card": "witch", "zone": "field" },
      { "card": "sword", "zone": "hand" }, { "card": "venom", "zone": "hand" },
      { "card": "salve", "zone": "hand" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_adjusts.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_adjusts.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function hit(verb, victim, n, source)
	actions.execute(verb .. ":hp@target:" .. n,
		{ card_id = source and find(source).id, targets = { find(victim).id } })
end

-- The whole point, in one test: two moments carried by the same engine verb,
-- and the aura tells them apart because the game named them.
function M.test_adjusts_armour_stops_damage_and_not_poison(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("damage", "knight", 3)
		check("armour takes one off the sword", find("knight").stats.hp == 8,
			tostring(find("knight").stats.hp))
		hit("poison", "knight", 3)
		check("and nothing off the poison", find("knight").stats.hp == 5,
			tostring(find("knight").stats.hp))
		hit("damage", "grunt", 3)
		check("a unit with no armour takes it all", find("grunt").stats.hp == 7,
			tostring(find("grunt").stats.hp))
	end)
end

-- The engine's own verb is unreachable. This is the safety property the word
-- rests on: a combat's internal bookkeeping cannot be intercepted, because
-- nothing is able to name it.
function M.test_adjusts_the_engine_verb_is_not_watchable(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("stat_damage:hp@target:3", { targets = { find("knight").id } })
		check("plain stat_damage is plumbing and lands in full", find("knight").stats.hp == 7,
			tostring(find("knight").stats.hp))
	end)
end

-- An aura names its stat too, so a shield written for hp never touches a plane
-- losing height with the same verb.
function M.test_adjusts_another_stat_is_another_matter(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("damage:altitude@target:3", { targets = { find("plane").id } })
		check("the plane descends by three", find("plane").stats.altitude == 6,
			tostring(find("plane").stats.altitude))
	end)
end

-- It may not change the sign. Three damage reduced by five is none, and never a
-- heal of two.
function M.test_adjusts_may_not_turn_harm_into_help(check)
	with_game(function(name)
		flow.init(name, 3)
		local banner = require("cards").create("banner", zones.find_id("field"))
		hit("damage", "grunt", 1)
		check("the anthem and nothing else leaves it whole", find("grunt").stats.hp == 10,
			tostring(find("grunt").stats.hp))
	end)
end

-- Two auras on one card sum, and the same card may hold one for each verb.
function M.test_adjusts_they_sum_and_they_keep_apart(check)
	with_game(function(name)
		flow.init(name, 3)
		local banner = require("cards").create("banner", zones.find_id("field"))
		hit("damage", "saint", 4)
		check("armour and the anthem take two off between them", find("saint").stats.hp == 8,
			tostring(find("saint").stats.hp))
		hit("mend", "saint", 1)
		check("and the blessing puts two back", find("saint").stats.hp == 10,
			tostring(find("saint").stats.hp))
	end)
end

-- `@source` is who is doing it, which is the one thing an aura needs that no
-- other scope names: @self is the card holding it and @target is the card hit.
function M.test_adjusts_source_says_who_is_doing_it(check)
	with_game(function(name)
		flow.init(name, 3)
		hit("damage", "shrouded", 4, "witch")
		check("the ward answers the witch", find("shrouded").stats.hp == 8,
			tostring(find("shrouded").stats.hp))
		hit("damage", "shrouded", 4, "grunt")
		check("and not the man with the sword", find("shrouded").stats.hp == 4,
			tostring(find("shrouded").stats.hp))
	end)
end

-- An aura reaches other cards, and only while it is on the table.
function M.test_adjusts_an_anthem_covers_a_side_while_it_stands(check)
	with_game(function(name)
		flow.init(name, 3)
		local banner = require("cards").create("banner", zones.find_id("field"))
		hit("damage", "grunt", 3)
		check("the banner protects the whole line", find("grunt").stats.hp == 8,
			tostring(find("grunt").stats.hp))
		zones.destroy_card(banner.id)
		hit("damage", "grunt", 3)
		check("and stops the moment it is gone", find("grunt").stats.hp == 5,
			tostring(find("grunt").stats.hp))
	end)
end

return M
