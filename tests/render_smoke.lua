-- Crash-test for the presentation layer: drives render/anim/fx/tooltip
-- through their main states with a stubbed love.graphics, catching nil
-- indexing and API typos the headless suite can't see. Pixels are not
-- checked — run the real game for that. From the repo root:
--   luajit tests/render_smoke.lua   (LuaJIT only, like LÖVE itself)

require("headless")

local rects = 0
-- Enough of a Font that the engine can treat it as one. setFilter matters:
-- text is drawn with nearest sampling because a glyph atlas is rasterised at
-- the size it is shown, and a stub without it turns that into a crash the real
-- game never sees.
local font = {
	getHeight = function() return 15 end,
	getWidth  = function(_, s) return 8 * #tostring(s) end,
	getWrap   = function(_, s, w) return w, { tostring(s) } end,
	setFilter = function() end,
}
local noop = function() end
love.graphics = setmetatable({
	getDimensions = function() return 960, 540 end,
	getWidth      = function() return 960 end,
	getHeight     = function() return 540 end,
	getFont       = function() return font end,
	newFont       = function() return font end,
	-- Enough of a canvas/image to let art.lua actually draw: every shape then
	-- runs its real geometry through the stubbed primitives, which is where a
	-- bad polygon or a nil count would blow up.
	-- A canvas is what art.lua hands back now, so the stub has to be a texture:
	-- everything downstream only ever asks it for its dimensions.
	newCanvas     = function()
		return { getDimensions = function() return 256, 256 end,
			getWidth = function() return 256 end, getHeight = function() return 256 end,
			newImageData = function() return {} end }
	end,
	newImage      = function()
		return { getDimensions = function() return 256, 256 end,
			getWidth = function() return 256 end, getHeight = function() return 256 end }
	end,
	-- Counted rather than ignored, so a test can see something that is *not*
	-- drawn — which is the only way to check a tag whose whole job is to
	-- suppress a shape.
	rectangle = function() rects = rects + 1 end,
	-- Not a stub but a check. Real LÖVE throws on a negative scissor, and a
	-- catch-all noop swallowed exactly that: a card shorter than the text band
	-- the layout reserves for it computed a negative image height and crashed
	-- the browser build on a game the suite otherwise called healthy. Anything
	-- that draws with a negative size is a bug, so say so here.
	setScissor = function(x, y, w, h)
		assert(not (w and h) or (w >= 0 and h >= 0),
			("setScissor with a negative size: %s,%s %sx%s"):format(x, y, w, h))
	end,
	-- Also a check rather than a stub. LÖVE answers malformed UTF-8 by drawing
	-- nothing and abandoning the rest of the zone, so a title truncated through
	-- the middle of a character silently deletes cards from the screen. That is
	-- invisible to a test that only asks whether drawing crashed.
	printf = function(text)
		local s, i = tostring(text), 1
		while i <= #s do
			local b, n = s:byte(i), 0
			if b < 0x80 then n = 1
			elseif b >= 0xF0 then n = 4
			elseif b >= 0xE0 then n = 3
			elseif b >= 0xC0 then n = 2
			else error("printf: stray continuation byte in " .. string.format("%q", s)) end
			for k = 1, n - 1 do
				local c = s:byte(i + k)
				assert(c and c >= 0x80 and c <= 0xBF,
					"printf: truncated UTF-8 in " .. string.format("%q", s))
			end
			i = i + n
		end
	end,
}, { __index = function() return noop end })
love.mouse = { getPosition = function() return 480, 270 end }
love.timer = { getTime = function() return os.clock() end }

math.randomseed(11)
require("rng").seed(11)   -- the engine's generator, so unseeded loads reproduce

local entity    = require("entity")
local zones     = require("zones")
local cards     = require("cards")
local actions   = require("actions")
local targeting = require("targeting")
local flow      = require("flow")
local render    = require("render")
local tooltip   = require("tooltip")
local anim      = require("anim")
local fx        = require("fx")

