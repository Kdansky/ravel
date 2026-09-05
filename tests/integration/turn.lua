-- A turn is a phase whose body is other phases.
--
-- Spellstorm wrote sixteen of its twenty-five phases twice — `play_1`/`play_2`,
-- `journal_2a`/`journal_2b`, four more pairs — and the second copy of each was
-- the first with one word changed. That duplication is what made the game
-- two-player: not anything in the engine, which has counted seats by `seat_list`
-- since the first one. Its own generator wrote the pairs in a Python loop, which
-- is the word this file puts into the format.
--
-- Two declarations, and they are kept apart on purpose. The **group** says what
-- runs, in what order, and for whom; the **members** say what running is. A
-- member is reachable only through its group, the way an overlay is reachable
-- only by being pushed, so it carries no routing of its own and a round boundary
-- sits on the group rather than on the last copy of a phase.

local entity = require("entity")
local flow = require("flow")
local log = require("log")
local phase = require("phase")
local zones = require("zones")

local M = {}

-- `order` is written in where the fixture wants one, so every case below is the
-- same game with one word changed — which is the comparison the feature is about.
local function game(order, extra_dawn, stop)
	return ([==[{
  "title": "Turns",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "gold", "label": "Gold", "subject": "gold@mine.player" },
    { "key": "mark", "label": "Mark", "subject": "mark@mine.player" },
    { "key": "lead", "label": "Lead", "subject": "lead@mine.player" },
    { "key": "tick", "label": "Tick", "subject": "sum:tick@plan" }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "desk", "layout": "stack", "status": "board", "pos": [0.05, 0.45, 0.15, 0.60] }
  ],
  "phases": [
    { "key": "boot", "type": "player_input", "zone": ["hand"], "next": [{ "then": "day" }] },
    { "key": "day", "type": "turn", "seat": "each", %s
      "phases": ["dawn", "noon"%s], "next": [{ "then": "hold", "ends_round": true }] },
    { "key": "dawn", "type": "automatic",
      "actions": ["stat_gain:tick@plan:1", "stat_set:mark@mine.player:sum:tick@plan"%s] },
    { "key": "noon", "type": "automatic", "actions": ["stat_gain:gold@mine.player:1"] },%s
    { "key": "hold", "type": "player_input", "zone": ["hand"] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "gold": 0, "mark": 0, "lead": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "gold": 0, "mark": 0, "lead": 0 } },
    { "key": "plan", "text": "Plan", "tags": ["plan"], "card_stats": { "tick": 0 } },
    { "key": "pass", "text": "Pass", "play": { "action": ["next_phase"] } }
  ],
  "setup": { "place": [{ "card": "plan", "zone": "desk" }] }
}]==]):format(order and ('"order": "' .. order .. '",') or "",
		stop and ', "act"' or "",
		extra_dawn or "",
		stop and '\n    { "key": "act", "type": "player_input", "zone": ["hand"] },' or "")
end

local function with_game(text, fn)
	local path = "game/games/tmp_turn.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_turn.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- The hand of whoever is up, because a card in somebody else's hand is not
-- playable and a test that plays one proves nothing.
local function my_hand()
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == zones.active_seat() then return z end
	end
end

local function pass()
	local p = zones.add(my_hand(), "pass")
	flow.play_card(p.id, {})
end

-- Past `boot`, which is only there so a test can arrange the seat cards before
-- the group is entered and its order settled.
local function begin(seat)
	if seat then zones.system_card().stats.turn = seat end
	pass()
end

-- Who went when, read off the marks: the seat that went first holds 1.
local function marks()
	return card("one").stats.mark, card("two").stats.mark
end

-- Every phase of the group, for every seat, and nothing twice.
function M.test_turn_runs_every_phase_once_per_seat(check)
	with_game(game(nil), function(name)
		flow.init(name, 5)
		begin()
		check("both phases ran for both seats", card("plan").stats.tick == 2, card("plan").stats.tick)
		check("and the second phase did too, once each",
			card("one").stats.gold == 1 and card("two").stats.gold == 1,
			card("one").stats.gold .. "/" .. card("two").stats.gold)
	end)
end

-- The seat moves between iterations, and moves the way handing over always has:
-- the log says whose it is, because that is the whole of what a player sees.
function M.test_turn_hands_the_seat_over_between_players(check)
	with_game(game(nil), function(name)
		flow.init(name, 5)
		log.clear()
		begin()
		local a, b = marks()
		check("one player went first and the other second", a == 1 and b == 2, a .. "/" .. b)
		local said = table.concat(log.tail(40), "\n")
		check("and the log named both of them",
			said:find("One to play", 1, true) and said:find("Two to play", 1, true), said)
	end)
end

-- The order a group goes round in is its own, and it is a stat on the seat cards
-- rather than a place in the players list.
function M.test_turn_order_leads_with_the_highest(check)
	with_game(game("highest:lead"), function(name)
		flow.init(name, 5)
		card("two").stats.lead = 3
		begin()
		local a, b = marks()
		check("the seat holding the number went first", b == 1 and a == 2, a .. "/" .. b)
	end)
end

