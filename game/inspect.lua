local entity      = require("entity")
local declaration = require("declaration")
local tags        = require("tags")
local json        = require("json")
local render      = require("render")

-- Hold ctrl and point at something to read the JSON behind it: the template as
-- written in the game file, then the live entity built from it, then whatever
-- the engine works out about that entity rather than storing (its owner, the
-- tags a zone hands it, a computed tag that is true only while a stat holds).
-- That third part is the reason this exists — a card's def is one text search
-- away, but what a piece *is* halfway through a game is spread across four
-- modules and was previously only visible from inside a debugger.
--
-- Read-only, and deliberately unconditional: it shows face-down cards and other
-- players' hands, because it is a window onto this machine's own state, which
-- the client already holds either way.
local M = {}

-- The renderer rewrites `place` every frame, and `tags_set` is the def's own
-- tag array in a second form. Neither is ever why you opened the JSON.
local SKIP = { place = true, tags_set = true }

local function encode(t)
	local copy = {}
	for k, v in pairs(t) do
		if not SKIP[k] and type(v) ~= "function" and type(v) ~= "userdata" then
			copy[k] = v
		end
	end
	local ok, s = pcall(json.encode, copy, true)
	return ok and s or ("// cannot encode: " .. tostring(s))
end

-- Every tag that is true of this card right now, from all three sources
-- entity_has consults. Computed tags have no list of bearers to read, so the
-- whole vocabulary is asked one tag at a time — a handful of lookups, on one
-- entity, only while a human holds ctrl.
local function effective_tags(e)
	local G, seen, out = declaration.G, {}, {}
	local function offer(t)
		if not seen[t] and tags.entity_has(e, t) then
			seen[t] = true
			out[#out + 1] = t
		end
	end
	local def = e.kind == "card" and G.card_defs[e.def_key]
	for _, t in ipairs(def and def.tags or {}) do offer(t) end
	local z = e.zone_id and entity.get(e.zone_id)
	for _, t in ipairs(z and z.applies or {}) do offer(t) end
	for t in pairs(G.computed_tags or {}) do offer(t) end
	table.sort(out)
	return out
end

-- The JSON of a thing, as one block of text. Pure, so the tests can read it.
function M.text(id)
	local e = entity.get(id)
	if not e then return nil end
	local G     = declaration.G
	local key   = e.kind == "card" and e.def_key or e.key
	local def   = e.kind == "card" and G.card_defs[e.def_key]
		or e.kind == "zone" and G.zone_defs[e.key]
	local parts = { "// " .. e.kind .. " #" .. e.id .. (key and (" — " .. key) or "") }

	if def then
		-- The template the engine holds, which is the file's own JSON plus what
		-- the parser worked out from it — a card with `moves` grew the
		-- activate_target that makes those moves clickable, and seeing that is
		-- most of the point.
		parts[#parts + 1] = "// template"
		parts[#parts + 1] = encode(def)
		parts[#parts + 1] = "// live"
	end
	parts[#parts + 1] = encode(e)

	if e.kind == "card" then
		parts[#parts + 1] = "// derived"
		parts[#parts + 1] = encode({
			owner = tags.owner_of(e),
			tags  = effective_tags(e),
		})
	end
	-- A piece hides the square it stands on, and the square is where its
	-- coordinates live, so it comes along rather than being unreachable.
	local slot = e.slot_id and entity.get(e.slot_id)
	if slot then
		parts[#parts + 1] = "// square #" .. slot.id
		parts[#parts + 1] = encode(slot)
	end
	return table.concat(parts, "\n")
end

local shown_id, lines, scroll, visible = nil, {}, 0, 0

function M.scroll_by(n)
	scroll = math.max(0, math.min(scroll + n, math.max(0, #lines - visible)))
end

function M.draw(id)
	if id ~= shown_id then shown_id, scroll = id, 0 end
	local text = id and M.text(id)
	if not text then return end

	local S      = render.scale()
	local sf     = render.small_font()
	local W, H   = love.graphics.getDimensions()
	local pad    = 6 * S
	local lh     = sf:getHeight() + 1 * S
	local w      = math.min(360 * S, W * 0.42)

	-- Wrapped, not clipped: a dump that quietly cuts off the end of a line is
	-- worse than no dump, because it looks complete. Wrapping here rather than
	-- printf-ing each line keeps one row of text one entry in `lines`, so the
	-- scroll arithmetic below stays about what is on screen.
	lines = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local _, rows = sf:getWrap(line, w - pad * 2)
		if #rows == 0 then lines[#lines + 1] = "" end
		for _, row in ipairs(rows) do lines[#lines + 1] = row end
	end

	local max_h  = math.max(H - 16 * S, lh * 3 + pad * 2)
	local h      = math.min(#lines * lh + pad * 2, max_h)
	visible      = math.max(1, math.floor((h - pad * 2) / lh))
	-- The footer only appears when it has something to say, and then it needs a
	-- line of its own rather than printing over the JSON.
	if #lines > visible then visible = math.max(1, visible - 1) end
	if scroll > math.max(0, #lines - visible) then scroll = math.max(0, #lines - visible) end

	-- Opposite the cursor, so the panel never covers the thing it describes.
	local mx = (love.mouse and love.mouse.getPosition()) or 0
	local x  = mx < W * 0.5 and (W - w - 8 * S) or 8 * S
	local y  = 8 * S

	love.graphics.push("all")
	love.graphics.setFont(sf)
	love.graphics.setColor(0.03, 0.05, 0.10, 0.98)
	love.graphics.rectangle("fill", x, y, w, h, 4, 4)
	love.graphics.setColor(0.25, 0.38, 0.60)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, 4, 4)

	love.graphics.setScissor(x + 1, y + 1, math.max(w - 2, 0), math.max(h - 2, 0))
	for i = 1, visible do
		local line = lines[i + scroll]
		if not line then break end
		if line:sub(1, 2) == "//" then
			love.graphics.setColor(0.55, 0.70, 0.95)
		else
			love.graphics.setColor(0.80, 0.86, 0.96)
		end
		love.graphics.print(line, x + pad, y + pad + (i - 1) * lh)
	end
	love.graphics.setScissor()

	if #lines > visible then
		love.graphics.setColor(0.45, 0.60, 0.85, 0.9)
		love.graphics.print(("lines %d-%d of %d, wheel scrolls"):format(
			scroll + 1, scroll + visible, #lines), x + pad, y + h - lh - 2 * S)
	end
	love.graphics.pop()
end

return M
