local entity = require("entity")
local cards  = require("cards")

local M = {}
local key_map = {}  -- zone key → entity ID

function M.reset()
	key_map = {}
end

function M.contains(p, x, y)
	return x >= p.x and x <= p.x + p.w and y >= p.y and y <= p.y + p.h
end

function M.create(def)
	local e = {
		kind      = "zone",
		key       = def.key,
		label     = def.label,
		zone_type = def.type or "pile",
		tags      = def.tags_set or {},
		grid      = def.grid,
		cards     = {},
		slots     = {},   -- slot_idx → slot entity ID (grid zones only)
		contents  = def.contents,
		pos       = def.pos,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		on_click  = def.on_click or {},
	}
	entity.register(e)
	key_map[e.key] = e.id

	if e.zone_type == "grid" and e.grid then
		local cols, rows = e.grid[1], e.grid[2]
		for idx = 1, cols * rows do
			local slot = {
				kind     = "slot",
				zone_id  = e.id,
				slot_idx = idx,
				occupant = nil,
				place    = { x = 0, y = 0, w = 0, h = 0 },
			}
			entity.register(slot)
			e.slots[idx] = slot.id
		end
	end

	M.refill(e)
	return e
end

-- Create the zone's declared contents ("card_key" or "card_key:count" strings),
-- shuffled if the zone is tagged. Also runs when a refill_when_empty zone empties.
function M.refill(z)
	for _, entry in ipairs(z.contents or {}) do
		local key, n = entry:match("^([^:]+):?(%d*)$")
		for _ = 1, tonumber(n) or 1 do M.auto_slot(cards.create(key, z.id).id) end
	end
	if z.tags.shuffle then M.shuffle(z.id) end
end

function M.find_id(key)
	return key_map[key]
end

function M.find(key)
	local id = key_map[key]
	return id and entity.get(id)
end

function M.move_top(from_id, to_id)
	local from = entity.get(from_id)
	if not from or #from.cards == 0 then return false end
	return M.move_card(from.cards[#from.cards], to_id)
end

function M.move_card(card_id, to_id)
	local c = entity.get(card_id)
	if not c then return false end

	-- Clear slot occupancy when card leaves its slot.
	if c.slot_id then
		local slot = entity.get(c.slot_id)
		if slot and slot.occupant == card_id then slot.occupant = nil end
		c.slot_id = nil
	end

	local from = entity.get(c.zone_id)
	if from then
		for i, id in ipairs(from.cards) do
			if id == card_id then table.remove(from.cards, i); break end
		end
		if #from.cards == 0 and from.tags.refill_when_empty then
			M.refill(from)
		end
	end

	local to = entity.get(to_id)
	if not to then return false end
	table.insert(to.cards, card_id)
	c.zone_id = to_id
	M.auto_slot(card_id)
	return true
end

-- A card in a grid zone without a chosen slot takes the first free one, so
-- cards can be placed friction-free (creation, drafts) or precisely
-- (slot targeting overrides this in place_in_slot).
function M.auto_slot(card_id)
	local c = entity.get(card_id)
	local z = c and entity.get(c.zone_id)
	if not z or z.zone_type ~= "grid" or c.slot_id then return end
	for _, sid in ipairs(z.slots) do
		local s = entity.get(sid)
		if s and not s.occupant then
			s.occupant = card_id
			c.slot_id  = sid
			return
		end
	end
end

-- Remove a card from play. The flat array keeps the husk (IDs stay valid) but
-- it belongs to no zone and holds no stats, so nothing renders, targets or
-- counts it. Unlike move_card this never triggers refill: destroying is not
-- drawing, and that also rules out refill loops.
function M.destroy_card(card_id)
	local c = entity.get(card_id)
	if not c then return end
	if c.slot_id then
		local slot = entity.get(c.slot_id)
		if slot and slot.occupant == card_id then slot.occupant = nil end
		c.slot_id = nil
	end
	local z = entity.get(c.zone_id)
	if z then
		for i, id in ipairs(z.cards) do
			if id == card_id then table.remove(z.cards, i); break end
		end
	end
	c.zone_id = nil
	c.stats   = {}
end

-- Place a card into a specific slot on a grid zone.
function M.place_in_slot(card_id, slot_id)
	local slot = entity.get(slot_id)
	if not slot or (slot.occupant ~= nil and slot.occupant ~= card_id) then return false end
	M.move_card(card_id, slot.zone_id)
	local card = entity.get(card_id)
	-- release whatever slot move_card auto-assigned on grid entry
	if card.slot_id and card.slot_id ~= slot_id then
		local old = entity.get(card.slot_id)
		if old and old.occupant == card_id then old.occupant = nil end
	end
	card.slot_id  = slot_id
	slot.occupant = card_id
	return true
end

function M.shuffle(zone_id)
	local z = entity.get(zone_id)
	if not z then return end
	local c = z.cards
	for i = #c, 2, -1 do
		local j = math.random(i)
		c[i], c[j] = c[j], c[i]
	end
end

-- Recompute pixel rects for all zones and their slots.
function M.resize()
	local W, H = love.graphics.getDimensions()
	for z in entity.each("zone") do
		local p = z.pos
		z.place = {
			x = p[1] * W,
			y = p[2] * H,
			w = (p[3] - p[1]) * W,
			h = (p[4] - p[2]) * H,
		}
		if z.zone_type == "grid" and z.grid and next(z.slots) then
			local cols = z.grid[1]
			local cw   = z.place.w / cols
			local ch   = z.place.h / z.grid[2]
			local pad  = 4
			for idx, slot_id in pairs(z.slots) do
				local slot = entity.get(slot_id)
				if slot then
					local col = (idx - 1) % cols
					local row = math.floor((idx - 1) / cols)
					slot.place = {
						x = z.place.x + col * cw + pad,
						y = z.place.y + row * ch + pad,
						w = cw - pad * 2,
						h = ch - pad * 2,
					}
				end
			end
		end
	end
end

function M.zone_at(x, y)
	local result = nil
	for z in entity.each("zone") do
		if M.contains(z.place, x, y) then result = z.id end
	end
	return result
end

return M
