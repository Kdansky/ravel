-- What a verb looks like, said on the verb.
--
-- A game declares a blow once, so the look belongs there too: every card that
-- deals one gets it, and no action list has to carry an `effect:` beside it.

local entity = require("entity")
local flow = require("flow")
local actions = require("actions")
local declaration = require("declaration")
local validate = require("validate")

local M = {}

local GAME = [==[{
  "title": "Verb effect",
  "players": [{ "card": "one" }],
  "stats": [{ "key": "hp", "on": ["unit"], "start": 10, "min": 0, "max": 10 },
            { "key": "tally", "on": ["unit"], "start": 0, "min": 0, "max": 99 }],
  "effects": { "dart": { "base": "bolt", "color": [1, 0.3, 0.1] } },
  "verbs": [
    { "key": "damage", "does": "stat_damage", "effect": "dart" },
    { "key": "poison", "does": "stat_damage" }
  ],
  "tags": {
    "shielded": { "adjusts": [{ "key": "shield", "verb": "damage", "stat": "hp", "covers": "self",
      "instead": ["stat_gain:tally@target:1"] }] }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "knight", "text": "Knight", "tags": ["unit", "shielded"] },
    { "key": "dart", "text": "Dart", "play": { "action": ["damage:hp@each.unit:1", "poison:hp@each.unit:1"] } }
  ],
  "setup": { "place": [
    { "card": "grunt", "zone": "field" }, { "card": "knight", "zone": "field" }, { "card": "dart", "zone": "hand" }
  ] }
}]==]

local function with_game(text, fn)
	local path = "game/games/tmp_verb_effect.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_verb_effect.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

function M.test_verb_effect_lands_on_each_victim_from_the_card_that_dealt_it(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local seen = {}
		actions.on_effect = function(effect, ctx, at)
			seen[#seen + 1] = { effect = effect, by = ctx and ctx.card_id, at = at and at.def_key }
		end
		local dart = find("dart")
		flow.play_card(dart.id, {})
		actions.on_effect = nil
		check("one effect per card the verb landed on, and none for the verb without one", #seen == 2, tostring(#seen))
		local at = {}
		for _, s in ipairs(seen) do
			at[s.at] = true
			check("it is the verb's effect, from the card that dealt it", s.effect == "dart" and s.by == dart.id)
		end
		check("on the grunt", at.grunt)
		check("and on the knight, whose shield soaked it: the blow still arrived", at.knight)
		check("the shield did soak it", find("knight").stats.tally == 1 and find("knight").stats.hp == 9,
			tostring(find("knight").stats.hp))
	end)
end

function M.test_verb_effect_is_checked(check)
	local text = GAME:gsub('"effect": "dart"', '"effect": "drat"')
		:gsub('{ "key": "poison", "does": "stat_damage" }', '{ "key": "poison", "does": "stat_damage" }, '
			.. '{ "key": "aim", "does": "target", "effect": "dart" }')
		:gsub('"tags": %["unit", "shielded"%] }', '"tags": ["unit", "shielded"], '
			.. '"play": { "target": { "type": "card", "count": 1, "verb": "aim" }, "action": ["damage:hp@target:1"] } }')
	with_game(text, function(name)
		local said = table.concat(validate.check(declaration.parse(name)), "; ")
		check("an effect nobody defined is named", said:find("the effect 'drat'", 1, true), said)
		check("an aim with an effect is told it lands nowhere", said:find("nowhere for its effect 'dart'", 1, true), said)
	end)
end

return M
