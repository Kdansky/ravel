-- "status": "supply" — a shop's shelves, a bank of tokens, the box a game deals
-- from.
--
-- Two games had built it by hand before it existed. Splendor's token piles and
-- Puzzle Strike's bank are the same shape twice, with no shared authoring: a
-- counter card tagged "immutable", carrying its stock as a stat, with the take
-- written as its activate. That is what a missing word in an enum looks like
-- from outside, and this is the word.
--
-- What it says is that the cards in it are **interchangeable**. Sixty-four
-- identical gems differ in nothing a rule may ask about, so the engine keeps one
-- of each as a real card and a number for the rest. The game file writes
-- "gem:64" and never learns that it did not get sixty-four cards — which is only
-- safe because nothing may point at one, so nothing can tell the copies apart.

local entity = require("entity")
local zones = require("zones")
local cards = require("cards")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local targeting = require("targeting")

local M = {}

local GAME = [==[{
  "title": "Supply",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "coin", "min": 0, "max": 99, "on": ["player"], "start": 5, "label": "Coin" },
    { "key": "price", "min": 0, "max": 99, "label": "Price" },
    { "key": "stock", "min": 0, "max": 99, "label": "Left" }],
  "zones": [
    { "key": "shop", "layout": "grid", "grid": [3, 1], "status": "supply", "use": "abilities",
      "applies": ["for_sale"], "contents": ["gem:64", "relic:2"],
      "pos": [0.05, 0.05, 0.9, 0.3] },
    { "key": "table", "layout": "grid", "grid": [3, 1], "pos": [0.05, 0.4, 0.9, 0.25] },
    { "key": "hand", "layout": "row", "copies": "per_seat", "pos": [0.05, 0.7, 0.9, 0.25] }],
  "phases": [{ "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "tags": {
    "for_sale": { "abilities": [
      { "key": "buy", "text": "Buy it", "merge": "this",
        "cost": { "coin@mine.player": "price@self", "stock@self": 1 },
        "action": ["fill:mine.hand:@self:1"] }] }
  },
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "gem", "text": "Gem", "tags": ["thing", "gem"], "card_stats": { "value": 1, "price": 1 } },
    { "key": "relic", "text": "Relic", "tags": ["thing", "relic"], "card_stats": { "value": 5, "price": 3 } },
    { "key": "idol", "text": "Idol", "tags": ["thing", "relic"], "card_stats": { "value": 9, "price": 3 } }
  ],
  "setup": { "place": [{ "card": "idol", "zone": "table", "at": ["a1"] }] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_supply.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_supply.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function shelf(def_key)
	for _, id in ipairs(zones.find("shop").cards) do
		local e = entity.get(id)
		if e.def_key == def_key then return e end
	end
end

local function count_in(key, def_key)
	local n = 0
	for _, z in ipairs(zones.all_with_key(key)) do
		for _, id in ipairs(z.cards or {}) do
			if def_key == nil or entity.get(id).def_key == def_key then n = n + 1 end
		end
	end
	return n
end

-- Sixty-six cards were declared and two entities exist. Everything else about
-- them is a number.
function M.test_supply_declares_a_count_and_keeps_one_card(check)
	with_game(function(name)
		flow.init(name, 3)
		check("one entity per kind, not per card", count_in("shop") == 2, tostring(count_in("shop")))
		check("and the number is on it",
			shelf("gem").stats.stock == 64 and shelf("relic").stats.stock == 2,
			shelf("gem").stats.stock .. " / " .. shelf("relic").stats.stock)
		-- The point of the whole thing: 66 cards' worth of game, 2 cards' worth
		-- of everything the engine has to carry.
		local live = 0
		for e in entity.each("card") do if e.def_key == "gem" then live = live + 1 end end
		check("sixty-four gems, one of them real", live == 1, tostring(live))
	end)
end

-- Every existing way of putting a card somewhere lands right without knowing.
function M.test_supply_counts_whatever_is_added_to_it(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "fill:shop:gem:6" }, {})
		check("filling a supply raises the number", shelf("gem").stats.stock == 70,
			tostring(shelf("gem").stats.stock))
		check("and mints no cards", count_in("shop") == 2)

		actions.run({ "fill:shop:idol:1" }, {})
		check("a kind it did not have gets its own card",
			count_in("shop") == 3 and shelf("idol").stats.stock == 1)
		-- A number has no capacity, so the grid's three cells never run out —
		-- a supply of four kinds in a [3,1] would, which is a layout question
		-- and not this one.
		actions.run({ "fill:shop:idol:99" }, {})
		check("and it keeps counting past any room a layout has",
			shelf("idol").stats.stock == 100, tostring(shelf("idol").stats.stock))
	end)
end

