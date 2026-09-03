-- Two marks in card text: `*bold*` and `_italic_`.
--
-- What is worth testing here is not that the marks work — it is everywhere they
-- must *not*. A card file is full of asterisks and underscores that were never
-- meant as markup: `weather_now` is a zone key a tooltip may name, and "2 * 3"
-- is arithmetic. A mark that fires where nobody asked eats a word silently, and
-- the only sign is prose that reads wrong on one card out of a hundred.
--
-- Drawing is not tested here (tests/render_smoke.lua drives that with a stubbed
-- graphics module). Wrapping is, because wrapping is arithmetic: a bold word is
-- wider than the plain one, and a panel measured off the plain text comes out
-- short of what it then draws.

local rich = require("richtext")

-- A face with no LOVE behind it: every glyph half the size wide, the size tall.
-- Enough for the only two questions wrapping asks a font.
local function face(px)
	return { px = px,
		getWidth = function(_, s) return #s * (px / 2) end,
		getHeight = function() return px end }
end

local sized = {}
local function at(px)
	sized[px] = sized[px] or face(px)
	return sized[px]
end

-- render hands this over at load; here the harness does, so italic can be a
-- size down the way it is on screen.
rich.font_step = function(f, d) return at(f.px + d) end

local function styles(s)
	local out = {}
	for _, r in ipairs(rich.parse(s)) do
		out[#out + 1] = (r.bold and "B" or "") .. (r.italic and "I" or "") .. ":" .. r.text
	end
	return table.concat(out, "|")
end

local M = {}

function M.test_richtext_a_mark_around_a_word_sets_it(check)
	check("bold takes the word between the stars",
		styles("Deal *2 damage* now.") == ":Deal |B:2 damage|: now.", styles("Deal *2 damage* now."))
	check("italic takes the words between the bars",
		styles("_A wind that remembers._") == "I:A wind that remembers.",
		styles("_A wind that remembers._"))
	check("both in one line stay apart",
		styles("*Gain* a card, then _draw_.") == "B:Gain|: a card, then |I:draw|:.",
		styles("*Gain* a card, then _draw_."))
	check("the marks are gone from the text itself",
		rich.strip("*Gain* a card, then _draw_.") == "Gain a card, then draw.")
end

function M.test_richtext_an_underscore_inside_a_word_is_part_of_the_word(check)
	-- The case that made this rule: a tooltip naming two zones by their keys had
	-- everything between them in italic, and the file looked correct.
	local s = "moves from weather_now to weather_discard"
	check("a key with an underscore is left alone", styles(s) == ":" .. s, styles(s))
	check("and reads back unchanged", rich.strip(s) == s)
end

function M.test_richtext_a_mark_that_never_closes_stays_a_character(check)
	check("arithmetic survives", rich.strip("2 * 3 = 6") == "2 * 3 = 6")
	check("a lone underscore survives", rich.strip("a lone _ mark") == "a lone _ mark")
	check("an opener with no closer is printed",
		rich.strip("*unfinished business") == "*unfinished business")
	check("a mark inside a word is not an opener", rich.strip("un*even") == "un*even")
	-- A style is one paragraph's business. Without this a forgotten star on the
	-- first line takes the rest of the card with it.
	check("a mark does not reach across a line break",
		rich.strip("*open\nnext line") == "*open\nnext line")
end

function M.test_richtext_plain_text_is_recognised_as_plain(check)
	check("no marks, nothing to do", rich.plain("Deal 2 damage to your opponent."))
	check("a star counts as markup until proven otherwise", not rich.plain("Deal *2* damage."))
	check("so does an underscore", not rich.plain("weather_now"))
end

function M.test_richtext_wrapping_measures_each_run_in_its_own_face(check)
	local base = at(12)
	local plain = "Gain a card at or below your Tier"
	local marked = "*Gain* a card at or below your *Tier*"
	check("the same words with marks strip to the same words",
		rich.strip(marked) == plain)

	local w = 120
	for _, l in ipairs(rich.wrap(base, marked, w)) do
		check("no line runs past the box it was given", l.w <= w, l.w)
	end

	-- Italic is set a size down, so the same sentence in italic takes less room
	-- than in the body face. That is the whole of "flavour steps back".
	local body = rich.wrap(base, "the storm settles a moment and then does not", 80)
	local flav = rich.wrap(base, "_the storm settles a moment and then does not_", 80)
	check("flavour fits in no more lines than the body face would", #flav <= #body,
		#flav .. " vs " .. #body)
end

-- Bold is the same glyphs struck again a little to the right, because the face
-- ships no bold cut -- and how far to the right has to follow the size of the
-- type, not the size of the screen. Struck once at the far edge, a two-pixel
-- stroke draws two thin letters with a hole down the middle instead of one heavy
-- one, which is exactly what a doubled-up bold looks like at any UI scale above
-- one. So every pixel across is struck, and the last one is worked out from the
-- face being drawn.
function M.test_richtext_a_bold_is_struck_at_every_pixel_across(check)
	local real, hits = love.graphics, nil
	love.graphics = {
		setFont = function() end, setColor = function() end,
		push = function() end, pop = function() end,
		print = function(_, x) hits[#hits + 1] = x end,
	}
	local function strikes(px, text)
		hits = {}
		rich.draw(at(px), rich.wrap(at(px), text, 1e6), 0, 0, 1e6)
		return hits
	end
	local plain, small, big = strikes(12, "ab"), strikes(12, "*ab*"), strikes(60, "*ab*")
	love.graphics = real

	check("plain text is drawn once", #plain == 1, #plain)
	check("body-sized bold is one strike heavier", #small == 2, #small)
	-- Sixty-pixel type wants two pixels of stroke, and both of them are struck.
	check("bigger type is struck wider", #big == 3, #big)
	local gaps = {}
	for i = 2, #big do gaps[#gaps + 1] = big[i] - big[i - 1] end
	check("with no gap left between the strikes",
		table.concat(gaps, ",") == "1,1", table.concat(gaps, ","))

	-- And what it draws is what it was measured as, or a bold word runs into the
	-- next one and off the end of the box it was wrapped into.
	local w_plain = rich.wrap(at(12), "ab", 1e6)[1].w
	local w_bold  = rich.wrap(at(12), "*ab*", 1e6)[1].w
	check("a bold run is measured as wide as it draws", w_bold == w_plain + 1,
		w_bold .. " vs " .. w_plain)
end


function M.test_richtext_a_line_break_in_the_text_breaks_the_line(check)
	local base = at(12)
	local lines = rich.wrap(base, "one\ntwo\nthree", 500)
	check("three lines, one per break", #lines == 3, #lines)
	local words = {}
	for i, l in ipairs(lines) do
		local t = {}
		for _, run in ipairs(l) do t[#t + 1] = run.text end
		words[i] = table.concat(t)
	end
	check("in the order they were written",
		words[1] == "one" and words[2] == "two" and words[3] == "three",
		table.concat(words, "/"))
end

function M.test_richtext_a_style_that_starts_mid_sentence_keeps_its_space(check)
	-- Runs are drawn one after another at measured offsets, so a space that goes
	-- missing between two of them is two words printed as one.
	local base = at(12)
	local l = rich.wrap(base, "take *two* cards", 500)[1]
	local t = {}
	for _, run in ipairs(l) do t[#t + 1] = run.text end
	check("the words are still separated", table.concat(t) == "take two cards",
		"[" .. table.concat(t) .. "]")
end

return M
