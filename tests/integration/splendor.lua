-- Splendor, and the one thing about it that looked like a missing capability.
--
-- A development card's price is its printed cost less the buyer's permanent
-- discounts, with gold covering whatever the tokens cannot — three clamped
-- subtractions per colour, which the amount grammar has no min() or max() for.
-- It does not need one: **stat_damage against a floor of zero is max(0, a - b)**,
-- and that is the whole of the arithmetic. These tests are pointed at that,
-- because it is the part a rules summary cannot confirm.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local GEMS = { "white", "blue", "green", "red", "black" }

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function in_zone(zone_key, def_key)
	for _, cid in ipairs((zones.find(zone_key) or {}).cards or {}) do
		local c = entity.get(cid)
		if c.def_key == def_key then return c end
	end
end

local function pile(gem) return in_zone("supply", "pile_" .. gem) end

-- One market card, its price rewritten, against a player dialled to order. The
-- costs are the game's own data everywhere else; here they are set so that a
-- case can be stated rather than hunted for in the deck.
local function priced(cost, bonus, tokens, gold)
	flow.init("splendor.json", 3)
	local me = seat("north")
	for i, k in ipairs(GEMS) do
		me.stats["b_" .. k] = bonus[i] or 0
		me.stats["t_" .. k] = tokens[i] or 0
	end
	me.stats.t_gold = gold or 0
	local c = entity.get(zones.find("t1_row").cards[1])
	for i, k in ipairs(GEMS) do c.stats["cost_" .. k] = cost[i] or 0 end
	actions.execute("activate_zone:t1_row", {})
	return me, c
end

local function take(gem)
	local p = pile(gem)
	for _, u in ipairs(flow.usable_abilities(p.id)) do
		if u.ability.key == "take_" .. gem then return flow.activate(p.id, {}, u.index) end
	end
	return false
end

-- The deck is data, and the point of checking it here rather than in the
-- generator is that the file somebody plays is the one being counted.
function M.test_splendor_the_deck_is_the_published_one(check)
	flow.init("splendor.json", 3)
	local tiers, bonuses, nobles = {}, {}, 0
	for _, def in pairs(require("declaration").G.card_defs) do
		local t, gem = tostring(def.key):match("^t(%d)_(%a+)_%d%d$")
		if t then
			tiers[t] = (tiers[t] or 0) + 1
			bonuses[t .. gem] = (bonuses[t .. gem] or 0) + 1
		end
		if (def.tags_set or {}).noble then nobles = nobles + 1 end
	end
	check("forty tier-one cards", tiers["1"] == 40, tostring(tiers["1"]))
	check("thirty tier-two", tiers["2"] == 30, tostring(tiers["2"]))
	check("twenty tier-three", tiers["3"] == 20, tostring(tiers["3"]))
	check("ten nobles", nobles == 10, tostring(nobles))
	local even = true
	for _, gem in ipairs(GEMS) do
		even = even and bonuses["1" .. gem] == 8 and bonuses["2" .. gem] == 6
			and bonuses["3" .. gem] == 4
	end
	check("eight, six and four of each colour per tier", even)
end

-- The four corners of the price. Every one of them is a subtraction that stops
-- at zero, and the last is the one a game file could not say before: gold is a
-- wildcard, so affordability is about the *total* shortfall and not any colour.
function M.test_splendor_a_price_is_clamped_subtraction(check)
	local _, c = priced({ 0, 0, 0, 3, 1 }, {}, {}, 0)
	check("with nothing at all, the whole cost falls to gold",
		c.stats.gold_due == 4 and c.stats.buyable == 0, tostring(c.stats.gold_due))

	local _, rich = priced({ 0, 0, 0, 3, 1 }, {}, { 9, 9, 9, 9, 9 }, 0)
	check("tokens alone pay the printed price",
		rich.stats.due_red == 3 and rich.stats.due_black == 1
		and rich.stats.gold_due == 0 and rich.stats.buyable == 1)

	local _, free = priced({ 0, 0, 0, 3, 1 }, { 0, 0, 0, 3, 1 }, {}, 0)
	check("discounts that meet the price make it free",
		free.stats.spent == 0 and free.stats.buyable == 1, tostring(free.stats.spent))

	-- The discount is a *reduction of the price*, not a token that gets spent.
	-- Treating it as a token overcharges by the discount, which is the mistake
	-- this arithmetic exists to avoid.
	local _, over = priced({ 0, 0, 0, 3, 0 }, { 0, 0, 0, 9, 0 }, { 0, 0, 0, 2, 0 }, 0)
	check("a discount past the price costs nothing and takes no tokens",
		over.stats.due_red == 0 and over.stats.gold_due == 0 and over.stats.buyable == 1)

	local _, mixed = priced({ 0, 0, 0, 3, 0 }, { 0, 0, 0, 1, 0 }, { 0, 0, 0, 1, 0 }, 1)
	check("otherwise the tokens pay what they can and gold covers the rest",
		mixed.stats.due_red == 1 and mixed.stats.gold_due == 1
		and mixed.stats.spent == 2 and mixed.stats.buyable == 1,
		mixed.stats.due_red .. "/" .. mixed.stats.gold_due)

	local _, broke = priced({ 0, 0, 0, 3, 0 }, { 0, 0, 0, 1, 0 }, { 0, 0, 0, 1, 0 }, 0)
	check("and one gold short is not affordable at all", broke.stats.buyable == 0)
