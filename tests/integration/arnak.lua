-- Lost Ruins of Arnak, and the four things about it a rules summary cannot
-- confirm.
--
-- Every other game in the box says what a card does; Arnak's cards say two
-- things and the player picks one, so the hand is a zone of *abilities* rather
-- than a zone of plays. That decision is what the first two tests are about.
-- The third is worker placement, which ideas/21 predicted would resolve into
-- exhaust-on-the-space plus a capped counter — worth checking that it actually
-- does. The fourth is the moon staff: the card row's two halves are sized off
-- the round number by clamped subtraction, and nothing else in the file is
-- arithmetic.

local entity = require("entity")
local zones  = require("zones")
local phase  = require("phase")
local flow   = require("flow")

local M = {}

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function zone(key, i)
	local all = zones.all_with_key(key)
	return i and all[i] or all[1]
end

local function keys(z)
	local out = {}
	for _, cid in ipairs(z.cards) do out[#out + 1] = entity.get(cid).def_key end
	return table.concat(out, ",")
end

local function find_in(zone_key, def_key, i)
	for _, cid in ipairs(zone(zone_key, i).cards) do
		local c = entity.get(cid)
		if def_key == nil or c.def_key == def_key then return c end
	end
end

local function offers(card)
	local out = {}
	for _, u in ipairs(flow.usable_abilities(card.id)) do out[#out + 1] = u.ability.key end
	table.sort(out)
	return table.concat(out, "/")
end

local function use(card, key)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.ability.key == key then return flow.activate(card.id, {}, u.index) end
	end
	return false
end

-- Rich enough to buy, dig and research without the deck having to cooperate.
local function funded(who)
	for _, k in ipairs({ "coin", "compass", "tablet", "arrowhead", "jewel", "travel" }) do
		who.stats[k] = 30
	end
end

-- A card in hand is played for its printed effect or for its travel value, and
-- never both. Two abilities on one card, so clicking it asks which.
function M.test_arnak_a_card_is_an_effect_or_a_journey(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	local card = find_in("hand", nil, 1)
	check("a hand card offers exactly two things", offers(card) == "effect/travel", offers(card))

	local before = me.stats.travel
	check("travel is where it goes", use(card, "travel"))
	check("and the printed value is what arrives",
		me.stats.travel == before + card.stats.trek, tostring(me.stats.travel))
	check("the card is spent into the play area", keys(zone("table", 1)) ~= "")
end

-- Fear has no effect half, which is what "this chip does nothing" looks like
-- when the doing is an ability rather than a play.
function M.test_arnak_fear_can_only_be_travelled_with(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	me.stats.travel = 0
	local fear = find_in("bag", "fear", 1) or find_in("hand", "fear", 1)
	check("there is a fear card", fear ~= nil)
	-- Put it in hand where it can be reached, whichever end of the deck it was on.
	zones.move_card(fear.id, zone("hand", 1).id)
	check("it offers travel and nothing else", offers(fear) == "travel", offers(fear))
	check("−1 a piece at the end", (fear.stats.points or 0) == 0)
end

-- Worker placement, as ideas/21 predicted it: the *space* carries the exhaust,
-- the player carries a capped counter, and the two gates are independent.
function M.test_arnak_a_space_is_taken_and_an_archaeologist_is_spent(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	local beach = find_in("island", "site_beach")

	check("two archaeologists to start the round", me.stats.workers == 2)
	check("digging works", use(beach, "dig"))
	check("it spends one of them", me.stats.workers == 1, tostring(me.stats.workers))
	check("and the main action", me.stats.main == 0)

	-- The space itself is now taken, for everybody, until the round wraps.
	me.stats.main = 1
	check("nobody may dig there again this round", offers(beach) == "", offers(beach))

	-- The other gate, asked of the player rather than of the space.
	local jungle = find_in("island", "site_jungle")
	check("a second, different site is still open", offers(jungle) == "dig", offers(jungle))
	check("digging there spends the last archaeologist", use(jungle, "dig"))
	me.stats.main = 1
	local cliffs = find_in("island", "site_cliffs")
	check("and now no site will take one", offers(cliffs) == "", offers(cliffs))
end

-- Discovery reveals a printed position rather than growing the board, wakes a
-- guardian with the tile, and hands out the idol.
function M.test_arnak_discovery_reveals_a_position_that_was_always_there(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	local before = #zone("island").cards
	local marker = find_in("island", "pos_1")

	check("discovering works", use(marker, "discover"))
	check("the island is the same size it was", #zone("island").cards == before,
		tostring(#zone("island").cards))
	check("an idol came back with it", keys(zone("idols", 1)) == "idol", keys(zone("idols", 1)))
	check("and an archaeologist stands under a guardian", me.stats.guarded == 1)

	local site
	for _, cid in ipairs(zone("island").cards) do
		local c = entity.get(cid)
		if (c.stats.guard or 0) >= 1 then site = c end
	end
	check("the new site woke a guardian", site ~= nil)
	me.stats.main, me.stats.workers = 1, 2
	check("which offers to be fought and does not block the dig",
		offers(site) == "dig_guarded/overcome", site and offers(site))

	check("overcoming it works", use(site, "overcome"))
	check("it is worth five at the end", me.stats.guardians == 1)
	check("and the archaeologist is no longer under one", me.stats.guarded == 0)
end

-- The notebook may never sit above the magnifying glass. Written as a condition
-- on the row rather than as a rule anywhere in the engine.
function M.test_arnak_the_notebook_follows_the_glass(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	local row = find_in("research", "res_1")
	check("only the glass may move first", offers(row) == "glass", offers(row))
	check("and it moves", use(row, "glass"))
	check("the glass is on row one", me.stats.glass == 1)

	me.stats.main = 1
	check("now the notebook may follow", offers(row) == "note", offers(row))
	check("and it does", use(row, "note"))
	check("both stand on row one", me.stats.note == 1 and me.stats.glass == 1)

	check("the temple is the glass's alone",
		find_in("research", "res_6").def_key == "res_6")
end

-- The moon staff. One artifact and five items at the start; one slot moves
-- across every round, and the row always shows six cards.
function M.test_arnak_the_moon_staff_moves_one_slot_a_round(check)
	flow.init("arnak.json", 7)
	local function shown()
		return #zone("artifacts").cards, #zone("items").cards
	end
	local a, i = shown()
	check("round one deals one artifact and five items", a == 1 and i == 5, a .. "/" .. i)

	-- Both seats pass, which is the only thing that ends a round.
	use(find_in("controls", "pass_turn"), "pass")
	use(find_in("controls", "pass_turn"), "pass")
	check("the round wrapped", seat("clock").stats.round_no == 2,
		tostring(seat("clock").stats.round_no))
	a, i = shown()
	check("round two deals two artifacts and four items", a == 2 and i == 4, a .. "/" .. i)
	check("the row is still six cards wide", a + i == 6)
end

-- Five rounds and then the count. Nothing scores while the game is running
-- except the temple, so this is where the whole tally is checked at once.
function M.test_arnak_five_rounds_and_then_the_count(check)
	flow.init("arnak.json", 7)
	local south, north = seat("south"), seat("north")

	-- One idol for north, and nothing at all for south. North is not up yet, so
	-- south passes first — and the funding has to come *after* the handover,
	-- since entering a turn is what clears the travel a player did not spend.
	use(find_in("controls", "pass_turn"), "pass")
	check("north is up", zones.active_seat() == "north", tostring(zones.active_seat()))
	funded(north)
	check("north discovers", use(find_in("island", "pos_1"), "discover"))

	for _ = 1, 30 do
		if phase.current().key ~= "turn" then break end
		use(find_in("controls", "pass_turn"), "pass")
	end
	check("the game reached its ending", phase.current().key == "reveal",
		phase.current().key)
	check("round six is the one nobody plays", seat("clock").stats.round_no == 6,
		tostring(seat("clock").stats.round_no))

	-- Three for the idol, less one for each of the two starting fear cards, and
	-- one more for the fear the guarded site cost at the round's end.
	check("north scored the idol and paid for the fear",
		north.stats.score == 0, tostring(north.stats.score))
	check("south, who did nothing, is two fear down",
		south.stats.score == -2, tostring(south.stats.score))
	check("and the engine knows who won", north.stats.won == 1 and (south.stats.won or 0) == 0,
		tostring(north.stats.won) .. "/" .. tostring(south.stats.won))
end

return M
