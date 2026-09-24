-- A `needs` written by what failing it does (needs.lua): `req` blocks, `where`
-- filters each candidate, `fizzle` lets it be used and do nothing, and any other
-- key is a gate that only the lines written "name? action" sit behind.
--
-- Magic Dart prints "Gain 1 mana. If you have Initiative, deal 1 damage." as one
-- sentence, and it is one list: the gate is named once, the lines behind it say
-- so, and the answer is asked at the first of them and kept.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local declaration = require("declaration")
local validate = require("validate")

local M = {}

local GAME = [==[{
  "title": "Gates",
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
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "dart", "text": "Gain 1 mana. If you have Initiative, deal 1 damage.",
      "play": { "needs": { "init": "initiative@mine.player >= 1" },
        "action": ["stat_gain:mana@mine.player:1", "init? stat_gain:hurt@mine.player:1", "stat_gain:after@mine.player:1"] } },
    { "key": "silt", "text": "Whoever has Initiative loses it.",
      "play": { "needs": { "init": "initiative@mine.player >= 1" },
        "action": ["init? stat_set:initiative@mine.player:0", "!init? stat_set:initiative@mine.player:1"] } },
    { "key": "both", "text": "Two conditions, one gate",
      "play": { "needs": { "rich": ["initiative@mine.player >= 1", "mana@mine.player >= 2"] },
        "action": ["rich? stat_gain:hurt@mine.player:5"] } },
    { "key": "blocked", "text": "Needs two mana to play",
      "play": { "needs": { "req": "mana@mine.player >= 2" }, "action": ["stat_gain:hurt@mine.player:1"] } },
    { "key": "fizzles", "text": "Playable; does nothing without two mana",
      "play": { "needs": { "fizzle": "mana@mine.player >= 2" }, "action": ["stat_gain:hurt@mine.player:1",
        "stat_gain:after@mine.player:1"] } },
    { "key": "ask", "text": "If you have Initiative, choose; then gain one after",
      "play": { "needs": { "init": "initiative@mine.player >= 1" },
        "action": ["init? options:pick:optional", "init? stat_set:initiative@mine.player:0",
          "init? stat_gain:hurt@mine.player:1", "stat_gain:after@mine.player:1"] } },
    { "key": "pick", "text": "Pick", "play": { "action": ["stat_gain:mana@mine.player:10"] } }
  ]
}]==]

local PATH, FILE = "game/games/tmp_gates.json", "tmp_gates.json"

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

