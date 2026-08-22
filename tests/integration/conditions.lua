-- A condition written as one string, which is now the only way it is written.
--
-- ideas/17. Six places took one vocabulary in three shapes; they take one. The
-- matrix below used to check the new form against the old one, and the old one
-- is gone — so its second opinion is written out here instead, as the rules say
-- them rather than as the code under test implements them. The five rules each
-- paid for by a bug are asserted separately, because a grammar reads like
-- arithmetic and invites the reading that a missing number is zero.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local phase = require("phase")
local predicate = require("predicate")

local M = {}

local GAME = [==[{
  "title": "Conditions",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "gold", "label": "Gold", "subject": "gold@mine.player" }],
  "zones": [
    { "key": "board", "type": "grid", "grid": [3, 1], "tags": ["activate"],
      "pos": [0.05, 0.30, 0.95, 0.55] },
    { "key": "hand", "type": "hand", "tags": ["per_seat"],
      "pos": [[0.30, 0.05, 0.95, 0.25], [0.30, 0.70, 0.95, 0.90]] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand",
      "next": [{ "when": "gold >= 5", "then": "rich" }, { "then": "act" }] },
    { "key": "rich", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "gold": 5 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "gold": 1 } },
    { "key": "beast", "text": "Beast", "tags": ["beast"], "card_stats": { "hp": 3 } },
    { "key": "ghost", "text": "Ghost", "tags": ["ghost"] },
    { "key": "one_gate", "text": "One gate",
      "play": { "needs": ["gold >= 3"], "action": ["destroy_self"] } },
    { "key": "range_gate", "text": "Range gate",
      "play": { "needs": ["gold >= 3", "gold <= 8"], "action": ["destroy_self"] } },
    { "key": "loose", "text": "Loose", "play": { "action": ["destroy_self"] } }
  ],
  "setup": {
    "place": [
      { "card": "beast", "owner": "one", "zone": "board", "at": ["a1", "b1"] },
      { "card": "ghost", "owner": "two", "zone": "board", "at": ["c1"] }
    ]
  }
}]==]

local function with_game(fn)
	local path = "game/games/tmp_conditions.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_conditions.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- The parser needs no game at all, which is the property that lets the
-- validator read a condition at authoring time.
function M.test_conditions_parse_without_a_game(check)
	local c = predicate.parse_condition("max:value@mine.red <= 6")
	check("both sides come back as what they are",
		c ~= nil and c.op == "<=" and c.left.subject.fn == "max" and c.right.n == 6)

	local subj = predicate.parse_condition("score@north_side >= score@south_side")
	check("a bound may be another subject",
		subj ~= nil and subj.right.subject ~= nil and subj.right.src == "score@south_side")

	for _, op in ipairs({ ">=", "<=", ">", "<", "==", "!=" }) do
		check("it knows " .. op, predicate.parse_condition("gold " .. op .. " 3") ~= nil)
	end
end

-- Every refusal names what to write instead. A condition that will not parse is
-- refused at the door rather than failing closed at run time, which is where the
-- struct form has to leave it.
function M.test_conditions_refuse_what_cannot_be_meant(check)
	local function why(s)
		local _, err = predicate.parse_condition(s)
		return err or ""
	end
	check("assignment is not comparison", why("gold = 3"):find("write >=", 1, true) ~= nil, why("gold = 3"))
	check("a range is two conditions", why("3 <= gold <= 8"):find("two of them", 1, true) ~= nil,
		why("3 <= gold <= 8"))
	check("nothing on one side", why("gold >=") ~= "", why("gold >="))
	check("no comparison at all", why("gold"):find("comparison", 1, true) ~= nil, why("gold"))
	-- The rule bound() keeps today, moved to the door: a misspelling on the
	-- right would otherwise read as an unknown stat worth nothing and pass.
	check("a bare word on the right is a typo", why("gold >= reserve"):find("bare word", 1, true) ~= nil,
		why("gold >= reserve"))
	check("and it is not one on the left", predicate.parse_condition("gold >= 3") ~= nil)
end

-- The second opinion, written as the rules read rather than as the parser
-- implements them: absent is not zero, "each" asks of every member, and a
-- measuring fn is asked of the pool. It answers over predicate.total and
-- predicate.bearers, so a mistake in compiling a comparison shows up as a
-- disagreement instead of as two copies of the same bug.
local CMP = {
	[">="] = function(a, b) return a >= b end,
	["<="] = function(a, b) return a <= b end,
	["=="] = function(a, b) return a == b end,
}

