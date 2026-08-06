-- The one condition vocabulary, shared by phase routing, end conditions,
-- challenge requires and card needs. Subjects are stat keys,
-- "count:<tag>" (cards on grid zones with that tag), or
-- "card:<key>" (instances of that template on grid zones).

local entity = require("entity")
local zones  = require("zones")
local tags   = require("tags")

local M = {}

-- All three functions below read attacker-suppliable content (routing
-- conditions, end_conditions, requires/needs maps) and must never let a
-- malformed value (wrong type, missing) reach a raw Lua comparison or
-- arithmetic op — that throws an uncaught error and kills the process.
-- Every subject/threshold is coerced or type-checked before use; anything
-- that doesn't check out fails the condition rather than crashing.
function M.total(subject)
	if type(subject) ~= "string" then return 0 end
	local tag = subject:match("^count:(.+)$")
	if tag then
		return #tags.find_targets({ tag }, { grid = true })
	end
	local key = subject:match("^card:(.+)$")
	if key then
		local n = 0
		for e in entity.each("card") do
			local z = e.def_key == key and entity.get(e.zone_id)
			if z and z.zone_type == "grid" then n = n + 1 end
		end
		return n
	end
	return entity.sum_stat(subject)
end

-- { "stat": "hp", "equals": 0 } with equals / at_least / at_most,
-- or { "zone_empty": ["road", "hand"] } (all listed zones empty).
function M.met(cond)
	if type(cond) ~= "table" then return false end
	if cond.zone_empty then
		if type(cond.zone_empty) ~= "table" then return false end
		for _, zk in ipairs(cond.zone_empty) do
			local z = type(zk) == "string" and zones.find(zk)
			if not z or #z.cards > 0 then return false end
		end
		return true
	end
	local v = M.total(cond.stat)
	if cond.equals   ~= nil then local n = tonumber(cond.equals);   return n ~= nil and v == n end
	if cond.at_least ~= nil then local n = tonumber(cond.at_least); return n ~= nil and v >= n end
	if cond.at_most  ~= nil then local n = tonumber(cond.at_most);  return n ~= nil and v <= n end
	return false
end

-- Map form { subject = n, ... }: every subject must total at least n.
function M.meets_all(map)
	if type(map) ~= "table" then return true end
	for subject, n in pairs(map) do
		local need = tonumber(n)
		if need == nil or M.total(subject) < need then return false end
	end
	return true
end

return M
