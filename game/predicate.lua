-- The one condition vocabulary, shared by phase routing, end conditions,
-- challenge requires, card needs and cost keys. The subject grammar it all
-- runs on is documented below.

local entity      = require("entity")
local zones       = require("zones")
local tags        = require("tags")
local geometry    = require("geometry")
local declaration = require("declaration")

local M = {}

-- Subject grammar:  [<fn>:]<arg>[@<scope expression>]
-- Scope expression:  [<quant>.][<owner>.]<zone-or-tag>
--
--   gold                    a stat on the player's own cards
--   insight@player          the stat on cards carrying the "player" tag
--   hp@each.follower        every follower, individually
--   hp@random.follower      one follower, chosen by the seeded RNG
--   hp@each.enemy.creature  every creature an opponent owns
--   hp@self                 the acting card
--   hp@target               the cards the player chose for this card
--   count:farm@board        the fn forms take a scope too
--   count:gem@everywhere    every card, hands and decks included (opt-in)
--   min:value@mine.hand     the smallest one, over the cards that carry it
--   score@owner_of.target   the seats owning the cards chosen — see below
--
-- The words are separated by "." because ":" cannot be: action strings are
-- split on colons (actions.lua), so "hp@each:follower" would arrive as two
-- arguments.
-- "tagged" and "not_tagged" answer a yes/no about a scope and are written as
-- 1 or 0, because a condition compares numbers. They exist because asking
-- "is there a pawn on that square" by counting to one reads like arithmetic
-- about a question that has no arithmetic in it.
-- "saved" is the same yes/no shape asked of the machine rather than of a card:
-- is there a game in that slot. It cannot be answered here — the save layer is
-- outside the engine and nothing in here may require it — so it arrives through
-- M.saved_slot below, and a build without one truthfully answers no.
local FNS    = { count = true, card = true, sum = true, max = true, min = true,
	tagged = true, not_tagged = true, saved = true }
local QUANTS = { any = true, each = true, random = true }
local OWNERS = { mine = true, enemy = true, anyone = true }

-- A scope expression: [<quant>.][<owner>.]<zone-or-tag>. It is the part after
-- "@" in a subject, and it also stands alone as an action's zone argument, so
-- "destroy:each.enemy.creature" and "hp@each.enemy.creature" read the same.
-- Leading words are taken while they are known, in either order; whatever is
-- left is the name, so a tag really called "each" is still reachable as the
-- last word. Pure — no game state — so it is testable on its own.
function M.parse_scope(s)
	if type(s) ~= "string" or s == "" then return nil end
	local quant, owner, rest = nil, nil, s
	for _ = 1, 2 do
		local word, tail = rest:match("^([%w_]+)%.(.+)$")
		if not word then break end
		if QUANTS[word] and not quant then quant, rest = word, tail
		elseif OWNERS[word] and not owner then owner, rest = word, tail
		else break end
	end
	if rest == "" then return nil end
	-- Choosing two targets means both of them; a tag that happens to match
	-- several cards means the pool. Different defaults because they are
	-- different intents, not an inconsistency.
	return { quant = quant or (rest == "target" and "each" or "any"),
		owner = owner, name = rest }
end

function M.parse_subject(s)
	if type(s) ~= "string" then return nil end
	local left, right = s:match("^([^@]*)@(.*)$")
	if not left then left = s end
	if left == "" then return nil end

	local fn, arg = left:match("^([%w_]+):(.+)$")
	if not (fn and FNS[fn]) then fn, arg = nil, left end

	local sc = right and right ~= "" and M.parse_scope(right) or nil
	return { fn = fn, arg = arg,
		quant = sc and sc.quant, owner = sc and sc.owner, scope = sc and sc.name }
end

-- Everything below reads attacker-suppliable content (routing conditions,
-- end_conditions, requires/needs maps, cost keys) and must never let a
-- malformed value (wrong type, missing) reach a raw Lua comparison or
-- arithmetic op — that throws an uncaught error and kills the process.
-- Every subject and threshold is coerced or type-checked before use; anything
-- that doesn't check out fails the condition rather than crashing.

-- Whose piece a card is (see tags.owner_of). Re-exported so that ownership has
-- one name everywhere conditions are written about.
--
-- A card with no owner at all still filters by nothing, which is why "mine"
-- must never come to mean "mine or unowned" — the ambiguity this vocabulary
-- exists to avoid.
M.owner_of = tags.owner_of

