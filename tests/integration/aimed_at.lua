-- `receive`'s write half: what a card does about having been pointed at.
--
-- The read half, `accepts`, has been asked of every candidate since the aim had
-- a name -- "cannot be targeted by spells" is one line on the card that has it.
-- What had no spelling was the other half: Codex's Illusions *die* of being
-- targeted, and an aim had no answering moment, so ten blue cards said NOT
-- MODELLED. A zone has had both halves since it had either; this is a card and
-- a tag getting the same.
--
-- Two things fall out of it that are worth their own tests. The first is the
-- blind spot the read half already has and the write half inherits: `accepts` is
-- asked when a player *points* and never when a scope names, which is why
-- hexproof stops a bolt and not a board wipe -- and why an Illusion survives one
-- too. The second is what happens to the spell: a card that dies of being
-- targeted is in its grave before the spell resolves, and `destroy` is a move
-- rather than a removal, so without a rule the spell follows the corpse into the
-- discard and bounces it to hand. The rule is that a target whose zone *status*
-- changed is no longer what was pointed at. Status and not zone, because Codex's
-- combat is army -> duel and home again and both are the board: a defender that
-- moves is still the thing the bolt was thrown at.

local entity = require("entity")
local flow   = require("flow")
local zones  = require("zones")
local cards  = require("cards")
local actions = require("actions")

local M = {}

