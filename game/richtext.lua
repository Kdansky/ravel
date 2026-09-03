-- Two marks, and nothing else: `*bold*` and `_italic_`.
--
-- Card text is prose a player reads at a glance, and the two things prose wants
-- to do are lean on a word and step back from one. Bold is the mechanics -- a
-- stat, a keyword, a number that matters. Italic is flavour: the line that is
-- there to be enjoyed rather than obeyed, set a size smaller so the eye knows
-- to skip it while it is still deciding what to play.
--
-- Nothing here is a markdown parser. No links, no headings, no code spans and
-- no nesting, because a card is one paragraph and the alternative is a language
-- with precedence living inside a game file.
--
-- LOVE ships one face and no bold or italic cut of it, so both are drawn rather
-- than set: bold is the same glyphs struck twice a pixel apart, italic is the
-- same glyphs sheared. At the size a card is read at that is what the reader
-- wants from the distinction anyway -- weight and slant -- and it costs no font
-- files.
local M = {}

-- The font cache and the UI scale belong to render, so it hands over the one
-- thing this module cannot work out on its own: the same face a size along.
-- Replaced once, at load, by whoever owns the cache.
M.font_step = function(font) return font end

-- How much fatter a bold is than the face it thickens, as a fraction of the line
-- height. It has to follow the size rather than the screen: one fixed pixel is
-- invisible on a banner, and three on body text are not a heavy letter but two
-- thin ones with a gap down the middle.
--
-- The default face's line height is a fifth again its size, so this is one pixel
-- of stroke up to about 30px of type, two to 60, three above -- which is a hair
-- under a tenth of the stem width at every size, and reads as weight rather than
-- as a smear.
local WEIGHT = 0.04

-- How far an italic leans, as a fraction of the line height.
local SLANT = 0.18

local MARK = { ["*"] = "bold", ["_"] = "italic" }

local function alnum(ch)
	return ch ~= nil and ch:match("[%w]") ~= nil
end

-- Where this mark closes, or nil if it never does -- which is what keeps a bare
-- asterisk in a sentence an asterisk, and `weather_now` one word. A style never
-- spans a line break: a forgotten mark then costs one paragraph rather than the
-- rest of the card.
local function closes_at(s, from, mark)
	for j = from, #s do
		local c = s:sub(j, j)
		if c == "\n" then return nil end
		if c == mark and s:sub(j - 1, j - 1):match("%S") and not alnum(s:sub(j + 1, j + 1)) then
			return j
		end
	end
end

