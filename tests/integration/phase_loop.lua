-- A phase that leads back to itself.
--
-- Splendor's turn is "take a token, then decide again"; The Crew's draft is
-- "take a task, then it is the next player's turn". Both are one phase looping,
-- and they want opposite things from the loop — so the seat moved onto the
-- *route*, where the transition is, rather than staying a property of the phase,
-- where it could only be said once.
--
-- Beside it the other half of the same question: what a phase does when the turn
-- *begins*, as against what it does every time round. A counter reset belongs to
-- the first — running it again on the way round would undo the turn it was
-- counting — and a number recomputed from the board belongs to the second. Two
-- phase keys used to be the price of that split, the second a copy of the first.

local entity   = require("entity")
local zones    = require("zones")
local phase    = require("phase")
local flow     = require("flow")
local declaration = require("declaration")
local validate = require("validate")

local M = {}

-- Two seats and a table to put chips on. `opened` counts arrivals, `rounds`
-- counts entries: the whole test is that those two numbers differ. The hand is
-- shared rather than per-seat, so that a test about the seat moving is not also
-- a test about whose cards are reachable.
local GAME = [==[{
  "title": "Phase Loop",
  "players": [{ "card": "north" }, { "card": "south" }],
  "stats": [
    { "key": "opened", "min": 0, "max": 99, "tags": ["hidden"], "on": ["side"], "start": 0 },
    { "key": "rounds", "min": 0, "max": 99, "tags": ["hidden"], "on": ["side"], "start": 0 }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.22, 0.80, 0.60, 0.95] },
    { "key": "table", "layout": "grid", "grid": [6, 1], "pos": [0.02, 0.30, 0.98, 0.50] }
  ],
  "phases": [
    { "key": "setup", "type": "automatic", "next": [{ "then": "act" }] },
    { "key": "act", "type": "player_input", "zone": "hand", "seat": "next", "ends_after": 1,
      "on_enter": ["stat_gain:opened@mine.player:1"],
      "actions": ["stat_gain:rounds@mine.player:1"],
      "next": [
        { "when": "count:chip@table >= 3", "then": "over" },
        { "then": "act", "seat": "same" }
      ] },
    { "key": "over", "type": "player_input", "label": "done", "next": [{ "then": "over" }] }
  ],
  "cards": [
    { "key": "north", "text": "North", "tags": ["side", "north_side"] },
    { "key": "south", "text": "South", "tags": ["side", "south_side"] },
    { "key": "chip", "text": "Chip", "tags": ["chip"], "play": { "action": ["move_to:table"] } }
  ],
  "setup": {
    "place": [
      { "card": "chip", "zone": "hand" }, { "card": "chip", "zone": "hand" },
      { "card": "chip", "zone": "hand" }, { "card": "chip", "zone": "hand" }
    ]
  }
}]==]

local function with_game(text, fn)
	local path = "game/games/tmp_phase_loop.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_phase_loop.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card_named(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function play_one()
	local z = zones.find("hand")
	for _, cid in ipairs(z and z.cards or {}) do
		if flow.can_play(cid) then flow.play_card(cid, {}); return true end
	end
	return false
end

-- The heart of it: three turns of one player, one arrival, three entries.
function M.test_phase_loop_on_enter_runs_once_and_actions_run_each_time(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local who = zones.active_seat()
		check("a player is up", who ~= nil)
		local me = card_named(who)
		check("the turn opened once", me.stats.opened == 1, tostring(me.stats.opened))
		check("and the phase has run once", me.stats.rounds == 1, tostring(me.stats.rounds))

		check("a chip goes down", play_one())
		check("still the same player", zones.active_seat() == who, tostring(zones.active_seat()))
		check("the turn did not open again", me.stats.opened == 1, tostring(me.stats.opened))
		check("but the phase ran again", me.stats.rounds == 2, tostring(me.stats.rounds))

		check("and another", play_one())
		check("opened is still one", me.stats.opened == 1, tostring(me.stats.opened))
		check("rounds is three", me.stats.rounds == 3, tostring(me.stats.rounds))
	end)
