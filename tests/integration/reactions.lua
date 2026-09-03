-- "reactions" — a card's subscriptions to another player's action. The schema
-- and Filter A: a reaction names the verb it answers ("to"), the engine indexes
-- every reaction by that verb once at load, and a verb no card answers opens no
-- window. The window itself is built on top of this; here we only prove the
-- surface is accepted, checked, and indexed.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local declaration = require("declaration")
local validate = require("validate")
local cards = require("cards")
local geometry = require("geometry")

local M = {}

local GAME = [==[{
  "title": "Reactions",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "mana", "label": "Mana", "subject": "mana@mine.player" }],
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.05, 0.40, 0.95, 0.60] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "board", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "mana": 3 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "mana": 3 } },
    { "key": "fireball", "text": "Fireball", "tags": ["spell", "fireball"] },
    { "key": "flame_counter", "text": "Flame Counter", "tags": ["spell"],
      "reactions": [
        { "to": "play",
          "where": ["tagged:fireball@event"],
          "when": ["mana@mine.player >= 1"],
          "cost": { "mana@mine.player": 1 },
          "action": ["destroy:event"] }
      ] }
  ],
  "setup": {
    "place": [
      { "card": "flame_counter", "owner": "two", "zone": "board", "at": ["a1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_reactions.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_reactions.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function at(name)
	local slot = entity.get(geometry.slot_named(zones.find("board"), name))
	return slot and slot.occupant and entity.get(slot.occupant)
end

local function has(list, needle)
	for _, p in ipairs(list) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

-- A well-formed reaction is accepted, indexed by the verb it answers, and reads
-- back off the card that carries it.
function M.test_reactions_are_accepted_and_indexed(check)
	with_game(function(name)
		flow.init(name, 3)
		check("nothing about the reaction is a problem",
			not has(validate.check(declaration.G), "reaction"),
			table.concat(validate.check(declaration.G), "; "))

		local by_card = declaration.G.react_index["play"]
		local hits = by_card and by_card["flame_counter"]
		check("the verb it answers is indexed", by_card ~= nil and hits ~= nil)
		check("and the index points back into the card's own list",
			hits and #hits == 1 and hits[1].index == 1, hits and #hits)
		check("a verb nothing answers is not in the index",
			declaration.G.react_index["summon"] == nil)

		local rs = cards.reactions(at("a1"))
		check("the card reads back its own reaction", #rs == 1, #rs)
		check("its verb survived", rs[1] and rs[1].to == "play", rs[1] and rs[1].to)
		check("and it defaults to optional when unwritten",
			rs[1] and rs[1].forced == "optional", rs[1] and rs[1].forced)
	end)
end

-- The structural mistakes are caught at parse, the last moment the authored
-- entry exists — the same as a typo inside an ability.
function M.test_reactions_structural_mistakes_are_caught(check)
	local path = "game/games/tmp_bad_reactions.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
		"title": "Bad Reactions",
		"zones": [{ "key": "board", "layout": "grid", "use": "abilities", "grid": [2, 2] }],
		"phases": [{ "key": "turn", "type": "player_input" }],
		"cards": [{ "key": "thing", "text": "Thing", "reactions": [
			{ "where": ["hp@self >= 1"] },
			{ "to": "play", "forced": "maybe" },
			{ "to": "play", "whose": "somebody" },
			{ "to": "play", "wat": 1 }
		] }]
	}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_bad_reactions.json")
	os.remove(path)
	if not ok then error(G, 2) end
	local said = validate.check(G)
	check("a reaction with no verb is refused",
		has(said, 'reaction 1 has no "to"'), table.concat(said, "; "))
	check("a \"forced\" that is neither word is refused",
		has(said, 'forced "maybe" is neither'), table.concat(said, "; "))
	check("a \"whose\" that is none of the three words is refused",
		has(said, 'whose "somebody" is none of'), table.concat(said, "; "))
	check("a field the engine does not read is refused",
		has(said, "reaction 4: has a field 'wat'"), table.concat(said, "; "))
end

return M