local function reference(s, op, n, ctx)
	local p = predicate.parse_subject(s)
	if p.fn == nil and #predicate.bearers(p, ctx) == 0 then return false end
	if p.fn == nil and p.quant == "each" then
		local ents = predicate.entities_in_scope(p.scope, ctx, p.owner)
		if #ents == 0 then return false end
		for _, e in ipairs(ents) do
			if not CMP[op](tonumber((e.stats or {})[p.arg]) or 0, n) then return false end
		end
		return true
	end
	return CMP[op](predicate.total(s, ctx), n)
end

function M.test_conditions_every_subject_answers_as_the_rules_say(check)
	with_game(function(name)
		flow.init(name, 3)
		local subjects = {
			"gold", "hp@beast", "hp@each.beast", "count:beast", "count:ghost",
			"sum:hp@board", "max:hp@board", "moves_made@beast", "hp@ghost",
			"tagged:beast@board",
		}
		local agreed, total = true, 0
		for _, s in ipairs(subjects) do
			for _, n in ipairs({ 0, 1, 3, 9 }) do
				for _, op in ipairs({ ">=", "<=", "==" }) do
					local want = reference(s, op, n, {})
					local got = predicate.holds(s .. " " .. op .. " " .. n, {})
					total = total + 1
					if want ~= got then
						agreed = false
						check("DISAGREED on " .. s .. " " .. op .. " " .. n,
							false, tostring(want) .. " vs " .. tostring(got))
					end
				end
			end
		end
		check("every subject answers as the rules say", agreed, total .. " comparisons")
	end)
end

-- Each of these cost a bug once. A grammar reads like arithmetic and invites the
-- reading that a missing number is zero, so they are asserted against the string
-- form specifically rather than trusted to the shared code underneath.
function M.test_conditions_the_rules_that_must_survive(check)
	with_game(function(name)
		flow.init(name, 3)
		check("a stat nobody carries fails every comparison, == 0 included",
			predicate.holds("moves_made@beast == 0", {}) == false)
		check("...and at_most, which is the direction that looks safe",
			predicate.holds("moves_made@beast <= 9", {}) == false)
		check("...and !=, the new operator, which fails closed like the rest",
			predicate.holds("moves_made@beast != 1", {}) == false)

		check("the measuring forms are exempt: no dragons really is none",
			predicate.holds("count:dragon == 0", {}))
		check("and an empty pool honestly sums to zero",
			predicate.holds("sum:hp@hand == 0", {}))

		check("each over an empty scope is false, not vacuously true",
			predicate.holds("hp@each.dragon >= 1", {}) == false)
		check("each over a real one asks of every member",
			predicate.holds("hp@each.beast >= 3", {}) and
			predicate.holds("hp@each.beast >= 4", {}) == false)

		check("a condition that will not parse is false, never an error",
			predicate.holds("gold >= reserve", {}) == false)
	end)
end

-- The three operators the struct form never had. Small, and they arrive for
-- free: the shapes it can express are the shapes it could always evaluate.
function M.test_conditions_the_operators_the_struct_form_lacked(check)
	with_game(function(name)
		flow.init(name, 3)
		check("greater than", predicate.holds("gold > 4", {}) and predicate.holds("gold > 5", {}) == false)
		check("less than", predicate.holds("count:beast < 3", {}) and predicate.holds("count:beast < 2", {}) == false)
		check("not equal", predicate.holds("count:beast != 1", {}) and predicate.holds("count:beast != 2", {}) == false)
	end)
end

-- A needs is a list, gating real cards through the real path — and a list is
-- what a map keyed by its own subject could never be: "gold >= 3" with
-- "gold <= 8" names one subject twice, which is how a range is written.
function M.test_conditions_a_needs_is_a_list_of_them(check)
	with_game(function(name)
		flow.init(name, 3)
		local hand = zones.all_with_key("hand")[1]
		local one = zones.add(hand, "one_gate")
		local range = zones.add(hand, "range_gate")
		-- Something else playable, or the escape hatch opens a gated card when
		-- nothing in its zone is playable — and would open both of these.
		zones.add(hand, "loose")
		check("both gates open on five gold", flow.can_play(one.id) and flow.can_play(range.id))

		card("one").stats.gold = 2
		check("and both shut when it drops",
			flow.can_play(one.id) == false and flow.can_play(range.id) == false)

		card("one").stats.gold = 12
		check("only the range shuts at the top", flow.can_play(one.id)
			and flow.can_play(range.id) == false)
	end)
end

-- Routing takes one under "when", which is where the struct form's stat/at_least
-- pair reads worst: two fields and a third for the destination.
function M.test_conditions_a_route_can_carry_one(check)
	with_game(function(name)
		flow.init(name, 3)
		check("five gold is the rich route", phase.current().key == "act")
		phase.next()
		check("and it was taken", phase.current().key == "rich", phase.current().key)

		phase.next()
		card("one").stats.gold = 1
		phase.next()
		check("one gold is not", phase.current().key == "act", phase.current().key)
	end)