end

-- Buying moves the numbers the pricing worked out. The bank has to get back
-- exactly what left the player, which is why the tokens are counted per colour
-- rather than as one total.
function M.test_splendor_buying_settles_every_number(check)
	local me, c = priced({ 0, 0, 0, 3, 0 }, { 0, 0, 0, 1, 0 }, { 0, 0, 0, 1, 0 }, 1)
	me.stats.t_total = 2
	local red_bank, gold_bank = pile("red").stats.bank, pile("gold").stats.bank
	local gem = c.def_key:match("^t1_(%a+)")
	check("the card is playable", flow.can_play(c.id))
	check("and buying it works", flow.play_card(c.id, {}))

	check("the tokens are gone", me.stats.t_red == 0 and me.stats.t_gold == 0
		and me.stats.t_total == 0)
	check("the bank has them back", pile("red").stats.bank == red_bank + 1
		and pile("gold").stats.bank == gold_bank + 1)
	check("the discount is permanent", me.stats["b_" .. gem] == 1)
	check("and the purchase is counted, for the tiebreak", me.stats.bought == 1)

	local held = entity.get(c.id)
	check("the card is in the buyer's tableau, and theirs",
		entity.get(held.zone_id).key == "tableau" and held.stats.owner == 1)
	-- Nothing prices a bought card again, so this is what stops it being sold
	-- to its owner a second time.
	check("a bought card is no longer for sale", held.stats.buyable == 0
		and not flow.can_play(c.id))
	check("the row filled the hole", #zones.find("t1_row").cards == 4)
	check("and the turn passed", zones.active_seat() == "south")
end

-- Three different colours, or two of one — and the second only while four of
-- that colour remain. Both are gated by an ability's cost, because an ability
-- is gated by its cost and its phase and by nothing else.
function M.test_splendor_taking_tokens(check)
	flow.init("splendor.json", 3)
	local me = seat("north")
	check("one of a colour", take("white") and me.stats.t_white == 1)
	check("and not that colour twice", take("white") == false)
	check("a second colour", take("blue") and me.stats.t_blue == 1)
	check("still your turn", zones.active_seat() == "north")
	check("a third ends it", take("green") and zones.active_seat() == "south")

	flow.init("splendor.json", 3)
	local south = seat("south")
	local function take2(gem)
		local p = pile(gem)
		for _, u in ipairs(flow.usable_abilities(p.id)) do
			if u.ability.key == "take2_" .. gem then return flow.activate(p.id, {}, u.index) end
		end
		return false
	end
	check("two of one colour is a whole turn",
		take2("red") and seat("north").stats.t_red == 2 and zones.active_seat() == "south")
	-- Four in the stack is the rule, and the 2-player supply is exactly four.
	check("but not once the stack is down to three",
		take2("red") == false and south.stats.t_red == 0)
end

-- Reserving is two verbs because the game means two things by it, and the
-- engine already told a deck from a pile for the same reason.
function M.test_splendor_reserving(check)
	flow.init("splendor.json", 3)
	local me   = seat("north")
	local btn  = in_zone("controls", "reserve_button")
	local want = entity.get(zones.find("t2_row").cards[1])
	check("the button takes a face-up card", flow.play_card(btn.id, { want.id }))
	check("into the reserver's own hand", entity.get(want.id).zone_id
		== zones.all_with_key("reserve")[1].id and want.stats.owner == 1)
	check("a slot is spent and a gold earned",
		me.stats.reserve_slots == 2 and me.stats.t_gold == 1 and me.stats.t_total == 1)
	check("the gold came out of the bank", pile("gold").stats.bank == 4)
	check("the row filled the hole", #zones.find("t2_row").cards == 4)

	local deck = zones.find("t3_deck")
	check("a deck reserves its own top card, unseen", flow.activate_zone(deck.id))
	check("into the other seat's hand", #zones.all_with_key("reserve")[2].cards == 1
		and seat("south").stats.reserve_slots == 2)

	me.stats.reserve_slots = 0
	check("and three reserved cards is the limit",
		flow.can_play(in_zone("controls", "reserve_button").id) == false)
end

-- A noble arrives for free the moment the discounts are there, and at most one
-- a turn — which falls out of a phase that ends when something is played in it.
function M.test_splendor_a_noble_visits(check)
	flow.init("splendor.json", 3)
	local me    = seat("north")
	local noble = entity.get(zones.find("nobles").cards[1])
	actions.execute("activate_zone:nobles", {})
	check("nobody qualifies at the start", noble.stats.ok == 0)

	local short_one
	for _, k in ipairs(GEMS) do
		me.stats["b_" .. k] = noble.stats["n_" .. k]
		if noble.stats["n_" .. k] > 0 then short_one = k end
	end
	me.stats["b_" .. short_one] = noble.stats["n_" .. short_one] - 1
	actions.execute("activate_zone:nobles", {})
	check("one discount short is not enough", noble.stats.ok == 0)

	me.stats["b_" .. short_one] = noble.stats["n_" .. short_one]
	actions.execute("activate_zone:nobles", {})
	check("meeting it exactly is", noble.stats.ok == 1)

	me.stats.takes = 1
	flow.play_card(in_zone("controls", "done_button").id, {})
	check("ending a turn stops at the choice", phase.current().key == "noble_pick")
	check("and the noble is claimable", flow.play_card(noble.id, {}))
	check("for three prestige, once", me.stats.score == 3
		and #zones.find("nobles").cards == 2)
	check("then the turn passes", zones.active_seat() == "south")
end

-- Ten tokens at the end of a turn, and the discard is a phase that routes back
-- into itself until the count is right.
function M.test_splendor_the_ten_token_limit(check)
	flow.init("splendor.json", 3)
	local me = seat("north")
	me.stats.t_total, me.stats.t_white, me.stats.takes = 12, 6, 1
	flow.play_card(in_zone("controls", "done_button").id, {})
	check("holding twelve stops the turn", phase.current().key == "discard")

	local function give_back()
		local p = pile("white")
		for _, u in ipairs(flow.usable_abilities(p.id)) do
			if u.ability.key == "back_white" then return flow.activate(p.id, {}, u.index) end
		end
		return false
	end
	local bank = pile("white").stats.bank
	check("one back is not enough", give_back() and phase.current().key == "discard")
	check("two is", give_back() and me.stats.t_total == 10 and zones.active_seat() == "south")
	check("and the bank has them", pile("white").stats.bank == bank + 2)
end

-- Fifteen does not stop the game; everybody finishes the round. The grammar has
-- no "and", so "somebody is done" and "the round is over" are asked one phase
-- apart rather than as one condition.
function M.test_splendor_the_last_round_is_played_out(check)
	flow.init("splendor.json", 3)
	local north, south = seat("north"), seat("south")
	north.stats.score, north.stats.takes = 15, 1
	flow.play_card(in_zone("controls", "done_button").id, {})
	check("reaching fifteen flags the end", north.stats.ending == 1)
	check("but the other seat still gets its turn",
		zones.active_seat() == "south" and phase.current().key == "act")

	south.stats.takes = 1
	flow.play_card(in_zone("controls", "done_button").id, {})
	check("and then the game is over", north.stats.won == 1 and south.stats.won == 0)
	check("with a banner that knows it", flow.outcome() ~= nil)
end

-- Level pegging is broken by fewest cards bought — efficiency over points — and
-- the routing says so in the order it asks.
function M.test_splendor_the_tiebreak(check)
	flow.init("splendor.json", 3)
	local north, south = seat("north"), seat("south")
	north.stats.score, south.stats.score = 15, 15
	north.stats.bought, south.stats.bought = 9, 7
	north.stats.takes = 1
	flow.play_card(in_zone("controls", "done_button").id, {})
	south.stats.takes = 1
	flow.play_card(in_zone("controls", "done_button").id, {})
	check("equal prestige goes to the shorter tableau",
		south.stats.won == 1 and north.stats.won == 0)
end

-- Nobody can be left with nothing to do. A turn always has a legal act while
-- the bank holds a token, and the routing always leads somewhere.
function M.test_splendor_a_scripted_game_never_deadlocks(check)
	flow.init("splendor.json", 3)
	local acted = 0
	for _ = 1, 60 do
		if flow.outcome() then break end
		local moved = false
		-- Buy anything affordable, else take a token, else stop taking.
		for _, zk in ipairs({ "t1_row", "t2_row", "t3_row" }) do
			for _, cid in ipairs(zones.find(zk).cards) do
				if not moved and flow.can_play(cid) then moved = flow.play_card(cid, {}) end
			end
		end
		if not moved then
			for _, gem in ipairs(GEMS) do
				if not moved then moved = take(gem) end
			end
		end
		if not moved then
			local d = in_zone("controls", "done_button")
			if d and flow.can_play(d.id) then moved = flow.play_card(d.id, {}) end
		end
		if not moved then
			local n = zones.find("nobles")
			for _, cid in ipairs(n and n.cards or {}) do
				if not moved and flow.can_play(cid) then moved = flow.play_card(cid, {}) end
			end
		end
		if not moved then break end
		acted = acted + 1
	end
	check("sixty acts went through without a dead end", acted == 60, tostring(acted))
	check("and the phase is one a player can act in",
		phase.current() ~= nil and phase.current().type == "player_input",
		phase.current() and phase.current().key)
end

return M
