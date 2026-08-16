-- Purely visual effects: impact rings, spark particles, screen shake.
-- Nothing here touches game state; flow never loads it.

local M = {}

local parts    = {}
local rings    = {}
local floats   = {}
local confetti = {}
local motes    = {}   -- shaped particles for the named card effects
local pending  = {}   -- work waiting its turn, so a run of hits reads as a run
local trauma   = 0
local SCALE    = 1

-- Match effect sizes to the UI scale (set by render.rescale).
function M.set_scale(s)
	SCALE = s
end

function M.clear()
	parts, rings, floats, confetti, motes, trauma = {}, {}, {}, {}, {}, 0
	pending = {}
end

-- The classic card-game effects, parameterized. Games name their own
-- effects on these bases ("effects" in the game file) and trigger them with
-- the effect: action; size/speed/count scale the look, color overrides it.
local function mote(m)
	motes[#motes + 1] = m
end

local BASES = {}

BASES.damage = function(x, y, o)
	for _ = 1, math.floor(8 * o.count) do
		local a = math.random() * 2 * math.pi
		mote({ shape = "slash", x = x, y = y, ang = a,
			vx = math.cos(a) * 220 * o.speed * SCALE, vy = math.sin(a) * 220 * o.speed * SCALE,
			size = 10 * o.size * SCALE, t = 0, life = 0.28 / o.speed, color = o.color or { 1.0, 0.25, 0.2 } })
	end
	rings[#rings + 1] = { x = x, y = y, t = 0, life = 0.25 / o.speed,
		max_r = 34 * o.size * SCALE, width = 3 * SCALE, color = o.color or { 1.0, 0.3, 0.2 } }
	trauma = math.min(1, trauma + 0.15 * o.size)
end

BASES.bleed = function(x, y, o)
	for _ = 1, math.floor(9 * o.count) do
		mote({ shape = "drop", x = x + (math.random() - 0.5) * 24 * o.size * SCALE, y = y,
			vx = (math.random() - 0.5) * 30 * SCALE, vy = (20 + math.random() * 50) * o.speed * SCALE,
			grav = 320 * o.speed * SCALE, size = (3 + math.random() * 2.5) * o.size * SCALE,
			t = 0, life = (0.7 + math.random() * 0.4) / o.speed, color = o.color or { 0.65, 0.08, 0.08 } })
	end
end

BASES.power_up = function(x, y, o)
	for _ = 1, math.floor(12 * o.count) do
		mote({ shape = "dot", x = x + (math.random() - 0.5) * 40 * o.size * SCALE,
			y = y + 20 * SCALE + math.random() * 20 * SCALE,
			vx = (math.random() - 0.5) * 20 * SCALE, vy = -(60 + math.random() * 80) * o.speed * SCALE,
			size = (2.5 + math.random() * 2.5) * o.size * SCALE,
			t = 0, life = (0.6 + math.random() * 0.5) / o.speed, color = o.color or { 1.0, 0.8, 0.3 } })
	end
	rings[#rings + 1] = { x = x, y = y, t = 0, life = 0.4 / o.speed,
		max_r = 44 * o.size * SCALE, width = 2.5 * SCALE, color = o.color or { 1.0, 0.8, 0.3 } }
end

BASES.sparkle = function(x, y, o)
	for _ = 1, math.floor(10 * o.count) do
		mote({ shape = "star", x = x + (math.random() - 0.5) * 56 * o.size * SCALE,
			y = y + (math.random() - 0.5) * 56 * o.size * SCALE,
			vx = 0, vy = -12 * o.speed * SCALE, spin = (math.random() - 0.5) * 4,
			size = (3 + math.random() * 3) * o.size * SCALE, twinkle = true,
			t = -math.random() * 0.35, life = (0.55 + math.random() * 0.5) / o.speed,
			color = o.color or { 1.0, 0.95, 0.65 } })
	end
end

BASES.stars = function(x, y, o)
	local n = math.max(3, math.floor(5 * o.count))
	for i = 1, n do
		mote({ shape = "star", orbit = { cx = x, cy = y, r = 30 * o.size * SCALE,
			a = (i / n) * 2 * math.pi, va = 4.5 * o.speed },
			x = x, y = y, vx = 0, vy = 0, spin = 3,
			size = 5.5 * o.size * SCALE,
			t = 0, life = 1.2 / o.speed, color = o.color or { 1.0, 0.9, 0.35 } })
	end
end

BASES.heal = function(x, y, o)
	for _ = 1, math.floor(9 * o.count) do
		mote({ shape = "cross", x = x + (math.random() - 0.5) * 44 * o.size * SCALE,
			y = y + (math.random() - 0.5) * 20 * SCALE,
			vx = 0, vy = -(35 + math.random() * 35) * o.speed * SCALE,
			size = (3.5 + math.random() * 2.5) * o.size * SCALE,
			t = -math.random() * 0.3, life = (0.8 + math.random() * 0.4) / o.speed,
			color = o.color or { 0.4, 0.95, 0.5 } })
	end
end

BASES.smoke = function(x, y, o)
	for _ = 1, math.floor(7 * o.count) do
		mote({ shape = "puff", x = x + (math.random() - 0.5) * 30 * o.size * SCALE, y = y,
			vx = (math.random() - 0.5) * 22 * SCALE, vy = -(20 + math.random() * 30) * o.speed * SCALE,
			size = (6 + math.random() * 7) * o.size * SCALE, grow = 14 * o.size * SCALE,
			t = -math.random() * 0.25, life = (1.0 + math.random() * 0.6) / o.speed,
			color = o.color or { 0.45, 0.45, 0.50 } })
	end
end

BASES.explosion = function(x, y, o)
	M.impact(x, y, math.min(1.6, 1.1 * o.size), o.color or { 1.0, 0.62, 0.25 })
	for _ = 1, math.floor(10 * o.count) do
		local a = math.random() * 2 * math.pi
		local sp = (140 + math.random() * 220) * o.speed * SCALE
		mote({ shape = "dot", x = x, y = y,
			vx = math.cos(a) * sp, vy = math.sin(a) * sp * 0.7 - 40 * SCALE, grav = 260 * SCALE,
			size = (2.5 + math.random() * 3) * o.size * SCALE,
			t = 0, life = (0.45 + math.random() * 0.35) / o.speed,
			color = o.color or { 1.0, 0.62, 0.25 } })
	end
end

-- Play a named-effect definition ({ base, size, speed, count, color }) at a
-- point. Unknown bases are ignored — the validator warns about them.
function M.play(def, x, y)
	local base = BASES[def.base or ""]
	if not base then return end
	base(x, y, {
		size  = tonumber(def.size) or 1,
		speed = math.max(0.25, tonumber(def.speed) or 1),
		count = tonumber(def.count) or 1,
		color = def.color,
	})
end

-- The base-effect vocabulary, for the validator.
function M.bases()
	local t = {}
	for k in pairs(BASES) do t[k] = true end
	return t
end

-- An ending flourish: golden confetti raining for a victory, slow dark
-- embers for a defeat. Drawn above the overlay dim via draw_celebration.
function M.celebrate(kind)
	local W = love.graphics.getWidth()
	local victory = kind == "victory"
	for _ = 1, 70 do
		confetti[#confetti + 1] = {
			x     = math.random() * W,
			y     = (-20 - math.random() * 160) * SCALE,
			vy    = (victory and 60 + math.random() * 100 or 22 + math.random() * 30) * SCALE,
			drift = (math.random() - 0.5) * 55 * SCALE,
			rot   = math.random() * 2 * math.pi,
			vr    = (math.random() - 0.5) * 7,
			size  = (victory and 5 + math.random() * 5 or 3 + math.random() * 4) * SCALE,
			t     = 0,
			life  = 3.0 + math.random() * 2.5,
			color = victory
				and { 0.95, 0.60 + math.random() * 0.35, 0.15 + math.random() * 0.35 }
				or { 0.40 + math.random() * 0.25, 0.26, 0.24 },
		}
	end
	if victory then trauma = math.min(1, trauma + 0.35) end
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

-- Do this a moment from now. Presentation only — whatever it shows has already
-- happened in the rules, so nothing downstream may depend on when it runs.
function M.after(delay, fn)
	if not (delay and delay > 0) then return fn() end
	pending[#pending + 1] = { at = delay, fn = fn }
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
	-- Anything waiting its turn. This is what lets a run of strikes read as a
	-- sequence instead of a single flash: the rules resolved the whole combat in
	-- one instant, and the sparks and numbers catch up one lane at a time.
	for i = #pending, 1, -1 do
		local q = pending[i]
		q.at = q.at - dt
		if q.at <= 0 then
			table.remove(pending, i)
			q.fn()
		end
	end
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
	for i = #confetti, 1, -1 do
		local c = confetti[i]
		c.t = c.t + dt
		if c.t >= c.life then
			table.remove(confetti, i)
		else
			c.x   = c.x + c.drift * math.sin(c.t * 2 + c.rot) * dt
			c.y   = c.y + c.vy * dt
			c.rot = c.rot + c.vr * dt
		end
	end
	for i = #motes, 1, -1 do
		local m = motes[i]
		m.t = m.t + dt
		if m.t >= m.life then
			table.remove(motes, i)
		elseif m.t >= 0 then
			if m.orbit then
				local o = m.orbit
				o.a = o.a + o.va * dt
				m.x = o.cx + math.cos(o.a) * o.r
				m.y = o.cy + math.sin(o.a) * o.r * 0.45
			else
				if m.grav then m.vy = m.vy + m.grav * dt end
				m.x = m.x + m.vx * dt
				m.y = m.y + m.vy * dt
			end
			if m.spin then m.ang = (m.ang or 0) + m.spin * dt end
			if m.grow then m.size = m.size + m.grow * dt end
		end
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
	for _, m in ipairs(motes) do
		if m.t >= 0 then
			local a = math.min(1, (m.life - m.t) / (m.life * 0.45))
			if m.twinkle then a = a * (0.4 + 0.6 * math.abs(math.sin(m.t * 9 + m.size))) end
			love.graphics.setColor(m.color[1], m.color[2], m.color[3], a)
			if m.shape == "dot" then
				love.graphics.circle("fill", m.x, m.y, m.size)
			elseif m.shape == "puff" then
				love.graphics.setColor(m.color[1], m.color[2], m.color[3], a * 0.35)
				love.graphics.circle("fill", m.x, m.y, m.size)
			elseif m.shape == "drop" then
				love.graphics.ellipse("fill", m.x, m.y, m.size * 0.45, m.size)
			elseif m.shape == "slash" then
				love.graphics.setLineWidth(math.max(1, m.size * 0.22))
				love.graphics.line(m.x - math.cos(m.ang or 0) * m.size, m.y - math.sin(m.ang or 0) * m.size,
					m.x + math.cos(m.ang or 0) * m.size, m.y + math.sin(m.ang or 0) * m.size)
			elseif m.shape == "cross" then
				local s = m.size
				love.graphics.rectangle("fill", m.x - s * 0.3, m.y - s, s * 0.6, s * 2)
				love.graphics.rectangle("fill", m.x - s, m.y - s * 0.3, s * 2, s * 0.6)
			elseif m.shape == "star" then
				-- five convex spikes: LÖVE won't fill a concave star polygon
				local s, ang = m.size, m.ang or 0
				for i = 0, 4 do
					local th = ang + i * 2 * math.pi / 5
					love.graphics.polygon("fill",
						m.x + math.cos(th) * s, m.y + math.sin(th) * s,
						m.x + math.cos(th - math.pi / 5) * s * 0.45,
						m.y + math.sin(th - math.pi / 5) * s * 0.45,
						m.x + math.cos(th + math.pi / 5) * s * 0.45,
						m.y + math.sin(th + math.pi / 5) * s * 0.45)
				end
				love.graphics.circle("fill", m.x, m.y, s * 0.42)
			end
		end
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

-- Confetti draws above the overlay dim, unlike the in-scene effects.
function M.draw_celebration()
	if #confetti == 0 then return end
	love.graphics.push("all")
	for _, c in ipairs(confetti) do
		local a = math.min(1, (c.life - c.t) / 0.8)
		love.graphics.setColor(c.color[1], c.color[2], c.color[3], a)
		love.graphics.push()
		love.graphics.translate(c.x, c.y)
		love.graphics.rotate(c.rot)
		love.graphics.rectangle("fill", -c.size * 0.5, -c.size * 0.25, c.size, c.size * 0.5)
		love.graphics.pop()
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