end

-- The route's word wins over the phase's. `act` says "next" for arrivals; its
-- own loop says "same", and one player takes three turns in a row.
function M.test_phase_loop_a_route_may_hold_the_seat(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local who = zones.active_seat()
		play_one()
		check("after one play the seat has not moved", zones.active_seat() == who)
		play_one()
		check("nor after two", zones.active_seat() == who)
		play_one()
		check("the third leaves the phase", phase.current().key == "over", phase.current().key)
	end)
end

-- And the other way: a phase that says nothing about seats, whose loop passes
-- the turn on. This is the draft, and it is why "same" could not simply be what
-- a self-route means. The phase's own seat is taken away here, so nothing but
-- the route can be moving it.
function M.test_phase_loop_a_route_may_pass_the_turn_on(check)
	local text = GAME
		:gsub('"seat": "next", "ends_after": 1', '"ends_after": 1')
		:gsub('{ "then": "act", "seat": "same" }', '{ "then": "act", "seat": "next" }')
	with_game(text, function(name)
		flow.init(name, 3)
		-- Nobody has been named yet — "turn" starts at nought and the first
		-- handover is what picks the first player, which is why this counts from
		-- the play after it rather than from the seat sitting there at init.
		play_one()
		local a = zones.active_seat()
		play_one()
		local b = zones.active_seat()
		check("the loop handed the turn on", a ~= b, tostring(a) .. " then " .. tostring(b))
		-- The point of the assertion: a loop that hands the turn on *is* the
		-- beginning of a turn, so the player it handed to gets the phase's
		-- opening. Firing on_enter only for arrivals from another phase would
		-- leave this at nought, and a draft would deal its second player nothing.
		check("and the player it handed to opened a turn",
			card_named(b).stats.opened == 1, tostring(card_named(b).stats.opened))
		check("having run the phase once", card_named(b).stats.rounds == 1,
			tostring(card_named(b).stats.rounds))
	end)
end

-- A word the engine doesn't know is refused rather than ignored: a route that
-- silently kept the seat would look exactly like one that meant to.
function M.test_phase_loop_an_unknown_seat_word_is_refused(check)
	local text = GAME:gsub('"seat": "same" }', '"seat": "sideways" }')
	with_game(text, function(name)
		flow.init(name, 3)
		local said
		for _, p in ipairs(validate.check(declaration.G)) do
			if p:match("sideways") then said = p end
		end
		check("the validator names it", said ~= nil, said or "(nothing said)")
		check("and offers the words it does know",
			said and (said:match("next") and said:match("same")) ~= nil, said)
	end)
end

-- on_enter on a phase nothing leads back to says a distinction that isn't
-- there — every entry is an arrival, which is what "actions" already means.
function M.test_phase_loop_on_enter_needs_something_to_lead_back(check)
	local text = GAME:gsub('{ "then": "act", "seat": "same" }', '{ "then": "over" }')
	with_game(text, function(name)
		flow.init(name, 3)
		local said
		for _, p in ipairs(validate.check(declaration.G)) do
			if p:match("on_enter") then said = p end
		end
		check("the validator says so", said ~= nil, said or "(nothing said)")
	end)
end

-- Both new fields are stack state, so undo has to carry them: restoring a frame
-- that forgot it was a loop would run the turn's opening a second time.
function M.test_phase_loop_a_snapshot_remembers_the_route(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		play_one()
		check("mid-loop", phase.current().key == "act")
		local snap = phase.snapshot()
		check("the frame knows it did not arrive", not phase.arrived())
		check("and what the route said about the seat", phase.route_seat() == "same")
		phase.push("over")
		check("pushed", phase.current().key == "over" and phase.arrived())
		phase.restore(snap)
		check("restored", phase.current().key == "act")
		check("still not an arrival", not phase.arrived())
		check("and the route's word came back", phase.route_seat() == "same")
	end)
end

return M
