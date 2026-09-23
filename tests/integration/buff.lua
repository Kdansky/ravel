-- A tag that shifts a stat, and never writes it down.
--
-- Every continuous effect in every card game is the same sentence: while this
-- is true, that number is different. Written as an action it is two sentences —
-- one that adds and one that takes away — and the second has to be repeated on
-- every path the first can be undone by. Codex kept a hidden "elited" stat for
-- no other reason, and undid it in ten places, because a unit can leave the
-- elite post ten ways.
--
-- So a buff is a *read*. Nothing happens when the tag arrives; the card simply
-- reads higher for as long as it wears it, and the printed number underneath is
-- never touched and so can never get out of step.

local entity    = require("entity")
local zones     = require("zones")
local flow      = require("flow")
local cards     = require("cards")
local actions   = require("actions")
local predicate = require("predicate")
local tags      = require("tags")
local net       = require("net")
local stats     = require("stats")

local M = {}

local GAME = [==[{
  "title": "Buffs",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "gold", "min": 0, "max": 99, "subject": "gold@mine.player" },
    { "key": "atk", "on": ["unit"], "start": 1, "min": 0 },
    { "key": "hp", "on": ["unit"], "start": 1, "min": 0, "max": 1 },
    { "key": "price", "on": ["wares"], "start": 2, "min": 0 },
    { "key": "wounds", "on": ["unit"], "start": 0, "min": 0 }
  ],
  "computed_tags": {
    "dead": { "needs": ["hp@self < 1"] },
    "hurt": { "needs": ["wounds@self >= 1"] }
  },
  "tags": {
    "elite": { "buffs": { "atk": 1 } },
    "raging": { "buffs": { "atk": 3, "hp": 1 } },
    "hurt": { "buffs": { "atk": 2 } },
    "marked_up": { "buffs": { "price": 5 } }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] },
    { "key": "ring", "status": "board", "layout": "row", "applies": ["raging"], "pos": [0.60, 0.40, 0.90, 0.55] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "card_stats": { "gold": 10 } },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "champ", "text": "Champ", "tags": ["unit", "elite"] },
    { "key": "trinket", "text": "Trinket", "tags": ["wares"],
      "play": { "cost": { "gold@mine.player": "price@self" }, "action": ["move_to:field"] } },
    { "key": "relic", "text": "Relic", "tags": ["wares", "marked_up"],
      "play": { "cost": { "gold@mine.player": "price@self" }, "action": ["move_to:field"] } }
  ],
  "setup": {
    "place": [
      { "card": "grunt", "zone": "field" },
      { "card": "champ", "zone": "field" },
      { "card": "trinket", "zone": "hand" },
      { "card": "relic", "zone": "hand" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_buff.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_buff.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

-- A printed keyword. The commonest buff there is, and the one that needs no
-- machinery at all beyond reading through the tag.
function M.test_buff_a_printed_tag_shifts_the_stat(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the plain unit reads its printed attack", predicate.total("atk@each.unit") == 3,
			predicate.total("atk@each.unit"))
		check("the elite one reads one higher", stats.current(find("champ"), "atk") == 2,
			stats.current(find("champ"), "atk"))
		check("and the number on the card never moved", find("champ").stats.atk == 1,
			find("champ").stats.atk)
	end)
end

-- Where a card *stands* can shift it, which is the whole of "gets +3 while in
-- the arena" — and the shift ends the instant it leaves, with nothing to undo.
function M.test_buff_a_zone_grants_and_takes_it_back(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt")
		check("on the field it is a 1", stats.current(g, "atk") == 1)
		zones.move_card(g.id, zones.find_id("ring"))
		check("in the ring it is a 4", stats.current(g, "atk") == 4, stats.current(g, "atk"))
		zones.move_card(g.id, zones.find_id("field"))
		check("and back on the field a 1 again", stats.current(g, "atk") == 1, stats.current(g, "atk"))
		check("with nothing left on the card", g.stats.atk == 1, g.stats.atk)
	end)
end

-- **The ceiling rises with the value.** Without this a 1/1 handed +1 hp would
-- be clamped straight back to 1 and the buff would be worth nothing.
function M.test_buff_lifts_the_ceiling_with_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt")
		zones.move_card(g.id, zones.find_id("ring"))
		check("it is a 2 of 2", stats.current(g, "hp") == 2 and stats.ceiling(g, "hp") == 2,
			stats.current(g, "hp") .. "/" .. tostring(stats.ceiling(g, "hp")))
		actions.execute("stat_gain:hp@self:5", { card_id = g.id })
		check("healing clamps at the lifted ceiling, not the printed one",
			stats.current(g, "hp") == 2, stats.current(g, "hp"))
	end)
end

-- Damage comes off what the card *is*, so a buffed 1/1 dies to two and not to
-- one. This is the half that a read-only buff would get wrong.
function M.test_buff_damage_comes_off_the_buffed_total(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt")
		zones.move_card(g.id, zones.find_id("ring"))
		actions.execute("stat_damage:hp@self:2", { card_id = g.id })
		check("two damage kills a buffed 1/1", tags.entity_has(g, "dead"), stats.current(g, "hp"))
	end)
end

-- And the damage is remembered when the buff goes. A 1/1 given +1, hurt once,
-- and then dropped back to its printed size is a 1/1 with a wound on it — which
-- is dead, and is what the physical card would be.
function M.test_buff_leaving_remembers_what_was_taken(check)
	with_game(function(name)
		flow.init(name, 3)
		local g = find("grunt")
		zones.move_card(g.id, zones.find_id("ring"))
		actions.execute("stat_damage:hp@self:1", { card_id = g.id })
		check("in the ring it is still standing", not tags.entity_has(g, "dead"), stats.current(g, "hp"))
		zones.move_card(g.id, zones.find_id("field"))
		check("out of it, the wound is all that is left", stats.current(g, "hp") == 0, stats.current(g, "hp"))
		check("so it is dead", tags.entity_has(g, "dead"))
	end)
end

-- A computed tag may buff, which is how "wounded animals hit harder" is said.
-- It is not behaviour and there is no card for the behaviour version to belong
-- to, so the rule that keeps the two apart makes an exception for this one word.
function M.test_buff_a_computed_tag_may_carry_one(check)
	with_game(function(name)
		flow.init(name, 3)
		local c = find("champ")
		check("unhurt, the elite is a 2", stats.current(c, "atk") == 2, stats.current(c, "atk"))
		actions.execute("stat_gain:wounds@self:1", { card_id = c.id })
		check("hurt, it is a 4", stats.current(c, "atk") == 4, stats.current(c, "atk"))
		check("having never been written to", c.stats.atk == 1, c.stats.atk)
	end)
end

-- A cost is measured through the same read as everything else, so a price with
-- a tag on it is simply dearer. Nothing in the cost machinery learned a word.
function M.test_buff_a_cost_is_paid_at_the_buffed_price(check)
	with_game(function(name)
		flow.init(name, 3)
		local pl = find("one")
		check("the plain one is priced at 2", predicate.total("price@self", { card_id = find("trinket").id }) == 2)
		check("the marked-up one at 7", predicate.total("price@self", { card_id = find("relic").id }) == 7,
			predicate.total("price@self", { card_id = find("relic").id }))
		flow.play_card(find("relic").id)
		check("and paying it takes seven gold", pl.stats.gold == 3, pl.stats.gold)
	end)
end

-- A write addresses the card's own number and a buff is not the card's to set.
-- Codex levels a hero to "attack 2" with a stat_set, and a hero standing in the
-- elite post has to come out of that a 3 — the level-up has never heard of the
-- post and must not be able to eat what it granted.
function M.test_buff_a_write_addresses_the_printed_number(check)
	with_game(function(name)
		flow.init(name, 3)
		local c = find("champ")
		actions.execute("stat_set:atk@self:5", { card_id = c.id })
		check("the card is printed at five", c.stats.atk == 5, c.stats.atk)
		check("and reads six, the buff untouched", stats.current(c, "atk") == 6, stats.current(c, "atk"))
	end)
end

-- Nothing extra crosses the wire. The shift is derived from the tag, and the
-- tag is derived from the card and the zone, both of which already travel.
function M.test_buff_survives_a_round_trip(check)
	with_game(function(name)
		flow.init(name, 3)
		zones.move_card(find("grunt").id, zones.find_id("ring"))
		local snap = net.snapshot()
		flow.init(name, 3)
		check("a fresh game has the plain unit", stats.current(find("grunt"), "atk") == 1)
		net.apply_full(snap)
		check("and the restored one is still raging", stats.current(find("grunt"), "atk") == 4,
			stats.current(find("grunt"), "atk"))
	end)
end

-- A read is a read, whichever door it comes through. Four places in the engine
-- reached past stats.current into e.stats and so answered about the number *stored*
-- rather than the number the card has: a condition quantified over "each", the
-- hp gate on a round action, the winner check, and the ceiling the inspector
-- prints. Pinned here rather than at each of the four, because what is true is
-- the rule and not the call sites.
function M.test_buff_a_condition_over_each_reads_the_buffed_number(check)
	with_game(function(name)
		flow.init(name, 3)
		-- Champ is a printed 1 attack wearing +1, so the two readings differ and
		-- the comparison can only be answering one of them.
		check("asked one at a time, every unit is at least its buffed attack",
			predicate.meets_all({ "atk@each.unit >= 1" }, {}))
		check("and the elite one is over the printed number it stores",
			predicate.meets_all({ "atk@each.unit <= 1" }, {}) == false)
		check("which is what the pooled spelling says about the same board",
			predicate.meets_all({ "max:atk@each.unit <= 1" }, {}) == false)

		-- The same word, aimed rather than scoped: a bare @target parses as
		-- "each", which is how this got past everything for so long.
		local champ = find("champ")
		check("a target subject agrees with a scoped one",
			predicate.meets_all({ "atk@target <= 1" }, { targets = { champ.id } }) == false)
		check("and still answers yes where it should",
			predicate.meets_all({ "atk@target <= 2" }, { targets = { champ.id } }))
	end)
end

-- A ceiling rises with the value it bounds, so the panel a player checks a
-- number in must not print 2/1 for a card standing on a borrowed point.
function M.test_buff_the_ceiling_the_panel_prints_rises_too(check)
	with_game(function(name)
		flow.init(name, 3)
		local ring = zones.find("ring")
		local grunt = find("grunt")
		check("a plain unit is at its printed one", stats.current(grunt, "hp") == 1
			and stats.ceiling(grunt, "hp") == 1)
		zones.move_card(grunt.id, ring.id)
		check("in the ring it holds two", stats.current(grunt, "hp") == 2,
			stats.current(grunt, "hp"))
		check("and the ceiling went with it, so nothing reads over its own maximum",
			stats.ceiling(grunt, "hp") == 2, stats.ceiling(grunt, "hp"))
		check("while the number stored is untouched", grunt.stats.hp == 1, grunt.stats.hp)
	end)
end

return M
