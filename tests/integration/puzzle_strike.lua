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
	flow.play_card(find_in("options", "char_" .. (first or "jaina")).id, {})
	flow.play_card(find_in("options", "char_" .. (second or "setsuki")).id, {})
end

-- Nothing about a character exists until somebody picks it: the roster is one
-- shared zone, each seat is asked once, and the pick's own action is what deals
-- ten chips into that seat's bag. This is the part no earlier game needed — The
-- Crew asks the *table* one question before dealing, and this asks each seat a
-- different one.
function M.test_puzzle_strike_a_character_is_picked_before_a_deck_exists(check)
	flow.init("puzzle_strike.json", 7)
	check("the offer holds all ten base characters", count_in("options") == 10,
		tostring(count_in("options")))
	check("and nobody has a bag yet", count_in("bag", "south") == 0 and count_in("bag", "north") == 0)

	flow.play_card(find_in("options", "char_jaina").id, {})
	-- The offer is still what is on screen — the second seat's pick opened
	-- straight over the first one's — so the turn moving is what says the phase
	-- did.
	check("the first pick hands the turn on", zones.active_seat() == "north")
	check("and it dealt into the picking seat only",
		count_in("bag", "south") == 10 and count_in("bag", "north") == 0,
		count_in("bag", "south") .. "/" .. count_in("bag", "north"))

	flow.play_card(find_in("options", "char_setsuki").id, {})
	check("both seats hold the same ten chips but three",
		count_in("bag", "south") + count_in("hand", "south") == 10
		and count_in("bag", "north") + count_in("hand", "north") == 10)
	check("five of them are in hand",
		count_in("hand", "south") == 5 and count_in("hand", "north") == 5)
	check("the offer is cleared away", count_in("options") == 0)
	check("and the character each seat picked is in front of them",
		find_in("fighter", "char_jaina", "south") ~= nil
		and find_in("fighter", "char_setsuki", "north") ~= nil)
	check("with its own three chips, and nobody else's",
		count_in("bag", "south", "burning_vigor") + count_in("hand", "south", "burning_vigor") == 1
		and count_in("bag", "south", "speed_of_the_fox") + count_in("hand", "south", "speed_of_the_fox") == 0)
end

-- The ante is mandatory and it lands in the gem pile rather than the deck,
-- which is the structural fact easiest to get wrong when modelling this off
-- Dominion: the two piles never mix.
function M.test_puzzle_strike_the_turn_opens_with_a_forced_ante(check)
	opening(7)
	check("the seat that is up antes one gem", count_in("gem_pile", "south") == 1,
		table.concat(keys_in("gem_pile", "south"), " "))
	check("and it is a 1-gem", keys_in("gem_pile", "south")[1] == "gem_1")
	check("the other seat has not anted yet", count_in("gem_pile", "north") == 0)
	check("and it went to the pile, not the bag",
		count_in("bag", "south") + count_in("hand", "south") == 10)
end

