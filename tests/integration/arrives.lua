-- A zone's `arrives`: a card coming *into play* here, as opposed to merely
-- landing here.
--
-- The counterpart to a card's `leaves`, and it keeps the same rule at the other
-- end. `leaves` fires on the way out of play and a unit walking between two
-- board zones fires nothing; this fires on the way in, and a unit walking back
-- fires nothing either. Codex's whole combat is a move to the duel zone and home
-- again, and an arrival trigger that answered that would fire on every attack.
--
-- Asked with the arriving card as @self, where `receive` is asked with the zone:
-- `receive` is the place doing something about what landed in it, and this is a
-- card's arrival being announced. That is also what lets `emit` name the newcomer
-- and `others` leave it out of a pool.

local entity = require("entity")
local flow = require("flow")
local actions = require("actions")
local zones = require("zones")

local M = {}

local GAME = [==[{
  "title": "Arrives",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "seen", "label": "Seen", "subject": "seen@mine.player", "min": 0, "max": 40, "on": ["player"], "start": 0 },
    { "key": "plus", "min": 0, "max": 40, "on": ["unit"], "start": 0, "display": "offscreen" }
  ],
  "zones": [
    { "key": "army", "layout": "row", "status": "board", "use": "abilities", "copies": "per_seat",
      "arrives": { "action": ["stat_gain:seen@mine.player:1", "emit:arrived"] },
      "pos": [[0.05, 0.55, 0.9, 0.12], [0.05, 0.2, 0.9, 0.12]] },
    { "key": "bench", "layout": "row", "status": "board", "use": "abilities", "copies": "per_seat",
      "arrives": { "action": ["stat_gain:seen@mine.player:1"] },
      "pos": [[0.05, 0.4, 0.9, 0.12], [0.05, 0.05, 0.9, 0.12]] },
    { "key": "hand", "layout": "row", "copies": "per_seat",
      "pos": [[0.05, 0.68, 0.6, 0.12], [0.05, 0.82, 0.6, 0.12]] },
    { "key": "announced", "layout": "stack", "display": "offscreen", "use": "none", "tags": ["stack"] },
    { "key": "discard", "layout": "stack", "status": "grave", "copies": "per_seat",
      "pos": [[0.68, 0.68, 0.1, 0.12], [0.68, 0.82, 0.1, 0.12]] }
  ],
  "phases": [
    { "key": "deal", "type": "automatic",
      "actions": ["set_active_seat:seat_one", "create:mine.hand:grunt:2", "create:mine.hand:summoner:1", "create:mine.hand:ancient:2"],
      "next": [{ "then": "main" }] },
    { "key": "main", "type": "player_input", "zone": "hand", "next": [{ "then": "main" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "seen": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "seen": 0 } },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"],
      "play": { "phases": ["main"], "action": ["move_to:mine.army"] } },
    { "key": "summoner", "text": "Summoner", "tags": ["unit"],
      "play": { "phases": ["main"], "action": ["move_to:mine.army", "create:mine.army:grunt:3"] } },
    { "key": "ancient", "text": "Ancient", "tags": ["unit", "ancient"],
      "play": { "phases": ["main"], "action": ["move_to:mine.army"] },
      "reactions": [
        { "to": "arrived", "whose": "mine", "forced": "mandatory", "in": "board",
          "needs": { "req": ["not_self@event", "tagged:unit@event"] },
          "action": ["stat_gain:plus@self:1"] } ] }
  ],
  "setup": { "place": [{ "card": "one", "zone": "army" }, { "card": "two", "zone": "army" }] }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_arrives.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_arrives.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function zone(key, seat)
	for z in entity.each("zone") do
		if z.key == key and z.seat == seat then return z end
	end
end
local function find(key, zkey)
	for _, id in ipairs(zone(zkey, "one").cards) do
		local e = entity.get(id)
		if e.def_key == key then return e end
	end
end
local function seen() return find("one", "army").stats.seen end

-- Setup places cards with cards.create rather than through a zone, so a game
-- does not open on an arrival apiece. 425 of them in Codex.
function M.test_arrives_setup_is_not_an_arrival(check)
	with_game(function(name)
		flow.init(name, 3)
		check("nothing arrived before anybody played", seen() == 0, tostring(seen()))
	end)
end

function M.test_arrives_a_card_played_out_of_hand_arrives(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("grunt", "hand").id, {})
		check("one arrival", seen() == 1, tostring(seen()))
	end)
end

-- 22 of the 28 arrivals Codex was failing to announce were creates. `receive` is
-- not fired by `add` and never was; this is.
function M.test_arrives_a_created_token_arrives(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("summoner", "hand").id, {})
		check("the summoner and its three tokens are four arrivals", seen() == 4,
			tostring(seen()))
	end)
end

-- The rule this exists for. Codex's combat is a move out to the duel zone and
-- home again, on every attack.
function M.test_arrives_walking_between_two_board_zones_is_not_an_arrival(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("grunt", "hand").id, {})
		check("it arrived once", seen() == 1, tostring(seen()))
		local g = find("grunt", "army")
		actions.run({ "move:mine.army.unit:mine.bench" }, { card_id = g.id, targets = {} })
		check("and walking to the bench is not arriving", seen() == 1, tostring(seen()))
		actions.run({ "move:mine.bench.unit:mine.army" }, { card_id = g.id, targets = {} })
		check("nor is walking back", seen() == 1, tostring(seen()))
	end)