-- Who a card answers for when a condition asks. As owner_of, except that a seat
-- card answers with its own key — that is what makes "score@mine" find the
-- active seat's own stat bag.
function M.seat_of(e)
	local G = declaration.G
	if e and G.seat_set and G.seat_set[e.def_key] then return e.def_key end
	return M.owner_of(e)
end

local function owned_by(e, owner, active)
	if owner == nil or owner == "anyone" then return true end
	local seat = M.seat_of(e)
	if owner == "mine" then return seat ~= nil and seat == active end
	return seat ~= nil and seat ~= active
end

-- The squares a named pattern picks out. Absolute patterns name a board (or
-- take the only one); relative patterns are anchored on the acting card, and
-- name nothing when it is not standing on a square.
function M.pattern_slots(name, ctx)
	local pat = (declaration.G.pattern_defs or {})[name]
	if not pat then return {} end
	if pat.absolute then
		local z = pat.zone and zones.find(pat.zone) or zones.sole_grid()
		return geometry.squares(pat, z)
	end
	-- Usually anchored on the acting card; a move rule asking about a square it
	-- is *considering* anchors on that square instead. Facing still comes from
	-- the mover, so "behind" means behind from where they are looking whichever
	-- square is being asked about.
	local c = ctx and ctx.card_id and entity.get(ctx.card_id)
	local from = ctx and ctx.anchor or (c and c.slot_id)
	if not from then return {} end
	return geometry.reach(from, pat,
		geometry.facing(c and tags.owner_of(c) or zones.active_seat(),
			declaration.G.seat_list or {}))
end

-- Turn a scope into the entities it means. The single place that decides, so
-- reads, costs and effects can never disagree about who "@player" is.
-- A move rule may carry a `needs`, and a `needs` may name a scope, so a rule
-- asking what its own side threatens would ask again while still being asked.
-- The circle names nothing rather than hanging.
local reaching = false

