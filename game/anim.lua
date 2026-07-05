-- Animation system: purely visual, completely decoupled from game state.
-- Game state (card.place) updates immediately; this module tracks visual
-- positions that fly toward it with a physical feel: cards lift off, grow
-- slightly mid-air, tilt into their direction of travel, and slam down with
-- a small overshoot. Hit-testing always uses card.place, never the visuals.

local M = {}

local tweens = {}

-- kind → duration; slam = onto the board, drop = onto a pile/deck, glide = hand
local DURATION = { glide = 0.22, drop = 0.26, slam = 0.32 }
local SQUASH   = 0.08   -- post-landing squash window for slams

M.on_land = nil   -- function(rect, kind), fired when a drop or slam finishes

local function ease_out(t)
	return 1 - (1 - t) * (1 - t)
end

-- Overshoots the target slightly and settles back: the slam.
local function ease_out_back(t)
	local c1, c3 = 1.70158, 2.70158
	t = t - 1
	return 1 + c3 * t * t * t + c1 * t * t
end

local function interp(t)
	local p = math.min(1, t.elapsed / t.duration)
	if p >= 1 then
		-- post-landing: squash against the ground, anchored at the bottom edge
		local q = math.sin(math.pi * math.min(1, (t.elapsed - t.duration) / SQUASH))
		local w = t.tw * (1 + 0.06 * q)
		local h = t.th * (1 - 0.10 * q)
		return { x = t.tx - (w - t.tw) * 0.5, y = t.ty + t.th - h, w = w, h = h, rot = 0 }
	end
	local e   = t.kind == "slam" and ease_out_back(p) or ease_out(p)
	local arc = math.sin(math.pi * p)   -- rises mid-flight, lands at 0
	local w   = t.fw + (t.tw - t.fw) * e
	local h   = t.fh + (t.th - t.fh) * e
	local gw  = w * (1 + t.pop * arc)
	local gh  = h * (1 + t.pop * arc)
	return {
		x   = t.fx + (t.tx - t.fx) * e - (gw - w) * 0.5,
		y   = t.fy + (t.ty - t.fy) * e - (gh - h) * 0.5 - t.lift * arc,
		w   = gw,
		h   = gh,
		rot = t.tilt * arc,
	}
end

-- Begin animating card `id` from `from` rect to `to` rect. If the card is
-- already mid-animation, the new tween starts from its current visual
-- position so motion stays smooth.
function M.move(id, from, to, kind)
	if math.abs(from.x - to.x) < 0.5 and math.abs(from.y - to.y) < 0.5
		and math.abs(from.w - to.w) < 0.5 and math.abs(from.h - to.h) < 0.5 then
		return
	end
	local existing = tweens[id]
	if existing then
		local cur = interp(existing)
		from = { x = cur.x, y = cur.y, w = cur.w, h = cur.h }
	end
	kind = kind or "glide"
	local dx   = to.x - from.x
	local dist = math.sqrt(dx * dx + (to.y - from.y) ^ 2)
	local body = kind == "slam" and 1 or kind == "drop" and 0.5 or 0.25
	tweens[id] = {
		fx = from.x, fy = from.y, fw = from.w, fh = from.h,
		tx = to.x,   ty = to.y,   tw = to.w,   th = to.h,
		elapsed = 0, duration = DURATION[kind], kind = kind,
		lift = math.min(46, dist * 0.18) * body,
		pop  = math.min(0.18, 0.06 + dist * 0.0003) * body,
		tilt = math.max(-0.14, math.min(0.14, dx / 900)) * body,
	}
end

function M.update(dt)
	for id, t in pairs(tweens) do
		t.elapsed = t.elapsed + dt
		if not t.landed and t.elapsed >= t.duration then
			t.landed = true
			if M.on_land and t.kind ~= "glide" then
				M.on_land({ x = t.tx, y = t.ty, w = t.tw, h = t.th }, t.kind)
			end
		end
		local total = t.duration + (t.kind == "slam" and SQUASH or 0)
		if t.elapsed >= total then tweens[id] = nil end
	end
end

-- Interpolated visual rect (plus rot, radians) for rendering, or nil at rest.
function M.visual_place(id)
	local t = tweens[id]
	if not t then return nil end
	return interp(t)
end

function M.clear()
	tweens = {}
end

return M
