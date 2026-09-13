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
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [3, 1],
      "pos": [0.05, 0.30, 0.95, 0.55] },
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
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
      "play": { "needs": ["gold >= 3"], "action": ["purge:self"] } },
    { "key": "range_gate", "text": "Range gate",
      "play": { "needs": ["gold >= 3", "gold <= 8"], "action": ["purge:self"] } },
    { "key": "loose", "text": "Loose", "play": { "action": ["purge:self"] } }
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
	check("and it is not one on the left", predicate.parse_condition("gold >= 3") ~= nil)
end

-- A bare word on the right is a compute the ability bound, or a misspelling
-- that would read as an unknown stat worth nothing. The grammar cannot tell
-- them apart — it is cached across games and knows nothing of one ability's
-- `compute` list — so it marks the word, the measure reads it as *absent*, and
-- the validator, which does know the bound names, is what calls it a typo.
function M.test_conditions_a_bare_word_on_the_right(check)
	local c = predicate.parse_condition("gold >= reserve")
	check("it parses rather than being refused at the door", c ~= nil)
	check("and says the word answers to nobody yet", c and c.right.bare == true)

	with_game(function(name)
		flow.init(name, 3)
		check("nothing bound it, so the comparison fails closed",
			predicate.holds("gold >= reserve", {}) == false)
		check("even the other way round", predicate.holds("gold <= reserve", {}) == false)
		check("a compute the ability bound answers it",
			predicate.holds("gold >= reserve", { let = { reserve = 4 } }) == true)
		check("and answers it as the number it is",
			predicate.holds("gold >= reserve", { let = { reserve = 6 } }) == false)
	end)
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

-- **Neither end is clamped on the way.** An empty pool answers 0 (below), but a
-- pool with something *below* zero in it must answer what is there. A stat stores
-- what is left once its buffs are off, so a card wounded under a counter it has
-- since lost holds a negative number — and a largest seeded at nought would call
-- that board nought.
function M.test_conditions_the_largest_may_be_below_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local board = zones.find("board")
		local a, b = entity.get(board.cards[1]), entity.get(board.cards[2])
		a.stats.hp, b.stats.hp = -3, -1

		check("max takes the largest of them, not zero",
			predicate.total("max:hp@board") == -1, tostring(predicate.total("max:hp@board")))
		check("min takes the smallest", predicate.total("min:hp@board") == -3,
			tostring(predicate.total("min:hp@board")))
		check("and the sum is the sum", predicate.total("sum:hp@board") == -4,
			tostring(predicate.total("sum:hp@board")))
		check("so a comparison is not quietly floored",
			predicate.holds("max:hp@board < 0"))
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

-- A compute's `from`: arithmetic over numbers and subjects, with + - *,
-- parentheses and the precedence every reader already has. Pure — a string in,
-- a tree out — so it is checked without a game loaded, as parse_condition is.
-- It held one operator and no brackets, and fifteen of Codex's twenty-five
-- computes existed only as the brackets it would not write.
function M.test_conditions_a_compute_is_an_arithmetic_expression(check)
	local v = predicate.parse_value("0 - health@across")
	check("the terms come back in the order they were written",
		v ~= nil and table.concat(v.terms, ",") == "0,health@across",
		v and table.concat(v.terms, ","))

	local one = predicate.parse_value("sum:power@self")
	check("and a single term is an expression too",
		one ~= nil and table.concat(one.terms, ",") == "sum:power@self")

	check("all three operators are known",
		predicate.value("6 + 2", {}) == 8
		and predicate.value("6 - 2", {}) == 4
		and predicate.value("6 * 2", {}) == 12)

	-- The one every reader has from school, which is the whole argument for
	-- allowing brackets at all: there is no second rule to be taught.
	check("times binds tighter than plus", predicate.value("2 + 3 * 4", {}) == 14,
		predicate.value("2 + 3 * 4", {}))
	check("and brackets say otherwise", predicate.value("(2 + 3) * 4", {}) == 20,
		predicate.value("(2 + 3) * 4", {}))
	check("minus associates left, so this is five and not nine",
		predicate.value("10 - 3 - 2", {}) == 5, predicate.value("10 - 3 - 2", {}))
	check("and nests", predicate.value("((1 + 2) * (3 + 4))", {}) == 21,
		predicate.value("((1 + 2) * (3 + 4))", {}))

	local _, err = predicate.parse_value("hp - ")
	check("an operator with nothing after it says so",
		err ~= nil and err:find("stops in the middle", 1, true) ~= nil, tostring(err))
	local _, e2 = predicate.parse_value("(hp - 1")
	check("so does a bracket never closed",
		e2 ~= nil and e2:find("never closed", 1, true) ~= nil, tostring(e2))
	local _, e3 = predicate.parse_value("hp - 1)")
	check("and one closed that was never opened",
		e3 ~= nil and e3:find("never opened", 1, true) ~= nil, tostring(e3))
	local _, e4 = predicate.parse_value("+ 1")
	check("and an operator with nothing in front of it",
		e4 ~= nil and e4:find("nothing in front", 1, true) ~= nil, tostring(e4))

	-- A hyphen inside a name is not an operator: the spaces are what say so,
	-- which is the same discipline a condition keeps.
	local name = predicate.parse_value("hp@each.enemy.creature")
	check("spaces are what make an operator one",
		name ~= nil and #name.terms == 1, name and #name.terms)
	local minus = predicate.parse_value("-1 + 2")
	check("so a minus glued to a digit is a negative number",
		minus ~= nil and minus.terms[1] == "-1", minus and minus.terms[1])
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

-- `@everywhere` — the one scope that reaches a hand and a deck. A bare tag, and
-- a tag scope, see the board alone on purpose: most rules must not read a hand
-- they cannot see. When a rule genuinely wants to count a tag wherever it sits —
-- "how many gems does this player hold, in play or in hand or still in the bag" —
-- and cannot name every zone one at a time, this is the deliberate opt-in.
local EVERYWHERE = [==[{
  "title": "Everywhere",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "gold", "label": "Gold", "subject": "gold@mine.player" }],
  "zones": [
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.05, 0.30, 0.95, 0.55] },
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.30, 0.05, 0.95, 0.25], [0.30, 0.70, 0.95, 0.90]] },
    { "key": "vault", "layout": "stack", "visibility": "secret", "display": "offscreen" }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "gold": 5 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "gold": 1 } },
    { "key": "gem", "text": "Gem", "tags": ["gem"], "card_stats": { "value": 2 } }
  ],
  "setup": {
    "place": [ { "card": "gem", "owner": "one", "zone": "board", "at": ["a1"] } ]
  }
}]==]

