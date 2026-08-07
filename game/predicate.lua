-- The one condition vocabulary, shared by phase routing, end conditions,
-- challenge requires, card needs and cost keys. The subject grammar it all
-- runs on is documented below.

local entity      = require("entity")
local zones       = require("zones")
local tags        = require("tags")
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

-- Whose card this is: the seat of the zone it sits in. A card in a shared zone
-- has no owner, which is why an unqualified scope filters by nothing — "mine"
-- would otherwise have to mean "mine or unowned", and that special case is
-- exactly what this vocabulary exists to avoid.
local function owned_by(e, owner, active)
	if owner == nil or owner == "anyone" then return true end
	local z = e.zone_id and entity.get(e.zone_id)
	local seat = z and z.seat
	if declaration.G.seat_set and declaration.G.seat_set[e.def_key] then
		seat = e.def_key
	end
	if owner == "mine" then return seat ~= nil and seat == active end
	return seat ~= nil and seat ~= active
end

-- Turn a scope into the entities it means. The single place that decides, so
-- reads, costs and effects can never disagree about who "@player" is.
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

local function compare(v, cond)
	if cond.equals   ~= nil then local n = tonumber(cond.equals);   return n ~= nil and v == n end
	if cond.at_least ~= nil then local n = tonumber(cond.at_least); return n ~= nil and v >= n end
	if cond.at_most  ~= nil then local n = tonumber(cond.at_most);  return n ~= nil and v <= n end
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
	if p and p.quant == "each" and p.fn == nil then
		local ents = M.entities_in_scope(p.scope, ctx, p.owner)
		if #ents == 0 then return false end
		for _, e in ipairs(ents) do
			if not compare(tonumber((e.stats or {})[p.arg]) or 0, cond) then return false end
		end
		return true
	end
	return compare(M.total(cond.stat, ctx), cond)
end

-- Map form { subject = n, ... }: each entry is "this subject, at least n".
function M.meets_all(map, ctx)
	if type(map) ~= "table" then return true end
	for subject, n in pairs(map) do
		if not M.met({ stat = subject, at_least = tonumber(n) }, ctx) then return false end
	end
	return true
end

return M
