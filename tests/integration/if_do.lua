-- An if inside an action list: { "if": [conditions], "do": [actions] }, in
-- place, between the lines it sits among.
--
-- Magic Dart prints "Gain 1 mana. If you have Initiative, deal 1 damage." as one
-- sentence, and until this it was two abilities both captioned "Resolve", run in
-- the order of their keys, with a phase pass per clause. The condition is the
-- `needs` grammar unchanged — a list, all of which must hold — so nothing about
-- conditions is new; only where one may stand.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local declaration = require("declaration")
local validate = require("validate")

local M = {}

local GAME = [==[{
  "title": "If Do",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "initiative", "min": 0, "max": 1, "on": ["player"], "start": 0 },
    { "key": "mana", "min": 0, "max": 99, "on": ["player"], "start": 0 },
    { "key": "hurt", "min": 0, "max": 99, "on": ["player"], "start": 0 },
    { "key": "after", "min": 0, "max": 99, "on": ["player"], "start": 0 }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.75, 0.9, 0.2], [0.05, 0.05, 0.9, 0.2]] },
    { "key": "options", "layout": "row", "status": "offer", "display": "offscreen" }
  ],
  "verbs": [
    { "key": "boost", "tooltip": "Gain param1 hurt, if you have at least param1 mana.",
      "action": [{ "if": ["mana@mine.player >= param1"], "do": ["stat_gain:hurt@mine.player:param1"] }] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "dart", "text": "Gain 1 mana. If you have Initiative, deal 1 damage.",
      "play": { "action": ["stat_gain:mana@mine.player:1",
        { "if": ["initiative@mine.player >= 1"], "do": ["stat_gain:hurt@mine.player:1"] },
        "stat_gain:after@mine.player:1"] } },
    { "key": "both", "text": "Two conditions, both needed",
      "play": { "action": [{ "if": ["initiative@mine.player >= 1", "mana@mine.player >= 2"],
        "do": ["stat_gain:hurt@mine.player:5"] }] } },
    { "key": "ask", "text": "If you have Initiative, choose; then gain one after",
      "play": { "action": [{ "if": ["initiative@mine.player >= 1"],
        "do": ["options:pick:optional", "stat_gain:hurt@mine.player:1"] }, "stat_gain:after@mine.player:1"] } },
    { "key": "pick", "text": "Pick", "play": { "action": ["stat_gain:mana@mine.player:10"] } },
    { "key": "boosted", "text": "Boost 2", "play": { "action": ["boost:2"] } }
  ]
}]==]

local PATH, FILE = "game/games/tmp_if_do.json", "tmp_if_do.json"

local function write(path, text)
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
end

local function with_game(fn)
	write(PATH, GAME)
	local ok, err = pcall(fn, FILE)
	os.remove(PATH)
	if not ok then error(err, 0) end
end

local function me()
	for e in entity.each("card") do if e.def_key == "one" then return e.stats end end
end

local function cast(key, init, mana)
	me().initiative, me().mana = init, mana or 0
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == "one" then
			flow.play_card(zones.add(z, key).id, {})
			flow.settle()
			return
		end
	end
end

local function pick(def_key)
	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == def_key then return flow.play_card(id, {}) end
	end
end

function M.test_if_do_runs_its_lines_in_place_when_it_holds(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("dart", 1)
		local s = me()
		check("the line before", s.mana == 1, s.mana)
		check("the if", s.hurt == 1, s.hurt)
		check("the line after", s.after == 1, s.after)
	end)
end

function M.test_if_do_skips_only_itself_when_it_fails(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("dart", 0)
		local s = me()
		check("the if did nothing", s.hurt == 0, s.hurt)
		check("and the lines around it ran", s.mana == 1 and s.after == 1, s.mana .. "/" .. s.after)
	end)
end

function M.test_if_do_needs_every_condition(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("both", 1, 1)
		check("one of two is not enough", me().hurt == 0, me().hurt)
		cast("both", 1, 2)
		check("both is", me().hurt == 5, me().hurt)
	end)
end

-- A question inside the do: the rest of the do and the rest of the list both
-- wait for the answer, in that order, exactly as if they had been one list.
function M.test_if_do_waits_behind_a_question_it_asks(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("ask", 1)
		check("nothing after the question has run yet", me().hurt == 0 and me().after == 0,
			me().hurt .. "/" .. me().after)
		pick("pick")
		flow.settle()
		check("the answer, then the rest of the do, then the rest of the list",
			me().mana == 10 and me().hurt == 1 and me().after == 1, me().mana .. "/" .. me().hurt .. "/" .. me().after)
	end)
end

-- A verb's parameter is a whole word wherever it stands, the condition included.
function M.test_if_do_takes_a_verb_parameter_in_both_halves(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("boosted", 0, 1)
		check("one mana is short of two", me().hurt == 0, me().hurt)
		cast("boosted", 0, 2)
		check("two is enough, and gains two", me().hurt == 2, me().hurt)
	end)
end

function M.test_if_do_game_is_clean(check)
	with_game(function(name)
		-- Where the seats sit is this fixture's business, not the if's.
		local problems = {}
		for _, s in ipairs(validate.check(declaration.parse(name))) do
			if not s:find("no visible home", 1, true) then problems[#problems + 1] = s end
		end
		check("no problems", #problems == 0, table.concat(problems, "; "))
	end)
end

local function said(entry)
	local path = "game/games/tmp_if_do_bad.json"
	write(path, [==[{
		"title": "Bad If",
		"stats": [{ "key": "gold", "min": 0, "on": ["player"] }],
		"zones": [{ "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner" }],
		"players": [{}, {}],
		"phases": [{ "key": "turn", "type": "player_input", "zone": "hand" }],
		"cards": [{ "key": "coin", "text": "Coin", "play": { "action": [ ]==] .. entry .. [==[ ] } }]
	}]==])
	local ok, G = pcall(declaration.parse, "tmp_if_do_bad.json")
	os.remove(path)
	if not ok then error(G, 2) end
	return table.concat(validate.check(G), "; ")
end

function M.test_if_do_validator_refuses_the_wrong_shapes(check)
	local s = said('{ "if": ["gold@mine.player >= 1"], "do": [{ "if": ["gold@mine.player >= 2"], "do": ["stat_gain:gold@mine.player:1"] }] }')
	check("an if inside an if", s:find("inside another", 1, true), s)
	s = said('{ "if": ["gold@mine.player >= 1"] }')
	check("an if with no do", s:find('"do"', 1, true), s)
	s = said('{ "do": ["stat_gain:gold@mine.player:1"] }')
	check("a do with no if", s:find('"if"', 1, true), s)
	s = said('{ "if": ["gold@mine.player >= 1"], "do": ["stat_gain:gold@mine.player:1"], "else": ["stat_gain:gold@mine.player:2"] }')
	check("an else", s:find("else", 1, true), s)
	s = said('{ "if": ["glod@mine.player >= 1"], "do": ["stat_gain:gold@mine.player:1"] }')
	check("a misspelt condition", s:find("glod", 1, true), s)
	s = said('{ "if": ["gold@mine.player >= 1"], "do": ["stat_gian:gold@mine.player:1"] }')
	check("a misspelt action inside the do", s:find("stat_gian", 1, true), s)
end

return M
