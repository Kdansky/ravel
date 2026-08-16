-- Runeterra, milestone 1: the board and the round.
--
-- Every board game gets a scripted test ([01](ideas/01-boardgames.md)), and this
-- one is the round loop before any combat exists: both seats draw and refill,
-- playing a unit hands priority over, and a round ends on two passes *in
-- succession* rather than on a fixed number of turns.
--
-- The deck is a mirror — both seats play the same ten templates — so an
-- asymmetric result here is a bug rather than a matter of opinion.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")
local predicate = require("predicate")

local M = {}

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == seat then return z end
	end
end

local function card_in_hand(seat)
	return zone_of("hand", seat).cards[1]
end

-- Passing is a card on the table with a flag on it, so this is an ordinary
-- activation of an ordinary card — there is nothing here the engine knows about.
--
-- The flag is cleared in one place, the "hand_over" phase, and the trick is that
-- it clears the **enemy's**. That phase runs after the round-end check and before
-- the seat rotates, so "enemy" there is the player whose turn is about to begin:
-- clearing their pass is exactly "your pass only counts until you act again".
-- Two seats is what makes it read that way, which is all this game has.
local function pass()
	local seat = zones.active_seat()
	for _, id in ipairs(zones.find("controls").cards) do
		local e = entity.get(id)
		if e.def_key == "pass_button" and predicate.owner_of(e) == seat then
			return flow.activate(e.id, {})
		end
	end
	return false
end

local function passed()
	return predicate.total("count:passed")
end

function M.test_lor_a_round_deals_to_both_seats(check)
	flow.init("lor.json", 5)
	check("north is up, and both decks are thirty", zones.active_seat() == "north"
		and #zone_of("deck", "north").cards == 29 and #zone_of("deck", "south").cards == 29,
		("%d / %d"):format(#zone_of("deck", "north").cards, #zone_of("deck", "south").cards))
	check("each seat drew one, and nothing else was dealt",
		#zone_of("hand", "north").cards == 1 and #zone_of("hand", "south").cards == 1)
	check("and each has a pass button of its own on the table",
		#zones.find("controls").cards == 2)
	-- Whose button it is does the gating, which is the ordinary ownership rule
	-- and not something passing had to be taught.
	local mine, theirs
	for _, id in ipairs(zones.find("controls").cards) do
		local e = entity.get(id)
		if predicate.owner_of(e) == "north" then mine = e else theirs = e end
	end
	check("north may use its own and not the other one",
		flow.can_activate(mine.id) and flow.can_activate(theirs.id) == false)

	-- Mana is the round number, which is what makes it rise by one a round and
	-- stop at ten: the stat's own max does the capping.
	check("both seats have one mana in round one",
		predicate.total("mana@north_side") == 1 and predicate.total("mana@south_side") == 1)
	check("and twenty nexus each",
		predicate.total("nexus@north_side") == 20 and predicate.total("nexus@south_side") == 20)

	-- Six lanes a side, one shared grid: an attacker and the unit across from it
	-- are the same column of a 6x2 board, which is the whole of the pairing.
	check("the battlefield is six lanes deep on both sides", #zones.find("battle").slots == 12)
end

function M.test_lor_playing_a_unit_hands_priority_over(check)
	flow.init("lor.json", 5)
	local unit = card_in_hand("north")
	local cost = entity.get(unit).stats.cost

	check("north can afford its own one-drop", flow.can_play(unit) and cost == 1)
	check("it goes to the bench", flow.play_card(unit, { zone_of("bench", "north").slots[1] }))
	check("and the bench holds it", #zone_of("bench", "north").cards == 1)
	check("the mana is spent", predicate.total("mana@north_side") == 0)
	check("and it is the other seat's move", zones.active_seat() == "south"
		and phase.current().key == "play")
end

function M.test_lor_a_round_ends_on_two_passes_in_succession(check)
	flow.init("lor.json", 5)
	flow.play_card(card_in_hand("north"), { zone_of("bench", "north").slots[1] })

	check("south passes, and the round does not end yet", pass()
		and passed() == 1 and phase.current().key == "play")
	check("north passes after it, and the round turns", pass()
		and predicate.total("max:round") == 2)
	check("the count is back to nothing", passed() == 0)
	check("mana refilled to the new round's gems for both",
		predicate.total("mana@north_side") == 2 and predicate.total("mana@south_side") == 2)
	check("and the unit is still on the bench", #zone_of("bench", "north").cards == 1)
end

-- Anything happening between two passes means they were not in succession.
function M.test_lor_a_play_between_two_passes_keeps_the_round(check)
	flow.init("lor.json", 5)
	check("north passes", pass())
	-- Enough mana that the play can only be refused for the reason under test:
	-- what south drew is the shuffle's business, and this is about the count.
	for e in entity.each("card") do
		if e.def_key == "south" then e.stats.mana = 9 end
	end
	check("south plays instead of passing",
		flow.play_card(card_in_hand("south"), { zone_of("bench", "south").slots[1] }))
	check("which clears the count", passed() == 0)
	check("north passes again", pass())
	check("and it is still round one", predicate.total("max:round") == 1,
		tostring(predicate.total("max:round")))
end

return M
