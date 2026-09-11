-- Where a card goes when it dies, and who decides.
--
-- Two verbs, and the whole difference between them is the landing. `purge` takes
-- a card out of the game and nothing may ask about it; `destroy` is a death, so
-- the card lands in a grave, its `leaves` fires, and it is still there
-- afterwards to be counted or raised.
--
-- Which grave is asked of five places, narrowest first: the card, its tags, the
-- zone it is standing in, its own seat's, and the table's. The seat is the
-- **dying card's** — the reason this is a word at all rather than a zone key
-- written at the site, since "move:target:mine.discard" puts somebody else's
-- unit in your discard.

local entity  = require("entity")
local flow    = require("flow")
local zones   = require("zones")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Grave",
  "players": [{ "card": "north" }, { "card": "south" }],
  "stats": [
    { "key": "tally", "on": ["player"], "start": 0, "min": 0, "max": 99 }
  ],
  "tags": {
    "unit": { "leaves": { "action": ["stat_gain:tally@mine.player:1"] } },
    "hero": { "grave": "command" },
    "ghost": { "grave": "limbo" }
  },
  "zones": [
    { "key": "seat_box", "status": "board", "layout": "stack", "copies": "per_seat", "pos": [[0.02, 0.80, 0.16, 0.98], [0.02, 0.02, 0.16, 0.20]] },
    { "key": "army", "status": "board", "layout": "row", "copies": "per_seat",
      "pos": [[0.20, 0.60, 0.80, 0.75], [0.20, 0.20, 0.80, 0.35]] },
    { "key": "pit", "status": "board", "layout": "row", "grave": "limbo", "pos": [0.20, 0.40, 0.80, 0.55] },
    { "key": "discard", "status": "grave", "layout": "stack", "copies": "per_seat",
      "pos": [[0.84, 0.80, 0.98, 0.98], [0.84, 0.02, 0.98, 0.20]] },
    { "key": "command", "layout": "stack", "pos": [0.84, 0.42, 0.98, 0.58] },
    { "key": "limbo", "layout": "stack", "display": "offscreen" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "seat_box", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "north", "text": "North" },
    { "key": "south", "text": "South" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "champion", "text": "Champion", "tags": ["unit", "hero"] },
    { "key": "relic", "text": "Relic", "tags": ["unit", "hero"], "grave": "limbo" },
    { "key": "argued", "text": "Argued", "tags": ["unit", "hero", "ghost"] },
    { "key": "token", "text": "Token" }
  ],
  "setup": {
    "place": [
      { "card": "north", "zone": "seat_box", "owner": "north" },
      { "card": "south", "zone": "seat_box", "owner": "south" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_grave.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_grave.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function make(key, zone_key, owner)
	local z = zones.find(zone_key, owner)
	return require("cards").create(key, z.id)
end

local function where(card)
	local e = entity.get(card.id)
	local z = e and e.zone_id and entity.get(e.zone_id)
	return z and z.key or "nowhere"
end

local function seat_of(card)
	local e = entity.get(card.id)
	local z = e and e.zone_id and entity.get(e.zone_id)
	return z and z.seat
end

-- The plain case, and the one a game with a single graveyard only ever needs:
-- one zone says it is the grave, and every death finds it.
function M.test_grave_a_seats_own_grave_takes_its_dead(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = make("grunt", "army")
		actions.execute("destroy:mine.army", {})
		check("the grunt is lying in a discard", where(g) == "discard", where(g))
		check("and it is its own seat's", seat_of(g) == "north", tostring(seat_of(g)))
	end)
end

-- **The seat is the dying card's, not the active one.** This is the whole reason
-- the word exists: written as a move, one side's removal spell files the other
-- side's unit in its own discard.
function M.test_grave_a_card_dies_into_its_owners_grave(check)
	with_game(function(name)
		flow.init(name, 3)
		local theirs = make("grunt", "army", "enemy")
		check("it starts in the other seat's army", seat_of(theirs) == "south", tostring(seat_of(theirs)))
		actions.execute("destroy:enemy.army", {})
		check("and dies into the other seat's discard", where(theirs) == "discard" and seat_of(theirs) == "south",
			where(theirs) .. "/" .. tostring(seat_of(theirs)))
	end)
end

-- A game may have more than one grave, and the kind of card is what tells them
-- apart: Codex sends a dead unit to the discard and a dead hero back to the
-- command zone to wait.
function M.test_grave_a_tag_names_a_grave_of_its_own(check)
	with_game(function(name)
		flow.init(name, 3)
		local c = make("champion", "army")
		actions.execute("destroy:mine.army", {})
		check("the hero falls back to the command zone", where(c) == "command", where(c))
	end)
end

-- Narrowest first, all the way down.
function M.test_grave_the_card_outranks_its_tag(check)
	with_game(function(name)
		flow.init(name, 3)
		local r = make("relic", "army")
		actions.execute("destroy:mine.army", {})
		check("the card's own grave wins over the hero tag's", where(r) == "limbo", where(r))
	end)
end

function M.test_grave_the_zone_outranks_the_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = make("grunt", "pit")
		actions.execute("destroy:pit", {})
		check("dying in the pit sends it to limbo, not to a discard", where(g) == "limbo", where(g))
	end)
end

-- Two tags disagreeing is not a majority vote. It is no answer, and the question
-- passes to the wider ones — the same rule a home zone already keeps.
function M.test_grave_two_tags_that_disagree_settle_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local a = make("argued", "army")
		actions.execute("destroy:mine.army", {})
		check("neither tag wins, so the seat's own grave takes it", where(a) == "discard", where(a))
	end)
end

-- The point of the whole split: a death is answerable and a purge is not.
function M.test_grave_a_death_fires_leaves_and_a_purge_does_not(check)
	with_game(function(name)
		flow.init(name, 3)
		local function tally()
			for e in entity.each("card") do
				if e.def_key == "north" then return e.stats.tally end
			end
		end
		make("grunt", "army")
		actions.execute("destroy:mine.army", {})
		check("the unit's leaves ran as it died", tally() == 1, tostring(tally()))
		make("grunt", "army")
		actions.execute("purge:mine.army", {})
		check("and a purge says nothing at all", tally() == 1, tostring(tally()))
	end)
end

-- A card with nowhere to die stays where it is. Quietly removing it is the bug
-- the two verbs were split to end, so the one thing this must not do is look
-- like a purge.
function M.test_grave_a_card_with_nowhere_to_die_is_left_alone(check)
	with_game(function(name)
		flow.init(name, 3)
		local t = make("token", "limbo")
		actions.execute("destroy:limbo", {})
		check("no grave serves limbo, so the token is still lying there", where(t) == "limbo", where(t))
	end)
end

return M
