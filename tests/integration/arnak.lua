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

-- One of a seat's archaeologists, still at home. `i` is which seat's camp.
local function digger(i, nth)
	local found = 0
	for _, cid in ipairs(zone("camp", i or 1).cards) do
		local c = entity.get(cid)
		if c.def_key == "digger" then
			found = found + 1
			if found == (nth or 1) then return c end
		end
	end
end

local function has_tag(e, tag)
	for _, t in ipairs((cards.def(e) or {}).tags or {}) do
		if t == tag then return true end
	end
	return false
end

local function guardian_on(site)
	for _, id in ipairs(entity.get(site.id).attached or {}) do
		local c = entity.get(id)
		if c and has_tag(c, "guardian") then return c end
	end
end

-- The site a guardian is lying on. There is none until a position is discovered:
-- the five that start face up are the ones nothing is standing over.
local function guarded_site()
	for _, cid in ipairs(zone("island").cards) do
		local c = entity.get(cid)
		if not c.parent_id and guardian_on(c) then return c end
	end
end

local function offers(card)
	local out = {}
	for _, u in ipairs(flow.usable_abilities(card.id)) do out[#out + 1] = u.rule.key end
	table.sort(out)
	return table.concat(out, "/")
end

local function use(card, key, targets)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.rule.key == key then return flow.activate(card.id, targets or {}, u.index) end
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

-- Worker placement, and the figure is the worker. ideas/21 predicted the space
-- would carry an exhaust and the player a capped counter; it does neither now,
-- because a counter says *you took some space* and never *you took this one* —
-- which is the hole ideas/36 was written to close.
function M.test_arnak_a_figure_takes_the_space_it_is_standing_on(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	local beach = find_in("island", "site_beach")
	local one, two = digger(1, 1), digger(1, 2)

	check("two archaeologists, at home", one ~= nil and two ~= nil and one.id ~= two.id)
	check("digging works", use(one, "dig", { beach.id }))
	check("the figure is standing on the site", entity.get(one.id).parent_id == beach.id)
	check("it is spent for the round", entity.get(one.id).exhausted == true)
	check("and the main action went with it", me.stats.main == 0)

	-- The space is taken because somebody is standing on it, which is a fact
	-- about the board and not a number on either player.
	me.stats.main = 1
	check("the other figure may not join it there", use(two, "dig", { beach.id }) == false)

	local jungle = find_in("island", "site_jungle")
	check("but a free site takes it", use(two, "dig", { jungle.id }))
	check("and it is standing there", entity.get(two.id).parent_id == jungle.id)
	me.stats.main = 1
	local cliffs = find_in("island", "site_cliffs")
	check("with both figures out, nothing is left to send",
		use(one, "dig", { cliffs.id }) == false and use(two, "dig", { cliffs.id }) == false)
end

-- The bug this replaced: `overcome` gated on a per-seat tally, so digging the
-- site with the best yield and then paying off the cheapest guardian anywhere
-- on the board cost no Fear at all. The gate is now the figure.
function M.test_arnak_a_guardian_is_fought_by_whoever_is_standing_there(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	local one, two = digger(1, 1), digger(1, 2)

	check("discovering works", use(one, "discover_1", { find_in("island", "pos_1").id }))
	local site = guarded_site()
	check("a guardian came up with the site", site ~= nil)
	local beast = guardian_on(site)
	check("it is lying on the site rather than printed on it", beast.parent_id == site.id)
	check("nobody is standing there, so nobody may fight it",
		offers(beast) == "", offers(beast))

	me.stats.main = 1
	check("so send a figure", use(two, "dig", { site.id }))
	me.stats.main = 1
	check("now it can be fought", offers(beast) == "overcome", offers(beast))
	check("overcoming it works", use(beast, "overcome"))
	check("the guardian is gone from the board", entity.get(beast.id) == nil
		or entity.get(beast.id).zone_id == nil)
	check("the site is clear of it", guardian_on(site) == nil)
	check("and it is worth five at the end", me.stats.guardians == 1)
end

-- Fear is what a figure brings home, not a number a rule keeps: the archaeologist
-- that left a site with the guardian still standing is the one that earns it.
function M.test_arnak_fear_is_counted_off_the_figures(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	local one, two = digger(1, 1), digger(1, 2)

	use(one, "discover_1", { find_in("island", "pos_1").id })
	local site = guarded_site()
	me.stats.main = 1
	check("a figure digs where a guardian still stands", use(two, "dig", { site.id }))

	local function fears()
		local n = 0
		for _, key in ipairs({ "bag", "hand", "table" }) do
			for _, cid in ipairs(zone(key, 1).cards) do
				if entity.get(cid).def_key == "fear" then n = n + 1 end
			end
		end
		return n
	end
	local before = fears()
	check("the deck opens with two of them", before == 2, tostring(before))
	use(find_in("controls", "pass_turn"), "pass")
	use(find_in("controls", "pass_turn"), "pass")
	check("one more came home with the figure", fears() == before + 1, tostring(fears()))
	check("and the figures are back in camp",
		entity.get(two.id).parent_id == nil and entity.get(two.id).zone_id == zone("camp", 1).id)
end

-- Discovery reveals a printed position rather than growing the board, and hands
-- out the idol. The marker is a card a figure is sent to, so the level it names
-- is which of the two decks answers.
function M.test_arnak_discovery_reveals_a_position_that_was_always_there(check)
	flow.init("arnak.json", 7)
	local me = seat("south")
	funded(me)
	-- Counting what stands in a cell. A guardian is in the zone too, lying on a
	-- site, and the point of the check is that the board is fifteen squares.
	local function tiles()
		local n = 0
		for _, cid in ipairs(zone("island").cards) do
			if not entity.get(cid).parent_id then n = n + 1 end
		end
		return n
	end
	local before = tiles()
	local marker = find_in("island", "pos_1")

	check("discovering works", use(digger(1, 1), "discover_1", { marker.id }))
	check("the island is the same size it was", tiles() == before, tostring(tiles()))
	check("an idol came back with it", keys(zone("idols", 1)) == "idol", keys(zone("idols", 1)))
	check("the new site came up with a guardian lying on it", guarded_site() ~= nil)
	check("and the five that started face up have none",
		guardian_on(find_in("island", "site_beach")) == nil)
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
	check("north discovers", use(digger(2, 1), "discover_1", { find_in("island", "pos_1").id }))

	for _ = 1, 30 do
		if phase.current().key ~= "turn" then break end
		use(find_in("controls", "pass_turn"), "pass")
	end
	check("the game reached its ending", phase.current().key == "reveal",
		phase.current().key)
	check("round six is the one nobody plays", seat("clock").stats.round_no == 6,
		tostring(seat("clock").stats.round_no))

	-- Three for the idol, less one for each of the two starting fear cards. The
	-- figure that discovered came straight home, so no guardian was left standing
	-- over it and no third fear was earned.
	check("north scored the idol and paid for the fear",
		north.stats.score == 1, tostring(north.stats.score))
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
