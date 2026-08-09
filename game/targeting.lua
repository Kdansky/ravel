local entity      = require("entity")
local tags        = require("tags")
local zones       = require("zones")
local predicate   = require("predicate")
local declaration = require("declaration")

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

-- Who this card could legally be played onto. Pure: no session state, so flow
-- can ask the same question independently and refuse a target no interface
-- ever offered. Targeting is advisory; this is the legality.
-- Every instance of the named zones. A place to put a card is a thing you can
-- point at in its own right: "discard it" means the pile, not whatever card
-- happens to be lying on the pile, and a destination that has to be represented
-- by a marker card stops working the moment something covers the marker.
local function find_zones(zone_set)
	local res = {}
	for z in entity.each("zone") do
		if zone_set and zone_set[z.key] and not z.tags.hidden then res[#res + 1] = z.id end
	end
	return res
end

function M.candidates(card_id, spec)
	local kind     = spec.type or "card"
	local zone_set = nil
	if spec.zones then
		zone_set = {}
		for _, zk in ipairs(spec.zones) do zone_set[zk] = true end
	end
	local out = kind == "slot" and find_empty_slots(zone_set)
		or kind == "zone" and find_zones(zone_set)
		or tags.find_targets(spec.tags or {}, zone_set)
	-- "Choose an enemy creature" is the same word the scopes use, so the
	-- player-chooses case needs no syntax of its own. Naming zones implies one
	-- too: "zones": ["red", "red_discard"] means *my* red expedition and the
	-- shared discard, exactly as a destination reads, so a spec that lists
	-- zones never offers another seat's copy of one unless it says so.
	local owner = spec.owner or (zone_set and "not_enemy")
	if owner then
		local active, kept = zones.active_seat(), {}
		for _, id in ipairs(out) do
			local e = entity.get(id)
			-- A zone carries its own seat; a card or slot borrows the seat of
			-- the zone holding it.
			local z = e and (e.kind == "zone" and e
				or e.zone_id and entity.get(e.zone_id))
			local seat = z and z.seat
			local ok = owner == "anyone"
				or (owner == "not_enemy" and (seat == nil or seat == active))
				or (owner == "mine"      and seat ~= nil and seat == active)
				or (owner == "enemy"     and seat ~= nil and seat ~= active)
			if ok then kept[#kept + 1] = id end
		end
		out = kept
	end

	-- A stack offers its top card and nothing else. The renderer has always
	-- drawn and hit-tested exactly that, so a candidate buried in a pile was one
	-- the player was shown and could never click: Lost Cities' discard marker
	-- stayed "eligible" for the whole game while the first card discarded on top
	-- of it made it unreachable, and that colour could never be discarded to
	-- again. Whatever is on top is the destination now, which is what a pile
	-- meant all along.
	local reachable = {}
	for _, id in ipairs(out) do
		local e = entity.get(id)
		local z = e and e.kind == "card" and e.zone_id and entity.get(e.zone_id)
		if not z or (z.zone_type ~= "deck" and z.zone_type ~= "pile")
			or z.cards[#z.cards] == id then
			reachable[#reachable + 1] = id
		end
	end
	out = reachable

	-- Legality that depends on both cards at once lives on the destination:
	-- "accepts" is asked of each candidate with itself as @self and the
	-- arriving card as @target, so a pile can say what it takes without every
	-- card in the game having to know about every pile. A candidate with no
	-- accepts takes anything, which is what every game before this assumed.
	-- "immutable" is the engine's own word for scenery: menu entries, labels,
	-- anything that is furniture rather than a game object. Nothing may target
	-- it and nothing may edit it, so a stray "destroy every card here" or a
	-- misaimed spell cannot eat the interface.
	local visible = {}
	for _, id in ipairs(out) do
		local e = entity.get(id)
		if not (e and e.kind == "card" and tags.entity_has(e, "immutable")) then
			visible[#visible + 1] = id
		end
	end
	out = visible

	-- Legality that depends on both sides at once lives on the destination.
	-- A zone answers for itself, exactly as a card does — which is what lets
	-- "cards must ascend" be one line on the expedition rather than a rule every
	-- card in the game has to know.
	local kept = {}
	for _, id in ipairs(out) do
		local e   = entity.get(id)
		local def = e and (e.kind == "card" and declaration.G.card_defs[e.def_key]
			or e.kind == "zone" and declaration.G.zone_defs[e.key])
		if not (def and def.accepts) then
			kept[#kept + 1] = id
		elseif predicate.meets_all(def.accepts, { card_id = id, zone_id = e.kind == "zone" and id or nil,
			targets = { card_id } }) then
			kept[#kept + 1] = id
		end
	end
	return kept
end

function M.start(card_id, spec, intent)
	local min, max = M.bounds(spec)
	M.card_id  = card_id
	M.kind     = spec.type or "card"
	M.intent   = intent or "play"
	M.spec     = { min = min, max = max, tags = spec.tags or {} }
	M.targets  = {}
	M.eligible = M.candidates(card_id, spec)
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
