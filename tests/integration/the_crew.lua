-- The Crew, and the four rules a trick-taking game is made of.
--
-- None of them is a new engine word. Follow-suit is one condition on every card
-- read against flow's escape hatch; the trump rule is a hundred added to a
-- number; the winner is the card whose contend fell short of the best by
-- nothing; and "the winner leads" is set_active_seat, which is the one thing
-- this game waited on. These tests are pointed at the arithmetic and at the
-- handover, because a rules summary cannot confirm either.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")

local M = {}

-- Four crew members, in the order they play. Read from the game rather than
-- written down twice: a trick is one card per seat, whatever that number is.
local function seats()
	return require("declaration").G.seat_list
end

-- Cards of a colour nothing in the scenario is using, for the seats whose play
-- does not matter. Off-suit, so none of them ever contends.
local function filler(n, named)
	local used = {}
	for _, k in ipairs(named) do used[k:match("^(%a+)_")] = true end
	for _, colour in ipairs({ "pink", "blue", "green", "yellow" }) do
		if not used[colour] then
			local out = {}
			for i = 1, n do out[i] = colour .. "_" .. i end
			return out
		end
	end
	error("no spare colour left for filler")
end

local function find(def_key)
	for e in entity.each("card") do
		if e.def_key == def_key and e.zone_id then return e end
	end
end

local function hand_of(seat)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == seat then return z end
	end
end

local function keys_in(z)
	local out = {}
	for i, id in ipairs(z.cards) do out[i] = entity.get(id).def_key end
	return out
end

-- Deal by hand: everything held goes back out of play, then the named cards
-- come in. A card in a hand belongs to that hand's seat, so this is all the
-- ownership these tests need to state.
local function set_hands(spec)
	local sink = zones.find_id("won")
	for _, z in ipairs(zones.all_with_key("hand")) do
		local ids = {}
		for i, id in ipairs(z.cards) do ids[i] = id end
		for _, id in ipairs(ids) do zones.move_card(id, sink) end
	end
	for seat, keys in pairs(spec) do
		for _, k in ipairs(keys) do zones.move_card(find(k).id, hand_of(seat).id) end
	end
end

-- Start a mission with n tasks, take the whole offer with the first player who
-- is asked, and stop at the first lead.
local function mission(seed, n, taker)
	flow.init("the_crew.json", seed)
	for _, id in ipairs(zones.find("mission").cards) do
		if entity.get(id).def_key == "m_" .. n then flow.play_card(id, {}) break end
	end
	while phase.current().key:find("^draft") do
		if taker then actions.execute("set_active_seat:" .. taker .. "_side", {}) end
		flow.play_card(zones.find("task_offer").cards[1], {})
	end
end

