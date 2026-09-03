local entity      = require("entity")
local declaration = require("declaration")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local targeting   = require("targeting")
local anim        = require("anim")
local fx          = require("fx")
local log         = require("log")
local flow        = require("flow")
local tags        = require("tags")
local art         = require("art")
local predicate   = require("predicate")
local rich        = require("richtext")

local M = {}

local CARD_RATIO = 1.6

local C = {
	bg              = { 0.06, 0.09, 0.14 },
	zone_fill       = { 0.10, 0.14, 0.22 },
	zone_border     = { 0.22, 0.32, 0.50 },
	card_default    = { 0.16, 0.22, 0.36 },
	card_text       = { 0.90, 0.93, 1.00 },
	card_body       = { 0.68, 0.80, 0.96 },
	card_back       = { 0.10, 0.15, 0.28 },
	card_border     = { 0.30, 0.42, 0.65, 0.60 },
	selected        = { 0.95, 0.80, 0.20 },
	eligible        = { 0.20, 0.75, 1.00 },
	eligible_fill   = { 0.15, 0.65, 1.00, 0.18 },
	target_chosen   = { 0.20, 1.00, 0.45 },
	faded           = { 0.12, 0.18, 0.32, 0.40 },
	overlay_dim     = { 0.00, 0.00, 0.00, 0.72 },
	stat            = { 0.65, 0.80, 1.00 },
	deck_count      = { 0.50, 0.65, 0.85 },
	cost            = { 1.00, 0.85, 0.40 },
	impact          = { 1.00, 0.90, 0.55 },
	button_fill     = { 0.12, 0.18, 0.30, 0.92 },
	button_border   = { 0.35, 0.50, 0.75 },
}

-- Landing cards kick off impact effects: hard for board slams, soft for piles.
anim.on_land = function(rect, kind)
	local cx, cy = rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
	if kind == "slam" then
		fx.impact(cx, cy, 1.0, C.impact)
	else
		fx.impact(cx, cy, 0.35, C.eligible)
	end
end

-- UI scale: the layout is proportional to the window, so type and chrome
-- must be too. 960×540 is the design size.
local S           = 1
local font_main   = nil
local font_small  = nil
local font_banner = nil

-- Fonts by pixel size, made once. A card picks the largest that fits rather
-- than cutting the word: "Score Green" at 13px in a 35px Lost Cities card came
-- out as "S...", which tells a player nothing at all, and the same string at
-- 8px is legible. Cutting is still the last resort, not the first.
local font_cache = {}
-- What size each face was made at. A LOVE font will not say, and rich text has
-- to ask for the same face a size down for the italic it sets flavour in.
local font_px = setmetatable({}, { __mode = "k" })
-- Text lands on whole pixels, everywhere. A zone's rect is a fraction of the
-- window, so a card lands on x = 371.4 and every glyph in it is sampled between
-- two texels — which is most of what "blurry" is. Wrapped once here rather than
-- rounded at forty call sites, where the next one added would forget.
local function printf(text, x, y, ...)
	return love.graphics.printf(text, math.floor(x + 0.5), math.floor(y + 0.5), ...)
end

local function print_at(text, x, y, ...)
	return love.graphics.print(text, math.floor(x + 0.5), math.floor(y + 0.5), ...)
end

local function font_at(px)
	px = math.max(6, math.floor(px + 0.5))
	if not font_cache[px] then
		local f = love.graphics.newFont(px)
		-- The default filter is linear, set once in main.lua for the card art,
		-- and a glyph atlas is not art: it is already rasterised at exactly the
		-- size it will be drawn, so sampling it smoothly can only soften edges
		-- that were sharp. Text is the one thing that wants nearest.
		f:setFilter("nearest", "nearest")
		font_cache[px] = f
		font_px[f] = px
	end
	return font_cache[px]
end

-- The same face a size or two along, which is all rich text needs of the cache.
function M.font_step(font, delta)
	local px = font_px[font]
	return px and font_at(px + delta) or font
end

function M.rescale()
	local W, H = love.graphics.getDimensions()
	S = math.max(0.75, math.min(3, math.min(W / 960, H / 540)))
	-- A point smaller than they were. The HUD and the zone labels are read at a
	-- glance and never studied, and the room they were taking is room a card
	-- wanted: a title that fits at 12 does not have to shrink to 8.
	font_main   = font_at(12 * S)
	font_small  = font_at(math.max(8, 8 * S))
	font_banner = font_at(30 * S)
	love.graphics.setFont(font_main)
	-- The band a named grid keeps clear for its own name, matching what
	-- `card_places` reserves on a hand and what `draw_zone_label` prints into.
	-- zones.lua has no font, so the measurement is pushed to it from here.
	zones.label_h = font_main:getHeight() + 3 * S
	-- Rich text owns no fonts; the one thing it cannot work out for itself is
	-- handed to it here. How heavy a bold is it takes from the face it is
	-- drawing, which is the only thing that answer depends on.
	rich.font_step = M.font_step
	fx.set_scale(S)
end

function M.scale()
	return S
end

local function get_small_font()
	if not font_small then M.rescale() end
	return font_small
end

-- The scale-aware font, for panels drawn outside this module (inspect.lua).
M.small_font = get_small_font

-- The body font, for panels drawn outside this module. Both are functions
-- rather than values because rescale replaces them when the window changes.
function M.main_font()
	if not font_main then M.rescale() end
	return font_main
end

-- Cut text to fit a width, appending "..." (multibyte-safe trim).
-- Drop the last *character*, not the last byte. The old version removed a byte
-- and then walked back over UTF-8 continuation bytes (0x80–0xBF) — but a lead
-- byte is 0xC2 or higher, so it stopped one short and left the lead dangling.
-- The result is invalid UTF-8, and LÖVE's printf answers that by drawing
-- nothing *and abandoning the rest of the zone*: one card titled "Lost Cities ·
-- online" blanked itself and took every card after it off the screen.
local function drop_char(s)
	local i = #s
	while i > 1 and s:byte(i) >= 0x80 and s:byte(i) <= 0xBF do i = i - 1 end
	return s:sub(1, i - 1)
end

local function truncate(font, text, w)
	text = tostring(text)
	if font:getWidth(text) <= w then return text end
	while #text > 1 and font:getWidth(text .. "...") > w do
		text = drop_char(text)
	end
	return text .. "..."
end

-- A title, fitted rather than cut. One line at the largest size that holds it;
-- failing that two lines, which is what a two-word name wants anyway; and only
-- when neither works does it lose characters. "Score Green" used to come out as
-- "S...", which tells a player nothing.
--
-- Returns the font, the text to draw (with a newline if it wrapped) and how
-- tall it will be.
local function fit_title(text, w, max_px, min_px)
	text = tostring(text)
	for px = math.floor(max_px), math.floor(min_px), -1 do
		local f = font_at(px)
		if f:getWidth(text) <= w then return f, text, f:getHeight() end
	end
	-- Two lines, biggest first — but only where there is a space to break at.
	-- LÖVE will happily split a long word, and "Watch/tower" reads worse than a
	-- smaller "Watchtower": a name is a name.
	for px = math.floor(max_px), math.floor(min_px), -1 do
		if not text:find(" ") then break end
		local f = font_at(px)
		local _, lines = f:getWrap(text, w)
		-- Two lines that put every line inside the width *and* broke at a space.
		-- LÖVE splits a word it cannot fit, so "Yellow 9" comes back as
		-- "Yello" / "w 9" — which passes a width check and reads as nonsense.
		-- Rejoining tells the difference: only a break at a space rebuilds the
		-- original string.
		if #lines == 2 and lines[1] .. " " .. lines[2] == text then
			local fits = true
			for _, l in ipairs(lines) do if f:getWidth(l) > w then fits = false end end
			if fits then return f, lines[1] .. "\n" .. lines[2], f:getHeight() * 2 end
		end
	end
	-- Nothing fitted: go smaller still before cutting, because a name a size
	-- down is readable and a name with its end missing is not.
	for px = math.floor(min_px) - 1, 7, -1 do
		local f = font_at(px)
		if f:getWidth(text) <= w then return f, text, f:getHeight() end
	end
	local f = font_at(7)
	return f, truncate(f, text, w), f:getHeight()
end

-- Light text with a dark outline, so it reads against a picture instead of
-- needing a slab of colour under it. Eight offsets rather than four: a diagonal
-- gap lets a bright pixel of art touch the glyph and the letter loses its edge.
local OUTLINE_OFFSETS = { {-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1} }
local function outlined_printf(text, x, y, w, align, fg, outline)
	local w_i = math.floor(w + 0.5)
	local d = math.max(1, math.floor(S + 0.5))
	love.graphics.setColor(outline[1], outline[2], outline[3], outline[4] or 1)
	for _, o in ipairs(OUTLINE_OFFSETS) do
		printf(text, x + o[1] * d, y + o[2] * d, w_i, align)
	end
	love.graphics.setColor(fg[1], fg[2], fg[3], fg[4] or 1)
	printf(text, x, y, w_i, align)
end

local function pulse(speed)
	return 0.5 + 0.5 * math.sin(love.timer.getTime() * (speed or 5))
end

-- Tiny vector glyphs for stats, so numbers read at a glance without art.
--
-- **Named by shape, and the game says which.** These used to be keyed on the
-- stat's own name — a stat called `gold` drew a coin — which is the engine
-- knowing one game's vocabulary, and the next game's currency drew a diamond
-- for no reason it could see or change. A stat declares its `icon` instead, out
-- of this closed set; anything undeclared gets the diamond.
--
-- `"none"` is the seventh word and draws nothing: a badge that is only a number.
-- Splendor's six token piles print how many are left and wore the fallback
-- diamond beside every one of them, which says the shape of a gem it is not.
-- It is a shape name rather than `icon: false` so the field stays one type, and
-- it is on the stat rather than on the style because the badge and the HUD row
-- draw the same icon through the same call and would otherwise disagree.
local ICON_COLOR = {
	coin   = { 0.95, 0.78, 0.25 },
	heart  = { 0.92, 0.32, 0.32 },
	shield = { 0.55, 0.70, 0.90 },
	banner = { 0.78, 0.55, 0.95 },
	leaf   = { 0.55, 0.85, 0.40 },
	blade  = { 0.98, 0.72, 0.30 },
	arrow  = { 0.90, 0.90, 0.95 },
	card   = { 0.72, 0.80, 0.92 },
	fist   = { 0.95, 0.40, 0.35 },
	orb    = { 0.60, 0.75, 0.95 },
	pot    = { 0.95, 0.62, 0.72 },
}

