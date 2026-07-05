-- The one condition vocabulary, shared by phase routing, end conditions,
-- challenge requires and card needs. Subjects are stat keys,
-- "count:<tag>" (cards on grid zones with that tag), or
-- "card:<key>" (instances of that template on grid zones).

local entity = require("entity")
local zones  = require("zones")
local tags   = require("tags")

local M = {}

function M.total(subject)
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
	if cond.zone_empty then
		for _, zk in ipairs(cond.zone_empty) do
			local z = zones.find(zk)
			if not z or #z.cards > 0 then return false end
		end
		return true
	end
	local v = M.total(cond.stat)
	if cond.equals   ~= nil then return v == cond.equals end
	if cond.at_least ~= nil then return v >= cond.at_least end
	if cond.at_most  ~= nil then return v <= cond.at_most end
	return false
end

-- Map form { subject = n, ... }: every subject must total at least n.
function M.meets_all(map)
	for subject, n in pairs(map or {}) do
		if M.total(subject) < n then return false end
	end
	return true
end

return M
