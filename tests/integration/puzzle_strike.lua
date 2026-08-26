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
local reactions = require("reactions")

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

-- The ten base-game chips this game was built and tested against, chosen one at
-- a time through the draft rather than randomised — so every test below reads
-- the same bank, and the picking half of the draft is exercised on every run.
local DEFAULT_BANK = { "risky_move", "really_annoying", "draw_three", "recklessness",
	"sneak_attack", "gem_essence", "one_two_punch", "one_of_each", "roundhouse", "combo_time" }

local function draft(chips)
	local button = find_in("controls", "pick_chip")
	for _, chip in ipairs(chips or DEFAULT_BANK) do
		flow.activate(button.id, {})
		local plate = find_in("options", "stack_" .. chip)
		assert(plate, "the box should be offering stack_" .. chip)
		flow.play_card(plate.id, {})
	end
end

-- Two seats, two characters and a bank, stopping at the first player's action
-- phase.
local function opening(seed, first, second, chips)
	flow.init("puzzle_strike.json", seed or 7)
	flow.play_card(find_in("options", "char_" .. (first or "jaina")).id, {})
	flow.play_card(find_in("options", "char_" .. (second or "setsuki")).id, {})
	draft(chips)
end

-- Nothing about a character exists until somebody picks it: the roster is one
-- shared zone, each seat is asked once, and the pick's own action is what deals
-- ten chips into that seat's bag. This is the part no earlier game needed — The
-- Crew asks the *table* one question before dealing, and this asks each seat a
-- different one.
function M.test_puzzle_strike_a_character_is_picked_before_a_deck_exists(check)
	flow.init("puzzle_strike.json", 7)
	check("the offer holds the whole roster, base and Shadows", count_in("options") == 20,
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
	-- The bank is drafted between the last pick and the deal, so nothing is in
	-- anybody's hand until it has been built.
	check("the bank has still to be built", count_in("hand", "south") == 0,
		count_in("hand", "south"))
	draft()
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

-- The bank is drafted, and that is the whole of "why is it the same every game".
--
-- It never was random: fifty-one Puzzle chips are printed, ten of them make a
-- bank, and the game file used to name the ten. Nothing was wrong with the
-- generator \u2014 nothing asked it for a shuffle. The draft is two buttons and no
-- new engine anything: one opens the box face up and takes what is picked, the
-- other shuffles what is left and deals the shortfall.
function M.test_puzzle_strike_the_bank_is_drafted_from_the_whole_box(check)
	flow.init("puzzle_strike.json", 7)
	flow.play_card(find_in("options", "char_jaina").id, {})
	flow.play_card(find_in("options", "char_setsuki").id, {})

	check("the bank opens with the eight that are always in it",
		count_in("bank") == 8, count_in("bank"))
	check("and every Puzzle chip ever printed is in the box",
		count_in("chip_box") == 51, count_in("chip_box"))

	local button = find_in("controls", "pick_chip")
	flow.activate(button.id, {})
	check("the box opens face up, all of it", count_in("options") == 51, count_in("options"))
	local plate = find_in("options", "stack_the_hammer")
	check("including a Shadows chip that was never in the bank before", plate ~= nil)

	flow.play_card(plate.id, {})
	check("the pick lands in the bank", find_in("bank", "stack_the_hammer") ~= nil)
	check("the offer is cleared and the rest went home",
		count_in("options") == 0 and count_in("chip_box") == 50,
		count_in("options") .. "/" .. count_in("chip_box"))
	check("the bank is nine chips short of a game", count_in("bank") == 9, count_in("bank"))
end

-- The button that fills the rest. It is one subtraction and a deal: ten less
-- however many Puzzle chips are already standing there, floored at nothing.
function M.test_puzzle_strike_randomising_fills_the_rest_of_the_bank(check)
	flow.init("puzzle_strike.json", 7)
	flow.play_card(find_in("options", "char_jaina").id, {})
	flow.play_card(find_in("options", "char_setsuki").id, {})
	draft({ "risky_move", "draw_three" })
	check("two were chosen by hand", count_in("bank") == 10, count_in("bank"))

	flow.activate(find_in("controls", "randomize_bank").id, {})
	check("and the rest arrived", count_in("bank") == 18, count_in("bank"))
	check("both of the chosen ones are still there",
		find_in("bank", "stack_risky_move") ~= nil and find_in("bank", "stack_draw_three") ~= nil)
	check("the box is short exactly ten", count_in("chip_box") == 41, count_in("chip_box"))
	check("and the game moved on to dealing",
		count_in("hand", "south") == 5, count_in("hand", "south"))
end

-- The same seed, the same bank: the draft draws from the engine's own generator,
-- so a replay and a networked opponent build the same game.
function M.test_puzzle_strike_a_random_bank_is_reproducible(check)
	local function banked(seed)
		flow.init("puzzle_strike.json", seed)
		flow.play_card(find_in("options", "char_jaina").id, {})
		flow.play_card(find_in("options", "char_setsuki").id, {})
		flow.activate(find_in("controls", "randomize_bank").id, {})
		local out = keys_in("bank")
		table.sort(out)
		return table.concat(out, ",")
	end
	local a, b = banked(3), banked(3)
	check("the same seed builds the same bank", a == b, a)
	check("and it is a full one", select(2, a:gsub(",", ",")) == 17, a)
	local c = banked(99)
	check("a different seed may build a different one", c ~= nil)
end

-- Three of the chips the box gained, each standing for one thing that used to
-- be unsayable. X-Copy is copy:, Training Day is the money trick, and Pick Your
-- Poison hands the choice across the table without moving the turn.
function M.test_puzzle_strike_x_copy_plays_a_chip_twice(check)
	opening(7, "jaina", "setsuki", { "x_copy", "draw_three", "risky_move", "really_annoying",
		"recklessness", "sneak_attack", "gem_essence", "one_two_punch", "one_of_each", "roundhouse" })
	local hand = zone_of("hand", "south")
	local xc   = zones.add(hand, "x_copy")
	local d3   = zones.add(hand, "draw_three")
	-- Enough in the bag to draw six, so the count says how many were drawn
	-- rather than how many were left.
	for _ = 1, 6 do zones.add(zone_of("bag", "south"), "gem_1") end
	local held = count_in("hand", "south")

	seat_card("south").stats.act_brown = 1
	check("X-Copy is played on the Draw Three in hand", flow.play_card(xc.id, { d3.id }))
	-- Six chips arrive and X-Copy itself leaves for the table.
	check("three chips came twice", count_in("hand", "south") == held + 5,
		held .. " -> " .. count_in("hand", "south"))
	check("and the copied chip is still in the hand it was chosen from",
		entity.get(d3.id).zone_id == hand.id)
end

-- "Gain a chip costing up to 2 more than the one you trashed" is money, and the
-- ordinary price of every pile does the gating. The borrowed buy phase is where
-- it gets spent, so the shopping happens inside an action phase.
function M.test_puzzle_strike_training_day_pays_an_allowance(check)
	opening(7, "jaina", "setsuki", { "training_day", "draw_three", "risky_move", "really_annoying",
		"recklessness", "sneak_attack", "gem_essence", "one_two_punch", "one_of_each", "roundhouse" })
	local hand = zone_of("hand", "south")
	local td   = zones.add(hand, "training_day")
	local gem  = zones.add(hand, "gem_3")

	seat_card("south").stats.act_brown = 1
	check("it is played on the 3-gem", flow.play_card(td.id, { gem.id }))
	check("the gem was trashed", entity.get(gem.id).zone_id == nil
		or entity.get(gem.id).zone_id == zones.find_id("void"))
	check("and the allowance is its price plus two",
		seat_card("south").stats.money == 7, seat_card("south").stats.money)
	check("with a buy to spend it on", seat_card("south").stats.buys == 1)
end

-- The opponent's choice, and it really is theirs: priority crosses the table
-- while the offer is up and each branch hands it back.
function M.test_puzzle_strike_pick_your_poison_asks_the_other_seat(check)
	opening(7, "jaina", "setsuki", { "pick_your_poison", "draw_three", "risky_move", "really_annoying",
		"recklessness", "sneak_attack", "gem_essence", "one_two_punch", "one_of_each", "roundhouse" })
	local pyp = zones.add(zone_of("hand", "south"), "pick_your_poison")
	seat_card("south").stats.act_red = 1

	check("south plays it", flow.play_card(pyp.id, {}))
	check("and north is the one being asked", zones.active_seat() == "north", zones.active_seat())
	check("with both branches on offer", count_in("options") == 2, count_in("options"))

	flow.play_card(find_in("options", "pp_ante").id, {})
	check("north's own pile took the gem", count_in("gem_pile", "north") == 1,
		count_in("gem_pile", "north"))
	check("and priority came home", zones.active_seat() == "south", zones.active_seat())
end

-- Panda's Bargain, whole: "at the end of any turn you bought a Puzzle chip, +1
-- chip". Two halves and two reactions — the buy is what it watches for, the turn
-- ending is when it pays — with a stat carrying the answer between them, because
-- an event knows what it is and not what came before it.
function M.test_puzzle_strike_pandas_bargain_pays_at_the_end_of_the_turn(check)
	opening(7)
	local pb = zones.add(zone_of("hand", "south"), "pandas_bargain")
	seat_card("south").stats.act_brown = 1
	check("it is laid out", flow.play_card(pb.id, {}))
	check("and it is on the table in front of them",
		find_in("ongoing", "pandas_bargain", "south") ~= nil)

	-- Buy a Puzzle chip, which is what it is watching for.
	actions.run({ "next_phase" }, {})
	seat_card("south").stats.money = 9
	local held = count_in("hand", "south")
	flow.activate(find_in("bank", "stack_draw_three").id, {})
	check("nothing is owed until the turn is over", count_in("hand", "south") == held,
		count_in("hand", "south"))

	-- End the turn. The chip is owed now.
	local bag = count_in("bag", "south")
	flow.activate(find_in("controls", "end_turn").id, {})
	check("the turn changed hands", zones.active_seat() == "north", zones.active_seat())
	check("and the bargain paid its chip on the way out",
		count_in("hand", "south") == 6, count_in("hand", "south"))
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

-- "Trash their *largest* gem" — the clause that has been the standing example of
-- what an offer could not say since Stage 4.
--
-- The whole hand still comes up, because revealing it is half the printed rule.
-- What changed is which of the revealed cards may be taken: the asking card says
-- so with `chosen.where`, in the same condition vocabulary a target already uses,
-- and "largest" is the candidate compared with the offer it is lying in.
function M.test_puzzle_strike_pilebunker_takes_only_the_largest_gem(check)
	opening(7)
	actions.run({ "fill:mine.hand:pilebunker:1" }, {})
	actions.run({ "fill:enemy.hand:gem_3:1" }, {})
	actions.run({ "fill:enemy.hand:wound:1" }, {})
	local held = count_in("hand", "north")

	flow.play_card(find_in("hand", "pilebunker", "south").id, {})
	check("their whole hand is revealed, wound and all",
		count_in("options") == held, count_in("options") .. "/" .. held)
	check("the wound came up too", find_in("options", "wound") ~= nil)

	check("but a wound is not a gem, so it cannot be taken",
		not flow.can_play(find_in("options", "wound").id))
	check("and neither is a 1-gem, because it is not the largest",
		not flow.can_play(find_in("options", "gem_1").id))
	check("the 3-gem is the one the chip names",
		flow.can_play(find_in("options", "gem_3").id))

	check("and taking it is accepted", flow.play_card(find_in("options", "gem_3").id, {}))
	check("everything else went home", count_in("hand", "north") == held - 1,
		count_in("hand", "north"))
end

-- An offer whose every card the asker refuses is a question with no answer, and
-- a mandatory one would never close. Nothing to take is nothing to look at.
function M.test_puzzle_strike_an_offer_nothing_qualifies_for_does_not_open(check)
	opening(7)
	actions.run({ "fill:mine.hand:pilebunker:1" }, {})
	-- Their hand emptied of gems and filled with wounds: a full hand, and not one
	-- card in it that Pilebunker will take.
	actions.run({ "move:enemy.hand:enemy.discard" }, {})
	actions.run({ "fill:enemy.hand:wound:3" }, {})

	flow.play_card(find_in("hand", "pilebunker", "south").id, {})
	check("no offer opened over a hand with nothing in it to take",
		count_in("options") == 0, count_in("options"))
	check("their hand was not disturbed", count_in("hand", "north") == 3,
		count_in("hand", "north"))
	check("and play carried on", phase.current().type ~= "overlay")
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

-- An arrow is an extra action play, and a coloured one only pays for a chip
-- whose own banner matches it. So a cost is a list of alternatives — this
-- colour's pool, or the plain one — and the order is the rule: the restricted
-- pool goes first, because a red arrow left unspent is a red arrow wasted.
function M.test_puzzle_strike_a_coloured_arrow_only_pays_its_own_colour(check)
	opening(7)
	local me = seat_card("south")
	check("a turn opens with one plain arrow and no coloured ones",
		me.stats.acts == 1 and me.stats.act_red == 0 and me.stats.act_brown == 0)

	actions.run({ "fill:mine.hand:sneak_attack:1", "fill:mine.hand:draw_three:1" }, {})
	flow.play_card(find_in("hand", "sneak_attack", "south").id, {})
	check("the plain arrow paid for the red chip", me.stats.acts == 0)
	check("and it gave a red one back", me.stats.act_red == 1)

	local brown = find_in("hand", "draw_three", "south")
	check("which will not pay for a brown chip", not flow.can_play(brown.id))
	actions.run({ "stat_gain:act_brown@mine.player:1" }, {})
	check("a brown arrow will", flow.can_play(brown.id))
	flow.play_card(brown.id, {})
	check("and the brown one is what was spent, not the red",
		me.stats.act_brown == 0 and me.stats.act_red == 1,
		me.stats.act_brown .. "/" .. me.stats.act_red)
end

-- The piggy bank, which is what the icon read as "+1 buy" actually is: keep one
-- unplayed chip out of the cleanup discard and draw one fewer for it. It is two
-- halves a turn apart, so the chip kept back needs somewhere to sit.
function M.test_puzzle_strike_a_piggy_bank_keeps_a_chip_for_next_turn(check)
	opening(7)
	actions.run({ "stat_gain:piggy@mine.player:1", "fill:mine.hand:gem_4:1" }, {})
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})

	check("cleanup asks which chip to keep", phase.current().type == "overlay")
	check("and keeping none is an answer", flow.can_dismiss())
	flow.play_card(find_in("options", "gem_4").id, {})
	check("the kept chip is on the shelf", count_in("stash", "south", "gem_4") == 1,
		table.concat(keys_in("stash", "south"), " "))
	check("and the hand it paid for is one short",
		count_in("hand", "south") == 4, tostring(count_in("hand", "south")))

	-- Round the table and back.
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	if phase.current().type == "overlay" then flow.dismiss_offer() end
	check("it is south's turn again", zones.active_seat() == "south")
	check("the chip came back by itself", find_in("hand", "gem_4", "south") ~= nil,
		table.concat(keys_in("hand", "south"), " "))
	check("and the shelf is empty", count_in("stash", "south") == 0)
