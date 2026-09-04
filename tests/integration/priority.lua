-- Priority, distinct from the turn — the whole of letting a card be played out
-- of turn. "active_seat" is who is acting right now, and it reads priority over
-- the turn: unset everywhere but inside a response window, where the seat
-- answering another player's action holds it while the turn stays put. Because
-- "mine", costs, the plays counter and reachability all read active_seat, moving
-- priority is all it takes for the other seat to act, on their own cards and out
-- of their own pool.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local geometry = require("geometry")

local M = {}

local GAME = [==[{
  "title": "Priority",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "subject": "score@mine.player" }],
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.05, 0.40, 0.95, 0.60] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "board", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "score": 0 } },
    { "key": "piece", "text": "Piece", "tags": ["piece"],
      "abilities": [{ "action": ["stat_gain:score@mine.player:1"] }] }
  ],
  "setup": {
    "place": [
      { "card": "piece", "owner": "one", "zone": "board", "at": ["a1"] },
      { "card": "piece", "owner": "two", "zone": "board", "at": ["c1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_priority.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_priority.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("board"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

local function can_act(card)
	return #flow.usable_abilities(card.id) > 0
end

-- With no window open, priority is the turn: the seat up may act, the other may
-- not, and every existing game is exactly this.
function M.test_priority_defaults_to_the_turn(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the first seat is up", zones.active_seat() == "one", tostring(zones.active_seat()))
		check("and the turn agrees", zones.turn_seat() == "one", tostring(zones.turn_seat()))
		check("the seat up may act on its piece", can_act(at("a1")))
		check("the other seat may not, out of turn", not can_act(at("c1")))
	end)
end

-- Set priority to the other seat and it becomes the one acting — its piece is
-- reachable, the turn owner's is not — while the turn itself does not move.
function M.test_priority_lets_the_other_seat_answer(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("set_priority:enemy.player", {})
		check("the answering seat is now acting", zones.active_seat() == "two",
			tostring(zones.active_seat()))
		check("but the turn is still the first seat's", zones.turn_seat() == "one",
			tostring(zones.turn_seat()))
		check("so the answering seat may act on its own piece", can_act(at("c1")))
		check("and the turn owner may not, mid-window", not can_act(at("a1")))
	end)
end

-- "mine" follows the reactor: an ability the answering seat activates is paid to
-- and read from that seat, not the one whose turn it is.
function M.test_priority_mine_follows_the_reactor(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("set_priority:enemy.player", {})
		actions.execute("stat_gain:score@mine.player:1", {})
		check("the answering seat was credited", seat("two").stats.score == 1,
			tostring(seat("two").stats.score))
		check("and the turn owner was not", seat("one").stats.score == 0,
			tostring(seat("one").stats.score))
	end)
end

-- The window closes and the seat that acts is the seat that was acting before it
-- opened.
function M.test_clear_priority_returns_to_the_turn(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("set_priority:enemy.player", {})
		check("held by the other seat", zones.active_seat() == "two")
		actions.execute("clear_priority", {})
		check("priority is the turn again", zones.active_seat() == "one",
			tostring(zones.active_seat()))
		check("the turn owner may act once more", can_act(at("a1")))
		check("and the other seat may not", not can_act(at("c1")))
	end)
end

return M
