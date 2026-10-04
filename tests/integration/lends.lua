-- A word a card did not print, handed to it from outside: `lends` while the lender
-- stands, `tag:` until somebody takes it back. Codex's Dreamscape and Hallucination
-- are the customers — "All tech 0, I and II units are Illusions" and "Up to two
-- tech 0, I or II units are Illusions this turn" — and the Illusion keyword they
-- hand out is the printed one, untouched, so its dying comes with the word.

local entity  = require("entity")
local flow    = require("flow")
local tags    = require("tags")
local cards   = require("cards")
local zones   = require("zones")
local harness = require("harness")

local M = {}

local GAME = [==[{
  "title": "Lends",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "hp", "on": ["unit"], "start": 3, "min": 0, "max": 3 },
    { "key": "tech_level", "on": ["unit"], "start": 1, "min": 0, "max": 3 }
  ],
  "verbs": [{ "key": "cast", "does": "target", "tooltip": "A spell picking what it lands on." }],
  "tags": {
    "illusion": { "tooltip": "Illusion — dies when a spell aims at it.",
      "receive": { "when": ["verb:cast"], "action": ["destroy:self"] } }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] },
    { "key": "ongoing", "status": "board", "layout": "row", "pos": [0.60, 0.40, 0.75, 0.55] },
    { "key": "discard", "status": "grave", "layout": "stack", "pos": [0.60, 0.80, 0.70, 0.95] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "titan", "text": "Titan", "tags": ["unit"], "card_stats": { "tech_level": 3 } },
    { "key": "mirror", "text": "Mirror", "tags": ["unit", "illusion"] },
    { "key": "dreamer", "text": "Dreamer", "tags": ["dream"],
      "lends": { "covers": "anyone.unit", "needs": { "req": ["tech_level@target <= 2"] }, "tags": ["illusion"] } },
    { "key": "bolt", "text": "Bolt",
      "play": { "target": { "verb": "cast", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } },
    { "key": "haze", "text": "Haze",
      "play": { "target": { "type": "card", "tags": ["unit"], "min": 0, "max": 2 }, "action": ["tag:target:illusion"] } },
    { "key": "dawn", "text": "Dawn", "play": { "action": ["untag:each.unit:illusion"] } },
    { "key": "wake", "text": "Wake", "play": { "action": ["move:each.dream:discard"] } },
    { "key": "recall", "text": "Recall",
      "play": { "target": { "type": "card", "tags": ["unit"], "count": 1 }, "action": ["move:target:hand"] } }
  ],
  "setup": {
    "place": [
      { "card": "grunt", "zone": "field" }, { "card": "titan", "zone": "field" },
      { "card": "mirror", "zone": "field" },
      { "card": "bolt", "zone": "hand" }, { "card": "haze", "zone": "hand" },
      { "card": "dawn", "zone": "hand" }, { "card": "wake", "zone": "hand" },
      { "card": "recall", "zone": "hand" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/" .. harness.tmp("lends")
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, harness.tmp("lends"))
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function zone_of(key)
	local z = find(key).zone_id and entity.get(find(key).zone_id)
	return z and z.key or "gone"
end

local function illusion(key)
	return tags.entity_has(find(key), "illusion")
end

local function dream(name)
	flow.init(name, 3)
	zones.add(entity.get(zones.find_id("ongoing")), "dreamer")
end

function M.test_lends_a_word_to_what_it_covers_and_nothing_else(check)
	with_game(function(name)
		flow.init(name, 3)
		check("nothing is an Illusion it was not printed as", not illusion("grunt"))
		zones.add(entity.get(zones.find_id("ongoing")), "dreamer")
		check("the cheap unit is lent the word", illusion("grunt"))
		check("the dear one is not", not illusion("titan"))
		check("and the panel says so", (cards.keywords(find("grunt"))[1] or {}).granted == true)
	end)
end

function M.test_lends_a_lent_word_carries_what_the_tag_does(check)
	with_game(function(name)
		dream(name)
		flow.play_card(find("bolt").id, { find("grunt").id })
		check("aimed at, the dreamt unit dies", zone_of("grunt") == "discard", zone_of("grunt"))
		check("of the aim and not the damage", find("grunt").stats.hp == 3, tostring(find("grunt").stats.hp))
	end)
end

function M.test_lends_the_word_goes_with_the_lender(check)
	with_game(function(name)
		dream(name)
		flow.play_card(find("wake").id)
		check("the lender has left play", zone_of("dreamer") == "discard", zone_of("dreamer"))
		check("and the unit is plain again", not illusion("grunt"))
	end)
end

function M.test_lends_a_given_word_is_worn_until_taken_back(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("haze").id, { find("titan").id, find("grunt").id })
		check("the dear one is given the word", illusion("titan"))
		flow.play_card(find("dawn").id)
		check("untag takes it back", not illusion("titan") and not illusion("grunt"))
		check("and leaves the printed one alone", illusion("mirror"))
	end)
end

function M.test_lends_a_given_word_outlasts_a_lent_one(check)
	with_game(function(name)
		dream(name)
		flow.play_card(find("haze").id, { find("grunt").id })
		flow.play_card(find("wake").id)
		check("hallucinated under Dreamscape, it stays an Illusion once Dreamscape goes", illusion("grunt"))
	end)
end

function M.test_lends_a_given_word_is_forgotten_out_of_play(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("haze").id, { find("titan").id })
		flow.play_card(find("recall").id, { find("titan").id })
		check("bounced to hand", zone_of("titan") == "hand", zone_of("titan"))
		check("it is a plain unit again", not illusion("titan"))
	end)
end

return M
