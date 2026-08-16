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
    { "key": "board", "type": "grid", "grid": [3, 1], "tags": ["activate"], "pos": [0.05, 0.05, 0.95, 0.30] },
    { "key": "rules", "type": "grid", "grid": [2, 1], "tags": ["hidden"] },
    { "key": "lane", "type": "grid", "grid": [3, 1], "tags": ["activate"], "pos": [0.05, 0.35, 0.95, 0.60] },
    { "key": "hand", "type": "hand", "pos": [0.25, 0.65, 0.95, 0.85] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "upkeep" }] },
    { "key": "upkeep", "type": "automatic", "actions": ["activate_zone:rules"],
      "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "tapper", "text": "Tapper", "card_stats": { "used": 0 },
      "activate": { "cost": { "exhaust": 1 }, "action": ["stat_gain:used@self:1"] } },
    { "key": "counter", "text": "Counter", "tags": ["counted"], "card_stats": { "ticks": 0 },
      "activate": { "action": ["stat_gain:ticks@self:1"] } },
    { "key": "rule_ready", "text": "Ready everything",
      "activate": { "action": ["ready:all"] } },
    { "key": "rule_count", "text": "Count the rounds",
      "activate": { "action": ["stat_gain:ticks@each.counted:1"] } }
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
			#zones.find("rules").cards == 2 and zones.find("rules").tags.hidden == true)
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

-- On a board, the order cards act in is where they stand — which is what "left
-- to right" means, and not the order they happened to arrive in.
function M.test_rules_zone_a_grid_acts_in_slot_order(check)
	with_game(function(name)
		flow.init(name, 3)
		local lane = zones.find("lane")
		-- Arrive out of order: the far square first, then the near one.
		local far = zones.add(lane, "counter")
		zones.place_in_slot(far.id, lane.slots[3])
		local near = zones.add(lane, "counter")
		zones.place_in_slot(near.id, lane.slots[1])

		local seen = {}
		local was = actions.on_stat_change
		actions.on_stat_change = function(e, key)
			if key == "ticks" then seen[#seen + 1] = e.id end
		end
		actions.execute("activate_zone:lane", {})
		actions.on_stat_change = was

		check("both acted", #seen == 2, tostring(#seen))
		check("and the one on the near square went first, though it arrived second",
			seen[1] == near.id and seen[2] == far.id,
			("%s then %s; near is %s"):format(tostring(seen[1]), tostring(seen[2]), tostring(near.id)))
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
		actions.execute("activate_zone:lane", {})
		actions.on_act = was

		check("one beat per card, plus the end of the run", #seen == 3, tostring(#seen))
		check("counted from one, in the order they stand",
			seen[1].id == near.id and seen[1].n == 1
			and seen[2].id == far.id and seen[2].n == 2)
		check("and the run says when it is over", seen[3].id == nil and seen[3].n == 0)
	end)
end

return M
