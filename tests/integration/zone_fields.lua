-- A zone by its parts.
--
-- One word, "type", answered seven questions at once — where the cards are
-- drawn, who may read them, how many of them the rules can see, what may be
-- done with one, what standing they have, whether the zone is drawn at all, and
-- whether there is one per seat. A game could have the five bundles somebody had
-- thought of and no other, and the fault was not that the bundles were wrong: a
-- deck really is a secret stack you take from the top. It is that a combination
-- nobody anticipated had to be faked by taking the nearest bundle and living
-- with the rest of it, which is how a row of ongoing effects came to be a hand.
--
-- Seven fields, and the tags that used to override half of them are gone. What
-- this buys is the combinations, so that is what is tested here: the ones that
-- could not be written before, and the two ways the parts refuse to disagree.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local predicate = require("predicate")

local M = {}

local GAME = [==[{
  "title": "Parts",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "gold", "label": "Gold", "subject": "gold@mine.player" }],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "board", "layout": "grid", "grid": [4, 1], "use": "abilities",
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "market", "layout": "stack", "contents": ["relic:3"],
      "pos": [0.55, 0.35, 0.65, 0.50] },
    { "key": "trash", "layout": "stack", "use": "none", "pos": [0.70, 0.35, 0.80, 0.50] },
    { "key": "column", "layout": "row", "row": "down", "reach": "top", "use": "abilities",
      "pos": [0.85, 0.30, 0.95, 0.70] },
    { "key": "readout", "layout": "grid", "grid": [1, 1], "status": "exile",
      "pos": [0.05, 0.05, 0.15, 0.15] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.05, 0.20, 0.15, 0.35] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "seat": "next", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "gold": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "gold": 0 } },
    { "key": "relic", "text": "Relic", "tags": ["loot"],
      "activate": { "action": ["stat_gain:gold@mine.player:1"] } }
  ]
}]==]

