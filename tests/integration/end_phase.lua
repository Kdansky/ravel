-- `end_phase`, and why it may name the phase it ends.
--
-- It used to be `next_phase`, which read as a routing instruction — *next we do
-- the action phase* — when what it says is that this one is over. Where it goes
-- afterwards was never its business: the phase's own `next` table says that.
--
-- Bare it ends whatever is running, which is what a button means and what a card
-- whose play is the whole move means. Naming a phase is for a card that prints
-- one: *"then end your action phase"* ends **that** phase and does nothing if it
-- has already ended. That made no difference at all until an action list could
-- resume somewhere other than where it started — and now one can, so three
-- copies of that sentence falling due together would otherwise end the action
-- phase, the phase after it, and the turn.

local zones = require("zones")
local phase = require("phase")
local flow  = require("flow")

local M = {}

local GAME = [==[{
  "title": "End Phase",
  "players": [{ "card": "one" }, { "card": "two" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.60, 0.95], [0.20, 0.05, 0.60, 0.20]] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "buy" }] },
    { "key": "buy", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "done", "text": "Done", "play": { "action": ["end_phase"] } },
    { "key": "act_done", "text": "That is my action", "play": { "action": ["end_phase:act"] } },
    { "key": "twice", "text": "Say it twice", "play": { "action": ["end_phase:act", "end_phase:act"] } },
    { "key": "bare_twice", "text": "Say it twice, unnamed", "play": { "action": ["end_phase", "end_phase"] } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_end_phase.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_end_phase.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function play(def_key)
	return flow.play_card(zones.add(hand_of(zones.active_seat()), def_key).id, {})
end

function M.test_end_phase_bare_ends_whatever_is_running(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the action phase is up", phase.current().key == "act", phase.current().key)
		play("done")
		check("and it is over", phase.current().key == "buy", phase.current().key)
		play("done")
		check("as is the one after it", phase.current().key == "act", phase.current().key)
	end)
end

function M.test_end_phase_may_name_the_one_it_means(check)
	with_game(function(name)
		flow.init(name, 3)
		play("act_done")
		check("naming the phase running ends it", phase.current().key == "buy",
			phase.current().key)
	end)
end

-- The whole point of the argument. Said from somewhere else it is not a
-- mistake and not a refusal — the phase it names is over, which is what the
-- card wanted, so there is nothing left to do.
function M.test_end_phase_does_nothing_from_a_phase_it_does_not_name(check)
	with_game(function(name)
		flow.init(name, 3)
		play("done")
		check("the buy phase is up", phase.current().key == "buy", phase.current().key)
		play("act_done")
		check("and a card ending the action phase leaves it alone",
			phase.current().key == "buy", phase.current().key)
	end)
end

-- Two of them in one list, which is the shape three copied chips make between
-- them: the phase ends once.
function M.test_end_phase_said_twice_ends_one_phase(check)
	with_game(function(name)
		flow.init(name, 3)
		play("twice")
		check("named, the action phase ended and the buy phase did not",
			phase.current().key == "buy", phase.current().key)

		flow.init(name, 3)
		play("bare_twice")
		check("unnamed, both of them ended — which is the bug the word answers",
			phase.current().key == "act", phase.current().key)
	end)
end

return M