local frames = 0
local function frame(dt)
	anim.update(dt)
	fx.update(dt)
	render.sync_places()
	render.draw()
	tooltip.draw()
	frames = frames + 1
end

local function hand_card(def_key)
	for e in entity.each("card") do
		if e.def_key == def_key and e.zone_id == zones.find_id("hand") then return e end
	end
end

local function eval(str)
	actions.execute(str, {})
	flow.settle()
end

-- initial deal: cards gliding from the deck
flow.init("castle.json")
render.rescale()
render.set_can_undo(true)
for _ = 1, 30 do frame(0.016) end
render.hit_button(12, 520)
assert(select(1, render.stat_pos("gold")) ~= nil, "expected a HUD stat position")

-- targeting arrow over the board (slots eligible, cursor mid-screen)
eval("fill:hand:watchtower:1")
local wt = hand_card("watchtower")
targeting.start(wt.id, cards.def(wt).target)
assert(#targeting.eligible > 0, "expected eligible slots")
frame(0.016)
local slot = targeting.eligible[1]
targeting.clear()

-- board play: slam tween mid-flight (rotation path), then landing impact fx
flow.play_card(wt.id, { slot })
frame(0.016)
frame(0.05)
assert(anim.visual_place(wt.id), "expected the played card to be mid-flight")
assert(anim.visual_place(wt.id).rot ~= nil, "expected a flight tilt")
for _ = 1, 40 do frame(0.016) end
assert(not anim.visual_place(wt.id), "expected the flight to finish")

-- The tooltip, over each kind of thing it has to describe. It is built as
-- measured blocks now — title, prose, a rule, label/value rows, a hint — and
-- every one of those has its own branch, so hovering one card exercised a third
-- of it. The throne room is the interesting case: it is the player, so it
-- carries a column of stats and an ability that may or may not be affordable.
for _, id in ipairs({ zones.find("hand").cards[1], zones.find("board").cards[1] }) do
	tooltip.update(0.3, id)
	tooltip.update(0.3, id)
	frame(0.016)
	-- and again once it is spent, which is the other hint branch
	local e = entity.get(id)
	local was = e.exhausted
	e.exhausted = true
	frame(0.016)
	e.exhausted = was
end
local hover = zones.find("hand").cards[1]
tooltip.update(0.3, hover)
frame(0.016)

-- corner log, collapsed and expanded
render.toggle_log()
frame(0.016)
render.toggle_log()
frame(0.016)

-- detail overlay: single card, then zone browse
render.set_detail(zones.find("board").cards[1]); frame(0.016)
eval("draw_from:build_deck:graveyard:2")
render.set_detail(zones.find_id("graveyard")); frame(0.016)
render.set_detail(nil)

-- choose overlay: options flying in above the dim
eval("stat_set:gold:9")
eval("fill:hand:royal_decree:1")
flow.play_card(hand_card("royal_decree").id, {})
for _ = 1, 30 do frame(0.016) end

-- story page overlay: the built-in reveal panel, plus its detail view
flow.init("tower.json", 3)
render.rescale()
for _ = 1, 8 do frame(0.016) end
render.set_detail(zones.find("reveal").cards[1]); frame(0.016)
render.set_detail(nil)
flow.play_card(zones.find("reveal").cards[1], {})
for _ = 1, 8 do frame(0.016) end
flow.play_card(hand_card("c_search").id, {})
for _ = 1, 8 do frame(0.016) end
flow.play_card(zones.find("reveal").cards[1], {})
for _ = 1, 8 do frame(0.016) end

-- Titles that do not fit, in a font that has to cut them. A card whose name
-- carries any non-ASCII character — an accent, a dash, a middle dot — used to
-- truncate into invalid UTF-8 and vanish, along with everything after it.
flow.init("menu.json")
render.rescale()
for _, title in ipairs({ "Lost Cities · online", "Café des Étoiles très très long",
	"日本語のとても長いタイトル", "Ærøskøbing—Højbro Plads", "plain ascii but extremely long indeed" }) do
	cards.edit("play_castle", "text", title)
	for _ = 1, 2 do frame(0.016) end
end
cards.edit("play_castle", "text", "Castle Lord")

-- Tall narrow grids: an expedition column is five cells deep, so each cell is
-- shorter than the text band a card reserves. Every shipped game gets a draw
-- here for the same reason — layouts differ far more than draw code does.
-- chess.json is the densest of them: sixty-four cells, thirty-two cards, and
-- the only board where a card is drawn on a square another card may be aiming
-- at.
for _, g in ipairs({ "lost_cities.json", "kingdom.json", "road.json", "vigil.json",
	"chess.json", "the_crew.json", "puzzle_strike.json", "codex.json", "menu.json" }) do
	flow.init(g, 4)
	render.rescale()
	for _ = 1, 4 do frame(0.016) end
end

-- Ctrl+hover's JSON panel, over each of the three things it can describe, in a
-- game whose board is full: a card's dump is the longest and the only one that
-- has to scroll, and the panel reserves its own footer line to say so.
local inspect = require("inspect")
flow.init("chess.json", 4)
render.rescale()
do
	local piece = zones.find("board").cards[1]
	local slot  = entity.get(piece).slot_id
	for _, id in ipairs({ piece, slot, zones.find_id("board") }) do
		inspect.draw(id)
		inspect.scroll_by(5)
		inspect.draw(id)
		inspect.scroll_by(-99)
		inspect.draw(id)
	end
	inspect.draw(nil)
	inspect.draw(999999)
end

-- `cell_outline: false`: a painted board draws nothing on its empty cells,
-- and still lights the ones a move may reach. Counting the same frame twice
-- with the tag flipped is the only way to see a shape that isn't there — and
-- the difference is exact, one outline per empty square, so a change in what
-- else the board draws cannot make this pass by accident.
do
	local function drawn(f)
		rects = 0
		if f then f() end
		render.draw()
		return rects
	end

	flow.init("chess.json", 4)
	render.rescale()
	local board = zones.find("board")
	assert(board.style.cell_outline == false, "chess.json is expected to style its board bare")

	local bare = drawn()
	board.style.cell_outline = nil
	local lined = drawn()
	local empty = 64 - #board.cards
	assert(lined - bare == empty,
		("expected %d outlines to disappear with the tag, saw %d"):format(empty, lined - bare))

	-- The affordance is not chrome: with the tag back on, the squares a piece
	-- may move to are still drawn, or the board is unplayable.
	board.style.cell_outline = false
	local piece
	for _, id in ipairs(board.cards) do
		local c = entity.get(id)
		local spec = cards.behaviour(c, "activate_target")
		if spec then
			targeting.start(id, spec)
			if #targeting.eligible > 0 then piece = id; break end
			targeting.clear()
		end
	end
	assert(piece, "expected some piece on the opening board to have a legal move")
	assert(drawn() > bare, "an eligible square must be drawn even on a bare board")
	targeting.clear()
end

-- A picture that cannot be produced draws a generated one. The reasons are
-- mostly not the author's — a remote host refusing the fetch, or a game file
-- that arrived over the network without the sender's assets folder — and a card
-- with no image at all reads as a bug in the game rather than as a card.
do
	local cards = require("cards")
	for _, case in ipairs({ "no_such_file.png", "hexagram:red", "gibberish" }) do
		local img = cards.asset_image(case, "smoke_" .. case)
		assert(img, "expected a placeholder for " .. case)
		assert(img.getDimensions, "the placeholder should be a texture")
	end
	-- Twice for one key is one draw and one cache hit, never two prints.
	local first = cards.asset_image("no_such_file.png", "smoke_twice")
	assert(cards.asset_image("no_such_file.png", "smoke_twice") == first,
		"a placeholder should be cached like any other picture")
end

-- every base effect animates and draws
flow.init("castle.json", 7)
render.rescale()
for _, base in ipairs({ "damage", "bleed", "power_up", "sparkle", "stars", "heal", "smoke", "explosion" }) do
	fx.play({ base = base, size = 1.2, speed = 0.9, count = 1.4, color = { 0.9, 0.6, 0.4 } }, 480, 270)
end
for _ = 1, 25 do frame(0.033) end

-- ending banner: defeat page fires the flourish, confetti animates
eval("stat_damage:hp:99")
for _ = 1, 20 do frame(0.033) end
fx.celebrate("victory")
for _ = 1, 20 do frame(0.033) end

-- An ending with two seats in it draws twice from one state: the winner's name
-- when nobody at this screen is playing, and the loser's word when somebody is.
flow.init("chess.json", 1)
render.rescale()
eval("stat_gain:won@black_side:1")
eval("reveal:black_wins")
for _ = 1, 10 do frame(0.033) end
require("net").claim_seat("player_white")
for _ = 1, 10 do frame(0.033) end
require("net").claim_seat(nil)

-- direct bursts and floating deltas
fx.hit(300, 200)
fx.impact(400, 300, 1)
local gx, gy = render.stat_pos("gold")
fx.float(gx, gy, "+2 gold", { 0.4, 1, 0.5 })
fx.float(480, 260, "-1 morale", { 1, 0.4, 0.35 })
for _ = 1, 30 do frame(0.016) end

-- Every shape through its real geometry. The primitives are stubs, but the
-- arithmetic that feeds them is not: a bad polygon, a zero count or a nil
-- colour blows up here rather than as a blank card in a running game.
local art = require("art")
local drawn = 0
for _, spec in ipairs({
	"circle:teal", "square:#ff8000", "triangle:crimson", "diamond:gold",
	"cross:red:white", "polygon:3:green", "polygon:12:navy", "star:5:amber",
	"star:3:violet", "stripes:2:slate", "stripes:16:sand", "chequer:2:black:white",
	"chequer:16:olive", "dots:1:pink", "dots:8:cyan",
}) do
	assert(art.render(spec), "art.render returned nothing for " .. spec)
	drawn = drawn + 1
end
for _, key in ipairs({ "watchtower", "farm", "a", "", "the_longest_card_key_here" }) do
	assert(art.render(art.auto(key)), "auto art failed for '" .. key .. "'")
	drawn = drawn + 1
end
assert(art.render("hexagram:red") == nil, "an unknown shape must draw nothing")

-- A fanned stack, measured. This is arithmetic that draws nothing of its own —
-- it decides where the cards go — and the fault it replaced passed every test
-- in the suite: a 1x12 grid in a zone a finger tall gave each card eight pixels
-- and drew it as a horizontal line.
do
	flow.init("lost_cities.json", 11)
	render.rescale()
	local red = zones.find("red")
	for _, key in ipairs({ "red_w1", "red_2", "red_4", "red_6", "red_9" }) do
		eval("fill:mine.red:" .. key .. ":1")
	end
	frame(0.016)

	local z = red.place
	local last
	for i, cid in ipairs(red.cards) do
		local pl = entity.get(cid).place
		assert(pl and pl.w > 0, "every card in a fan needs a place of its own, card " .. i)
		assert(pl.x >= z.x - 1 and pl.y >= z.y - 1
			and pl.x + pl.w <= z.x + z.w + 1 and pl.y + pl.h <= z.y + z.h + 1,
			"a fanned card must stay inside its zone, card " .. i)
		if last then
			local strip = pl.y - last.y
			assert(strip > 0, "a fan laid down must go down, card " .. i)
			-- The strip is the point of the whole layout: it has to be tall
			-- enough for the card's name, which is what the eight-pixel grid
			-- cell was not.
			assert(strip >= 12, ("card %d shows a %.1fpx strip, too thin to letter"):format(i, strip))
			assert(math.abs(pl.w - last.w) < 0.01 and math.abs(pl.h - last.h) < 0.01,
				"cards in one fan are one size, card " .. i)
		end
		last = pl
	end
	assert(#red.cards == 5, "expected the five cards played above")

	-- And the other way: the same cards as a stack draw one card, which is what
	-- every other stack does. Which way a row fans is the zone's own field now,
	-- so this is two words rather than a style being taken off it.
	red.layout, red.row = "stack", nil
	render.sync_places()
	local top = entity.get(red.cards[#red.cards]).place
	assert(top.h > last.h * 2,
		"a stack that is not fanned shows its top card whole, not a strip")
end

-- A row too long for one line takes another line rather than thinner cards.
-- Puzzle Strike's bank draft opens forty-one chip plates in one offer, and a
-- row that only ever shrinks gave each of them 23px of picture — a strip with
-- no room for the name, which is the one thing a row exists to show.
do
	flow.init("puzzle_strike.json", 11)
	render.rescale()
	local offer = zones.find("options")
	local box = zones.find("chip_box")
	-- init lands in the character pick, whose roster is sitting in the offer.
	for i = #offer.cards, 1, -1 do zones.move_card(offer.cards[i], zones.find_id("void")) end
	for _ = 1, 41 do
		local cid = box.cards[#box.cards]
		if not cid then break end
		zones.move_card(cid, offer.id)
	end
	assert(#offer.cards == 41, "expected the whole chip box in the offer, got " .. #offer.cards)
	render.sync_places()

	local first = entity.get(offer.cards[1]).place
	local rows = 1
	for i, cid in ipairs(offer.cards) do
		local pl = entity.get(cid).place
		assert(pl and pl.w > 0, "every card in the offer needs a place, card " .. i)
		assert(pl.x >= offer.place.x - 1 and pl.y >= offer.place.y - 1
			and pl.x + pl.w <= offer.place.x + offer.place.w + 1
			and pl.y + pl.h <= offer.place.y + offer.place.h + 1,
			"an offered card must stay inside its zone, card " .. i)
		assert(math.abs(pl.w - first.w) < 0.01 and math.abs(pl.h - first.h) < 0.01,
			"cards in one row are one size, card " .. i)
		if pl.y > first.y + 1 then rows = math.max(rows, math.floor((pl.y - first.y) / (pl.h + 4)) + 1) end
	end
	assert(rows > 1, "forty-one cards across one line is the fault this replaced")
	-- Measured against the line it replaced rather than against a pixel count, so
	-- the floor means the same thing at any window size.
	local wire = offer.place.w / #offer.cards
	assert(first.w > wire * 2, ("a drafted chip is %.1fpx wide against a wire's %.1f"):format(first.w, wire))

	-- And the short question is unchanged: what fits on one line stays on one
	-- line, because one line is among the shapes the arithmetic tries.
	for i = #offer.cards, 4, -1 do zones.move_card(offer.cards[i], box.id) end
	render.sync_places()
	local y = entity.get(offer.cards[1]).place.y
	for _, cid in ipairs(offer.cards) do
		assert(math.abs(entity.get(cid).place.y - y) < 0.01, "three cards belong on one line")
	end
end

-- A card with no shape of its own takes the whole of its cell, outside a grid
-- as well as in one. `fit: "fill"` was read on the grid branch and nowhere
-- else, so two buttons in a wide strip drew as two portrait cards floating in
-- the middle of it — the zone said how much room there was and the card ratio
-- gave most of it back.
do
	local path = "game/games/tmp_fill.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
  "title": "Fill",
  "styles": { "button": { "fit": "fill" } },
  "zones": [
    { "key": "plain", "layout": "row", "pos": [0.05, 0.05, 0.45, 0.20],
      "contents": ["a", "b"] },
    { "key": "filled", "layout": "row", "tags": ["button"], "pos": [0.55, 0.05, 0.95, 0.20],
      "contents": ["c", "d"] },
    { "key": "many", "layout": "row", "tags": ["button"], "pos": [0.25, 0.30, 0.75, 0.90],
      "contents": ["e", "f", "g", "h", "i", "j", "k", "l"] }
  ],
  "phases": [{ "key": "main", "type": "player_input", "zone": "plain" }],
  "cards": [
    { "key": "a", "text": "End action" }, { "key": "b", "text": "End turn" },
    { "key": "c", "text": "End action" }, { "key": "d", "text": "End turn" },
    { "key": "e", "text": "E" }, { "key": "f", "text": "F" }, { "key": "g", "text": "G" },
    { "key": "h", "text": "H" }, { "key": "i", "text": "I" }, { "key": "j", "text": "J" },
    { "key": "k", "text": "K" }, { "key": "l", "text": "L" }
  ]
}]==])
	f:close()
	flow.init("tmp_fill.json", 5)
	os.remove(path)
	render.rescale()
	render.sync_places()

	local function places(key)
		local z, out = zones.find(key), {}
		for i, cid in ipairs(z.cards) do out[i] = entity.get(cid).place end
		return z, out
	end

	local plain, pp = places("plain")
	assert(math.abs(pp[1].h / pp[1].w - 1.6) < 0.01,
		("an unfilled card keeps the card ratio, got %.2f"):format(pp[1].h / pp[1].w))
	assert(pp[1].w * 2 < plain.place.w * 0.5, "and so leaves most of a wide strip empty")

	local filled, fp = places("filled")
	assert(math.abs(fp[1].h - fp[2].h) < 0.01 and math.abs(fp[1].w - fp[2].w) < 0.01,
		"two buttons in one zone are one size")
	assert(fp[1].w > pp[1].w * 2, ("a filled button is %.1fpx wide against %.1f"):format(fp[1].w, pp[1].w))
	-- The pair spans the zone bar the padding it is drawn inside, which is what
	-- "use the whole zone" has to mean if it is to mean anything measurable.
	local span = fp[2].x + fp[2].w - fp[1].x
	assert(span > filled.place.w * 0.9, ("two filled cards span %.1f of %.1f"):format(span, filled.place.w))
	assert(fp[1].h > filled.place.h * 0.7, "and take the height as well as the width")

	-- Eight of them tile rather than run off the edge, and every one stays in.
	local many, mp = places("many")
	for i, pl in ipairs(mp) do
		assert(pl.x >= many.place.x - 1 and pl.y >= many.place.y - 1
			and pl.x + pl.w <= many.place.x + many.place.w + 1
			and pl.y + pl.h <= many.place.y + many.place.h + 1,
			"a filled card must stay inside its zone, card " .. i)
	end
	local rows = 1
	for _, pl in ipairs(mp) do if pl.y > mp[1].y + 1 then rows = 2 end end
	assert(rows == 2, "eight cards in a tall zone come out as a block, not a line")
end

-- A bump is a displacement laid over a card standing still: the rules put it
-- somewhere and it stays there, so the rect the renderer asks for moves and
-- nothing else does. It also has to settle back to exactly where it started,
-- or a card that gets hit twice walks off its square.
do
	local rest = { x = 100, y = 200, w = 40, h = 60 }
	assert(anim.visual_place("bumper", rest) == nil, "a card at rest has no visual of its own")

	anim.bump("bumper", 0, 400)
	anim.update(0.05)
	local out = anim.visual_place("bumper", rest)
	assert(out, "a bumping card has a visual rect")
	assert(out.y > rest.y, "it leans towards what it hit")
	assert(out.y - rest.y <= 26.01, "and only leans — the reach is capped")
	assert(math.abs(out.x - rest.x) < 0.01, "straight down means straight down")
	assert(out.w == rest.w and out.h == rest.h, "a bump moves a card, it does not resize it")

	anim.update(1)
	assert(anim.visual_place("bumper", rest) == nil, "and it settles back to where it stood")

	-- Nothing to lean towards is not a bump.
	anim.bump("still", 0, 0)
	assert(anim.visual_place("still", rest) == nil, "a bump at no distance does nothing")
end

print("render smoke ok: " .. frames .. " frames drawn, " .. drawn .. " placeholders")
