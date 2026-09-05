-- Where a card came from, and how it gets back there.
--
-- "Send it back" was the one move the format could not make. Every destination
-- word names one place — a zone, or the slot a player pointed at — and that is
-- exactly wrong for a set of cards gathered from all over: a duel pulls a unit
-- out of one of ten zones and the survivor has to return to the one it left,
-- not to the one its neighbour left. Nothing recorded which.
--
-- So the engine records it, on every move, and "origin" reads it back. It is a
-- destination and never a source, because it is a different place for every
-- card: the whole reason the word exists is that one line sends each of them
-- somewhere else.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")
local net     = require("net")

local M = {}

local GAME = [==[{
  "title": "Origin",
  "players": [{ "card": "one" }],
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "north", "layout": "stack", "pos": [0.10, 0.10, 0.20, 0.25] },
    { "key": "south", "layout": "stack", "pos": [0.30, 0.10, 0.40, 0.25] },
    { "key": "duel", "layout": "stack", "pos": [0.55, 0.40, 0.65, 0.55] },
    { "key": "posts", "layout": "grid", "grid": [3, 1], "pos": [0.20, 0.40, 0.50, 0.55] },
    { "key": "bin", "layout": "stack", "pos": [0.80, 0.10, 0.90, 0.25] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "alpha", "text": "Alpha", "tags": ["letter"] },
    { "key": "beta", "text": "Beta", "tags": ["letter"] },
    { "key": "gamma", "text": "Gamma", "tags": ["letter"] },
    { "key": "sender", "text": "Sender",
      "play": { "target": { "type": "card", "zones": ["duel"], "count": 1 },
        "action": ["move:target:origin"] } }
  ],
  "setup": {
    "place": [
      { "card": "alpha", "zone": "north" },
      { "card": "beta", "zone": "south" },
      { "card": "gamma", "zone": "bin" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_origin.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_origin.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function where(key)
	local e = find(key)
	local z = e and e.zone_id and entity.get(e.zone_id)
	return z and z.key or "nowhere"
end

-- Two cards pulled from two zones, sent home by one line. This is the whole
-- idea: "origin" is not a place, it is a different place per card.
function M.test_origin_sends_each_card_somewhere_else(check)
	with_game(function(name)
		flow.init(name, 3)
		local duel = zones.find_id("duel")
		zones.move_card(find("alpha").id, duel)
		zones.move_card(find("beta").id, duel)
		check("both are in the duel", where("alpha") == "duel" and where("beta") == "duel")

		actions.execute("move:duel:origin", {})
		check("alpha went back north", where("alpha") == "north", where("alpha"))
		check("beta went back south", where("beta") == "south", where("beta"))
		check("and the duel is empty", #zones.find("duel").cards == 0)
	end)
end

-- Immediately before, not "where this lives". A card that has been round the
-- houses remembers only the last leg.
function M.test_origin_is_the_last_place_and_not_a_home(check)
	with_game(function(name)
		flow.init(name, 3)
		local a = find("alpha").id
		zones.move_card(a, zones.find_id("hand"))
		zones.move_card(a, zones.find_id("duel"))
		actions.execute("move_to:origin", { card_id = a })
		check("it goes back to the hand it last left", where("alpha") == "hand", where("alpha"))
	end)
end

-- A card dealt at setup and never moved has no origin at all, and nothing
-- invents one for it.
function M.test_origin_a_card_that_never_moved_stays_put(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.execute("move_to:origin", { card_id = find("gamma").id })
		check("it is where it was dealt", where("gamma") == "bin", where("gamma"))
	end)
end

-- Going home from home is not a move, so a rule that sends a whole zone back
-- does not shuffle the ones already there.
function M.test_origin_from_where_it_already_is_does_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local a = find("alpha").id
		-- A move that goes nowhere, which is what makes north its own origin.
		zones.move_card(a, zones.find_id("north"))
		actions.execute("move_to:origin", { card_id = a })
		check("it stays where it stands", where("alpha") == "north", where("alpha"))
		check("and it is still the only card there", #zones.find("north").cards == 1)
	end)
end

-- Every op that names a destination takes it, so a rule does not have to pick
-- its verb by which cards it can reach.
function M.test_origin_every_destination_op_takes_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local duel = zones.find_id("duel")

		local a = find("alpha").id
		zones.move_card(a, duel)
		actions.execute("move_to:origin", { card_id = a })
		check("move_to", where("alpha") == "north", where("alpha"))

		local b = find("beta").id
		zones.move_card(b, duel)
		actions.execute("move:target:origin", { targets = { b } })
		check("move:target", where("beta") == "south", where("beta"))

		local g = find("gamma").id
		zones.move_card(g, duel)
		actions.execute("move:duel:origin", {})
		check("move, by scope", where("gamma") == "bin", where("gamma"))
	end)
end

-- On a grid, where it came from is a *square*. A fight that pulls three
-- patrollers out of a row has to put each one back in its own post, and the
-- zone alone cannot say which.
function M.test_origin_remembers_the_square(check)
	with_game(function(name)
		flow.init(name, 3)
		local posts = zones.find("posts")
		zones.place_in_slot(find("alpha").id, posts.slots[1])
		zones.place_in_slot(find("beta").id, posts.slots[3])
		local third = entity.get(posts.slots[3])
		check("beta is in the third post", entity.get(find("beta").id).slot_id == third.id)

		local duel = zones.find_id("duel")
		zones.move_card(find("beta").id, duel)
		actions.execute("move:duel:origin", {})
		check("it went back to the third and not the first free one",
			entity.get(find("beta").id).slot_id == third.id)
	end)
end

-- A post somebody else has taken is not one to evict them from.
function M.test_origin_gives_way_to_whoever_took_the_post(check)
	with_game(function(name)
		flow.init(name, 3)
		local posts = zones.find("posts")
		zones.place_in_slot(find("alpha").id, posts.slots[2])
		zones.move_card(find("alpha").id, zones.find_id("duel"))
		zones.place_in_slot(find("beta").id, posts.slots[2])

		actions.execute("move:duel:origin", {})
		check("beta kept the post", entity.get(find("beta").id).slot_id == posts.slots[2])
		check("and alpha still came home to the zone", where("alpha") == "posts", where("alpha"))
	end)
end

-- It is entity state like any other, so it has to survive the wire and a save.
function M.test_origin_survives_a_round_trip(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.move_card(find("alpha").id, zones.find_id("duel"))
		local snap = net.snapshot()

		flow.init("menu.json", 3)
		net.apply_full(snap)
		actions.execute("move:duel:origin", {})
		check("it still knows where it came from", where("alpha") == "north", where("alpha"))
	end)
end

return M
