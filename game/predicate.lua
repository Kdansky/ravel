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
--
-- The words are separated by "." because ":" cannot be: action strings are
-- split on colons (actions.lua), so "hp@each:follower" would arrive as two
-- arguments.
local FNS    = { count = true, card = true, sum = true, max = true }
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
	local c = ctx and ctx.card_id and entity.get(ctx.card_id)
	if not (c and c.slot_id) then return {} end
	return geometry.reach(c.slot_id, pat,
		geometry.facing(tags.owner_of(c) or zones.active_seat(),
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
		-- No scope means "mine": the cards this player's stats live on, plus
		-- the engine's own card behind them. A bare subject has always meant
		-- the player's total; it now names the cards that hold it, so a read
		-- and a write can no longer disagree about which one that is.
		local seen = {}
		for _, id in ipairs(tags.find_targets({ "player" }, { grid = true })) do
			seen[id]     = true
			out[#out + 1] = entity.get(id)
		end
		for _, id in ipairs((zones.find("system") or {}).cards or {}) do
			if not seen[id] then out[#out + 1] = entity.get(id) end
		end
	elseif scope == "all" then
		for e in entity.each() do out[#out + 1] = e end
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
		reaching = false
		-- The owner word was spent on choosing the pieces, so it must not be
		-- spent again on what they threaten.
		return out
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

function M.total(subject, ctx)
	local p = M.parse_subject(subject)
	if not p then return 0 end

	-- The counting forms keep their shipped meaning without a scope: "in play",
	-- which is wider than the player's own cards. A bare stat falls through to
	-- the default scope below.
	if not p.scope then
		if p.fn == "count" then
			return #tags.find_targets({ p.arg }, { grid = true })
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
	elseif p.fn == "card" then
		local n = 0
		for _, e in ipairs(ents) do if e.def_key == p.arg then n = n + 1 end end
		return n
	end

	local sum, best = 0, 0
	for _, e in ipairs(M.bearers(p, ctx, ents)) do
		local v = tonumber(e.stats[p.arg]) or 0
		sum = sum + v
		if v > best then best = v end
	end
	return p.fn == "max" and best or sum
end

-- What a comparison is measured against: a number, or another subject. JSON
-- and Lua both carry either happily, so the type decides at run time — which
-- is what lets a card compare itself to what it is being played onto
-- ({ "at_least": "max:value@mine.red" }) instead of only to a constant.
--
-- A subject here must *look* like one — it has to name a scope or a measuring
-- fn. A bare word is a typo, not a reading of zero: without that rule every
-- misspelling would quietly compare against 0 and pass, which is precisely the
-- silent-wrong-answer this file's fail-closed discipline exists to prevent.
local function bound(x, ctx)
	local n = tonumber(x)
	if n then return n end
	if type(x) ~= "string" then return nil end
	local p = M.parse_subject(x)
	if not (p and (p.scope or p.fn)) then return nil end
	return M.total(x, ctx)
end

local function compare(v, cond, ctx)
	if cond.equals   ~= nil then local n = bound(cond.equals, ctx);   return n ~= nil and v == n end
	if cond.at_least ~= nil then local n = bound(cond.at_least, ctx); return n ~= nil and v >= n end
	if cond.at_most  ~= nil then local n = bound(cond.at_most, ctx);  return n ~= nil and v <= n end
	return false
end

-- { "stat": "hp", "equals": 0 } with equals / at_least / at_most,
-- or { "zone_empty": ["road", "hand"] } (all listed zones empty).
function M.met(cond, ctx)
	if type(cond) ~= "table" then return false end
	if cond.zone_empty then
		if type(cond.zone_empty) ~= "table" then return false end
		for _, zk in ipairs(cond.zone_empty) do
			local z = type(zk) == "string" and zones.find(zk)
			if not z or #z.cards > 0 then return false end
		end
		return true
	end
	-- "each" asks of every member; anything else asks of the pool. The fn
	-- forms are aggregates already, so they always read the pool. An empty
	-- scope fails rather than passing vacuously, or a cost would be free
	-- exactly when nothing can pay it.
	local p = M.parse_subject(cond.stat)

	-- **A stat nobody carries is absent, not zero**, and every comparison
	-- against it fails. Reading a missing value as 0 is C's mistake and it is
	-- not repeated here: Lua tells nil from 0 and so does this vocabulary.
	-- Without it "this rook has never moved" is true of a rook captured twenty
	-- moves ago, because a sum over nobody is zero — a gate that opens exactly
	-- when the thing it guards no longer exists.
	--
	-- The counting forms are exempt, and must be: no farms really is a count of
	-- zero, and "these squares are empty" is written that way. `sum:`/`max:` are
	-- exempt too — they are asked *of a pool*, and the measure of an empty pool
	-- is honestly 0.
	if p and p.fn == nil and #M.bearers(p, ctx) == 0 then return false end

	if p and p.quant == "each" and p.fn == nil then
		local ents = M.entities_in_scope(p.scope, ctx, p.owner)
		if #ents == 0 then return false end
		for _, e in ipairs(ents) do
			if not compare(tonumber((e.stats or {})[p.arg]) or 0, cond, ctx) then return false end
		end
		return true
	end
	return compare(M.total(cond.stat, ctx), cond, ctx)
end

-- Map form { subject = n, ... }: each entry is "this subject, at least n" —
-- much the commonest thing to ask, so a bare number keeps meaning exactly
-- that. When you need the other direction, the value is a comparison instead:
-- { "max:value@mine.red": { "at_most": 6 } } is how a card says it may only be
-- played on a lower one.
function M.meets_all(map, ctx)
	if type(map) ~= "table" then return true end
	for subject, n in pairs(map) do
		local cond
		if type(n) == "table" then
			cond = { stat = subject, equals = n.equals,
				at_least = n.at_least, at_most = n.at_most }
		else
			cond = { stat = subject, at_least = tonumber(n) }
		end
		if not M.met(cond, ctx) then return false end
	end
	return true
end

return M
