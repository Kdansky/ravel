-- `take` — a move out of a box.
--
-- A supply keeps one card per kind and writes the rest on it as a number, so
-- there is nothing in there to pick up: the card standing on the shelf *is* the
-- stack. A component leaving the box was therefore a `fill` that conjured it
-- beside a decrement that paid for it — two statements a game file can put out
-- of step, with nothing tying them together, which is why a gem arrived in the
-- other player's pile out of nowhere and the presentation had to guess which
-- box it came from.
--
-- The one place a scope names the source rather than what moves. That inversion
-- is the argument for a verb of its own: two spellings that read alike and mean
-- opposite things would be worse than two words.
--
-- A shelf lent to an offer is still the shelf — `zones.supply_home` asks where it
-- belongs rather than where it is standing — which is what lets a card offer the
-- bank and take out of the pick. Puzzle Strike's Training Day is the test of that.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")
local predicate = require("predicate")

local M = {}

local GAME = [==[{
  "title": "Take",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "stock", "min": 0, "max": 99, "label": "Left" },
    { "key": "seen", "min": 0, "max": 99, "on": ["player"], "start": 0, "label": "Seen" }],
  "zones": [
    { "key": "bank", "layout": "grid", "grid": [3, 1], "status": "supply",
      "contents": ["gem_1:5", "gem_2:1", "wound:1"], "pos": [0.05, 0.05, 0.9, 0.3] },
    { "key": "vault", "layout": "grid", "grid": [3, 1], "status": "supply", "pos": [0.05, 0.4, 0.4, 0.2] },
    { "key": "pile", "layout": "stack", "pos": [0.5, 0.4, 0.2, 0.2] },
    { "key": "hand", "layout": "row", "on_receive": ["stat_gain:seen@mine.player:1"],
      "pos": [0.05, 0.7, 0.9, 0.25] }],
  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "gem_1", "text": "One Gem", "tags": ["gem", "gem_1"] },
    { "key": "gem_2", "text": "Two Gem", "tags": ["gem", "gem_2"] },
    { "key": "wound", "text": "Wound", "tags": ["wound"] },
    { "key": "rock", "text": "Rock", "tags": ["rock"] }
  ],
  "setup": { "place": [{ "card": "rock", "zone": "pile" }] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_take.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_take.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function shelf(def_key)
	for _, id in ipairs(zones.find("bank").cards) do
		local e = entity.get(id)
		if e.def_key == def_key then return e end
	end
end

local function count(zone_key, def_key)
	local n = 0
	for _, id in ipairs(zones.find(zone_key).cards) do
		if not def_key or entity.get(id).def_key == def_key then n = n + 1 end
	end
	return n
end

local function order(zone_key)
	local out = {}
	for _, id in ipairs(zones.find(zone_key).cards) do out[#out + 1] = entity.get(id).def_key end
	return table.concat(out, ",")
end

function M.test_take_moves_the_count_out_of_the_box(check)
	with_game(function(name)
		flow.init(name, 1)
		check("the box starts with five", shelf("gem_1").stats.stock == 5)
		actions.execute("take:bank.gem_1:pile:2", {})
		check("two real cards arrived", count("pile", "gem_1") == 2)
		check("and the box is two lighter", shelf("gem_1").stats.stock == 3)
		check("the shelf itself stayed put", count("bank", "gem_1") == 1)
	end)
end

function M.test_take_defaults_to_one(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("take:bank.gem_1:pile", {})
		check("one came out", count("pile", "gem_1") == 1)
		check("and one was paid for", shelf("gem_1").stats.stock == 4)
	end)
end

function M.test_a_short_shelf_hands_over_what_it_has(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("take:bank.gem_2:pile:4", {})
		check("one is what there was", count("pile", "gem_2") == 1)
		check("and the shelf is empty rather than owing", shelf("gem_2").stats.stock == 0)
	end)
end

function M.test_an_empty_shelf_says_nothing(check)
	with_game(function(name)
		flow.init(name, 1)
		-- An empty box is a legal state and a game counts the stacks that have
		-- run out, so this is not a mistake and must not read as one.
		actions.execute("take:bank.wound:pile:1", {})
		actions.execute("take:bank.wound:pile:1", {})
		check("the one there was came out, and no more", count("pile", "wound") == 1)
		check("and the shelf is still standing to be counted", count("bank", "wound") == 1)
	end)
end

function M.test_every_shelf_in_scope_hands_over_its_own(check)
	with_game(function(name)
		flow.init(name, 1)
		-- The same rule `fill` follows: a wider scope deals a set rather than
		-- picking a winner out of it.
		actions.execute("take:bank.gem:pile:1", {})
		check("one of each kind that had any", count("pile", "gem_1") == 1 and count("pile", "gem_2") == 1)
		check("both shelves paid", shelf("gem_1").stats.stock == 4 and shelf("gem_2").stats.stock == 0)
	end)
end

function M.test_the_card_remembers_the_box_it_came_out_of(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("take:bank.gem_1:pile:1", {})
		local id = zones.find("pile").cards[#zones.find("pile").cards]
		check("its origin is the bank, not nowhere",
			entity.get(id).origin_zone_id == zones.find("bank").id)
	end)
end

function M.test_a_position_still_reads_where_a_count_would_go(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("take:bank.gem_1:pile:bottom", {})
		check("it went under the rock", order("pile") == "gem_1,rock")
		check("and only one came out", shelf("gem_1").stats.stock == 4)
	end)
end

function M.test_a_count_and_then_a_position(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("take:bank.gem_1:pile:2:bottom", {})
		check("two, buried", order("pile") == "gem_1,gem_1,rock")
	end)
end

function M.test_arriving_is_an_arrival(check)
	with_game(function(name)
		flow.init(name, 1)
		-- It is a move, so a zone that answers what lands in it answers this.
		actions.execute("take:bank.gem_1:hand:2", {})
		check("two arrivals were counted", count("hand") == 2)
		local one = entity.get(zones.find("hand").cards[1])
		check("and the card is real, off its own template", one.def_key == "gem_1")
		check("the zone's own on_receive ran once per card",
			predicate.total("sum:seen@mine.player", {}) == 2)
	end)
end

function M.test_a_box_passing_to_another_box_moves_a_number(check)
	with_game(function(name)
		flow.init(name, 1)
		actions.execute("take:bank.gem_1:vault:3", {})
		check("the bank paid three", shelf("gem_1").stats.stock == 2)
		local kept
		for _, id in ipairs(zones.find("vault").cards) do kept = entity.get(id) end
		check("and the vault holds one card standing for three",
			kept and kept.def_key == "gem_1" and kept.stats.stock == 3)
	end)
end

function M.test_a_scope_of_ordinary_cards_is_refused(check)
	with_game(function(name)
		flow.init(name, 1)
		-- A rock in a pile is a card, and moving it is what `move` is for. Saying
		-- so out loud beats silently doing nothing to it.
		local said
		local real = print
		print = function(s) said = tostring(s) end
		actions.execute("take:pile.rock:hand:1", {})
		print = real
		check("it named the verb that would have worked", said and said:find("move", 1, true) ~= nil)
		check("and nothing moved", count("hand") == 0)
	end)
end

return M
