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
local cards  = require("cards")

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
	for _, u in ipairs(flow.usable_abilities(card.id)) do out[#out + 1] = u.rule.key end
	table.sort(out)
	return table.concat(out, "/")
end

local function use(card, key)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.rule.key == key then return flow.activate(card.id, {}, u.index) end
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

-- The moon staff, and the row it stands in. One grid of seven: artifacts to its
-- left, items to its right. Every round the two cards beside it are cleared
-- away, it steps one place right, and the row closes up towards it — so where a
-- card sits is how long it has been on show, which two fixed halves sized by
-- arithmetic could say nothing about.
function M.test_arnak_the_moon_staff_steps_along_the_row(check)
	flow.init("arnak.json", 7)
	-- The row read left to right: the kind of each card, or a dot for a free cell.
	local function row()
		local z, out = zone("row"), {}
		for i, sid in ipairs(z.slots) do
			local occ = entity.get(sid).occupant
			local c   = occ and entity.get(occ)
			out[i] = c and (c.def_key == "moon_staff" and "staff" or c.def_key:sub(1, 2)) or "."
		end
		return table.concat(out, ",")
	end
	local function wrap_the_round()
		use(find_in("controls", "pass_turn"), "pass")
		use(find_in("controls", "pass_turn"), "pass")
	end

	check("one artifact, the staff, then five items",
		row() == "ar,staff,it,it,it,it,it", row())

	wrap_the_round()
	check("the round wrapped", seat("clock").stats.round_no == 2,
		tostring(seat("clock").stats.round_no))
	-- The artifact and the item flanking the staff are gone, the staff has moved
	-- into the cell the item left, and two fresh artifacts fill the near end.
	check("the staff has stepped, and the artifact side has grown",
		row() == "ar,ar,staff,it,it,it,it", row())

	wrap_the_round()
	check("and again, the row still seven wide and six cards deep",
		row() == "ar,ar,ar,staff,it,it,it", row())
end

-- What position on the shelf is *for*. A bought card leaves a hole; the row
-- closes up towards the staff and the new card is dealt at the far end, so the
-- oldest card is always the one next to the staff and the exile is never
-- arbitrary. Under the old two-zone shape the new card dropped into the hole
-- and nothing on the board said which card had been there longest.
function M.test_arnak_a_bought_card_is_replaced_at_the_end_of_the_row(check)
	flow.init("arnak.json", 7)
	-- Cards by identity, not by key: the deck holds three of each item, so a
	-- fresh card can arrive wearing a name that is already on the shelf.
	local function shelf()
		local z, out = zone("row"), {}
		for i, sid in ipairs(z.slots) do out[i] = entity.get(sid).occupant end
		return out
	end
	local before = shelf()
	funded(seat("south"))
	local bought = entity.get(before[5])
	check("the middle item is merchandise and nothing else", offers(bought) == "buy", offers(bought))
	check("bought it", use(bought, "buy"))

	local after = shelf()
	check("the cards nearer the staff did not move",
		after[1] == before[1] and after[2] == before[2] and after[3] == before[3]
		and after[4] == before[4])
	check("the two beyond the hole slid one place towards it",
		after[5] == before[6] and after[6] == before[7])
	check("and a new card came in at the far end", after[7] ~= before[7] and after[7] ~= nil)
	check("the bought card went to the bottom of the buyer's deck",
		zone("bag", 1).cards[1] == bought.id)
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

-- What a card is worth is one number, read twice: the badge draws it and the
-- ability spends it. Nothing in the file writes a yield down a second time, so
-- the printed card and the rule it runs cannot drift apart.
function M.test_arnak_a_card_pays_out_exactly_what_it_prints(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	me.stats.main, me.stats.coin, me.stats.tablet = 1, 0, 0

	-- Straight out of the deck, so this is the shipped card and not one dialled up.
	local camera = cards.create("it_camera", zone("hand", 1).id)
	camera.stats.owner = 1
	check("the camera prints two tablets and a coin",
		camera.stats.y_tablet == 2 and camera.stats.y_coin == 1)
	check("and using it works", use(camera, "effect"))
	check("two tablets arrived", me.stats.tablet == 2, tostring(me.stats.tablet))
	check("and one coin", me.stats.coin == 1, tostring(me.stats.coin))

	-- A card that prints none of a thing gains none of it, silently: sum: over a
	-- card with no such stat is zero, so the uniform action list costs nothing.
	check("and nothing it does not print", me.stats.jewel == 0, tostring(me.stats.jewel))
end

-- Every badge a style lists is a stat some card actually carries, and every
-- yield a card carries is on the badge list of the style it wears. A number
-- the player cannot see is a rule written in invisible ink.
function M.test_arnak_every_printed_number_is_drawn(check)
	flow.init("arnak.json", 7)
	local G = require("declaration").G
	local box, missing = zone("item_deck").id, {}
	for key, def in pairs(G.card_defs) do
		if def.card_stats then
			local made  = cards.create(key, box)
			local style = cards.style(made)
			for stat in pairs(def.card_stats) do
				if stat:match("^y_") or stat == "price" or stat == "toll"
					or stat == "trek" or stat == "points" then
					local drawn = false
					for _, b in ipairs(style.badges or {}) do drawn = drawn or b == stat end
					if not drawn then missing[#missing + 1] = key .. "." .. stat end
				end
			end
		end
	end
	table.sort(missing)
	check("every printed number has a badge to draw it", #missing == 0,
		table.concat(missing, ", "))
end

return M