local function playable(seat)
	local out = {}
	for _, id in ipairs(hand_of(seat).cards) do
		if flow.can_play(id) then out[#out + 1] = entity.get(id).def_key end
	end
	table.sort(out)
	return out
end

local function play(key)
	return flow.play_card(find(key).id, {})
end

-- Lead from `seat`, then let the rest follow in seat order. One card per seat,
-- so a scenario names the cards it cares about and the rest is filler.
local function trick(seat, plays)
	assert(#plays == #seats(), "a trick is one card per seat")
	actions.execute("set_active_seat:" .. seat .. "_side", {})
	for _, k in ipairs(plays) do play(k) end
end

-- The hands a scenario names, plus a filler card each for the seats it does
-- not, laid out so the named ones play in the order given.
local function stage(lead, named)
	local order, spec, plays = seats(), {}, {}
	local at = nil
	for i, k in ipairs(order) do if k == lead then at = i end end
	local spare = filler(#order, named)
	local s = 0
	for i = 1, #order do
		local seat = order[(at + i - 2) % #order + 1]
		local card = named[i]
		if not card then s = s + 1; card = spare[s] end
		spec[seat] = { card }
		plays[i] = card
	end
	set_hands(spec)
	return plays
end

function M.test_crew_the_deck_is_the_published_one(check)
	flow.init("the_crew.json", 3)
	local defs = require("declaration").G.card_defs
	local play_cards, tasks, rockets = 0, 0, 0
	for key, def in pairs(defs) do
		if (def.tags_set or {}).play_card then
			play_cards = play_cards + 1
			if key:find("^rocket_") then rockets = rockets + 1 end
		end
		if (def.tags_set or {}).task then tasks = tasks + 1 end
	end
	check("forty playing cards", play_cards == 40, tostring(play_cards))
	check("four of them rockets", rockets == 4, tostring(rockets))
	check("thirty-six tasks, one per colour card", tasks == 36, tostring(tasks))
	-- No rocket task: a card nobody can be asked to win is a rule, not an omission.
	check("and none of them names a rocket", defs.task_rocket_1 == nil)

	-- Nothing is dealt until the crew has said how many tasks they want: the
	-- opening overlay is the mission, and the shuffle waits for it.
	check("nothing is dealt before the mission is chosen", #zones.find("deck").cards == 40)
	mission(3, 2)
	local dealt = 0
	for _, z in ipairs(zones.all_with_key("hand")) do dealt = dealt + #z.cards end
	check("then every card is dealt", dealt == 40, tostring(dealt))
	check("and the deck is empty", #zones.find("deck").cards == 0)
	local even = true
	for _, z in ipairs(zones.all_with_key("hand")) do
		even = even and #z.cards == dealt / #seats()
	end
	check("split evenly between the crew", even, tostring(#hand_of("north").cards))
end

-- The whole of follow-suit is one condition, the same on all forty cards, read
-- against flow's escape hatch. Three cases, and the third is the one that only
-- works because the hatch exists.
function M.test_crew_follow_the_suit_that_was_led(check)
	mission(3, 1)
	set_hands({
		north = { "pink_9", "pink_2", "blue_5", "rocket_1" },
		east  = { "green_3", "green_8", "yellow_4" },
		south = { "yellow_2", "blue_7" },
		west  = { "green_1" },
	})

	actions.execute("set_active_seat:north_side", {})
	check("leading, every card in hand is legal", #playable("north") == 4,
		table.concat(playable("north"), " "))

	play("pink_9")
	check("the led suit is remembered", find("flight_plan").stats.led == 1)

	-- east holds no pink at all, so anything goes — which is the hatch opening,
	-- not a rule of its own.
	local free = playable("east")
	check("holding none of it, anything may be played", #free == 3, table.concat(free, " "))

	-- ...and once east has pink, only pink.
	set_hands({
		north = { "pink_2" },
		east  = { "green_3", "green_8", "pink_4" },
		south = { "yellow_2" },
		west  = { "green_1" },
	})
	local bound = playable("east")
	check("holding it, only it may be played",
		#bound == 1 and bound[1] == "pink_4", table.concat(bound, " "))
end

-- A rocket is a suit like any other: led first it must be followed, and played
-- off-suit it wins anyway. Both halves fall out of the same two numbers.
function M.test_crew_the_rocket_is_trump_and_a_suit(check)
	mission(3, 1)
	set_hands({
		north = { "rocket_2" },
		east  = { "rocket_1", "green_9" },
		south = { "yellow_8" },
		west  = { "yellow_7" },
	})
	actions.execute("set_active_seat:north_side", {})
	play("rocket_2")
	local bound = playable("east")
	check("a rocket led must be followed with a rocket",
		#bound == 1 and bound[1] == "rocket_1", table.concat(bound, " "))
	play("rocket_1")
	play("yellow_8")
	play("yellow_7")
	check("and the higher rocket takes it", zones.active_seat() == "north",
		tostring(zones.active_seat()))

	-- The other half: the lowest rocket beats the highest colour card, and only
	-- a seat with none of the led suit may play one.
	mission(3, 1)
	trick("north", stage("north", { "green_9", "green_1" }))
	check("without a rocket the highest of the led suit wins",
		zones.active_seat() == "north", tostring(zones.active_seat()))

	mission(3, 1)
	trick("north", stage("north", { "green_9", "yellow_2", "rocket_1" }))
	check("the lowest rocket beats the highest colour", zones.active_seat() == "south",
		tostring(zones.active_seat()))
	check("and an off-suit nine wins nothing", zones.active_seat() ~= "east")
end

-- The winner leads. This is the one thing the game could not be built without,
-- and the whole of it is one action reading whose the winning card is.
function M.test_crew_the_winner_leads_the_next_trick(check)
	mission(3, 1)
	set_hands({
		north = { "blue_2", "pink_1" },
		east  = { "blue_8", "pink_9" },
		south = { "blue_5", "pink_3" },
		west  = { "blue_4", "pink_6" },
	})
	trick("north", { "blue_2", "blue_8", "blue_5", "blue_4" })
	check("the highest of the led suit took it", zones.active_seat() == "east",
		tostring(zones.active_seat()))
	check("and is the one asked to lead", phase.current().key == "lead")
	check("the trick was set aside", #zones.find("trick").cards == 0)
	check("one trick has been played", find("flight_plan").stats.tricks == 1)

	-- ...and the seats that follow are the two after the winner, in order.
	play("pink_9")
	check("the seat after the winner follows first", zones.active_seat() == "south",
		tostring(zones.active_seat()))
end

-- Whoever was dealt the rocket 4 picks first and leads first. It is a fact
-- about the shuffle, not about the seat list, which is why it needed asking.
function M.test_crew_the_commander_is_whoever_holds_the_rocket_four(check)
	for _, seed in ipairs({ 1, 2, 3, 5, 8 }) do
		flow.init("the_crew.json", seed)
		for _, id in ipairs(zones.find("mission").cards) do
			if entity.get(id).def_key == "m_2" then flow.play_card(id, {}) break end
		end
		local holder
		for _, z in ipairs(zones.all_with_key("hand")) do
			for _, k in ipairs(keys_in(z)) do
				if k == "rocket_4" then holder = z.seat end
			end
		end
		check("seed " .. seed .. ": the rocket 4 holder picks first",
			zones.active_seat() == holder, tostring(zones.active_seat()) .. " vs " .. tostring(holder))
		-- The draft hands round the table, so the lead has to come back to them.
		while phase.current().key:find("^draft") do
			flow.play_card(zones.find("task_offer").cards[1], {})
		end
		check("seed " .. seed .. ": and leads the first trick",
			zones.active_seat() == holder, tostring(zones.active_seat()))
	end
end

-- A task is done when its owner wins the trick its card turns up in, and the
-- mission is over the moment anybody else wins that card. Both are one question
-- asked of the trick that just closed — no reasoning about hidden hands.
function M.test_crew_a_task_is_won_by_the_right_seat_or_not_at_all(check)
	mission(3, 1, "north")
	-- The zones come back in seat order, so the first is the seat that took
	-- every task on offer. Its card names one playing card; win that.
	local want = entity.get(zones.all_with_key("tasks")[1].cards[1]).def_key:gsub("^task_", "")
	trick("north", stage("north", { want }))
	check("the task's owner won its card", zones.active_seat() == "north",
		tostring(zones.active_seat()))
	check("so the task is done and filed", #zones.all_with_key("tasks")[1].cards == 0)
	local filed = 0
	for _, z in ipairs(zones.all_with_key("archive")) do filed = filed + #z.cards end
	check("in the crew member's own done pile", filed == 1, tostring(filed))
	check("and the mission is complete", phase.current().key == "reveal"
		or phase.current().key == "over", phase.current().key)
end

function M.test_crew_the_wrong_seat_winning_a_task_card_ends_it(check)
	mission(3, 1, "north")
	local want = entity.get(zones.all_with_key("tasks")[1].cards[1]).def_key:gsub("^task_", "")
	local high = want:gsub("_%d+$", "_9")
	if high == want then high = want:gsub("_%d+$", "_8") end
	-- south leads the card north needed; east has none of that colour and takes
	-- the trick with a rocket, which is the loss the rules name.
	-- Play order from south is south, west, north, east: south leads the card
	-- north needs, north's own higher one would take it, and east's rocket
	-- takes it instead — which is the loss the rules name.
	local off = want:find("^pink") and "blue_2" or "pink_2"
	set_hands({ south = { want }, west = { off }, north = { high }, east = { "rocket_4" } })
	trick("south", { want, off, high, "rocket_4" })
	check("the trick went to the wrong seat", zones.active_seat() == "east",
		tostring(zones.active_seat()))
	check("and the mission ended on the spot",
		phase.current().key == "reveal" or phase.current().key == "over", phase.current().key)
	local r = zones.find("reveal")
	local shown = r and r.cards[1] and entity.get(r.cards[1]).def_key
	check("saying so", shown == "mission_lost", tostring(shown))
end

-- Nothing about the trick is written down twice: the led suit is set once, by a
-- phase between the lead and the follows. Written into every card's own play it
-- would be overwritten by the second player and the third would follow a suit
-- nobody led.
function M.test_crew_the_led_suit_is_written_once(check)
	mission(3, 1)
	set_hands({
		north = { "green_4", "green_6" },
		east  = { "yellow_7", "green_2" },
		south = { "blue_3", "green_5" },
		west  = { "pink_8", "green_1" },
	})
	actions.execute("set_active_seat:north_side", {})
	play("green_4")
	check("the lead sets it", find("flight_plan").stats.led == 3)
	play("green_2")
	check("the second play leaves it alone", find("flight_plan").stats.led == 3)
	local bound = playable("south")
	check("so the third seat still has to follow green",
		#bound == 1 and bound[1] == "green_5", table.concat(bound, " "))
	play("green_5")
	local last = playable("west")
	check("and so does the last", #last == 1 and last[1] == "green_1",
		table.concat(last, " "))
	play("green_1")
	check("and it is cleared for the next trick", find("flight_plan").stats.led == 0)
end

-- Thirteen tricks and the deal is spent — the fourteenth card one crew member
-- holds is never played, which is what a forty-card deck dealt three ways
-- means. Anything still outstanding then is a mission failed.
function M.test_crew_the_tricks_run_out(check)
	mission(3, 1, "north")
	local want = entity.get(zones.all_with_key("tasks")[1].cards[1]).def_key:gsub("^task_", "")
	local last = 40 / #seats()
	find("flight_plan").stats.tricks = last - 1
	-- A trick that finishes nothing: the wanted card stays in a hand.
	trick("north", stage("north", { want:find("^pink") and "blue_9" or "pink_9" }))
	check("the last trick is the deal's last", find("flight_plan").stats.tricks == last,
		tostring(find("flight_plan").stats.tricks))
	local r = zones.find("reveal")
	local shown = r and r.cards[1] and entity.get(r.cards[1]).def_key
	check("with a task outstanding, the mission is failed", shown == "mission_lost",
		tostring(shown))
end

-- The two clamps, stated on their own rather than only through a trick.
-- [23](../../ideas/23-splendor.md) found that a floor of zero makes
-- stat_damage into max(0, a - b) and closed by saying a clamp at *one* was
-- still missing. It is not: min(a, k) is a - max(0, a - k), the same floor used
-- twice, and that is what folds "followed the suit" and "is a rocket" back into
-- one flag. Asserted here because it is the arithmetic the whole game rests on.
function M.test_crew_a_floor_of_zero_gives_both_clamps(check)
	mission(3, 1)
	local c = find("pink_5")
	local ctx = { card_id = c.id }
	for _, case in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 1 }, { 3, 1 }, { 5, 0 } }) do
		c.stats.contend, c.stats.best = case[1], case[2]
		actions.execute("stat_set:gap@self:sum:contend@self", ctx)
		actions.execute("stat_damage:gap@self:sum:best@self", ctx)
		local want = math.max(0, case[1] - case[2])
		check(("max(0, %d - %d) is %d"):format(case[1], case[2], want),
			c.stats.gap == want, tostring(c.stats.gap))
	end
	for _, case in ipairs({ { 0, 1 }, { 1, 1 }, { 2, 1 }, { 7, 1 }, { 7, 3 }, { 2, 3 } }) do
		c.stats.live = case[1]
		actions.execute("stat_set:over@self:sum:live@self", ctx)
		actions.execute("stat_damage:over@self:" .. case[2], ctx)
		actions.execute("stat_damage:live@self:sum:over@self", ctx)
		local want = math.min(case[1], case[2])
		check(("min(%d, %d) is %d"):format(case[1], case[2], want),
			c.stats.live == want, tostring(c.stats.live))
	end
end

return M
