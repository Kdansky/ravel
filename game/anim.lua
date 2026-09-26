-- Animation system: purely visual, completely decoupled from game state.
-- Game state (card.place) updates immediately; this module tracks visual
-- positions that fly toward it with a physical feel: cards lift off, grow
-- slightly mid-air, tilt into their direction of travel, and slam down with
-- a small overshoot. Hit-testing always uses card.place, never the visuals.
--

local M = {}

local tweens = {}
local bumps  = {}   -- a card leaning into what it is acting on, and settling back
local whirls = {}   -- a pile fanning out, spinning, and settling: a shuffle
local flips  = {}   -- a card turning over where it lies

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
	-- The overshoot is for where the card lands, never for its size: a card
	-- shrinking more than elevenfold would overshoot through zero width.
	local s   = ease_out(p)
	local w   = t.fw + (t.tw - t.fw) * s
	local h   = t.fh + (t.th - t.fh) * s
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
-- position so motion stays smooth. `flip` turns it over on the way.
function M.move(id, from, to, kind, flip)
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
		flip = flip,
	}
end

local WHIRL, FLIP = 0.6, 0.3

-- A shuffle: copies of the card fan out from under it, swing round it once and
-- close back up. `o` carries an effect's size, speed and count.
function M.whirl(id, o)
	o = o or {}
	local speed = math.max(0.25, tonumber(o.speed) or 1)
	whirls[id] = { elapsed = 0, duration = WHIRL / speed, size = tonumber(o.size) or 1,
		n = math.max(2, math.floor(4 * (tonumber(o.count) or 1) + 0.5)) }
end

-- The card turns over where it lies, showing the other side first.
function M.flip(id, o)
	flips[id] = { elapsed = 0, duration = FLIP / math.max(0.25, tonumber((o or {}).speed) or 1) }
end

-- How long a shuffle holds the board, so what is drawn off the pile leaves once it has settled.
function M.whirl_time()
	return WHIRL
end

local function smooth(t)
	t = math.max(0, math.min(1, t))
	return t * t * (3 - 2 * t)
end

-- The copies for one frame of a whirl. They open over the first fifth and close
-- over the last, and the swing between carries them round the card.
local function whirl_copies(w, r)
	local p = w.elapsed / w.duration
	local open = smooth(p / 0.2) * (1 - smooth((p - 0.8) / 0.2))
	local q = smooth((p - 0.15) / 0.7)
	local swing = math.sin(math.pi * q)
	local spin = 2 * math.pi * q
	local out = {}
	for i = 1, w.n do
		local fan = (i - (w.n + 1) / 2) * 0.22 * w.size
		local phi = 2 * math.pi * (i - 1) / w.n + spin
		local rad = r.w * 0.3 * w.size * swing * open
		local rot = open * (fan * (1 - swing) + 0.35 * math.sin(phi) * swing)
		out[i] = {
			-- Fanned from the bottom edge, as a hand holds cards: turning about the centre would lift the whole pile.
			x = r.x + math.cos(phi) * rad + math.sin(rot) * r.h * 0.5,
			y = r.y + math.sin(phi) * rad * 0.5 + (1 - math.cos(rot)) * r.h * 0.5,
			w = r.w, h = r.h, rot = rot,
		}
	end
	return out
end

-- A card lunging at whatever it just acted on. Purely a displacement laid over
-- wherever the card already is — the rules put it somewhere and it stays there,
-- so hit-testing, layout and the snapshot are all untouched.
--
-- It is the answer to "what just happened": a stat changed on a card across the
-- board and nothing tied the two together. The distance is capped because the
-- gesture is a nod towards the target, not a journey to it.
local BUMP = 0.24

function M.bump(id, dx, dy)
	local d = math.sqrt(dx * dx + dy * dy)
	if d < 1 then return end
	local reach = math.min(26, d * 0.4)
	bumps[id] = { dx = dx / d * reach, dy = dy / d * reach, elapsed = 0 }
end

function M.update(dt)
	for _, list in ipairs({ whirls, flips }) do
		for id, a in pairs(list) do
			a.elapsed = a.elapsed + dt
			if a.elapsed >= a.duration then list[id] = nil end
		end
	end
	for id, b in pairs(bumps) do
		b.elapsed = b.elapsed + dt
		if b.elapsed >= BUMP then bumps[id] = nil end
	end
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
-- `rest` is where the rules have the card; it is only needed for a bump, which
-- is an offset from a card that is otherwise standing still.
function M.visual_place(id, rest)
	local t, b, w, f = tweens[id], bumps[id], whirls[id], flips[id]
	local out
	if t then
		out = interp(t)
		if t.flip then out.flip = math.min(1, t.elapsed / t.duration) end
	elseif (b or w or f) and rest then
		out = { x = rest.x, y = rest.y, w = rest.w, h = rest.h, rot = 0 }
	end
	-- `flip` is how far over the card has turned: before half way it still shows the side it had.
	if out and f then out.flip = f.elapsed / f.duration end
	if out and w then out.copies = whirl_copies(w, out) end
	if out and b then
		-- Out quickly, back slowly: the weight is in the return.
		local p = b.elapsed / BUMP
		local k = p < 0.35 and (p / 0.35) or math.max(0, 1 - (p - 0.35) / 0.65)
		out.x = out.x + b.dx * k
		out.y = out.y + b.dy * k
	end
	-- Last line of defence: LÖVE throws on a negative scissor, so a slip in any
	-- curve above would take the whole game down over one frame of one card.
	if out then
		out.w, out.h = math.max(1, out.w), math.max(1, out.h)
	end
	return out
end

function M.clear()
	tweens = {}
	bumps  = {}
	whirls = {}
	flips  = {}
end

return M