end

-- `min:` — the smallest of a pool, and the one measuring form that is not
-- exempt from *a stat nobody carries is absent, not zero*.
--
-- It only ever sees the cards that carry the stat, which is what makes "the
-- lowest card of this colour in my hand" sayable at all: a tag scope reads grid
-- zones only, so `@pink` cannot see a hand — but a stat only pink cards carry
-- can, read through `@mine.hand`.
function M.test_conditions_min_is_the_smallest_of_what_carries_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local board = zones.find("board")
		local a, b = entity.get(board.cards[1]), entity.get(board.cards[2])
		a.stats.hp, b.stats.hp = 4, 7

		check("min takes the smaller", predicate.total("min:hp@board") == 4,
			tostring(predicate.total("min:hp@board")))
		check("and max still takes the larger", predicate.total("max:hp@board") == 7)
		a.stats.hp = 9
		check("min follows the numbers", predicate.total("min:hp@board") == 7)

		-- The ghost on c1 carries no hp at all and must not drag the answer to
		-- zero: bearers is what min walks, not the scope.
		check("a card without the stat is not a zero in the pool",
			predicate.total("min:hp@board") == 7)

		check("a comparison reads it", predicate.holds("min:hp@board == 7"))
		check("and reads it on the right too",
			predicate.holds("hp@ghost >= min:hp@board") == false)
	end)
end

-- Nothing is not *at least* nothing. `sum:` and `max:` of an empty pool are
-- honestly 0 — nothing adds to nothing, nothing is at most nothing — but a zero
-- minimum would sit *below* every real value, so a gate would open exactly when
-- the thing it measures is not there at all.
function M.test_conditions_the_smallest_of_nothing_is_absent(check)
	with_game(function(name)
		flow.init(name, 3)
		check("sum over an empty pool is zero", predicate.holds("sum:hp@hand == 0"))
		check("and so is max", predicate.holds("max:hp@hand == 0"))
		check("but min fails every comparison", predicate.holds("min:hp@hand == 0") == false
			and predicate.holds("min:hp@hand <= 9") == false
			and predicate.holds("min:hp@hand >= 0") == false)
		check("including on the right-hand side",
			predicate.holds("hp@beast >= min:hp@hand") == false)
	end)
end

-- A compute's `from`: the same subject grammar, one operator, and no
-- parentheses. Pure — a string in, a split out — so it is checked without a
-- game loaded, exactly as parse_condition is.
function M.test_conditions_a_compute_splits_on_one_operator(check)
	local v = predicate.parse_value("0 - health@across")
	check("a two-term expression splits into both sides and the operator",
		v ~= nil and v.left == "0" and v.op == "-" and v.right == "health@across")

	local one = predicate.parse_value("sum:power@self")
	check("and a single term is a left with no operator",
		one ~= nil and one.left == "sum:power@self" and one.op == nil)

	check("all three operators are known",
		predicate.parse_value("a + b").op == "+"
		and predicate.parse_value("a - b").op == "-"
		and predicate.parse_value("a * b").op == "*")

	-- No parentheses means no precedence to remember, which is only true while
	-- there is one operator to apply it to.
	local _, err = predicate.parse_value("hp - 1 - 1")
	check("two operators are refused, and say what to do instead",
		err ~= nil and err:find("one operator per compute", 1, true) ~= nil, tostring(err))

	local _, err2 = predicate.parse_value("hp - ")
	check("and so is an operator with nothing after it", err2 ~= nil, tostring(err2))

	-- A hyphen inside a name is not an operator: the spaces are what say so,
	-- which is the same discipline a condition keeps.
	check("spaces are what make an operator one",
		predicate.parse_value("hp@each.enemy.creature").op == nil)
end

-- Bindings are read before a bare subject is judged absent, which is what lets
-- a compute stand as an operand at all: nothing carries it, so the absent rule
-- would otherwise fail every comparison against it.
function M.test_conditions_a_bound_compute_answers_a_comparison(check)
	with_game(function(name)
		flow.init(name, 3)
		local ctx = { let = { spare = 4 } }
		check("a bound name measures its number", predicate.holds("spare >= 4", ctx))
		check("and compares both ways", predicate.holds("spare < 5", ctx)
			and predicate.holds("spare == 4", ctx))
		check("unbound, the same string fails rather than reading as zero",
			predicate.holds("spare == 0", {}) == false)
		check("a stat that really is absent still fails every comparison",
			predicate.holds("nosuchstat == 0", ctx) == false)
	end)
end

return M