end

-- Without the ability nothing is asked: the cleanup runs straight through.
function M.test_puzzle_strike_no_piggy_bank_no_question(check)
	opening(7)
	flow.activate(loose("done_acting").id, {})
	flow.activate(loose("stack_wound").id, {})
	flow.activate(loose("end_turn").id, {})
	check("no offer opened", phase.current().type ~= "overlay", phase.current().key)
	check("and a full five were drawn", count_in("hand", "north") == 5,
		tostring(count_in("hand", "north")))
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
		one.plus_act == 1 and one.plus_piggy == 1 and one.plus_pow == 1 and one.plus_draw == 1)
	local three = find_in("hand", "draw_three", "south").stats
	check("draw three is three chips and nothing else",
		three.plus_draw == 3 and three.plus_act == nil and three.plus_piggy == nil)
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

-- Bubble Shield, both legs of it. Laying the chip out does not leave the chip
-- lying there: it becomes a card of its own, because the printed chip is two
-- reactions answered from two different zones and one card cannot say which of
-- its reactions belongs to which. "transform" was already the word for a card
-- becoming another card, so the split costs no vocabulary.
function M.test_puzzle_strike_bubble_shield_becomes_its_ongoing_half(check)
	opening(7, "argagarg", "jaina")
	local one = zones.turn_seat()
	local chip = loose("bubble_shield")
	zones.move_card(chip.id, zone_of("hand", one).id)
	local pl = seat_card(one)
	pl.stats.act_blue = (pl.stats.act_blue or 0) + 1

	flow.play_card(chip.id, {})
	check("the chip it was is off the board", entity.get(chip.id).zone_id == nil)
	check("and its ongoing half is out", count_in("ongoing", one, "bubble_shield_up") == 1,
		table.concat(keys_in("ongoing", one), " "))
	check("nothing was left in hand", count_in("hand", one, "bubble_shield") == 0)
