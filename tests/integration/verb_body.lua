-- A game's own action: a declared verb with a body, performed by name.
--
-- `param1`, `param2` … are the call's arguments in order. The body runs as the caller, and every stat change its
-- engine verbs make is the verb's own, so an aura watching the verb adjusts what is inside it.

local entity  = require("entity")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Verb body",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "hp", "on": ["unit"], "start": 10, "min": 0, "max": 10 },
    { "key": "tally", "on": ["unit"], "start": 0, "min": 0, "max": 99 }
  ],
  "verbs": [
    { "key": "damage", "does": "stat_damage" },
    { "key": "burn", "action": ["stat_damage:hp@param1:param2", "stat_gain:tally@self:1"],
      "tooltip": "Burn — the first argument is who, the second how much." },
    { "key": "scorch", "action": ["damage:hp@param1:param2"] },
    { "key": "twice", "action": ["param1", "param1"] }
  ],
  "tags": {
    "fireproof": { "adjusts": [{ "key": "fireproof", "verb": "burn", "stat": "hp", "covers": "self", "by": -1 }] },
    "armoured": { "adjusts": [{ "key": "armour", "verb": "damage", "stat": "hp", "covers": "self", "by": -2 }] }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "mage", "text": "Mage", "tags": ["unit"] },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "salamander", "text": "Salamander", "tags": ["unit", "fireproof"] },
    { "key": "knight", "text": "Knight", "tags": ["unit", "armoured"] },
    { "key": "torch", "text": "Torch",
      "play": { "target": { "type": "card", "tags": ["unit"], "count": 1 }, "action": ["burn:target:3"] } }
  ],
  "setup": { "place": [
    { "card": "mage", "zone": "field" }, { "card": "grunt", "zone": "field" },
    { "card": "salamander", "zone": "field" }, { "card": "knight", "zone": "field" },
    { "card": "torch", "zone": "hand" }
  ] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_verb_body.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(function() flow.init("tmp_verb_body.json", 3); fn() end)
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function as(caller, str, victim)
	actions.execute(str, { card_id = find(caller).id, targets = { find(victim).id } })
end

function M.test_verb_body_arguments_fill_in_by_position_and_self_is_the_caller(check)
	with_game(function()
		as("mage", "burn:target:3", "grunt")
		check("the grunt takes three", find("grunt").stats.hp == 7, tostring(find("grunt").stats.hp))
		check("and @self is the mage that burned it", find("mage").stats.tally == 1, tostring(find("mage").stats.tally))
	end)
end

function M.test_verb_body_an_aura_watching_the_verb_adjusts_its_engine_change(check)
	with_game(function()
		as("mage", "burn:target:3", "salamander")
		check("fireproof takes one off the burn", find("salamander").stats.hp == 8, tostring(find("salamander").stats.hp))
		actions.execute("stat_damage:hp@target:3", { targets = { find("salamander").id } })
		check("and nothing off plain stat_damage", find("salamander").stats.hp == 5, tostring(find("salamander").stats.hp))
	end)
end

-- A declared verb in the body keeps its name, so armour watching `damage` sees a scorch, and fireproof — watching
-- burn — is never asked.
function M.test_verb_body_a_declared_verb_inside_keeps_its_own_name(check)
	with_game(function()
		as("mage", "scorch:target:3", "knight")
		check("armour answers the damage inside the scorch", find("knight").stats.hp == 9, tostring(find("knight").stats.hp))
	end)
end

function M.test_verb_body_the_last_argument_takes_the_rest(check)
	with_game(function()
		as("mage", "twice:stat_gain:tally@self:2", "grunt")
		check("a whole action, colons and all, run twice", find("mage").stats.tally == 4, tostring(find("mage").stats.tally))
	end)
end

function M.test_verb_body_too_few_arguments_does_nothing(check)
	with_game(function()
		as("mage", "burn:target", "grunt")
		check("the grunt is untouched", find("grunt").stats.hp == 10, tostring(find("grunt").stats.hp))
		check("and so is the mage", find("mage").stats.tally == 0, tostring(find("mage").stats.tally))
	end)
end

function M.test_verb_body_a_played_card_performs_it(check)
	with_game(function()
		check("the torch plays", flow.play_card(find("torch").id, { find("salamander").id }))
		check("and the burn lands, less the fireproofing", find("salamander").stats.hp == 8,
			tostring(find("salamander").stats.hp))
	end)
end

return M