-- The vocabulary, for the validator: it must refuse a shape nobody draws rather
-- than let a game ask for one and silently get a diamond.
function M.icons()
	local out = { diamond = true, none = true }
	for k in pairs(ICON_COLOR) do out[k] = true end
	return out
end

local function draw_stat_icon(key, cx, cy, s, tint)
	if key == "none" then return end
	local col = tint or ICON_COLOR[key] or { 0.60, 0.70, 0.85 }
	love.graphics.setColor(unpack(col))
	if key == "coin" then
		love.graphics.circle("fill", cx, cy, s * 0.42)
		love.graphics.setColor(col[1] * 0.6, col[2] * 0.6, col[3] * 0.6)
		love.graphics.circle("line", cx, cy, s * 0.24)
	elseif key == "heart" then
		love.graphics.circle("fill", cx - s * 0.18, cy - s * 0.12, s * 0.24)
		love.graphics.circle("fill", cx + s * 0.18, cy - s * 0.12, s * 0.24)
		love.graphics.polygon("fill",
			cx - s * 0.40, cy - s * 0.02, cx + s * 0.40, cy - s * 0.02, cx, cy + s * 0.44)
	elseif key == "shield" then
		love.graphics.polygon("fill",
			cx - s * 0.35, cy - s * 0.38, cx + s * 0.35, cy - s * 0.38,
			cx + s * 0.35, cy + s * 0.02, cx, cy + s * 0.44, cx - s * 0.35, cy + s * 0.02)
	elseif key == "banner" then
		love.graphics.setLineWidth(math.max(1, s * 0.12))
		love.graphics.line(cx - s * 0.28, cy - s * 0.42, cx - s * 0.28, cy + s * 0.44)
		love.graphics.polygon("fill",
			cx - s * 0.28, cy - s * 0.42, cx + s * 0.42, cy - s * 0.24, cx - s * 0.28, cy - s * 0.04)
	elseif key == "leaf" then
		love.graphics.circle("fill", cx, cy + s * 0.08, s * 0.32)
		love.graphics.setLineWidth(math.max(1, s * 0.10))
		love.graphics.line(cx, cy - s * 0.20, cx + s * 0.16, cy - s * 0.42)
	elseif key == "blade" then
		love.graphics.polygon("fill",
			cx - s * 0.08, cy + s * 0.44, cx + s * 0.10, cy + s * 0.44,
			cx + s * 0.10, cy - s * 0.18, cx + s * 0.01, cy - s * 0.46,
			cx - s * 0.08, cy - s * 0.18)
		love.graphics.rectangle("fill", cx - s * 0.28, cy + s * 0.16, s * 0.56, s * 0.10)
	elseif key == "arrow" then
		love.graphics.polygon("fill",
			cx - s * 0.06, cy + s * 0.42, cx + s * 0.10, cy + s * 0.42,
			cx + s * 0.10, cy - s * 0.10, cx - s * 0.06, cy - s * 0.10)
		love.graphics.polygon("fill",
			cx - s * 0.32, cy - s * 0.08, cx + s * 0.36, cy - s * 0.08, cx + s * 0.02, cy - s * 0.46)
	elseif key == "card" then
		love.graphics.rectangle("fill", cx - s * 0.26, cy - s * 0.40, s * 0.52, s * 0.80, s * 0.10, s * 0.10)
		love.graphics.setColor(col[1] * 0.35, col[2] * 0.35, col[3] * 0.35)
		love.graphics.rectangle("fill", cx - s * 0.15, cy - s * 0.28, s * 0.30, s * 0.34)
	elseif key == "fist" then
		love.graphics.rectangle("fill", cx - s * 0.34, cy - s * 0.20, s * 0.62, s * 0.56, s * 0.14, s * 0.14)
		love.graphics.rectangle("fill", cx - s * 0.20, cy - s * 0.40, s * 0.44, s * 0.26, s * 0.10, s * 0.10)
		love.graphics.rectangle("fill", cx + s * 0.20, cy - s * 0.06, s * 0.18, s * 0.30, s * 0.08, s * 0.08)
	elseif key == "orb" then
		love.graphics.circle("fill", cx, cy, s * 0.40)
		love.graphics.setColor(1, 1, 1, 0.55)
		love.graphics.circle("fill", cx - s * 0.13, cy - s * 0.15, s * 0.11)
	elseif key == "pot" then
		love.graphics.polygon("fill",
			cx - s * 0.38, cy - s * 0.14, cx + s * 0.38, cy - s * 0.14,
			cx + s * 0.28, cy + s * 0.40, cx - s * 0.28, cy + s * 0.40)
		love.graphics.rectangle("fill", cx - s * 0.16, cy - s * 0.34, s * 0.32, s * 0.10, s * 0.04, s * 0.04)
	else
		love.graphics.polygon("fill",
			cx, cy - s * 0.42, cx + s * 0.36, cy, cx, cy + s * 0.42, cx - s * 0.36, cy)
	end
end

-- The shape a stat asks for, or nothing, which draws the diamond — and the
-- colour it asks for, or nothing, which is the shape's own.
--
-- A shape carries a colour so that an undeclared stat still reads at a glance,
-- but the shapes are a closed set of six and a game's numbers are not: Splendor
-- has five gems and borrows five silhouettes, and onyx came out an orange
-- sword. The colour is the stat's to say, in the same vocabulary a zone paints
-- its squares with.
local function stat_icon(key)
	local def = declaration.G.stat_defs[key]
	if not def then return nil end
	return def.icon, def.color and art.colour(def.color) or nil
end

local selected_id = nil
local detail_id   = nil   -- card or zone shown in the full-screen detail overlay
local can_undo    = false
local celebrated  = false -- the ending flourish fires once per ending screen
local buttons     = {}    -- name → rect, rebuilt every frame for hit-testing
-- Which cards may answer what is announced, worked out once a frame. Asked per
-- card it would walk every card in the game once per card drawn, which on a
-- hundred-chip board is ten thousand predicate reads a frame for a window that
-- is usually not even open.
local react_offer = {}
local stat_hud    = {}    -- stat key → {x, y}, where the HUD drew it last frame

function M.set_can_undo(b) can_undo = b end

-- Which on-screen button (if any) is at x,y. Rects were stored during draw.
function M.hit_button(x, y)
	for name, r in pairs(buttons) do
		if zones.contains(r, x, y) then return name end
	end
end

-- Screen position of a stat's HUD row, for floating deltas.
function M.stat_pos(key)
	local p = stat_hud[key]
	if p then return p.x, p.y end
	return love.graphics.getWidth() - 80 * S, 12 * S
end

-- Compute per-card pixel rects within a zone.
-- A card keeps its proportions inside whatever box it is given, centred, so a
-- grid cell wider than a card leaves breathing room instead of stretching the
-- art into a banner. Board games that want their cells filled edge to edge as
-- tiles (a 5x5 castle) declare "fit": "fill" on the zone.
local function fit_card(box, mode)
	if mode == "fill" then return box end
	local w, h = box.w, box.w * CARD_RATIO
	if h > box.h then h = box.h; w = h / CARD_RATIO end
	return { x = box.x + (box.w - w) * 0.5, y = box.y + (box.h - h) * 0.5, w = w, h = h }
end

-- A fanned stack: every card laid along one axis, each one covering all but a
-- strip of the one before. The strip is what the whole layout is for, so it is
-- what the arithmetic protects — the cards shrink to keep it, not the other way
-- round. Below `STRIP` a card is a line with no room for its name, which is the
-- fault this replaced.
local STRIP  = 18
local SPREAD = 0.34

local function fan_places(zone_e, dir)
	local p, n = zone_e.place, #zone_e.cards
	if n == 0 then return {} end
	local vert   = dir == "up" or dir == "down"
	local pad    = 4 * S
	-- Along the fan, and across it. Naming the two axes once is what keeps the
	-- four directions from being four copies of this function.
	local run    = (vert and p.h or p.w) - pad * 2
	local across = (vert and p.w or p.h) - pad * 2

	-- Open to a comfortable spread, close it to fit, and only then make the
	-- cards smaller: a tight strip on a big card reads, a loose one on a card
	-- too small to letter does not.
	local card_run = vert and across * CARD_RATIO or across / CARD_RATIO
	local strip    = math.min(card_run * SPREAD, math.max(STRIP * S, (run - card_run) / math.max(1, n - 1)))
	if card_run + (n - 1) * strip > run then
		card_run = run - (n - 1) * strip
		-- More cards than there are readable strips. Keep the last one a card —
		-- it is the one being played on, and a fan of nothing but strips has no
		-- top — and divide what is left. Strips get thin here, which is honest:
		-- the zone is too short for what is in it, and the alternative is cards
		-- running off the end where they cannot be seen at all.
		if card_run < strip then
			card_run = math.max(strip, run * 0.3)
			strip    = (run - card_run) / (n - 1)
		end
	end

	local card_w = vert and across or card_run
	local card_h = vert and card_run or across
	local step   = (dir == "up" or dir == "left") and -strip or strip
	-- Growing up or left, the first card still sits at the far end, so the run
	-- fills the zone in the direction it was asked to fill.
	local x0 = p.x + pad + (dir == "left" and (run - card_w) or 0)
	local y0 = p.y + pad + (dir == "up" and (run - card_h) or 0)

	local places = {}
	for i = 1, n do
		local box = {
			x = x0 + (vert and 0 or (i - 1) * step),
			y = y0 + (vert and (i - 1) * step or 0),
			w = card_w,
			h = card_h,
		}
		places[i] = fit_card(box, zone_e.style.fit)
	end
	return places
end

-- How much of a fanned card is still showing once the next one is laid over it.
-- The card's name is drawn at the bottom of *this*, not of the card, so a strip
-- carries the one thing a covered card has to say.
local function fan_visible(pl, next_pl, dir)
	if not next_pl then return pl end
	if dir == "down" then return { x = pl.x, y = pl.y, w = pl.w, h = math.max(0, next_pl.y - pl.y) }
	elseif dir == "up" then
		local top = next_pl.y + next_pl.h
		return { x = pl.x, y = top, w = pl.w, h = math.max(0, pl.y + pl.h - top) }
	elseif dir == "right" then return { x = pl.x, y = pl.y, w = math.max(0, next_pl.x - pl.x), h = pl.h }
	else
		local left = next_pl.x + next_pl.w
		return { x = left, y = pl.y, w = math.max(0, pl.x + pl.w - left), h = pl.h }
	end
