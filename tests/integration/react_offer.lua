-- A reaction that asks a question of its own.
--
-- "Trash a chip, then take one costing up to 2 more" is a sentence three Puzzle
-- Strike chips say, and two of them say it in a main phase where it is one
-- `show:` and one `chosen`. The third says it as a *reaction*, and converting it
-- lost the buy it was answering: the pick resolved, the offer closed, and the
-- announcement underneath was simply gone.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")

local M = {}

local GAME = [==[{
  "title": "React Offer",
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
    { "key": "shelf", "layout": "row", "pos": [0.05, 0.40, 0.45, 0.55] },
    { "key": "shop", "layout": "row", "use": "abilities", "status": "supply",
      "applies": ["buyable", "for_sale"], "contents": ["widget:5", "gadget:5"],
      "pos": [0.05, 0.22, 0.45, 0.36] },
    { "key": "options", "layout": "row", "status": "offer", "pos": [0.10, 0.30, 0.90, 0.70] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "tags": {
    "buyable": { "emits": { "activate": "buy" } },
    "for_sale": { "abilities": [
      { "key": "buy", "text": "Buy it", "merge": "this",
        "action": ["take:self:mine.graveyard:1", "stat_gain:landed@mine.player:1"] }] }
  },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "landed": 0, "mana": 3 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "landed": 0, "mana": 3 } },
    { "key": "trinket", "text": "Trinket", "tags": ["goods"] },
    { "key": "widget", "text": "Widget", "tags": ["goods"] },
    { "key": "gadget", "text": "Gadget", "tags": ["goods"] },
    { "key": "shopper", "text": "Shopper", "tags": ["counter"],
      "reactions": [
        { "to": "buy", "action": ["show:shop:optional"], "spent": "mine.graveyard" }
      ],
      "chosen": { "action": ["stat_gain:mana@mine.player:1"] } },
    { "key": "fireball", "text": "Fireball", "tags": ["spell", "fireball"],
      "play": { "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.graveyard" } },
    { "key": "browser", "text": "Browser", "tags": ["counter"],
      "reactions": [
        { "to": "play", "where": ["tagged:fireball@event"],
          "action": ["show:shelf:optional"], "spent": "mine.graveyard" }
      ],
      "chosen": { "action": ["move:target:mine.graveyard", "stat_gain:mana@mine.player:1"] } }
  ],
  "setup": { "place": [{ "card": "trinket", "zone": "shelf" },
                       { "card": "trinket", "zone": "shelf" },
                       { "card": "trinket", "zone": "shelf" }] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_react_offer.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_react_offer.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function stack_count()
	return #(zones.find("stack") or { cards = {} }).cards
end

-- The whole of it: the answer asks a question, the question is answered, and the
-- thing being answered still happens.
function M.test_react_offer_the_announcement_survives_the_question(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = zones.add(hand_of("one"), "fireball")
		local br = zones.add(hand_of("two"), "browser")

		flow.cast(fb.id)
		check("the window opened for the other seat", zones.active_seat() == "two", zones.active_seat())
		flow.react(br.id, 1, {})

		check("the reaction's own question is up", phase.current().key == "options", phase.current().key)
		check("and it is the reactor's to answer", zones.active_seat() == "two", zones.active_seat())
		check("the spell is still waiting underneath", stack_count() >= 1, stack_count())

		local pick = zones.find("options").cards[1]
		check("the pick goes through", flow.play_card(pick, {}))
		check("the chosen block ran", seat("two").stats.mana == 4, seat("two").stats.mana)

		check("and the spell it was answering landed", seat("one").stats.landed == 1,
			seat("one").stats.landed)
		check("the stack is empty", stack_count() == 0, stack_count())
		check("priority is back with the caster", zones.active_seat() == "one", zones.active_seat())
	end)
end

-- The same, when what is announced is an *activation* and the offer is over the
-- very zone the announcement came from — which is Puzzle Strike's shape exactly:
-- a bank plate bought, answered by a chip that offers the bank.
function M.test_react_offer_an_activation_survives_an_offer_of_its_own_zone(check)
	with_game(function(name)
		flow.init(name, 3)
		local sh = zones.add(hand_of("two"), "shopper")
		local plate
		for _, id in ipairs(zones.find("shop").cards) do
			if entity.get(id).def_key == "widget" then plate = entity.get(id) end
		end

		flow.activate(plate.id, {}, 1)
		check("the buy was announced", zones.active_seat() == "two", zones.active_seat())
		check("and is waiting on the stack", stack_count() == 1, stack_count())

		flow.react(sh.id, 1, {})
		check("the reaction's question is up", phase.current().key == "options", phase.current().key)

		local pick = zones.find("options").cards[1]
		check("the pick goes through", flow.play_card(pick, {}))
		check("the chosen block ran", seat("two").stats.mana == 4, seat("two").stats.mana)
		check("and the buy it was answering happened", seat("one").stats.landed == 1,
			seat("one").stats.landed)
		check("the goods came out of the box", #zones.all_with_key("graveyard")[1].cards == 1,
			#zones.all_with_key("graveyard")[1].cards)
		check("the stack is empty", stack_count() == 0, stack_count())
	end)
end

return M
