-- What a card does when it is played, said once for all the cards that do it.
--
-- A tag has always been a card mixin, and it has always been able to carry an
-- `activate` — but a `play` on one only ever reached the cards a *zone* handed
-- it to, through `applies`. So ninety Splendor development cards each carried
-- their own copy of the same twenty-seven actions, and a game that wrote the
-- obvious thing instead got a card that was offered, played, and did nothing.
--
-- Now the loader copies it onto every card wearing the tag. Whole block or
-- none, the card's own wins outright, and two tags granting it is refused
-- rather than resolved.

local entity   = require("entity")
local zones    = require("zones")
local flow     = require("flow")
local cards    = require("cards")
local declaration = require("declaration")
local validate = require("validate")

local M = {}

-- One hand, one table, and four cards that reach it by different routes.
local GAME = [==[{
  "title": "Tag Play",
  "players": [{ "card": "one" }],
  "stats": [{ "key": "purse", "min": 0, "max": 99, "tags": ["hidden"] }],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat", "pos": [[0.02, 0.80, 0.60, 0.95]] },
    { "key": "table", "layout": "grid", "grid": [6, 1], "pos": [0.02, 0.30, 0.98, 0.50] },
    { "key": "sold", "layout": "grid", "grid": [2, 1], "pos": [0.02, 0.55, 0.40, 0.70] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "tags": {
    "goes":   { "play": { "action": ["stat_gain:purse@mine.player:1", "move_to:table"] } },
    "priced": { "play": { "cost": { "purse@mine.player": 2 }, "action": ["move_to:sold"] } },
    "gated":  { "play": { "needs": ["purse@mine.player >= 5"], "action": ["move_to:table"] } },
    "elsewhere": { "play": { "action": ["move_to:sold"] } }
  },
  "cards": [
    { "key": "one",   "text": "One", "card_stats": { "purse": 3 } },
    { "key": "plain", "text": "Plain", "tags": ["goes"] },
    { "key": "own",   "text": "Own",   "tags": ["goes"],
      "play": { "action": ["move_to:sold"] } },
    { "key": "buy",   "text": "Buy",   "tags": ["priced"] },
    { "key": "shut",  "text": "Shut",  "tags": ["gated"] },
    { "key": "both",  "text": "Both",  "tags": ["goes", "elsewhere"] }
  ],
  "setup": {
    "place": [
      { "card": "plain", "zone": "hand" }, { "card": "own", "zone": "hand" },
      { "card": "buy", "zone": "hand" }, { "card": "shut", "zone": "hand" },
      { "card": "both", "zone": "hand" }
    ]
  }
}]==]

local function with_game(text, fn)
	local path = "game/games/tmp_tag_play.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_tag_play.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function in_zone(key, def_key)
	for _, cid in ipairs((zones.find(key) or {}).cards or {}) do
		local c = entity.get(cid)
		if c.def_key == def_key then return c end
	end
end

local function seat()
	for e in entity.each("card") do if e.def_key == "one" then return e end end
end

-- The whole point: a card that says nothing about being played does what its
-- tag says, and the actions run for real rather than being merely present.
function M.test_tag_play_a_tag_hands_its_cards_the_moment(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local c = in_zone("hand", "plain")
		check("the card has a play it never wrote",
			cards.behaviour(c, "on_play") ~= nil)
		check("and it is playable", flow.can_play(c.id))
		flow.play_card(c.id, {})
		check("it went where the tag sends it", in_zone("table", "plain") ~= nil)
		check("and the tag's actions ran", seat().stats.purse == 4, tostring(seat().stats.purse))
	end)
end

-- Cost and needs come with it. This is the half that would fail silently if
-- only the action were copied: the card would be offered for free and the gate
-- would never close.
function M.test_tag_play_brings_its_cost_and_its_gate(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local buy = in_zone("hand", "buy")
		check("a purse of three affords a cost of two", flow.can_play(buy.id))
		seat().stats.purse = 1
		check("a purse of one does not", not flow.can_play(buy.id))
		seat().stats.purse = 3
		flow.play_card(buy.id, {})
		check("paying it moved the card", in_zone("sold", "buy") ~= nil)
		check("and took the two", seat().stats.purse == 1, tostring(seat().stats.purse))
	end)
end

-- `needs` from a tag gates as a card's own would. The escape hatch is what
-- makes this worth asserting separately: with other cards playable, a gated
-- card stays gated.
function M.test_tag_play_a_gate_from_a_tag_closes(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		check("five is more than three", not flow.can_play(in_zone("hand", "shut").id))
		seat().stats.purse = 5
		check("and it opens when the number is met", flow.can_play(in_zone("hand", "shut").id))
	end)
end

-- A card's own block wins, and wins *whole*: the tag's action does not run
-- underneath it, which is what "half a moment" would have meant.
function M.test_tag_play_a_cards_own_block_wins_outright(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local before = seat().stats.purse
		flow.play_card(in_zone("hand", "own").id, {})
		check("it did its own thing", in_zone("sold", "own") ~= nil)
		check("and not the tag's", in_zone("table", "own") == nil)
		check("so nothing was gained", seat().stats.purse == before, tostring(seat().stats.purse))
	end)
end

-- Two tags is no answer. An ambiguous home is no home, and the same holds
-- here: whichever won would be the order somebody typed the tags.
function M.test_tag_play_two_tags_granting_it_is_refused(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local both = in_zone("hand", "both")
		check("the card took neither", cards.behaviour(both, "on_play") == nil)
		local said
		for _, p in ipairs(validate.check(declaration.G)) do
			if p:match("both") and p:match("goes") and p:match("elsewhere") then said = p end
		end
		check("and the validator names both tags", said ~= nil, said or "(nothing said)")
	end)
end

-- The zone route is untouched. `applies` is looked up where the card lies, and
-- it still answers before the card's own def — that is what makes an offer
-- work, and it is a different question from what a card's own tags say.
function M.test_tag_play_a_zone_still_speaks_first(check)
	local text = GAME
		:gsub('"key": "sold", "layout": "grid", "grid": %[2, 1%]',
			'"key": "sold", "layout": "grid", "grid": [2, 1], "applies": ["shove"]')
		:gsub('"elsewhere": { "play"', '"shove": { "play": { "action": ["move_to:table"] } },\n    "elsewhere": { "play"')
	with_game(text, function(name)
		flow.init(name, 3)
		flow.play_card(in_zone("hand", "own").id, {})
		local c = in_zone("sold", "own")
		check("the card is lying in the zone that grants one", c ~= nil)
		check("and there its zone answers, not its own def",
			cards.behaviour(c, "on_play")[1] == "move_to:table")
	end)
end

return M
