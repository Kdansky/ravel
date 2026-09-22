-- The Grimm Forest: three pigs, one pile of straw, and the division of it.
--
-- The rule this file exists for is *sharing a Location*: what lies there is
-- split between the pigs standing on it, rounded down, and the remainder is
-- left for next round. That is one compute with a `/` in it, and the thing that
-- makes it right is **when** it is read — once, before anybody collects, so the
-- second pig does not divide what the first one left behind.
--
-- The other two are the Gather card standing in for a place (it is the only
-- card in the round that knows where its owner went, so every "at your
-- Location" rule is written on it), and the Starting Player marker, which is a
-- turn order read off `(seat_no - round) % 3`.

local entity = require("entity")
local zones = require("zones")
local phase = require("phase")
local flow = require("flow")

local M = {}

local function start(seed)
	flow.init("grimm.json", seed or 11)
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- A per-seat zone is addressed by its seat rather than by "mine": which copy a
-- card landed in is usually the thing under test.
local function box(key, seat_key)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == seat_key then return z end
	end
	return zones.find(key)
end

local function card_in(z, def_key)
	for _, id in ipairs((z or {}).cards or {}) do
		local c = entity.get(id)
		if c.def_key == def_key then return c end
	end
end

local function board(key)
	return card_in(zones.find("locations"), key .. "_board")
end

local function pigs(where)
	return #zones.find(where).cards
end

-- One player's half of the Gather phase: the card they play, then no Fable.
local function commit(where)
	local s = zones.active_seat()
	local g = card_in(box("plan", s), "g_" .. where)
	if not (g and flow.play_card(g.id, {})) then return s .. " could not go to " .. where end
	local p = card_in(box("fables", s), "no_fable")
	if not (p and flow.play_card(p.id, {})) then return s .. " could not decline a Fable" end
end

-- Everybody commits, in whatever order the round put them in. `choices` is
-- keyed by seat, because the order is exactly what some of these tests are
-- about and hard-coding it would hide the answer.
local function gather(choices)
	for _ = 1, 3 do
		local s = zones.active_seat()
		local why = commit(choices[s])
		if why then return why end
	end
end

local function order()
	local out = {}
	for _, k in ipairs({ "orange", "blue", "green" }) do out[#out + 1] = seat(k).stats.turnpos end
	return table.concat(out, " ")
end

local function tool(key)
	return card_in(zones.find("tools"), key)
end

local function use(key, index)
	local c = tool(key)
	return c ~= nil and flow.activate(c.id, {}, index or 1)
end

-- Spend whatever is left of a build turn on straw, which is always available.
local function idle()
	while phase.current().key == "build_turn" and seat(zones.active_seat()).stats.acts > 0 do
		if not use("gain_straw") then return false end
	end
	return true
end

-- Abilities are looked up by name: which index a rule has depends on how many
-- of its neighbours are usable right now, and that changes as a house grows.
local function ability(card, key)
	for _, u in ipairs(flow.usable_abilities(card.id)) do
		if u.rule.key == key then return u.index end
	end
end

local function build(card, key)
	local i = ability(card, key)
	return i ~= nil and flow.activate(card.id, {}, i)
end

-- One move, whatever the phase is asking for: somewhere to gather, no Fable,
-- or a handful of straw. Enough to walk the table round to a given seat.
local function nudge()
	local k, s = phase.current().key, zones.active_seat()
	if k == "build_turn" then return use("gain_straw") end
	if k == "pick_gather" then
		local g = card_in(box("plan", s), "g_fields")
		return g ~= nil and flow.play_card(g.id, {})
	end
	if k == "pick_fable" then
		local p = card_in(box("fables", s), "no_fable")
		return p ~= nil and flow.play_card(p.id, {})
	end
	return false
end

-- Play on until the named seat is the one building.
local function until_seat(key)
	for _ = 1, 40 do
		if phase.current().key == "build_turn" and zones.active_seat() == key then return true end
		if not nudge() then return false end
	end
	return false
end

local function pick(def_key)
	local c = card_in(zones.find("options"), def_key)
	return c ~= nil and flow.play_card(c.id, {})
end

local function houses(seat_key)
	local out = {}
	for _, id in ipairs(box("sites", seat_key).cards) do
		local c = entity.get(id)
		out[#out + 1] = c.def_key:gsub("^house_", "") .. tostring(c.stats.level)
	end
	table.sort(out)
	return table.concat(out, " ")
end

function M.test_grimm_opens_with_the_mega_tokens_and_a_pig_apiece(check)
	start()
	check("five Straw in the Fields, four Wood, three Brick",
		board("fields").stats.pool == 5 and board("forest").stats.pool == 4
		and board("brickyard").stats.pool == 3)
	check("a pig in every pen", #box("pen", "orange").cards == 1
		and #box("pen", "blue").cards == 1 and #box("pen", "green").cards == 1)
	check("three Gather cards each", #box("plan", "orange").cards == 3
		and #box("plan", "green").cards == 3)
	check("five build sites each, all empty", houses("orange") == "")
	check("Orange leads, and the deck is full", zones.active_seat() == "orange"
		and #zones.find("fable_deck").cards == 24)
end

function M.test_grimm_a_shared_location_is_divided_and_the_remainder_stays(check)
	start()
	check("Orange and Blue both go to the Fields, Green to the Forest",
		gather({ orange = "fields", blue = "fields", green = "forest" }) == nil)

	check("two pigs in the Fields, one in the Forest", pigs("fields") == 2 and pigs("forest") == 1)
	check("five Straw between two is two each", seat("orange").stats.straw == 2
		and seat("blue").stats.straw == 2)
	check("and the odd one is left lying there", board("fields").stats.pool == 1)
	check("the pig that is alone takes the lot", seat("green").stats.wood == 4
		and board("forest").stats.pool == 0)
	check("nobody picked up what they did not gather", seat("orange").stats.wood == 0
		and seat("green").stats.straw == 0)
	check("the Gather card wrote down who was standing there",
		seat("orange").stats.crowd == 2 and seat("orange").stats.mates == 1
		and seat("green").stats.crowd == 1 and seat("green").stats.mates == 0)
end

function M.test_grimm_the_starting_player_marker_passes_round(check)
	start()
	check("the table starts in seat order", order() == "0 1 2" and zones.active_seat() == "orange")
	check("round one plays", gather({ orange = "fields", blue = "forest", green = "brickyard" }) == nil)
	for _ = 1, 3 do
		if not idle() then break end
	end
	check("round two starts with Blue", order() == "2 0 1" and zones.active_seat() == "blue")
	check("and the Locations were replenished on top of what was left",
		board("fields").stats.pool == 5 and board("forest").stats.pool == 4)
end

-- A house is three sections in order, and the file says so with one stat: a
-- floor is level 1, walls 2, a roof 3. Everything else — the Friend on the
-- walls, the First Builder token on the roof — hangs off that step.
function M.test_grimm_a_house_is_built_floor_walls_roof(check)
	start()
	check("everybody gathers", gather({ orange = "fields", blue = "forest", green = "brickyard" }) == nil)

	local me = seat("orange")
	me.stats.straw = 12
	check("Orange is up", zones.active_seat() == "orange")
	check("two Straw lays a floor", use("start_straw") and houses("orange") == "straw1"
		and me.stats.straw == 10)
	check("and it cost one of the two actions", me.stats.acts == 1)

	local house = entity.get(box("sites", "orange").cards[1])
	check("a second Straw house may not be started while that one is unfinished",
		flow.can_activate(tool("start_straw").id) == false)
	me.stats.wood = 2
	check("but a Wood one may be, given the wood", flow.can_activate(tool("start_wood").id))

	check("four Straw raises the walls", build(house, "walls") and house.stats.level == 2)
	check("and the walls drew a Friend", #box("friend", "orange").cards == 1)

	check("the round comes back round to Orange", until_seat("orange"))
	me.stats.straw = 6
	check("six Straw puts the roof on", build(house, "roof") and house.stats.level == 3)
	check("the first roof of its kind takes the First Builder token, and asks for a reward",
		phase.current().key == "options")
	check("one of each resource is a legal answer", pick("fb_resources"))
	check("the token is in Orange's tray", #box("trophies", "orange").cards == 1
		and seat("orange").stats.tok_straw == 1)
	check("the house counts", seat("orange").stats.houses == 1 and seat("orange").stats.hb_straw == 1)
	seat("orange").stats.straw = 4
	check("the second Straw house is unblocked now the first is finished",
		flow.can_activate(tool("start_straw").id))
end

function M.test_grimm_three_houses_end_the_contest(check)
	start()
	local blue = seat("blue")
	blue.stats.houses = 2
	blue.stats.hb_brick = 2
	check("everybody gathers", gather({ orange = "fields", blue = "brickyard", green = "forest" }) == nil)

	check("Blue gets a turn", until_seat("blue"))
	blue.stats.brick = 12
	blue.stats.acts = 3
	check("a floor goes down", use("start_brick") and houses("blue") == "brick1")
	local house = entity.get(box("sites", "blue").cards[1])
	check("walls and roof follow", build(house, "walls") and build(house, "roof"))
	check("the reward is taken", phase.current().key ~= "options" or pick("fb_fables"))
	check("that is Blue's third house", seat("blue").stats.houses == 3)

	blue.stats.acts = 0
	for _ = 1, 3 do
		if phase.current().key ~= "build_turn" then break end
		idle()
	end
	check("the game is over and Blue is the Royal Builder", phase.current().key == "reveal"
		and entity.get(zones.find("reveal").cards[1]).def_key == "blue_wins"
		and seat("blue").stats.won == 1)
end

-- Every "at your Location" rule reads `crowd` and `mates` off the seat rather
-- than the board, which is what lets a Fable sitting in a face-down commit zone
-- ask a question about a place it is not standing in.
function M.test_grimm_a_fable_reads_the_location_off_its_owners_seat(check)
	start()
	local me = seat("orange")
	local fable = entity.get(zones.find("fable_deck").cards[1])
	fable.stats = fable.stats or {}
	-- Put a known Fable in Orange's hand rather than trusting the shuffle.
	local actions = require("actions")
	actions.run({ "create:fables:f_little_helpers:1" }, {})
	local card = card_in(box("fables", "orange"), "f_little_helpers")
	check("Orange holds Little Helpers", card ~= nil)

	local s = zones.active_seat()
	check("Orange is up", s == "orange")
	local g = card_in(box("plan", "orange"), "g_forest")
	check("Orange goes to the Forest with it", flow.play_card(g.id, {}) and flow.play_card(card.id, {}))
	check("the others crowd the Fields", commit("fields") == nil and commit("fields") == nil)

	check("Orange was alone", me.stats.crowd == 1)
	check("so the Fable paid two extra actions", me.stats.acts == 4 or me.stats.extra_acts == 2,
		tostring(me.stats.acts) .. "/" .. tostring(me.stats.extra_acts))
	check("and the Fable is on the discard pile", #zones.find("fable_discard").cards == 1)
end

-- A card that asks a question is answered by whoever is *up* when the answer
-- comes, not by the seat that asked — and an End of Gather Phase step runs for
-- all three seats before anybody answers anything. So the two cards that ask
-- write a flag there and open the offer at the start of their own owner's build
-- turn, which is the only moment `mine` is certainly them.
function M.test_grimm_a_question_asked_at_the_end_of_gathering_waits_for_its_own_turn(check)
	start(5)
	local actions = require("actions")
	actions.run({ "create:friend:fr_golden_goose:1" }, {})
	check("Orange has the Golden Goose", card_in(box("friend", "orange"), "fr_golden_goose") ~= nil)
	check("Orange gathers alone, the others together",
		gather({ orange = "forest", blue = "fields", green = "fields" }) == nil)

	check("the offer is open, and it is Orange's turn", phase.current().key == "options"
		and zones.active_seat() == "orange")
	check("Brick is a legal answer", pick("take_brick"))
	check("and it went to Orange, not to whoever happened to be last",
		seat("orange").stats.brick == 1 and seat("blue").stats.brick == 0
		and seat("green").stats.brick == 0)
end

-- Playing a Fable leaves the phase's own *No Fable* card behind, and a card
-- dealt every round that is never taken is a hand that grows for ever.
function M.test_grimm_the_no_fable_card_does_not_pile_up(check)
	start(5)
	local actions = require("actions")
	actions.run({ "create:fable_discard:f_spy_network:3" }, {})
	actions.run({ "create:fables:f_search_the_past:1" }, {})

	local s = zones.active_seat()
	check("Orange is up", s == "orange")
	local g = card_in(box("plan", "orange"), "g_fields")
	local f = card_in(box("fables", "orange"), "f_search_the_past")
	check("Orange goes to the Fields and tells a Fable",
		flow.play_card(g.id, {}) and flow.play_card(f.id, {}))
	check("Blue follows them there", commit("fields") == nil)
	check("Green goes to the Forest", commit("forest") == nil)

	check("the search opens on Orange's own turn", phase.current().key == "options"
		and zones.active_seat() == "orange")
	check("two are taken", pick("f_spy_network") and pick("f_spy_network"))
	check("Orange holds those two and nothing else",
		#box("fables", "orange").cards == 2 and card_in(box("fables", "orange"), "no_fable") == nil)
	check("and the rest of the pile is where it was", #zones.find("fable_discard").cards == 2)
end

return M
