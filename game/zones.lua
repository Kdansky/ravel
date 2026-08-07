local entity      = require("entity")
local cards       = require("cards")
local declaration = require("declaration")
local rng         = require("rng")

local M = {}
local key_map  = {}  -- zone key → entity ID (shared zones)
local seat_map = {}  -- zone key → seat name → entity ID (per_seat zones)

function M.reset()
	key_map, seat_map = {}, {}
end

function M.contains(p, x, y)
	return x >= p.x and x <= p.x + p.w and y >= p.y and y <= p.y + p.h
end

-- The seat an unqualified zone key means. Derived from the system card's
-- "turn" rather than cached, so undo restores it along with everything else.
-- One-seat games — every shipped game — never look past the first line.
function M.active_seat()
	local seats = declaration.G.seat_list or {}
	if #seats < 2 then return seats[1] end
	for e in entity.each("card") do
		if e.def_key == "system" and e.zone_id then
			-- turn 0 is "nobody has taken one yet", which reads as the first
			-- seat: a game that never hands over still has somebody playing.
			return seats[e.stats.turn or 0] or seats[1]
		end
	end
	return seats[1]
end

local function build(def, seat, pos)
	local e = {
		kind      = "zone",
		key       = def.key,
		seat      = seat,   -- nil for a shared zone: its cards have no owner
		label     = def.label,
		zone_type = def.type or "pile",
		tags      = def.tags_set or {},
		grid      = def.grid,
		fit       = def.fit,
		cards     = {},
		slots     = {},   -- slot_idx → slot entity ID (grid zones only)
		contents  = def.contents,
		pos       = pos,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		on_click  = def.on_click or {},
	}
	entity.register(e)
	if seat then
		seat_map[e.key] = seat_map[e.key] or {}
		seat_map[e.key][seat] = e.id
	else
		key_map[e.key] = e.id
	end

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

-- A per_seat zone exists once per seat, each instance with its own rect from
-- the def's list of positions. Everything downstream sees ordinary zones that
-- happen to carry a seat, so only the lookup below has to know the difference.
function M.create(def)
	if not def.per_seat then return build(def, nil, def.pos) end
	-- One rect per seat: "pos" is a list of rects here, not the single rect a
	-- shared zone declares. Two seats sharing one rect would draw on top of
	-- each other, so the author names both — the validator insists.
	local many = type(def.pos) == "table" and type(def.pos[1]) == "table"
	local first
	for i, seat in ipairs(declaration.G.seat_list or {}) do
		local e = build(def, seat, many and def.pos[i] or def.pos)
		first = first or e
	end
	return first
end

-- Create a card into a zone and give it a slot, or return nil when a grid is
-- full. move_card guards arrivals, but creation bypasses it entirely, so the
-- capacity bound lives here rather than being restated at every creation site.
function M.add(z, def_key)
	if not z or not M.has_room(z) then return nil end
	local e = cards.create(def_key, z.id)
	M.auto_slot(e.id)
	return e
end

-- Create the zone's declared contents ("card_key" or "card_key:count" strings),
-- shuffled if the zone is tagged. Also runs when a refill_when_empty zone empties.
function M.refill(z)
	for _, entry in ipairs(z.contents or {}) do
		local key, n = entry:match("^([^:]+):?(%d*)$")
		for _ = 1, tonumber(n) or 1 do
			if not M.add(z, key) then break end
		end
	end
	if z.tags.shuffle then M.shuffle(z.id) end
end

-- A zone key, optionally qualified by whose it is: "arena" is the active
-- seat's, "enemy.arena" the other's. A destination has to resolve to exactly
-- one zone — a set can be wide, a place to put a card cannot — so "anyone"
-- and "enemy" pick the first matching seat rather than all of them.
function M.find_id(key, owner)
	local seats = seat_map[key]
	if not seats then return key_map[key] end
	local active = M.active_seat()
	if owner == nil or owner == "mine" then return seats[active] end
	for _, seat in ipairs(declaration.G.seat_list or {}) do
		if owner == "anyone" or seat ~= active then
			if seats[seat] then return seats[seat] end
		end
	end
end

function M.find(key, owner)
	local id = M.find_id(key, owner)
	return id and entity.get(id)
end

-- Every instance of a zone key, in seat order. Shared zones have exactly one.
function M.all_with_key(key)
	local out = {}
	if key_map[key] then out[1] = entity.get(key_map[key]) end
	for _, seat in ipairs(declaration.G.seat_list or {}) do
		local id = seat_map[key] and seat_map[key][seat]
		if id then out[#out + 1] = entity.get(id) end
	end
	return out
end

function M.move_top(from_id, to_id)
	local from = entity.get(from_id)
	if not from or #from.cards == 0 then return false end
	return M.move_card(from.cards[#from.cards], to_id)
end

-- True when a card can take a place in the zone: grids are bounded by their
-- free slots, every other zone type is unbounded.
function M.has_room(z)
	if not z or z.zone_type ~= "grid" then return true end
	for _, sid in ipairs(z.slots) do
		local s = entity.get(sid)
		if s and not s.occupant then return true end
	end
	return false
end

function M.move_card(card_id, to_id)
	local c  = entity.get(card_id)
	local to = entity.get(to_id)
	-- A full board refuses new arrivals (checked before any mutation, so a
	-- refused move leaves the card exactly where it was).
	if not c or not to or not M.has_room(to) then return false end

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
	rng.shuffle(z.cards)
end

-- The pixel rect of cell `idx` in a grid zone, 1-based and row-major. Shared
-- with the renderer, which needs the same cell for a card that has no slot.
function M.cell_rect(z, idx)
	local g    = z.grid or { 4, 3 }
	local cols = g[1]
	local pad  = 4
	local cw   = z.place.w / cols
	local ch   = z.place.h / (g[2] or 3)
	local col  = (idx - 1) % cols
	local row  = math.floor((idx - 1) / cols)
	return {
		x = z.place.x + col * cw + pad,
		y = z.place.y + row * ch + pad,
		w = cw - pad * 2,
		h = ch - pad * 2,
	}
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
			for idx, slot_id in pairs(z.slots) do
				local slot = entity.get(slot_id)
				if slot then slot.place = M.cell_rect(z, idx) end
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
