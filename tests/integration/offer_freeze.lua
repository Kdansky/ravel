-- Nothing about whose game it is moves while a question is on the table.
--
-- An offer is asked in a phase, of a seat, holding priority. End the phase while
-- it stands and the cards it borrowed have nowhere to come home to: the overlay
-- is still on the stack under a phase that has moved on, and Puzzle Strike's
-- whole eighteen-chip bank sat in it, unreachable, for exactly one afternoon.
--
-- So the change is refused, not performed quietly and not performed after
-- closing the offer on the rule's behalf — a list that walks away from a
-- question it asked has not decided what happens to it. The place to put the
-- change is "chosen", which runs once the offer has closed.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local declaration = require("declaration")
local validate    = require("validate")

local M = {}

local GAME = [==[{
  "title": "Offer Freeze",
  "players": [{ "card": "one" }, { "card": "two" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.4, 0.9, 0.2], [0.05, 0.62, 0.9, 0.2]] },
    { "key": "vault", "layout": "row", "pos": [0.05, 0.05, 0.9, 0.25],
      "contents": ["gem:3"] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "rest" }] },
    { "key": "rest", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "gem", "text": "Gem", "tags": ["gem"] },
    { "key": "walker", "text": "Walker",
      "play": { "phases": ["act"], "action": ["show:vault", "next_phase"], "spent": "void" } },
    { "key": "hander", "text": "Hander",
      "play": { "phases": ["act"], "action": ["show:vault", "set_priority:enemy.player"],
                "spent": "void" } },
    { "key": "waiter", "text": "Waiter",
      "play": { "phases": ["act"], "action": ["show:vault"], "spent": "void" },
      "chosen": { "action": ["next_phase"] } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_offer_freeze.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_offer_freeze.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function count_in(key)
	local z = zones.find(key)
	return #((z or {}).cards or {})
end

local function play(def_key)
	local c = zones.add(zones.find("hand"), def_key)
	return flow.play_card(c.id, {})
end

function M.test_offer_freeze_refuses_a_phase_change(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the vault filled", count_in("vault") == 3, count_in("vault"))
		play("walker")
		check("the offer opened and holds the borrowed cards", count_in("options") == 3,
			count_in("options"))
		check("and the phase did not move out from under it",
			phase.current().key == "options", phase.current().key)
		check("the vault is empty while they are lent out", count_in("vault") == 0)

		-- The question still answerable is the point: the refusal leaves a live
		-- offer, not a dead one.
		local pick = entity.get(zones.find("options").cards[1])
		flow.play_card(pick.id, {})
		check("choosing sends every borrowed card home", count_in("vault") == 3,
			count_in("vault"))
		check("and the phase underneath comes back", phase.current().key == "act",
			phase.current().key)
	end)
end

function M.test_offer_freeze_refuses_a_priority_change(check)
	with_game(function(name)
		flow.init(name, 3)
		local before = zones.active_seat()
		play("hander")
		check("the offer is open", count_in("options") == 3)
		check("and priority stayed with the seat that asked",
			zones.active_seat() == before, tostring(zones.active_seat()))
	end)
end

-- The permitted route, and the reason the rule is a refusal rather than a
-- silent close: "chosen" runs once the offer has been answered, so the same
-- action does exactly what it was written to do.
function M.test_offer_freeze_allows_the_change_once_the_offer_has_closed(check)
	with_game(function(name)
		flow.init(name, 3)
		play("waiter")
		check("the offer is open", phase.current().key == "options")
		flow.play_card(zones.find("options").cards[1], {})
		check("chosen moved the phase on", phase.current().key == "rest",
			phase.current().key)
		check("and the borrowed cards still went home", count_in("vault") == 3,
			count_in("vault"))
	end)
end

function M.test_offer_freeze_is_read_off_the_file_too(check)
	with_game(function(name)
		local G = declaration.parse(name)
		local said = table.concat(validate.check(G), "; ")
		check("the list that opens an offer and then leaves is named",
			said:find("'show:vault' opens an offer and then 'next_phase'", 1, true), said)
		check("so is the one that hands priority away",
			said:find("and then 'set_priority'", 1, true), said)
		check("and it says where the action belongs instead",
			said:find("chosen", 1, true), said)
		check("while the card that waited for the answer is left alone",
			not said:find("'waiter'", 1, true), said)
	end)
end

return M