end

-- A card lent to a question comes home having arrived nowhere: `from` is the
-- zone it was borrowed from, not the offer it sat in, exactly as fire_leaves
-- already substitutes.
function M.test_arrives_a_card_lent_to_a_question_and_returned_has_not_arrived(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("grunt", "hand").id, {})
		check("it arrived once", seen() == 1, tostring(seen()))
		local g = find("grunt", "army")
		-- The real path: `show:` writes borrowed_from before it moves the card,
		-- which is what the substitution reads. Lending it by hand would skip
		-- the link and read as a card that genuinely left play.
		actions.run({ "show:mine.army.unit:optional" }, { card_id = g.id, targets = {} })
		check("it is lent out", entity.get(g.id).borrowed_from ~= nil,
			tostring(entity.get(g.id).borrowed_from))
		check("going out to the offer is not an arrival", seen() == 1, tostring(seen()))
		zones.move_card(g.id, zone("army", "one").id)
		check("and coming home is not one either", seen() == 1, tostring(seen()))
	end)
end

-- Leaving play is not arriving, and a zone that is not in play cannot be
-- arrived at -- which is what keeps a discard from announcing a death twice.
function M.test_arrives_landing_somewhere_out_of_play_is_not_an_arrival(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("grunt", "hand").id, {})
		local g = find("grunt", "army")
		actions.run({ "move:mine.army.unit:mine.discard" }, { card_id = g.id, targets = {} })
		check("going out of play announces no arrival", seen() == 1, tostring(seen()))
	end)
end

-- Coming back from the dead is arriving: it was out of play and now it is in.
function M.test_arrives_coming_back_from_out_of_play_is_an_arrival(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("grunt", "hand").id, {})
		local g = find("grunt", "army")
		actions.run({ "move:mine.army.unit:mine.discard" }, { card_id = g.id, targets = {} })
		check("still one", seen() == 1, tostring(seen()))
		actions.run({ "move:mine.discard.unit:mine.army" }, { card_id = g.id, targets = {} })
		check("and raising it is a second arrival", seen() == 2, tostring(seen()))
	end)
end

-- A zone that is not play cannot be arrived at, so saying "arrives" there is a
-- rule that can never fire. Said at authoring time rather than left silent.
function M.test_arrives_a_zone_out_of_play_cannot_be_arrived_at(check)
	local path = "game/games/tmp_arrives_bad.json"
	local f = assert(io.open(path, "w"))
	f:write((GAME:gsub('{ "key": "discard", "layout": "stack", "status": "grave", "copies": "per_seat",',
		'{ "key": "discard", "layout": "stack", "status": "grave", "copies": "per_seat",'
		.. ' "arrives": { "action": ["stat_gain:seen@mine.player:1"] },', 1)))
	f:close()
	local declaration = require("declaration")
	local validate = require("validate")
	local ok, G = pcall(declaration.parse, "tmp_arrives_bad.json")
	os.remove(path)
	if not ok then error(G, 2) end
	local said = table.concat(validate.check(G), "; ")
	check("it says the status is why nothing would fire",
		said:find("come into play in a zone that", 1, true) ~= nil, said)
end

-- The shape Codex's Blooming Ancient now uses, end to end: the zone announces
-- an arrival, and the watcher answers with a mandatory reaction. The rule lives
-- on the card that prints it, "another" is `not_self@event`, and it fires once
-- per watcher -- which is what "every Blooming Ancient you have" means.
function M.test_arrives_a_watcher_answers_every_arrival_but_its_own(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("ancient", "hand").id, {})
		local a = find("ancient", "army")
		check("its own arrival does not rune it", a.stats.plus == 0, tostring(a.stats.plus))

		flow.play_card(find("grunt", "hand").id, {})
		check("another unit arriving does", a.stats.plus == 1, tostring(a.stats.plus))

		-- The 22-of-28 case: a card that arrives and then conjures three more.
		flow.play_card(find("summoner", "hand").id, {})
		check("and so does each created token, four arrivals in one play",
			a.stats.plus == 5, tostring(a.stats.plus))

		-- Two watchers, one arrival: a rune each, not one shared between them.
		local b = find("ancient", "hand")
		flow.play_card(b.id, {})
		check("a second watcher arriving runes the first", a.stats.plus == 6, tostring(a.stats.plus))
		check("and does not rune itself", b.stats.plus == 0, tostring(b.stats.plus))
		flow.play_card(find("grunt", "hand").id, {})
		check("now one arrival runes both", a.stats.plus == 7 and b.stats.plus == 1,
			a.stats.plus .. "/" .. b.stats.plus)
	end)
end

-- And the case the whole status rule exists for, through the reaction rather
-- than through the counter: walking out and back must announce nothing.
function M.test_arrives_a_watcher_ignores_a_walk_between_board_zones(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("ancient", "hand").id, {})
		flow.play_card(find("grunt", "hand").id, {})
		local a = find("ancient", "army")
		check("one arrival so far", a.stats.plus == 1, tostring(a.stats.plus))
		local g = find("grunt", "army")
		actions.run({ "move:mine.army.unit:mine.bench" }, { card_id = g.id, targets = {} })
		flow.settle()
		actions.run({ "move:mine.bench.unit:mine.army" }, { card_id = g.id, targets = {} })
		flow.settle()
		check("and the round trip announced nothing", a.stats.plus == 1, tostring(a.stats.plus))
	end)
end

return M
