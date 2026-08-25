-- Reducing a pending effect rather than cancelling it: "prevent 1 of the damage",
-- Puzzle Strike's Bubble Shield, a shield that takes the edge off a hit. The
-- emitter works out the size *before* it announces, into a stat; the tail it
-- defers reads that stat back at resolution. A reaction that lands in between
-- writes the stat down, so what finally resolves is smaller. No new vocabulary:
-- the window is the pause, and a stat is the number everyone agrees on.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")

local M = {}

local GAME = [==[{
  "title": "React Reduce",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "incoming", "label": "Incoming", "subject": "incoming@mine.player" },
    { "key": "hits", "label": "Hits", "subject": "hits@mine.player" }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "ongoing", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.60, 0.50, 0.75], [0.20, 0.25, 0.50, 0.40]] },
    { "key": "discard", "layout": "stack", "copies": "per_seat",
      "pos": [[0.75, 0.80, 0.90, 0.95], [0.75, 0.05, 0.90, 0.20]] },
    { "key": "board", "layout": "grid", "copies": "per_seat", "grid": [3, 1],
      "pos": [[0.05, 0.60, 0.18, 0.75], [0.05, 0.25, 0.18, 0.40]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "incoming": 0, "hits": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "incoming": 0, "hits": 0 } },
    { "key": "hammer", "text": "Hammer", "tags": ["chip", "attack"],
      "play": { "action": [
        "stat_set:incoming@mine.player:3",
        "emit:strike:stat_gain:hits@enemy.player:sum:incoming@mine.player"
      ] } },
    { "key": "pebble", "text": "Pebble", "tags": ["pebble"] },
    { "key": "recycler", "text": "Recycler", "tags": ["chip"],
      "reactions": [
        { "to": "strike", "where": ["tagged:attack@event >= 1"],
          "action": ["destroy:any.mine.pebble"], "spent": "mine.discard" }
      ] },
    { "key": "shield", "text": "Shield", "tags": ["chip"],
      "reactions": [
        { "to": "strike", "where": ["tagged:attack@event >= 1"],
          "action": ["stat_damage:incoming@enemy.player:1"], "spent": "mine.discard" }
      ] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_react_reduce.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_react_reduce.json")
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
		if z.seat == seat_key then return z end
	end
end

-- Nobody holds a shield: the emit is transparent, the tail runs in place, and the
-- hit lands at full size. This is the "an emit costs a game with no reactions
-- nothing" half, checked on the same card the reduction is checked on.
function M.test_react_reduce_unanswered_hit_is_full(check)
	with_game(function(name)
		flow.init(name, 3)
		local h = zones.add(zone_of("hand", "one"), "hammer")
		flow.play_card(h.id, {})
		check("the full hit landed", seat("two").stats.hits == 3, seat("two").stats.hits)
	end)
end

-- The shield answers, writes the pending size down by one, and the tail then
-- resolves against what the stat now says.
function M.test_react_reduce_shield_takes_one_off(check)
	with_game(function(name)
		flow.init(name, 3)
		local h = zones.add(zone_of("hand", "one"), "hammer")
		local s = zones.add(zone_of("ongoing", "two"), "shield")

		flow.play_card(h.id, {})
		check("the window opened for the defender", zones.active_seat() == "two", zones.active_seat())
		check("while the turn stayed put", zones.turn_seat() == "one", zones.turn_seat())

		flow.react(s.id, 1, {})
		check("the hit landed reduced by one", seat("two").stats.hits == 2, seat("two").stats.hits)
		-- Spent by its own word: the reaction block said where it goes, and the
		-- engine put it there once the answer was over.
		check("the shield went to the discard",
			entity.get(s.id).zone_id == zone_of("discard", "two").id)
		check("the stack cleared", #(zones.find("stack") or { cards = {} }).cards == 0)
	end)
end

-- Two shields stack, because the window re-opens after each answer and there is
-- no per-event latch. Each one writes the same stat down again.
function M.test_react_reduce_two_shields_stack(check)
	with_game(function(name)
		flow.init(name, 3)
		local h = zones.add(zone_of("hand", "one"), "hammer")
		zones.add(zone_of("ongoing", "two"), "shield")
		zones.add(zone_of("ongoing", "two"), "shield")

		flow.play_card(h.id, {})
		local og = zone_of("ongoing", "two")
		flow.react(og.cards[#og.cards], 1, {})
		og = zone_of("ongoing", "two")
		if og.cards[1] then flow.react(og.cards[1], 1, {}) end
		check("both shields came off the hit", seat("two").stats.hits == 1, seat("two").stats.hits)
	end)
end

-- A reaction goes home the same way a play does: it says "spent" and the engine
-- puts it there once the answer is over. The card was never on the stack, so it
-- is the same card that comes back — no minting a fresh copy to stand in for one
-- the stack ate, which is what this shape used to need.
function M.test_react_reduce_reaction_goes_to_its_discard(check)
	with_game(function(name)
		flow.init(name, 3)
		local h = zones.add(zone_of("hand", "one"), "hammer")
		local r = zones.add(zone_of("ongoing", "two"), "recycler")
		zones.add(zone_of("board", "two"), "pebble")

		flow.play_card(h.id, {})
		flow.react(r.id, 1, {})
		local d = zone_of("discard", "two")
		check("the chip itself is in the discard", entity.get(r.id).zone_id == d.id)
		check("and only it", #d.cards == 1, #d.cards)
		check("the tagged card was destroyed by scope", #zone_of("board", "two").cards == 0)
	end)
end

return M
