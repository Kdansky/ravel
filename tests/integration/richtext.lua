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
