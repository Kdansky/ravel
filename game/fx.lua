-- Purely visual effects: impact rings, spark particles, screen shake.
-- Nothing here touches game state; flow never loads it.

local M = {}

local parts  = {}
local rings  = {}
local floats = {}
local trauma = 0
local SCALE  = 1

-- Match effect sizes to the UI scale (set by render.rescale).
function M.set_scale(s)
	SCALE = s
end

function M.clear()
	parts, rings, floats, trauma = {}, {}, {}, 0
end

-- A card landing: shockwave ring, debris sparks, a kick of screen shake.
-- power ranges from ~0.3 (soft drop on a pile) to 1 (slammed onto the board).
function M.impact(x, y, power, color)
	color = color or { 1.00, 0.92, 0.60 }
	rings[#rings + 1] = {
		x = x, y = y, t = 0, life = 0.30 + 0.15 * power,
		max_r = (26 + 55 * power) * SCALE, width = (2 + 4 * power) * SCALE, color = color,
	}
	for _ = 1, math.floor(6 + 12 * power) do
		local a  = math.random() * 2 * math.pi
		local sp = (90 + math.random() * 180) * (0.4 + 0.6 * power) * SCALE
		parts[#parts + 1] = {
			x = x, y = y,
			vx = math.cos(a) * sp,
			vy = math.sin(a) * sp * 0.6 - 60 * power * SCALE,
			t = 0, life = 0.25 + math.random() * 0.30,
			color = color,
		}
	end
	trauma = math.min(1, trauma + 0.2 + 0.25 * power)
end

-- Floating text ("+2 gold") drifting up from a stat change.
function M.float(x, y, text, color)
	floats[#floats + 1] = { x = x, y = y, text = text, color = color, t = 0, life = 1.0 }
end

-- A spell or effect connecting with a target card: sharper, brighter burst.
function M.hit(x, y, color)
	M.impact(x, y, 0.8, color or { 0.70, 0.95, 1.00 })
	rings[#rings + 1] = {
		x = x, y = y, t = 0, life = 0.18,
		max_r = 22, width = 2, color = { 1, 1, 1 },
	}
end

function M.update(dt)
	trauma = math.max(0, trauma - 2.2 * dt)
	for i = #parts, 1, -1 do
		local p = parts[i]
		p.t = p.t + dt
		if p.t >= p.life then
			table.remove(parts, i)
		else
			p.vy = p.vy + 420 * dt          -- gravity: sparks fall like debris
			p.vx = p.vx * (1 - 2.5 * dt)
			p.x  = p.x + p.vx * dt
			p.y  = p.y + p.vy * dt
		end
	end
	for i = #rings, 1, -1 do
		local r = rings[i]
		r.t = r.t + dt
		if r.t >= r.life then table.remove(rings, i) end
	end
	for i = #floats, 1, -1 do
		local f = floats[i]
		f.t = f.t + dt
		if f.t >= f.life then table.remove(floats, i) end
	end
end

local function ease_out(t)
	return 1 - (1 - t) * (1 - t)
end

function M.draw()
	love.graphics.push("all")
	love.graphics.setLineWidth(1.5)
	for _, p in ipairs(parts) do
		local a = 1 - p.t / p.life
		love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
		-- streak along the velocity: reads as motion
		love.graphics.line(p.x, p.y, p.x - p.vx * 0.03, p.y - p.vy * 0.03)
	end
	for _, r in ipairs(rings) do
		local k = r.t / r.life
		love.graphics.setColor(r.color[1], r.color[2], r.color[3], 1 - k)
		love.graphics.setLineWidth(r.width * (1 - k) + 1)
		love.graphics.circle("line", r.x, r.y, r.max_r * ease_out(k))
	end
	local font = love.graphics.getFont()
	for _, f in ipairs(floats) do
		local a = math.min(1, (f.life - f.t) / 0.35)
		local y = f.y - ease_out(f.t / f.life) * 36 * SCALE
		local w = font:getWidth(f.text)
		love.graphics.setColor(0, 0, 0, a * 0.6)
		love.graphics.print(f.text, f.x - w * 0.5 + 1, y + 1)
		love.graphics.setColor(f.color[1], f.color[2], f.color[3], a)
		love.graphics.print(f.text, f.x - w * 0.5, y)
	end
	love.graphics.pop()
end

-- Decaying offset for the whole scene; squared so small trauma barely moves it.
function M.shake_offset()
	if trauma <= 0 then return 0, 0 end
	local a = trauma * trauma * 13 * SCALE
	local t = love.timer.getTime()
	return a * math.sin(t * 71), a * math.cos(t * 59)
end

return M
