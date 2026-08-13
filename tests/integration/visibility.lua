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
local declaration = require("declaration")

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

-- Looking inside a deck. What is *in* one is public in most games — you know
-- what the market holds — and every deck whose contents are secret is already
-- tagged "hidden", which nothing can click. The **order** is the secret, and
-- the browser is what keeps it: a face-down stack is shown sorted by name, so
-- reading it tells you nothing about what comes next.
function M.test_visibility_a_deck_shows_what_not_when(check)
	flow.init("lost_cities.json", 11)
	local deck = zones.find("deck")
	check("the deck is a face-down stack with cards in it",
		deck.zone_type == "deck" and #deck.cards > 1 and not deck.tags.face_up)

	local shown = zones.browse_order(deck)
	check("browsing shows every card", #shown == #deck.cards)

	local function names(list)
		local out = {}
		for i, id in ipairs(list) do
			out[i] = declaration.G.card_defs[entity.get(id).def_key].text
		end
		return out
	end
	local sorted, order = names(shown), names(deck.cards)
	local ok = true
	for i = 2, #sorted do if sorted[i] < sorted[i - 1] then ok = false end end
	check("in name order", ok, table.concat(sorted, ", "):sub(1, 60))

	-- The point: shuffling changes what comes next and changes nothing about
	-- what browsing shows, so the list carries no information about the draw.
	local before = table.concat(sorted, "|")
	require("actions").execute("shuffle:deck", {})
	check("shuffling really did reorder it",
		table.concat(names(deck.cards), "|") ~= table.concat(order, "|"))
	check("and the browser reads exactly the same afterwards",
		table.concat(names(zones.browse_order(deck)), "|") == before)
end

-- A face-up stack has no secret to keep, so it is shown as it lies.
function M.test_visibility_a_pile_is_shown_in_order(check)
	flow.init("castle.json", 7)
	local pile = zones.find("graveyard")
	for _ = 1, 3 do
		require("actions").execute("draw_from:build_deck:graveyard:1", {})
	end
	local shown = zones.browse_order(pile)
	local same = #shown == #pile.cards
	for i, id in ipairs(shown) do if id ~= pile.cards[i] then same = false end end
	check("a pile browses in the order it is stacked", same and #shown == 3,
		tostring(#shown))
end

-- Drawing a hand as backs is only half of hiding it. Every path that *reads* a
-- card has to ask the same question, or one of them quietly undoes the other:
-- right-clicking a card, right-clicking the hand it lies in, and ctrl+hovering
-- for the inspector all named the opponent's cards outright.
function M.test_visibility_an_opponents_hand_cannot_be_read(check)
	flow.init("lost_cities.json", 11)
	local mine, theirs = hand_of("north"), hand_of("south")
	check("north is to play, with a hand each", zones.active_seat() == "north"
		and #mine.cards > 0 and #theirs.cards > 0)

	check("my own hand may be looked into", zones.peekable(mine))
	check("and theirs may not", zones.peekable(theirs) == false)
	check("which is the same answer their cards give", 
		zones.visible(entity.get(mine.cards[1]))
		and zones.visible(entity.get(theirs.cards[1])) == false)

	-- The board is nobody's hand and stays readable, or this would have hidden
	-- the game from both players.
	local deck = zones.find("deck")
	check("a shared zone is still open to everyone", zones.peekable(deck))
	check("and a zone that asked not to be peeked at is not",
		zones.peekable(zones.find("mode")) == false)

	-- Hand over, and the answers swap.
	for e in entity.each("card") do
		if e.def_key == "system" then e.stats.turn = 2 end
	end
	check("south to play", zones.active_seat() == "south")
	check("now theirs is readable and mine is not",
		zones.peekable(theirs) and zones.peekable(mine) == false)
end

return M