end

local function card_places(zone_e)
	local p  = zone_e.place
	local n  = #zone_e.cards
	local zt = zone_e.layout

	-- Page zones (the built-in reveal overlay): every card fills the zone,
	-- so the whole story panel is the tap target.
	if zt == "page" then
		local pad, places = 6 * S, {}
		for i = 1, n do
			places[i] = { x = p.x + pad, y = p.y + pad, w = p.w - pad * 2, h = p.h - pad * 2 }
		end
		return places
	end

	-- A stack asked to show its whole length. It answers before `type` does,
	-- because the question it settles — where does each card go — is the one
	-- `type` was otherwise the only one answering.
	if zone_e.row then return fan_places(zone_e, zone_e.row) end

	if zt == "stack" then
		local pad = 3 * S
		return { fit_card({ x = p.x + pad, y = p.y + pad,
			w = p.w - pad * 2, h = p.h - pad * 2 }, zone_e.style.fit) }
	end

	if zt == "grid" then
		local places = {}
		for i, card_id in ipairs(zone_e.cards) do
			local c    = entity.get(card_id)
			local slot = c and c.slot_id and entity.get(c.slot_id)
			if slot then
				places[i] = fit_card(slot.place, zone_e.style.fit)
			else
				places[i] = fit_card(zones.cell_rect(zone_e, i), zone_e.style.fit)
			end
		end
		return places
	end

	-- hand and others: lay out left-to-right
	if n == 0 then return {} end
	local pad    = 6 * S
	-- A named zone stays named once there is something in it. The label draws
	-- along the top edge, so the cards begin below it instead of over it —
	-- without this a hand told you what it was only while it was empty, which
	-- is exactly when there is least to work out.
	local head   = zone_e.label and love.graphics.getFont():getHeight() + 3 * S or 0
	local gap    = 4 * S
	local room_w = p.w - pad * 2
	local room_h = p.h - pad * 2 - head
	-- A filled card has no shape of its own, so the card ratio cannot bound the
	-- search and every column count tiles the same area. Cells closest to square
	-- is what settles it instead: two buttons in a wide strip come out side by
	-- side using the whole of it, which is the fault this fixes, and fifty-one
	-- plates come out as a block rather than as a row of slivers.
	--
	-- Otherwise: one line for as long as one line reads, then more lines rather
	-- than narrower cards. A row is the layout that promises every card shows its
	-- text, and forty-one chips across a strip are 23px of picture each, which
	-- is a promise broken quietly. One line is among the shapes tried, so the
	-- winner is never smaller than the single line would have been.
	local fill = zone_e.style.fit == "fill"
	local cols, card_h, best = n, 0, math.huge
	for c = 1, n do
		local r = math.ceil(n / c)
		local w = (room_w - (c - 1) * gap) / c
		local h = (room_h - (r - 1) * gap) / r
		if fill then
			-- Both sides positive or the ratio says nothing: a column count that
			-- does not fit is not a layout, it is a negative width.
			local off = (w > 0 and h > 0) and math.abs(math.log(w / h)) or math.huge
			if off < best then cols, best = c, off end
		else
			h = math.min(h, w * CARD_RATIO)
			if h > card_h then cols, card_h = c, h end
		end
	end
	local rows = math.ceil(n / cols)
	local card_w
	if fill then
		card_w = (room_w - (cols - 1) * gap) / cols
		card_h = (room_h - (rows - 1) * gap) / rows
	else
		card_w = card_h / CARD_RATIO
	end
	local top    = p.y + head + (p.h - head - (rows * card_h + (rows - 1) * gap)) / 2
	local places = {}
	for i = 1, n do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		-- Every line centred on its own count, so eleven above three reads as a
		-- block with a short last line rather than as a block hanging off the left.
		local wide = math.min(cols, n - row * cols)
		local left = p.x + (p.w - (wide * card_w + (wide - 1) * gap)) / 2
		places[i] = { x = left + col * (card_w + gap), y = top + row * (card_h + gap), w = card_w, h = card_h }
	end
	return places
end

local function draw_card_back(pl)
	love.graphics.push("all")
	love.graphics.setColor(unpack(C.card_back))
	love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
	love.graphics.setColor(0.22, 0.38, 0.65)
	love.graphics.setLineWidth(2 * S)
	love.graphics.rectangle("line", pl.x + 2 * S, pl.y + 2 * S, pl.w - 4 * S, pl.h - 4 * S, 4 * S, 4 * S)
	local m = 7 * S
	love.graphics.setColor(0.16, 0.26, 0.46)
	love.graphics.setLineWidth(S)
	love.graphics.rectangle("line", pl.x + m, pl.y + m, pl.w - m * 2, pl.h - m * 2, 2 * S, 2 * S)
	local cx = pl.x + pl.w * 0.5
	local cy = pl.y + pl.h * 0.5
	local dw = pl.w * 0.30
	local dh = pl.h * 0.22
	love.graphics.setColor(0.14, 0.24, 0.44)
	love.graphics.polygon("fill", cx, cy - dh, cx + dw, cy, cx, cy + dh, cx - dw, cy)
	love.graphics.setColor(0.28, 0.46, 0.78)
	love.graphics.polygon("line", cx, cy - dh, cx + dw, cy, cx, cy + dh, cx - dw, cy)
	love.graphics.pop()
end

