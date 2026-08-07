local entity    = require("entity")
local tags      = require("tags")
local zones     = require("zones")

local M = {}

M.card_id  = nil
M.kind     = nil   -- "slot" or "card"
M.intent   = nil   -- "play" or "activate": what confirming these targets does
M.spec     = nil   -- { min, max, tags, zone_set }
M.targets  = {}
M.eligible = {}

local function find_empty_slots(zone_set)
	local res = {}
	for z in entity.each("zone") do
		if z.zone_type == "grid" and z.slots then
			local zone_ok = not zone_set or zone_set[z.key] or zone_set[z.zone_type]
			if zone_ok then
				for _, slot_id in pairs(z.slots) do
					local slot = entity.get(slot_id)
					if slot and not slot.occupant then
						res[#res + 1] = slot_id
					end
				end
			end
		end
	end
	return res
end

-- How many targets a spec asks for. "count" is shorthand for both bounds.
-- The one definition: flow gates on it, the input layers decide whether to
-- open targeting at all, and targeting.start sizes itself from it.
function M.bounds(spec)
	if type(spec) ~= "table" then return 0, 0 end
	return spec.min or spec.count or 0, spec.max or spec.count or 0
end

function M.active()
	return M.card_id ~= nil
end

function M.start(card_id, spec, intent)
	local min, max = M.bounds(spec)
	local kind     = spec.type or "card"
	local zone_set = nil
	if spec.zones then
		zone_set = {}
		for _, zk in ipairs(spec.zones) do zone_set[zk] = true end
	end
	M.card_id  = card_id
	M.kind     = kind
	M.intent   = intent or "play"
	M.spec     = { min = min, max = max, tags = spec.tags or {}, zone_set = zone_set,
		owner = spec.owner }
	M.targets  = {}
	if kind == "slot" then
		M.eligible = find_empty_slots(zone_set)
	else
		M.eligible = tags.find_targets(M.spec.tags, zone_set)
	end
	-- "Choose an enemy creature" is the same word the scopes use, so the
	-- player-chooses case needs no syntax of its own.
	if spec.owner then
		local active, kept = zones.active_seat(), {}
		for _, id in ipairs(M.eligible) do
			local e = entity.get(id)
			local z = e and e.zone_id and entity.get(e.zone_id)
			local seat = z and z.seat
			local ok = spec.owner == "anyone"
				or (spec.owner == "mine"  and seat ~= nil and seat == active)
				or (spec.owner == "enemy" and seat ~= nil and seat ~= active)
			if ok then kept[#kept + 1] = id end
		end
		M.eligible = kept
	end
end

function M.is_eligible(id)
	for _, eid in ipairs(M.eligible) do
		if eid == id then return true end
	end
	return false
end

function M.is_selected(id)
	for _, tid in ipairs(M.targets) do
		if tid == id then return true end
	end
	return false
end

function M.add(id)
	if M.is_eligible(id) and not M.is_selected(id) then
		M.targets[#M.targets + 1] = id
		return true
	end
	return false
end

function M.is_full()
	return M.spec and #M.targets >= M.spec.max
end

function M.can_confirm()
	return M.spec and #M.targets >= M.spec.min
end

function M.clear()
	M.card_id  = nil
	M.kind     = nil
	M.intent   = nil
	M.spec     = nil
	M.targets  = {}
	M.eligible = {}
end

return M
