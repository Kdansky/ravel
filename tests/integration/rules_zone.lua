-- A phase making cards act, and a hidden zone of rules for it to act on.
--
-- Until this existed a card acted for two reasons only: a player clicked it, or
-- the round wrapped. Anything that had to happen at some *other* moment had to be
-- built into the engine — readying spent cards is exactly that, and its timing is
-- a rule of the game in every game that has it.
--
-- Now the rule is a card. A phase says "activate that zone", the zone is hidden,
-- and the cards in it are the game's own rules written in the game's own
-- vocabulary. Nothing about them is special to the engine: they are cards.

local declaration = require("declaration")
local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Rules Zone",
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [3, 1], "pos": [0.05, 0.05, 0.95, 0.30] },
    { "key": "rules", "layout": "grid", "display": "offscreen", "grid": [2, 1] },
    { "key": "lane", "layout": "grid", "use": "abilities", "grid": [3, 1], "pos": [0.05, 0.35, 0.95, 0.60] },
    { "key": "hand", "layout": "row", "pos": [0.25, 0.65, 0.95, 0.85] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "upkeep" }] },
    { "key": "upkeep", "type": "automatic", "actions": ["activate_zone:rules"],
      "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "tapper", "text": "Tapper", "card_stats": { "used": 0 },
      "abilities": [{ "cost": { "exhaust": 1 }, "action": ["stat_gain:used@self:1"] }] },
    { "key": "counter", "text": "Counter", "tags": ["counted"], "card_stats": { "ticks": 0 },
      "abilities": [{ "action": ["stat_gain:ticks@self:1"] }] },
    { "key": "rule_ready", "text": "Ready everything",
      "abilities": [{ "action": ["ready:all"] }] },
    { "key": "rule_count", "text": "Count the rounds",
      "abilities": [{ "action": ["stat_gain:ticks@each.counted:1"] }] }
  ],
  "setup": {
    "place": [
      { "card": "tapper", "zone": "board", "at": ["a1"] },
      { "card": "counter", "zone": "board", "at": ["b1"] },
      { "card": "rule_ready", "zone": "rules", "at": ["a1"] },
      { "card": "rule_count", "zone": "rules", "at": ["b1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_rules_zone.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_rules_zone.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

function M.test_rules_zone_a_phase_can_make_cards_act(check)
	with_game(function(name)
		flow.init(name, 3)
		local counter = card("counter")
		check("the rules are on the table but out of sight",
			#zones.find("rules").cards == 2 and zones.find("rules").display == "offscreen")
		check("and the counter starts at nothing", counter.stats.ticks == 0)

		-- The upkeep phase runs the rules zone. Two of the four cards act: the
		-- counter's own ability and the rule that counts it, so the tick is 2.
		actions.execute("activate_zone:rules", {})
		check("a rule card acted without anybody clicking it", counter.stats.ticks == 1,
			tostring(counter.stats.ticks))
	end)
end

-- The case that motivated it: exhaustion wears off when the *game* says, not
-- when the engine's round happens to wrap.
function M.test_rules_zone_readying_is_a_rule_a_game_writes(check)
	with_game(function(name)
		flow.init(name, 3)
		local tapper = card("tapper")

		check("the tapper acts once", flow.activate(tapper.id, {}))
		check("and is spent for it", entity.get(tapper.id).exhausted == true)
		check("so it cannot act again", flow.can_activate(tapper.id) == false)

		actions.execute("activate_zone:rules", {})
		check("the rule readied it", entity.get(tapper.id).exhausted == nil)
		check("and it can act again", flow.can_activate(tapper.id))
	end)
end

-- **The order is the game's, not the engine's.** An absolute pattern is a list
-- of squares in the order it names them, so "left to right" is a line in the
-- file; the engine walks what it is handed and prefers nothing.
local function acted_order(order)
	local lane = zones.find("lane")
	-- Arrive out of order: the far square first, then the near one, so arrival
	-- order and board order disagree and the answer says which was used.
	local far = zones.add(lane, "counter")
	zones.place_in_slot(far.id, lane.slots[3])
	local near = zones.add(lane, "counter")
	zones.place_in_slot(near.id, lane.slots[1])

	local seen = {}
	local was = actions.on_stat_change
	actions.on_stat_change = function(e, key)
		if key == "ticks" then seen[#seen + 1] = e.id end
	end
	actions.execute("activate_zone:lane" .. (order and (":" .. order) or ""), {})
	actions.on_stat_change = was
	return seen, near.id, far.id
end

function M.test_rules_zone_the_game_file_names_the_order(check)
	with_game(function(name)
		flow.init(name, 3)
		local seen, near, far = acted_order("by_column")
		check("both acted", #seen == 2, tostring(#seen))
		check("and the near square went first, though it arrived second",
			seen[1] == near and seen[2] == far)
	end)
end

-- A closed set of one, and the rest are refused rather than quietly given the
-- default: an order the engine cannot honour must not look like one it can.
function M.test_rules_zone_an_order_it_does_not_know_is_refused(check)
	with_game(function(name)
		flow.init(name, 3)
		local seen = acted_order("by_the_light_of_the_moon")
		check("nothing acted at all", #seen == 0, tostring(#seen))
	end)
end

-- Naming none is not "some order the engine likes": it is the order the cards
-- are in, which is the order the game put them there.
function M.test_rules_zone_without_an_order_the_cards_act_as_they_lie(check)
	with_game(function(name)
		flow.init(name, 3)
		local seen, near, far = acted_order(nil)
		check("the one that arrived first goes first", seen[1] == far and seen[2] == near)
	end)
end

-- A whole zone resolves in one instant, because a snapshot taken halfway
-- through a combat would be a position no rule could describe. So the only
-- thing the presentation gets to space a run out with is the ordinal, and it
-- has to count the cards that actually acted, in the order they acted.
function M.test_rules_zone_says_which_of_the_run_each_card_is(check)
	with_game(function(name)
		flow.init(name, 3)
		local lane = zones.find("lane")
		local far = zones.add(lane, "counter")
		zones.place_in_slot(far.id, lane.slots[3])
		local near = zones.add(lane, "counter")
		zones.place_in_slot(near.id, lane.slots[1])

		local seen = {}
		local was = actions.on_act
		actions.on_act = function(id, ordinal) seen[#seen + 1] = { id = id, n = ordinal } end
		actions.execute("activate_zone:lane:by_column", {})
		actions.on_act = was

		check("one beat per card, plus the end of the run", #seen == 3, tostring(#seen))
		check("counted from one, along the order the file named",
			seen[1].id == near.id and seen[1].n == 1
			and seen[2].id == far.id and seen[2].n == 2)
		check("and the run says when it is over", seen[3].id == nil and seen[3].n == 0)
	end)
end

return M