-- Nothing may point at one, and that is what makes the count safe: a rule that
-- could tell two gems apart would find out there is only one.
function M.test_supply_cards_cannot_be_targeted(check)
	with_game(function(name)
		flow.init(name, 3)
		local spec = { type = "card", tags = { "thing" }, owner = "anyone", count = 1 }
		local found = {}
		for _, id in ipairs(targeting.candidates(shelf("gem").id, spec)) do
			found[#found + 1] = entity.get(id).def_key
		end
		check("the idol on the table is a candidate", #found == 1 and found[1] == "idol",
			table.concat(found, ", "))
		check("and neither shelf is", not table.concat(found, ","):find("gem"))
	end)
end

-- Not in play either: a supply is stock, so a bare tag scope walks past it the
-- way it walks past a hand.
function M.test_supply_is_not_in_play(check)
	with_game(function(name)
		flow.init(name, 3)
		check("a bare tag sees the table and not the shelves",
			predicate.total("count:thing", {}) == 1, tostring(predicate.total("count:thing", {})))
		check("naming the zone still reaches it, as naming a zone always has",
			predicate.total("count:thing@shop", {}) == 2)
		check("and so does the pair", predicate.total("count:gem@shop.gem", {}) == 1)
	end)
end

-- The shop sells what it is: the stock is spent as a cost and a fresh card is
-- made at the destination, so the card on the shelf never moves.
function M.test_supply_selling_spends_the_count(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = shelf("gem")
		check("it is clickable, because use said abilities",
			#flow.usable_abilities(g.id) == 1, tostring(#flow.usable_abilities(g.id)))
		check("and buying works", flow.activate(g.id, {}, 1))
		check("the count went down", g.stats.stock == 63, tostring(g.stats.stock))
		check("a gem arrived", count_in("hand", "gem") == 1)
		check("the shelf kept its card", shelf("gem") ~= nil and count_in("shop") == 2)

		local bought
		for _, z in ipairs(zones.all_with_key("hand")) do
			for _, id in ipairs(z.cards) do bought = entity.get(id) end
		end
		check("and what arrived is a fresh card, not the shelf's",
			bought.id ~= g.id and bought.stats.stock == nil,
			tostring(bought.id) .. " vs " .. tostring(g.id))
	end)
end

-- An empty shelf still has a card, which is what lets a game count how many of
-- them have run out — the thing a heap of real cards could never answer, since
-- an absence carries no tag.
function M.test_supply_an_empty_shelf_is_still_something(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "stat_set:stock@shop.relic:0" }, {})
		check("the card stays when the stock is gone", shelf("relic") ~= nil)
		check("so it can be counted", predicate.total("count:relic@shop", {}) == 1)
		check("and it cannot be bought", not flow.activate(shelf("relic").id, {}, 1))
		check("while its neighbour still can", flow.activate(shelf("gem").id, {}, 1))
	end)
end

-- A shared buy cannot type a price: the ability lives on the tag the zone hands
-- out, and every shelf wants a different number. So the cost is measured off the
-- card being bought, which is the same "price@self" a rule elsewhere already
-- reads to say "costing one more than the chip you trashed".
function M.test_supply_a_shared_buy_prices_itself_off_the_shelf(check)
	with_game(function(name)
		flow.init(name, 3)
		local seat
		for e in entity.each("card") do if e.def_key == "one" then seat = e end end
		check("the purse opens at five", seat.stats.coin == 5)

		check("a gem costs its own one", flow.activate(shelf("gem").id, {}, 1))
		check("and one is what was paid", seat.stats.coin == 4, tostring(seat.stats.coin))

		check("a relic costs its own three", flow.activate(shelf("relic").id, {}, 1))
		check("and three is what was paid", seat.stats.coin == 1, tostring(seat.stats.coin))

		-- The refusal is the half that matters: a measured cost that could not be
		-- afforded has to fail the same way a typed one does.
		check("with one coin left the relic refuses", not flow.activate(shelf("relic").id, {}, 1))
		check("and its stock is untouched", shelf("relic").stats.stock == 1,
			tostring(shelf("relic").stats.stock))
		check("while the gem still sells", flow.activate(shelf("gem").id, {}, 1))
	end)
end

-- An offer borrows the *real* card, and in a supply the real card is a whole
-- shelf. A stack lent to a question has to come back as deep as it left, or
-- declining an offer quietly empties the box.
function M.test_supply_a_shelf_lent_to_an_offer_comes_home_whole(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the shelf starts deep", shelf("gem").stats.stock == 64)
		actions.run({ "show:shop:optional" }, {})
		check("the offer borrowed the real cards", count_in("shop") == 0)
		check("and it is the shelf that is standing in it",
			#zones.find("options").cards == 2, tostring(#zones.find("options").cards))

		flow.dismiss_offer()
		check("declining sends them home", count_in("shop") == 2, tostring(count_in("shop")))
		check("with the whole stock, not one of it", shelf("gem").stats.stock == 64,
			tostring(shelf("gem").stats.stock))
		check("and the other shelf too", shelf("relic").stats.stock == 2)
	end)
end

-- The other direction: an ordinary card put into the box is worth one, however
-- it got there.
function M.test_supply_an_ordinary_card_put_back_is_worth_one(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "fill:table:gem:1" }, {})
		local loose
		for _, id in ipairs(zones.find("table").cards) do
			if entity.get(id).def_key == "gem" then loose = entity.get(id) end
		end
		check("a loose gem exists and carries no stock", loose and loose.stats.stock == nil)
		zones.move_card(loose.id, zones.find("shop").id)
		check("putting it in the box raises the number by one",
			shelf("gem").stats.stock == 65, tostring(shelf("gem").stats.stock))
		check("and does not leave a second gem lying there", count_in("shop", "gem") == 1)
	end)
end

return M
