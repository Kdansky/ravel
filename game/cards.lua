local entity      = require("entity")
local declaration = require("declaration")
local json        = require("json")

local M = {}

-- Image cache: def_key → love.graphics.Image or false
local img_cache = {}

function M.reset()
	img_cache = {}
end

function M.create(def_key, zone_id)
	local def = declaration.G.card_defs[def_key]
	assert(def, "Unknown card def: " .. tostring(def_key))
	local e = {
		kind      = "card",
		def_key   = def_key,
		zone_id   = zone_id,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		stats     = {},    -- per-entity stats (e.g. hp, hp_max for buildings)
		parent_id = nil,   -- set when attached to another card
		attached  = {},    -- IDs of cards attached to this card
	}
	if def.card_stats then
		for k, v in pairs(def.card_stats) do e.stats[k] = v end
	end
	entity.register(e)
	local zone = entity.get(zone_id)
	if zone then table.insert(zone.cards, e.id) end
	return e
end

function M.def(card_entity)
	return declaration.G.card_defs[card_entity.def_key]
end

-- The zone a card's tags call home: the first of its tags whose tag
-- definition names a zone. nil when no tag does.
function M.home_zone(def)
	if type(def.tags) ~= "table" then return nil end
	for _, t in ipairs(def.tags) do
		local td = declaration.G.tag_defs[t]
		if td and td.zone then return td.zone end
	end
end

-- True if total stats cover a cost table like { gold = 2 }. nil cost = free.
function M.can_afford(cost)
	for stat, n in pairs(cost or {}) do
		if entity.sum_stat(stat) < n then return false end
	end
	return true
end

-- Overwrite instance stats with the template's card_stats. Used when a
-- template's stats change: immediate dev feedback beats preserving damage.
local function restamp(def_key, card_stats)
	for e in entity.each("card") do
		-- skip destroyed husks (no zone): they must stay stat-less
		if e.def_key == def_key and e.zone_id then
			e.stats = {}
			for k, v in pairs(card_stats or {}) do e.stats[k] = v end
		end
	end
end

-- Edit a card template in place, for live development. Instances only hold a
-- def_key, so every one of them reflects the change immediately. `raw` is
-- parsed as JSON; if that fails it's taken as a plain string. "null" clears
-- the field.
function M.edit(def_key, field, raw)
	local def = declaration.G.card_defs[def_key]
	if not def then return false, "unknown card: " .. tostring(def_key) end
	local ok, value = pcall(json.decode, raw)
	if not ok then value = raw end
	def[field] = value
	if field == "tags" then
		def.tags_set = {}
		if type(value) == "table" then
			for _, t in ipairs(value) do def.tags_set[t] = true end
		end
	elseif field == "card_stats" then
		restamp(def_key, value)
	elseif field == "asset" then
		img_cache[def_key] = nil
	end
	return true
end

-- Copy of a template without derived fields, for dumps and the debug API.
function M.template(def_key)
	local def = declaration.G.card_defs[def_key]
	if not def then return nil, "unknown card: " .. tostring(def_key) end
	local copy = {}
	for k, v in pairs(def) do
		if k ~= "tags_set" then copy[k] = v end
	end
	return copy
end

-- Template as pretty JSON, ready to paste back into the game file.
function M.dump(def_key)
	local copy, err = M.template(def_key)
	return copy and json.encode(copy, true), err
end

local function stats_equal(a, b)
	a, b = a or {}, b or {}
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Re-read templates from the current game file: edit the JSON in your editor,
-- reload, keep playing. Only template-ish data is swapped — zones and phases
-- are structural and need a full game load. Instances whose card_stats
-- changed on disk are re-stamped.
function M.reload()
	local ok, fresh = pcall(declaration.parse, declaration.filename)
	if not ok then return false, fresh end
	local G = declaration.G
	for key, def in pairs(fresh.card_defs) do
		local old = G.card_defs[key]
		if not (old and stats_equal(old.card_stats, def.card_stats)) then
			restamp(key, def.card_stats)
		end
	end
	G.card_defs      = fresh.card_defs
	G.computed_tags  = fresh.computed_tags
	G.stat_defs      = fresh.stat_defs
	G.stat_defs_list = fresh.stat_defs_list
	G.tag_defs       = fresh.tag_defs
	G.parse_problems = fresh.parse_problems
	img_cache = {}
	return true
end

-- "2 gold, 1 food" for a cost table, stat keys sorted for stable display.
function M.cost_text(cost)
	local keys = {}
	for k in pairs(cost or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = cost[k] .. " " .. k end
	return table.concat(parts, ", ")
end

-- Load (and cache) the asset image for a card def, returns nil if missing.
function M.image(def_key)
	if img_cache[def_key] ~= nil then return img_cache[def_key] end
	local def = declaration.G.card_defs[def_key]
	local asset = def and def.asset
	if not asset then img_cache[def_key] = false; return nil end
	local ok, img = pcall(love.graphics.newImage, "games/assets/" .. asset)
	img_cache[def_key] = ok and img or false
	return img_cache[def_key] or nil
end

return M
