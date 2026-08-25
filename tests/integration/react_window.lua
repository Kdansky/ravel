-- The response window, end to end: a spell cast onto the stack, a reaction
-- played out of turn to answer it, priority passing while the turn stays put,
-- and the stack resolving last-in-first-out. Depth-1 (resolve, counter, pass)
-- and depth-2 (answer the answer) both, on one synthetic game — which is what
-- says the depth-1 build is the general loop and not a shortcut.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local net = require("net")
local json = require("json")

local M = {}

local GAME = [==[{
  "title": "React Window",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "landed", "label": "Landed", "subject": "landed@mine.player" },
    { "key": "mana", "label": "Mana", "subject": "mana@mine.player" }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "graveyard", "layout": "stack", "copies": "per_seat",
      "pos": [[0.75, 0.80, 0.90, 0.95], [0.75, 0.05, 0.90, 0.20]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "landed": 0, "mana": 3 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "landed": 0, "mana": 3 } },
    { "key": "fireball", "text": "Fireball", "tags": ["spell", "fireball"],
      "play": { "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.graveyard" } },
    { "key": "flame_counter", "text": "Flame Counter", "tags": ["counter"],
      "reactions": [
        { "to": "play", "where": ["tagged:fireball@event >= 1"],
          "action": ["counterspell"], "spent": "mine.graveyard" }
      ] },
    { "key": "ward", "text": "Ward", "tags": ["counter"],
      "reactions": [
        { "to": "play", "where": ["tagged:fireball@event >= 1"],
          "action": ["stat_gain:mana@mine.player:1"] }
      ] },
    { "key": "spellshield", "text": "Spellshield", "tags": ["shield"],
      "reactions": [
        { "to": "play", "where": ["tagged:counter@event >= 1"],
          "action": ["counterspell"], "spent": "mine.graveyard" }
      ] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_react_window.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_react_window.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function grave_of(key)
	for _, z in ipairs(zones.all_with_key("graveyard")) do
		if z.seat == key then return z end
	end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function give(seat_key, def_key)
	return zones.add(hand_of(seat_key), def_key)
end

local function stack_count()
	return #(zones.find("stack") or { cards = {} }).cards
end

-- Nobody can answer, so no window opens and the spell simply lands — the
-- suppression that keeps an unanswerable action from ever prompting.
function M.test_react_window_unanswered_spell_lands(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		flow.cast(fb.id)
		check("the spell resolved", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("the stack is empty again", stack_count() == 0, stack_count())
		check("the turn is the caster's still", zones.active_seat() == "one", zones.active_seat())
	end)
end

-- The other seat holds a counter, so casting opens a window: priority passes to
-- them while the turn stays put, and answering removes the spell before it lands.
function M.test_react_window_a_reaction_counters(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local fc = give("two", "flame_counter")

		flow.cast(fb.id)
		check("the window opened for the other seat", zones.active_seat() == "two",
			zones.active_seat())
		check("without moving the turn", zones.turn_seat() == "one", zones.turn_seat())
		check("the spell is waiting on the stack", stack_count() == 1, stack_count())

		flow.react(fc.id, 1, {})
		check("the spell never landed", seat("one").stats.landed == 0, seat("one").stats.landed)
		check("the stack cleared", stack_count() == 0, stack_count())
		check("priority went back to the turn", zones.active_seat() == "one", zones.active_seat())
	end)
end

-- Declining the window lets the spell through: the counter is not spent, and
-- passing is a real answer, distinct from having none.
function M.test_react_window_passing_lets_it_resolve(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local fc = give("two", "flame_counter")

		flow.cast(fb.id)
		check("the window is open", zones.active_seat() == "two")
		flow.pass_react()
		check("the spell resolved after the pass", seat("one").stats.landed == 1,
			seat("one").stats.landed)
		check("the counter is still in hand, unspent",
			entity.get(fc.id) ~= nil and entity.get(fc.id).zone_id == hand_of("two").id)
		check("the turn seat is acting again", zones.active_seat() == "one")
	end)
end

-- Depth-2: the counter is itself answered. The spellshield goes on above the
-- counter and resolves first, taking the counter with it — so the spell lands
-- after all. Last-in-first-out, and priority passing back and forth.
function M.test_react_window_answer_the_answer(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local ss = give("one", "spellshield")
		local fc = give("two", "flame_counter")

		flow.cast(fb.id)
		check("first the other seat may answer", zones.active_seat() == "two")
		flow.react(fc.id, 1, {})
		check("now the caster may answer the counter", zones.active_seat() == "one",
			zones.active_seat())
		check("both spell and counter are on the stack", stack_count() == 2, stack_count())

		flow.react(ss.id, 1, {})
		check("the counter was countered", entity.get(fc.id).zone_id == grave_of("two").id)
		check("so the spell landed after all", seat("one").stats.landed == 1,
			seat("one").stats.landed)
		check("the shield is spent", entity.get(ss.id).zone_id == grave_of("one").id)
		check("the stack is empty", stack_count() == 0, stack_count())
		check("and the turn is back to normal", zones.active_seat() == "one")
	end)
end

-- A record remembers who has already answered it, and has to still remember
-- after the state has been through JSON — which every save and every full sync
-- does. Card ids are numbers, and a map keyed by one comes back keyed by a
-- string, so a set would forget and the same card could answer forever.
function M.test_react_window_answered_survives_a_round_trip(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local ss = give("one", "spellshield")
		local wd = give("two", "ward")

		flow.cast(fb.id)
		flow.react(wd.id, 1, {})
		check("the ward is answerable in turn, so the caster is up", zones.active_seat() == "one",
			zones.active_seat())
		check("both records are on the stack", stack_count() == 2, stack_count())

		local ok, err = net.apply_full(json.decode(json.encode(net.snapshot())))
		check("the state survives an encode/decode/apply", ok, err)

		flow.pass_react()
		check("the ward resolved", seat("two").stats.mana == 4, seat("two").stats.mana)
		check("and the spell landed behind it", seat("one").stats.landed == 1,
			seat("one").stats.landed)
		check("the ward was not asked twice", stack_count() == 0, stack_count())
		check("so nobody is left holding priority", zones.active_seat() == "one",
			zones.active_seat())
		check("the shield was never needed", entity.get(ss.id).zone_id == hand_of("one").id)
	end)
end

return M
