-- A phase interjected in the middle of an answer. Puzzle Strike's Rigorous
-- Training is the case: reacting to an opponent's buy hands *you* a buy, and the
-- game returns to where it was afterwards.
--
-- The whole of it is who is up while the interjected phase runs. Priority is the
-- one answer to that — the turn never moves — so the rule is that priority is
-- released when nothing holds it, and a pushed phase holds it.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")

local M = {}

local GAME = [==[{
  "title": "Interject",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "loot", "label": "Loot", "subject": "loot@mine.player" }],
  "zones": [
    { "key": "hand", "type": "hand", "tags": ["per_seat"],
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "shop", "type": "grid", "grid": [2, 1], "tags": ["activate"],
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "table", "type": "pile", "tags": ["per_seat"],
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "type": "pile", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] },
    { "key": "spree", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "tags": { "loud": { "emits": { "play": "shout" } } },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "loot": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "loot": 0 } },
    { "key": "horn", "text": "Horn", "tags": ["loud"],
      "play": { "action": ["stat_gain:loot@mine.player:1"], "spent": "mine.table" } },
    { "key": "envy", "text": "Envy", "tags": ["answer"],
      "reactions": [
        { "to": "shout", "action": ["push_phase:spree"], "spent": "mine.table" }
      ] },
    { "key": "trinket", "text": "Trinket", "tags": ["wares"],
      "play": { "phases": ["spree"], "action": ["stat_gain:loot@mine.player:5", "pop_phase"],
        "spent": "mine.table" } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_interject.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_interject.json")
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

-- The reacting seat keeps priority through the phase their own reaction pushed.
-- Without this the last record leaves the stack, priority goes home, and the buy
-- the reactor was handed belongs to the player they reacted against.
function M.test_interject_a_pushed_phase_holds_priority(check)
	with_game(function(name)
		flow.init(name, 3)
		local horn = zones.add(zone_of("hand", "one"), "horn")
		local envy = zones.add(zone_of("hand", "two"), "envy")

		flow.play_card(horn.id, {})
		check("the window opened for the other seat", zones.active_seat() == "two",
			zones.active_seat())

		flow.react(envy.id, 1, {})
		check("the interjected phase is up", phase.current().key == "spree",
			phase.current().key)
		check("and it is the reactor's", zones.active_seat() == "two", zones.active_seat())
		check("while the turn never moved", zones.turn_seat() == "one", zones.turn_seat())
		-- The horn is still stacked underneath, unresolved. An interjection is part
		-- of resolving the record that opened it, so nothing below it moves until
		-- it pops — otherwise the turn player's effects land mid-answer.
		check("the horn is still waiting", #(zones.find("stack") or { cards = {} }).cards == 1,
			#(zones.find("stack") or { cards = {} }).cards)
		check("so it has not gone off yet", seat("one").stats.loot == 0, seat("one").stats.loot)
	end)
end

-- What the interjection was for: the reactor acts, as themselves, on their own
-- cards. Then the phase pops and priority goes back with it.
function M.test_interject_the_reactor_acts_then_priority_goes_home(check)
	with_game(function(name)
		flow.init(name, 3)
		local horn = zones.add(zone_of("hand", "one"), "horn")
		local envy = zones.add(zone_of("hand", "two"), "envy")
		local tr   = zones.add(zone_of("hand", "two"), "trinket")

		flow.play_card(horn.id, {})
		flow.react(envy.id, 1, {})
		check("the reactor may play in the phase they were handed", flow.can_play(tr.id))

		flow.play_card(tr.id, {})
		check("and it paid them, not the turn player", seat("two").stats.loot == 5,
			seat("two").stats.loot)
		check("the phase popped back", phase.current().key == "act", phase.current().key)
		check("the horn went off once the interjection was over", seat("one").stats.loot == 1,
			seat("one").stats.loot)
		check("priority went home", zones.active_seat() == "one", zones.active_seat())
		check("and the stack emptied", #(zones.find("stack") or { cards = {} }).cards == 0)
	end)
end

-- The reaction card is spent by its own word even though it opened a phase — the
-- stack never held it, so nothing about the interjection changes where it lands.
function M.test_interject_the_reaction_is_still_spent(check)
	with_game(function(name)
		flow.init(name, 3)
		local horn = zones.add(zone_of("hand", "one"), "horn")
		local envy = zones.add(zone_of("hand", "two"), "envy")

		flow.play_card(horn.id, {})
		flow.react(envy.id, 1, {})
		check("the answer is on its owner's table",
			entity.get(envy.id).zone_id == zone_of("table", "two").id)
		-- The horn has not resolved yet, so it is not spent yet either: it is still
		-- in the hand it was announced from, which is the honest state.
		check("while the horn is still in hand",
			entity.get(horn.id).zone_id == zone_of("hand", "one").id)
	end)
end

return M