local function with_game(text, fn)
	local path = "game/games/tmp_zone_fields.json"
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	local ok, err = pcall(fn, "tmp_zone_fields.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function zone_of(key, seat_key)
	for _, z in ipairs(zones.all_with_key(key)) do
		if not seat_key or z.seat == seat_key then return z end
	end
end

-- A deck was a secret stack you may not reach into, and those are three separate
-- facts. Say two of them and leave the third out and you get the fourth thing
-- nobody could write: a stack of cards everyone can read and pick from, which is
-- a market row, and which used to have to be a "pile" and lose the rest.
function M.test_zone_fields_a_public_stack_can_be_searched(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local market = zone_of("market")
		check("it is a stack all the same", market.layout == "stack", market.layout)
		check("reached from the top, which a stack is unless it says otherwise",
			market.reach == "top", market.reach)
		check("and its cards are there to be found", #predicate.entities_in_scope("market", {}) == 3,
			#predicate.entities_in_scope("market", {}))
	end)
end

-- The other half of the same split, and the one that had no spelling at all: a
-- place a rule can point at and nothing can touch. MTG's exile, Slay the Spire's
-- trash. Every zone a rule could name was a zone whose cards a search found.
function M.test_zone_fields_a_trash_is_nameable_and_untouchable(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local trash = zone_of("trash")
		local c = zones.add(trash, "relic")
		check("a rule that names the zone finds it", #predicate.entities_in_scope("trash", {}) == 1,
			#predicate.entities_in_scope("trash", {}))
		check("but nothing here may be used", #flow.usable_abilities(c.id) == 0,
			#flow.usable_abilities(c.id))
		-- The same card, one zone over, to show it is the zone refusing and not
		-- the card having nothing to offer.
		zones.move_card(c.id, zone_of("column").id)
		check("while the same card elsewhere may be", #flow.usable_abilities(c.id) == 1,
			#flow.usable_abilities(c.id))
	end)
end

-- Reach is not the layout. A column read down its whole length, of which only
-- the last card is in play, is Lost Cities' expedition — and it used to happen
-- by side effect, a "pile" wearing a style that fanned it, which drew five cards
-- and answered for one without either half knowing about the other.
function M.test_zone_fields_a_row_may_be_reached_from_the_top(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local col = zone_of("column")
		for _ = 1, 3 do zones.add(col, "relic") end
		check("every card in it is laid out", col.layout == "row" and col.row == "down")
		local top = entity.get(col.cards[#col.cards])
		local buried = entity.get(col.cards[1])
		check("the last of them may be used", #flow.usable_abilities(top.id) == 1,
			#flow.usable_abilities(top.id))
		check("and the ones under it may not", #flow.usable_abilities(buried.id) == 0,
			#flow.usable_abilities(buried.id))
		check("which is a reach, said on purpose", col.reach == "top", col.reach)
	end)
end

-- Status is not the layout either. A grid used as a readout — a scoreboard, a
-- turn indicator — is in play by the old rule and has no business being counted,
-- sacrificed, or asked to act.
function M.test_zone_fields_a_grid_may_be_a_readout(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		zones.add(zone_of("readout"), "relic")
		zones.add(zone_of("board"), "relic")
		check("only the board's is in play", predicate.total("count:loot") == 1,
			predicate.total("count:loot"))
	end)
end

-- The defaults, which are what keep seven fields from being seven things to
-- remember: most zones say one word and mean the obvious thing.
function M.test_zone_fields_a_neighbouring_field_supplies_the_defaults(check)
	with_game(GAME, function(name)
		flow.init(name, 3)
		local market, board = zone_of("market"), zone_of("board")
		check("a stack is reached from the top", market.reach == "top", market.reach)
		check("a grid is in play", board.status == "board", board.status)
		check("and everything else is what it says on the tin",
			market.visibility == "public" and market.use == "play"
			and market.status == "exile" and market.display == "onscreen"
			and market.copies == "one")
	end)
end

-- Cards nobody can see cannot be picked out of the zone, so a deck is two words
-- rather than five — and a game that wants the searchable face-up deck the old
-- bundle refused says so, in the field that means it.
function M.test_zone_fields_a_secret_zone_is_a_box_by_default(check)
	local text = GAME:gsub('"key": "market", "layout": "stack"',
		'"key": "market", "layout": "stack", "visibility": "secret"')
	with_game(text, function(name)
		flow.init(name, 3)
		local market = zone_of("market")
		check("nobody reaches into a box", market.use == "none", market.use)
		-- Nameable all the same: a rule that says "market" means the market, in a
		-- box exactly as in a trash. What "none" refuses is a hand reaching in.
		local c = entity.get(market.cards[1])
		check("and nothing in it can be used", #flow.usable_abilities(c.id) == 0,
			#flow.usable_abilities(c.id))
	end)
end

-- A value names its own parameter field, which is the whole reason every word on
-- every field is reserved. A parameter whose value was not chosen is a zone that
-- thinks it is two shapes, and the validator says so rather than letting the
-- renderer pick whichever it read last.
function M.test_zone_fields_a_parameter_needs_its_value(check)
	local declaration = require("declaration")
	local validate = require("validate")
	local path = "game/games/tmp_bad_parts.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
		"title": "Two Shapes",
		"zones": [
			{ "key": "board", "layout": "grid", "grid": [2, 2] },
			{ "key": "muddle", "layout": "row", "grid": [2, 2] },
			{ "key": "worse", "layout": "grid", "grid": [2, 2], "visibility": "translucent" }
		],
		"cards": [{ "key": "thing", "text": "Thing" }]
	}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_bad_parts.json")
	os.remove(path)
	if not ok then error(G, 2) end
	local said = table.concat(validate.check(G), " | ")

	check("a parameter whose value was not chosen is refused",
		said:find('writes "grid", which belongs to "layout"', 1, true) ~= nil, said)
	check("and the zone that did choose it is left alone",
		said:find("zone 'board': writes", 1, true) == nil, said)
	check("a word the engine does not have is refused with the words it does",
		said:find("none of owner, public, secret", 1, true) ~= nil, said)
	check("and it falls back to the default rather than to whatever was typed",
		G.zone_defs.worse.visibility == "public", G.zone_defs.worse.visibility)
end

return M