-- Cost badge: one stat icon + number per cost entry, top-left of the card.
--
-- **A measured cost is drawn as the number it comes to**, not as the expression
-- that finds it. A cost amount may be a subject rather than a number — which is
-- the whole of a card whose price is printed on itself, and the only way a play
-- block shared by ninety cards can charge each of them its own — and printing
-- the string put "price@self" on the face of every card in the game. Measured
-- against this card, because "@self" is what the expression is about.
local function draw_cost_badge(pl, cost, card_e)
	local sf   = get_small_font()
	local ih   = sf:getHeight()
	local keys, shown = {}, {}
	for k, v in pairs(cost) do
		keys[#keys + 1] = k
		shown[k] = tostring(cards.cost_amount(v, card_e and card_e.id))
	end
	table.sort(keys)

	local w = 4 * S
	for _, k in ipairs(keys) do
		local icon = stat_icon(k)
		w = w + (icon ~= "none" and ih or 0) + 2 * S + sf:getWidth(shown[k]) + 4 * S
	end
	love.graphics.setColor(0, 0, 0, 0.65)
	love.graphics.rectangle("fill", pl.x + 2, pl.y + 2, w, ih + 4 * S, 2 * S, 2 * S)

	love.graphics.setFont(sf)
	local x = pl.x + 2 + 4 * S
	local y = pl.y + 2 + 2 * S
	for _, k in ipairs(keys) do
		local icon, tint = stat_icon(k)
		local ind = icon ~= "none" and ih or 0
		draw_stat_icon(icon, x + ih * 0.5, y + ih * 0.5, ih, tint)
		love.graphics.setColor(unpack(C.cost))
		print_at(shown[k], x + ind + 2 * S, y)
		x = x + ind + 2 * S + sf:getWidth(shown[k]) + 4 * S
	end
end

-- How wide the pill is, and how much of its front the shape takes — nothing,
-- when the stat says it has none, and then the number closes the gap rather
-- than sitting behind an empty square. Measured apart from the drawing because
-- the title has to start clear of the badges, and it was clearing a fraction of
-- the card where there is a number to be had.
-- A badge is an icon and a number, and a stat may say it has none: a banner
-- shape meaning "this is an attack" is a fact without a quantity, and the 1
-- that carries it is noise on the card. The mirror of `icon: "none"`, which is
-- a number without a shape, and on the stat for the same reason.
local function badge_text(key, v)
	local def = declaration.G.stat_defs[key]
	return (def and def.number == false) and "" or tostring(v)
end

local function badge_size(key, txt)
	local sf  = get_small_font()
	local ind = stat_icon(key) ~= "none" and sf:getHeight() or 0
	return ind + sf:getWidth(txt) + 8 * S, ind
end

-- The badges a card actually shows: the style's list, less any zero it asked to
-- leave out. Asked by the drawing and by the title's layout both, because a
-- title giving way to a badge that is not there would be off-centre for nothing.
-- What a card's stat shows, which is what the rules read and not what is stored
-- on it: a badge that said the printed number while every condition in the game
-- saw a buffed one would be the screen disagreeing with the board. Nil stays
-- nil — a buff never gives a card a stat it has not got.
local function shown_stat(card_e, key)
	local stats = card_e and card_e.stats
	if not (stats and stats[key]) then return stats and stats[key] end
	return tags.stat(card_e, key)
end

local function badge_keys(look, card_e)
	local out = {}
	if not (type(look.badges) == "table" and card_e and card_e.stats) then return out end
	local zeros = look.badge_zeros ~= false
	for _, key in ipairs(look.badges) do
		local v = shown_stat(card_e, key)
		if v and (zeros or v ~= 0) then out[#out + 1] = key end
	end
	return out
end

-- Draw a card face.
-- show_text=true: allocate extra space below the image for description text (hand cards).
-- show_text=false: compact title bar only (board tiles, animations, pile top).
-- `vis` is the part of the card that is not covered by the next one in a fan;
-- the words go at the bottom of it rather than at the bottom of the card, so a
-- card showing only a strip still shows its name. It is the whole card
-- everywhere else, which is every zone that is not fanned.
local function draw_card_face(pl, card_e, show_text, vis)
	vis = vis or pl
	local def   = cards.def(card_e)
	local look  = cards.style(card_e)
	-- One property for the plate: a colour, or false for none, so a transparent
	-- PNG shows the board through it. Two words for one decision was one too many.
	local color = look.color or C.card_default
	local img   = cards.image(card_e)
	local z     = entity.get(card_e.zone_id)
	local title = def and def.text or card_e.def_key
	-- Some cards are their picture. A chess knight labelled "White Knight" is
	-- worse than one that just looks like a knight, and on a board tile the
	-- label costs a quarter of the height it needed for the drawing. Carried as
	-- a tag so a zone can grant it too ("nothing on this board is titled")
	-- rather than every template having to say it.
	local no_title = look.title == false
	-- What is left to put in the text band once the title is gone. A hand card
	-- may still have a description worth the room; a board tile has nothing, and
	-- gives the space back to the art.
	local body = show_text and def and def.tooltip or nil
	if body == "" then body = nil end
	-- Where the words ended up, reported to the caller: on a card wide enough
	-- for prose the badges belong on the title's line, because the prose is
	-- under it and a bottom-anchored row would print over it.
	local title_y = nil

	-- Three states, and the two unusable ones must be told apart: a spent
	-- ability reads "exhausted" (wait for the round), an unpayable one reads
	-- "can't yet" (change something). Board abilities carry the whole
	-- interface in verb-driven games, so silence is not an option.
	-- An ability the card's *zone* grants it counts: the top of a discard pile
	-- you may take from has to say so, or the only discoverable thing about it
	-- is that clicking sometimes does nothing.
	local dim, dim_label
	if react_offer[card_e.id] then
		-- Being asked for beats everything below: inside a window a reaction is
		-- neither playable nor activatable, and it may well be spent as well, so
		-- every other rule here would draw the one live card as dead.
		dim = false
	elseif card_e.exhausted then
		dim, dim_label = true, "exhausted"
	elseif z and z.use == "play" then
		dim = not flow.can_play(card_e.id)
	elseif z and z.use == "abilities" and #cards.abilities(card_e) > 0 then
		dim, dim_label = not flow.can_activate(card_e.id), "not now"
	end

	-- A piece, not a card: no plate behind the art, so the PNG's own
	-- transparency shows whatever the board is painted with. The card colour
	-- would otherwise cover the square it stands on, which on a chessboard means
	-- covering the chessboard.
	local bare = look.color == false

	love.graphics.push("all")
	if not bare then
		love.graphics.setColor(unpack(color))
		love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
	end

	-- The picture gets the whole card. The words float over it, light on a dark
	-- outline and a scrim, rather than being given a slab of colour to sit on —
	-- which is where the height went, and why a hand card showed a stamp-sized
	-- image above two cut-off lines.
	--
	-- It also settles contrast by construction. The old band drew fixed light
	-- text over whatever colour the card chose, so white on a green expedition
	-- was unreadable and no palette could have fixed it: the game picks the
	-- colour. Outlined text on a darkened strip reads on anything.
	local img_h = pl.h

	love.graphics.stencil(function()
		love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
	end, "replace", 1)
	love.graphics.setStencilTest("greater", 0)

	if img then
		local iw, ih = img:getDimensions()
		love.graphics.setScissor(pl.x, pl.y, pl.w, img_h)
		-- A plateless card has nothing to lay a dimming rectangle over — one
		-- would just be a dark square on the board — so it dims by tinting the
		-- art instead, which is how a greyed-out piece has always looked.
		local tint = (bare and dim) and 0.45 or 1
		love.graphics.setColor(tint, tint, tint)
		if bare then
			-- A card crops its art to the width and lets the top of the picture
			-- be the picture. A piece is the whole shape: fit it inside the
			-- square and centre it, or it hangs off the top of a cell that is
			-- taller than it is wide.
			local sc = math.min(pl.w / iw, img_h / ih)
			love.graphics.draw(img, pl.x + (pl.w - iw * sc) * 0.5,
				pl.y + (img_h - ih * sc) * 0.5, 0, sc, sc)
		else
			-- Cover the card rather than fit it: a letterbox of plate colour
			-- under a picture is the band this pass removed, wearing a hat.
			local sc = math.max(pl.w / iw, img_h / ih)
			love.graphics.draw(img, pl.x + (pl.w - iw * sc) * 0.5,
				pl.y + (img_h - ih * sc) * 0.5, 0, sc, sc)
		end
		love.graphics.setScissor()
	end

	-- What the card has to say, and how much room it can have for it. Whole
	-- lines only: the old band clipped mid-glyph at the card's edge, so a
	-- description ended in a row of half-letters. What does not fit is in the
	-- tooltip, which is where the long version always lived.
	if not no_title or body then
		local pad, gap = 3 * S, 2 * S
		local avail    = vis.w - pad * 2
		-- A badge sits in the bottom-left corner, so the words start to its
		-- right rather than under it — clear of what the badges measure rather
		-- than of a fraction of the card, which on a token plate was half its
		-- width for a two-character number. A row shares the bottom edge and
		-- the title gives way from the start; a column's claim on it is decided
		-- below, once the title has a height.
		local stats = card_e.stats
		local down  = look.badge_run == "down"
		local keys  = badge_keys(look, card_e)
		local row_w, col_h = 0, 0
		for i, key in ipairs(keys) do
			local w = badge_size(key, badge_text(key, shown_stat(card_e, key)))
			if down then
				row_w = math.max(row_w, w)
				col_h = col_h + get_small_font():getHeight() + 3 * S
			else
				row_w = row_w + w + (i > 1 and 2 * S or 0)
			end
		end
		if #keys == 0 and stats and stats.hp then
			local hp = shown_stat(card_e, "hp")
			row_w = badge_size("hp", hp .. "/" .. (tags.stat_max(card_e, "hp") or hp))
		end
		local badge_w = down and 0 or row_w

		local tf, shown, title_h = nil, nil, 0
		if not no_title then
			tf, shown, title_h = fit_title(title, avail - badge_w, 12 * S, 8 * S)
			-- A column usually runs down the side and takes none of the title's
			-- line. A short card is the exception — Splendor's nobles are four
			-- requirements on a plate two thirds the height of a market card —
			-- and there the last badge lands in the corner the title starts
			-- from. Which is only knowable once the title has a size, and a
			-- second fit can only make it smaller, so it cannot come back.
			if down and col_h + title_h + pad * 2 > vis.h then
				badge_w = row_w
				tf, shown, title_h = fit_title(title, avail - badge_w, 12 * S, 8 * S)
			end
		end

		-- Prose needs room to be prose. Below about a thumb's width a card can
		-- hold a name or a paragraph, not both, and the name is the half a
		-- player is choosing between — the rest is a hover away.
		local bf, body_h, body_lines = get_small_font(), 0, nil
		if body and show_text and vis.w >= 92 * S then
			local lines = rich.wrap(bf, body, avail)
			local room = vis.h * 0.55 - title_h - pad * 2 - gap
			local n = math.min(#lines, math.max(0, math.floor(room / bf:getHeight())))
			if n > 0 then
				-- Wrapped once and cut here, so what gets drawn is what was counted.
				for i = #lines, n + 1, -1 do lines[i] = nil end
				body_lines, body_h = lines, n * bf:getHeight()
			end
		end

		local band = pad + title_h + (body_h > 0 and (gap + body_h) or 0) + pad
		band = math.min(band, vis.h)
		local top = vis.y + vis.h - band

		-- A dark strip under the words, softest at its top edge so the picture
		-- fades into it instead of ending at a line.
		love.graphics.setScissor(vis.x, vis.y, vis.w, vis.h)
		local steps = 6
		for i = 0, steps - 1 do
			love.graphics.setColor(0, 0, 0, 0.72 * (i / (steps - 1)) ^ 0.6)
			love.graphics.rectangle("fill", vis.x, top + band * i / steps, vis.w, band / steps + 1)
		end

		local y = top + pad
		if not no_title then
			title_y = y
			love.graphics.setFont(tf)
			outlined_printf(shown, vis.x + pad + badge_w, y, avail - badge_w, "center",
				C.card_text, { 0, 0, 0, 0.9 })
			y = y + title_h + gap
		end
		if body_h > 0 then
			rich.draw(bf, body_lines, vis.x + pad, y, avail, "center",
				{ color = C.card_body, outline = { 0, 0, 0, 0.85 } })
		end
		love.graphics.setScissor()
	end
	love.graphics.setStencilTest()

	if def and def.cost and next(def.cost) then
		draw_cost_badge(pl, def.cost, card_e)
	end

	-- The art was already tinted for a plateless card, and "not now" written
	-- across sixteen enemy pieces is noise rather than an explanation: whose
	-- turn it is, a board says by other means.
	if dim and not bare then
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
		if dim_label then
			local sf = get_small_font()
			love.graphics.setFont(sf)
			love.graphics.setColor(0.70, 0.75, 0.85, 0.90)
			printf(dim_label, pl.x, pl.y + pl.h * 0.5 - sf:getHeight() * 0.5,
				pl.w, "center")
		end
	end

	-- Targeting states are triple-encoded — border color, pulsing fill and a
	-- corner marker — so eligibility never rides on hue alone.
	if targeting.active() then
		-- A slot-typed spec's eligibility lives on the *square*, and the piece
		-- standing there is what the player sees and clicks — so ask about the
		-- same thing a click resolves to. Without this a capture target sat
		-- faded under a highlight it was never offered, while the empty square
		-- beside it glowed: the decoration existed all along, nothing asked for
		-- it. Same seam as targeting.aim, and the same one line fixes both.
		local aimed = targeting.aim(card_e.id)
		local marker_col, marker_a = nil, 1
		if card_e.id == targeting.card_id then
			love.graphics.setColor(unpack(C.selected))
			love.graphics.setLineWidth(3 * S)
		elseif targeting.is_selected(aimed) then
			love.graphics.setColor(C.target_chosen[1], C.target_chosen[2], C.target_chosen[3], 0.20)
			love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
			love.graphics.setColor(unpack(C.target_chosen))
			love.graphics.setLineWidth(3 * S)
			marker_col = C.target_chosen
		elseif targeting.is_eligible(aimed) then
			love.graphics.setColor(C.eligible[1], C.eligible[2], C.eligible[3], 0.06 + 0.12 * pulse(5))
			love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
			love.graphics.setColor(unpack(C.eligible))
			love.graphics.setLineWidth(2 * S)
			marker_col, marker_a = C.eligible, 0.4 + 0.6 * pulse(5)
		else
			love.graphics.setColor(unpack(C.faded))
			love.graphics.setLineWidth(S)
		end
		love.graphics.rectangle("line", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
		if marker_col then
			local ms = 10 * S
			love.graphics.setColor(marker_col[1], marker_col[2], marker_col[3], marker_a)
			love.graphics.polygon("fill",
				pl.x, pl.y + 4 * S, pl.x + ms, pl.y + 4 * S + ms * 0.5, pl.x, pl.y + 4 * S + ms)
		end
	elseif card_e.id == selected_id then
		love.graphics.setColor(unpack(C.selected))
		love.graphics.setLineWidth(3 * S)
		love.graphics.rectangle("line", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
	elseif look.border ~= false then
		-- A piece is not a card and should not be drawn inside one. The same
		-- reasoning as `cell_outline` on the board it stands on: the rectangle
		-- is chrome, and a chess knight in a rounded box reads as a card with a
		-- knight on it. Selection and eligibility above still draw, because
		-- those are the affordance rather than the frame.
		love.graphics.setColor(unpack(C.card_border))
		love.graphics.setLineWidth(S)
		love.graphics.rectangle("line", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
	end

	if card_e.attached and #card_e.attached > 0 then
		local sf = get_small_font()
		local bs = sf:getHeight() + 2 * S
		local bx = pl.x + pl.w - bs - 2 * S
		local by = pl.y + 3 * S
		love.graphics.setFont(sf)
		love.graphics.setColor(0.80, 0.60, 1.00)
		love.graphics.rectangle("fill", bx, by, bs, bs, 2 * S, 2 * S)
		love.graphics.setColor(0.05, 0.05, 0.10)
		printf(tostring(#card_e.attached), bx, by + S, bs, "center")
	end

	love.graphics.pop()
	return title_y
end

-- One number in a dark pill, with its icon. Returns the width it took.
local function draw_badge(key, txt, x, y, colour)
	local sf = get_small_font()
	love.graphics.setFont(sf)
	local fh = sf:getHeight()
	local w, ind = badge_size(key, txt)
	love.graphics.setColor(0, 0, 0, 0.65)
	love.graphics.rectangle("fill", x - 1, y - 1, w, fh + 2, 2 * S, 2 * S)
	local icon, tint = stat_icon(key)
	draw_stat_icon(icon, x + fh * 0.5, y + fh * 0.5, fh * 0.9, tint)
	love.graphics.setColor(colour)
	print_at(txt, x + ind + 3 * S, y)
	return w
end

-- The numbers a card wears on its face.
--
-- `hp` is the engine's own: a bar's worth of health, coloured by how much of it
-- is left, and it stays the default so every game written before this is
-- unchanged. Anything else is the game's business — a creature game wants its
-- attack beside its health and neither of them is `hp` — so a style names them
-- and they are drawn left to right along the bottom edge.
--
-- **Or down the left edge, and then a zero may be left out.** Five of them will
-- not fit across a card, which is a printed price: Splendor's ninety market
-- cards carry five costs of which two or three are nothing, and a column
-- reading `0 0 2 0 1` is worse than the abbreviation it replaced. `badge_run`
-- says which way they go and `badge_zeros: false` leaves the empty lines out —
-- separately, because a creature's zero power is a fact and must still draw.
--
-- Without this a card could carry any number of stats and show none of them,
-- which is how a whole combat could resolve correctly and look like nothing had
-- happened.
-- `by` is where the card's own title landed, when it has one and prose under
-- it: the row then shares the title's line instead of printing over the words.
-- Without it the row sits on the bottom edge, which is where the title is on a
-- compact card and so is the same place.
local function draw_card_stats_overlay(pl, card_e, by)
	local stats = card_e and card_e.stats
	if not stats then return end
	local look   = cards.style(card_e)
	local badges = type(look.badges) == "table" and look.badges or nil

	love.graphics.push("all")
	local fh = get_small_font():getHeight()
	by = by or (pl.y + pl.h - fh - 3 * S)
	if badges then
		-- A column starts at the top, where a bottom-anchored row would run off
		-- the card, and the title below it has already made room for whichever
		-- of the two reaches it.
		local down = look.badge_run == "down"
		local x, y = pl.x + 2 * S, down and (pl.y + 3 * S) or by
		for _, key in ipairs(badge_keys(look, card_e)) do
			local w = draw_badge(key, badge_text(key, shown_stat(card_e, key)), x, y, { 1, 1, 1 })
			if down then y = y + fh + 3 * S else x = x + w + 2 * S end
		end
	elseif stats.hp then
		local hp     = shown_stat(card_e, "hp")
		local hp_max = tags.stat_max(card_e, "hp") or hp
		local ratio  = hp_max > 0 and hp / hp_max or 0
		local colour = ratio > 0.6 and { 0.25, 0.95, 0.35 }
			or ratio > 0.3 and { 1.00, 0.82, 0.15 }
			or { 1.00, 0.28, 0.15 }
		draw_badge("hp", hp .. "/" .. hp_max, pl.x + 2 * S, by, colour)
	end
	love.graphics.pop()
end

-- A story page: title, divider, long-form prose, continue hint. Drawn by the
-- built-in reveal overlay in place of a card face.
local function draw_page(pl, card_e)
	local def = cards.def(card_e)
	local mf  = love.graphics.getFont()
	local sf  = get_small_font()

	love.graphics.push("all")
	love.graphics.setColor(0.09, 0.12, 0.19, 0.98)
	love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 6 * S, 6 * S)
	love.graphics.setColor(unpack(C.zone_border))
	love.graphics.setLineWidth(S)
	love.graphics.rectangle("line", pl.x, pl.y, pl.w, pl.h, 6 * S, 6 * S)

	local m = 18 * S
	local y = pl.y + m
	love.graphics.setColor(unpack(C.card_text))
	printf(def and def.text or card_e.def_key, pl.x + m, y, pl.w - m * 2, "center")
	y = y + mf:getHeight() + 8 * S
	love.graphics.setColor(0.28, 0.40, 0.62)
	love.graphics.line(pl.x + m, y, pl.x + pl.w - m, y)
	y = y + 12 * S

	local hint_h = sf:getHeight() + 12 * S
	love.graphics.setScissor(pl.x, y, pl.w, math.max(0, pl.y + pl.h - hint_h - y))
	love.graphics.setColor(0.80, 0.88, 1.00)
	printf(def and (def.story or def.tooltip) or "",
		pl.x + m, y, pl.w - m * 2, "left")
	love.graphics.setScissor()

	love.graphics.setFont(sf)
	love.graphics.setColor(0.45, 0.60, 0.80, 0.55 + 0.35 * pulse(3))
	printf("click to continue", pl.x, pl.y + pl.h - hint_h + 4 * S, pl.w, "center")
	love.graphics.pop()
end

-- A picture behind a whole zone: the painted board most games have. Stretched
-- to the zone's rect, because that rect is what the cells are computed from —
-- an image that kept its own proportions would drift out of step with them.
local function draw_zone_art(zone_e)
	local img = zone_e.asset and cards.asset_image(zone_e.asset, "zone:" .. zone_e.key)
	if not img then return end
	local p      = zone_e.place
	local iw, ih = img:getDimensions()
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1)
	love.graphics.draw(img, p.x, p.y, 0, p.w / iw, p.h / ih)
	love.graphics.pop()
end

-- Individual squares, named by an absolute pattern and given a colour or a
-- picture: terrain, a goal row, the thrones in the middle. Patterns already
-- name sets of cells and are already checked, so this needs no second way of
-- saying which squares are meant.
local function draw_painted_squares(zone_e)
	if not (zone_e.style.paint and zone_e.slots) then return end
	love.graphics.push("all")
	for name, look in pairs(zone_e.style.paint) do
		local col = art.colour(look)
		local img = not col and cards.asset_image(look, "paint:" .. tostring(look)) or nil
		for _, slot_id in ipairs(predicate.pattern_slots(name)) do
			local slot = entity.get(slot_id)
			if slot and slot.zone_id == zone_e.id then
				local p = zones.cell_rect(zone_e, slot.slot_idx, 0)
				love.graphics.setColor(1, 1, 1)
				if col then
					love.graphics.setColor(unpack(col))
					love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
				elseif img then
					local iw, ih = img:getDimensions()
					love.graphics.draw(img, p.x, p.y, 0, p.w / iw, p.h / ih)
				end
			end
		end
	end
	love.graphics.pop()
end

-- A board's own squares, alternating two colours — which is what a chessboard,
-- a draughts board and a battle map all are. Drawn under everything, including
-- occupied cells, and edge to edge (pad 0) rather than on the card footprint:
-- squares that tile with gaps between them do not read as a board.
--
-- Which square takes which colour is `zones.chequer_index`, because it is a fact
-- about the board and not about drawing — and because a1 being dark is testable
-- headless, where this function is not.
-- Colours are the same words a card's art uses — a palette name or "#rrggbb" —
-- so there is one colour vocabulary rather than two.
local function draw_grid_squares(zone_e)
	local c = zone_e.style.chequer
	if not (c and zone_e.slots and zone_e.grid) then return end
	local a, b = art.colour(c[1]), art.colour(c[2])
	if not (a and b) then return end
	love.graphics.push("all")
	for idx, slot_id in pairs(zone_e.slots) do
		local slot = entity.get(slot_id)
		if slot and slot.stats then
			local p = zones.cell_rect(zone_e, idx, 0)
			love.graphics.setColor(unpack(zones.chequer_index(slot) == 1 and a or b))
			love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
		end
	end
	love.graphics.pop()
end

-- The outline on an empty cell is what a board looks like when it has no art of
-- its own, so it is the right default — and wrong on a painted one, where it is
-- a rounded rectangle drawn inside a square somebody chose the colour of.
-- The style property `cell_outline: false` drops it.
--
-- Eligibility during targeting is not chrome and is drawn either way: it is the
-- only thing telling a player where a piece may go, and a chessboard that hides
-- it is a chessboard nobody can move on.
local function draw_grid_empty(zone_e)
	if not zone_e.slots then return end
	local bare = zone_e.style.cell_outline == false
	love.graphics.push("all")
	for _, slot_id in pairs(zone_e.slots) do
		local slot = entity.get(slot_id)
		local lit  = targeting.active() and targeting.is_eligible(slot_id)
		if slot and not slot.occupant and (lit or not bare) then
			-- Match the card footprint, so an empty slot reads as the same
			-- shape as the card that would fill it.
			local p = fit_card(slot.place, zone_e.style.fit)
			if lit then
				love.graphics.setColor(C.eligible[1], C.eligible[2], C.eligible[3],
					0.10 + 0.14 * pulse(5))
				love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 3 * S, 3 * S)
				love.graphics.setColor(C.eligible[1], C.eligible[2], C.eligible[3], 0.90)
				love.graphics.setLineWidth(2 * S)
			else
				local dim = targeting.active() and 0.6 or 1
				love.graphics.setColor(0.08 * dim, 0.12 * dim, 0.20 * dim, 0.80)
				love.graphics.setLineWidth(S)
			end
			love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 3 * S, 3 * S)
		end
	end
	love.graphics.pop()
end

-- A zone's name, laid across the top of it and under whatever it holds — so an
-- empty one says what it is waiting for and a full one is covered by the cards.
-- Drawn for every kind that has room for it, which now includes grids and
-- hands: LoR's bench, Splendor's nobles and its bank all named themselves and
-- drew nothing, and an empty hand with a name on it is the case that made it
-- obvious — a box saying nothing is not a zone a player can learn.
-- A zone's label is normally a fixed word, and two things a board most wants to
-- say are not fixed: which phase it is in and whose turn it is. Both are read
-- off the engine every frame, so they are reserved words rather than text a
-- game could keep in step by hand. Only the drawing substitutes — the log still
-- names the zone by what the file called it.
local LIVE_LABEL = {
	current_phase = function()
		local cur = phase.current()
		return cur and (cur.label or cur.key)
	end,
	current_player = function()
		local seat = zones.active_seat()
		local def  = seat and declaration.G.card_defs[seat]
		return def and def.text or seat
	end,
}

local function draw_zone_label(zone_e)
	local text = zone_e.label
	local live = text and LIVE_LABEL[text]
	if live then text = live() end
	if not text then return end
	local p = zone_e.place
	love.graphics.push("all")
	love.graphics.setColor(0.30, 0.42, 0.60, 0.65)
	printf(text, p.x + 2, p.y + 3 * S, p.w - 4, "center")
	love.graphics.pop()
end

local function draw_zone(zone_e)
	local p  = zone_e.place
	local zt = zone_e.layout

	love.graphics.push("all")
	-- A zone can be a target in its own right, and eligibility never rides on
	-- hue alone: border colour, a pulsing fill, and the same blue every other
	-- eligible thing wears.
	if targeting.active() and targeting.is_eligible(zone_e.id) then
		love.graphics.setColor(C.eligible[1], C.eligible[2], C.eligible[3],
			0.10 + 0.14 * pulse(5))
		love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 7 * S, 7 * S)
		love.graphics.setColor(C.eligible[1], C.eligible[2], C.eligible[3], 0.90)
		love.graphics.setLineWidth(2 * S)
	elseif #zone_e.cards == 0 and not zone_e.label and zt ~= "grid" then
		-- A box with nothing in it and no name on it tells a player nothing.
		-- Lost Cities' scoring tray is empty from the first move until the
		-- tally, and drew a wide blank rectangle across the bottom of the board
		-- for the whole game. A grid is exempt: its empty cells *are* the thing,
		-- because they are where a card may be put.
		love.graphics.pop()
		return
	else
		love.graphics.setColor(unpack(C.zone_fill))
		love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 7 * S, 7 * S)
		love.graphics.setColor(unpack(C.zone_border))
		love.graphics.setLineWidth(S)
	end
	love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 7 * S, 7 * S)
	love.graphics.pop()

	local places = card_places(zone_e)
	local fh     = love.graphics.getFont():getHeight()

	if zone_e.row then
		draw_zone_label(zone_e)
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id, places[i]) then
				local c = entity.get(card_id)
				if zone_e.visibility == "secret" or not zones.visible(c) then
					draw_card_back(places[i])
				else
					draw_card_face(places[i], c, false,
						fan_visible(places[i], places[i + 1], zone_e.row))
				end
			end
		end
	elseif zt == "stack" and zone_e.use == "none" and zone_e.label then
		local cur = phase.current()
		if cur and cur.deck == zone_e.key then
			love.graphics.push("all")
			love.graphics.setColor(0.14, 0.30, 0.52, 0.70)
			love.graphics.rectangle("fill", p.x + 1, p.y + 1, p.w - 2, p.h - 2, 6 * S, 6 * S)
			love.graphics.pop()
		end
		-- Card-back stack so a labeled deck still reads as a pile of cards.
		if #zone_e.cards > 0 then
			local pl = places[1]
			love.graphics.push("all")
			for i = 2, 1, -1 do
				love.graphics.setColor(0.16, 0.24, 0.40)
				love.graphics.rectangle("line",
					pl.x + i * 2.5 * S, pl.y + i * 2.5 * S, pl.w, pl.h, 5 * S, 5 * S)
			end
			love.graphics.pop()
			draw_card_back(pl)
		end
		love.graphics.push("all")
		local band_h = fh * 2 + 8 * S
		local band_y = p.y + (p.h - band_h) * 0.5
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", p.x + 3 * S, band_y, p.w - 6 * S, band_h, 3 * S, 3 * S)
		love.graphics.setColor(unpack(C.card_text))
		printf(truncate(love.graphics.getFont(), zone_e.label, p.w - 10 * S),
			p.x + 5 * S, band_y + 3 * S, p.w - 10 * S, "center")
		love.graphics.setColor(0.55, 0.72, 1.00)
		printf(tostring(#zone_e.cards),
			p.x + 5 * S, band_y + fh + 5 * S, p.w - 10 * S, "center")
		love.graphics.pop()
	elseif zt == "stack" and zone_e.use == "none" then
		if #zone_e.cards > 0 then
			local top = entity.get(zone_e.cards[#zone_e.cards])
			if zone_e.visibility ~= "secret" then
				draw_card_face(places[1], top, false)
			else
				draw_card_back(places[1])
			end
			love.graphics.push("all")
			love.graphics.setColor(unpack(C.deck_count))
			printf(tostring(#zone_e.cards), p.x, p.y + p.h - fh - 5 * S, p.w, "center")
			love.graphics.pop()
		end
	elseif zt == "stack" then
		if #zone_e.cards > 0 then
			local top = entity.get(zone_e.cards[#zone_e.cards])
			if not anim.visual_place(top.id, top.place) then
				if zone_e.visibility == "secret" then
					draw_card_back(places[1])
				else
					draw_card_face(places[1], top, false)
				end
			end
		end
		draw_zone_label(zone_e)
	elseif zt == "grid" then
		draw_zone_art(zone_e)
		draw_grid_squares(zone_e)
		draw_painted_squares(zone_e)
		draw_grid_empty(zone_e)
		draw_zone_label(zone_e)
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id, places[i]) then
				local c = entity.get(card_id)
				draw_card_face(places[i], c, false)
				draw_card_stats_overlay(places[i], c)
			end
		end
	else
		-- hand and other zones: show description text on the card
		draw_zone_label(zone_e)
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id, places[i]) then
				local c = entity.get(card_id)
				if zt == "page" then
					draw_page(places[i], c)
				elseif not zones.visible(c) then
					-- Somebody else's hand. Backs, so the cards are still there
					-- to count — how many an opponent holds is public in every
					-- card game — and the faces are not.
					draw_card_back(places[i])
				else
					-- The face already left room for the badges; drawing them
					-- was the half that only grids did, so a chip in hand wore
					-- a hole where its numbers belong.
					draw_card_stats_overlay(places[i], c, draw_card_face(places[i], c, true))
				end
			end
		end
	end
end

local function draw_stats()
	local G  = declaration.G
	local W  = love.graphics.getWidth()
	local mf = love.graphics.getFont()
	local fh = mf:getHeight()
	local y  = 10 * S
	local x  = W - 10 * S
	stat_hud = {}
	love.graphics.push("all")
	local cur = phase.current()
	if cur and cur.label then
		love.graphics.setColor(0.70, 0.88, 1.00)
		print_at(cur.label, x - mf:getWidth(cur.label), y)
		y = y + fh + 8 * S
	end
	-- Your numbers, not the numbers of whoever is to move. The two are the same
	-- seat at one screen and two seats over a network, where a row reading
	-- "Your score" would otherwise report the opponent's while they think.
	zones.as_seat(zones.watching(), function()
		for _, key in ipairs(G.stat_defs_list or {}) do
			local def = G.stat_defs[key]
			if not (def and def.tags_set and def.tags_set.hidden) then
				local label = def and (def.label or key) or key
				local txt   = label .. ": " .. tostring(predicate.total(def and def.subject or key))
				local tw    = mf:getWidth(txt)
				local icon, tint = stat_icon(key)
				local ind   = icon ~= "none" and fh or 0
				local row_x = x - tw - ind - 4 * S
				draw_stat_icon(icon, row_x + fh * 0.5, y + fh * 0.5, fh * 0.85, tint)
				love.graphics.setColor(unpack(C.stat))
				print_at(txt, row_x + ind + 4 * S, y)
				stat_hud[key] = { x = row_x + ind + tw * 0.5, y = y }
				y = y + fh + 5 * S
			end
		end
	end)
	love.graphics.pop()
end

local function bezier(t, x0, y0, x1, y1, x2, y2)
	local u = 1 - t
	local a, b, c = u * u, 2 * u * t, t * t
	return a * x0 + b * x1 + c * x2, a * y0 + b * y1 + c * y2
end

-- Filled chevron (">") at px,py pointing along ang. Split into two triangles
-- because LÖVE only fills convex polygons.
local function draw_chevron(px, py, ang, s)
	local ca, sa = math.cos(ang), math.sin(ang)
	local nx, ny = -sa, ca
	local tx, ty = px + ca * s, py + sa * s
	local ix, iy = px - ca * s * 0.15, py - sa * s * 0.15
	love.graphics.polygon("fill", tx, ty,
		px - ca * s * 0.6 + nx * s * 0.85, py - sa * s * 0.6 + ny * s * 0.85, ix, iy)
	love.graphics.polygon("fill", tx, ty, ix, iy,
		px - ca * s * 0.6 - nx * s * 0.85, py - sa * s * 0.6 - ny * s * 0.85)
end

-- Curved targeting arrow: a bezier arcing up from the source card to the
-- cursor, chevrons marching along it, hot-colored over a valid target.
local function draw_targeting_arrow()
	if not targeting.active() then return end
	local c = entity.get(targeting.card_id)
	if not c or not c.place then return end

	local pl = c.place
	local sx, sy = pl.x + pl.w * 0.5, pl.y + pl.h * 0.5
	local mx, my = love.mouse.getPosition()
	local dx, dy = mx - sx, my - sy
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist < 8 then return end

	local bx = (sx + mx) * 0.5
	local by = (sy + my) * 0.5 - math.min(150 * S, dist * 0.35)

	local hot = false
	for _, id in ipairs(targeting.eligible) do
		local e = entity.get(id)
		if e and e.place and zones.contains(e.place, mx, my) then hot = true; break end
	end
	local col   = hot and C.target_chosen or C.eligible
	local now   = love.timer.getTime()
	local pw    = 0.7 + 0.3 * math.sin(now * 6)

	love.graphics.push("all")

	-- soft base curve under the chevrons
	local line = {}
	for i = 0, 24 do
		local px, py = bezier(i / 24, sx, sy, bx, by, mx, my)
		line[#line + 1] = px
		line[#line + 1] = py
	end
	love.graphics.setColor(col[1], col[2], col[3], 0.16 * pw)
	love.graphics.setLineWidth(7 * S)
	love.graphics.line(line)
	love.graphics.setColor(col[1], col[2], col[3], 0.35 * pw)
	love.graphics.setLineWidth(2 * S)
	love.graphics.line(line)

	-- chevrons marching from the card toward the cursor, growing on the way
	local n     = math.max(4, math.floor(dist / (46 * S)))
	local march = (now * 0.8) % (1 / n)
	for i = 0, n - 1 do
		local tt = i / n + march
		if tt > 0.05 and tt < 0.90 then
			local px, py = bezier(tt, sx, sy, bx, by, mx, my)
			local qx, qy = bezier(math.min(1, tt + 0.02), sx, sy, bx, by, mx, my)
			love.graphics.setColor(col[1], col[2], col[3], (0.25 + 0.6 * tt) * pw)
			draw_chevron(px, py, math.atan2(qy - py, qx - px), (6 + 8 * tt) * S)
		end
	end

	-- glow and arrowhead at the cursor
	love.graphics.setColor(col[1], col[2], col[3], 0.22 * pw)
	love.graphics.circle("fill", mx, my, (16 + 3 * pw) * S)
	love.graphics.setColor(col[1], col[2], col[3], 0.95)
	draw_chevron(mx, my, math.atan2(my - by, mx - bx), 16 * S)

	love.graphics.pop()
end

-- A labeled tap-target. Registers its rect in `buttons` for hit-testing.
local function draw_button(name, label, x, y, w, h)
	buttons[name] = { x = x, y = y, w = w, h = h }
	love.graphics.setColor(unpack(C.button_fill))
	love.graphics.rectangle("fill", x, y, w, h, 4 * S, 4 * S)
	love.graphics.setColor(unpack(C.button_border))
	love.graphics.setLineWidth(S)
	love.graphics.rectangle("line", x, y, w, h, 4 * S, 4 * S)
	love.graphics.setColor(unpack(C.card_text))
	local mf = love.graphics.getFont()
	print_at(label, x + (w - mf:getWidth(label)) * 0.5,
		y + (h - mf:getHeight()) * 0.5)
end

-- What is announced and waiting to be answered, across the top. Nothing else on
-- screen says a window is open — the turn has not moved and the phase has not
-- changed — and the seat it is open for is being asked a question they never
-- clicked for, so it is stated and given a way out.
--
-- The top, because the bottom bar belongs to targeting and a reaction that aims
-- at something raises one while this is still up.
local function draw_react_hint()
	local top = flow.pending_event()
	if not top then return end
	local W     = love.graphics.getWidth()
	local mf    = love.graphics.getFont()
	local bar_h = mf:getHeight() + 14 * S
	local names = {}
	for _, id in ipairs(top.re_subject) do
		local c = entity.get(id)
		if c then names[#names + 1] = (cards.def(c) or {}).text or c.def_key end
	end
	local msg = table.concat(names, ", ") .. ": " .. top.re_verb
		.. "   —   " .. tostring(zones.active_seat()) .. " to answer"
	-- As wide as it needs and no wider. A full-width bar would lie across the
	-- stat row in the far corner, which is exactly what a player weighing whether
	-- to answer is reading.
	local pw = mf:getWidth("Pass") + 20 * S
	local bw = math.min(W, mf:getWidth(msg) + pw + 32 * S)
	love.graphics.push("all")
	love.graphics.setColor(0.00, 0.00, 0.00, 0.82)
	love.graphics.rectangle("fill", 0, 0, bw, bar_h)
	love.graphics.setColor(1.00, 0.88, 0.55)
	print_at(msg, 12 * S, 7 * S)
	draw_button("pass", "Pass", bw - pw - 8 * S, 3 * S, pw, bar_h - 6 * S)
	love.graphics.pop()
end

local function draw_targeting_hint()
	if not targeting.active() then return end
	local W, H  = love.graphics.getDimensions()
	local mf    = love.graphics.getFont()
	local fh    = mf:getHeight()
	local bar_h = fh + 14 * S
	local spec  = targeting.spec
	local n_sel = #targeting.targets
	local msg
	if spec.min == spec.max then
		msg = string.format("Select %d target(s)  [%d/%d chosen]", spec.max, n_sel, spec.max)
	else
		msg = string.format("Select %d-%d target(s)  [%d chosen, %d eligible]",
			spec.min, spec.max, n_sel, #targeting.eligible)
	end
	love.graphics.push("all")
	love.graphics.setColor(0.00, 0.00, 0.00, 0.82)
	love.graphics.rectangle("fill", 0, H - bar_h, W, bar_h)
	love.graphics.setColor(0.75, 0.92, 1.00)
	print_at(msg, 12 * S, H - bar_h + 7 * S)

	-- tap-friendly confirm/cancel, mirrored by Enter / Esc
	local bh = bar_h - 6 * S
	local bx = W - 8 * S
	local cw = mf:getWidth("Cancel") + 20 * S
	draw_button("cancel", "Cancel", bx - cw, H - bar_h + 3 * S, cw, bh)
	bx = bx - cw - 8 * S
	if targeting.can_confirm() then
		local kw = mf:getWidth("Confirm") + 20 * S
		draw_button("confirm", "Confirm", bx - kw, H - bar_h + 3 * S, kw, bh)
	end
	love.graphics.pop()
end

local function draw_undo_button()
	if targeting.active() or not can_undo then return end
	local H  = love.graphics.getHeight()
	local mf = love.graphics.getFont()
	local w  = mf:getWidth("Undo (Z)") + 20 * S
	local h  = mf:getHeight() + 10 * S
	love.graphics.push("all")
	draw_button("undo", "Undo (Z)", 8 * S, H - h - 8 * S, w, h)
	love.graphics.pop()
end

-- Corner event log; L toggles the expanded view. Undo shortens it live.
local log_expanded = false

function M.toggle_log()
	log_expanded = not log_expanded
end

local function draw_log()
	local lines = log.tail(log_expanded and 24 or 3)
	if #lines == 0 then return end
	local sf = get_small_font()
	local fh = sf:getHeight()
	local H  = love.graphics.getHeight()
	local w  = (log_expanded and 320 or 170) * S
	local h  = #lines * (fh + 2 * S) + 8 * S

	local bottom = 10 * S
	local mf_h   = love.graphics.getFont():getHeight()
	if targeting.active() then
		bottom = bottom + mf_h + 14 * S
	elseif can_undo then
		bottom = bottom + mf_h + 18 * S
	end
	local x, y = 8 * S, H - bottom - h

	love.graphics.push("all")
	love.graphics.setFont(sf)
	love.graphics.setColor(0, 0, 0, log_expanded and 0.88 or 0.65)
	love.graphics.rectangle("fill", x, y, w, h, 3 * S, 3 * S)
	for i, line in ipairs(lines) do
		local a = log_expanded and 0.95 or (0.55 + 0.40 * (i / #lines))
		love.graphics.setColor(0.75, 0.85, 1.00, a)
		print_at(truncate(sf, line, w - 22 * S),
			x + 4 * S, y + 4 * S + (i - 1) * (fh + 2 * S))
	end
	love.graphics.setColor(0.45, 0.60, 0.80, 0.75)
	print_at("L", x + w - fh - 3 * S, y + 4 * S)
	love.graphics.pop()
end

-- A mid-flight card: drawn at its interpolated rect, tilted into its motion.
local function draw_flying_card(vpl, card_e)
	love.graphics.push()
	if vpl.rot and vpl.rot ~= 0 then
		local cx, cy = vpl.x + vpl.w * 0.5, vpl.y + vpl.h * 0.5
		love.graphics.translate(cx, cy)
		love.graphics.rotate(vpl.rot)
		love.graphics.translate(-cx, -cy)
	end
	draw_card_face(vpl, card_e, false)
	love.graphics.pop()
end

local function draw_animated_cards()
	for z in entity.each("zone") do
		if z.display ~= "offscreen" then
			local list = z.layout == "stack" and { z.cards[#z.cards] } or z.cards
			for _, cid in ipairs(list or {}) do
				local vpl = cid and anim.visual_place(cid, (entity.get(cid) or {}).place)
				if vpl then draw_flying_card(vpl, entity.get(cid)) end
			end
		end
	end
end

-- Full-screen browse view of a zone's cards (right-click on a face-up pile).
local function draw_zone_browse(zone_e)
	local W, H = love.graphics.getDimensions()
	local n    = #zone_e.cards
	local gap  = 10 * S

	love.graphics.push("all")
	love.graphics.setColor(unpack(C.card_text))
	printf((zone_e.label or zone_e.key) .. "  (" .. n .. ")", 0, 18 * S, W, "center")

	-- Pick the shape of the grid, rather than the width of a card and then
	-- however many rows that needs. The old way fixed the columns from an
	-- uncapped card width and shrank the cards to fit the height, so a big deck
	-- came out as six columns of stamps with the sides of the screen empty:
	-- forty-four cards were 40px wide and titled "Whit…".
	local avail_w, avail_h = W - 40 * S, H - 100 * S
	local cols, cw = 1, 0
	for c = 1, n do
		local r = math.ceil(n / c)
		local w = math.min(130 * S, avail_w / c - gap, (avail_h / r - gap) / CARD_RATIO)
		if w > cw then cols, cw = c, w end
	end
	local rows = math.ceil(n / cols)
	local ch   = cw * CARD_RATIO
	local x0 = (W - math.min(n, cols) * (cw + gap) + gap) / 2
	local y0 = 55 * S

	for i, cid in ipairs(zones.browse_order(zone_e)) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local pl  = { x = x0 + col * (cw + gap), y = y0 + row * (ch + gap), w = cw, h = ch }
		local c   = entity.get(cid)
		if zones.visible(c) then
			draw_card_face(pl, c, false)
			draw_card_stats_overlay(pl, c)
		else
			draw_card_back(pl)
		end
	end
	love.graphics.pop()
end

-- Detail panel for a single card: big face plus name, description, stats, tags.
local function draw_card_detail(card_e)
	local def  = cards.def(card_e)
	local W, H = love.graphics.getDimensions()
	local main_font = love.graphics.getFont()

	love.graphics.push("all")

	-- Card: up to 36% of screen width, respecting aspect ratio and screen height.
	local card_w = math.min(math.floor(W * 0.36), math.floor(H * 0.84 / CARD_RATIO))
	local card_h = math.floor(card_w * CARD_RATIO)
	local card_x = math.floor(W * 0.07)
	local card_y = math.floor((H - card_h) * 0.5)

	draw_card_face({ x = card_x, y = card_y, w = card_w, h = card_h }, card_e, false)

	-- Info panel to the right of the card.
	local info_x = card_x + card_w + 28 * S
	local info_y = card_y
	local info_w = W - info_x - 20 * S

	if info_w > 80 * S then
		local y = info_y

		love.graphics.setColor(1.00, 1.00, 1.00)
		printf(def and def.text or card_e.def_key, info_x, y, info_w, "left")
		y = y + main_font:getHeight() + 8 * S

		love.graphics.setColor(0.28, 0.40, 0.62)
		love.graphics.setLineWidth(S)
		love.graphics.line(info_x, y, info_x + info_w, y)
		y = y + 10 * S

		if def and def.cost and next(def.cost) then
			love.graphics.setColor(unpack(C.cost))
			print_at("Cost: " .. cards.cost_text(def.cost, card_e and card_e.id), info_x, y)
			y = y + main_font:getHeight() + 8 * S
		end

		local tooltip = def and def.tooltip or ""
		if tooltip ~= "" then
			love.graphics.setColor(0.82, 0.91, 1.00)
			printf(tooltip, info_x, y, info_w, "left")
			local _, wrapped = main_font:getWrap(tooltip, info_w)
			y = y + #wrapped * main_font:getHeight() + 14 * S
		end

		-- What the card's keywords mean, said once by the game rather than copied
		-- onto every card that has one. This is the panel a player opens *to
		-- find out*, so it is the one place the sentence has to appear.
		for _, kw in ipairs(cards.keywords(card_e)) do
			if kw.text ~= tooltip then
				love.graphics.setColor(0.72, 0.86, 0.98)
				printf(kw.text, info_x, y, info_w, "left")
				local _, wrapped = main_font:getWrap(kw.text, info_w)
				y = y + #wrapped * main_font:getHeight() + 8 * S
			end
		end

		local story = def and def.story or ""
		if story ~= "" then
			love.graphics.setColor(0.68, 0.78, 0.94)
			printf(story, info_x, y, info_w, "left")
			local _, swrapped = main_font:getWrap(story, info_w)
			y = y + #swrapped * main_font:getHeight() + 14 * S
		end

		local stats = card_e.stats
		if stats and next(stats) then
			love.graphics.setColor(0.55, 0.70, 0.90)
			print_at("Stats:", info_x, y)
			y = y + main_font:getHeight() + 4 * S
			local caps = card_e.stat_max or {}
			for k in pairs(stats) do
				local v   = tags.stat(card_e, k)
				local hi  = caps[k] and tags.stat_max(card_e, k)
				local val = hi and (v .. "/" .. hi) or tostring(v)
				love.graphics.setColor(0.78, 0.92, 1.00)
				print_at("  " .. k .. ": " .. val, info_x, y)
				y = y + main_font:getHeight()
			end
			y = y + 10 * S
		end

		if def and def.tags_set and next(def.tags_set) then
			love.graphics.setColor(0.55, 0.70, 0.90)
			love.graphics.setFont(main_font)
			print_at("Tags:", info_x, y)
			y = y + main_font:getHeight() + 4 * S

			local sf = get_small_font()
			love.graphics.setFont(sf)
			local tx = info_x
			for tag in pairs(def.tags_set) do
				local tw = sf:getWidth(tag) + 10 * S
				if tx + tw > info_x + info_w then
					tx = info_x
					y  = y + sf:getHeight() + 6 * S
				end
				love.graphics.setColor(0.14, 0.22, 0.40)
				love.graphics.rectangle("fill", tx, y, tw, sf:getHeight() + 4 * S, 3 * S, 3 * S)
				love.graphics.setColor(0.35, 0.52, 0.80)
				love.graphics.rectangle("line", tx, y, tw, sf:getHeight() + 4 * S, 3 * S, 3 * S)
				love.graphics.setColor(0.78, 0.90, 1.00)
				print_at(tag, tx + 5 * S, y + 2 * S)
				tx = tx + tw + 5 * S
			end
		end
	end

	love.graphics.pop()
end

-- Full-screen detail overlay shown on right-click or long-press.
local function draw_detail_overlay()
	if not detail_id then return end
	local e = entity.get(detail_id)
	if not e then detail_id = nil; return end
	local W, H = love.graphics.getDimensions()

	love.graphics.push("all")
	love.graphics.setColor(0, 0, 0, 0.88)
	love.graphics.rectangle("fill", 0, 0, W, H)

	if e.kind == "zone" then
		draw_zone_browse(e)
	else
		draw_card_detail(e)
	end

	love.graphics.setColor(0.38, 0.52, 0.70)
	printf("Click or tap anywhere to close",
		0, H - love.graphics.getFont():getHeight() - 10 * S, W, "center")
	love.graphics.pop()
end

function M.draw()
	if not font_main then M.rescale() end
	love.graphics.clear(unpack(C.bg))
	buttons = {}
	react_offer = {}
	for _, u in ipairs(flow.usable_reactions()) do react_offer[u.card] = true end

	-- Impacts kick the whole scene; UI overlays below stay put.
	local shx, shy = fx.shake_offset()
	love.graphics.push()
	love.graphics.translate(shx, shy)

	for z in entity.each("zone") do
		if z.display ~= "offscreen" then draw_zone(z) end
	end
	draw_animated_cards()
	fx.draw()
	draw_stats()

	-- Overlay phase: dim everything, then draw its offer zone (and any cards
	-- still flying into it) on top of the dim.
	local outcome = flow.outcome()
	if not outcome then celebrated = false end
	if phase.is_overlay() then
		local W, H = love.graphics.getDimensions()
		love.graphics.push("all")
		love.graphics.setColor(unpack(C.overlay_dim))
		love.graphics.rectangle("fill", 0, 0, W, H)
		love.graphics.pop()

		local cur = phase.current()
		local oz  = zones.find(cur.zone or "hand")
		if oz then
			if cur.label then
				love.graphics.push("all")
				love.graphics.setColor(unpack(C.card_text))
				printf(cur.label, 0, oz.place.y - 30 * S, W, "center")
				love.graphics.pop()
			end
			draw_zone(oz)
			for _, cid in ipairs(oz.cards) do
				local vpl = anim.visual_place(cid, (entity.get(cid) or {}).place)
				if vpl then draw_flying_card(vpl, entity.get(cid)) end
			end
			-- The way out of a question that may go unanswered, under the cards
			-- it is about. Right-click and Escape do the same thing and always
			-- did; neither is discoverable, and on a touch screen neither
			-- exists.
			if flow.can_dismiss() then
				local mf = love.graphics.getFont()
				local bw = mf:getWidth("No choice") + 24 * S
				local bh = mf:getHeight() + 12 * S
				draw_button("no_choice", "No choice",
					oz.place.x + (oz.place.w - bw) * 0.5, oz.place.y + oz.place.h + 8 * S, bw, bh)
			end
		end

		-- An ending screen announces itself: banner, run summary, flourish.
		if outcome then
			local lost = outcome == "defeat"
			if not celebrated then
				fx.celebrate(lost and "defeat" or "victory")
				celebrated = true
			end
			-- Nobody at this screen has claimed a seat, so there is no "you" to
			-- congratulate: the room is told who won, rather than one of the two
			-- people in it being told they lost.
			local btxt = outcome == "decided" and ((flow.winner() or "Nobody") .. " wins")
				or (lost and "Defeat" or "Victory")
			local col  = lost and { 0.95, 0.32, 0.26 } or { 1.00, 0.84, 0.30 }
			love.graphics.push("all")
			love.graphics.setFont(font_banner)
			love.graphics.setColor(0, 0, 0, 0.80)
			printf(btxt, 0, 10 * S + 2 * S, W, "center")
			love.graphics.setColor(unpack(col))
			printf(btxt, 0, 10 * S, W, "center")
			local summary = table.concat(flow.summary(), "    ·    ")
			if summary ~= "" then
				love.graphics.setFont(font_main)
				love.graphics.setColor(0.85, 0.90, 1.00, 0.95)
				printf(summary, 0, 10 * S + font_banner:getHeight() + 4 * S, W, "center")
			end
			love.graphics.pop()
		end
	end

	love.graphics.pop()

	fx.draw_celebration()
	draw_targeting_arrow()
	draw_react_hint()
	draw_targeting_hint()
	draw_log()
	draw_undo_button()
	draw_detail_overlay()
end

-- Sync card.place (used for hit-testing, tooltips and as the animation target)
-- with the current layout. Runs every frame from love.update; position changes
-- kick off a tween from the old rect.
function M.sync_places()
	for z in entity.each("zone") do
		local places = card_places(z)
		local zt     = z.layout
		local kind   = zt == "grid" and "slam"
			or zt == "stack" and "drop" or "glide"
		-- A stack keeps one place, because only its top card is ever drawn or
		-- clicked. A fanned one shows every card, so every card needs one — miss
		-- this and the fan draws correctly and answers the mouse from wherever
		-- its cards used to be.
		local list   = zt == "stack" and { z.cards[#z.cards] } or z.cards
		for i, cid in ipairs(list) do
			local c   = cid and entity.get(cid)
			local new = places[i]
			if c and new then
				if c.place and c.place.w > 0 then anim.move(c.id, c.place, new, kind) end
				c.place = new
			end
		end
	end
end

function M.set_selected(id) selected_id = id end
function M.get_selected()   return selected_id end
function M.set_detail(id)   detail_id = id end
function M.get_detail()     return detail_id end

return M