function M.test_conditions_everywhere_reaches_a_hand_and_a_deck(check)
	local path = "game/games/tmp_everywhere.json"
	local f = assert(io.open(path, "w")); f:write(EVERYWHERE); f:close()
	local ok, err = pcall(function()
		flow.init("tmp_everywhere.json", 3)
		-- One gem on the board (owned by seat one, from setup), one into the
		-- active seat's hand, one into the shared deck.
		require("actions").run({ "create:mine.hand:gem:1", "create:vault:gem:1" }, {})

		-- The default is unchanged, and it is two spellings of the same board.
		check("a bare tag still sees the board alone",
			predicate.holds("count:gem == 1", {}),
			tostring(predicate.total("count:gem")))
		check("and a tag scope is the same board, not a wider search",
			predicate.holds("count:gem@gem == 1", {}))

		-- The opt-in reaches all three at once — the one thing naming a single
		-- zone cannot do.
		check("everywhere counts the board, the hand and the deck together",
			predicate.holds("count:gem@everywhere == 3", {}),
			tostring(predicate.total("count:gem@everywhere")))
		check("a measuring fn reads over the same set",
			predicate.holds("sum:value@everywhere == 6", {}),
			tostring(predicate.total("sum:value@everywhere")))

		-- The owner word narrows it exactly as it narrows anything else: the
		-- board gem and the hand gem are seat one's; the deck gem is nobody's,
		-- so it drops out of both mine and enemy.
		check("mine keeps only this seat's, wherever they sit",
			predicate.holds("count:gem@mine.everywhere == 2", {}),
			tostring(predicate.total("count:gem@mine.everywhere")))
		check("and a card in a shared deck belongs to neither seat",
			predicate.holds("count:gem@enemy.everywhere == 0", {}))
	end)
	os.remove(path)
	if not ok then error(err, 0) end
end

-- "not_self" -- the one question in the vocabulary that is not about a property.
--
-- Everything else a condition asks is what a card *is*: a tag, a stat, a zone.
-- "a different Fire card in your hand" asks which one you are, and there was no
-- spelling for it at all: two copies of the same card are alike in every way a
-- condition can see, so nothing short of identity tells them apart.
--
-- It is also the only measuring fn written with no argument, which is the whole
-- of why the parser needed a word for it: without a colon there is nothing to
-- find it by, so `not_self@target` parsed as a stat nobody carries and quietly
-- answered no.
function M.test_conditions_not_self_tells_a_card_from_the_one_asking(check)
	local predicate = require("predicate")
	local sub = predicate.parse_subject("not_self@target")
	check("it parses as a measuring fn, not as a stat called not_self",
		sub.fn == "not_self" and sub.arg == nil and sub.scope == "target",
		tostring(sub.fn) .. "/" .. tostring(sub.arg) .. "/" .. tostring(sub.scope))

	with_game(function(name)
		flow.init(name, 3)
		-- Two of a kind, which is the case that needs it: alike in every way a
		-- condition can see, and still not the same card.
		local hand = zones.find("hand")
		local me = zones.add(hand, "loose")
		local twin = zones.add(hand, "loose")

		check("a candidate that is the asker answers no",
			predicate.total("not_self@target", { card_id = me.id, targets = { me.id } }) == 0)
		check("and its identical twin answers yes",
			predicate.total("not_self@target", { card_id = me.id, targets = { twin.id } }) == 1)

		-- The reading that matters when the engine runs a card with nobody aimed
		-- at anything: there is no asker, so every candidate is somebody else.
		check("with nobody asking, everything is somebody else",
			predicate.total("not_self@target", { targets = { me.id } }) == 1)

		check("it holds as a condition, not only as a measurement",
			predicate.holds("not_self@target", { card_id = me.id, targets = { twin.id } })
			and not predicate.holds("not_self@target", { card_id = me.id, targets = { me.id } }))
	end)
