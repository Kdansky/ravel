-- "@event" — the subject of the event a reaction is answering.
--
-- A reaction reads what it reacts to: is this a fireball, is that crash worth
-- four or less. The card acted on never names what answers it — the event
-- carries its own tags and stats, and "@event" is how a reaction reads them,
-- through the same grammar "@target" reads a chosen card. Like target it is a
-- list the engine puts in the ctx, not a scope of the board.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local geometry = require("geometry")

local M = {}

local GAME = [==[{
  "title": "Event Scope",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "value", "label": "Value" }],
  "zones": [
    { "key": "board", "type": "grid", "grid": [4, 1], "tags": ["activate"],
      "pos": [0.05, 0.40, 0.95, 0.60] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "board", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "bolt", "text": "Bolt", "tags": ["spell", "fireball"], "card_stats": { "value": 3 } },
    { "key": "beast", "text": "Beast", "tags": ["creature"], "card_stats": { "value": 5 } }
  ],
  "setup": {
    "place": [
      { "card": "bolt", "owner": "one", "zone": "board", "at": ["a1"] },
      { "card": "beast", "owner": "two", "zone": "board", "at": ["b1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_event_scope.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_event_scope.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("board"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

-- The whole point: a reaction reads the tags and stats of what it reacts to,
-- and a fireball is only a fireball, not a creature.
function M.test_event_reads_the_subject_it_is_given(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = { event = { at("a1").id } }
		local beast = { event = { at("b1").id } }

		check("the fireball is seen as a fireball",
			predicate.total("count:fireball@event", bolt) == 1,
			tostring(predicate.total("count:fireball@event", bolt)))
		check("and the creature is not",
			predicate.total("count:fireball@event", beast) == 0,
			tostring(predicate.total("count:fireball@event", beast)))
		check("its stat is read off the card acted on",
			predicate.total("value@event", bolt) == 3,
			tostring(predicate.total("value@event", bolt)))
		check("tagged answers yes or no about the subject",
			predicate.total("tagged:creature@event", beast) == 1,
			tostring(predicate.total("tagged:creature@event", beast)))
	end)
end

-- The reduced-reaction shape: answer a fireball, and answer a small crash but
-- not a big one, both said in the one condition grammar.
function M.test_event_gates_a_reaction_by_condition(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = { event = { at("a1").id } }
		local beast = { event = { at("b1").id } }
		check("a flame-counter answers a fireball",
			predicate.holds("tagged:fireball@event >= 1", bolt))
		check("and does not answer a creature",
			not predicate.holds("tagged:fireball@event >= 1", beast))
		check("immune above three: the small one is answerable",
			predicate.holds("value@event <= 3", bolt))
		check("and the big one is not",
			not predicate.holds("value@event <= 3", beast))
	end)
end

-- An event may be about several cards, and it defaults to all of them the way
-- a two-card target does, not to any one.
function M.test_event_defaults_to_each_like_target(check)
	with_game(function(name)
		flow.init(name, 3)
		local both = { event = { at("a1").id, at("b1").id } }
		check("every subject clears three", predicate.holds("value@each.event >= 3", both))
		check("but not every subject clears five",
			not predicate.holds("value@each.event >= 5", both))
	end)
end

-- A reaction's action reaches the thing it is reacting to, same scope on the
-- other side of the colon: this is how a counter cancels what it answers.
function M.test_event_an_action_reaches_the_subject(check)
	with_game(function(name)
		flow.init(name, 3)
		local ctx = { event = { at("a1").id } }
		actions.execute("stat_gain:value@event:2", ctx)
		check("the subject's own stat moved", at("a1").stats.value == 5,
			tostring(at("a1").stats.value))
		actions.execute("destroy:event", ctx)
		check("and destroy:event removes what was reacted to", at("a1") == nil)
	end)
end

-- No event in the ctx names nothing, and every comparison against nothing
-- fails closed rather than reading as zero and quietly passing.
function M.test_event_with_none_names_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		check("counted, an absent event is zero of anything",
			predicate.total("count:fireball@event", {}) == 0)
		check("a stat read of no subject fails the condition",
			not predicate.holds("value@event <= 3", {}))
	end)
end

return M