function M.test_turn_order_lowest_is_the_same_word_backwards(check)
	with_game(game("lowest:lead"), function(name)
		flow.init(name, 5)
		card("two").stats.lead = 3
		begin()
		local a, b = marks()
		check("the seat holding the least went first", a == 1 and b == 2, a .. "/" .. b)
	end)
end

-- Nobody leading is a state a game can reach — Spellstorm's Initiative is nought
-- for both players before the first battle — so it has to mean something, and
-- the only honest answer is the order the game listed its players in.
function M.test_turn_order_ties_keep_the_order_the_players_are_listed_in(check)
	with_game(game("highest:lead"), function(name)
		flow.init(name, 5)
		begin()
		local a, b = marks()
		check("with nobody ahead, the table plays in its own order", a == 1 and b == 2, a .. "/" .. b)
	end)
end

-- The sort happens once, when the group is entered. Asked again per seat, a
-- player who scores during their own turn decides who comes after them — and
-- here would simply take both turns.
function M.test_turn_order_is_settled_when_the_group_is_entered(check)
	with_game(game("highest:lead", ', "stat_gain:lead@mine.player:10"'), function(name)
		flow.init(name, 5)
		card("two").stats.lead = 3
		begin()
		local a, b = marks()
		check("the player who pulled ahead mid-turn did not go twice", b == 1 and a == 2, a .. "/" .. b)
		check("and both of them did go", card("plan").stats.tick == 2, card("plan").stats.tick)
	end)
end

-- Without an order the table goes round from whoever is next, which is what a
-- pair of phases both saying seat "next" used to mean.
function M.test_turn_without_an_order_goes_round_from_whoever_is_next(check)
	with_game(game(nil), function(name)
		flow.init(name, 5)
		begin(1)
		local a, b = marks()
		check("the player after the one who was up went first", b == 1 and a == 2, a .. "/" .. b)
	end)
end

-- The group's routing is the group's: it runs after the last seat, not after
-- each of them. A round that ticked per player would be two rounds a turn.
function M.test_turn_takes_its_route_once_after_the_last_seat(check)
	with_game(game(nil), function(name)
		flow.init(name, 5)
		local before = zones.system_card().stats.round or 1
		begin()
		check("the phase after the group is the one that is up",
			phase.current().key == "hold", phase.current().key)
		check("and the round advanced once, not once per player",
			zones.system_card().stats.round == before + 1, zones.system_card().stats.round)
	end)
end

-- A group's place in itself is state, so it goes over the wire and into a save
-- with everything else. Stopped halfway through — the second player has not had
-- their turn yet — a restore has to put them back in the queue.
function M.test_turn_keeps_its_place_across_a_snapshot(check)
	with_game(game("highest:lead", nil, "stops"), function(name)
		flow.init(name, 5)
		card("two").stats.lead = 3
		begin()
		check("the group stopped inside itself, waiting on the first player",
			phase.current().key == "act" and phase.group().key == "day",
			phase.current().key .. "/" .. tostring(phase.group() and phase.group().key))

		local mid = phase.snapshot()
		check("the snapshot carries the group and its place",
			mid.stack[#mid.stack].turn ~= nil and mid.stack[#mid.stack].turn.seat_at == 1,
			tostring(mid.stack[#mid.stack].turn and mid.stack[#mid.stack].turn.seat_at))

		-- Play on past the restore point, then go back to it: the second player
		-- must still be waiting rather than the group being over.
		pass()
		check("the group came round to the other player",
			phase.group() ~= nil and card("plan").stats.tick == 2,
			card("plan").stats.tick .. "/" .. tostring(phase.group() and phase.group().key))

		phase.restore(mid)
		check("restored, the group is back where it was",
			phase.current().key == "act" and phase.group().key == "day", phase.current().key)
		check("and the copy did not take the live counter with it",
			phase.snapshot().stack[#mid.stack].turn ~= mid.stack[#mid.stack].turn)
	end)
end

-- Over the wire the stack carries keys rather than defs, so the group had to be
-- taught the same trick. A peer handed a state from the middle of somebody's
-- turn has to find the rest of the table still waiting: dropped, the group would
-- end on the frame that arrived and everybody after would be skipped.
function M.test_turn_crosses_the_wire_with_its_place_in_it(check)
	with_game(game("highest:lead", nil, "stops"), function(name)
		local net = require("net")
		flow.init(name, 5)
		card("two").stats.lead = 3
		begin()
		check("stopped inside the group", phase.group() ~= nil and phase.current().key == "act",
			phase.current().key)
		local snap = net.snapshot()

		-- Somewhere else entirely, then back to what was sent.
		flow.init(name, 5)
		local ok, err = net.apply_full(snap)
		check("the state applied", ok, tostring(err))
		check("and it is the same phase, inside the same group",
			phase.current().key == "act" and phase.group() and phase.group().key == "day",
			phase.current().key .. "/" .. tostring(phase.group() and phase.group().key))

		-- The proof that the *place* came too and not just the group: play on and
		-- the other player still gets their turn.
		pass()
		check("the player who had not been asked yet was asked",
			card("plan").stats.tick == 2, card("plan").stats.tick)
	end)
end

return M
