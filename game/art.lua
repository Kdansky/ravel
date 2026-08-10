-- Procedural placeholder art: a card may name a shape instead of a file, so a
-- game needs no assets at all to be playable and legible.
--
-- This is decoration and nothing else. **Nothing below the presentation line
-- may require this module** — the moment a rule can ask "is this card red",
-- the art has become game data, and a solitaire deck whose colours are drawn
-- by the renderer is one refactor away from breaking its own rules. Colour the
-- rules care about is a tag or a stat; the art only has to agree with it.
--
-- `parse` is the one exception, and only because it is pure: no love, no
-- state, so validate.lua can check a spec at load time. That is the same
-- arrangement cards.url_is_safe already has, for the same reason.

local M = {}

-- Chosen to sit on the dark table without glowing. Names are the CSS basics
-- plus the muted tones the existing card art already uses.
local PALETTE = {
	black  = { 0.09, 0.10, 0.13 }, white  = { 0.93, 0.94, 0.92 },
	grey   = { 0.55, 0.58, 0.62 }, slate  = { 0.36, 0.42, 0.52 },
	ash    = { 0.72, 0.74, 0.76 }, silver = { 0.80, 0.83, 0.86 },
	red    = { 0.82, 0.26, 0.24 }, crimson= { 0.65, 0.16, 0.22 },
	maroon = { 0.44, 0.14, 0.18 }, pink   = { 0.90, 0.55, 0.65 },
	orange = { 0.88, 0.50, 0.20 }, amber  = { 0.90, 0.68, 0.25 },
	gold   = { 0.85, 0.72, 0.30 }, yellow = { 0.90, 0.85, 0.35 },
	sand   = { 0.78, 0.72, 0.55 }, tan    = { 0.68, 0.56, 0.40 },
	brown  = { 0.45, 0.33, 0.24 }, olive  = { 0.52, 0.55, 0.28 },
	green  = { 0.36, 0.62, 0.34 }, forest = { 0.20, 0.42, 0.28 },
	teal   = { 0.22, 0.56, 0.54 }, cyan   = { 0.38, 0.72, 0.78 },
	blue   = { 0.30, 0.50, 0.80 }, navy   = { 0.16, 0.24, 0.44 },
	indigo = { 0.32, 0.30, 0.62 }, violet = { 0.52, 0.38, 0.70 },
	purple = { 0.42, 0.26, 0.50 }, magenta= { 0.72, 0.32, 0.62 },
}

-- `n` is the default count; absent means the shape ignores one.
local SHAPES = {
	circle   = {},
	square   = {},
	triangle = {},
	diamond  = {},
	cross    = {},
	polygon  = { n = 5, min = 3, max = 12 },
	star     = { n = 5, min = 3, max = 12 },
	stripes  = { n = 4, min = 2, max = 16 },
	checker  = { n = 6, min = 2, max = 16 },
	dots     = { n = 3, min = 1, max = 8 },
}

-- A colour word: a palette name or "#rrggbb". Shared with the renderer, which
-- lets a zone paint its squares from the same vocabulary a card's art uses.
function M.colour(word)
	if type(word) ~= "string" then return nil end
	if PALETTE[word] then return PALETTE[word] end
	local r, g, b = word:match("^#(%x%x)(%x%x)(%x%x)$")
	if not r then return nil end
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

-- A background that is obviously the same idea as the foreground, so a
-- one-colour spec ("circle:teal") looks deliberate rather than unfinished.
local function backdrop(fg)
	return { fg[1] * 0.26 + 0.03, fg[2] * 0.26 + 0.04, fg[3] * 0.26 + 0.06 }
end

