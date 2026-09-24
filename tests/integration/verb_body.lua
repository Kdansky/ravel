-- A game's own action: a declared verb with a body, performed by name.
--
-- `param1`, `param2` … are the call's arguments in order. The body runs as the caller, and every stat change its
-- engine verbs make is the verb's own, so an aura watching the verb adjusts what is inside it.

local entity  = require("entity")
local flow    = require("flow")
local actions = require("actions")
local declaration = require("declaration")
local validate = require("validate")

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
    { "key": "twice", "action": ["param1", "param1"] },
    { "key": "finish", "needs": { "low": "hp@param1 < 5" },
      "action": ["low? stat_damage:hp@param1:9", "!low? stat_gain:tally@self:1", "stat_gain:tally@self:1"] }
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

-- A gate may ask about an argument, and the lines behind it run or not as they would on a card.
function M.test_verb_body_a_gate_reads_the_argument(check)
	with_game(function()
		as("mage", "finish:target", "grunt")
		check("a grunt at ten is not low, so the other branch", find("grunt").stats.hp == 10 and find("mage").stats.tally == 2,
			find("grunt").stats.hp .. "/" .. find("mage").stats.tally)
		find("grunt").stats.hp = 4
		as("mage", "finish:target", "grunt")
		check("at four it is, and the line behind the gate lands", find("grunt").stats.hp == 0 and find("mage").stats.tally == 3,
			find("grunt").stats.hp .. "/" .. find("mage").stats.tally)
	end)
end

-- The caller asked a gate of the same name already; the body asks its own.
function M.test_verb_body_a_callers_gate_is_not_the_bodys(check)
	with_game(function()
		actions.execute("finish:target", { card_id = find("mage").id, targets = { find("grunt").id }, gated = { low = true } })
		check("the grunt at ten is spared", find("grunt").stats.hp == 10, tostring(find("grunt").stats.hp))
	end)
end

-- The fixture's verbs are performed by the tests rather than by its cards, so that is the one thing said of them.
function M.test_verb_body_a_gated_body_passes_the_validator(check)
	with_game(function()
		local problems = {}
		for _, s in ipairs(validate.check(declaration.parse("tmp_verb_body.json"))) do
			if s:find("finish", 1, true) and not s:find("no action performs it", 1, true) then problems[#problems + 1] = s end
		end
		check("nothing said of finish's gate", #problems == 0, table.concat(problems, "; "))
	end)
end

-- A req would be asked once the caller's list is already under way, so a verb is refused one and told why.
function M.test_verb_body_a_req_is_refused(check)
	local path = "game/games/tmp_verb_req.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
		"title": "Verb Req",
		"stats": [{ "key": "hp", "on": ["unit"], "start": 10 }],
		"verbs": [{ "key": "maul", "needs": { "req": "hp@param1 < 5" }, "action": ["stat_damage:hp@param1:1"] }],
		"zones": [{ "key": "hand", "layout": "row" }],
		"phases": [{ "key": "turn", "type": "player_input", "zone": "hand" }],
		"cards": [{ "key": "claw", "text": "Claw", "play": { "action": ["maul:self"] } }]
	}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_verb_req.json")
	os.remove(path)
	if not ok then error(G, 2) end
	local said = table.concat(validate.check(G), "; ")
	check("named, with the reason", said:find("verb 'maul': needs takes no \"req\" here — a verb takes gates only", 1, true), said)
end

return M
