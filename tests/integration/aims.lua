-- A verb that names the *aim* rather than an action, and the two things that
-- read it.
--
-- "Cannot be targeted by spells" was never a question about the caster: the
-- hero that casts is the hero that attacks, so no tag on the aiming card can
-- tell the two apart. Every game with the keyword wrote the exception on every
-- spell instead. A target spec that says which kind of aim it is moves the rule
-- back onto the card that has it — and the same word, watched by an `adjusts`,
-- is resist.

local entity    = require("entity")
local flow      = require("flow")
local zones     = require("zones")
local cards     = require("cards")
local targeting = require("targeting")

local M = {}

local GAME = [==[{
  "title": "Aims",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "hp", "on": ["unit"], "start": 10, "min": 0, "max": 10 },
    { "key": "gold", "on": ["player"], "start": 10, "min": 0, "max": 99 }
  ],
  "verbs": [
    { "key": "attack", "does": "target", "tooltip": "One fighter picking what it throws itself at." },
    { "key": "cast",   "does": "target", "tooltip": "A spell picking what it lands on." }
  ],
  "computed_tags": { "hurt": { "needs": ["hp@self < 5"] } },
  "tags": {
    "resist_1": {
      "adjusts": [{ "key": "resist", "verb": "cast", "stat": "gold", "covers": "self", "by": 1 }]
    },
    "hurt": {
      "adjusts": [{ "key": "desperate", "verb": "cast", "stat": "gold", "covers": "self", "by": 2 }]
    }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "warded", "text": "Warded", "tags": ["unit"],
      "receive": { "needs": ["not_verb:cast"] } },
    { "key": "tough", "text": "Tough", "tags": ["unit", "resist_1"] },
    { "key": "bolt", "text": "Bolt", "tags": ["spell"],
      "play": { "cost": { "gold@mine.player": 3 },
        "target": { "verb": "cast", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } },
    { "key": "punch", "text": "Punch", "tags": ["spell"],
      "play": { "target": { "verb": "attack", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } },
    { "key": "shove", "text": "Shove", "tags": ["spell"],
      "play": { "target": { "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } }
  ],
  "setup": {
    "place": [
      { "card": "grunt", "zone": "field" }, { "card": "warded", "zone": "field" },
      { "card": "tough", "zone": "field" },
      { "card": "bolt", "zone": "hand" }, { "card": "punch", "zone": "hand" },
      { "card": "shove", "zone": "hand" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_aims.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_aims.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

-- Who the named aim is offered, as a sorted list of card keys.
local function offered(aimer)
	local c    = find(aimer)
	local defs = require("declaration").G.card_defs
	local out  = {}
	for _, id in ipairs(targeting.candidates(c.id, defs[aimer].target)) do
		out[#out + 1] = entity.get(id).def_key
	end
	table.sort(out)
	return table.concat(out, ",")
end

-- The whole point, in one test: two aims at the same cards, and the ward tells
-- them apart because the target spec said which kind each one was.
function M.test_aims_a_ward_refuses_one_kind_of_aim(check)
	with_game(function(name)
		flow.init(name, 3)
		check("a cast is refused by the ward", offered("bolt") == "grunt,tough", offered("bolt"))
		check("an attack is not", offered("punch") == "grunt,tough,warded", offered("punch"))
	end)
end

-- An aim the game never named is not a cast. Being interfered with is opted
-- into here as everywhere else, so a file with no verbs wards nothing.
function M.test_aims_an_unnamed_aim_answers_no(check)
	with_game(function(name)
		flow.init(name, 3)
		check("an aim that says nothing walks past the ward",
			offered("shove") == "grunt,tough,warded", offered("shove"))
	end)
end

-- Resist: the same verb, watched by an aura whose stat is what the aimer pays.
function M.test_aims_resist_is_paid_by_whoever_points(check)
	with_game(function(name)
		flow.init(name, 3)
		local seat = find("one")
		flow.play_card(find("bolt").id, { find("grunt").id })
		check("a plain target costs the printed price", seat.stats.gold == 7,
			tostring(seat.stats.gold))
		seat.stats.gold = 10
		cards.create("bolt", zones.find_id("hand"))
		flow.play_card(find("bolt").id, { find("tough").id })
		check("and a resisting one costs a gold more", seat.stats.gold == 6,
			tostring(seat.stats.gold))
	end)
end

-- Nothing is charged before there is a target: playability is judged with none
-- chosen, so a card in hand is dimmed on its printed cost and learns the
-- surcharge when you pick.
function M.test_aims_the_surcharge_arrives_with_the_target(check)
	with_game(function(name)
		flow.init(name, 3)
		local seat = find("one")
		seat.stats.gold = 3
		check("three gold is enough to hold the bolt up", flow.can_play(find("bolt").id))
		check("but not enough to aim it at the resisting one",
			not flow.play_card(find("bolt").id, { find("tough").id }))
		check("and the gold is untouched", seat.stats.gold == 3, tostring(seat.stats.gold))
		check("while the plain one goes through",
			flow.play_card(find("bolt").id, { find("grunt").id }))
	end)
end

-- A computed tag may carry an aura, exactly as it may carry a buff: both are
-- things that are true. Codex's lookout post is the case — resist while
-- something stands on the fifth square.
function M.test_aims_a_computed_tag_may_resist(check)
	with_game(function(name)
		flow.init(name, 3)
		local seat = find("one")
		flow.play_card(find("bolt").id, { find("grunt").id })
		check("a whole grunt costs the printed price", seat.stats.gold == 7,
			tostring(seat.stats.gold))
		find("grunt").stats.hp = 2
		seat.stats.gold = 10
		cards.create("bolt", zones.find_id("hand"))
		flow.play_card(find("bolt").id, { find("grunt").id })
		check("a hurt one costs two more, and stops when it is healed",
			seat.stats.gold == 5, tostring(seat.stats.gold))
	end)
end

-- Two resisting targets in one aim are two surcharges.
function M.test_aims_every_target_is_asked(check)
	with_game(function(name)
		flow.init(name, 3)
		local seat = find("one")
		local defs = require("declaration").G.card_defs
		defs.bolt.target.count, defs.bolt.target.max = nil, 2
		defs.bolt.target.min = 1
		local second = cards.create("tough", zones.find_id("field"))
		flow.play_card(find("bolt").id, { find("tough").id, second.id })
		check("aiming at two costs two more", seat.stats.gold == 5, tostring(seat.stats.gold))
	end)
end

return M