function M.entities_in_scope(scope, ctx, owner)
	local out = {}
	if scope == nil then
		-- No scope means "mine": the card this player's stats live on, plus the
		-- engine's own card behind it. A bare subject has always meant the
		-- player's total; it names the cards that hold it, so a read and a write
		-- can no longer disagree about which one that is.
		--
		-- **The active seat's, and only theirs.** Said without the filter this
		-- was the *pool* of every seat's copy of the stat — so a two-seat game
		-- checked a cost against both players' mana added together and then took
		-- it off whichever seat came first in the file, and one player could buy
		-- a card out of the other's gems. A solo game cannot see it, which is why
		-- it survived this long. A seatless game has no active seat and every
		-- player card answers to nobody, so it is unchanged.
		local active, seen = zones.active_seat(), {}
		for _, id in ipairs(tags.find_targets({ "player" }, { grid = true })) do
			local e = entity.get(id)
			seen[id] = true
			if M.seat_of(e) == active then out[#out + 1] = e end
		end
		for _, id in ipairs((zones.find("system") or {}).cards or {}) do
			if not seen[id] then out[#out + 1] = entity.get(id) end
		end
	elseif scope == "all" then
		for e in entity.each() do out[#out + 1] = e end
	elseif scope == "everywhere" then
		-- Every card, in whatever zone it sits — a hand, a deck, a pile or the
		-- board. The deliberate opposite of a bare tag, which sees the board
		-- alone: most rules must not read a hand they cannot see, so grid-only
		-- stays the default and this is the word that says "look in the hidden
		-- zones too, on purpose". `all` above is wider still and takes every
		-- entity of every kind; this takes cards, so a measuring fn always has
		-- something with a stat to read. The owner word narrows it as it does
		-- anywhere else, so "count:gem@mine.everywhere" is one seat's gems
		-- wherever they are — the one search a named zone cannot do, because it
		-- would have to name every zone a card might be in.
		for e in entity.each("card") do out[#out + 1] = e end
	elseif scope == "self" then
		local e = ctx and ctx.card_id and entity.get(ctx.card_id)
		if e then out[1] = e end
	elseif scope == "target" then
		for _, id in ipairs(ctx and ctx.targets or {}) do
			local e = entity.get(id)
			if e then out[#out + 1] = e end
		end
	elseif scope == "reach" then
		-- Where a set of pieces could move, answered as the things standing
		-- there. The owner word picks *whose* pieces are asked rather than what
		-- comes back: "@enemy.reach" is every square my opponent could move
		-- onto, and my king turning up among the answers is what check means.
		--
		-- Nothing here knows what an attack is. A piece may only land on an
		-- occupied square if its own move says so — a pawn's step is
		-- "fill": "empty" and its take is "fill": "enemy" — so the line between
		-- moving and threatening is one the game file has already drawn, and
		-- this only adds it up.
		if reaching then return out end
		reaching = true
		-- Put the latch back even when the body raises. Left standing, it does
		-- not crash anything — it answers *empty* to every later reach question,
		-- so chess quietly stops seeing check and the game plays on saying
		-- nothing is wrong. A silent wrong answer for the rest of the session is
		-- worse than the error that caused it, which is the same reason
		-- zones.as_seat is written this way.
		local ok, err = pcall(function()
			local active, seen = zones.active_seat(), {}
			local targeting = require("targeting")
			for e in entity.each("card") do
				if e.slot_id and owned_by(e, owner, active) then
					for _, sid in ipairs(targeting.moves_of(e.id)) do
						if not seen[sid] then
							seen[sid] = true
							local occ = entity.get(sid).occupant
							if occ then out[#out + 1] = entity.get(occ) end
						end
					end
				end
			end
		end)
		reaching = false
		if not ok then error(err, 0) end
		-- The owner word was spent on choosing the pieces, so it must not be
		-- spent again on what they threaten.
		return out
	elseif scope == "owner_of" or (type(scope) == "string" and scope:sub(1, 9) == "owner_of.") then
		-- Whose these are, answered as the seats themselves: "@owner_of.target"
		-- is the seat holding the card the player pointed at, so a rule can pay
		-- the *owner* of something without knowing which chair that is. On its
		-- own the word means the acting card's own seat, which is the commonest
		-- one to ask about and the one a card can never name otherwise.
		--
		-- A prefix rather than a word of its own, because it takes an argument
		-- and the words after "@" are separated by "." — a colon would arrive as
		-- a second action argument (actions.lua). What follows it is an ordinary
		-- scope expression, quantifier and owner word included.
		--
		-- **An owner word means whichever side of the prefix it is written on.**
		-- Inside, it picks the cards: "@owner_of.enemy.creature" is the seats an
		-- opponent's creatures answer for. Before it, it filters the seats that
		-- come back, which the tail of this function does: "@mine.owner_of.target"
		-- is the target's owner, when that owner is me. Each word sits beside
		-- what it is about, so neither reading has to be remembered.
		--
		-- It answers with `seat_of` rather than `owner_of`, which is what
		-- "mine"/"enemy" ask (`owned_by`): the two can then never disagree about
		-- whose a card is, and a seat card asked about itself answers itself
		-- rather than nobody.
		local inner = M.parse_scope(scope == "owner_of" and "self" or scope:sub(10))
		if not inner then return out end
		local seats, cards = declaration.G.seat_set or {}, {}
		for e in entity.each("card") do
			if seats[e.def_key] and e.zone_id then cards[e.def_key] = e end
		end
		local seen = {}
		for _, e in ipairs(M.entities_in_scope(inner.name, ctx, inner.owner)) do
			local key = M.seat_of(e)
			if key and cards[key] and not seen[key] then
				seen[key] = true
				out[#out + 1] = cards[key]
			end
		end
	elseif (declaration.G.pattern_defs or {})[scope] then
		-- A pattern names a shape, and a shape answers "what is standing there"
		-- as readily as "where may I go" — so the same word serves a move and a
		-- condition. An absolute pattern names squares outright, which is how
		-- "these cells are empty" is asked without a condition of its own:
		-- { "count:piece@castle_path": { "equals": 0 } }. A relative one is
		-- anchored on the acting card, which is a neighbourhood.
		for _, sid in ipairs(M.pattern_slots(scope, ctx)) do
			local occ = entity.get(sid).occupant
			if occ then out[#out + 1] = entity.get(occ) end
		end
	else
		-- A zone key reaches every instance of it — both arenas, not just the
		-- active seat's. Narrowing to one is what the owner word is for, and a
		-- set may be wide where a destination may not.
		local instances = zones.all_with_key(scope)
		if #instances > 0 then
			for _, z in ipairs(instances) do
				for _, id in ipairs(z.cards) do
					local e = entity.get(id)
					if e then out[#out + 1] = e end
				end
			end
		else
			-- A tag means the cards in play carrying it — grid zones only,
			-- exactly what bare "count:<tag>" has always meant. A card in hand
			-- is not on the board and must not be reachable by "@beast"; name
			-- the zone (@hand) when that is what you want.
			for _, id in ipairs(tags.find_targets({ scope }, { grid = true })) do
				out[#out + 1] = entity.get(id)
			end
		end
	end
	if owner == nil then return out end
	local active, kept = zones.active_seat(), {}
	for _, e in ipairs(out) do
		if owned_by(e, owner, active) then kept[#kept + 1] = e end
	end
	return kept
end

-- Entities in a subject's scope that actually carry its stat. Filtering here
-- matters: a change would otherwise invent the stat on a card that never had
-- one, so "every beast loses hp" cannot give hp to something without it.
-- Pass `ents` when the caller has already resolved the scope.
function M.bearers(p, ctx, ents)
	local out = {}
	for _, e in ipairs(ents or M.entities_in_scope(p.scope, ctx, p.owner)) do
		if e.stats and e.stats[p.arg] ~= nil then out[#out + 1] = e end
	end
	return out
end

-- True when a subject is scoped to targets the player has not chosen yet, so
-- it cannot be judged. ctx.targets nil means "not asked yet" (the gates that
-- dim a card run before targeting); an empty list means "chose none".
function M.awaits_targets(subject, ctx)
	local p = M.parse_subject(subject)
	return p ~= nil and p.scope == "target" and (ctx == nil or ctx.targets == nil)
end

-- hook(slot) -> boolean, set by save.lua when it is loaded.
M.saved_slot = nil

function M.total(subject, ctx)
	-- A compute the ability bound before it ran. Checked first because it is a
	-- name and not a measurement: nothing about the board answers it.
	local bound = ctx and ctx.let and ctx.let[subject]
	if bound then return bound end
	local p = M.parse_subject(subject)
	if not p then return 0 end

	if p.fn == "saved" then
		return (M.saved_slot and M.saved_slot(p.arg)) and 1 or 0
	end

	-- The counting forms keep their shipped meaning without a scope: "in play",
	-- which is wider than the player's own cards. A bare stat falls through to
	-- the default scope below.
	if not p.scope then
		if p.fn == "count" then
			return #tags.find_targets({ p.arg }, { grid = true })
		elseif p.fn == "tagged" or p.fn == "not_tagged" then
			local any = #tags.find_targets({ p.arg }, { grid = true }) > 0
			return (p.fn == "tagged") == any and 1 or 0
		elseif p.fn == "card" then
			local n = 0
			for _, id in ipairs(tags.find_targets({}, { grid = true })) do
				if entity.get(id).def_key == p.arg then n = n + 1 end
			end
			return n
		end
	end

	local ents = M.entities_in_scope(p.scope, ctx, p.owner)
	if p.fn == "count" then
		local n = 0
		for _, e in ipairs(ents) do if tags.entity_has(e, p.arg) then n = n + 1 end end
		return n
	elseif p.fn == "tagged" or p.fn == "not_tagged" then
		-- Any of them, and its exact complement: an empty scope has nothing
		-- tagged, so it answers no to the first and yes to the second.
		local any = false
		for _, e in ipairs(ents) do
			if tags.entity_has(e, p.arg) then any = true; break end
		end
		return (p.fn == "tagged") == any and 1 or 0
	elseif p.fn == "card" then
		local n = 0
		for _, e in ipairs(ents) do if e.def_key == p.arg then n = n + 1 end end
		return n
	end

	local sum, best, least = 0, 0, nil
	for _, e in ipairs(M.bearers(p, ctx, ents)) do
		local v = tonumber(e.stats[p.arg]) or 0
		sum = sum + v
		if v > best then best = v end
		if least == nil or v < least then least = v end
	end
	if p.fn == "max" then return best end
	-- A pool with nothing in it has no smallest thing, and answering 0 would put
	-- one *below* everything rather than beside nothing. Callers that need a
	-- number get one; a condition asks through measure(), which reads the empty
	-- pool as absent and so fails every comparison.
	if p.fn == "min" then return least or 0 end
	return sum
end

-- A `computes` entry's `from`: "<term>", or "<term> <op> <term>" with one of
-- + - *, spaces required around the operator. A term is a number or a subject.
--
-- **One operator, and no parentheses**, which is the same cap a condition keeps
-- for the same reason: with one there is no precedence to remember, and with two
-- there is a rule a reader has to be taught and cannot check. n-ary addition
-- already has a spelling — successive stat_gain lines onto one stat — so what is
-- missing here is subtraction into a value slot, and that is exactly one
-- operator.
--
-- Pure grammar, so it splits without a game loaded and the validator reads one
-- at authoring time.
local ARITH = {
	["+"] = function(a, b) return a + b end,
	["-"] = function(a, b) return a - b end,
	["*"] = function(a, b) return a * b end,
}

local split = {}

function M.parse_value(s)
	if type(s) ~= "string" or s:match("^%s*$") then return nil, "a compute needs a \"from\"" end
	local hit = split[s]
	if hit == nil then
		local l, op, r = s:match("^%s*(.-)%s+([%+%-%*])%s+(.-)%s*$")
		if not l then
			hit = { left = s:match("^%s*(.-)%s*$") }
		elseif r:find("[%+%-%*]%s") or r:match("^%s*$") then
			hit = { err = "one operator per compute — say the rest in a second one" }
		else
			hit = { left = l, op = op, right = r }
		end
		if not hit.err then
			for _, side in ipairs({ hit.left, hit.right }) do
				if tonumber(side) == nil and not M.parse_subject(side) then
					hit = { err = "'" .. side .. "' is not a number and not something the engine can measure" }
					break
				end
			end
		end
		split[s] = hit
	end
	if hit.err then return nil, hit.err end
	return hit
end

local function measure_term(s, ctx)
	return tonumber(s) or M.total(s, ctx)
end

function M.value(s, ctx)
	local v = M.parse_value(s)
	if not v then return 0 end
	local n = measure_term(v.left, ctx)
	if v.op then n = ARITH[v.op](n, measure_term(v.right, ctx)) end
	return n
end

-- Work the named computes out and hand back a ctx carrying them. Evaluated in
-- the order the ability lists them, each seeing the ones before it — which is
-- what makes "the line above ran first" the whole of the dependency rule, with
-- no graph to walk and no cycle to find.
--
-- The original ctx is never written to: an ability's bindings are its own, and
-- one that runs inside another's action list must not inherit or overwrite them.
function M.bind(names, ctx)
	if type(names) ~= "table" or #names == 0 then return ctx end
	local out = { let = {} }
	for k, v in pairs(ctx or {}) do out[k] = v end
	for k, v in pairs((ctx or {}).let or {}) do out.let[k] = v end
	for _, name in ipairs(names) do
		local def = declaration.G.compute_defs[name]
		if def then out.let[name] = M.value(def.from, out) end
	end
	return out
end

-- A condition written as one string: "<subject> <op> <number-or-subject>".
--
-- Pure, exactly as parse_subject above it is — a string in, a table out, no game
-- state and nothing loaded — so the validator reads one at authoring time and
-- the runtime compiles each exactly once. It is a *spelling* for the comparison
-- the engine already evaluates and not a second vocabulary: both operands are
-- the subject grammar unchanged, which is what keeps one condition language
-- rather than two.
--
-- **One comparison per string, and no boolean operators.** "and" is what a list
-- of conditions already means, and "or" is two abilities — which the card
-- grammar has. Anything past that is a program, and the format's whole schema
-- section exists to refuse one.
local COMPARE = {
	[">="] = function(a, b) return a >= b end,
	["<="] = function(a, b) return a <= b end,
	[">"] = function(a, b) return a > b end,
	["<"] = function(a, b) return a < b end,
	["=="] = function(a, b) return a == b end,
	["!="] = function(a, b) return a ~= b end,
}

local function operand(s)
	local n = tonumber(s)
	if n then return { n = n } end
	local p = M.parse_subject(s)
	return p and { subject = p, src = s } or nil
end

-- Parsed once per distinct string. The set is bounded by the game file, which
-- is why this may be a plain table rather than something that forgets: a peer's
-- game text is parsed through the same door and is one file's worth of strings.
local compiled = {}

local function compile(s)
	local left, op, right = s:match("^%s*(.-)%s*([<>=!]=?)%s*(.-)%s*$")
	if not left then
		return nil, "should be a comparison, like \"gold >= 3\""
	end
	if COMPARE[op] == nil then
		return nil, "'" .. op .. "' is not a comparison — write >=, <=, >, <, == or !="
	end
	if left == "" or right == "" then
		return nil, "a comparison needs something on both sides of '" .. op .. "'"
	end
	if right:find("[<>=!]") then
		return nil, "one comparison per condition — two of them are two entries"
	end
	local l, r = operand(left), operand(right)
	if not l then return nil, "'" .. left .. "' is not something the engine can measure" end
	if not r then return nil, "'" .. right .. "' is not something the engine can measure" end
	-- The rule bound() keeps for the struct form, kept here at the door instead:
	-- a bare word on the right would read as an unknown stat worth nothing and
	-- quietly pass, so it is a typo until it says which cards it means.
	if r.subject and not (r.subject.scope or r.subject.fn) then
		return nil, "'" .. right .. "' is a bare word, so it would read as a stat worth nothing — "
			.. "write a number, or say which cards you mean (\"value@target\", \"max:value@mine.red\")"
	end
	return { left = l, op = op, right = r, src = s }
end

function M.parse_condition(s)
	if type(s) ~= "string" then return nil, "a condition is written as a string" end
	local hit = compiled[s]
	if not hit then
		local ast, err = compile(s)
		hit = { ast = ast, err = err }
		compiled[s] = hit
	end
	return hit.ast, hit.err
end

-- What an operand measures, or nil for "absent".
--
-- **A stat nobody carries is absent, not zero**, and every comparison against it
-- fails. Reading a missing value as 0 is C's mistake and it is not repeated
-- here: Lua tells nil from 0 and so does this vocabulary. Without it "this rook
-- has never moved" is true of a rook captured twenty moves ago, because a sum
-- over nobody is zero — a gate that opens exactly when the thing it guards no
-- longer exists.
--
-- The counting forms are exempt, and must be: no farms really is a count of
-- zero, and "these squares are empty" is written that way. `sum:`/`max:` are
-- exempt too — they are asked *of a pool*, and the measure of an empty pool is
-- honestly 0: nothing adds to nothing, and nothing is at most nothing.
--
-- **`min:` is not exempt**, and it is the one place the pool rule and the
-- absent rule disagree. Nothing is not *at least* nothing — a zero answer would
-- sit below every real value, so "the lowest card of this colour I hold" would
-- read as beating everything precisely when the colour is not in the hand. An
-- empty pool has no smallest member, which is absence, so it fails every
-- comparison exactly as a stat nobody carries does.
local function measure(o, ctx)
	if o.n then return o.n end
	if ctx and ctx.let and ctx.let[o.src] then return ctx.let[o.src] end
	local p = o.subject
	local pooled = p.fn == nil or p.fn == "min"
	if pooled and #M.bearers(p, ctx) == 0 then return nil end
	return M.total(o.src, ctx)
end

function M.holds(c, ctx)
	if type(c) == "string" then c = M.parse_condition(c) end
	if type(c) ~= "table" or not COMPARE[c.op or ""] then return false end
	local r = measure(c.right, ctx)
	if r == nil then return false end

	local p = c.left.subject
	if p and p.fn == nil and p.quant == "each" then
		local ents = M.entities_in_scope(p.scope, ctx, p.owner)
		if #ents == 0 or #M.bearers(p, ctx, ents) == 0 then return false end
		for _, e in ipairs(ents) do
			if not COMPARE[c.op](tonumber((e.stats or {})[p.arg]) or 0, r) then return false end
		end
		return true
	end
	local l = measure(c.left, ctx)
	return l ~= nil and COMPARE[c.op](l, r)
end

-- A routing entry or an end condition: { "when": "hp == 0" }, or
-- { "zone_empty": ["road", "hand"] } (all listed zones empty), which is the one
-- question the comparison grammar cannot ask — no subject counts a zone's cards
-- regardless of what they are.
function M.met(cond, ctx)
	if type(cond) == "string" then return M.holds(cond, ctx) end
	if type(cond) ~= "table" then return false end
	if cond.when ~= nil then return M.holds(cond.when, ctx) end
	if type(cond.zone_empty) ~= "table" then return false end
	for _, zk in ipairs(cond.zone_empty) do
		local z = type(zk) == "string" and zones.find(zk)
		if not z or #z.cards > 0 then return false end
	end
	return true
end

-- Every condition in the list holds. A list rather than a map keyed by subject,
-- because such a map cannot hold one subject twice — "gold >= 3" with
-- "gold <= 8" is a range, which is an ordinary thing to want.
function M.meets_all(list, ctx)
	if type(list) ~= "table" then return true end
	for _, s in ipairs(list) do
		if not M.holds(s, ctx) then return false end
	end
	return true
end

return M
