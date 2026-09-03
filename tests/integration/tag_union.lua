-- "a CURSE or an ICE" — the union the format could not say.
--
-- A condition list is an `and`, a scope names one tag, and two cards of
-- different kinds have nothing in common to point at. So the union is *named*,
-- once, centrally, and the name is then an ordinary tag: every tag question in
-- the engine comes through `tags.entity_has`, so one addition there makes it
-- work in a scope, in `tagged:`, in a count and in a target spec at once.
--
-- The second half is that a *place* can be a kind too, since a zone hands out
-- tags. A union over two of those is "hand or discard", which no zone key
-- covers — and reaching it wants `everywhere.<tag>`, a scope that could count
-- such a set before it could select one.

local declaration = require("declaration")
local validate    = require("validate")
local entity      = require("entity")
local zones       = require("zones")
local flow        = require("flow")
local actions     = require("actions")
local predicate   = require("predicate")

local M = {}

local GAME = [==[{
  "title": "Union",
  "players": [{ "card": "one" }, { "card": "two" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "applies": ["in_hand"], "pos": [[0.2, 0.4, 0.75, 0.2], [0.2, 0.62, 0.75, 0.2]] },
    { "key": "discard", "layout": "stack", "copies": "per_seat",
      "applies": ["in_discard"], "pos": [[0.2, 0.05, 0.1, 0.2], [0.7, 0.05, 0.1, 0.2]] },
    { "key": "table", "layout": "grid", "grid": [2, 1], "status": "board",
      "pos": [0.35, 0.28, 0.3, 0.1] },
    { "key": "bin", "layout": "stack", "display": "offscreen", "use": "none" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "tags": { "in_hand": { "tooltip": "Held." }, "in_discard": { "tooltip": "Binned." } },
  "computed_tags": {
    "junk": { "any_of": ["curse", "ice"] },
    "held_or_binned": { "any_of": ["in_hand", "in_discard"] },
    "junk_held": { "all_of": ["junk", "held_or_binned"] }
  },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "curse", "text": "Curse", "tags": ["curse"] },
    { "key": "ice", "text": "Ice", "tags": ["ice"] },
    { "key": "gem", "text": "Gem", "tags": ["gem"] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_union.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_union.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function zone(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if seat == nil or z.seat == seat then return z end
	end
end

local function keys(scope)
	local sc = predicate.parse_scope(scope)
	local out = {}
	for _, e in ipairs(sc and predicate.entities_in_scope(sc.name, {}, sc.owner) or {}) do
		if e.kind == "card" then out[#out + 1] = e.def_key end
	end
	table.sort(out)
	return table.concat(out, ",")
end

-- Three cards of three kinds, two of which are the union.
local function deal(seat)
	local h = zone("hand", seat)
	zones.add(h, "curse")
	zones.add(h, "ice")
	zones.add(h, "gem")
end

function M.test_tag_union_is_a_tag_wherever_a_tag_works(check)
	with_game(function(name)
		flow.init(name, 3)
		local one = zones.active_seat()
		deal(one)

		check("as a scope, it names the two kinds and not the third",
			keys("mine.hand.junk") == "curse,ice", keys("mine.hand.junk"))
		check("and counting it agrees",
			predicate.value("count:junk@mine.hand", {}) == 2,
			predicate.value("count:junk@mine.hand", {}))

		local ice
		for e in entity.each("card") do if e.def_key == "ice" then ice = e end end
		check("a condition can ask a single card whether it wears it",
			predicate.meets_all({ "tagged:junk@target" }, { card_id = ice.id, targets = { ice.id } }))

		-- And it moves what it names, which is the half a `where` cannot do.
		actions.execute("move:mine.hand.junk:mine.discard", {})
		check("the union moved, the gem stayed",
			keys("mine.hand") == "gem", keys("mine.hand"))
	end)
end

-- A place is a kind too, because a zone hands out tags. This is the union no
-- zone key covers, and the scope that reaches it.
function M.test_tag_union_spans_two_zones(check)
	with_game(function(name)
		flow.init(name, 3)
		local one = zones.active_seat()
		deal(one)
		zones.add(zone("discard", one), "curse")
		zones.add(zone("table"), "ice")
		zones.add(zones.find("bin"), "ice")

		check("counting a set spread over two zones was always possible",
			predicate.value("count:held_or_binned@mine.everywhere", {}) == 4,
			predicate.value("count:held_or_binned@mine.everywhere", {}))
		check("and now a scope selects the same set",
			keys("mine.everywhere.held_or_binned") == "curse,curse,gem,ice",
			keys("mine.everywhere.held_or_binned"))
		check("the ICE on the table and the one in the bin are in neither place",
			select(2, keys("mine.everywhere.held_or_binned"):gsub("ice", "")) == 1,
			keys("mine.everywhere.held_or_binned"))

		-- The two unions compose, which is the whole point of a union being a
		-- tag rather than a special case. The owner word narrows it as it
		-- narrows anything: the shared table and bin belong to nobody.
		check("every junk card there is, wherever it sits",
			keys("everywhere.junk") == "curse,curse,ice,ice,ice",
			keys("everywhere.junk"))
		check("and mine alone, which drops the two nobody owns",
			keys("mine.everywhere.junk") == "curse,curse,ice",
			keys("mine.everywhere.junk"))
	end)
end

-- The board-only default still holds: a bare tag must not read a hand.
-- The intersection, which is the shape a real card wants: "a CURSE or an ICE
-- from your hand or discard" is two unions met in the middle, and the middle has
-- a name rather than a nesting.
function M.test_tag_union_meets_another_union_in_the_middle(check)
	with_game(function(name)
		flow.init(name, 3)
		local one = zones.active_seat()
		deal(one)
		zones.add(zone("discard", one), "curse")
		zones.add(zone("table"), "ice")

		check("the ICE on the table is junk and is in neither place",
			keys("mine.everywhere.junk_held") == "curse,curse,ice",
			keys("mine.everywhere.junk_held"))
		check("and the gem is in both places and is not junk",
			keys("mine.everywhere.junk_held"):find("gem") == nil)
	end)
end

function M.test_tag_union_does_not_widen_a_bare_tag(check)
	with_game(function(name)
		flow.init(name, 3)
		deal(zones.active_seat())
		check("a bare union sees the board, exactly as a bare tag does",
			keys("junk") == "", keys("junk"))
		check("naming everywhere is the opt-in, and it is a decision",
			keys("mine.everywhere.junk") == "curse,ice", keys("mine.everywhere.junk"))
	end)
end

function M.test_tag_union_refuses_the_shapes_that_cannot_settle(check)
	with_game(function(name)
		local G = declaration.parse(name)
		check("the fixture is clean to start with", #validate.check(G) == 0,
			table.concat(validate.check(G), " | "))

		local function says(needle)
			for _, p in ipairs(validate.check(G)) do
				if p:find(needle, 1, true) then return true end
			end
			return false
		end

		G.computed_tags.junk = { any_of = { "curse", "nosuchtag" } }
		check("a union of a tag nothing carries is a typo", says("nosuchtag"))

		G.computed_tags.junk = { any_of = { "curse" }, stat = "hp" }
		check("a union that is also a stat is two answers to one word",
			says("one way, from a number or from other tags"))

		G.computed_tags.junk = { any_of = { "held_or_binned" } }
		G.computed_tags.held_or_binned = { any_of = { "junk" } }
		check("and a union that reaches itself never settles",
			says("combines its way back to itself"))
	end)
end

return M
