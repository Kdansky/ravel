-- Puzzle Strike, and the four things it asks for that no game before it did.
--
-- A character chosen before the board exists, which is a draft over a shared
-- roster where the pick is what deals your deck. Two personal piles rather than
-- one — a bag that cycles and a gem pile that never does. A reshuffle that
-- happens *mid-draw*, which is a loop of phases because an action list cannot
-- branch. And a loss condition asked only at the end of your own turn, so that
-- sitting above ten in the middle of it is legal and is the whole tactical
-- layer.
--
-- These tests are pointed at those four and at the arithmetic underneath them,
-- because the rest is content and the validator already reads it.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")

local M = {}

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if seat == nil or z.seat == seat then return z end
	end
end

local function keys_in(key, seat)
	local z, out = zone_of(key, seat), {}
	for i, id in ipairs((z or {}).cards or {}) do out[i] = entity.get(id).def_key end
	return out
end

local function count_in(key, seat, def_key)
	local n = 0
	for _, k in ipairs(keys_in(key, seat)) do
		if def_key == nil or k == def_key then n = n + 1 end
	end
	return n
end

local function find_in(key, def_key, seat)
	for _, id in ipairs((zone_of(key, seat) or {}).cards or {}) do
		local c = entity.get(id)
		if c.def_key == def_key then return c end
	end
end

local function loose(def_key)
	for e in entity.each("card") do
		if e.def_key == def_key and e.zone_id then return e end
	end
end

local function seat_card(seat)
	for e in entity.each("card") do if e.def_key == seat then return e end end
end

-- Two seats and two characters, stopping at the first player's action phase.
local function opening(seed, first, second)
	flow.init("puzzle_strike.json", seed or 7)
	flow.play_card(find_in("roster", "char_" .. (first or "jaina")).id, {})
	flow.play_card(find_in("roster", "char_" .. (second or "setsuki")).id, {})
end

-- Nothing about a character exists until somebody picks it: the roster is one
-- shared zone, each seat is asked once, and the pick's own action is what deals
-- ten chips into that seat's bag. This is the part no earlier game needed — The
-- Crew asks the *table* one question before dealing, and this asks each seat a
-- different one.
function M.test_puzzle_strike_a_character_is_picked_before_a_deck_exists(check)
	flow.init("puzzle_strike.json", 7)
	check("the roster offers every character whose chips are known", count_in("roster") == 5,
		tostring(count_in("roster")))
	check("and nobody has a bag yet", count_in("bag", "north") == 0 and count_in("bag", "south") == 0)

	flow.play_card(find_in("roster", "char_jaina").id, {})
	check("the first pick hands the turn on", phase.current().key == "pick_2")
	check("and it dealt into the picking seat only",
		count_in("bag", "north") == 10 and count_in("bag", "south") == 0,
		count_in("bag", "north") .. "/" .. count_in("bag", "south"))

	flow.play_card(find_in("roster", "char_setsuki").id, {})
	check("both seats hold the same ten chips but three",
		count_in("bag", "north") + count_in("hand", "north") == 10
		and count_in("bag", "south") + count_in("hand", "south") == 10)
	check("five of them are in hand",
		count_in("hand", "north") == 5 and count_in("hand", "south") == 5)
	check("the roster is cleared away", count_in("roster") == 0)
	check("and the character each seat picked is in front of them",
		find_in("ongoing", "char_jaina", "north") ~= nil
		and find_in("ongoing", "char_setsuki", "south") ~= nil)
	check("with its own three chips, and nobody else's",
		count_in("bag", "north", "burning_vigor") + count_in("hand", "north", "burning_vigor") == 1
		and count_in("bag", "north", "speed_of_the_fox") + count_in("hand", "north", "speed_of_the_fox") == 0)
end

-- The ante is mandatory and it lands in the gem pile rather than the deck,
-- which is the structural fact easiest to get wrong when modelling this off
-- Dominion: the two piles never mix.
function M.test_puzzle_strike_the_turn_opens_with_a_forced_ante(check)
	opening(7)
	check("the seat that is up antes one gem", count_in("gem_pile", "north") == 1,
		table.concat(keys_in("gem_pile", "north"), " "))
	check("and it is a 1-gem", keys_in("gem_pile", "north")[1] == "gem_1")
	check("the other seat has not anted yet", count_in("gem_pile", "south") == 0)
	check("and it went to the pile, not the bag",
		count_in("bag", "north") + count_in("hand", "north") == 10)
end