-- The same chip is money out of your hand and weight in your pile, and `value`
-- is one stat on one card rather than two kinds of gem.
function M.test_puzzle_strike_a_gem_is_money_in_hand_and_weight_in_the_pile(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	check("the action phase gives way to buying", phase.current().key == "buy")
	local before = seat_card("south").stats.money or 0
	local g = find_in("hand", "gem_1", "south")
	flow.play_card(g.id, {})
	check("playing it out of hand is a gem power", (seat_card("south").stats.money or 0) == before + 1)
	check("and the chip is on the table, not in the gem pile",
		find_in("table", "gem_1", "south") ~= nil)
	check("the pile still holds only the ante", count_in("gem_pile", "south") == 1)
end

-- The whole of the loss condition is a sum over one zone, so it has to be a
-- zone a scope can see.
function M.test_puzzle_strike_the_pile_is_read_as_a_sum_of_values(check)
	opening(7)
	local predicate = require("predicate")
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_2:1" }, {})
	check("four plus two plus the ante is seven",
		predicate.holds("sum:value@mine.gem_pile == 7", {}),
		table.concat(keys_in("gem_pile", "south"), " "))
	check("and three chips is not the same question",
		predicate.holds("count:gem@mine.gem_pile == 3", {}))
end

-- Crashing is one rule whatever the gem's size, because the size is a number
-- the action reads: set it, send the gem away, create that many 1-gems on the
-- other side. Four abilities keyed to four values would have been the other way.
function M.test_puzzle_strike_a_crash_breaks_one_gem_into_that_many_ones(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_3:1", "fill:mine.hand:crash_gem:1" }, {})
	local crash = find_in("hand", "crash_gem", "south")
	local three = find_in("gem_pile", "gem_3", "south")
	check("the crash is playable in the action phase", flow.can_play(crash.id))
	flow.play_card(crash.id, { three.id })
	check("the crashed gem left your own pile", find_in("gem_pile", "gem_3", "south") == nil)
	check("and arrived as three 1-gems in theirs", count_in("gem_pile", "north", "gem_1") == 3,
		table.concat(keys_in("gem_pile", "north"), " "))
	check("with a gem power for the trouble", (seat_card("south").stats.money or 0) == 1)
end

-- Two gems out, one gem in, and the sum is what says which — a rule that turns
-- a number into a *card*, which no amount grammar can do. One card per answer
-- in a hidden zone, walked by the action, each with its own `when`.
function M.test_puzzle_strike_combining_makes_the_gem_they_add_up_to(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_1:1", "fill:mine.hand:combine:1" }, {})
	local ones = {}
	for _, id in ipairs(zone_of("gem_pile", "south").cards) do
		if entity.get(id).def_key == "gem_1" then ones[#ones + 1] = id end
	end
	check("there are two ones to work with", #ones == 2)
	flow.play_card(find_in("hand", "combine", "south").id, { ones[1], ones[2] })
	check("they became a 2-gem", count_in("gem_pile", "south", "gem_2") == 1,
		table.concat(keys_in("gem_pile", "south"), " "))
	check("and nothing else is left of them", count_in("gem_pile", "south") == 1)
	check("the pile is worth what it was", require("predicate").holds("sum:value@mine.gem_pile == 2", {}))
end

-- A pile too big to combine is refused, which is the whole of "if the total is
-- 4 or less" and is asked of the targets rather than of the card.
function M.test_puzzle_strike_a_combine_over_four_is_refused(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_3:1",
	              "fill:mine.hand:combine:1" }, {})
	local big = { find_in("gem_pile", "gem_4", "south").id, find_in("gem_pile", "gem_3", "south").id }
	local before = count_in("gem_pile", "south")
	flow.play_card(find_in("hand", "combine", "south").id, big)
	check("seven is more than four, so nothing happened", count_in("gem_pile", "south") == before,
		table.concat(keys_in("gem_pile", "south"), " "))
end

-- You must buy at least one chip a turn, and a Wound is free — which is what
-- makes that rule a rule rather than a wish. The end-turn button spends the
-- counter, so the gate is the cost.
function M.test_puzzle_strike_a_turn_cannot_end_before_something_is_bought(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	check("nothing bought yet", (seat_card("south").stats.bought or 0) == 0)
	check("so the turn cannot be ended", not flow.can_activate(loose("end_turn").id))
	check("and a Wound is always affordable", flow.can_activate(loose("stack_wound").id))
	flow.activate(loose("stack_wound").id, {})
	check("taking one counts as the buy", (seat_card("south").stats.bought or 0) == 1)
	check("it went to the discard, not the hand", count_in("discard", "south", "wound") == 1)
	check("and now the turn may end", flow.can_activate(loose("end_turn").id))
end

-- Cleanup sweeps the table and the unplayed hand into the discard and draws a
-- fresh five, and the turn passes. This is the loop the whole game runs on.
function M.test_puzzle_strike_cleanup_sweeps_and_hands_over(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("the other seat is up", zones.active_seat() == "north")
	check("in their action phase", phase.current().key == "action")
	check("the first seat holds a fresh five", count_in("hand", "south") == 5,
		tostring(count_in("hand", "south")))
	check("nothing is left on their table", count_in("table", "south") == 0)
	check("and the second seat has anted", count_in("gem_pile", "north") == 1)
end

-- The rulebook's own reshuffle: the bag runs out *mid-draw*, the discard goes
-- back in, and the draw carries on. `refill_when_empty` would have recreated
-- the starting ten and thrown away everything bought since.
function M.test_puzzle_strike_the_bag_refills_from_the_discard_mid_draw(check)
	opening(7)
	-- Empty the bag and put something in the discard that was never in it, so a
	-- recreated starting deck and a genuine reshuffle look different.
	actions.run({ "return_to:mine.bag:mine.discard", "fill:mine.discard:gem_4:1" }, {})
	check("the bag is empty", count_in("bag", "south") == 0)
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("the draw still filled a hand", count_in("hand", "south") == 5,
		tostring(count_in("hand", "south")))
	local held = count_in("hand", "south", "gem_4") + count_in("bag", "south", "gem_4")
		+ count_in("discard", "south", "gem_4")
	check("and the chip that was only ever in the discard is still in the deck", held == 1)
	check("nothing was conjured back: the ten are still ten plus what was bought",
		count_in("hand", "south") + count_in("bag", "south") + count_in("discard", "south") == 12,
		tostring(count_in("hand", "south") + count_in("bag", "south") + count_in("discard", "south")))
end

-- The loss condition is asked at the end of your own turn and nowhere else, so
-- sitting above ten in the middle of one is legal — and bringing yourself back
-- under before it ends is the game's whole defensive layer.
function M.test_puzzle_strike_ten_is_only_fatal_at_your_own_turns_end(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_4:1",
	              "fill:mine.gem_pile:gem_1:1" }, {})
	check("the pile is over ten", require("predicate").holds("sum:value@mine.gem_pile >= 10", {}),
		table.concat(keys_in("gem_pile", "south"), " "))
	check("and the game has not ended", phase.current().key == "action")
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("ending the turn there is what loses it", flow.winner() == "North",
		tostring(flow.winner()))
end

-- ...and coming back under before the turn ends saves you, which is the same
-- rule read the other way.
function M.test_puzzle_strike_crashing_back_under_ten_saves_the_turn(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_4:1",
	              "fill:mine.gem_pile:gem_1:1", "fill:mine.hand:crash_gem:1" }, {})
	local four = find_in("gem_pile", "gem_4", "south")
	flow.play_card(find_in("hand", "crash_gem", "south").id, { four.id })
	check("the pile came back under ten",
		require("predicate").holds("sum:value@mine.gem_pile <= 9", {}),
		table.concat(keys_in("gem_pile", "south"), " "))
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("so nobody has won", flow.winner() == nil, tostring(flow.winner()))
	check("and play carried on", zones.active_seat() == "north")
end

-- Being close to losing is what lets you draw your way out of it: the height
-- bonus is three separate ifs that add up, rather than one table lookup.
function M.test_puzzle_strike_a_fuller_pile_draws_more_chips(check)
	opening(7)
	actions.run({ "fill:mine.gem_pile:gem_4:1", "fill:mine.gem_pile:gem_4:1" }, {})
	check("the pile stands at nine", require("predicate").holds("sum:value@mine.gem_pile == 9", {}),
		table.concat(keys_in("gem_pile", "south"), " "))
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("nine draws eight, not five", count_in("hand", "south") == 8,
		tostring(count_in("hand", "south")))
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
	check("so the next seat antes a 2-gem", count_in("gem_pile", "north", "gem_2") == 1,
		table.concat(keys_in("gem_pile", "north"), " "))
end

-- "Choose one" is an offer and a card per branch, which is the same mechanism
-- chess promotes a pawn with. Six cards for "any different two of four" is the
-- exhaustive set, and cheaper to read than two questions in a row.
function M.test_puzzle_strike_a_choice_is_an_offer_of_its_branches(check)
	opening(7)
	actions.run({ "fill:mine.hand:versatile_style:1" }, {})
	flow.play_card(find_in("hand", "versatile_style", "south").id, {})
	check("the offer is open", phase.current().type == "overlay", phase.current().key)
	check("with a card for each branch", count_in("options") == 3,
		table.concat(keys_in("options"), " "))
	local before = seat_card("south").stats.money or 0
	flow.play_card(find_in("options", "vs_money").id, {})
	check("taking the money branch pays two", (seat_card("south").stats.money or 0) == before + 2)
	check("and the offer is swept", count_in("options") == 0)
end

-- An extra turn is one flag read at the handover, and the route overrules the
-- phase about the seat — which is the whole of "again, same player".
function M.test_puzzle_strike_an_extra_turn_keeps_the_same_seat(check)
	opening(7)
	actions.run({ "fill:mine.hand:burst_of_speed:1" }, {})
	flow.play_card(find_in("hand", "burst_of_speed", "south").id, {})
	check("the chip is gone rather than played to the table",
		find_in("table", "burst_of_speed", "south") == nil)
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("the same seat is up again", zones.active_seat() == "south")
	check("with a second ante in the pile", count_in("gem_pile", "south") == 2,
		table.concat(keys_in("gem_pile", "south"), " "))
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("and the turn after that passes normally", zones.active_seat() == "north")
end

-- A gem one bigger than the one you gave up, asked three times over with three
-- different places for the answer to land: the discard, the hand, the pile.
function M.test_puzzle_strike_an_upgrade_lands_where_the_chip_says(check)
	opening(7)
	actions.run({ "fill:mine.hand:gem_2:1", "fill:mine.hand:big_rocks:1" }, {})
	flow.play_card(find_in("hand", "big_rocks", "south").id,
		{ find_in("hand", "gem_2", "south").id })
	check("Big Rocks puts the bigger gem in your hand",
		count_in("hand", "south", "gem_3") == 1, table.concat(keys_in("hand", "south"), " "))
	check("and the one it ate is gone", count_in("hand", "south", "gem_2") == 0)
end

-- Reading somebody else's hand. The offer holds the *real* chips rather than
-- copies of them, which is the whole difference: Pilebunker trashes one of
-- them, and a copy would leave the original where it was.
function M.test_puzzle_strike_an_opponents_hand_opens_in_the_offer(check)
	opening(7)
	actions.run({ "fill:mine.hand:pilebunker:1" }, {})
	-- A known gem in the other hand, so there is something worth trashing.
	local south = zone_of("hand", "north")
	actions.run({ "fill:enemy.hand:gem_3:1" }, {})
	local held = count_in("hand", "north")

	flow.play_card(find_in("hand", "pilebunker", "south").id, {})
	check("the offer opened", phase.current().type == "overlay")
	check("and it holds their whole hand, not a copy of it",
		count_in("options") == held and count_in("hand", "north") == 0,
		count_in("options") .. " offered, " .. count_in("hand", "north") .. " left")
	check("the chips are still theirs", find_in("options", "gem_3") ~= nil)

	local before = count_in("discard", "north", "gem_1")
	flow.play_card(find_in("options", "gem_3").id, {})
	check("choosing one is not playing it — north's table is untouched",
		find_in("table", "gem_3", "south") == nil)
	check("the pick is trashed", find_in("hand", "gem_3", "north") == nil)
	check("and three 1-gems land in their discard",
		count_in("discard", "north", "gem_1") == before + 3,
		tostring(count_in("discard", "north", "gem_1")))
	check("everything else went home", count_in("hand", "north") == held - 1
		and count_in("options") == 0,
		count_in("hand", "north") .. "/" .. count_in("options"))
	check("and the overlay is closed", phase.current().type ~= "overlay")
end

-- The way out of a question that may go unanswered. Pilebunker says "optional"
-- because a hand with no gem in it has nothing the chip names, and a forced
-- pick would trash something it never asked for.
function M.test_puzzle_strike_a_hand_read_may_be_declined(check)
	opening(7)
	actions.run({ "fill:mine.hand:pilebunker:1" }, {})
	local held = count_in("hand", "north")

	flow.play_card(find_in("hand", "pilebunker", "south").id, {})
	check("the offer says it may be walked away from", flow.can_dismiss())
	check("and dismissing it works", flow.dismiss_offer())
	check("their hand is whole again", count_in("hand", "north") == held,
		count_in("hand", "north") .. " of " .. held)
	check("the offer is empty", count_in("options") == 0)
	check("and the board is back", phase.current().type ~= "overlay")
end

-- A choice the rules force has no way out, which is what every offer before
-- this one was.
function M.test_puzzle_strike_a_forced_choice_has_no_way_out(check)
	opening(7)
	actions.run({ "fill:mine.hand:versatile_style:1" }, {})
	flow.play_card(find_in("hand", "versatile_style", "south").id, {})
	check("the branches are offered", count_in("options") == 3, tostring(count_in("options")))
	check("and there is no No choice button", not flow.can_dismiss())
	check("nor does dismissing do anything", not flow.dismiss_offer())
end

-- The same loop, closed *inside a chip*. This is where the phase loop could not
-- reach: Draw Three on a bag of one used to draw one and say nothing, because
-- an action list cannot branch and no phase runs between two draws.
function M.test_puzzle_strike_a_chip_that_draws_reshuffles_too(check)
	opening(7)
	actions.run({ "return_to:mine.bag:mine.discard", "fill:mine.hand:draw_three:1" }, {})
	check("the bag is empty on purpose and stays that way",
		count_in("bag", "south") == 0, tostring(count_in("bag", "south")))
	local held = count_in("hand", "south")
	flow.play_card(find_in("hand", "draw_three", "south").id, {})
	check("all three chips arrive", count_in("hand", "south") == held + 3 - 1,
		count_in("hand", "south") .. " from " .. held)
	check("out of a bag that shook itself", count_in("discard", "south") == 0)
end

-- A wound is the chip that cannot be played, and it says so by having no play
-- at all. That has to *mean* something: a card with nothing to run used to be
-- playable, cost nothing and change nothing, so a hand of wounds was a row of
-- live-looking chips that did nothing when clicked — and the escape hatch that
-- exists to stop a soft-lock would offer one forever.
function M.test_puzzle_strike_a_wound_is_not_a_move(check)
	opening(7)
	actions.run({ "fill:mine.hand:wound:1" }, {})
	local w = find_in("hand", "wound", "south")
	check("the wound is in hand", w ~= nil)
	check("and it cannot be played", not flow.can_play(w.id))
	check("nor does asking twice make it one", not flow.play_card(w.id, {}))
	check("it is still in hand", find_in("hand", "wound", "south") ~= nil)
end

-- What a chip says in pictures. The badges are stats so the card can wear them,
-- and a chip that gives nothing numeric wears nothing.
function M.test_puzzle_strike_a_chip_wears_what_it_gives(check)
	opening(7)
	actions.run({ "fill:mine.hand:one_of_each:1", "fill:mine.hand:draw_three:1" }, {})
	local one = find_in("hand", "one_of_each", "south").stats
	check("one of each is one of each",
		one.plus_act == 1 and one.plus_buy == 1 and one.plus_pow == 1 and one.plus_draw == 1)
	local three = find_in("hand", "draw_three", "south").stats
	check("draw three is three chips and nothing else",
		three.plus_draw == 3 and three.plus_act == nil and three.plus_buy == nil)
	local gem = find_in("hand", "gem_1", "south").stats
	check("a gem wears its value", gem.value == 1)
end

-- The printed words, and ours kept out of them. A chip's tooltip opens with the
-- text on the physical chip; anything we have to say about the build comes
-- after a blank line and says so.
function M.test_puzzle_strike_the_printed_text_comes_first(check)
	opening(7)
	local cards = require("cards")
	local declaration = require("declaration")
	local bad = {}
	for key, def in pairs(declaration.G.card_defs) do
		local tip = def.tooltip
		if tip and tip:find("DEV:", 1, true) then
			if not tip:find("\n\nDEV: ", 1, true) then bad[#bad + 1] = key end
			if tip:sub(1, 4) == "DEV:" then bad[#bad + 1] = key .. " (leads with it)" end
		end
	end
	check("every development note is a trailing DEV line", #bad == 0, table.concat(bad, " "))
	local rev = declaration.G.card_defs.reversal.tooltip
	check("and the chip's own words come first",
		rev:sub(1, 15) == "Main: +2 chips.", rev:sub(1, 30))
end

return M
