local entity      = require("entity")
local declaration = require("declaration")
local cards       = require("cards")
local render      = require("render")

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

function M.draw()
	if not visible or not hover_id then return end
	local c   = entity.get(hover_id)
	if not c then return end
	local def = declaration.G.card_defs[c.def_key]
	if not def then return end

	local pl  = c.place
	if not pl then return end

	local img  = cards.image(c.def_key)
	local text = def.tooltip or ""

	if def.cost and next(def.cost) then
		if text ~= "" then text = text .. "\n" end
		text = text .. "Cost: " .. cards.cost_text(def.cost)
	end
	if def.needs and next(def.needs) then
		if text ~= "" then text = text .. "\n" end
		text = text .. "Needs: " .. cards.cost_text(def.needs)
	end

	-- Per-entity stats (hp, etc.) shown below tooltip text.
	if c.stats and next(c.stats) then
		local parts = {}
		for k, v in pairs(c.stats) do
			if k:sub(-4) ~= "_max" then
				local mk = k .. "_max"
				if c.stats[mk] then
					parts[#parts + 1] = k .. ": " .. v .. "/" .. c.stats[mk]
				else
					parts[#parts + 1] = k .. ": " .. v
				end
			end
		end
		if #parts > 0 then
			if text ~= "" then text = text .. "\n" end
			text = text .. table.concat(parts, "  ")
		end
	end

	-- Activatable ability hint.
	if def.on_activate then
		if text ~= "" then text = text .. "\n" end
		if c.exhausted then
			text = text .. "[Exhausted — readies next round]"
		else
			text = text .. "[Click to activate]"
			if def.activate_cost and next(def.activate_cost) then
				text = text .. " (" .. cards.cost_text(def.activate_cost) .. ")"
			end
		end
	end

	-- Attached cards summary.
	if c.attached and #c.attached > 0 then
		if text ~= "" then text = text .. "\n" end
		text = text .. "Attachments: " .. #c.attached
	end

	if not img and text == "" then return end

	local W, H   = love.graphics.getDimensions()
	local S      = render.scale()
	local pad    = 10 * S
	local box_w  = math.min(230 * S, W * 0.32)
	local img_h  = img and math.floor(box_w * 0.67) or 0

	local font       = love.graphics.getFont()
	local _, lines   = font:getWrap(text, box_w - pad * 2)
	local text_h     = #lines > 0 and (#lines * math.ceil(font:getHeight() * 1.2) + pad) or 0
	local box_h      = pad + img_h + text_h + pad

	local x = pl.x + pl.w + 8 * S
	local y = pl.y
	if x + box_w > W then x = pl.x - box_w - 8 * S end
	if y + box_h > H then y = H - box_h - 4 end
	if y < 0 then y = 4 end

	love.graphics.push("all")

	-- background
	love.graphics.setColor(0.04, 0.07, 0.13, 0.96)
	love.graphics.rectangle("fill", x, y, box_w, box_h, 4, 4)
	love.graphics.setColor(0.25, 0.38, 0.60)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, box_w, box_h, 4, 4)

	-- card image (larger, fills top of tooltip)
	if img then
		local iw, ih = img:getDimensions()
		love.graphics.setScissor(x, y + pad, box_w, img_h)
		love.graphics.setColor(1, 1, 1)
		love.graphics.draw(img, x, y + pad, 0, box_w / iw, box_w / iw)
		love.graphics.setScissor()
	end

	-- tooltip text below image
	if text ~= "" then
		love.graphics.setColor(0.82, 0.88, 1.00)
		love.graphics.printf(text, x + pad, y + pad + img_h, box_w - pad * 2)
	end

	love.graphics.pop()
end

return M
