-- "When you discard this" — `leaves` pointed at a zone instead of at play.
--
-- Every card game has two triggers about a card on its way out and the engine
-- could say one of them. "When this dies" is leaving play, and it needs no help:
-- a board zone is one the engine already tells from the rest. "When you discard
-- this" is leaving a *hand*, and there is nothing about a hand the engine knows
-- — a game may keep no board at all, in which case leaving play is a thing that
-- never happens and the whole moment is dead.
--
-- So `from` names the departure. What is being tested is mostly that it stays
-- narrow: the same card discarded, voided, drawn and played, and only one of
-- those is the discard. The failure this replaces was Spellstorm writing the
-- trigger as an ability, which every rule that runs abilities then ran.

local entity = require("entity")
local zones  = require("zones")
local flow   = require("flow")

local M = {}

-- No zone here has `status: board`, which is the point: this game cannot say
-- "when this dies" at all, and used to be unable to say anything.
local GAME = [==[{
  "title": "Leaves From",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "power", "min": 0, "max": 99, "on": ["player"], "start": 0 }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.4, 0.9, 0.2], [0.05, 0.62, 0.9, 0.2]] },
    { "key": "deck", "layout": "stack", "copies": "per_seat", "visibility": "secret",
      "pos": [[0.05, 0.05, 0.1, 0.2], [0.85, 0.05, 0.1, 0.2]] },
    { "key": "discard", "layout": "stack", "copies": "per_seat",
      "pos": [[0.2, 0.05, 0.1, 0.2], [0.7, 0.05, 0.1, 0.2]] },
    { "key": "battle", "layout": "row", "copies": "per_seat",
      "pos": [[0.35, 0.05, 0.3, 0.2], [0.35, 0.28, 0.3, 0.2]] },
    { "key": "void", "layout": "stack", "display": "offscreen", "use": "none" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "gem", "text": "Power Gem",
      "play": { "phases": ["act"], "action": ["move_to:mine.battle"] },
      "abilities": [{ "key": "cast", "text": "Resolve",
                      "action": ["stat_gain:power@mine.player:1"] }],
      "leaves": { "from": "hand", "into": "discard",
                  "action": ["stat_gain:power@mine.player:1"] } },
    { "key": "sifter", "text": "Sifter",
      "play": { "phases": ["act"], "action": ["show:mine.hand"], "spent": "void" },
      "chosen": { "action": ["copy:target:activate", "move:target:mine.discard"] } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_leaves_from.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_leaves_from.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- The seat card that carries the stat, which is the one the players list named.
local function power()
	for e in entity.each("card") do
		if e.def_key == "one" then return e.stats.power end
	end
end

local function gem_in(key)
	return zones.add(zones.find(key), "gem")
end

function M.test_leaves_from_a_discard_from_hand_fires_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local gem = gem_in("hand")
		check("nothing has happened yet", power() == 0, power())

		zones.move_card(gem.id, zones.find_id("discard", "mine"))
		check("hand to discard is the departure it names", power() == 1, power())
	end)
end

function M.test_leaves_from_stays_narrow(check)
	with_game(function(name)
		flow.init(name, 3)

		-- Voided out of the same hand: the departure matches, the arrival does
		-- not, and that is the whole of "does not trigger when you VOID".
		local a = gem_in("hand")
		zones.move_card(a.id, zones.find_id("void"))
		check("voided out of the hand, it is quiet", power() == 0, power())

		-- The same arrival from somewhere else. A card milled off a deck lands
		-- in the discard too, and a rule about discarding from hand is not
		-- about that.
		local b = gem_in("deck")
		zones.move_card(b.id, zones.find_id("discard", "mine"))
		check("milled off the deck, it is quiet", power() == 0, power())

		-- And the card leaving the hand to be played. This is the one that
		-- mattered: as an ability the effect ran on the way into battle and
		-- again when the copier reached it.
		local c = gem_in("hand")
		flow.play_card(c.id, {})
		flow.settle()
		check("played out of the hand, it is quiet", power() == 0, power())
	end)
end

-- Resolving a card is not discarding it, and the two used to be the same list.
function M.test_leaves_from_resolving_is_not_discarding(check)
	with_game(function(name)
		flow.init(name, 3)
		local gem = gem_in("hand")
		require("actions").execute("activate_zone:mine.hand:by_column:cast",
			{ card_id = gem.id, targets = {} })
		check("resolved where it lies, only the ability ran", power() == 1, power())

		require("actions").execute("copy:target:activate",
			{ card_id = gem.id, targets = { gem.id } })
		check("and copying it runs the same one thing", power() == 2, power())
	end)
end

-- The offer is a spotlight, not a location: a card held up out of a hand has not
-- left it. Without this every discard a player was *asked* about would miss —
-- which is most of them, since being asked is how a card gets discarded.
function M.test_leaves_from_a_card_lent_to_an_offer_still_leaves_the_hand(check)
	with_game(function(name)
		flow.init(name, 3)
		local gem = gem_in("hand")
		local sifter = zones.add(zones.find("hand"), "sifter")

		flow.play_card(sifter.id, {})
		check("the gem is lent to the offer", entity.get(gem.id).zone_id == zones.find_id("options"),
			tostring(entity.get(gem.id).zone_id))
		check("and lending it fired nothing", power() == 0, power())

		flow.play_card(gem.id, {})
		flow.settle()
		check("it landed in the discard",
			entity.get(gem.id).zone_id == zones.find_id("discard", "mine"),
			tostring(entity.get(gem.id).zone_id))
		-- One from the copy, one from the discard, and the discard is the half
		-- that was unreachable while the offer counted as the card's home.
		check("resolved once and discarded once", power() == 2, power())
		check("and it no longer remembers being lent",
			entity.get(gem.id).borrowed_from == nil)
	end)
end

return M
