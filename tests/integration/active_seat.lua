-- "set_active_seat:<scope>" — handing the turn to whoever a card belongs to.
--
-- The reading half of this question shipped as "@owner_of" (owner_scope.lua);
-- this is the writing half, and it is what a trick-taking game cannot be built
-- without. Every other way of naming a seat is settled before the game starts,
-- so a rule that says "the winner leads" has no way to say it.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")
local log     = require("log")
local net     = require("net")
local geometry = require("geometry")

local M = {}

local GAME = [==[{
  "title": "Active Seat",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "subject": "score@mine.player" }],
  "zones": [
    { "key": "board", "type": "grid", "grid": [4, 1], "tags": ["activate"],
      "pos": [0.05, 0.40, 0.95, 0.60] },
    { "key": "commons", "type": "pile", "pos": [0.30, 0.70, 0.45, 0.90] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "board", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "score": 0 } },
    { "key": "piece", "text": "Piece", "tags": ["piece"] }
  ],
  "setup": {
    "place": [
      { "card": "piece", "owner": "one", "zone": "board", "at": ["a1"] },
      { "card": "piece", "owner": "two", "zone": "board", "at": ["c1"] }
    ]
  }
}]==]

local PATH, FILE = "game/games/tmp_active_seat.json", "tmp_active_seat.json"

local function with_game(fn)
	local f = assert(io.open(PATH, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, FILE)
	os.remove(PATH)
	if not ok then error(err, 0) end
end

-- The piece standing on a square, by its algebraic name.
local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("board"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

local function log_text() return table.concat(log.tail(1e9), "\n") end

function M.test_active_seat_follows_the_card(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the first seat is up", zones.active_seat() == "one", tostring(zones.active_seat()))

		actions.execute("set_active_seat:owner_of.target", { targets = { at("c1").id } })
		check("the target's owner is now up", zones.active_seat() == "two", tostring(zones.active_seat()))
		check("and the handover is in the log", log_text():find("Two") ~= nil, log_text())

		actions.execute("set_active_seat:owner_of.target", { targets = { at("a1").id } })
		check("it follows the card back", zones.active_seat() == "one", tostring(zones.active_seat()))
	end)
end

-- The scope names cards and the seat is whose they are, so the prefix is not
-- needed to reach an ordinary card's owner. One rule, not two spellings.
function M.test_active_seat_a_bare_scope_means_whose_it_is(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("set_active_seat:target", { targets = { at("c1").id } })
		check("naming the card names its owner", zones.active_seat() == "two", tostring(zones.active_seat()))

		-- ...and a seat card answers for itself, which is how a game names a
		-- seat outright when it does know which one it wants.
		actions.execute("set_active_seat:seat_one", {})
		check("a seat card is its own seat", zones.active_seat() == "one", tostring(zones.active_seat()))
	end)
end

-- Picking the first would make turn order depend on the order cards happen to
-- sit in the file, which is the kind of rule nobody can read off the game.
function M.test_active_seat_refuses_to_name_two_seats(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("set_active_seat:anyone.piece", {})
		check("an ambiguous scope changes nothing", zones.active_seat() == "one", tostring(zones.active_seat()))
		check("and says so", log_text():find("names both") ~= nil, log_text())
	end)
end

-- A scope matching nothing is an ordinary state of the game rather than a
-- mistake in it: the trick is not won until somebody has won it.
function M.test_active_seat_naming_nobody_does_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local before = log_text()
		actions.execute("set_active_seat:commons", {})
		check("an empty scope leaves the turn alone", zones.active_seat() == "one", tostring(zones.active_seat()))
		check("and says nothing about it", log_text() == before)

		actions.execute("set_active_seat:owner_of.target", { targets = { at("a1").id } })
		check("naming the seat already up is not a handover", log_text() == before, log_text())
	end)
end

-- Undo history belongs to the seat that had it. Undoing across a handover would
-- rewrite a decision that was not yours — which is exactly why a turn ending
-- normally clears it too (flow.rotate_seat).
function M.test_active_seat_a_handover_ends_the_undo_history(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("stat_gain:score@mine.player:1", {})
		flow.play_card(at("a1").id)
		check("there is something to undo", flow.can_undo())

		actions.execute("set_active_seat:owner_of.target", { targets = { at("c1").id } })
		check("the handover took the history with it", not flow.can_undo())
	end)
end

-- It ships state, not moves, so the far end learns whose turn it is the same
-- way it learns everything else. What makes it worth asserting is that the turn
-- lives on the injected system card: a snapshot that skipped that card would
-- leave both machines believing they were up.
function M.test_active_seat_travels_over_the_wire(check)
	with_game(function(name)
		net.begin(name, 7)
		local shared = net.export(true)
		actions.execute("set_active_seat:owner_of.target", { targets = { at("c1").id } })
		local moved, delta = net.fingerprint(), net.export()
		check("the sender handed over", zones.active_seat() == "two", tostring(zones.active_seat()))

		net.import(shared)                     -- rewind: be the opponent
		check("the opponent still thinks the first seat is up", zones.active_seat() == "one")
		local ok, err = net.import(delta)
		check("the delta applies", ok, err)
		check("and the opponent now agrees who is up", zones.active_seat() == "two",
			tostring(zones.active_seat()))
		check("on exactly the sender's state", net.fingerprint() == moved)
	end)
end

-- Nought is "nobody has taken a turn yet" and it *reads* as the first seat, so
-- naming that seat looked like a no-op — and left the sentinel standing. The
-- next handover computed 0 % seats + 1, named the first seat again, and the
-- table took its second turn out of order. Found by writing The Crew's deal as
-- one "each_seat" line, which restored the turn to nought where the old walk
-- had left it at four and hidden this.
function M.test_active_seat_naming_the_first_seat_settles_the_sentinel(check)
	with_game(function(name)
		flow.init(name, 3)
		local sys = zones.system_card()
		check("nobody has played", sys.stats.turn == 0, tostring(sys.stats.turn))
		check("which reads as the first seat", zones.active_seat() == "one")

		actions.execute("set_active_seat:owner_of.target", { targets = { at("a1").id } })
		check("naming that seat writes the number down", sys.stats.turn == 1, tostring(sys.stats.turn))
		check("and the seat is unchanged", zones.active_seat() == "one")

		-- The whole point: the handover after it must reach somebody else.
		actions.execute("set_active_seat:owner_of.target", { targets = { at("c1").id } })
		check("so the next handover reaches the other seat", zones.active_seat() == "two",
			tostring(zones.active_seat()))
	end)
end

return M
