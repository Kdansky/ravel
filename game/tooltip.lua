local entity      = require("entity")
local declaration = require("declaration")
local cards       = require("cards")
local render      = require("render")
local flow        = require("flow")
local zones       = require("zones")
local tags        = require("tags")
local rich        = require("richtext")

local M = {}

local DELAY    = 0.18
local timer    = 0
local hover_id = nil
local visible  = false

function M.update(dt, card_id)
	if card_id ~= hover_id then
		hover_id = card_id
		timer    = 0
		visible  = false
	elseif card_id then
		timer = timer + dt
		if timer >= DELAY then visible = true end
	end
end

-- Colours, by what a line *is* rather than where it sits. The old panel drew
-- everything in one tone at one size, so the card's prose, its price and the
-- hint about clicking it were indistinguishable — a wall of text the eye had to
-- parse word by word.
local C = {
	title = { 0.94, 0.96, 1.00 },
	prose = { 0.78, 0.85, 0.97 },
	label = { 0.52, 0.62, 0.78 },
	value = { 0.88, 0.93, 1.00 },
	rule  = { 0.25, 0.34, 0.50 },
	ready = { 0.55, 0.90, 0.70 },
	wait  = { 0.75, 0.70, 0.55 },
}

-- What a card has to say about itself, in order and in kinds. Built as a list
-- so the panel can measure before it draws and so each kind can be given its
-- own weight — a title is not a price is not a hint.
--
-- The order is deliberate: what it is, what it says, what it costs, what it is
-- worth now, and what happens if you click. A player reads down until the
-- answer appears, and the commonest question is the top one.
local function blocks(c, def)
	local out = {}
	local function add(kind, a, b) out[#out + 1] = { kind = kind, a = a, b = b } end

	add("title", def.text or c.def_key)

	-- The card's own words, then whatever its zone says about lying there
	-- ("Take this card into your hand"). Without the second, a granted ability
	-- is invisible: nothing on the card mentions it and nothing in the rulebook
	-- is a card.
	local own   = def.tooltip
	local zone  = cards.zone_grant(c, "tooltip")
	if own and own ~= "" then add("prose", own) end
	if zone and zone ~= "" and zone ~= own then add("prose", zone) end

	-- Then its keywords, each said once by the game and inherited by every card
	-- that carries the tag. A player who has forgotten what Tough does should
	-- not have to find the one card whose author remembered to write it down.
	-- Prose, not a labelled row: a keyword is a sentence, and a row is a line.
	-- The tag def's own text carries the name ("Tough — takes 1 less damage from
	-- every source"), so the engine makes no decision about how it reads.
	for _, kw in ipairs(cards.keywords(c)) do
		if kw.text ~= own then add("prose", kw.text) end
	end

	-- The engine's own counters are not the card's business. `round` and `plays`
	-- are bookkeeping it keeps on whichever card happens to be the seat, `turn`
	-- says whose go it is, and `owner` is a seat number nobody wants read out as
	-- a statistic — the sprite already says whose piece it is. None of them
	-- describes the thing being hovered, and on castle's throne room the first
	-- two read as two more of its numbers.
	local BOOKKEEPING = { round = true, plays = true, turn = true, owner = true, won = true,
		ability = true, last_acted = true }

	local rows = {}
	if def.cost and next(def.cost) then rows[#rows + 1] = { "Cost", cards.cost_text(def.cost, c.id) } end
	if def.needs and next(def.needs) then rows[#rows + 1] = { "Needs", cards.cost_text(def.needs) } end
	-- Per-instance numbers, named the way the HUD names them where the game
	-- declared a label, so one card does not call it "hp" while the bar calls it
	-- "Health".
	for _, key in ipairs(declaration.G.stat_defs_list or {}) do
		local v = c.stats and c.stats[key]
		if v and key:sub(-4) ~= "_max" and not BOOKKEEPING[key] then
			local sd  = declaration.G.stat_defs[key]
			local max = c.stats[key .. "_max"]
			-- What the rules will read, buffs and all. The panel is the place a
			-- player checks a number they doubt, so it is the last place that
			-- may show the printed one.
			v = tags.stat(c, key)
			rows[#rows + 1] = { sd and sd.label or key, max and (v .. "/" .. max) or tostring(v) }
		end
	end
	-- Anything the game never declared as a stat is still worth showing, under
	-- its own name — capitalised, so a column does not read half labels and half
	-- variable names.
	local undeclared = {}
	for key in pairs(c.stats or {}) do
		if key:sub(-4) ~= "_max" and not declaration.G.stat_defs[key] and not BOOKKEEPING[key] then
			undeclared[#undeclared + 1] = key
		end
	end
	table.sort(undeclared)
	for _, key in ipairs(undeclared) do
		local v, max = tags.stat(c, key), c.stats[key .. "_max"]
		rows[#rows + 1] = { key:sub(1, 1):upper() .. key:sub(2),
			max and (v .. "/" .. max) or tostring(v) }
	end
	if c.attached and #c.attached > 0 then
		rows[#rows + 1] = { "Attached", tostring(#c.attached) }
	end
	if #rows > 0 then
		add("rule")
		for _, r in ipairs(rows) do add("row", r[1], r[2]) end
	end

	-- What clicking does, and when it will not. Reads the *granted* abilities
	-- too, so one a zone hands out announces itself rather than leaving a dead
	-- click to explain itself — and every ability is listed, because a card with
	-- two is a card whose tooltip has to say what the choice will be between.
	local all   = cards.abilities(c)
	local ready = flow.usable_abilities(c.id)
	if #all > 0 then
		add("rule")
		if #ready == 0 then
			add("hint", c.exhausted and "Exhausted — ready next round"
				or "Not available now", C.wait)
		elseif #ready == 1 then
			local text = "Click to " .. (#all > 1 and (ready[1].ability.text or "activate") or "activate")
			local ac = ready[1].ability.cost
			if ac and next(ac) then text = text .. "  (" .. cards.cost_text(ac, c.id) .. ")" end
			add("hint", text, C.ready)
		else
			add("hint", "Click to choose:", C.ready)
			for _, u in ipairs(ready) do
				local line = "  " .. (u.ability.text or u.ability.key)
				if u.ability.cost and next(u.ability.cost) then
					line = line .. "  (" .. cards.cost_text(u.ability.cost, c.id) .. ")"
				end
				add("hint", line, C.ready)
			end
		end
	end
	return out
end

-- A zone answers for itself: its label, whatever it says about being used, and
-- what using it would cost. There are no cards in a deck to ask — there is a
-- deck — so this is what a player reads before clicking one.
local function zone_blocks(z)
	local out = {}
	local function add(kind, a, b) out[#out + 1] = { kind = kind, a = a, b = b } end
	add("title", z.label or z.key)
	if z.tooltip and z.tooltip ~= "" then add("prose", z.tooltip) end
	if #z.cards > 0 then
		add("rule")
		add("row", "Cards", tostring(#z.cards))
	end
	if flow.can_activate_zone(z.id) then
		add("rule")
		local text = "Click to use"
		if z.activate_cost and next(z.activate_cost) then
			text = text .. "  (" .. cards.cost_text(z.activate_cost) .. ")"
		end
		add("hint", text, C.ready)
	elseif z.on_activate then
		add("rule")
		add("hint", "Not available in this phase", C.wait)
	end
	return out
end

function M.draw()
	if not visible or not hover_id then return end
	local c = entity.get(hover_id)
	if not c then return end
	local is_zone = c.kind == "zone"
	local def = not is_zone and declaration.G.card_defs[c.def_key] or nil
	if (not is_zone and not def) or not c.place then return end
	-- Hovering is looking. A card the player may not see does not describe
	-- itself, or the hand is face-down and the tooltip reads it out.
	if not is_zone and not zones.visible(c) then return end

	local S      = render.scale()
	local W, H   = love.graphics.getDimensions()
	-- Whole pixels, so glyphs are not sampled between texels. Rounded here at
	-- the source rather than at each printf: everything below is measured from
	-- these, so integers in means integers out.
	local pad    = math.floor(9 * S + 0.5)
	local gap    = math.floor(5 * S + 0.5)
	local box_w  = math.min(240 * S, W * 0.34)
	local inner  = box_w - pad * 2
	local tf, bf = render.main_font(), render.small_font()
	local img    = not is_zone and cards.image(c) or nil
	local img_h  = img and math.floor(box_w * 0.62) or 0

	local list = is_zone and zone_blocks(c) or blocks(c, def)

	-- Measure, then draw. Two passes rather than one so the panel is the size of
	-- what is in it: guessing the height is what left the old one padded at the
	-- bottom on a short card and tight on a long one.
	-- Prose is the one thing here a card may have set in bold or italic, so it is
	-- measured by the same wrap that will draw it: a bold word is wider than the
	-- plain one, and a panel sized off the plain text comes out short.
	local line_h = math.ceil(bf:getHeight() * 1.25)
	local function height_of(b)
		if b.kind == "title" then return tf:getHeight()
		elseif b.kind == "rule" then return math.floor(gap * 1.8)
		elseif b.kind == "row" then return math.ceil(bf:getHeight() * 1.15)
		else return #rich.wrap(bf, b.a, inner) * line_h
		end
	end

	local body_h = 0
	for i, b in ipairs(list) do
		body_h = body_h + height_of(b)
		if b.kind == "title" or (b.kind == "prose" and list[i + 1] and list[i + 1].kind ~= "prose") then
			body_h = body_h + gap
		end
	end
	local box_h = pad + img_h + (img_h > 0 and gap or 0) + body_h + pad

	local x = c.place.x + c.place.w + 8 * S
	local y = c.place.y
	if x + box_w > W then x = c.place.x - box_w - 8 * S end
	if x < 0 then x = 4 end
	if y + box_h > H then y = H - box_h - 4 end
	if y < 0 then y = 4 end
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)

	love.graphics.push("all")
	love.graphics.setColor(0.04, 0.07, 0.13, 0.97)
	love.graphics.rectangle("fill", x, y, box_w, box_h, 5 * S, 5 * S)
	love.graphics.setColor(C.rule[1], C.rule[2], C.rule[3], 0.9)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, box_w, box_h, 5 * S, 5 * S)

	local cy = y + pad
	if img then
		local iw, ih = img:getDimensions()
		local sc = math.max(inner / iw, img_h / ih)
		love.graphics.setScissor(x + pad, cy, inner, img_h)
		love.graphics.setColor(1, 1, 1)
		love.graphics.draw(img, x + pad + (inner - iw * sc) * 0.5,
			cy + (img_h - ih * sc) * 0.5, 0, sc, sc)
		love.graphics.setScissor()
		cy = cy + img_h + gap
	end

	for i, b in ipairs(list) do
		if b.kind == "title" then
			love.graphics.setFont(tf)
			love.graphics.setColor(unpack(C.title))
			love.graphics.printf(b.a, x + pad, cy, inner, "left")
		elseif b.kind == "prose" then
			rich.printf(bf, b.a, x + pad, cy, inner, "left",
				{ color = C.prose, line_h = line_h })
		elseif b.kind == "rule" then
			love.graphics.setColor(C.rule[1], C.rule[2], C.rule[3], 0.85)
			love.graphics.rectangle("fill", x + pad, math.floor(cy + gap * 0.9) + 0.5, inner, 1)
		elseif b.kind == "row" then
			-- Name on the left, number on the right, so a column of them can be
			-- read down rather than word by word.
			love.graphics.setFont(bf)
			love.graphics.setColor(unpack(C.label))
			love.graphics.printf(b.a, x + pad, cy, inner, "left")
			love.graphics.setColor(unpack(C.value))
			love.graphics.printf(b.b, x + pad, cy, inner, "right")
		else
			rich.printf(bf, b.a, x + pad, cy, inner, "left",
				{ color = b.b, line_h = line_h })
		end
		cy = cy + height_of(b)
		if b.kind == "title" or (b.kind == "prose" and list[i + 1] and list[i + 1].kind ~= "prose") then
			cy = cy + gap
		end
	end

	love.graphics.pop()
end

return M