-- Text to runs. A run is a stretch wearing one style; the marks themselves are
-- gone by the time anything measures or draws.
function M.parse(s)
	local runs, buf = {}, {}
	local bold, italic = false, false
	local function flush()
		if #buf > 0 then
			runs[#runs + 1] = { text = table.concat(buf), bold = bold, italic = italic }
			buf = {}
		end
	end
	for i = 1, #s do
		local c = s:sub(i, i)
		local style = MARK[c]
		local on = style and (style == "bold" and bold or style == "italic" and italic)
		if style and on and s:sub(i - 1, i - 1):match("%S") and not alnum(s:sub(i + 1, i + 1)) then
			flush()
			if style == "bold" then bold = false else italic = false end
		elseif style and not on and not alnum(s:sub(i - 1, i - 1))
			and s:sub(i + 1, i + 1):match("%S") and closes_at(s, i + 1, c) then
			flush()
			if style == "bold" then bold = true else italic = true end
		else
			buf[#buf + 1] = c
		end
	end
	flush()
	return runs
end

-- The same words with the marks taken off, for everywhere text is read rather
-- than drawn: a terminal, a log line, a width measured by something that knows
-- nothing about styles.
function M.strip(s)
	local out = {}
	for _, r in ipairs(M.parse(s)) do out[#out + 1] = r.text end
	return table.concat(out)
end

-- The mark that opens a style and never closes it, or nil. A mark that never
-- closes prints as itself, which is right for the arithmetic and the zone keys
-- that share these two characters -- but on a card where somebody meant markup
-- it is a typo nobody sees, so the validator asks.
function M.unclosed(s)
	for i = 1, #s do
		local c = s:sub(i, i)
		if MARK[c] and not alnum(s:sub(i - 1, i - 1)) and s:sub(i + 1, i + 1):match("%S")
			and not closes_at(s, i + 1, c) then
			return c
		end
	end
end

-- Whether a string carries no mark at all, so a caller can skip the whole of
-- this module for the plain text that most text still is.
function M.plain(s)
	return not (s:find("*", 1, true) or s:find("_", 1, true))
end

-- The face a run is set in. Italic is a size down because the only thing a card
-- writes in italic is flavour, and flavour the same size as the rules competes
-- with them for the same glance.
local function face(font, run)
	return run.italic and M.font_step(font, -1) or font
end

-- How far the last strike of a bold lands past the first, in whole pixels: at
-- least one, or the mark would do nothing at all.
local function weight(f)
	return math.max(1, math.floor(f:getHeight() * WEIGHT + 0.5))
end

local function width_of(font, run)
	local f = face(font, run)
	-- The lean pushes the last glyph's top past where its box ends, so the run
	-- is one slant wider than its glyphs are. Without this an italic word runs
	-- into whatever follows it.
	--
	-- A bold is wider than its glyphs for the same reason, by the strike that
	-- fattens it -- and a run measured thinner than it draws runs into the next
	-- word and off the end of the box it was wrapped into.
	return f:getWidth(run.text)
		+ (run.italic and f:getHeight() * SLANT or 0)
		+ (run.bold and weight(f) or 0)
end

local function like(run, text)
	return { text = text, bold = run.bold, italic = run.italic }
end

-- The smallest pieces a line break may fall between: a word with the spaces it
-- carries, or a break of its own. Leading spaces stay on the word so a style
-- that starts mid-sentence keeps the gap before it.
local function tokens(runs)
	local out = {}
	for _, r in ipairs(runs) do
		local i = 1
		while i <= #r.text do
			local nl = r.text:find("\n", i, true)
			local seg = nl and r.text:sub(i, nl - 1) or r.text:sub(i)
			for word in seg:gmatch("[ \t]*%S+[ \t]*") do
				out[#out + 1] = like(r, word)
			end
			if not nl then break end
			out[#out + 1] = like(r, "\n")
			i = nl + 1
		end
	end
	return out
end

-- Wrapped lines, each a list of runs carrying its own width. The greedy fill
-- LOVE does, done a run at a time so a bold word is measured in the face it
-- will be drawn in rather than in the one around it.
function M.wrap(font, s, w)
	local lines = { { w = 0 } }
	for _, tok in ipairs(tokens(M.parse(s))) do
		if tok.text == "\n" then
			lines[#lines + 1] = { w = 0 }
		else
			local l = lines[#lines]
			-- Measured without the space it trails, so a word that only just
			-- fits is not pushed down by a gap that would never be drawn.
			local bare = tok.text:match("^%s*(.-)%s*$")
			if l.w > 0 and l.w + width_of(font, like(tok, bare)) > w then
				lines[#lines + 1] = { w = 0 }
				l = lines[#lines]
			end
			local text = l.w == 0 and tok.text:gsub("^[ \t]+", "") or tok.text
			local tw = width_of(font, like(tok, text))
			local last = l[#l]
			-- Adjacent pieces in one style are one run: a paragraph is then two
			-- or three draws rather than thirty, which counts where every run is
			-- struck nine times for its outline.
			if last and last.bold == tok.bold and last.italic == tok.italic then
				last.text, last.w = last.text .. text, last.w + tw
			else
				l[#l + 1] = like(tok, text)
				l[#l].w = tw
			end
			l.w = l.w + tw
		end
	end
	-- The space a line ends on is not part of how wide it is, or a centred line
	-- sits half a space left of centre.
	for _, l in ipairs(lines) do
		local last = l[#l]
		if last and last.text:match("%s$") then
			local trimmed = last.text:gsub("%s+$", "")
			local dw = last.w - width_of(font, like(last, trimmed))
			last.w, l.w = last.w - dw, l.w - dw
		end
	end
	return lines
end

-- Every line advances by the base face's height even where it holds only the
-- smaller type, so a flavour line does not close up under the rule above it.
function M.height(font, s, w)
	return #M.wrap(font, s, w) * font:getHeight()
end

local OUTLINE = { {-1,-1},{0,-1},{1,-1},{-1,0},{1,0},{-1,1},{0,1},{1,1} }

local function draw_run(font, run, x, y)
	local f = face(font, run)
	love.graphics.setFont(f)
	local kx = run.italic and -SLANT or 0
	-- The shear pivots at the top, so a sheared run's feet land a slant left of
	-- where it was placed; half a slant back keeps the word inside the box it
	-- was measured into.
	local ox = run.italic and f:getHeight() * SLANT * 0.5 or 0
	-- Whole pixels: the atlas is rasterised at exactly the size it is drawn, so
	-- landing between texels is most of what "blurry" is.
	x, y = math.floor(x + ox + 0.5), math.floor(y + 0.5)
	love.graphics.print(run.text, x, y, 0, 1, 1, 0, 0, kx, 0)
	if run.bold then
		-- Struck at every whole pixel across rather than only at the far edge.
		-- Two strikes two pixels apart are two letters, and the hole down the
		-- middle of them is what a doubled-up bold looks like.
		for i = 1, weight(f) do
			love.graphics.print(run.text, x + i, y, 0, 1, 1, 0, 0, kx, 0)
		end
	end
end

local function draw_line(font, l, lx, ly)
	local x = lx
	for _, run in ipairs(l) do
		draw_run(font, run, x, ly)
		x = x + run.w
	end
end

-- Draw lines already wrapped, so a caller that had to measure them first --
-- a card with room for three of five -- draws the same ones it counted.
-- `opts.outline` strikes the text in that colour eight ways first, which is how
-- a card's own words read over art.
function M.draw(font, lines, x, y, w, align, opts)
	opts = opts or {}
	-- A panel that spaces its lines wider than the face does says so; a card,
	-- which has no room to spare, takes the face's own height.
	local lh, out = opts.line_h or font:getHeight(), opts.outline
	local fg = opts.color or { 1, 1, 1 }
	love.graphics.push("all")
	for i, l in ipairs(lines) do
		local ly = y + (i - 1) * lh
		local lx = x
		if align == "center" then lx = x + (w - l.w) * 0.5
		elseif align == "right" then lx = x + w - l.w
		end
		if out then
			-- A halo one stroke thick, which is the same measure as a bold and for
			-- the same reason: a single pixel around sixty-pixel type is not a
			-- halo, it is a slightly soft edge.
			local r = weight(font)
			love.graphics.setColor(out[1], out[2], out[3], out[4] or 1)
			for _, o in ipairs(OUTLINE) do
				draw_line(font, l, lx + o[1] * r, ly + o[2] * r)
			end
		end
		love.graphics.setColor(fg[1], fg[2], fg[3], fg[4] or 1)
		draw_line(font, l, lx, ly)
	end
	love.graphics.pop()
	return #lines
end

-- Wrap and draw in one call, for the callers with room for whatever it comes to.
function M.printf(font, s, x, y, w, align, opts)
	return M.draw(font, M.wrap(font, s, w), x, y, w, align, opts)
end

return M
