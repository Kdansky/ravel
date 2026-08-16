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
	end
	return font_cache[px]
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
-- Keys are conventions (gold/hp/defense/morale/food); anything else gets a diamond.
local ICON_COLOR = {
	gold    = { 0.95, 0.78, 0.25 },
	hp      = { 0.92, 0.32, 0.32 },
	health  = { 0.92, 0.32, 0.32 },
	power   = { 0.98, 0.72, 0.30 },
	defense = { 0.55, 0.70, 0.90 },
	morale  = { 0.78, 0.55, 0.95 },
	food    = { 0.55, 0.85, 0.40 },
}

local function draw_stat_icon(key, cx, cy, s)
	local col = ICON_COLOR[key] or { 0.60, 0.70, 0.85 }
	love.graphics.setColor(unpack(col))
	if key == "gold" then
		love.graphics.circle("fill", cx, cy, s * 0.42)
		love.graphics.setColor(col[1] * 0.6, col[2] * 0.6, col[3] * 0.6)
		love.graphics.circle("line", cx, cy, s * 0.24)
	elseif key == "hp" or key == "health" then
		love.graphics.circle("fill", cx - s * 0.18, cy - s * 0.12, s * 0.24)
		love.graphics.circle("fill", cx + s * 0.18, cy - s * 0.12, s * 0.24)
		love.graphics.polygon("fill",
			cx - s * 0.40, cy - s * 0.02, cx + s * 0.40, cy - s * 0.02, cx, cy + s * 0.44)
	elseif key == "power" then
		-- A blade: the other half of every creature card ever printed.
		love.graphics.polygon("fill",
			cx - s * 0.08, cy + s * 0.44, cx + s * 0.10, cy + s * 0.44,
			cx + s * 0.10, cy - s * 0.18, cx + s * 0.01, cy - s * 0.46,
			cx - s * 0.08, cy - s * 0.18)
		love.graphics.rectangle("fill", cx - s * 0.28, cy + s * 0.16, s * 0.56, s * 0.10)
	elseif key == "defense" then
		love.graphics.polygon("fill",
			cx - s * 0.35, cy - s * 0.38, cx + s * 0.35, cy - s * 0.38,
			cx + s * 0.35, cy + s * 0.02, cx, cy + s * 0.44, cx - s * 0.35, cy + s * 0.02)
	elseif key == "morale" then
		love.graphics.setLineWidth(math.max(1, s * 0.12))
		love.graphics.line(cx - s * 0.28, cy - s * 0.42, cx - s * 0.28, cy + s * 0.44)
		love.graphics.polygon("fill",
			cx - s * 0.28, cy - s * 0.42, cx + s * 0.42, cy - s * 0.24, cx - s * 0.28, cy - s * 0.04)
	elseif key == "food" then
		love.graphics.circle("fill", cx, cy + s * 0.08, s * 0.32)
		love.graphics.setLineWidth(math.max(1, s * 0.10))
		love.graphics.line(cx, cy - s * 0.20, cx + s * 0.16, cy - s * 0.42)
	else
		love.graphics.polygon("fill",
			cx, cy - s * 0.42, cx + s * 0.36, cy, cx, cy + s * 0.42, cx - s * 0.36, cy)
	end
end

