-- "@<zone tag>.<tag>" — a place half that names what several zones have in
-- common, rather than one zone by its key.
--
-- Spellstorm is why. "An ICE of mine, wherever I am keeping it" is my hand or my
-- discard and not my deck, and a scope could name one zone — so the game said it
-- on the cards instead: a tag handed out by each of the two zones, a union to or
-- them together, an `and` to put the real question back, and then `everywhere`
-- walked, which is every card entity in the game. Five of its eight computed
-- tags were that last step. Which places count is the zone's own business.

local zones = require("zones")
local flow = require("flow")
local actions = require("actions")
local predicate = require("predicate")
local targeting = require("targeting")
local entity = require("entity")

local M = {}

local GAME = [==[{
  "title": "Zone Word Scope",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "score", "label": "Score", "subject": "score@mine.player" }],
  "styles": { "plate": { "fit": "card" } },
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "tags": ["open"], "pos": [0.05, 0.05, 0.9, 0.2] },
    { "key": "bench", "layout": "row", "use": "abilities",
      "tags": ["open"], "pos": [0.05, 0.26, 0.9, 0.1] },
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "tags": ["held", "plate"], "pos": [[0.05, 0.4, 0.9, 0.12], [0.05, 0.54, 0.9, 0.12]] },
    { "key": "discard", "layout": "stack", "copies": "per_seat", "status": "grave",
      "tags": ["held"], "pos": [[0.05, 0.68, 0.12, 0.14], [0.2, 0.68, 0.12, 0.14]] },
    { "key": "deck", "layout": "stack", "copies": "per_seat", "visibility": "secret",
      "pos": [[0.4, 0.68, 0.12, 0.14], [0.55, 0.68, 0.12, 0.14]] }
  ],
  "phases": [
    { "key": "deal", "type": "automatic",
      "actions": ["set_active_seat:seat_one",
                  "create:mine.hand:ruby:1", "create:mine.hand:brick:1", "create:mine.hand:wand:1",
                  "create:mine.discard:ruby:1", "create:mine.deck:ruby:1",
                  "set_active_seat:seat_two",
                  "create:mine.hand:ruby:1", "create:mine.deck:ruby:1",
                  "set_active_seat:seat_one"],
      "next": [{ "then": "act" }] },
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "score": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "score": 0 } },
    { "key": "ruby", "text": "Ruby", "tags": ["thing", "gem"], "card_stats": { "value": 3 } },
    { "key": "brick", "text": "Brick", "tags": ["thing", "junk"], "card_stats": { "value": 0 } },
    { "key": "wand", "text": "Wand", "tags": ["thing", "tool"],
      "play": { "phases": ["act"],
                "target": { "type": "card", "count": 1, "owner": "mine",
                            "tags": ["gem"], "zones": ["held"] },
                "action": ["purge:target"] } }
  ],
  "setup": {
    "place": [
      { "card": "brick", "zone": "board", "at": ["a1"] },
      { "card": "ruby", "zone": "bench" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_zone_word_scope.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_zone_word_scope.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function total(s) return predicate.total(s, {}) end

-- The whole of it: one word for two places, and not for the third.
function M.test_zone_word_scope_names_every_zone_wearing_it(check)
	with_game(function(name)
		flow.init(name, 3)
		check("my hand and my discard, added", total("count:gem@mine.held") == 2,
			tostring(total("count:gem@mine.held")))
		check("and my deck is not one of them", total("count:gem@mine.deck") == 1,
			tostring(total("count:gem@mine.deck")))
		check("which is what the word buys: the deck is excluded, not counted",
			total("count:gem@mine.held") ~= total("count:gem@mine.everywhere"),
			total("count:gem@mine.held") .. " / " .. total("count:gem@mine.everywhere"))
		check("a measure reads the union", total("sum:value@mine.held.gem") == 6,
			tostring(total("sum:value@mine.held.gem")))
	end)
end

-- Whose, where, which — the same three narrowings in the same order, with only
-- the middle word made wider.
function M.test_zone_word_scope_stacks_with_the_owner_word(check)
	with_game(function(name)
		flow.init(name, 3)
		check("mine", total("count:gem@mine.held") == 2)
		check("theirs", total("count:gem@enemy.held") == 1,
			tostring(total("count:gem@enemy.held")))
		check("either", total("count:gem@anyone.held") == 3,
			tostring(total("count:gem@anyone.held")))
		check("and the tag still narrows", total("count:junk@mine.held") == 1,
			tostring(total("count:junk@mine.held")))
	end)
end

-- A shared zone has no seat, so a word over two of them is one pool and the
-- owner word has nothing to divide.
function M.test_zone_word_scope_over_shared_zones(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the board and the bench are both open", total("count:thing@open") == 2,
			tostring(total("count:thing@open")))
		check("and the tag picks one of them out", total("count:gem@open") == 1,
			tostring(total("count:gem@open")))
	end)
end

-- The key is the narrower reading and wins. The validator refuses a word that is
-- both so nobody has to know that, but the runtime must not be the thing that
-- decides it.
function M.test_zone_word_scope_a_zone_key_wins_over_a_zone_tag(check)
	with_game(function(name)
		flow.init(name, 3)
		local by_key = zones.all_named("hand")
		check("one key, one place per seat", #by_key == 2, tostring(#by_key))
		for _, z in ipairs(by_key) do
			check("and every one of them is that zone", z.key == "hand", tostring(z.key))
		end
	end)
end

-- A style is a look. A zone and its cards are routinely given the one they
-- share, and reading that as a set of places would answer a line nobody wrote.
function M.test_zone_word_scope_a_style_is_not_a_place(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the hand wears the style", total("count:gem@mine.hand") == 1,
			tostring(total("count:gem@mine.hand")))
		check("and the style names no place at all", #zones.all_named("plate") == 0,
			tostring(#zones.all_named("plate")))
	end)
end

-- One scope grammar, so an action takes it where a measure does.
function M.test_zone_word_scope_works_where_an_action_names_a_scope(check)
	with_game(function(name)
		flow.init(name, 3)
		actions.run({ "purge:mine.held.gem" }, {})
		check("both of mine went", total("count:gem@mine.held") == 0,
			tostring(total("count:gem@mine.held")))
		check("my junk stayed", total("count:junk@mine.held") == 1)
		check("my deck was never in scope", total("count:gem@mine.deck") == 1)
		check("and theirs is untouched", total("count:gem@enemy.held") == 1)
	end)
end

-- The other half of the word: a target spec's "zones" reads it too, because
-- "which places count" is one question however it is asked.
function M.test_zone_word_scope_a_target_spec_names_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local wand
		for e in entity.each("card") do if e.def_key == "wand" then wand = e end end
		local spec = require("cards").def(wand).play.target
		local ids = targeting.candidates(wand.id, spec)
		check("my gems in hand and in discard, and nothing else", #ids == 2, tostring(#ids))
		local places = {}
		for _, id in ipairs(ids) do
			local e = entity.get(id)
			places[entity.get(e.zone_id).key] = true
		end
		check("one from each place", places.hand and places.discard,
			tostring(places.hand) .. " / " .. tostring(places.discard))
		check("and the deck was not offered", not places.deck)
	end)
end

return M