-- <shape>[:<n>]:<fg>[:<bg>] — the engine's usual colon style. Pure: no love,
-- no state, so the validator can call it. nil means "not a shape spec", which
-- is how cards.image tells a typo'd filename from a placeholder.
function M.parse(spec)
	if type(spec) ~= "string" then return nil end
	local parts = {}
	for p in spec:gmatch("[^:]+") do parts[#parts + 1] = p end

	local sd = SHAPES[parts[1] or ""]
	if not sd then return nil end
	local i, n = 2, sd.n

	-- A count is consumed wherever it appears, even for a shape that has no
	-- use for one: "circle:6:red" is odd but unambiguous, and refusing it
	-- would only produce a puzzling error about the colour.
	if tonumber(parts[i]) then
		n = math.floor(tonumber(parts[i]))
		i = i + 1
	end
	if sd.n then n = math.max(sd.min, math.min(sd.max, n or sd.n)) else n = nil end

	local fg = M.colour(parts[i])
	if not fg then return nil end
	local bg = M.colour(parts[i + 1]) or backdrop(fg)
	if parts[i + 2] then return nil end   -- trailing junk is a typo, not art

	return { shape = parts[1], n = n, fg = fg, bg = bg }
end

local function hsl(h, s, l)
	local function f(n)
		local k = (n + h * 12) % 12
		return l - s * math.min(l, 1 - l) * math.max(-1, math.min(k - 3, 9 - k, 1))
	end
	return { f(0), f(8), f(4) }
end

local AUTO_SHAPES = { "circle", "square", "triangle", "diamond", "polygon",
	"star", "cross", "stripes", "checker", "dots" }

-- A stable spec derived from the card key alone: same card, same art, every
-- run and every machine, with no authoring and no RNG draw (which would also
-- shift the seeded shuffle). Distinct shapes matter more than distinct hues —
-- you end up recognising cards by silhouette.
function M.auto(key)
	local h = 5381
	for i = 1, #tostring(key) do h = (h * 33 + tostring(key):byte(i)) % 4294967296 end
	local shape = AUTO_SHAPES[h % #AUTO_SHAPES + 1]
	local n     = 3 + math.floor(h / 16) % 6
	local c     = hsl((math.floor(h / 512) % 360) / 360, 0.52, 0.58)
	return string.format("%s:%d:#%02x%02x%02x", shape, n,
		math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local SIZE = 256

local function regular(cx, cy, r, sides, turn)
	local pts = {}
	for i = 0, sides - 1 do
		local a = turn + i * 2 * math.pi / sides
		pts[#pts + 1] = cx + math.cos(a) * r
		pts[#pts + 1] = cy + math.sin(a) * r
	end
	return pts
end

local function paint(p)
	local g, c = love.graphics, SIZE * 0.5
	g.clear(p.bg[1], p.bg[2], p.bg[3], 1)
	g.setColor(p.fg[1], p.fg[2], p.fg[3])

	if p.shape == "circle" then
		g.circle("fill", c, c, SIZE * 0.32)
	elseif p.shape == "square" then
		g.rectangle("fill", SIZE * 0.20, SIZE * 0.20, SIZE * 0.60, SIZE * 0.60)
	elseif p.shape == "triangle" then
		g.polygon("fill", regular(c, c, SIZE * 0.36, 3, -math.pi / 2))
	elseif p.shape == "diamond" then
		g.polygon("fill", regular(c, c, SIZE * 0.38, 4, -math.pi / 2))
	elseif p.shape == "cross" then
		g.rectangle("fill", SIZE * 0.40, SIZE * 0.16, SIZE * 0.20, SIZE * 0.68)
		g.rectangle("fill", SIZE * 0.16, SIZE * 0.40, SIZE * 0.68, SIZE * 0.20)
	elseif p.shape == "polygon" then
		g.polygon("fill", regular(c, c, SIZE * 0.36, p.n, -math.pi / 2))
	elseif p.shape == "star" then
		local pts, r1, r2 = {}, SIZE * 0.38, SIZE * 0.17
		for i = 0, p.n * 2 - 1 do
			local a = -math.pi / 2 + i * math.pi / p.n
			local r = (i % 2 == 0) and r1 or r2
			pts[#pts + 1] = c + math.cos(a) * r
			pts[#pts + 1] = c + math.sin(a) * r
		end
		g.polygon("fill", pts)
	elseif p.shape == "stripes" then
		local h = SIZE / (p.n * 2 - 1)
		for i = 0, p.n - 1 do g.rectangle("fill", 0, i * 2 * h, SIZE, h) end
	elseif p.shape == "checker" then
		local s = SIZE / p.n
		for row = 0, p.n - 1 do
			for col = 0, p.n - 1 do
				if (row + col) % 2 == 0 then g.rectangle("fill", col * s, row * s, s, s) end
			end
		end
	elseif p.shape == "dots" then
		local s = SIZE / p.n
		for row = 0, p.n - 1 do
			for col = 0, p.n - 1 do
				g.circle("fill", (col + 0.5) * s, (row + 0.5) * s, s * 0.28)
			end
		end
	end
end

-- A drawable texture, or nil for anything that isn't a spec or any platform
-- that can't draw one. Every love call is inside the pcall, so the headless
-- shim (which has no newCanvas) simply gets nil — the same contract
-- cards.image honours.
--
-- The canvas is returned as-is. It used to round-trip through
-- `newImage(canvas:newImageData())`, which bought nothing — a Canvas is
-- already a texture, and getDimensions/draw are all anyone asks of it — while
-- costing a full GPU readback per card. Worse, `newImageData` is a *pixel
-- read*, which is exactly the call browser fingerprinting protection perturbs:
-- Brave adds noise to canvas and WebGL reads by default, so every generated
-- card came back speckled while the JPEGs, which are never read back, were
-- perfect. Drawing the canvas directly never reads a pixel, so there is
-- nothing left to farble.
function M.render(spec)
	local p = M.parse(spec)
	if not p then return nil end
	local ok, img = pcall(function()
		local canvas = love.graphics.newCanvas(SIZE, SIZE)
		love.graphics.push("all")
		love.graphics.setCanvas(canvas)
		paint(p)
		love.graphics.setCanvas()
		love.graphics.pop()
		return canvas
	end)
	if not ok then pcall(love.graphics.setCanvas) end
	return ok and img or nil
end

-- The shape and colour vocabularies, for the validator's suggestions.
function M.shapes()
	local t = {}
	for k in pairs(SHAPES) do t[k] = true end
	return t
end

function M.colours()
	local t = {}
	for k in pairs(PALETTE) do t[k] = true end
	return t
end

return M
