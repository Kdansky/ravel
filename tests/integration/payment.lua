-- Who decides which coins settle a price.
--
-- A cost is decided in full before anything is spent — that is the whole of what
-- separates it from an effect. An effect that cannot happen is skipped where it
-- stands; a cost that cannot be paid stops the card being played at all, so
-- there is never half a payment to unwind. Every way of settling a price is
-- therefore a *complete* plan, known payable before a single coin moves, and
-- choosing between them is safe by construction.
--
-- `select` in a scope's quantifier slot is how a game says the choice is the
-- player's. Without it the engine settles greedily, as it always has. A
-- sacrifice is the exception that needs no word: taking somebody's unit is
-- always theirs to choose.

local entity    = require("entity")
local flow      = require("flow")
local zones     = require("zones")
local cards     = require("cards")
local targeting = require("targeting")

local M = {}

local GAME = [==[{
  "title": "Payment",
  "players": [{ "card": "north" }, { "card": "south" }],
  "stats": [
    { "key": "gold", "on": ["land"], "start": 3, "min": 0, "max": 99 },
    { "key": "tally", "on": ["player"], "start": 0, "min": 0, "max": 99 },
    { "key": "red", "on": ["player"], "start": 0, "min": 0, "max": 99 },
    { "key": "blue", "on": ["player"], "start": 0, "min": 0, "max": 99 },
    { "key": "wild", "on": ["player"], "start": 0, "min": 0, "max": 99, "pays_for": ["red", "blue"] }
  ],
  "zones": [
    { "key": "seat_box", "status": "board", "layout": "stack", "copies": "per_seat", "pos": [[0.02, 0.80, 0.16, 0.98], [0.02, 0.02, 0.16, 0.20]] },
    { "key": "field", "status": "board", "layout": "row", "copies": "per_seat", "pos": [[0.20, 0.58, 0.80, 0.72], [0.20, 0.08, 0.80, 0.22]] },
    { "key": "army", "status": "board", "use": "abilities", "layout": "row", "copies": "per_seat", "pos": [[0.20, 0.42, 0.80, 0.56], [0.20, 0.24, 0.80, 0.38]] },
    { "key": "hand", "layout": "row", "copies": "per_seat", "pos": [[0.20, 0.80, 0.80, 0.95], [0.20, 0.05, 0.80, 0.20]] },
    { "key": "discard", "status": "grave", "layout": "stack", "copies": "per_seat", "pos": [[0.84, 0.80, 0.98, 0.98], [0.84, 0.02, 0.98, 0.20]] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "north", "text": "North" },
    { "key": "south", "text": "South" },
    { "key": "land", "text": "Land", "tags": ["land"] },
    { "key": "soldier", "text": "Soldier", "tags": ["unit"] },
    { "key": "chosen_spell", "text": "Chosen Spell",
      "play": { "cost": { "gold@select.mine.field": 5 }, "action": ["stat_gain:tally@mine.player:1"] } },
    { "key": "greedy_spell", "text": "Greedy Spell",
      "play": { "cost": { "gold@mine.field": 5 }, "action": ["stat_gain:tally@mine.player:1"] } },
    { "key": "pool_spell", "text": "Pool Spell",
      "play": { "cost": { "red@select.mine.player": 1 }, "action": ["stat_gain:tally@mine.player:1"] } },
    { "key": "rite", "text": "Rite",
      "play": { "cost": { "sacrifice:unit": 1 }, "action": ["stat_gain:tally@mine.player:1"] } },
    { "key": "bomber", "text": "Bomber", "tags": ["unit"],
      "abilities": [{ "key": "boom", "cost": { "sacrifice:self": 1 },
        "action": ["stat_gain:tally@mine.player:1"] }] }
  ],
  "setup": {
    "place": [
      { "card": "north", "zone": "seat_box", "owner": "north" },
      { "card": "south", "zone": "seat_box", "owner": "south" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_payment.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_payment.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function make(key, zone_key, owner)
	return cards.create(key, zones.find(zone_key, owner).id)
end

local function gold(c)
	local e = entity.get(c.id)
	return e and e.stats and e.stats.gold
end

-- Two lands of three, and a price of five: the only question is which land is
-- left with one.
local function two_lands()
	return make("land", "field"), make("land", "field")
end

-- A price nobody has a choice about is one plan, and the plan is what the engine
-- would have paid by itself. This is almost every cost in every game, and the
-- reason nothing had to be asked before now.
function M.test_payment_a_cost_with_one_answer_asks_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		two_lands()
		local spell = make("greedy_spell", "hand")
		local ways  = flow.play_payments(spell.id, {})
		check("one way to pay", #ways == 1, tostring(#ways))
		check("and nothing to ask", targeting.begin_payment(ways, spell.id, "play", {}) == false)
	end)
end

-- "select" opens the price out: every split of five across two lands of three.
function M.test_payment_select_offers_every_split(check)
	with_game(function(name)
		flow.init(name, 3)
		two_lands()
		local spell = make("chosen_spell", "hand")
		local ways  = flow.play_payments(spell.id, {})
		check("both splits are offered", #ways == 2, tostring(#ways))
		-- The greedy plan is always the head of the list, so stopping the
		-- enumeration early can cost the choice but never the payment.
		local head = ways[1]
		check("the greedy plan comes first", head[1].n == 3, tostring(head[1].n))
	end)
end

-- The chosen split is what is actually spent, and it is not the greedy one.
function M.test_payment_the_chosen_split_is_what_is_spent(check)
	with_game(function(name)
		flow.init(name, 3)
		local a, b = two_lands()
		local spell = make("chosen_spell", "hand")
		local ways  = flow.play_payments(spell.id, {})
		-- The way that leaves the *first* land holding two, which greedy would
		-- have emptied.
		local want
		for _, plan in ipairs(ways) do
			for _, step in ipairs(plan) do
				if step.id == a.id and step.n == 2 then want = plan end
			end
		end
		check("there is a split taking two off the first land", want ~= nil)
		check("it was played", flow.play_card(spell.id, {}, want) == true)
		check("the first land kept one", gold(a) == 1, tostring(gold(a)))
		check("and the second is empty", gold(b) == 0, tostring(gold(b)))
	end)
end

-- Flow is the single legality gate, and a payment arrives beside the targets —
-- from an interface, a script, the network or an engine seat. A payment that is
-- not one of the ways this cost may be settled is refused, exactly as a target
-- the rules never offered is.
function M.test_payment_a_fabricated_payment_is_refused(check)
	with_game(function(name)
		flow.init(name, 3)
		local a, b = two_lands()
		local spell = make("chosen_spell", "hand")
		local lie = { { subject = "gold@select.mine.field", n = 1, id = a.id, stat = "gold" } }
		check("a payment covering less than the price is refused",
			flow.play_card(spell.id, {}, lie) == false)
		check("and nothing was taken", gold(a) == 3 and gold(b) == 3,
			tostring(gold(a)) .. "/" .. tostring(gold(b)))
	end)
end

-- The other half of "select": where pays_for gives a price two pools that could
-- both settle it, the player says which.
function M.test_payment_select_chooses_between_pools(check)
	with_game(function(name)
		flow.init(name, 3)
		local me = entity.get(zones.find("seat_box").cards[1])
		me.stats.red, me.stats.wild = 1, 1
		local spell = make("pool_spell", "hand")
		local ways  = flow.play_payments(spell.id, {})
		check("either pool may settle it", #ways == 2, tostring(#ways))
		local wild
		for _, plan in ipairs(ways) do
			for _, step in ipairs(plan) do
				if step.stat == "wild" then wild = plan end
			end
		end
		check("one of them spends the wild", wild ~= nil)
		check("it was played", flow.play_card(spell.id, {}, wild) == true)
		check("the wild went", me.stats.wild == 0, tostring(me.stats.wild))
		check("and the red stayed", me.stats.red == 1, tostring(me.stats.red))
	end)
end

-- A sacrifice needs no word to be the player's: taking somebody's unit is always
-- a choice, so every combination is offered and the oldest is only the default.
function M.test_payment_a_sacrifice_always_asks(check)
	with_game(function(name)
		flow.init(name, 3)
		local one, two, three = make("soldier", "army"), make("soldier", "army"), make("soldier", "army")
		local rite = make("rite", "hand")
		local ways = flow.play_payments(rite.id, {})
		check("three units, three ways to pay", #ways == 3, tostring(#ways))
		local want
		for _, plan in ipairs(ways) do
			if plan[1].ids[1] == three.id then want = plan end
		end
		check("one of them takes the newest", want ~= nil)
		check("it was played", flow.play_card(rite.id, {}, want) == true)
		check("the newest died", entity.get(three.id).zone_id == nil)
		check("and the older two are standing",
			entity.get(one.id).zone_id ~= nil and entity.get(two.id).zone_id ~= nil)
	end)
end

-- **"self" is the asking card, which no tag can name.** A cost already reached
-- its own card for "exhaust"; without this a game gave one card a private tag
-- and killed the wrong copy the moment there were two of it.
function M.test_payment_sacrifice_self_takes_the_asking_card(check)
	with_game(function(name)
		flow.init(name, 3)
		local first, second = make("bomber", "army"), make("bomber", "army")
		local ways = flow.rule_payments(second.id, cards.def(entity.get(second.id)).abilities[1], {})
		check("spending itself is one way, never two", #ways == 1, tostring(#ways))
		check("it went off", flow.activate(second.id, {}, 1, ways[1]) == true)
		check("the card that asked is gone", entity.get(second.id).zone_id == nil)
		check("and the other one is untouched", entity.get(first.id).zone_id ~= nil)
	end)
end

-- Paying is picking, so it is the same session as aiming: a card is pointed at
-- once per coin, and each pick drops every way that does not spend that much off
-- it. The payment is what is left when everything it is not has been ruled out.
function M.test_payment_picking_narrows_to_one_way(check)
	with_game(function(name)
		flow.init(name, 3)
		local a, b = two_lands()
		local spell = make("chosen_spell", "hand")
		check("there is something to ask",
			targeting.begin_payment(flow.play_payments(spell.id, {}), spell.id, "play", {}) == true)
		check("five coins are owed", targeting.spec.min == 5, tostring(targeting.spec.min))
		check("both lands may be pointed at", #targeting.eligible == 2, tostring(#targeting.eligible))
		check("and nothing is settled yet", targeting.payment() == nil)
		for _ = 1, 3 do targeting.add(b.id) end
		check("three off the second land leaves only one way", #targeting.ways == 1, tostring(#targeting.ways))
		check("the first land is all that is left to point at",
			#targeting.eligible == 1 and targeting.eligible[1] == a.id)
		for _ = 1, 2 do targeting.add(a.id) end
		local plan = targeting.payment()
		check("the price is settled", plan ~= nil)
		check("it was played", flow.play_card(spell.id, {}, plan) == true)
		check("and the second land is the empty one", gold(b) == 0 and gold(a) == 1,
			tostring(gold(a)) .. "/" .. tostring(gold(b)))
		targeting.clear()
	end)
end

-- An engine seat weighs every way of paying, because each one is a different
-- move. There are few enough moves in a turn that a handful more costs nothing.
function M.test_payment_an_engine_seat_sees_every_way(check)
	with_game(function(name)
		flow.init(name, 3)
		two_lands()
		make("chosen_spell", "hand")
		local opponent = require("opponent")
		opponent.take(zones.active_seat())
		local moves = #opponent.legal()
		opponent.leave()
		check("both ways of paying are moves of their own", moves == 2, tostring(moves))
	end)
end

-- A caller that names no payment gets the plan the engine would have paid by
-- itself, which is what keeps every interface that never learned to ask working
-- unchanged — the debug API and the network among them.
function M.test_payment_naming_no_payment_pays_greedily(check)
	with_game(function(name)
		flow.init(name, 3)
		local a, b = two_lands()
		local spell = make("chosen_spell", "hand")
		check("it was played", flow.play_card(spell.id, {}) == true)
		check("the first land was emptied first", gold(a) == 0 and gold(b) == 1,
			tostring(gold(a)) .. "/" .. tostring(gold(b)))
	end)
end

-- **"select" is what makes an ambiguous substitution legal.** Two `pays_for`
-- pools that overlap without nesting are refused at a price the engine would
-- settle greedily, because the greedy can refuse a cost that was payable. Said
-- with "select" the overlap is the question rather than the bug — which is why
-- the complaint is made at the price and not at the stats.
function M.test_payment_select_makes_an_ambiguous_substitution_legal(check)
	local declaration, validate = require("declaration"), require("validate")
	with_game(function(name)
		local function said(subject)
			local g = declaration.parse(name)
			g.stat_defs.ab = { key = "ab", pays_for = { "red", "blue" } }
			g.stat_defs.bc = { key = "bc", pays_for = { "blue", "tally" } }
			g.stat_defs_list[#g.stat_defs_list + 1] = "ab"
			g.stat_defs_list[#g.stat_defs_list + 1] = "bc"
			g.card_defs.greedy_spell.cost = { [subject] = 1 }
			g.card_defs.greedy_spell.play.cost = g.card_defs.greedy_spell.cost
			return table.concat(validate.check(g), "\n")
		end
		check("a greedy price across the overlap is refused",
			said("blue@mine.player"):find("do not nest", 1, true) ~= nil)
		check("and the same price the player settles is not",
			said("blue@select.mine.player"):find("do not nest", 1, true) == nil)
	end)
end

return M
