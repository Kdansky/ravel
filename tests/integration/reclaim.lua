-- Where a destroyed card goes.
--
-- `destroy:` means "take this out of play", and for a component that is not the
-- same as leaving the game: a gem taken off a pile is still a gem the bank owns.
-- Every game with a finite box therefore named the bank at every site that
-- removed one — a destroy beside a `stat_gain:stock`, two statements that can
-- drift, and a box that leaks the day one site forgets.
--
-- No new word. A supply's shelves are already the game's statement of what it
-- stocks, so the kind is looked up against them and nothing is said twice.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Reclaim",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "stock", "min": 0, "max": 99, "label": "Left" }],
  "zones": [
    { "key": "bank", "layout": "grid", "grid": [3, 1], "status": "supply",
      "contents": ["gem_1:5", "gem_2:1"], "pos": [0.05, 0.05, 0.9, 0.2] },
    { "key": "crate", "layout": "grid", "grid": [2, 1], "status": "supply", "copies": "per_seat",
      "contents": ["gem_1:2"], "pos": [[0.05, 0.3, 0.4, 0.15], [0.55, 0.3, 0.4, 0.15]] },
    { "key": "pile", "layout": "stack", "pos": [0.4, 0.5, 0.2, 0.15] },
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.05, 0.7, 0.4, 0.25], [0.55, 0.7, 0.4, 0.25]] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "gem_1", "text": "One Gem", "tags": ["gem", "gem_1"] },
    { "key": "gem_2", "text": "Two Gem", "tags": ["gem", "gem_2"] },
    { "key": "rock", "text": "Rock", "tags": ["rock"] }
  ],
  "setup": {
    "place": [
      { "card": "gem_1", "zone": "hand" },
      { "card": "rock", "zone": "pile" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_reclaim.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_reclaim.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- The shelf of a kind in a named box, and for a per-seat box the copy belonging
-- to that seat.
local function shelf(zone_key, def_key, seat)
	for _, z in ipairs(zones.all_with_key(zone_key)) do
		if z.seat == seat then
			for _, id in ipairs(z.cards) do
				local e = entity.get(id)
				if e.def_key == def_key then return e end
			end
		end
	end
end

local function stock(zone_key, def_key, seat)
	local e = shelf(zone_key, def_key, seat)
	return e and e.stats.stock or 0
end

local function first_in(zone_key, seat)
	for _, z in ipairs(zones.all_with_key(zone_key)) do
		if z.seat == seat then return entity.get(z.cards[1]) end
	end
end

function M.test_a_destroyed_component_goes_back_in_its_box(check)
	with_game(function(name)
		flow.init(name, 2)
		actions.execute("take:bank.gem_2:pile:1", {})
		check("one out of the box", stock("bank", "gem_2") == 0, stock("bank", "gem_2"))
		actions.execute("destroy:pile.gem_2", {})
		check("and one back in", stock("bank", "gem_2") == 1, stock("bank", "gem_2"))
		check("with no card left over", #zones.find("pile").cards == 1)
	end)
end

function M.test_a_card_no_box_stocks_stops_existing(check)
	with_game(function(name)
		flow.init(name, 2)
		local rock = first_in("pile")
		actions.execute("destroy:pile.rock", {})
		check("the rock is gone", entity.get(rock.id).zone_id == nil)
		check("and nothing grew to hold it", stock("bank", "gem_1") == 5, stock("bank", "gem_1"))
	end)
end

function M.test_the_owners_own_box_is_asked_first(check)
	with_game(function(name)
		flow.init(name, 2)
		local mine = first_in("hand", "one")
		zones.destroy_card(mine.id)
		check("it went home to its owner's crate", stock("crate", "gem_1", "one") == 3,
			stock("crate", "gem_1", "one"))
		check("not the other seat's", stock("crate", "gem_1", "two") == 2, stock("crate", "gem_1", "two"))
		check("and not the shared bank", stock("bank", "gem_1") == 5, stock("bank", "gem_1"))
	end)
end

function M.test_a_card_nobody_owns_goes_to_the_shared_box(check)
	with_game(function(name)
		flow.init(name, 2)
		zones.take(shelf("crate", "gem_1", "one"), zones.find("pile").id)
		-- Out of a seat's crate, into a zone with no owner: it comes back to the
		-- bank, because the question asked is who owns it *now*.
		local n = stock("bank", "gem_1")
		actions.execute("destroy:pile.gem_1", {})
		check("the shared box took it", stock("bank", "gem_1") == n + 1, stock("bank", "gem_1"))
	end)
end

function M.test_a_shelf_does_not_reclaim_itself(check)
	with_game(function(name)
		flow.init(name, 2)
		local face = shelf("bank", "gem_1")
		zones.destroy_card(face.id)
		check("the box lost the kind rather than getting deeper", shelf("bank", "gem_1") == nil)
		check("and the shelf is off the table", entity.get(face.id).zone_id == nil)
	end)
end

function M.test_a_stack_comes_back_as_deep_as_it_left(check)
	with_game(function(name)
		flow.init(name, 2)
		-- What an offer does: it borrows the real shelf, stock and all, so the
		-- card standing outside the box is worth every one of them.
		local lent = first_in("hand", "one")
		lent.stats.stock = 3
		zones.destroy_card(lent.id)
		check("all three went back", stock("crate", "gem_1", "one") == 5, stock("crate", "gem_1", "one"))
	end)
end

function M.test_a_move_into_a_box_still_counts_once(check)
	with_game(function(name)
		flow.init(name, 2)
		zones.move_card(first_in("hand", "one").id, zones.find("bank").id)
		check("the bank went up by one and not by two", stock("bank", "gem_1") == 6, stock("bank", "gem_1"))
		check("and the crate it might have gone to is untouched",
			stock("crate", "gem_1", "one") == 2, stock("crate", "gem_1", "one"))
	end)
end

return M
