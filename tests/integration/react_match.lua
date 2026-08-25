-- reactions.responders — Filter A, the match, and Filter B, together.
--
-- The suppression brain: given an event (a verb and its subject), who may answer
-- it. A verb no card answers returns nothing before any card is weighed; a
-- reaction answers only the events its "where" names, only when its "when"
-- holds for the reactor, and only from a zone it can be answered out of. No
-- window opens for an empty answer.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local geometry = require("geometry")
local reactions = require("reactions")

local M = {}

local GAME = [==[{
  "title": "React Match",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "mana", "label": "Mana", "subject": "mana@mine.player" }],
  "zones": [
    { "key": "board", "type": "grid", "grid": [4, 1], "tags": ["activate"],
      "pos": [0.05, 0.40, 0.95, 0.60] },
    { "key": "bin", "type": "pile", "pos": [0.30, 0.70, 0.45, 0.90] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "board", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "mana": 3 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "mana": 3 } },
    { "key": "fireball", "text": "Fireball", "tags": ["spell", "fireball"] },
    { "key": "beast", "text": "Beast", "tags": ["creature"] },
    { "key": "flame_counter", "text": "Flame Counter", "tags": ["counter"],
      "reactions": [
        { "to": "play", "where": ["tagged:fireball@event >= 1"],
          "when": ["mana@mine.player >= 1"], "from": "board",
          "action": ["destroy:event"] }
      ] },
    { "key": "summon_counter", "text": "Summon Counter", "tags": ["counter"],
      "reactions": [
        { "to": "summon", "where": ["tagged:creature@event >= 1"], "from": "board",
          "action": ["destroy:event"] }
      ] }
  ],
  "setup": {
    "place": [
      { "card": "fireball", "owner": "one", "zone": "board", "at": ["a1"] },
      { "card": "beast", "owner": "one", "zone": "board", "at": ["b1"] },
      { "card": "flame_counter", "owner": "two", "zone": "board", "at": ["c1"] },
      { "card": "summon_counter", "owner": "two", "zone": "board", "at": ["d1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_react_match.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_react_match.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("board"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

-- The right reaction answers the right event, and only it: a fireball is
-- answered by the flame-counter, and the summon-counter stays silent.
function M.test_react_match_the_right_reaction_answers(check)
	with_game(function(name)
		flow.init(name, 3)
		local rs = reactions.responders("play", { at("a1").id })
		check("one reaction answers the fireball", #rs == 1, #rs)
		check("it is the flame counter", rs[1] and rs[1].reaction.to == "play"
			and entity.get(rs[1].card).def_key == "flame_counter",
			rs[1] and entity.get(rs[1].card).def_key)
		check("and it belongs to the other seat", rs[1] and rs[1].seat == "two", rs[1] and rs[1].seat)

		local su = reactions.responders("summon", { at("b1").id })
		check("the summon is answered by the summon counter",
			#su == 1 and entity.get(su[1].card).def_key == "summon_counter", #su)
	end)
end

-- "where" is a real gate: a summon-counter's verb and a flame-counter's tag keep
-- them from answering the wrong thing.
function M.test_react_match_where_keeps_them_apart(check)
	with_game(function(name)
		flow.init(name, 3)
		check("a creature played is not a fireball played",
			#reactions.responders("play", { at("b1").id }) == 0)
		check("and nobody answers a fireball summon",
			#reactions.responders("summon", { at("a1").id }) == 0)
	end)
end

-- Filter A: a verb no card in the game answers returns nothing at all, which is
-- what stops every action asking whether anyone wants to react.
function M.test_react_match_filter_a_short_circuits_an_unanswered_verb(check)
	with_game(function(name)
		flow.init(name, 3)
		check("no card answers a buy, so no window",
			#reactions.responders("buy", { at("a1").id }) == 0)
		check("and the index does not carry the verb",
			require("declaration").G.react_index["buy"] == nil)
	end)
end

-- "when" is about the reactor: no mana, no answer, even for the right event.
function M.test_react_match_when_gates_the_reactor(check)
	with_game(function(name)
		flow.init(name, 3)
		check("with mana it answers", #reactions.responders("play", { at("a1").id }) == 1)
		seat("two").stats.mana = 0
		check("with none it cannot", #reactions.responders("play", { at("a1").id }) == 0)
	end)
end

-- Filter B, the plain half: a reaction answered "from" the board is no answer
-- once the card has left the board. (A reaction in a graveyard is spent.)
function M.test_react_match_filter_b_needs_the_card_where_it_acts(check)
	with_game(function(name)
		flow.init(name, 3)
		check("on the board it answers", #reactions.responders("play", { at("a1").id }) == 1)
		actions.execute("move_target_to:bin", { targets = { at("c1").id } })
		check("in the bin it does not", #reactions.responders("play", { at("a1").id }) == 0)
	end)
end

return M