-- The same chip is money out of your hand and weight in your pile, and `value`
-- is one stat on one card rather than two kinds of gem.
function M.test_puzzle_strike_a_gem_is_money_in_hand_and_weight_in_the_pile(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	check("the action phase gives way to buying", phase.current().key == "buy")
	local before = seat_card("north").stats.money or 0
	local g = find_in("hand", "gem_1", "north")
	flow.play_card(g.id, {})
	check("playing it out of hand is a gem power", (seat_card("north").stats.money or 0) == before + 1)
	check("and the chip is on the table, not in the gem pile",
		find_in("table", "gem_1", "north") ~= nil)
	check("the pile still holds only the ante", count_in("gem_pile", "north") == 1)
end

-- The whole of the loss condition is a sum over one zone, so it has to be a
-- zone a scope can see.
function M.test_puzzle_strike_the_pile_is_read_as_a_sum_of_values(check)
	opening(7)
	local predicate = require("predicate")
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_2:1" }, {})
	check("four plus two plus the ante is seven",
		predicate.holds("sum:value@mine.gem_pile == 7", {}),
		table.concat(keys_in("gem_pile", "north"), " "))
	check("and three chips is not the same question",
		predicate.holds("count:gem@mine.gem_pile == 3", {}))
end

-- Crashing is one rule whatever the gem's size, because the size is a number
-- the action reads: set it, send the gem away, create that many 1-gems on the
-- other side. Four abilities keyed to four values would have been the other way.
function M.test_puzzle_strike_a_crash_breaks_one_gem_into_that_many_ones(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_3:1", "fill:mine.hand:crash_gem:1" }, {})
	local crash = find_in("hand", "crash_gem", "north")
	local three = find_in("gem_pile", "gem_3", "north")
	check("the crash is playable in the action phase", flow.can_play(crash.id))
	flow.play_card(crash.id, { three.id })
	check("the crashed gem left your own pile", find_in("gem_pile", "gem_3", "north") == nil)
	check("and arrived as three 1-gems in theirs", count_in("gem_pile", "south", "gem_1") == 3,
		table.concat(keys_in("gem_pile", "south"), " "))
	check("with a gem power for the trouble", (seat_card("north").stats.money or 0) == 1)
end

-- Two gems out, one gem in, and the sum is what says which — a rule that turns
-- a number into a *card*, which no amount grammar can do. One card per answer
-- in a hidden zone, walked by the action, each with its own `when`.
function M.test_puzzle_strike_combining_makes_the_gem_they_add_up_to(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_1:1", "fill:mine.hand:combine:1" }, {})
	local ones = {}
	for _, id in ipairs(zone_of("gem_pile", "north").cards) do
		if entity.get(id).def_key == "gem_1" then ones[#ones + 1] = id end
	end
	check("there are two ones to work with", #ones == 2)
	flow.play_card(find_in("hand", "combine", "north").id, { ones[1], ones[2] })
	check("they became a 2-gem", count_in("gem_pile", "north", "gem_2") == 1,
		table.concat(keys_in("gem_pile", "north"), " "))
	check("and nothing else is left of them", count_in("gem_pile", "north") == 1)
	check("the pile is worth what it was", require("predicate").holds("sum:value@mine.gem_pile == 2", {}))
end

-- A pile too big to combine is refused, which is the whole of "if the total is
-- 4 or less" and is asked of the targets rather than of the card.
function M.test_puzzle_strike_a_combine_over_four_is_refused(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_3:1",
	              "fill:mine.hand:combine:1" }, {})
	local big = { find_in("gem_pile", "gem_4", "north").id, find_in("gem_pile", "gem_3", "north").id }
	local before = count_in("gem_pile", "north")
	flow.play_card(find_in("hand", "combine", "north").id, big)
	check("seven is more than four, so nothing happened", count_in("gem_pile", "north") == before,
		table.concat(keys_in("gem_pile", "north"), " "))
end

-- You must buy at least one chip a turn, and a Wound is free — which is what
-- makes that rule a rule rather than a wish. The end-turn button spends the
-- counter, so the gate is the cost.
function M.test_puzzle_strike_a_turn_cannot_end_before_something_is_bought(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	check("nothing bought yet", (seat_card("north").stats.bought or 0) == 0)
	check("so the turn cannot be ended", not flow.can_activate(loose("end_turn").id))
	check("and a Wound is always affordable", flow.can_activate(loose("stack_wound").id))
	flow.activate(loose("stack_wound").id, {})
	check("taking one counts as the buy", (seat_card("north").stats.bought or 0) == 1)
	check("it went to the discard, not the hand", count_in("discard", "north", "wound") == 1)
	check("and now the turn may end", flow.can_activate(loose("end_turn").id))
end

-- Cleanup sweeps the table and the unplayed hand into the discard and draws a
-- fresh five, and the turn passes. This is the loop the whole game runs on.
function M.test_puzzle_strike_cleanup_sweeps_and_hands_over(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("the other seat is up", zones.active_seat() == "south")
	check("in their action phase", phase.current().key == "action")
	check("the first seat holds a fresh five", count_in("hand", "north") == 5,
		tostring(count_in("hand", "north")))
	check("nothing is left on their table", count_in("table", "north") == 0)
	check("and the second seat has anted", count_in("gem_pile", "south") == 1)
end

-- The rulebook's own reshuffle: the bag runs out *mid-draw*, the discard goes
-- back in, and the draw carries on. `refill_when_empty` would have recreated
-- the starting ten and thrown away everything bought since.
function M.test_puzzle_strike_the_bag_refills_from_the_discard_mid_draw(check)
	opening(7)
	-- Empty the bag and put something in the discard that was never in it, so a
	-- recreated starting deck and a genuine reshuffle look different.
	actions.run({ "return_to:mine.bag:mine.discard", "fill:mine.discard:gem_4:1" }, {})
	check("the bag is empty", count_in("bag", "north") == 0)
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("the draw still filled a hand", count_in("hand", "north") == 5,
		tostring(count_in("hand", "north")))
	local held = count_in("hand", "north", "gem_4") + count_in("bag", "north", "gem_4")
		+ count_in("discard", "north", "gem_4")
	check("and the chip that was only ever in the discard is still in the deck", held == 1)
	check("nothing was conjured back: the ten are still ten plus what was bought",
		count_in("hand", "north") + count_in("bag", "north") + count_in("discard", "north") == 12,
		tostring(count_in("hand", "north") + count_in("bag", "north") + count_in("discard", "north")))
end

-- The loss condition is asked at the end of your own turn and nowhere else, so
-- sitting above ten in the middle of one is legal — and bringing yourself back
-- under before it ends is the game's whole defensive layer.
function M.test_puzzle_strike_ten_is_only_fatal_at_your_own_turns_end(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_4:1",
	              "fill:mine.gem_pile:gem_1:1" }, {})
	check("the pile is over ten", require("predicate").holds("sum:value@mine.gem_pile >= 10", {}),
		table.concat(keys_in("gem_pile", "north"), " "))
	check("and the game has not ended", phase.current().key == "action")
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("ending the turn there is what loses it", flow.winner() == "South",
		tostring(flow.winner()))
end

-- ...and coming back under before the turn ends saves you, which is the same
-- rule read the other way.
function M.test_puzzle_strike_crashing_back_under_ten_saves_the_turn(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_4:1",
	              "fill:mine.gem_pile:gem_1:1", "fill:mine.hand:crash_gem:1" }, {})
	local four = find_in("gem_pile", "gem_4", "north")
	flow.play_card(find_in("hand", "crash_gem", "north").id, { four.id })
	check("the pile came back under ten",
		require("predicate").holds("sum:value@mine.gem_pile <= 9", {}),
		table.concat(keys_in("gem_pile", "north"), " "))
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("so nobody has won", flow.winner() == nil, tostring(flow.winner()))
	check("and play carried on", zones.active_seat() == "south")
end

-- Being close to losing is what lets you draw your way out of it: the height
-- bonus is three separate ifs that add up, rather than one table lookup.
function M.test_puzzle_strike_a_fuller_pile_draws_more_chips(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_4:1" }, {})
	check("the pile stands at nine", require("predicate").holds("sum:value@mine.gem_pile == 9", {}),
		table.concat(keys_in("gem_pile", "north"), " "))
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("nine draws eight, not five", count_in("hand", "north") == 8,
		tostring(count_in("hand", "north")))
end

-- Panic Time: the ante grows as the bank empties, which is a count of stacks
-- with nothing left rather than a clock anybody winds.
function M.test_puzzle_strike_the_ante_grows_as_the_bank_runs_dry(check)
	opening(7)
	check("no stack is spent yet", require("predicate").holds("count:spent@bank == 0", {}))
	-- Two empty stacks at a two-player table is Panic Time.
	actions.run({ "stat_set:stock@stack_recklessness:0", "stat_set:stock@stack_roundhouse:0" }, {})
	check("two stacks are spent", require("predicate").holds("count:spent@bank == 2", {}))
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("so the next seat antes a 2-gem", count_in("gem_pile", "south", "gem_2") == 1,
		table.concat(keys_in("gem_pile", "south"), " "))
end

return M
