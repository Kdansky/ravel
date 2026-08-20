-- Saying "every seat" once.
--
-- The engine knows how many seats there are, and content used to write the
-- number out anyway — twice over. A stat every player carries was copied onto
-- each seat card, so Splendor's two seats held twenty numbers each of which
-- nineteen were the same, and adding a third seat meant copying them again. And
-- an action for every player was a walk: The Crew's deal named four seats and
-- drew four times, so a five-player variant meant editing the phase rather than
-- the players list.
--
-- Neither needed new vocabulary. `on: ["player"]` is the stat word that already
-- existed, reaching the one tag a game never types; `each_seat:` wraps any
-- action at all, because every scope a game writes is already relative to
-- whoever is up.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")
local log     = require("log")
local declaration = require("declaration")
local validate = require("validate")

local M = {}

local GAME = [==[{
  "title": "Every Seat",
  "players": [{ "card": "north" }, { "card": "east" }, { "card": "south" }],
  "stats": [
    { "key": "purse", "min": 0, "max": 99, "tags": ["hidden"], "on": ["player"], "start": 3 },
    { "key": "score", "min": 0, "max": 99, "tags": ["hidden"], "on": ["player"], "start": 0 },
    { "key": "held", "min": 0, "max": 99, "tags": ["hidden"], "on": ["player"], "start": 0 }
  ],
  "zones": [
    { "key": "hand", "type": "hand", "tags": ["per_seat"],
      "pos": [[0.22, 0.80, 0.60, 0.95], [0.22, 0.02, 0.60, 0.17], [0.62, 0.02, 0.98, 0.17]] },
    { "key": "deck", "type": "deck", "tags": ["hidden"],
      "contents": ["chip:9"] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "north", "text": "North", "tags": ["north_side"] },
    { "key": "east",  "text": "East",  "tags": ["east_side"] },
    { "key": "south", "text": "South", "tags": ["south_side"], "card_stats": { "purse": 7 } },
    { "key": "chip",  "text": "Chip",  "tags": ["chip"] }
  ]
}]==]

local PATH, FILE = "game/games/tmp_every_seat.json", "tmp_every_seat.json"

local function with_game(text, fn)
	local f = assert(io.open(PATH, "w"))
	f:write(text or GAME)
	f:close()
	local ok, err = pcall(fn, FILE)
	os.remove(PATH)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function log_text() return table.concat(log.tail(1e9), "\n") end

-- A stat every seat carries, declared once. `player` is stamped by the engine
-- from the players list, which is why this had to wait for the loader to do
-- that before granting anything.
function M.test_every_seat_a_stat_may_name_the_seats(check)
	with_game(nil, function(name)
		flow.init(name, 3)
		check("north was granted the purse", seat("north").stats.purse == 3,
			tostring(seat("north").stats.purse))
		check("and so was east", seat("east").stats.purse == 3)
		check("and the second stat too", seat("north").stats.score == 0
			and seat("east").stats.score == 0)
		-- The rule the whole feature rests on, and the same one card_stats has
		-- always had against a stat's "start".
		check("but a seat that says its own keeps it", seat("south").stats.purse == 7,
			tostring(seat("south").stats.purse))
	end)
end

-- One action, once per seat, with "mine" meaning each of them in turn.
function M.test_every_seat_an_action_may_be_run_for_each(check)
	with_game(nil, function(name)
		flow.init(name, 3)
		actions.execute("each_seat:draw_from:deck:mine.hand:2", {})
		for _, k in ipairs({ "north", "east", "south" }) do
			local z = zones.find("hand", k)
			check(k .. " holds two", z ~= nil and #z.cards == 2,
				z and tostring(#z.cards) or "(no hand)")
		end

		actions.execute("each_seat:stat_gain:held@mine.player:1", {})
		check("and every seat's own number moved",
			seat("north").stats.held == 1 and seat("east").stats.held == 1
			and seat("south").stats.held == 1,
			("%d/%d/%d"):format(seat("north").stats.held, seat("east").stats.held,
				seat("south").stats.held))
	end)
end

-- Dealing to everybody is not anybody's turn: the seat that was up is up when
-- it returns, nothing is announced, and the undo history is untouched.
function M.test_every_seat_is_not_a_handover(check)
	with_game(nil, function(name)
		flow.init(name, 3)
		local before, said = zones.active_seat(), log_text()
		local sys = zones.system_card()
		local turn = sys.stats.turn
		actions.execute("each_seat:stat_gain:held@mine.player:1", {})
		check("the same seat is up", zones.active_seat() == before, tostring(zones.active_seat()))
		check("down to the number", sys.stats.turn == turn, tostring(sys.stats.turn))
		-- The actions it wraps still say what they did — that is theirs. What
		-- must not appear is a handover, since nobody's turn ended.
		check("the actions it ran still speak for themselves", log_text() ~= said)
		check("but no turn was announced", log_text():match("to play") == nil, log_text())
	end)
end

-- It wraps an action, so what it wraps is checked as one. Without this the
-- inner half is a string nobody reads until it runs and does nothing.
function M.test_every_seat_checks_what_it_wraps(check)
	local text = GAME:gsub('"key": "act", "type": "player_input", "zone": "hand"',
		'"key": "act", "type": "player_input", "zone": "hand",'
		.. ' "actions": ["each_seat:draw_from:nowhere:mine.hand:1"]')
	with_game(text, function(name)
		flow.init(name, 3)
		local said
		for _, p in ipairs(validate.check(declaration.G)) do
			if p:match("nowhere") then said = p end
		end
		check("the zone inside it is checked", said ~= nil, said or "(nothing said)")
	end)
end

return M