end

-- A question is written on its own, and comparing one to a number is refused.
--
-- The fns that answer yes or no were written as 1 or 0 only because the grammar
-- demanded a comparison on every condition. It no longer does, and the taxed
-- spelling is now an authoring error rather than a second way to say the same
-- thing -- because the corpus would otherwise hold both, and because the numeric
-- dress invited shapes that should not exist: `tagged:x@y < 1` was in a shipped
-- game where `not_tagged:x@y` is the word for it.
function M.test_conditions_a_question_is_written_on_its_own(check)
	local predicate = require("predicate")
	local validate = require("validate")
	local declaration = require("declaration")

	local bare = predicate.parse_condition("tagged:pawn@behind")
	check("a yes/no fn needs no comparison", bare ~= nil)
	check("and compiles to the shape the comparison had, so nothing below learns "
		.. "that booleans exist", bare and bare.op == ">=" and bare.right.n == 1,
		bare and (bare.op .. "/" .. tostring(bare.right.n)))

	-- The refusal has to be narrow: a count is a number and still says what it
	-- is being compared to. "At least one" is a real thing to write.
	check("a counting form on its own is still an error",
		predicate.parse_condition("count:gem@mine.hand") == nil)
	check("and so is a bare stat, which would otherwise read as a stat worth nothing",
		predicate.parse_condition("gold") == nil)
	check("while a real comparison is untouched",
		predicate.parse_condition("gold >= 3") ~= nil)

	with_game(function(name)
		local G = declaration.parse(name)
		G.card_defs.one_gate.needs = { "tagged:beast@board >= 1" }
		local said = table.concat(validate.check(G), "; ")
		check("the taxed spelling is reported", said:find("compares a question to a number", 1, true), said)
		check("and the message shows the spelling to use instead",
			said:find("tagged:beast@board\"", 1, true), said)
	end)
end

-- **A quantifier that orders rather than narrows.** It says what order the pool
-- is in and nothing about how many of it is meant, which is what lets a consumer
-- keep its own count: one takes the first, four take the first four.
function M.test_conditions_a_pool_may_be_put_in_order(check)
	with_game(function(name)
		flow.init(name, 3)
		local board = zones.find("board")
		local a, b = entity.get(board.cards[1]), entity.get(board.cards[2])
		a.stats.hp, b.stats.hp = 7, 4

		local function order(scope)
			local sc = predicate.parse_scope(scope)
			local out = {}
			for _, e in ipairs(predicate.entities_in_scope(sc.name, {}, sc.owner, sc.quant)) do
				out[#out + 1] = e.id
			end
			return out
		end
		-- The board also holds a ghost carrying no hp at all, which reads nought
		-- and so sorts to the front of "lowest" and the back of "highest".
		local low, high = order("lowest:hp.board"), order("highest:hp.board")
		check("the one with no number at all comes first", low[1] ~= a.id and low[1] ~= b.id,
			tostring(low[1]))
		check("then the smaller of the two", low[2] == b.id, tostring(low[2]))
		check("and the larger last", low[3] == a.id, tostring(low[3]))
		check("highest reads the other way", high[1] == a.id and high[2] == b.id)
		a.stats.hp = 1
		check("and it follows the numbers", order("lowest:hp.board")[2] == a.id)

		-- The order is the whole of what it says: everything is still named.
		local sc = predicate.parse_scope("lowest:hp.board")
		check("the pool is the same pool",
			#predicate.entities_in_scope(sc.name, {}, sc.owner, sc.quant)
			== #predicate.entities_in_scope("board", {}, nil, "any"))
	end)
end

-- A scope keeps reading as a scope: an owner word and a zone still follow, and
-- the sort carries its own number in front of them.
function M.test_conditions_ordering_combines_with_owner_and_zone(check)
	local p = predicate.parse_scope("lowest:tier.enemy.patrol.unit")
	check("the quantifier keeps its number", p.quant == "lowest:tier", tostring(p.quant))
	check("the owner word is still read", p.owner == "enemy", tostring(p.owner))
	check("and so is the zone, narrowed by a tag", p.name == "patrol.unit", tostring(p.name))
	check("a plain quantifier is untouched", predicate.parse_scope("each.mine.unit").quant == "each")
	check("and a word with a colon that is not a sort is not one",
		predicate.parse_scope("random.beast").quant == "random")
end

return M
