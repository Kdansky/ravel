-- A card that can do two things, when the two come from different places.
--
-- `cards.abilities` adds what a card declares to what its zone hands out, and
-- the comment there names the case: a rook lying in a discard pile can be taken
-- *and* still moved. Nothing had ever built that board. The chooser dealt one
-- menu card per ability, menu cards were minted only for a card's own list, and
-- so the zone's ability asked for a card called nil — a left click on that rook
-- was `Unknown card def: nil`, a hard error rather than a wrong answer.

local declaration = require("declaration")
local entity = require("entity")
local zones = require("zones")
local cards = require("cards")
local flow = require("flow")

local M = {}

local GAME = [==[{
  "title": "Two Sources",
  "zones": [{ "key": "board", "type": "grid", "grid": [2, 2],
    "tags": ["activate"], "applies": ["takeable"] },
    { "key": "hand", "type": "hand" }],
  "phases": [{ "key": "turn", "type": "player_input" }],
  "tags": { "takeable": { "abilities": [
    { "key": "take", "text": "Take it", "action": ["move_to:hand"] }] } },
  "cards": [{ "key": "rook", "text": "Rook", "card_stats": { "moves_made": 0 },
    "abilities": [{ "key": "move", "text": "Move it", "action": ["gain_stat:moves_made@self:1"] }] }],
  "setup": { "place": [{ "card": "rook", "zone": "board", "at": ["a1"] }] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_two_sources.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_two_sources.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

function M.test_abilities_a_zone_grants_one_and_the_card_has_its_own(check)
	with_game(function(name)
		flow.init(name, 3)
		local rook
		for e in entity.each("card") do
			if e.def_key == "rook" and e.slot_id then rook = e end
		end
		check("the rook is on the board", rook ~= nil)

		local all = cards.abilities(rook)
		check("it has two abilities, one from each source", #all == 2,
			tostring(#all))
		check("and both are declared, so both were minted a menu card",
			all[1].menu_card == "rook#move" and all[2].menu_card == "takeable#take",
			tostring(all[1].menu_card) .. " / " .. tostring(all[2].menu_card))

		check("both are usable, so there is nothing to guess",
			#flow.usable_abilities(rook.id) == 2 and flow.sole_ability(rook.id) == nil)

		-- The line that used to raise.
		check("the chooser opens rather than asking for a card called nil",
			flow.offer_abilities(rook.id))
		local offer = zones.find("options")
		check("with one entry per ability", #offer.cards == 2 and offer.asked_by == rook.id)

		-- Each entry has to resolve to *its own* ability. The index is written on
		-- the entry when it is dealt, because which number an ability is depends
		-- on the zone the card is lying in.
		local picked = {}
		for _, id in ipairs(offer.cards) do
			local choice = flow.menu_choice(id)
			check("an entry resolves to the card that asked",
				choice ~= nil and choice.source == rook.id)
			picked[choice.index] = choice.ability.text
		end
		check("and the two entries mean two different abilities",
			picked[1] == "Move it" and picked[2] == "Take it",
			tostring(picked[1]) .. " / " .. tostring(picked[2]))
	end)
end

-- Everything a card writes as an "abilities" list used to be invisible to the
-- validator: it read the flat activate_* fields, and those exist only for the
-- one-ability form. Chess's pawn and king are written entirely as lists, so the
-- game driving the whole feature was the one nothing was reading.
function M.test_abilities_a_list_entry_is_validated_like_a_block(check)
	local path = "game/games/tmp_bad_abilities.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
  "title": "Bad Abilities",
  "zones": [{ "key": "board", "type": "grid", "grid": [2, 2], "tags": ["activate"] }],
  "phases": [{ "key": "turn", "type": "player_input" }],
  "patterns": { "hop": { "vectors": [[0, 1]] } },
  "cards": [{ "key": "thing", "text": "Thing", "abilities": [
    { "key": "bad", "cost": { "gold": 1, "exhaust": 3 }, "phases": ["nowhere"],
      "action": ["gain_stat:gold:1", "flibbertigibbet:2"],
      "moves": [{ "patterns": ["nosuch"], "fill": "friendly" }],
      "target": { "type": "wherever", "count": 1 } }] }]
}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_bad_abilities.json")
	os.remove(path)
	check("it parses", ok, tostring(G))
	if not ok then return end

	local said = table.concat(require("validate").check(G), "\n")
	local function reports(what, needle)
		check("it reports " .. what, said:find(needle, 1, true) ~= nil, said)
	end
	reports("a cost stat no card holds", "gold")
	reports("exhaust as anything but 1", "exhaust is 1")
	reports("an action the engine has no verb for", "flibbertigibbet")
	reports("a pattern nothing declares", "'nosuch'")
	reports("a fill that is not one of the four words", "a move's fill should be")
	reports("a target type that is not card, slot or zone", "'wherever'")
	reports("a phase key no phase has", "'nowhere'")
	reports("and names which ability it was talking about", "ability 1 ('bad')")
end

-- A chooser you opened may be taken back; one the rules opened may not. The
-- permission lived on the offer zone and only close_offer cleared it, so an
-- offer consumed any other way left it standing — and the next offer, opened
-- after a pawn had already moved, could be declined into a pawn on the eighth
-- rank.
function M.test_abilities_a_mandatory_offer_cannot_inherit_a_dismissal(check)
	flow.init("chess.json", 1)
	local board = zones.find("board")
	local offer = zones.find("options")

	-- The rules ask: promotion, opened by an action rather than by a click.
	require("actions").execute("options:to_queen,to_rook,to_bishop,to_knight",
		{ card_id = board.cards[1] })
	check("the offer is open with its choices", #offer.cards == 4)
	check("and it cannot be waved away", flow.dismiss_offer() == false)
	check("so the choices are still there", #offer.cards == 4)
	flow.close_offer()

	-- Now one a player opened, then emptied by another route than close_offer.
	offer.dismissable = true
	offer.asked_by = board.cards[1]
	require("actions").execute("options:to_queen,to_rook", { card_id = board.cards[1] })
	check("an offer the rules opened says nothing about being dismissable",
		offer.dismissable == nil and flow.dismiss_offer() == false)
	flow.close_offer()
end

-- Two abilities with one name are one name for two things, and the chooser
-- cannot tell them apart: both mint the same menu card, so the second silently
-- eats the first. Caught where the authored entry still exists.
function M.test_abilities_two_with_the_same_key_are_refused(check)
	local path = "game/games/tmp_same_key.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
  "title": "Same Key",
  "zones": [{ "key": "board", "type": "grid", "grid": [2, 2], "tags": ["activate"] }],
  "phases": [{ "key": "turn", "type": "player_input" }],
  "cards": [{ "key": "thing", "text": "Thing", "abilities": [
    { "key": "go", "text": "One", "action": ["next_phase"] },
    { "key": "go", "text": "Two", "action": ["next_phase"] }] }]
}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_same_key.json")
	os.remove(path)
	check("it parses", ok, tostring(G))
	if not ok then return end
	local said = false
	for _, p in ipairs(G.parse_problems or {}) do
		if p:find("two abilities called 'go'", 1, true) then said = true end
	end
	check("and says the two abilities share a name", said,
		table.concat(G.parse_problems or {}, "; "))
end

return M