local selected_id = nil
local detail_id   = nil   -- card or zone shown in the full-screen detail overlay
local can_undo    = false
local celebrated  = false -- the ending flourish fires once per ending screen
local buttons     = {}    -- name → rect, rebuilt every frame for hit-testing
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
	local zt = zone_e.zone_type

	-- Page zones (the built-in reveal overlay): every card fills the zone,
	-- so the whole story panel is the tap target.
	if zone_e.tags.page then
		local pad, places = 6 * S, {}
		for i = 1, n do
			places[i] = { x = p.x + pad, y = p.y + pad, w = p.w - pad * 2, h = p.h - pad * 2 }
		end
		return places
	end

	-- A stack asked to show its whole length. It answers before `type` does,
	-- because the question it settles — where does each card go — is the one
	-- `type` was otherwise the only one answering.
	if zone_e.style.fan then return fan_places(zone_e, zone_e.style.fan) end

	if zt == "deck" or zt == "pile" then
		local pad = 3 * S
		return { fit_card({ x = p.x + pad, y = p.y + pad,
			w = p.w - pad * 2, h = p.h - pad * 2 }) }
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
	local card_h = p.h - pad * 2
	local card_w = card_h / CARD_RATIO
	local gap    = 4 * S
	local needed = n * card_w + (n - 1) * gap
	if needed > p.w - pad * 2 then
		card_w = (p.w - pad * 2 - (n - 1) * gap) / n
		card_h = card_w * CARD_RATIO
	end
	-- Centred, not left-aligned. A row that fills its zone looks the same
	-- either way; a row that does not — two choices on a menu built for eight —
	-- looks deliberate one way and abandoned the other.
	local row  = n * card_w + (n - 1) * gap
	local left = p.x + (p.w - row) / 2
	local places = {}
	for i = 1, n do
		places[i] = {
			x = left + (i - 1) * (card_w + gap),
			y = p.y + (p.h - card_h) / 2,
			w = card_w,
			h = card_h,
		}
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
local function draw_cost_badge(pl, cost)
	local sf   = get_small_font()
	local ih   = sf:getHeight()
	local keys = {}
	for k in pairs(cost) do keys[#keys + 1] = k end
	table.sort(keys)

	local w = 4 * S
	for _, k in ipairs(keys) do
		w = w + ih + 2 * S + sf:getWidth(tostring(cost[k])) + 4 * S
	end
	love.graphics.setColor(0, 0, 0, 0.65)
	love.graphics.rectangle("fill", pl.x + 2, pl.y + 2, w, ih + 4 * S, 2 * S, 2 * S)

	love.graphics.setFont(sf)
	local x = pl.x + 2 + 4 * S
	local y = pl.y + 2 + 2 * S
	for _, k in ipairs(keys) do
		draw_stat_icon(k, x + ih * 0.5, y + ih * 0.5, ih)
		love.graphics.setColor(unpack(C.cost))
		print_at(tostring(cost[k]), x + ih + 2 * S, y)
		x = x + ih + 2 * S + sf:getWidth(tostring(cost[k])) + 4 * S
	end
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

	-- Three states, and the two unusable ones must be told apart: a spent
	-- ability reads "exhausted" (wait for the round), an unpayable one reads
	-- "can't yet" (change something). Board abilities carry the whole
	-- interface in verb-driven games, so silence is not an option.
	-- An ability the card's *zone* grants it counts: the top of a discard pile
	-- you may take from has to say so, or the only discoverable thing about it
	-- is that clicking sometimes does nothing.
	local dim, dim_label
	if card_e.exhausted then
		dim, dim_label = true, "exhausted"
	elseif z and z.zone_type == "hand" then
		dim = not flow.can_play(card_e.id)
	elseif z and z.tags.activate and #cards.abilities(card_e) > 0 then
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
		-- right rather than under it.
		local badges  = type(look.badges) == "table" and #look.badges or 0
		local badge_w = (badges > 0 or (card_e.stats and card_e.stats.hp))
			and (vis.w * (badges > 1 and 0.62 or 0.42)) or 0

		local tf, shown, title_h = nil, nil, 0
		if not no_title then
			tf, shown, title_h = fit_title(title, avail - badge_w, 12 * S, 8 * S)
		end

		-- Prose needs room to be prose. Below about a thumb's width a card can
		-- hold a name or a paragraph, not both, and the name is the half a
		-- player is choosing between — the rest is a hover away.
		local bf, body_h, body_text = get_small_font(), 0, nil
		if body and show_text and vis.w >= 92 * S then
			local _, lines = bf:getWrap(body, avail)
			local room = vis.h * 0.55 - title_h - pad * 2 - gap
			local n = math.min(#lines, math.max(0, math.floor(room / bf:getHeight())))
			if n > 0 then
				body_text = table.concat(lines, "\n", 1, n)
				body_h    = n * bf:getHeight()
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
			love.graphics.setFont(tf)
			outlined_printf(shown, vis.x + pad + badge_w, y, avail - badge_w, "center",
				C.card_text, { 0, 0, 0, 0.9 })
			y = y + title_h + gap
		end
		if body_h > 0 then
			love.graphics.setFont(bf)
			outlined_printf(body_text, vis.x + pad, y, avail, "center",
				C.card_body, { 0, 0, 0, 0.85 })
		end
		love.graphics.setScissor()
	end
	love.graphics.setStencilTest()

	if def and def.cost and next(def.cost) then
		draw_cost_badge(pl, def.cost)
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
end

-- One number in a dark pill, with its icon. Returns the width it took.
local function draw_badge(key, txt, x, y, colour)
	local sf = get_small_font()
	love.graphics.setFont(sf)
	local tw, fh = sf:getWidth(txt), sf:getHeight()
	local w = fh + tw + 8 * S
	love.graphics.setColor(0, 0, 0, 0.65)
	love.graphics.rectangle("fill", x - 1, y - 1, w, fh + 2, 2 * S, 2 * S)
	draw_stat_icon(key, x + fh * 0.5, y + fh * 0.5, fh * 0.9)
	love.graphics.setColor(colour)
	print_at(txt, x + fh + 3 * S, y)
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
-- Without this a card could carry any number of stats and show none of them,
-- which is how a whole combat could resolve correctly and look like nothing had
-- happened.
local function draw_card_stats_overlay(pl, card_e)
	local stats = card_e and card_e.stats
	if not stats then return end
	local look   = cards.style(card_e)
	local badges = type(look.badges) == "table" and look.badges or nil

	love.graphics.push("all")
	local fh = get_small_font():getHeight()
	local by = pl.y + pl.h - fh - 3 * S
	if badges then
		local x = pl.x + 2 * S
		for _, key in ipairs(badges) do
			local v = stats[key]
			if v then x = x + draw_badge(key, tostring(v), x, by, { 1, 1, 1 }) + 2 * S end
		end
	elseif stats.hp then
		local hp_max = (card_e.stat_max or {}).hp or stats.hp
		local ratio  = hp_max > 0 and stats.hp / hp_max or 0
		local colour = ratio > 0.6 and { 0.25, 0.95, 0.35 }
			or ratio > 0.3 and { 1.00, 0.82, 0.15 }
			or { 1.00, 0.28, 0.15 }
		draw_badge("hp", stats.hp .. "/" .. hp_max, pl.x + 2 * S, by, colour)
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

local function draw_zone(zone_e)
	local p  = zone_e.place
	local zt = zone_e.zone_type

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

	if zone_e.style.fan then
		-- The name goes down first, so an empty expedition says which colour it
		-- is waiting for and a played one is covered by what was played.
		if zone_e.label then
			love.graphics.push("all")
			love.graphics.setColor(0.30, 0.42, 0.60, 0.65)
			printf(zone_e.label, p.x + 2, p.y + 3 * S, p.w - 4, "center")
			love.graphics.pop()
		end
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id, places[i]) then
				local c = entity.get(card_id)
				if zone_e.tags.face_down or not zones.visible(c) then
					draw_card_back(places[i])
				else
					draw_card_face(places[i], c, false,
						fan_visible(places[i], places[i + 1], zone_e.style.fan))
				end
			end
		end
	elseif zt == "deck" and zone_e.label then
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
	elseif zt == "deck" then
		if #zone_e.cards > 0 then
			local top = entity.get(zone_e.cards[#zone_e.cards])
			if zone_e.tags.face_up then
				draw_card_face(places[1], top, false)
			else
				draw_card_back(places[1])
			end
			love.graphics.push("all")
			love.graphics.setColor(unpack(C.deck_count))
			printf(tostring(#zone_e.cards), p.x, p.y + p.h - fh - 5 * S, p.w, "center")
			love.graphics.pop()
		end
	elseif zt == "pile" then
		if #zone_e.cards > 0 then
			local top = entity.get(zone_e.cards[#zone_e.cards])
			if not anim.visual_place(top.id, top.place) then
				if zone_e.tags.face_down then
					draw_card_back(places[1])
				else
					draw_card_face(places[1], top, false)
				end
			end
		end
		if zone_e.label then
			love.graphics.push("all")
			love.graphics.setColor(0.30, 0.42, 0.60, 0.65)
			printf(zone_e.label, p.x + 2, p.y + 3 * S, p.w - 4, "center")
			love.graphics.pop()
		end
	elseif zt == "grid" then
		draw_zone_art(zone_e)
		draw_grid_squares(zone_e)
		draw_painted_squares(zone_e)
		draw_grid_empty(zone_e)
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id, places[i]) then
				local c = entity.get(card_id)
				draw_card_face(places[i], c, false)
				draw_card_stats_overlay(places[i], c)
			end
		end
	else
		-- hand and other zones: show description text on the card
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id, places[i]) then
				local c = entity.get(card_id)
				if zone_e.tags.page then
					draw_page(places[i], c)
				elseif not zones.visible(c) then
					-- Somebody else's hand. Backs, so the cards are still there
					-- to count — how many an opponent holds is public in every
					-- card game — and the faces are not.
					draw_card_back(places[i])
				else
					draw_card_face(places[i], c, true)
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
				local row_x = x - tw - fh - 4 * S
				draw_stat_icon(key, row_x + fh * 0.5, y + fh * 0.5, fh * 0.85)
				love.graphics.setColor(unpack(C.stat))
				print_at(txt, row_x + fh + 4 * S, y)
				stat_hud[key] = { x = row_x + fh + tw * 0.5, y = y }
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
		if not z.tags.hidden then
			local zt   = z.zone_type
			local list = (zt == "deck" or zt == "pile") and { z.cards[#z.cards] } or z.cards
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
			print_at("Cost: " .. cards.cost_text(def.cost), info_x, y)
			y = y + main_font:getHeight() + 8 * S
		end

		local tooltip = def and def.tooltip or ""
		if tooltip ~= "" then
			love.graphics.setColor(0.82, 0.91, 1.00)
			printf(tooltip, info_x, y, info_w, "left")
			local _, wrapped = main_font:getWrap(tooltip, info_w)
			y = y + #wrapped * main_font:getHeight() + 14 * S
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
			for k, v in pairs(stats) do
				local val = caps[k] and (v .. "/" .. caps[k]) or tostring(v)
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

	-- Impacts kick the whole scene; UI overlays below stay put.
	local shx, shy = fx.shake_offset()
	love.graphics.push()
	love.graphics.translate(shx, shy)

	for z in entity.each("zone") do
		if not z.tags.hidden then draw_zone(z) end
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
		local zt     = z.zone_type
		local kind   = zt == "grid" and "slam"
			or (zt == "deck" or zt == "pile") and "drop" or "glide"
		-- A stack keeps one place, because only its top card is ever drawn or
		-- clicked. A fanned one shows every card, so every card needs one — miss
		-- this and the fan draws correctly and answers the mouse from wherever
		-- its cards used to be.
		local list   = (zt == "deck" or zt == "pile") and not z.style.fan
			and { z.cards[#z.cards] } or z.cards
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
