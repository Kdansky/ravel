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

function M.rescale()
	local W, H = love.graphics.getDimensions()
	S = math.max(0.75, math.min(3, math.min(W / 960, H / 540)))
	font_main   = love.graphics.newFont(math.floor(13 * S + 0.5))
	font_small  = love.graphics.newFont(math.max(8, math.floor(9 * S + 0.5)))
	font_banner = love.graphics.newFont(math.floor(32 * S + 0.5))
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

-- Cut text to fit a width, appending "..." (multibyte-safe trim).
local function truncate(font, text, w)
	text = tostring(text)
	if font:getWidth(text) <= w then return text end
	while #text > 1 and font:getWidth(text .. "...") > w do
		text = text:sub(1, -2)
		while #text > 0 and text:byte(-1) >= 0x80 and text:byte(-1) <= 0xBF do
			text = text:sub(1, -2)
		end
	end
	return text .. "..."
end

local function pulse(speed)
	return 0.5 + 0.5 * math.sin(love.timer.getTime() * (speed or 5))
end

-- Tiny vector glyphs for stats, so numbers read at a glance without art.
-- Keys are conventions (gold/hp/defense/morale/food); anything else gets a diamond.
local ICON_COLOR = {
	gold    = { 0.95, 0.78, 0.25 },
	hp      = { 0.92, 0.32, 0.32 },
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
	elseif key == "hp" then
		love.graphics.circle("fill", cx - s * 0.18, cy - s * 0.12, s * 0.24)
		love.graphics.circle("fill", cx + s * 0.18, cy - s * 0.12, s * 0.24)
		love.graphics.polygon("fill",
			cx - s * 0.40, cy - s * 0.02, cx + s * 0.40, cy - s * 0.02, cx, cy + s * 0.44)
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
				places[i] = fit_card(slot.place, zone_e.fit)
			else
				local g    = zone_e.grid or { 4, 3 }
				local cols = g[1]
				local pad  = 4
				local cw   = p.w / cols
				local ch   = p.h / (g[2] or 3)
				local col  = (i - 1) % cols
				local row  = math.floor((i - 1) / cols)
				places[i]  = fit_card({ x = p.x + col * cw + pad, y = p.y + row * ch + pad,
					w = cw - pad * 2, h = ch - pad * 2 }, zone_e.fit)
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
	local places = {}
	for i = 1, n do
		places[i] = {
			x = p.x + pad + (i - 1) * (card_w + gap),
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
		love.graphics.print(tostring(cost[k]), x + ih + 2 * S, y)
		x = x + ih + 2 * S + sf:getWidth(tostring(cost[k])) + 4 * S
	end
end

-- Draw a card face.
-- show_text=true: allocate extra space below the image for description text (hand cards).
-- show_text=false: compact title bar only (board tiles, animations, pile top).
local function draw_card_face(pl, card_e, show_text)
	local def   = cards.def(card_e)
	local color = def and def.color or C.card_default
	local img   = cards.image(card_e.def_key)
	local z     = entity.get(card_e.zone_id)
	local title = def and def.text or card_e.def_key

	-- Three states, and the two unusable ones must be told apart: a spent
	-- ability reads "exhausted" (wait for the round), an unpayable one reads
	-- "can't yet" (change something). Board abilities carry the whole
	-- interface in verb-driven games, so silence is not an option.
	local dim, dim_label
	if card_e.exhausted then
		dim, dim_label = true, "exhausted"
	elseif z and z.zone_type == "hand" then
		dim = not flow.can_play(card_e.id)
	elseif z and z.zone_type == "grid" and def and def.on_activate then
		dim, dim_label = not flow.can_activate(card_e.id), "can't yet"
	end

	love.graphics.push("all")
	love.graphics.setColor(unpack(color))
	love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)

	if img then
		local text_h
		if show_text then
			-- Allocate ~42% of card height for name + description.
			text_h = math.max(42 * S, math.floor(pl.h * 0.42))
		else
			text_h = math.max(18 * S, math.floor(pl.h * 0.26))
		end
		local img_h  = pl.h - text_h
		local iw, _  = img:getDimensions()

		-- Clip the image to the rounded card shape (stencil) and its band (scissor).
		love.graphics.stencil(function()
			love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
		end, "replace", 1)
		love.graphics.setStencilTest("greater", 0)
		love.graphics.setScissor(pl.x, pl.y, pl.w, img_h)
		love.graphics.setColor(1, 1, 1)
		love.graphics.draw(img, pl.x, pl.y, 0, pl.w / iw, pl.w / iw)
		love.graphics.setScissor()
		love.graphics.setStencilTest()

		love.graphics.setColor(unpack(color))
		love.graphics.rectangle("fill", pl.x, pl.y + img_h, pl.w, text_h)

		if show_text then
			local mf     = love.graphics.getFont()
			local name_h = mf:getHeight() + 4 * S
			love.graphics.setColor(unpack(C.card_text))
			love.graphics.printf(
				truncate(mf, title, pl.w - 6 * S),
				pl.x + 3 * S, pl.y + img_h + 2 * S, pl.w - 6 * S, "center")
			-- Description below name in a smaller font.
			love.graphics.setFont(get_small_font())
			love.graphics.setColor(unpack(C.card_body))
			love.graphics.printf(
				def and def.tooltip or "",
				pl.x + 4 * S, pl.y + img_h + name_h + 2 * S, pl.w - 8 * S, "left")
		else
			local mf = love.graphics.getFont()
			love.graphics.setColor(unpack(C.card_text))
			love.graphics.printf(
				truncate(mf, title, pl.w - 6 * S),
				pl.x + 3 * S, pl.y + img_h + (text_h - mf:getHeight()) * 0.5, pl.w - 6 * S, "center")
		end
	else
		local mf = love.graphics.getFont()
		love.graphics.setColor(unpack(C.card_text))
		love.graphics.printf(
			truncate(mf, title, pl.w - 8 * S),
			pl.x + 4 * S, pl.y + pl.h * 0.5 - mf:getHeight() * 0.5, pl.w - 8 * S, "center")
	end

	if def and def.cost and next(def.cost) then
		draw_cost_badge(pl, def.cost)
	end

	if dim then
		love.graphics.setColor(0, 0, 0, 0.55)
		love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
		if dim_label then
			local sf = get_small_font()
			love.graphics.setFont(sf)
			love.graphics.setColor(0.70, 0.75, 0.85, 0.90)
			love.graphics.printf(dim_label, pl.x, pl.y + pl.h * 0.5 - sf:getHeight() * 0.5,
				pl.w, "center")
		end
	end

	-- Targeting states are triple-encoded — border color, pulsing fill and a
	-- corner marker — so eligibility never rides on hue alone.
	if targeting.active() then
		local marker_col, marker_a = nil, 1
		if card_e.id == targeting.card_id then
			love.graphics.setColor(unpack(C.selected))
			love.graphics.setLineWidth(3 * S)
		elseif targeting.is_selected(card_e.id) then
			love.graphics.setColor(C.target_chosen[1], C.target_chosen[2], C.target_chosen[3], 0.20)
			love.graphics.rectangle("fill", pl.x, pl.y, pl.w, pl.h, 5 * S, 5 * S)
			love.graphics.setColor(unpack(C.target_chosen))
			love.graphics.setLineWidth(3 * S)
			marker_col = C.target_chosen
		elseif targeting.is_eligible(card_e.id) then
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
	else
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
		love.graphics.printf(tostring(#card_e.attached), bx, by + S, bs, "center")
	end

	love.graphics.pop()
end

-- HP badge overlaid on board cards (bottom-left corner).
local function draw_card_stats_overlay(pl, card_e)
	local stats = card_e and card_e.stats
	if not stats or not stats.hp then return end
	local hp     = stats.hp
	local hp_max = stats.hp_max or hp
	local txt    = hp .. "/" .. hp_max
	local ratio  = hp_max > 0 and hp / hp_max or 0

	love.graphics.push("all")
	local sf = get_small_font()
	love.graphics.setFont(sf)
	local tw = sf:getWidth(txt)
	local fh = sf:getHeight()
	local bx = pl.x + 2 * S
	local by = pl.y + pl.h - fh - 3 * S
	love.graphics.setColor(0, 0, 0, 0.65)
	love.graphics.rectangle("fill", bx - 1, by - 1, fh + tw + 8 * S, fh + 2, 2 * S, 2 * S)
	draw_stat_icon("hp", bx + fh * 0.5, by + fh * 0.5, fh * 0.9)
	if ratio > 0.6 then
		love.graphics.setColor(0.25, 0.95, 0.35)
	elseif ratio > 0.3 then
		love.graphics.setColor(1.00, 0.82, 0.15)
	else
		love.graphics.setColor(1.00, 0.28, 0.15)
	end
	love.graphics.print(txt, bx + fh + 3 * S, by)
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
	love.graphics.printf(def and def.text or card_e.def_key, pl.x + m, y, pl.w - m * 2, "center")
	y = y + mf:getHeight() + 8 * S
	love.graphics.setColor(0.28, 0.40, 0.62)
	love.graphics.line(pl.x + m, y, pl.x + pl.w - m, y)
	y = y + 12 * S

	local hint_h = sf:getHeight() + 12 * S
	love.graphics.setScissor(pl.x, y, pl.w, math.max(0, pl.y + pl.h - hint_h - y))
	love.graphics.setColor(0.80, 0.88, 1.00)
	love.graphics.printf(def and (def.story or def.tooltip) or "",
		pl.x + m, y, pl.w - m * 2, "left")
	love.graphics.setScissor()

	love.graphics.setFont(sf)
	love.graphics.setColor(0.45, 0.60, 0.80, 0.55 + 0.35 * pulse(3))
	love.graphics.printf("click to continue", pl.x, pl.y + pl.h - hint_h + 4 * S, pl.w, "center")
	love.graphics.pop()
end

local function draw_grid_empty(zone_e)
	if not zone_e.slots then return end
	love.graphics.push("all")
	for _, slot_id in pairs(zone_e.slots) do
		local slot = entity.get(slot_id)
		if slot and not slot.occupant then
			-- Match the card footprint, so an empty slot reads as the same
			-- shape as the card that would fill it.
			local p = fit_card(slot.place, zone_e.fit)
			if targeting.active() and targeting.is_eligible(slot_id) then
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
	love.graphics.setColor(unpack(C.zone_fill))
	love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 7 * S, 7 * S)
	love.graphics.setColor(unpack(C.zone_border))
	love.graphics.setLineWidth(S)
	love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 7 * S, 7 * S)
	love.graphics.pop()

	local places = card_places(zone_e)
	local fh     = love.graphics.getFont():getHeight()

	if zt == "deck" and zone_e.label then
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
		love.graphics.printf(truncate(love.graphics.getFont(), zone_e.label, p.w - 10 * S),
			p.x + 5 * S, band_y + 3 * S, p.w - 10 * S, "center")
		love.graphics.setColor(0.55, 0.72, 1.00)
		love.graphics.printf(tostring(#zone_e.cards),
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
			love.graphics.printf(tostring(#zone_e.cards), p.x, p.y + p.h - fh - 5 * S, p.w, "center")
			love.graphics.pop()
		end
	elseif zt == "pile" then
		if #zone_e.cards > 0 then
			local top = entity.get(zone_e.cards[#zone_e.cards])
			if not anim.visual_place(top.id) then
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
			love.graphics.printf(zone_e.label, p.x + 2, p.y + 3 * S, p.w - 4, "center")
			love.graphics.pop()
		end
	elseif zt == "grid" then
		draw_grid_empty(zone_e)
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id) then
				local c = entity.get(card_id)
				draw_card_face(places[i], c, false)
				draw_card_stats_overlay(places[i], c)
			end
		end
	else
		-- hand and other zones: show description text on the card
		for i, card_id in ipairs(zone_e.cards) do
			if places[i] and not anim.visual_place(card_id) then
				local c = entity.get(card_id)
				if zone_e.tags.page then
					draw_page(places[i], c)
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
		love.graphics.print(cur.label, x - mf:getWidth(cur.label), y)
		y = y + fh + 8 * S
	end
	for _, key in ipairs(G.stat_defs_list or {}) do
		local def = G.stat_defs[key]
		if not (def and def.hidden) then
			local label = def and (def.label or key) or key
			local txt   = label .. ": " .. tostring(entity.sum_stat(key))
			local tw    = mf:getWidth(txt)
			local row_x = x - tw - fh - 4 * S
			draw_stat_icon(key, row_x + fh * 0.5, y + fh * 0.5, fh * 0.85)
			love.graphics.setColor(unpack(C.stat))
			love.graphics.print(txt, row_x + fh + 4 * S, y)
			stat_hud[key] = { x = row_x + fh + tw * 0.5, y = y }
			y = y + fh + 5 * S
		end
	end
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
	love.graphics.print(label, x + (w - mf:getWidth(label)) * 0.5,
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
	love.graphics.print(msg, 12 * S, H - bar_h + 7 * S)

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
		love.graphics.print(truncate(sf, line, w - 22 * S),
			x + 4 * S, y + 4 * S + (i - 1) * (fh + 2 * S))
	end
	love.graphics.setColor(0.45, 0.60, 0.80, 0.75)
	love.graphics.print("L", x + w - fh - 3 * S, y + 4 * S)
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
				local vpl = cid and anim.visual_place(cid)
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
	love.graphics.printf((zone_e.label or zone_e.key) .. "  (" .. n .. ")", 0, 18 * S, W, "center")

	local cw   = math.min(130 * S, (W - 40 * S) / math.min(n, 5) - gap)
	local cols = math.max(1, math.floor((W - 40 * S) / (cw + gap)))
	local rows = math.ceil(n / cols)
	local avail_h = H - 100 * S
	if rows * (cw * CARD_RATIO + gap) > avail_h then
		cw = math.min(cw, (avail_h / rows - gap) / CARD_RATIO)
	end
	local ch = cw * CARD_RATIO
	local x0 = (W - math.min(n, cols) * (cw + gap) + gap) / 2
	local y0 = 55 * S

	for i, cid in ipairs(zone_e.cards) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local pl  = { x = x0 + col * (cw + gap), y = y0 + row * (ch + gap), w = cw, h = ch }
		local c   = entity.get(cid)
		draw_card_face(pl, c, false)
		draw_card_stats_overlay(pl, c)
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
		love.graphics.printf(def and def.text or card_e.def_key, info_x, y, info_w, "left")
		y = y + main_font:getHeight() + 8 * S

		love.graphics.setColor(0.28, 0.40, 0.62)
		love.graphics.setLineWidth(S)
		love.graphics.line(info_x, y, info_x + info_w, y)
		y = y + 10 * S

		if def and def.cost and next(def.cost) then
			love.graphics.setColor(unpack(C.cost))
			love.graphics.print("Cost: " .. cards.cost_text(def.cost), info_x, y)
			y = y + main_font:getHeight() + 8 * S
		end

		local tooltip = def and def.tooltip or ""
		if tooltip ~= "" then
			love.graphics.setColor(0.82, 0.91, 1.00)
			love.graphics.printf(tooltip, info_x, y, info_w, "left")
			local _, wrapped = main_font:getWrap(tooltip, info_w)
			y = y + #wrapped * main_font:getHeight() + 14 * S
		end

		local story = def and def.story or ""
		if story ~= "" then
			love.graphics.setColor(0.68, 0.78, 0.94)
			love.graphics.printf(story, info_x, y, info_w, "left")
			local _, swrapped = main_font:getWrap(story, info_w)
			y = y + #swrapped * main_font:getHeight() + 14 * S
		end

		local stats = card_e.stats
		if stats and next(stats) then
			love.graphics.setColor(0.55, 0.70, 0.90)
			love.graphics.print("Stats:", info_x, y)
			y = y + main_font:getHeight() + 4 * S
			for k, v in pairs(stats) do
				if k:sub(-4) ~= "_max" then
					local mk  = k .. "_max"
					local val = stats[mk] and (v .. "/" .. stats[mk]) or tostring(v)
					love.graphics.setColor(0.78, 0.92, 1.00)
					love.graphics.print("  " .. k .. ": " .. val, info_x, y)
					y = y + main_font:getHeight()
				end
			end
			y = y + 10 * S
		end

		if def and def.tags_set and next(def.tags_set) then
			love.graphics.setColor(0.55, 0.70, 0.90)
			love.graphics.setFont(main_font)
			love.graphics.print("Tags:", info_x, y)
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
				love.graphics.print(tag, tx + 5 * S, y + 2 * S)
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
	love.graphics.printf("Click or tap anywhere to close",
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
				love.graphics.printf(cur.label, 0, oz.place.y - 30 * S, W, "center")
				love.graphics.pop()
			end
			draw_zone(oz)
			for _, cid in ipairs(oz.cards) do
				local vpl = anim.visual_place(cid)
				if vpl then draw_flying_card(vpl, entity.get(cid)) end
			end
		end

		-- An ending screen announces itself: banner, run summary, flourish.
		if outcome then
			if not celebrated then
				fx.celebrate(outcome)
				celebrated = true
			end
			local btxt = outcome == "victory" and "Victory" or "Defeat"
			local col  = outcome == "victory" and { 1.00, 0.84, 0.30 } or { 0.95, 0.32, 0.26 }
			love.graphics.push("all")
			love.graphics.setFont(font_banner)
			love.graphics.setColor(0, 0, 0, 0.80)
			love.graphics.printf(btxt, 0, 10 * S + 2 * S, W, "center")
			love.graphics.setColor(unpack(col))
			love.graphics.printf(btxt, 0, 10 * S, W, "center")
			local summary = table.concat(flow.summary(), "    ·    ")
			if summary ~= "" then
				love.graphics.setFont(font_main)
				love.graphics.setColor(0.85, 0.90, 1.00, 0.95)
				love.graphics.printf(summary, 0, 10 * S + font_banner:getHeight() + 4 * S, W, "center")
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
		local list   = (zt == "deck" or zt == "pile") and { z.cards[#z.cards] } or z.cards
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
