-- What standing a card has, asked as a question of its own.
--
-- "In play" was spelled `zone_type == "grid"` in nine places, which is a rule
-- reading a *layout*. It held for as long as every game's board was a board —
-- and Puzzle Strike lays its ongoing chips in a face-up row, unbounded, in front
-- of one player. That row is in play by every rule of the game and a `hand` by
-- every rule of the engine, so a chip on it could not be counted, could not be
-- sacrificed, was never asked to act, and no reaction could answer "from" it.
--
-- Three standings, because there turned out to be three: "board" is in play,
-- "offer" is a card lent to a question — nobody's while it is there — and
-- "exile" is everything else, which is the default so a zone is inert until it
-- says otherwise. A deck, a discard, a bag and a trash are all exile, and cards
-- there are still *nameable*, because naming a zone has always reached it. What
-- they are not is counted, sacrificed, or asked to act.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local predicate = require("predicate")

local M = {}

local GAME = [==[{
  "title": "Standing",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "gold", "label": "Gold", "subject": "gold@mine.player" },
    { "key": "seen", "label": "Seen", "subject": "seen@mine.player" }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "ongoing", "layout": "row", "status": "board", "copies": "per_seat", "status": "board",
      "pos": [[0.55, 0.80, 0.95, 0.95], [0.55, 0.05, 0.95, 0.20]] },
    { "key": "shelf", "layout": "row", "copies": "per_seat",
      "pos": [[0.55, 0.60, 0.95, 0.75], [0.55, 0.25, 0.95, 0.40]] },
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "trash", "layout": "stack", "pos": [0.05, 0.45, 0.15, 0.60] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.05, 0.20, 0.15, 0.35] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "seat": "next",
      "next": [{ "then": "wrap" }] },
    { "key": "wrap", "type": "automatic",
      "next": [{ "then": "act", "ends_round": true }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "gold": 0, "seen": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "gold": 0, "seen": 0 } },
    { "key": "pass", "text": "Pass", "play": { "action": ["next_phase"] } },
    { "key": "lamp", "text": "Lamp", "tags": ["lit"],
      "turn": { "action": ["stat_gain:gold@mine.player:1"] } },
    { "key": "bell", "text": "Bell", "tags": ["lit"],
      "reactions": [
        { "to": "ring", "whose": "anyone", "forced": "mandatory", "from": "board",
          "action": ["stat_gain:seen@mine.player:1"] }
      ] },
    { "key": "ringer", "text": "Ringer", "play": { "action": ["emit:ring"], "spent": "mine.trash" } },
    { "key": "burner", "text": "Burner",
      "play": { "action": ["stat_gain:gold@mine.player:1"], "cost": { "sacrifice:lit": 1 },
        "spent": "mine.trash" } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_zone_status.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_zone_status.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function zone_of(key, seat_key)
	for _, z in ipairs(zones.all_with_key(key)) do
		if not seat_key or z.seat == seat_key then return z end
	end
end

-- The case that reopened all of this. Two rows, laid out the same way, showing
-- the same card face up in front of the same player — and only the one that says
-- it is in play is counted.
function M.test_status_a_row_may_be_in_play(check)
	with_game(function(name)
		flow.init(name, 5)
		zones.add(zone_of("ongoing", "one"), "lamp")
		check("a chip laid in play is counted", predicate.total("count:lit") == 1,
			predicate.total("count:lit"))

		zones.add(zone_of("shelf", "one"), "lamp")
		check("and one on a shelf beside it is not", predicate.total("count:lit") == 1,
			predicate.total("count:lit"))
	end)
end

-- A bare tag scope means the cards in play carrying it, and it reaches the row
-- for the same reason: it asks what standing they have, not what shape the zone
-- happens to be drawn in.
function M.test_status_a_bare_tag_scope_reaches_it(check)
	with_game(function(name)
		flow.init(name, 5)
		zones.add(zone_of("ongoing", "one"), "bell")
		zones.add(zone_of("hand", "one"), "bell")
		check("only the one in play answers to @lit", #predicate.entities_in_scope("lit", {}) == 1,
			#predicate.entities_in_scope("lit", {}))
	end)
end

-- Sacrifice eats what is in play. A chip you have laid out is exactly what a
-- game means by "sacrifice one of yours", and it was unreachable.
function M.test_status_sacrifice_reaches_what_is_in_play(check)
	with_game(function(name)
		flow.init(name, 5)
		local burner = zones.add(zone_of("hand", "one"), "burner")
		check("nothing to sacrifice, so nothing to play", not flow.can_play(burner.id))

		local lamp = zones.add(zone_of("ongoing", "one"), "lamp")
		check("a laid-out chip is something to sacrifice", flow.can_play(burner.id))
		flow.play_card(burner.id, {})
		-- Destroying a card empties it rather than unregistering it, so what says
		-- it is gone is that it is nowhere.
		check("and it was the one that went", entity.get(lamp.id).zone_id == nil)
	end)
end

-- on_turn is a card acting by itself, which is a thing only a card in play does.
-- It fired on grids alone, so an ongoing effect that ticks every round — half of
-- what an ongoing effect *is* — could not be written as a row.
function M.test_status_on_turn_fires_where_cards_are_in_play(check)
	with_game(function(name)
		flow.init(name, 5)
		zones.add(zone_of("ongoing", "one"), "lamp")
		zones.add(zone_of("shelf", "one"), "lamp")

		local before = seat("one").stats.gold
		local p = zones.add(zone_of("hand", "one"), "pass")
		flow.play_card(p.id, {})
		check("the round wrapped and the lamp in play paid once",
			seat("one").stats.gold == before + 1, seat("one").stats.gold)
	end)
end

-- The reaction half, which is where this was first paid for: four Puzzle Strike
-- chips were unplayable because "from": "board" meant "on a grid".
function M.test_status_a_reaction_answers_from_a_row_in_play(check)
	with_game(function(name)
		flow.init(name, 5)
		zones.add(zone_of("ongoing", "two"), "bell")
		local r = zones.add(zone_of("hand", "one"), "ringer")

		flow.play_card(r.id, {})
		check("the bell in play answered", seat("two").stats.seen == 1,
			seat("two").stats.seen)
	end)
end

-- The defaults, stated so they stay true: a grid is in play and a stack is not,
-- neither having said a word about it, which is what keeps every game written
-- before this field unchanged.
function M.test_status_the_types_that_carry_one_supply_it(check)
	with_game(function(name)
		flow.init(name, 5)
		check("a grid is in play without saying so", zone_of("board").status == "board",
			zone_of("board").status)
		check("a pile is not", zone_of("trash").status == "exile", zone_of("trash").status)
		check("nor is a hand", zone_of("hand", "one").status == "exile",
			zone_of("hand", "one").status)
		check("and the offer is an offer", zones.find("options").status == "offer",
			zones.find("options").status)
	end)
end

-- Exile is not oblivion. Naming a zone has always reached inside it, and that is
-- how MTG's exile and Slay the Spire's trash are said: the cards are there to be
-- pointed at by a rule that means them, and by nothing else.
function M.test_status_an_exiled_card_is_still_nameable(check)
	with_game(function(name)
		flow.init(name, 5)
		zones.add(zones.find("trash"), "lamp")
		check("no rule counts it", predicate.total("count:lit") == 0,
			predicate.total("count:lit"))
		check("and a rule that names the zone finds it", #predicate.entities_in_scope("trash", {}) == 1,
			#predicate.entities_in_scope("trash", {}))
	end)
end

-- A standing the engine does not have is refused where every other typo is: at
-- parse, the last place the authored word exists.
function M.test_status_an_unknown_standing_is_refused(check)
	local declaration = require("declaration")
	local path = "game/games/tmp_bad_status.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
		"title": "Bad Standing",
		"zones": [
			{ "key": "board", "layout": "grid", "use": "abilities", "grid": [2, 2] },
			{ "key": "limbo", "layout": "stack", "status": "purgatory", "status": "purgatory" }
		],
		"cards": [{ "key": "thing", "text": "Thing" }]
	}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_bad_status.json")
	os.remove(path)
	if not ok then error(G, 2) end
	local found = false
	for _, p in ipairs(G.parse_problems or {}) do
		if p:find("none of board, exile, offer", 1, true) then found = true end
	end
	check("a standing the engine does not have is refused", found,
		table.concat(G.parse_problems or {}, "; "))
	check("and it falls back to inert rather than to whatever was typed",
		G.zone_defs.limbo.status == "exile", G.zone_defs.limbo.status)
end

return M