local GAME = [==[{
  "title": "Aimed at",
  "players": [{ "card": "one" }],
  "stats": [
    { "key": "hp", "on": ["unit"], "start": 3, "min": 0, "max": 3 },
    { "key": "faith", "on": ["player"], "start": 0, "min": 0, "max": 99 }
  ],
  "verbs": [
    { "key": "cast",   "does": "target", "tooltip": "A spell picking what it lands on." },
    { "key": "attack", "does": "target", "tooltip": "One fighter throwing itself at another." }
  ],
  "computed_tags": {
    "fragile": { "needs": ["tagged:illusion@self", "count:ward_aura@field == 0"] }
  },
  "tags": {
    "illusion": { "tooltip": "Illusion — dies when a spell or an ability aims at it." },
    "fragile":  { "receive": { "when": ["verb:cast"], "action": ["destroy:self"] } }
  },
  "zones": [
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] },
    { "key": "duel", "status": "board", "layout": "row", "pos": [0.20, 0.20, 0.50, 0.35] },
    { "key": "shrine", "status": "board", "layout": "row", "pos": [0.60, 0.40, 0.75, 0.55],
      "receive": { "when": ["tagged:unit@target"], "action": ["stat_gain:faith@mine.player:1"] } },
    { "key": "discard", "status": "grave", "layout": "stack", "pos": [0.60, 0.80, 0.70, 0.95] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "mirror", "text": "Mirror", "tags": ["unit", "illusion"] },
    { "key": "guard", "text": "Guard", "tags": ["unit"],
      "receive": { "action": ["stat_damage:hp@self:1"] } },
    { "key": "warden", "text": "Warden", "tags": ["unit", "ward_aura"] },
    { "key": "bolt", "text": "Bolt", "tags": ["spell"],
      "play": { "target": { "verb": "cast", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } },
    { "key": "charge", "text": "Charge", "tags": ["spell"],
      "play": { "target": { "verb": "attack", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } },
    { "key": "bounce", "text": "Bounce", "tags": ["spell"],
      "play": { "target": { "verb": "cast", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["move:target:hand"] } },
    { "key": "wave", "text": "Wave", "tags": ["spell"],
      "play": { "action": ["stat_damage:hp@each.unit:1"] } }
  ],
  "setup": {
    "place": [
      { "card": "grunt", "zone": "field" }, { "card": "mirror", "zone": "field" },
      { "card": "guard", "zone": "field" },
      { "card": "bolt", "zone": "hand" }, { "card": "bounce", "zone": "hand" },
      { "card": "wave", "zone": "hand" }, { "card": "charge", "zone": "hand" }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_aimed_at.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_aimed_at.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function find(key)
	for e in entity.each("card") do if e.def_key == key then return e end end
end

local function zone_of(key)
	local c = find(key)
	local z = c and c.zone_id and entity.get(c.zone_id)
	return z and z.key or "gone"
end

-- The whole customer, in one test. Pointing at the Illusion is what kills it,
-- and the spell that pointed lands on nothing.
function M.test_aimed_an_illusion_dies_of_being_pointed_at(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("bolt").id, { find("mirror").id })
		check("the illusion is in the discard", zone_of("mirror") == "discard", zone_of("mirror"))
		check("and it died of the aim, not of the damage",
			find("mirror").stats.hp == 3, tostring(find("mirror").stats.hp))
	end)
end

-- The trap this word would have shipped with. `destroy` is a move into the
-- grave and not a removal, so the corpse is still an entity and "@target" still
-- finds it: a bounce would haul the dead Illusion back out of the discard and
-- into the hand.
function M.test_aimed_the_spell_does_not_follow_the_corpse(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("bounce").id, { find("mirror").id })
		check("the illusion died", zone_of("mirror") == "discard", zone_of("mirror"))
		check("and the bounce did not pull it back", zone_of("mirror") ~= "hand", zone_of("mirror"))
	end)
end

-- A card that merely moved is still what was pointed at. Codex's combat is
-- army -> duel and home again, both of them the board, so keying the rule to the
-- zone would fizzle a bolt every time the defender stepped forward.
function M.test_aimed_a_move_that_keeps_its_standing_is_still_the_target(check)
	with_game(function(name)
		flow.init(name, 3)
		local grunt = find("grunt")
		zones.move_card(grunt.id, zones.find_id("duel"))
		flow.play_card(find("bolt").id, { grunt.id })
		check("a target that walked between two board zones still takes it",
			grunt.stats.hp == 2, tostring(grunt.stats.hp))
	end)
end

-- The blind spot, inherited from the read half on purpose. A scope is not an
-- aim, so nothing answers it -- which is the real rule in every game with the
-- keyword, and it falls out rather than being written.
function M.test_aimed_a_scope_is_not_an_aim(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("wave").id, {})
		check("the illusion is still standing", zone_of("mirror") == "field", zone_of("mirror"))
		check("and it took the wave like anything else",
			find("mirror").stats.hp == 2, tostring(find("mirror").stats.hp))
	end)
end

-- A card may say it without a keyword. Codex's Guardian of the Gates is one
-- card with one rule and inventing a tag for it would be worse than writing it.
function M.test_aimed_a_card_answers_for_itself(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("bolt").id, { find("guard").id })
		check("the guard answered its own aim and took the spell too",
			find("guard").stats.hp == 1, tostring(find("guard").stats.hp))
	end)
end

-- And the aura comes off the same way every other conditional keyword does.
-- There is no tag-removal word and this is why one is not needed: the fragility
-- is a computed tag, so Macciatus takes it away by making the condition false
-- while the printed "illusion" -- what counts, what a buff reads -- stays put.
function M.test_aimed_a_warden_takes_the_word_away(check)
	with_game(function(name)
		flow.init(name, 3)
		cards.create("warden", zones.find_id("field"))
		flow.play_card(find("bolt").id, { find("mirror").id })
		check("the illusion is still on the field", zone_of("mirror") == "field", zone_of("mirror"))
		check("and took the bolt like any other unit",
			find("mirror").stats.hp == 2, tostring(find("mirror").stats.hp))
	end)
end

-- The gate, and the reason it is not `needs`. An Illusion is targetable by
-- everything -- it refuses nothing -- and dies only to a spell, so the two
-- questions want opposite answers and one list could not have held both. Codex
-- aims 91 times with "cast" and 3 times with "attack", and a write half that
-- answered every aim would kill Illusions in combat.
function M.test_aimed_when_says_which_aim_is_answered(check)
	with_game(function(name)
		flow.init(name, 3)
		flow.play_card(find("charge").id, { find("mirror").id })
		check("an attack does not kill it", zone_of("mirror") == "field", zone_of("mirror"))
		check("and it takes the damage like any unit",
			find("mirror").stats.hp == 2, tostring(find("mirror").stats.hp))
		flow.play_card(find("bolt").id, { find("mirror").id })
		check("a cast still does", zone_of("mirror") == "discard", zone_of("mirror"))
	end)
end

-- A zone's receive takes the same gate, and it gates the same half: "needs"
-- would refuse the landing outright, where a shrine takes anything and only
-- *notices* a unit.
function M.test_aimed_a_zone_gates_its_arrival_action(check)
	with_game(function(name)
		flow.init(name, 3)
		local seat = find("one")
		zones.move_card(find("bolt").id, zones.find_id("shrine"))
		check("a spell landing on the shrine is not noticed", seat.stats.faith == 0,
			tostring(seat.stats.faith))
		zones.move_card(find("grunt").id, zones.find_id("shrine"))
		check("a unit is", seat.stats.faith == 1, tostring(seat.stats.faith))
	end)
end

-- Two seats and one shared board, for the half of `receive` that is about the
-- card rather than about the aim. The shield is on the *player*, so the only
-- thing separating a right answer from a wrong one is which seat "mine" means.
local SEATED = [==[{
  "title": "Aimed at, seated",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "hp", "on": ["unit"], "start": 3, "min": 0, "max": 3 },
    { "key": "shield", "on": ["player"], "start": 0, "min": 0, "max": 9 }
  ],
  "verbs": [{ "key": "cast", "does": "target", "tooltip": "A spell picking what it lands on." }],
  "tags": {
    "illusion": { "tooltip": "Illusion — dies to a spell, unless its own controller is shielded.",
      "receive": { "when": ["verb:cast", "sum:shield@mine.player == 0"], "action": ["destroy:self"] } }
  },
  "zones": [
    { "key": "seats", "status": "board", "layout": "row", "pos": [0.05, 0.05, 0.95, 0.20] },
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.50, 0.95] },
    { "key": "field", "status": "board", "layout": "row", "pos": [0.20, 0.40, 0.50, 0.55] },
    { "key": "discard", "status": "grave", "layout": "stack", "pos": [0.60, 0.80, 0.70, 0.95] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "two", "text": "Two" },
    { "key": "mirror", "text": "Mirror", "tags": ["unit", "illusion"] },
    { "key": "bolt", "text": "Bolt", "tags": ["spell"],
      "play": { "target": { "verb": "cast", "type": "card", "tags": ["unit"], "count": 1 },
        "action": ["stat_damage:hp@target:1"] } }
  ],
  "setup": {
    "place": [
      { "card": "one", "zone": "seats" }, { "card": "two", "zone": "seats" },
      { "card": "mirror", "owner": "one", "zone": "field" },
      { "card": "bolt", "zone": "hand" }, { "card": "bolt", "zone": "hand" }
    ]
  }
}]==]

