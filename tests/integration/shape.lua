-- What leaves shape.lua is the right type, whatever went in.
--
-- The engine past declaration trusts a field to be what it says — a number, a
-- list, an object — and the guarantee is only as good as shape.lua's knowledge of
-- the fields. So the tables are held to the validator's, and every mistake that
-- once crashed a running game is loaded and played here.

local shape    = require("shape")
local validate = require("validate")
local flow     = require("flow")
local opponent = require("opponent")
local json     = require("json")

local unpack = table.unpack or unpack

local M = {}

-- Fields the validator lists that are not authored and not left to a file to
-- write: the engine derives them, and shape.lua removes them if a file tries.
local function engine_only(name)
	return shape.ENGINE_WRITES[name] or name == "menu_card"
end

function M.test_shape_every_field_the_validator_knows_has_a_type(check)
	for section, fields in pairs(validate.FIELDS) do
		local spec = shape.SPECS[section]
		check("shape.lua describes the section '" .. section .. "'", spec ~= nil and spec.fields ~= nil)
		for name in pairs(spec and spec.fields and fields or {}) do
			check(("%s.%s has a type"):format(section, name),
				spec.fields[name] ~= nil or engine_only(name),
				("validate.FIELDS.%s names '%s', and shape.lua gives it no type"):format(section, name))
		end
	end
	for section, fields in pairs(validate.SHAPES) do
		local spec = shape.SPECS[section]
		for name in pairs(spec and spec.fields and fields or {}) do
			check(("%s.%s has a type"):format(section, name), spec.fields[name] ~= nil)
		end
	end
end

-- The guarantee itself: walk what came out and find nothing of the wrong type.
local function conforms(v, spec)
	if spec.t == "any" then return true end
	if spec.t == "either" then
		for _, s in ipairs(spec) do
			if conforms(v, s) then return true end
		end
		return false
	end
	if spec.t == "string" or spec.t == "number" or spec.t == "boolean" then return type(v) == spec.t end
	if type(v) ~= "table" then return false end
	if spec.t == "list" then
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		if n ~= #v then return false end
		local lo, hi = spec.n, spec.n
		if type(spec.n) == "table" then lo, hi = spec.n[1], spec.n[2] end
		if lo and (#v < lo or #v > hi) then return false end
		for _, x in ipairs(v) do
			if not conforms(x, spec.of) then return false end
		end
		return true
	end
	for k, x in pairs(v) do
		local sub = spec.t == "map" and spec.of or spec.fields[k]
		if type(k) ~= "string" or (sub and not conforms(x, sub)) then return false end
	end
	return true
end

local WRONG = { "x", 3, 0.5, true, { "a" }, { a = 1 }, {} }

local function leaves(t, out)
	for k, v in pairs(t) do
		if type(v) == "table" then leaves(v, out) end
		out[#out + 1] = { t = t, k = k }
	end
end

function M.test_shape_what_comes_out_is_always_the_right_type(check)
	local f = io.open("game/games/splendor.json")
	local text = f:read("*a")
	f:close()
	math.randomseed(5)
	local bad = 0
	for _ = 1, 300 do
		local doc = json.decode(text)
		local all = {}
		leaves(doc, all)
		for _ = 1, 4 do
			local l = all[math.random(#all)]
			l.t[l.k] = WRONG[math.random(#WRONG)]
		end
		if not conforms(shape.clean(doc, {}), shape.FILE) then bad = bad + 1 end
	end
	check("three hundred mangled files all come out conforming", bad == 0, bad .. " did not")
end

local function with_game(text, fn)
	local path = "game/games/tmp_shape.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_shape.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- One game, with a hole where each mistake goes.
local BASE = [[{
  "title": "Shapes",
  "players": [{ "card": "one" }],
  "stats": [ { "key": "gold", "on": ["player"], "start": 5 %s },
             { "key": "hp", "on": ["unit"], "start": 3 } ],
  "tags": { "brave": {} },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.2, 0.8, 0.5, 0.95], "contents": ["zap", "grunt" %s] },
    { "key": "field", "status": "board", "layout": "row", "pos": %s %s }
  ],
  "phases": [ { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] } ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"], "play": { "action": ["move_to:field"] } },
    { "key": "zap", "text": "Zap", "play": %s }
  ],
  "setup": { "place": [ { "card": "one", "zone": "field" } ] }
}]]

local PLAY = '{ "action": ["stat_damage:hp@each.unit:1"] }'

-- Each of these was a crash in a running game, and the validator already knew
-- about most of them: it said so and the game went down anyway.
local MISTAKES = {
	{ "a cost written as a string", { "", "", "[0.2, 0.4, 0.5, 0.55]", "",
		'{ "cost": "gold:2", "action": ["stat_damage:hp@each.unit:1"] }' }, "cost" },
	{ "a zone applying one word rather than a list", { "", "", "[0.2, 0.4, 0.5, 0.55]",
		', "applies": "brave"', PLAY }, "applies" },
	{ "a stat's floor written as text", { ', "min": "0"', "", "[0.2, 0.4, 0.5, 0.55]", "", PLAY }, "min" },
	{ "a stat's ceiling written as an object", { ', "max": { "a": 1 }', "", "[0.2, 0.4, 0.5, 0.55]", "", PLAY }, "max" },
	{ "a target's zones written as one word", { "", "", "[0.2, 0.4, 0.5, 0.55]", "",
		'{ "target": { "zones": "field" }, "action": ["stat_damage:hp@target:1"] }' }, "zones" },
	{ "an action that is not a string", { "", "", "[0.2, 0.4, 0.5, 0.55]", "", '{ "action": [3, "end_phase"] }' }, "entry 1" },
	{ "a rect missing a corner", { "", "", "[0.2, 0.4, 0.5]", "", PLAY }, "pos" },
}

function M.test_shape_old_crashes_load_and_play(check)
	local say = print
	for _, m in ipairs(MISTAKES) do
		local said = {}
		print = function(s) said[#said + 1] = tostring(s) end
		local ok, err = pcall(with_game, BASE:format(unpack(m[2])), function(name)
			flow.init(name, 1)
			for _ = 1, 20 do
				local moves = opponent.legal()
				if #moves == 0 then break end
				moves[1]()
			end
		end)
		print = say
		check(m[1] .. " does not crash the game", ok, tostring(err))
		local named = false
		for _, s in ipairs(said) do
			if s:find(m[3], 1, true) then named = true end
		end
		check(m[1] .. " is reported", named, table.concat(said, "\n"))
	end
end

-- The file handed in is what the author wrote, and a message quoting it must be
-- able to: the copy is cleaned, the original is not.
function M.test_shape_a_bad_value_is_left_out_not_guessed_at(check)
	local pp = {}
	local out = shape.clean({ stats = { { key = "hp", min = "0", max = 5 } } }, pp)
	check("the text is gone", out.stats[1].min == nil)
	check("the number beside it stays", out.stats[1].max == 5)
	check("and it is said", #pp == 1 and pp[1]:find("stat 'hp' min", 1, true) ~= nil, pp[1])
	check("an entry of the wrong type drops out of its list, and the rest stay",
		#shape.clean({ cards = { { key = "a" }, 7, { key = "b" } } }, {}).cards == 2)
	check("a field nobody knows goes through as written, for the validator to name",
		shape.clean({ cards = { { key = "a", colour = "red" } } }, {}).cards[1].colour == "red")
	check("a name the engine derives is removed, not trusted",
		shape.clean({ phases = { { key = "p", zone_list = 5 } } }, {}).phases[1].zone_list == nil)
end

return M
