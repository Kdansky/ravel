-- Animation system: purely visual, completely decoupled from game state.
-- Game state (card.place) updates immediately; this module tracks visual
-- positions that fly toward it with a physical feel: cards lift off, grow
-- slightly mid-air, tilt into their direction of travel, and slam down with
-- a small overshoot. Hit-testing always uses card.place, never the visuals.
--
-- A card can also be *held*, which is how `stage` plays a click back in the
-- order it happened: the flight is worked out as usual and simply not started
-- yet. That is the only way the visual position and card.place ever disagree
-- about which state they are in, and it lasts as long as one click's run.

local M = {}

local tweens = {}
local bumps  = {}   -- a card leaning into what it is acting on, and settling back
-- Cards that are not allowed to set off yet. `stage` pins one while a click's
-- steps are queued up, so the card stays where the player last saw it while the
-- rules run on ahead. The move the layout asks for in the meantime is kept, not
-- refused, and fired when the card's beat comes round.
local held   = {}

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
	local h = held[id]
	if h then
		-- Where it set off from is the first answer given, not the last: the
		-- layout keeps shifting under a pinned card as the ones around it land,
		-- and it is still leaving from where it stood when the click happened.
		h.from, h.to, h.kind = h.from or from, to, kind
		return
	end
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

function M.hold(id)
	held[id] = held[id] or {}
end

function M.holding(id)
	return held[id] ~= nil
end

-- Let a pinned card go without the journey: it is simply somewhere else now.
-- What a card that moved more than once in one run gets — the line from where it
-- started to where it ended is a trip it never took, and when a shuffle happened
-- along the way it is one nobody is allowed to watch.
function M.cut(id)
	held[id] = nil
end

-- Let a pinned card go, starting whatever move it was waiting on.
function M.release(id)
	local h = held[id]
	if not h then return end
	held[id] = nil
	if h.to then M.move(id, h.from, h.to, h.kind) end
end

function M.update(dt)
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
	local t, b = tweens[id], bumps[id]
	local h    = held[id]
	local out
	if h and h.from then
		out = { x = h.from.x, y = h.from.y, w = h.from.w, h = h.from.h, rot = 0 }
	elseif t then
		out = interp(t)
	elseif b and rest then
		out = { x = rest.x, y = rest.y, w = rest.w, h = rest.h, rot = 0 }
	end
	if out and b then
		-- Out quickly, back slowly: the weight is in the return.
		local p = b.elapsed / BUMP
		local k = p < 0.35 and (p / 0.35) or math.max(0, 1 - (p - 0.35) / 0.65)
		out.x = out.x + b.dx * k
		out.y = out.y + b.dy * k
	end
	return out
end

function M.clear()
	tweens = {}
	bumps  = {}
	held   = {}
end

return M