local function card(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == "one" then return zones.add(z, key) end
	end
end

local function cast(key, init, mana)
	me().initiative, me().mana = init, mana or 0
	flow.play_card(card(key).id, {})
	flow.settle()
end

local function pick(def_key)
	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == def_key then return flow.play_card(id, {}) end
	end
end

function M.test_gates_run_their_lines_in_place_when_they_hold(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("dart", 1)
		local s = me()
		check("the line before", s.mana == 1, s.mana)
		check("the gated line", s.hurt == 1, s.hurt)
		check("the line after", s.after == 1, s.after)
	end)
end

function M.test_gates_skip_only_their_own_lines(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("dart", 0)
		local s = me()
		check("the gated line did nothing", s.hurt == 0, s.hurt)
		check("and the lines around it ran", s.mana == 1 and s.after == 1, s.mana .. "/" .. s.after)
	end)
end

-- Swamp Silt's shape: the first branch changes what the gate reads, and the
-- other branch must not see the change.
function M.test_gates_answer_once_so_the_other_branch_reads_the_same(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("silt", 1)
		check("held it, lost it, and did not take it back", me().initiative == 0, me().initiative)
		cast("silt", 0)
		check("did not hold it, took it", me().initiative == 1, me().initiative)
	end)
end

function M.test_gates_need_every_condition(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("both", 1, 1)
		check("one of two is not enough", me().hurt == 0, me().hurt)
		cast("both", 1, 2)
		check("both is", me().hurt == 5, me().hurt)
	end)
end

function M.test_gates_req_blocks_and_fizzle_does_not(check)
	with_game(function(name)
		flow.init(name, 3)
		me().mana = 1
		-- Both in hand, or the escape hatch opens the gated one for want of anything else.
		local fizzles, blocked = card("fizzles"), card("blocked")
		check("req: not playable", not flow.can_play(blocked.id))
		check("fizzle: playable", flow.can_play(fizzles.id))
		cast("fizzles", 0, 1)
		check("and does nothing at all", me().hurt == 0 and me().after == 0, me().hurt .. "/" .. me().after)
		cast("fizzles", 0, 2)
		check("with two mana it does all of it", me().hurt == 1 and me().after == 1, me().hurt .. "/" .. me().after)
	end)
end

-- A question behind a gate parks the rest of the list, and the answer the gate
-- got rides with it: the line that clears Initiative does not turn off the ones
-- after the question.
function M.test_gates_keep_their_answer_behind_a_question(check)
	with_game(function(name)
		flow.init(name, 3)
		cast("ask", 1)
		check("nothing after the question has run yet", me().hurt == 0 and me().after == 0,
			me().hurt .. "/" .. me().after)
		pick("pick")
		flow.settle()
		check("the answer, then the rest behind the gate, then the rest of the list",
			me().mana == 10 and me().initiative == 0 and me().hurt == 1 and me().after == 1,
			me().mana .. "/" .. me().initiative .. "/" .. me().hurt .. "/" .. me().after)
	end)
end

function M.test_gates_game_is_clean(check)
	with_game(function(name)
		-- Where the seats sit is this fixture's business, not the gates'.
		local problems = {}
		for _, s in ipairs(validate.check(declaration.parse(name))) do
			if not s:find("no visible home", 1, true) then problems[#problems + 1] = s end
		end
		check("no problems", #problems == 0, table.concat(problems, "; "))
	end)
end

local function said(play)
	local path = "game/games/tmp_gates_bad.json"
	write(path, [==[{
		"title": "Bad Needs",
		"stats": [{ "key": "gold", "min": 0, "on": ["player"] }],
		"zones": [{ "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner" }],
		"players": [{}, {}],
		"phases": [{ "key": "turn", "type": "player_input", "zone": "hand" }],
		"cards": [{ "key": "coin", "text": "Coin", "play": ]==] .. play .. [==[ },
		  { "key": "rule", "text": "Rule", "abilities": [{ "key": "tick", "phases": [],
		    "needs": { "fizzle": "gold@mine.player >= 1" }, "action": ["stat_gain:gold@mine.player:1"] }] }]
	}]==])
	local ok, G = pcall(declaration.parse, "tmp_gates_bad.json")
	os.remove(path)
	if not ok then error(G, 2) end
	return table.concat(validate.check(G), "; ")
end

function M.test_gates_the_wrong_shapes_are_named(check)
	local s = said('{ "needs": ["gold@mine.player >= 1"], "action": ["stat_gain:gold@mine.player:1"] }')
	check("the old list form", s:find('needs says what failing it does', 1, true), s)
	s = said('{ "target": { "type": "card", "count": 1, "where": ["gold@target >= 1"] }, "action": ["purge:target"] }')
	check("a where on the target", s:find('goes in the ability\'s "needs"', 1, true), s)
	s = said('{ "needs": { "req": "gold@target >= 1" }, "target": { "type": "card", "count": 1 }, "action": ["purge:target"] }')
	check("@target in a req", s:find('nothing is chosen when req is asked', 1, true), s)
	s = said('{ "needs": { "where": "gold@target >= 1" }, "action": ["stat_gain:gold@mine.player:1"] }')
	check("a where with no target", s:find('nothing here has a target', 1, true), s)
	s = said('{ "needs": { "rich": "gold@mine.player >= 1" }, "action": ["stat_gain:gold@mine.player:1"] }')
	check("a gate no line uses", s:find('no line is behind it', 1, true), s)
	s = said('{ "action": ["rich? stat_gain:gold@mine.player:1"] }')
	check("a line behind a gate that is not there", s:find('which its needs does not name', 1, true), s)
	s = said('{ "needs": { "rich": "glod@mine.player >= 1" }, "action": ["rich? stat_gain:gold@mine.player:1"] }')
	check("a misspelt condition in a gate", s:find("glod", 1, true), s)
	check("fizzle on an ability no player uses", s:find('write "req"', 1, true), s)
end

return M
