-- A seat the engine plays.
--
-- The move list was the terminator's for as long as its only caller was a test;
-- it is an interface's now, and an interface has to offer everything a player
-- could click. What it was missing is what stalled it: a response window, a
-- place with an ability, and a card whose zone the phase never names.
--
-- The turn gate is the other half. Claiming a seat is how the opponent's hand
-- is hidden, and it was also what forbade the opponent from moving.

local entity   = require("entity")
local zones    = require("zones")
local flow     = require("flow")
local net      = require("net")
local opponent = require("opponent")

local M = {}

local GAME = [==[{
  "title": "Engine Seat",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "loot", "label": "Loot", "subject": "loot@mine.player" }],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "deck", "layout": "stack", "visibility": "secret",
      "pos": [0.80, 0.40, 0.90, 0.60],
      "abilities": [{ "action": ["draw_from:deck:hand:1"] }],
      "contents": ["coin:6"] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "next": [{ "then": "act" }] }],
  "tags": { "loud": { "emits": { "play": "shout" } } },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "loot": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "loot": 0 } },
    { "key": "coin", "text": "Coin", "play": { "action": ["stat_gain:loot@mine.player:1"] } },
    { "key": "horn", "text": "Horn", "tags": ["loud"],
      "play": { "action": ["stat_gain:loot@mine.player:1"], "spent": "mine.table" } },
    { "key": "envy", "text": "Envy",
      "reactions": [{ "to": "shout", "action": ["stat_gain:loot@mine.player:5"], "spent": "mine.table" }] }
  ],
  "setup": {
    "place": [
      { "card": "one", "owner": "one", "zone": "table" },
      { "card": "two", "owner": "two", "zone": "table" }
    ]
  }
}]==]

local PATH, FILE = "game/games/tmp_engine_seat.json", "tmp_engine_seat.json"
-- The same game under a second name, seats and all: what a claim outliving its
-- game looks like when the next game has a seat of the same name.
local PATH2, FILE2 = "game/games/tmp_engine_seat_two.json", "tmp_engine_seat_two.json"

local function with_game(fn)
	local f = assert(io.open(PATH, "w"))
	f:write(GAME)
	f:close()
	local g = assert(io.open(PATH2, "w"))
	g:write(GAME)
	g:close()
	local ok, err = pcall(fn, FILE, FILE2)
	os.remove(PATH)
	os.remove(PATH2)
	net.claim_seat(nil)
	opponent.leave()
	if not ok then error(err, 0) end
end

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == seat then return z end
	end
end

local function seat_card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- Step 2 itself: a seat nobody is sitting at plays by itself, and only when it
-- is that seat's turn.
function M.test_opponent_plays_its_own_turn_and_no_other(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		zones.add(zone_of("hand", "two"), "coin")
		check("nothing moves while no seat is the engine's", not opponent.act())
		opponent.take("two")
		check("and none while the other seat is up", not opponent.act())
		check("the loot is untouched", seat_card("two").stats.loot == 0)
		require("actions").execute("set_active_seat:owner_of.target",
			{ targets = { seat_card("two").id } })
		check("the engine plays when its own seat is up", opponent.act())
		check("and it moved for itself and not the other seat",
			seat_card("one").stats.loot == 0, tostring(seat_card("one").stats.loot))
	end)
end

-- Claiming a seat is how the opponent's hand is hidden, so it must not be what
-- stops the opponent playing. The gate is about the human at this screen.
function M.test_opponent_moves_through_a_claimed_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		local theirs = zones.add(zone_of("hand", "two"), "coin")
		net.claim_seat("one")
		opponent.take("two")
		require("actions").execute("set_active_seat:owner_of.target",
			{ targets = { seat_card("two").id } })
		check("a human may not move for the seat they are not in",
			not flow.play_card(theirs.id, {}))
		check("but the engine seat still moves", opponent.act())
	end)
end

-- A claim belongs to the game it was made in. Two games with the same seat
-- names is the case a name check would miss, and both of these are one and two.
function M.test_opponent_a_claim_does_not_outlive_its_game(check)
	with_game(function(name, other)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		net.claim_seat("two")
		check("a seat that is not up may not act",
			not flow.play_card(zone_of("hand", "one").cards[1], {}))
		flow.init(other, 3)
		zones.add(zone_of("hand", "one"), "coin")
		check("and another game is not held by the old claim",
			flow.play_card(zone_of("hand", "one").cards[1], {}))
	end)
end

-- Everything a player could click, which the hand-only list was not: a place
-- with an ability is a move, and it was the commonest thing the old list missed.
function M.test_opponent_offers_a_place(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		zones.add(zone_of("hand", "one"), "horn")
		check("the deck offers one", #flow.usable_zone_abilities(zones.find("deck").id) == 1)
		check("and the list is the hand plus the place", #opponent.legal() == 3,
			tostring(#opponent.legal()))
	end)
end

-- A window is answerable, and a window nobody wants to answer still closes:
-- passing is always on the list. Without it a seat with no reaction sat there
-- for ever, which is what stalled Spellstorm.
function M.test_opponent_answers_a_window(check)
	with_game(function(name)
		flow.init(name, 3)
		local horn = zones.add(zone_of("hand", "one"), "horn")
		zones.add(zone_of("hand", "two"), "envy")
		flow.play_card(horn.id, {})
		check("the window opened for the other seat", zones.active_seat() == "two",
			zones.active_seat())
		local moves = opponent.legal()
		check("which is the answer and the pass", #moves == 2, tostring(#moves))

		opponent.take(zones.active_seat())
		for _ = 1, 8 do
			if not flow.pending_event() then break end
			opponent.act()
		end
		check("and an engine seat always closes one it is handed",
			flow.pending_event() == nil)
	end)
end

-- Standing up again.
function M.test_opponent_leaves_the_seat_when_told(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.add(zone_of("hand", "one"), "coin")
		opponent.take("one")
		check("it is the engine's turn", opponent.act())
		opponent.leave()
		check("and nobody's once it stands up", not opponent.act())
	end)
end

return M
