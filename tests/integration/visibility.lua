-- Who may look at what.
--
-- One rule: a card in a *hand* belongs to whoever that hand belongs to. Decks
-- already draw a back, a pile is face-up because that is what a discard is, and
-- a board is public. A hand with no seat — a one-player game, a shared tray —
-- is nobody's in particular and stays visible, which is what keeps every game
-- written before seats existed unchanged.
--
-- Lost Cities is the case that matters: two seats, per-seat hands, and hot-seat
-- play where both hands were on one screen at once.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")

local M = {}

local function hand_of(seat)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == seat then return z end
	end
end

-- The active seat is derived from the system card's `turn`, so moving it is how
-- a test hands over without playing a legal game first. It indexes seat_list
-- directly, so 1 is the first seat — 0 means "nobody yet" and reads as the
-- first one too.
local function seat_turn(n)
	for e in entity.each("card") do
		if e.def_key == "system" then e.stats.turn = n end
	end
end

function M.test_visibility_a_hand_is_its_owners(check)
	flow.init("lost_cities.json", 11)
	check("north is to play", zones.active_seat() == "north")

	local north, south = hand_of("north"), hand_of("south")
	check("both seats were dealt a hand", #north.cards > 0 and #south.cards > 0,
		("north %d, south %d"):format(#north.cards, #south.cards))

	check("the seat to play sees its own cards",
		zones.visible(entity.get(north.cards[1])))
	check("and not the other seat's",
		not zones.visible(entity.get(south.cards[1])))

	-- Hand over. The same cards, the other way round.
	seat_turn(2)
	check("south is to play", zones.active_seat() == "south")
	check("now south sees its own", zones.visible(entity.get(south.cards[1])))
	check("and north's are hidden", not zones.visible(entity.get(north.cards[1])))
end

function M.test_visibility_only_hands_hide(check)
	flow.init("lost_cities.json", 11)
	-- A deck draws a back for its own reasons; visibility is about faces the
	-- renderer would otherwise show, so it says nothing about one.
	local deck = zones.find("build_deck") or zones.find("deck")
	if deck and #deck.cards > 0 then
		check("a deck's cards are not what this rule hides",
			zones.visible(entity.get(deck.cards[1])))
	end

	-- A discard is public: it is face-up in every card game, and Lost Cities
	-- lets you take from an opponent's.
	local pile = zones.find("red_discard")
	if pile then
		check("a pile is public", pile.zone_type == "pile")
	end
end

function M.test_visibility_a_seatless_hand_stays_visible(check)
	-- Every game written before seats existed has one hand belonging to nobody,
	-- and must be untouched by this.
	flow.init("castle.json", 11)
	local hand = zones.find("hand")
	check("castle's hand has no seat", hand.seat == nil)
	check("and its cards are visible", #hand.cards > 0 and zones.visible(entity.get(hand.cards[1])),
		tostring(#hand.cards) .. " cards")
end

return M