local function with_seated(fn)
	local path = "game/games/tmp_aimed_seated.json"
	local f = assert(io.open(path, "w"))
	f:write(SEATED)
	f:close()
	local ok, err = pcall(fn, "tmp_aimed_seated.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

-- **"mine" in an answer is the card that is answering.** Everywhere else it means
-- whoever is up, which is right for an imperative -- a game file tells the active
-- player to draw and to pay -- and wrong here, because being pointed at is not
-- something the receiver chose to do. Macciatus is "*your* Illusions no longer
-- die when a spell aims at them": read from the aimer's side it protects the
-- wrong player's board, and the two answers differ on every aim across the table.
function M.test_aimed_the_answer_reads_as_the_card_that_answers(check)
	with_seated(function(name)
		flow.init(name, 3)
		local mirror = find("mirror")
		actions.execute("set_active_seat:target", { targets = { find("two").id } })
		actions.execute("stat_set:shield@target:1", { targets = { find("one").id } })
		check("the other seat is up", zones.active_seat() == "two", tostring(zones.active_seat()))
		check("and only the illusion's owner is shielded",
			find("one").stats.shield == 1 and find("two").stats.shield == 0,
			find("one").stats.shield .. "/" .. find("two").stats.shield)

		flow.play_card(find("bolt").id, { mirror.id })
		check("the illusion's own shield saved it", zone_of("mirror") == "field", zone_of("mirror"))
		check("and it took the spell like any unit", mirror.stats.hp == 2, tostring(mirror.stats.hp))
	end)
end

-- The other half of the same question, because a rule that always says no is not
-- reading anything. The shield that matters is the owner's, so dropping it kills
-- the Illusion while the aimer's own shield is untouched and still nought.
function M.test_aimed_the_owners_shield_is_the_one_that_counts(check)
	with_seated(function(name)
		flow.init(name, 3)
		actions.execute("set_active_seat:target", { targets = { find("two").id } })
		actions.execute("stat_set:shield@target:0", { targets = { find("one").id } })
		actions.execute("stat_set:shield@target:1", { targets = { find("two").id } })
		check("the owner is bare and the aimer is the shielded one",
			find("one").stats.shield == 0 and find("two").stats.shield == 1,
			find("one").stats.shield .. "/" .. find("two").stats.shield)

		flow.play_card(find("bolt").id, { find("mirror").id })
		check("so the illusion dies of the aim", zone_of("mirror") == "discard", zone_of("mirror"))
	end)
end

return M
