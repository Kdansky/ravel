-- Asking each player in turn.
--
-- An offer is a *place*: `show:` moves the cards into one zone and puts an
-- overlay over it, and a game has one of each. So "every player discards one"
-- had nowhere to go. `each_seat:` ran the loop to completion inside a single
-- step, which meant two hands lying in the same pile and one seat picking out
-- of the other's -- and the seat answering was neither of them, because the
-- loop had put the turn back before the overlay was ever drawn.
--
-- The fix is not a word. `show:` writes down the question it cannot open, and
-- settle asks the next one when the last is answered -- the same place a
-- response window is settled, and for the same reason: it is after an action.
-- What is written down is the request, not the cards, so the scope is read again
-- when it opens, against the board the previous answer left.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")
local net     = require("net")
local json    = require("json")

local M = {}

local GAME = [==[{
  "title": "Offer Queue",
  "players": [{ "card": "one" }, { "card": "two" }, { "card": "three" }],
  "stats": [{ "key": "kept", "min": 0, "max": 99, "on": ["player"], "start": 0 }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.75, 0.9, 0.2], [0.05, 0.4, 0.9, 0.2], [0.05, 0.05, 0.9, 0.2]] },
    { "key": "bin", "layout": "stack", "copies": "per_seat", "display": "offscreen" },
    { "key": "rules", "layout": "stack", "display": "offscreen", "use": "none" },
    { "key": "options", "layout": "row", "status": "offer", "display": "offscreen" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "ask" }] },
    { "key": "ask", "type": "automatic",
      "actions": ["each_seat:activate_zone:rules:by_column:sweep"],
      "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "three", "text": "Three", "tags": ["seat_three"] },
    { "key": "chip", "text": "Chip", "tags": ["chip"] },
    { "key": "sweeper", "text": "Everybody discards one", "tags": ["immutable"],
      "abilities": [{ "key": "sweep", "text": "Discard", "action": ["show:mine.hand:optional"] }],
      "chosen": { "action": ["move_target_to:mine.bin", "stat_gain:kept@mine.player:1"] } },
    { "key": "greedy", "text": "Everybody discards, and the first takes the rest", "tags": ["immutable"],
      "abilities": [{ "key": "sweep", "text": "Discard", "action": ["show:mine.hand:optional"] }],
      "chosen": { "action": ["move_target_to:mine.bin", "destroy:everywhere.chip"] } }
  ],
  "setup": { "place": [{ "card": "sweeper", "zone": "rules" }] }
}]==]

local PATH, FILE = "game/games/tmp_offer_queue.json", "tmp_offer_queue.json"

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

-- zones.find only knows "mine" and "enemy", so a named seat is asked for by
-- walking the instances, which come back in seat order.
local function hand_of(s)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == s then return z end
	end
end

local function deal()
	for _, s in ipairs({ "one", "two", "three" }) do
		for _ = 1, 2 do zones.add(hand_of(s), "chip") end
	end
end

-- Take whatever the offer is holding, so the next question comes round.
local function answer()
	local o = zones.find("options")
	return o.cards[1] ~= nil and flow.play_card(o.cards[1], {}) or false
end

-- Three seats, one question each, and each asked of the seat it is about. The
-- old behaviour put all six cards in one pile and asked seat one about them.
function M.test_offer_queue_asks_each_seat_in_turn(check)
	with_game(nil, function(name)
		flow.init(name, 3)
		deal()
		actions.execute("next_phase", {})
		flow.settle()

		local asked = {}
		for _ = 1, 3 do
			local o = zones.find("options")
			check("one question at a time", #o.cards == 2, #o.cards)
			asked[#asked + 1] = zones.active_seat()
			-- What is on the table is that seat's own hand and nobody else's.
			for _, id in ipairs(o.cards) do
				check("holding only the seat's own cards",
					entity.get(id).borrowed_from == hand_of(zones.active_seat()).id)
			end
			answer()
		end
		check("each seat was asked, in order",
			table.concat(asked, ",") == "one,two,three", table.concat(asked, ","))
		check("and each answered for themselves",
			seat("one").stats.kept == 1 and seat("two").stats.kept == 1
			and seat("three").stats.kept == 1,
			("%d/%d/%d"):format(seat("one").stats.kept, seat("two").stats.kept,
				seat("three").stats.kept))
	end)
end

-- The first offer is the one that used to go to the wrong seat, and it is the
-- easiest to miss: it opens where it stands, so nothing was obviously broken --
-- except that `each_seat:` had put the turn back by the time anyone could click.
-- Asked here of a table where somebody other than the first seat is up, which is
-- also where the order of the questions is visible.
function M.test_offer_queue_the_seat_that_asked_is_the_seat_that_answers(check)
	with_game(nil, function(name)
		flow.init(name, 3)
		deal()
		local was = zones.active_seat()
		actions.execute("set_active_seat:seat_three", {})
		local up = zones.active_seat()
		check("somebody other than the first seat is up", up ~= was, up)

		actions.execute("next_phase", {})
		flow.settle()
		local asked = {}
		for _ = 1, 3 do
			asked[#asked + 1] = zones.active_seat()
			answer()
		end
		-- `each_seat:` goes round the table from whoever is up, so naming a seat
		-- before it is how a game says "starting with the player who has
		-- Initiative" -- and the questions arrive in that order.
		check("the questions go round the table from whoever is up",
			table.concat(asked, ",") == "three,one,two", table.concat(asked, ","))
		check("and the turn is handed back afterwards", zones.active_seat() == up,
			zones.active_seat())
	end)
end

-- A queued question is about the board when it is asked, not when it was
-- written down. The card here empties every hand as its answer, so the two
-- questions behind it have nothing to ask about -- and must say so rather than
-- open an overlay over nothing or stall the round.
function M.test_offer_queue_a_waiting_question_reads_the_board_as_it_stands(check)
	local text = GAME:gsub('"card": "sweeper"', '"card": "greedy"')
	with_game(text, function(name)
		flow.init(name, 3)
		deal()
		actions.execute("next_phase", {})
		flow.settle()
		check("seat one is asked", zones.active_seat() == "one", zones.active_seat())
		answer()

		check("the questions behind it found nothing and did not open",
			#zones.find("options").cards == 0, #zones.find("options").cards)
		check("the queue drained rather than stalling",
			zones.find("options").pending == nil)
		check("and the round moved on", phase.current().key == "act", phase.current().key)
	end)
end

-- The queue is plain data on a zone, so it goes wherever the rest of the state
-- goes -- a save, a net message, an undo checkpoint -- with nothing to teach any
-- of them. This is the check that it really is plain: encode, decode, apply.
function M.test_offer_queue_survives_the_wire(check)
	with_game(nil, function(name)
		flow.init(name, 3)
		deal()
		actions.execute("next_phase", {})
		flow.settle()
		check("two questions are waiting", #zones.find("options").pending == 2,
			#zones.find("options").pending)

		local ok, err = net.apply_full(json.decode(json.encode(net.snapshot())))
		check("the state survives an encode/decode/apply", ok, err)
		check("and the queue came with it", #zones.find("options").pending == 2,
			zones.find("options").pending and #zones.find("options").pending or "(gone)")

		answer()
		check("the second seat is asked as if nothing had happened",
			zones.active_seat() == "two", zones.active_seat())
	end)
end

return M
