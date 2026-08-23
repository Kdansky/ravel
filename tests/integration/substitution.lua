-- "A plain arrow can be spent as a red one."
--
-- A cost is one map of what is owed. That some other pool will settle part of
-- it is a fact about *that pool*, said once on the stat with `pays_for`, rather
-- than a list of ways to pay copied onto every card that might be paid for.
--
-- Which pool settles which part is then a matching, and the engine solves it
-- with a greedy: the most constrained demand first, and a demand's own stat
-- before any substitute. Magic's "four generic and three red" is the case that
-- needs both halves — a pool of three red and two blue pays it, and spending
-- the red on the generic loses a cost that was payable.

local entity  = require("entity")
local zones   = require("zones")
local flow    = require("flow")
local actions = require("actions")

local M = {}

-- Five mana pools and a "generic" nobody ever holds: every colour pays for it,
-- which is exactly what generic mana means.
local GAME = [==[{
  "title": "Substitution",
  "players": [{ "card": "wizard" }],
  "stats": [
    { "key": "generic", "label": "Generic", "on": ["player"], "start": 0 },
    { "key": "red",   "label": "Red",   "on": ["player"], "start": 0, "pays_for": ["generic"] },
    { "key": "blue",  "label": "Blue",  "on": ["player"], "start": 0, "pays_for": ["generic"] },
    { "key": "gold",  "label": "Gold",  "on": ["player"], "start": 0, "pays_for": ["generic", "red", "blue"] }
  ],
  "zones": [
    { "key": "hand", "type": "hand", "pos": [0.25, 0.7, 0.95, 0.95] },
    { "key": "table", "type": "hand", "pos": [0.25, 0.4, 0.95, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "wizard", "text": "Wizard" },
    { "key": "bolt", "text": "Bolt", "tags": ["spell"],
      "play": { "cost": { "generic@mine.player": 4, "red@mine.player": 3 },
                "action": ["move_to:table"] } },
    { "key": "cantrip", "text": "Cantrip", "tags": ["spell"],
      "play": { "cost": { "red@mine.player": 1 }, "action": ["move_to:table"] } }
  ],
  "setup": { "place": [{ "card": "bolt", "zone": "hand" }, { "card": "cantrip", "zone": "hand" }] }
}]==]

local PATH, FILE = "game/games/tmp_substitution.json", "tmp_substitution.json"

local function with_game(fn)
	local f = assert(io.open(PATH, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, FILE)
	os.remove(PATH)
	if not ok then error(err, 0) end
end

local function wizard()
	for e in entity.each("card") do if e.def_key == "wizard" then return e end end
end

local function card(key)
	for e in entity.each("card") do if e.def_key == key and e.zone_id then return e end end
end

local function purse(red, blue, gold)
	local w = wizard()
	w.stats.red, w.stats.blue, w.stats.gold, w.stats.generic = red, blue, gold, 0
end

-- The allocation Magic's own rules require, and the one a naive walk gets wrong.
function M.test_substitution_the_constrained_half_is_paid_first(check)
	with_game(function(name)
		flow.init(name, 1)
		local bolt = card("bolt")

		purse(3, 4, 0)
		check("three red and four blue pays four generic and three red",
			flow.can_afford({ ["generic@mine.player"] = 4, ["red@mine.player"] = 3 }, {}))
		flow.play_card(bolt.id, {})
		local w = wizard()
		check("the red went on the red half", w.stats.red == 0, tostring(w.stats.red))
		check("and the four blue on the generic", w.stats.blue == 0, tostring(w.stats.blue))
	end)
end

function M.test_substitution_a_pool_one_short_cannot_pay(check)
	with_game(function(name)
		flow.init(name, 1)
		purse(2, 5, 0)
		check("seven mana but only two red is not three red",
			flow.can_afford({ ["generic@mine.player"] = 4, ["red@mine.player"] = 3 }, {}) == false)
		purse(3, 1, 0)
		check("and four mana is not seven",
			flow.can_afford({ ["generic@mine.player"] = 4, ["red@mine.player"] = 3 }, {}) == false)
	end)
end

-- The restricted pool goes first because the substitute is worth more
-- elsewhere. Nothing on the card says so.
function M.test_substitution_the_narrow_pool_is_spent_before_the_wild(check)
	with_game(function(name)
		flow.init(name, 1)
		purse(1, 0, 1)
		flow.play_card(card("cantrip").id, {})
		local w = wizard()
		check("the red paid, not the gold", w.stats.red == 0 and w.stats.gold == 1,
			w.stats.red .. "/" .. w.stats.gold)
	end)
end

function M.test_substitution_a_wild_pays_when_the_narrow_one_is_empty(check)
	with_game(function(name)
		flow.init(name, 1)
		purse(0, 0, 1)
		check("gold can be spent as red", flow.can_afford({ ["red@mine.player"] = 1 }, {}))
		flow.play_card(card("cantrip").id, {})
		check("and it was", wizard().stats.gold == 0)
	end)
end

return M
