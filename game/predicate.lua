-- The one condition vocabulary, shared by phase routing, end conditions,
-- challenge requires and card needs. Subjects are stat keys,
-- "count:<tag>" (cards on grid zones with that tag), or
-- "card:<key>" (instances of that template on grid zones).

local entity = require("entity")
local zones  = require("zones")
local tags   = require("tags")

local M = {}

-- Subject grammar:  [<fn>:]<arg>[@[<quant>.]<scope>]
--
--   gold                 a stat, summed over everything (unchanged)
--   insight@player       the stat on cards carrying the "player" tag
--   hp@each.follower     every follower, individually
--   hp@random.follower   one follower, chosen by the seeded RNG
--   hp@self              the acting card
--   hp@target            the cards the player chose for this card
--   count:farm@board     the fn forms take a scope too
--
-- The quantifier is separated by "." because ":" cannot be: action strings are
-- split on colons (actions.lua), so "hp@each:follower" would arrive as two
-- arguments. Parsing is pure — no game state — so it is testable on its own.
local FNS    = { count = true, card = true, sum = true, max = true }
local QUANTS = { any = true, each = true, random = true }

function M.parse_subject(s)
	if type(s) ~= "string" then return nil end
	local left, right = s:match("^([^@]*)@(.*)$")
	if not left then left = s end
	if left == "" then return nil end

	local fn, arg = left:match("^([%w_]+):(.+)$")
	if not (fn and FNS[fn]) then fn, arg = nil, left end

	local quant, scope
	if right and right ~= "" then
		local q, rest = right:match("^([%w_]+)%.(.+)$")
		if q and QUANTS[q] then
			quant, scope = q, rest
		else
			scope = right
		end
		-- Choosing two targets means both of them; choosing a tag that happens
		-- to match several cards means the pool. Different defaults because
		-- they are different intents, not an inconsistency.
		quant = quant or (scope == "target" and "each" or "any")
	end
	return { fn = fn, arg = arg, quant = quant, scope = scope }
end

-- All three functions below read attacker-suppliable content (routing
-- conditions, end_conditions, requires/needs maps) and must never let a
-- malformed value (wrong type, missing) reach a raw Lua comparison or
-- arithmetic op — that throws an uncaught error and kills the process.
-- Every subject/threshold is coerced or type-checked before use; anything
-- that doesn't check out fails the condition rather than crashing.
-- Turn a scope name into the entities it means. The single place that decides,
-- so reads, costs and effects can never disagree about who "@player" is.
function M.entities_in_scope(scope, ctx)
	local out = {}
	if scope == nil or scope == "all" then
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
		local z = zones.find(scope)
		if z then
			for _, id in ipairs(z.cards) do
				local e = entity.get(id)
				if e then out[#out + 1] = e end
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
	return out
end

-- The stat values a subject names, one per entity in its scope that carries it.
function M.values(p, ctx)
	local out = {}
	for _, e in ipairs(M.entities_in_scope(p.scope, ctx)) do
		local v = e.stats and e.stats[p.arg]
		if v ~= nil then out[#out + 1] = tonumber(v) or 0 end
	end
	return out
end

function M.total(subject, ctx)
	local p = M.parse_subject(subject)
	if not p then return 0 end

	if not p.scope then
		-- No scope: exactly the behaviour that shipped, so every existing
		-- game file keeps its meaning untouched.
		if p.fn == "count" then
			return #tags.find_targets({ p.arg }, { grid = true })
		elseif p.fn == "card" then
			local n = 0
			for e in entity.each("card") do
				local z = e.def_key == p.arg and entity.get(e.zone_id)
				if z and z.zone_type == "grid" then n = n + 1 end
			end
			return n
		end
		return entity.sum_stat(p.arg)
	end

	local ents = M.entities_in_scope(p.scope, ctx)
	if p.fn == "count" then
		local n = 0
		for _, e in ipairs(ents) do if tags.entity_has(e, p.arg) then n = n + 1 end end
		return n
	elseif p.fn == "card" then
		local n = 0
		for _, e in ipairs(ents) do if e.def_key == p.arg then n = n + 1 end end
		return n
	end

	local vals = M.values(p, ctx)
	if p.fn == "max" then
		local m = 0
		for _, v in ipairs(vals) do if v > m then m = v end end
		return m
	end
	local s = 0
	for _, v in ipairs(vals) do s = s + v end
	return s
end

local function compare(v, cond)
	if cond.equals   ~= nil then local n = tonumber(cond.equals);   return n ~= nil and v == n end
	if cond.at_least ~= nil then local n = tonumber(cond.at_least); return n ~= nil and v >= n end
	if cond.at_most  ~= nil then local n = tonumber(cond.at_most);  return n ~= nil and v <= n end
	return false
end

-- True when a subject carrying "each" holds for every member of its scope.
-- An empty scope fails: "each follower has 1 hp" must not be satisfied by
-- owning no followers, or a cost becomes free exactly when it cannot be paid.
local function each_holds(p, ctx, test)
	local ents = M.entities_in_scope(p.scope, ctx)
	if #ents == 0 then return false end
	for _, e in ipairs(ents) do
		if not test(tonumber((e.stats or {})[p.arg]) or 0) then return false end
	end
	return true
end

-- A subject asks about a set; "each" asks of every member, anything else asks
-- of the pool. fn forms (count:/card:/sum:/max:) are already aggregates, so
-- they always read the pool.
local function distributive(p)
	return p and p.quant == "each" and p.fn == nil
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
	local p = M.parse_subject(cond.stat)
	if distributive(p) then
		return each_holds(p, ctx, function(v) return compare(v, cond) end)
	end
	return compare(M.total(cond.stat, ctx), cond)
end

-- Map form { subject = n, ... }: every subject must reach n — pooled by
-- default, or held by every member when the subject says "each".
function M.meets_all(map, ctx)
	if type(map) ~= "table" then return true end
	for subject, n in pairs(map) do
		local need = tonumber(n)
		if need == nil then return false end
		local p = M.parse_subject(subject)
		if distributive(p) then
			if not each_holds(p, ctx, function(v) return v >= need end) then return false end
		elseif M.total(subject, ctx) < need then
			return false
		end
	end
	return true
end

return M