end

-- The crash announces itself, and the announcement is what the shield hears.
-- Nothing waits on it — the gems have already landed — so the window is a pure
-- question, and answering takes one back off the pile.
function M.test_puzzle_strike_bubble_shield_takes_a_gem_back_off(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	local shield = zones.add(zone_of("ongoing", two), "bubble_shield_up")

	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	local pl = seat_card(one)
	pl.stats.act_purple = (pl.stats.act_purple or 0) + 1
	-- Something of one's own to break, so the crash has a size at all.
	local mine = zones.add(zone_of("gem_pile", one), "gem_1")

	local before = count_in("gem_pile", two, "gem_1")
	local stock = find_in("bank", "stack_gem_1").stats.stock
	flow.play_card(crash.id, { mine.id })

	check("the defender was asked", zones.active_seat() == two, zones.active_seat())
	check("while the turn stayed with the crasher", zones.turn_seat() == one, zones.turn_seat())
	check("one gem arrived", count_in("gem_pile", two, "gem_1") == before + 1,
		count_in("gem_pile", two, "gem_1"))

	-- What an interface has to be told, since a window moves neither turn nor
	-- phase and so looks like nothing at all from the outside.
	check("the crash is named as what waits", flow.pending_event() ~= nil
		and flow.pending_event().re_verb == "crash")
	local offer = flow.usable_reactions()
	check("and the shield is the one answer offered", #offer == 1 and offer[1].card == shield.id,
		#offer)
	check("so a click on it means answering", (flow.sole_reaction(shield.id) or {}).card == shield.id)
	check("and it is not drawn dead", flow.can_react(shield.id))

	flow.react(shield.id, 1, {})
	check("and the shield took it straight back off",
		count_in("gem_pile", two, "gem_1") == before, count_in("gem_pile", two, "gem_1"))
	check("the bank is whole again", find_in("bank", "stack_gem_1").stats.stock == stock, stock)
	-- It walks to the discard and turns back into the chip you buy, so the bag it
	-- comes back in holds a Bubble Shield rather than the laid-out half of one.
	check("the shield is spent", entity.get(shield.id).zone_id == nil)
	check("and a Bubble Shield is in the discard",
		count_in("discard", two, "bubble_shield") == 1, count_in("discard", two, "bubble_shield"))
	check("and recycles as the plain chip", count_in("discard", two, "bubble_shield") == 1,
		table.concat(keys_in("discard", two), " "))
	check("priority went back to the crasher", zones.active_seat() == one, zones.active_seat())
end

-- One gem, not every gem. "any" in a scope means the whole pool it matches, so a
-- shield written with it emptied the pile instead of negating the one that
-- arrived — and the first test could not see it, because the pile it defended
-- was empty to begin with.
function M.test_puzzle_strike_bubble_shield_negates_one_gem_only(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	local shield = zones.add(zone_of("ongoing", two), "bubble_shield_up")
	-- Gems already standing there, which is the ordinary case: a pile is what a
	-- crash lands on and it is rarely empty.
	zones.add(zone_of("gem_pile", two), "gem_1")
	zones.add(zone_of("gem_pile", two), "gem_1")

	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	local mine = zones.add(zone_of("gem_pile", one), "gem_1")

	flow.play_card(crash.id, { mine.id })
	check("three gems stand there", count_in("gem_pile", two, "gem_1") == 3,
		count_in("gem_pile", two, "gem_1"))
	flow.react(shield.id, 1, {})
	check("and the shield took exactly one back off",
		count_in("gem_pile", two, "gem_1") == 2, count_in("gem_pile", two, "gem_1"))
end

-- Red is attack, and the rule is written once on the colour rather than on each
-- red chip. Playing one announces itself, so Really Annoying's reaction half —
-- unbuildable while a chip could not be played out of turn — answers by wounding
-- whoever swung.
function M.test_puzzle_strike_a_red_chip_announces_an_attack(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat ~= one then two = z.seat end
	end
	-- Bought chips rather than character ones, so they are minted into the hands
	-- that need them instead of hunted for in a deal.
	local answer = zones.add(zone_of("hand", two), "really_annoying")
	local red = zones.add(zone_of("hand", one), "sneak_attack")
	seat_card(one).stats.act_red = (seat_card(one).stats.act_red or 0) + 1

	local wounds = count_in("discard", one, "wound")
	flow.play_card(red.id, {})
	check("the attack is announced, not resolved", zones.active_seat() == two, zones.active_seat())
	check("with the turn still the attacker's", zones.turn_seat() == one, zones.turn_seat())

	flow.react(answer.id, 1, {})
	check("the attacker took a wound", count_in("discard", one, "wound") == wounds + 1,
		count_in("discard", one, "wound"))
	-- The window re-opens rather than closing on one answer: Argagarg starts with
	-- a Bubble Shield, and from across the table a bag and a hand are one place.
	check("and the same seat is asked again", zones.active_seat() == two, zones.active_seat())
	flow.pass_react()
	check("and the answer recycles into its own discard",
		count_in("discard", two, "really_annoying") == 1,
		table.concat(keys_in("discard", two), " "))
	check("the red chip then resolved to the table", count_in("table", one, "sneak_attack") == 1,
		table.concat(keys_in("table", one), " "))
	check("and priority went back", zones.active_seat() == one, zones.active_seat())
end

-- The other half of Bubble Shield, and the other thing a reaction can be: not an
-- effect of its own but the refusal of somebody else's. Answered from hand, it
-- counterspells the attack, so the red chip's action never runs at all — the gem
-- it would have anted never leaves the bank and the attacker keeps the red action
-- it would have gained.
--
-- The counter names no zone. Where the attack goes once it is stopped is written
-- on the attack, and that is the whole reason a card this small can exist: it
-- refuses without knowing a single rule about what it refused.
function M.test_puzzle_strike_bubble_shield_makes_you_immune_to_a_red_chip(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat ~= one then two = z.seat end
	end
	local shield = zones.add(zone_of("hand", two), "bubble_shield")
	local red = zones.add(zone_of("hand", one), "sneak_attack")
	seat_card(one).stats.act_red = (seat_card(one).stats.act_red or 0) + 1

	local gems = count_in("gem_pile", two, "gem_1")
	local stock = find_in("bank", "stack_gem_1").stats.stock
	flow.play_card(red.id, {})
	check("the attack is announced, not resolved", zones.active_seat() == two, zones.active_seat())
	-- Read with the cost already paid and the action not yet run, which is exactly
	-- what a window is.
	local reds = seat_card(one).stats.act_red

	local offer = flow.usable_reactions()
	check("and the shield is the answer offered", #offer == 1 and offer[1].card == shield.id, #offer)

	flow.react(shield.id, 1, {})
	check("no gem was anted", count_in("gem_pile", two, "gem_1") == gems,
		count_in("gem_pile", two, "gem_1"))
	check("so the bank never paid one out", find_in("bank", "stack_gem_1").stats.stock == stock,
		find_in("bank", "stack_gem_1").stats.stock)
	check("and the attacker never got the action it grants", seat_card(one).stats.act_red == reds,
		seat_card(one).stats.act_red)
	-- Stopped, not undone: the chip was still played and still goes where playing
	-- it sends it.
	check("the red chip is spent to the table either way",
		count_in("table", one, "sneak_attack") == 1, table.concat(keys_in("table", one), " "))
	check("the shield is spent to its own discard",
		count_in("discard", two, "bubble_shield") == 1, table.concat(keys_in("discard", two), " "))
	check("and priority went back", zones.active_seat() == one, zones.active_seat())
end

-- Stone Wall sends the whole crash back, not one gem of it. How many is the size
-- of the crash and nothing else, which is why repeating a line could never say it
-- — the count is only known as the game runs, so "destroy" takes one.
function M.test_puzzle_strike_stone_wall_reflects_the_whole_crash(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	local wall = zones.add(zone_of("hand", two), "stone_wall")
	-- A gem already standing there, which the reflection must leave alone: it was
	-- not sent by this crash.
	zones.add(zone_of("gem_pile", two), "gem_1")

	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	-- A 3-gem broken is three 1-gems sent.
	local mine = zones.add(zone_of("gem_pile", one), "gem_3")
	local stock = find_in("bank", "stack_gem_1").stats.stock

	flow.play_card(crash.id, { mine.id })
	check("three gems arrived on top of the one already there",
		count_in("gem_pile", two, "gem_1") == 4, count_in("gem_pile", two, "gem_1"))

	flow.react(wall.id, 1, {})
	check("the three sent went back and the one standing stayed",
		count_in("gem_pile", two, "gem_1") == 1, count_in("gem_pile", two, "gem_1"))
	check("the bank has them again", find_in("bank", "stack_gem_1").stats.stock == stock, stock)
	check("and the wall recycles into its own discard",
		count_in("discard", two, "stone_wall") == 1, table.concat(keys_in("discard", two), " "))
end

-- Counter-crashing is mutual annihilation, not two independent halves: the
-- smaller of the two crashes is struck off both, and only the remainder arrives.
-- Both gems are broken either way, which is what makes answering a big crash with
-- a small one still cost you.
--
-- Three into a counter of two: two cancel, so one of the three stands and nothing
-- goes back the other way. The both-halves reading sent all three home and two
-- more besides, and the difference is the whole rule.
function M.test_puzzle_strike_reversal_counter_crashes(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	local rev = zones.add(zone_of("hand", two), "reversal")
	local back = zones.add(zone_of("gem_pile", two), "gem_2")

	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	local mine = zones.add(zone_of("gem_pile", one), "gem_3")

	flow.play_card(crash.id, { mine.id })
	check("three gems arrived", count_in("gem_pile", two, "gem_1") == 3,
		count_in("gem_pile", two, "gem_1"))
	-- A seat opens with a gem of its own, so the counter is counted from there.
	local held = count_in("gem_pile", one, "gem_1")
	local stock = find_in("bank", "stack_gem_1").stats.stock

	flow.react(rev.id, 1, { back.id })
	check("two of the three were cancelled and one stands",
		count_in("gem_pile", two, "gem_1") == 1, count_in("gem_pile", two, "gem_1"))
	check("and nothing went the other way", count_in("gem_pile", one, "gem_1") == held,
		count_in("gem_pile", one, "gem_1"))
	check("the two cancelled gems went home to the bank",
		find_in("bank", "stack_gem_1").stats.stock == stock + 2,
		find_in("bank", "stack_gem_1").stats.stock)
	check("the broken gem is out of play", entity.get(back.id).zone_id == zones.find_id("void"))
	-- Nothing is left in flight, so there is nothing for the attacker to answer
	-- and priority comes straight back.
	check("the counter sent nothing, so nobody is asked about it",
		zones.active_seat() == one, zones.active_seat())
end

-- The counter that is bigger than the crash: the remainder turns round. Three at
-- me, four back, three cancel — I take none and the attacker takes one, both of
-- us having spent the gem. This is the case a both-halves reading gets loudest
-- wrong, sending four where the rule sends one.
function M.test_puzzle_strike_a_bigger_counter_sends_the_remainder_back(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	local rev = zones.add(zone_of("hand", two), "reversal")
	local back = zones.add(zone_of("gem_pile", two), "gem_4")

	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	local mine = zones.add(zone_of("gem_pile", one), "gem_3")

	flow.play_card(crash.id, { mine.id })
	local held = count_in("gem_pile", one, "gem_1")

	flow.react(rev.id, 1, { back.id })
	check("the defender takes nothing", count_in("gem_pile", two, "gem_1") == 0,
		count_in("gem_pile", two, "gem_1"))
	check("and the attacker takes the one left over",
		count_in("gem_pile", one, "gem_1") == held + 1, count_in("gem_pile", one, "gem_1"))
	-- Countered with a four, and a broken four is unanswerable — which is exactly
	-- what ends a counter-crash chain rather than any depth limit.
	check("a four cannot be answered, so the chain stops here",
		zones.active_seat() == one, zones.active_seat())
end

-- A broken 4-gem is immune outright: no window opens, for anybody, however many
-- answers are held. The counter-crash chain terminates because of this and for no
-- other reason.
function M.test_puzzle_strike_a_crashed_four_cannot_be_answered(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	zones.add(zone_of("hand", two), "reversal")
	zones.add(zone_of("gem_pile", two), "gem_2")

	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	local mine = zones.add(zone_of("gem_pile", one), "gem_4")

	flow.play_card(crash.id, { mine.id })
	check("four gems arrived", count_in("gem_pile", two, "gem_1") == 4,
		count_in("gem_pile", two, "gem_1"))
	check("and nobody was asked", zones.active_seat() == one, zones.active_seat())
	check("nothing waits to be answered", #zone_of("pending").cards == 0)
end

-- A Double Crash that breaks a four shields the gem beside it: the rule reads the
-- biggest gem broken, not the size of the crash, so a 4+1 sends five gems that
-- nobody may answer.
function M.test_puzzle_strike_a_four_in_a_double_crash_shields_the_whole_crash(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("gem_pile")) do
		if z.seat ~= one then two = z.seat end
	end
	zones.add(zone_of("hand", two), "reversal")
	zones.add(zone_of("gem_pile", two), "gem_2")

	local crash = zones.add(zone_of("hand", one), "double_crash")
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	local four = zones.add(zone_of("gem_pile", one), "gem_4")
	local lone = zones.add(zone_of("gem_pile", one), "gem_1")

	flow.play_card(crash.id, { four.id, lone.id })
	check("five gems arrived", count_in("gem_pile", two, "gem_1") == 5,
		count_in("gem_pile", two, "gem_1"))
	check("and the four shielded the one beside it",
		zones.active_seat() == one, zones.active_seat())
end

-- Nobody holds one, so the crash never asks. This is Filter A doing its job on
-- a real game: the emit is written on four chips and costs the other ninety
-- nothing at all.
function M.test_puzzle_strike_a_crash_nobody_answers_asks_nothing(check)
	opening(7, "jaina", "setsuki")
	local one = zones.turn_seat()
	local crash = loose("crash_gem")
	zones.move_card(crash.id, zone_of("hand", one).id)
	seat_card(one).stats.act_purple = (seat_card(one).stats.act_purple or 0) + 1
	local mine = zones.add(zone_of("gem_pile", one), "gem_1")

	flow.play_card(crash.id, { mine.id })
	check("the turn seat is still acting", zones.active_seat() == one, zones.active_seat())
	check("and nothing is waiting to be answered", #zone_of("pending").cards == 0)
end


-- Rigorous Training: an opponent buying a purple hands *you* a shopping trip.
--
-- Two things the engine had to grow for it, and one it did not. The bank hands
-- whatever lies in it a "buy" announcement through "applies", so the piles say
-- nothing about being answerable and the tag says it once. The answer interjects
-- a phase, and priority stays with the seat it was interjected for while the
-- turn never moves. What it did *not* need is a way to filter a shop by price:
-- the allowance is handed over as money and the ordinary price of every pile
-- does the gating.
function M.test_puzzle_strike_rigorous_training_buys_out_of_turn(check)
	opening(7, "jaina", "argagarg")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat ~= one then two = z.seat end
	end
	local rt = zones.add(zone_of("hand", two), "rigorous_training")
	-- Something non-purple to trash, priced, so the allowance is a real sum.
	local fodder = zones.add(zone_of("hand", two), "draw_three")
	flow.activate(loose("done_acting").id, {})
	seat_card(one).stats.money = 9
	seat_card(one).stats.buys  = 1

	-- The rule is the colour, not the price: an eight-cost brown chip is not a
	-- purple and opens no window, which is the check a price test would pass by
	-- accident.
	check("a cheap buy is answered by nobody",
		not reactions.anyone_answers("buy", { find_in("bank", "stack_risky_move").id }, one))
	check("and an expensive one that is not purple is not either",
		not reactions.anyone_answers("buy", { find_in("bank", "stack_combo_time").id }, one))

	local pile = find_in("bank", "stack_double_crash")
	flow.activate(pile.id, {}, 1)
	check("the purple buy is announced", zones.active_seat() == two, zones.active_seat())
	check("while the turn stays the buyer's", zones.turn_seat() == one, zones.turn_seat())

	local offer = flow.usable_reactions()
	check("and the training is the answer offered",
		#offer == 1 and offer[1].card == rt.id, #offer)

	flow.react(rt.id, 1, { fodder.id })
	check("the trashed chip is gone", entity.get(fodder.id).zone_id == zones.find_id("void"))
	-- 3 for the Draw Three, plus the two the card gives.
	check("the allowance is the price plus two", seat_card(two).stats.money == 5,
		seat_card(two).stats.money)
	check("the shopping phase is up", phase.current().key == "react_buy", phase.current().key)
	check("and it belongs to the reactor", zones.active_seat() == two, zones.active_seat())

	-- What the allowance is *for*: it gates the shop without anything filtering it.
	check("a pile within the allowance is buyable",
		flow.can_activate(find_in("bank", "stack_one_of_each").id))
	check("one over it is not",
		not flow.can_activate(find_in("bank", "stack_roundhouse").id))

	flow.activate(find_in("bank", "stack_one_of_each").id, {}, 1)
	check("the gained chip is in the reactor's discard",
		count_in("discard", two, "one_of_each") == 1,
		table.concat(keys_in("discard", two), " "))

	flow.activate(find_in("controls", "finish_shopping").id, {}, 1)
	check("the interjection is over", phase.current().key ~= "react_buy", phase.current().key)
	check("nothing is left over", seat_card(two).stats.money == 0, seat_card(two).stats.money)
	check("the turn player's buy landed", count_in("discard", one, "double_crash") == 1,
		table.concat(keys_in("discard", one), " "))
	check("and priority went home", zones.active_seat() == one, zones.active_seat())
	check("the training went to its own discard",
		count_in("discard", two, "rigorous_training") == 1,
		table.concat(keys_in("discard", two), " "))
end

-- Double-take, whole: the chosen chip does what it does twice, is trashed, and
-- the action phase ends. `copy:` is what makes it one line — nothing is spent
-- and the chip does not move, which is what leaves it there to be trashed.
function M.test_puzzle_strike_double_take_plays_a_chip_twice_and_trashes_it(check)
	opening(7, "setsuki", "jaina")
	local hand = zone_of("hand", "south")
	local dt   = find_in("hand", "double_take", "south") or zones.add(hand, "double_take")
	local bot  = zones.add(hand, "bag_of_tricks")
	for _ = 1, 4 do zones.add(zone_of("bag", "south"), "gem_1") end
	seat_card("south").stats.act_brown = 1
	local held = count_in("hand", "south")

	check("a Puzzle chip is not a legal pick",
		not flow.play_card(dt.id, { zones.add(hand, "draw_three").id }))
	check("Double-take is played on the Bag of Tricks", flow.play_card(dt.id, { bot.id }))
	-- Two of everything it gives, and the chip itself left the hand along with
	-- the Puzzle chip the failed pick added.
	check("it gave two piggy banks", seat_card("south").stats.piggy == 2,
		seat_card("south").stats.piggy)
	check("and drew twice", count_in("hand", "south") == held + 1,
		held .. " -> " .. count_in("hand", "south"))
	check("the copied chip was trashed", entity.get(bot.id).zone_id == nil
		or entity.get(bot.id).zone_id == zones.find_id("void"))
	check("and the action phase is over", phase.current().key ~= "action", phase.current().key)
end

-- Future Sight puts the chips back in the order they were picked. Every arrival
-- lands on the end of a zone, so the last one named is the first one drawn.
function M.test_puzzle_strike_future_sight_returns_chips_in_the_order_picked(check)
	opening(7, "geiger", "jaina")
	local hand = zone_of("hand", "south")
	local fs   = find_in("hand", "future_sight", "south") or zones.add(hand, "future_sight")
	local one  = zones.add(hand, "gem_1")
	local two  = zones.add(hand, "gem_2")
	seat_card("south").stats.act_brown = 1

	check("it is played on the two gems, the 2 named last", flow.play_card(fs.id, { one.id, two.id }))
	local bag = zone_of("bag", "south")
	check("the last one picked is the one on top",
		bag.cards[#bag.cards] == two.id and bag.cards[#bag.cards - 1] == one.id,
		table.concat(keys_in("bag", "south"), " "))
end

-- Troublesome Rhetoric hands the question across the table: priority is theirs
-- while the offer is up, so from inside those two lines the benefit is "enemy",
-- which is the seat that played the chip.
function M.test_puzzle_strike_troublesome_rhetoric_lets_them_choose(check)
	opening(7, "degrey", "jaina")
	local tr = find_in("hand", "troublesome_rhetoric", "south")
		or zones.add(zone_of("hand", "south"), "troublesome_rhetoric")
	seat_card("south").stats.act_brown = 1
	seat_card("south").stats.money = 0
	seat_card("north").stats.money = 0

	check("south plays it", flow.play_card(tr.id, {}))
	check("and north is the one being asked", zones.active_seat() == "north", zones.active_seat())
	check("with both branches on offer", count_in("options") == 2, count_in("options"))

	flow.play_card(find_in("options", "tr_money").id, {})
	check("the gem power went to the seat that played the chip",
		seat_card("south").stats.money == 2, seat_card("south").stats.money)
	check("and not to the seat that chose", (seat_card("north").stats.money or 0) == 0,
		seat_card("north").stats.money)
	check("with the piggy bank on the same side",
		(seat_card("south").stats.piggy or 0) == 1, seat_card("south").stats.piggy)
	check("and priority came home", zones.active_seat() == "south", zones.active_seat())
end

-- "Main or Reaction" is one chip written twice. The reaction half crashes in
-- answer to a red chip, costs no action, and lands in its own discard.
function M.test_puzzle_strike_unstable_power_crashes_as_a_reaction(check)
	opening(7, "argagarg", "jaina")
	local one = zones.turn_seat()
	local two
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat ~= one then two = z.seat end
	end
	local up  = zones.add(zone_of("hand", two), "unstable_power")
	local gem = zones.add(zone_of("gem_pile", two), "gem_2")
	local red = zones.add(zone_of("hand", one), "sneak_attack")
	seat_card(one).stats.act_red = (seat_card(one).stats.act_red or 0) + 1
	local acts = seat_card(two).stats.act_brown or 0
	local piled = count_in("gem_pile", one, "gem_1")

	flow.play_card(red.id, {})
	check("the attack is announced", zones.active_seat() == two, zones.active_seat())
	local offer = flow.usable_reactions()
	local offered = false
	for _, o in ipairs(offer) do if o.card == up.id then offered = true end end
	check("and Unstable Power is one of the answers", offered, #offer)

	flow.react(up.id, 1, { gem.id })
	check("the 2-gem crashed across as two ones",
		count_in("gem_pile", one, "gem_1") == piled + 2, count_in("gem_pile", one, "gem_1"))
	check("two wounds came with it", count_in("discard", two, "wound") == 2,
		count_in("discard", two, "wound"))
	check("it cost no action", (seat_card(two).stats.act_brown or 0) == acts,
		seat_card(two).stats.act_brown)
	check("and it is spent to its own discard",
		count_in("discard", two, "unstable_power") == 1,
		table.concat(keys_in("discard", two), " "))
end

-- Hex of Murkwood, v1: a wound into their bag and then a 1-gem anted for every
-- wound in their discard pile. The order is the rule — the wound goes into the
-- bag, so it is not one of the ones counted.
function M.test_puzzle_strike_hex_of_murkwood_antes_one_per_wound(check)
	opening(7, "argagarg", "jaina")
	local hex = find_in("hand", "hex_of_murkwood", "south")
		or zones.add(zone_of("hand", "south"), "hex_of_murkwood")
	for _ = 1, 3 do zones.add(zone_of("discard", "north"), "wound") end
	seat_card("south").stats.act_red = 1
	local piled  = count_in("gem_pile", "north", "gem_1")
	local bagged = count_in("bag", "north")
	local stock  = find_in("bank", "stack_gem_1").stats.stock

	check("south plays it", flow.play_card(hex.id, {}))
	-- A red chip announces an attack before it does anything, so the hex lands
	-- only once the window it opened has closed.
	check("the attack is announced first", zones.active_seat() == "north", zones.active_seat())
	flow.pass_react()

	check("a wound went into their bag",
		count_in("bag", "north", "wound") == 1 and count_in("bag", "north") == bagged + 1,
		count_in("bag", "north"))
	check("their discard is untouched, so it is still three",
		count_in("discard", "north", "wound") == 3, count_in("discard", "north", "wound"))
	check("and they anted one gem for each of those three",
		count_in("gem_pile", "north", "gem_1") == piled + 3,
		count_in("gem_pile", "north", "gem_1"))
	check("the bank paid all three out",
		find_in("bank", "stack_gem_1").stats.stock == stock - 3,
		find_in("bank", "stack_gem_1").stats.stock)
end

-- The Shadows ten, and the shapes they needed. Nothing new was asked of the
-- engine for any of them — these are the four that are worth a test because the
-- shape is doing something the base ten only half used.

-- Flagstone Tax is a rule about somebody else's buying said as an answer to it:
-- an opponent buying over their own gem pile total is refused outright, and the
-- comparison has a subject on both sides.
function M.test_puzzle_strike_flagstone_tax_prices_an_opponent_out(check)
	local function bought(south_pile, north_pile)
		opening(7, "quince", "jaina")
		local ft = find_in("hand", "flagstone_tax", "south")
			or zones.add(zone_of("hand", "south"), "flagstone_tax")
		seat_card("south").stats.act_brown = 1
		flow.play_card(ft.id, {})
		flow.activate(find_in("controls", "done_acting").id, {})
		flow.activate(find_in("bank", "stack_wound").id, {}, 1)
		flow.activate(find_in("controls", "end_turn").id, {})
		flow.activate(find_in("controls", "done_acting").id, {})
		for _, seat in ipairs({ "south", "north" }) do
			local z = zone_of("gem_pile", seat)
			for _, id in ipairs(z.cards) do entity.get(id).zone_id = nil end
			z.cards = {}
		end
		for _ = 1, south_pile do zones.add(zone_of("gem_pile", "south"), "gem_1") end
		for _ = 1, north_pile do zones.add(zone_of("gem_pile", "north"), "gem_1") end
		seat_card("north").stats.money, seat_card("north").stats.buys = 20, 1
		local before = count_in("discard", "north", "roundhouse")
		flow.activate(find_in("bank", "stack_roundhouse").id, {}, 1)
		if zones.active_seat() ~= "north" then flow.pass_react() end
		return count_in("discard", "north", "roundhouse") > before
	end
	-- Roundhouse costs 6.
	check("the tax refuses a buy over their own pile total", not bought(3, 0))
	check("a pile that covers the price buys it", bought(3, 6))
	check("and under three of your own the tax says nothing", bought(2, 0))
end

-- Two Truths hands the pick across the table: priority crosses while the offer
-- is up, so from inside it "enemy" is the seat that played the chip.
function M.test_puzzle_strike_two_truths_lets_them_pick_out_of_your_pile(check)
	opening(7, "quince", "jaina")
	local tt = find_in("hand", "two_truths", "south")
		or zones.add(zone_of("hand", "south"), "two_truths")
	zones.add(zone_of("discard", "south"), "draw_three")
	seat_card("south").stats.act_brown = 1

	check("south plays it", flow.play_card(tt.id, {}))
	check("and north is the one reading the pile", zones.active_seat() == "north", zones.active_seat())
	check("with south's discard face up", find_in("options", "draw_three") ~= nil)

	flow.play_card(find_in("options", "draw_three").id, {})
	check("the pick lands in south's hand", count_in("hand", "south", "draw_three") == 1,
		count_in("hand", "south", "draw_three"))
	check("and priority came home", zones.active_seat() == "south", zones.active_seat())
end

-- Bonecracker is Pilebunker's rule aimed at a hand instead of a pile: the whole
-- hand comes up and only the largest gem in it may be clicked.
function M.test_puzzle_strike_bonecracker_takes_only_the_largest_gem(check)
	opening(7, "menelker", "jaina")
	local bc = find_in("hand", "bonecracker", "south")
		or zones.add(zone_of("hand", "south"), "bonecracker")
	local big = zones.add(zone_of("hand", "north"), "gem_3")
	local small = zones.add(zone_of("hand", "north"), "gem_1")
	seat_card("south").stats.act_red = 1

	flow.play_card(bc.id, {})
	-- A red chip announces an attack before it does anything.
	flow.pass_react()
	check("their whole hand is up", find_in("options", "gem_3") ~= nil
		and find_in("options", "gem_1") ~= nil)
	check("a smaller gem cannot be taken", not flow.play_card(small.id, {}))
	check("the largest can", flow.play_card(big.id, {}))
	check("and it went to their own discard", count_in("discard", "north", "gem_3") == 1,
		count_in("discard", "north", "gem_3"))
end

-- Into Oblivion reaches the bank, which nothing may point at: a plate is
-- "immutable" — scenery — so the bank comes up as an offer instead.
function M.test_puzzle_strike_into_oblivion_removes_a_bank_stack(check)
	opening(7, "menelker", "jaina")
	local io_ = find_in("hand", "into_oblivion", "south")
		or zones.add(zone_of("hand", "south"), "into_oblivion")
	seat_card("south").stats.act_brown = 1
	local banked = count_in("bank")

	check("it opens the bank", flow.play_card(io_.id, {}) and count_in("options") == banked,
		count_in("options") .. " of " .. banked)
	check("a gem plate is not one of the answers",
		not flow.play_card(find_in("options", "stack_gem_1").id, {}))
	flow.play_card(find_in("options", "stack_draw_three").id, {})
	check("the stack is out of the bank", count_in("bank") == banked - 1, count_in("bank"))
	check("and back in the box", find_in("chip_box", "stack_draw_three") ~= nil)
end

return M
