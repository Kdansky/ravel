-- Crash-test for the presentation layer: drives render/anim/fx/tooltip
-- through their main states with a stubbed love.graphics, catching nil
-- indexing and API typos the headless suite can't see. Pixels are not
-- checked — run the real game for that. From the repo root:
--   luajit tests/render_smoke.lua   (LuaJIT only, like LÖVE itself)

require("headless")

local rects = 0
local font = {
	getHeight = function() return 15 end,
	getWidth  = function(_, s) return 8 * #tostring(s) end,
	getWrap   = function(_, s, w) return w, { tostring(s) } end,
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
eval("set_stat:gold:9")
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
	"chess.json", "menu.json" }) do
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
eval("lose_stat:hp:99")
for _ = 1, 20 do frame(0.033) end
fx.celebrate("victory")
for _ = 1, 20 do frame(0.033) end

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
	"star:3:violet", "stripes:2:slate", "stripes:16:sand", "checker:2:black:white",
	"checker:16:olive", "dots:1:pink", "dots:8:cyan",
}) do
	assert(art.render(spec), "art.render returned nothing for " .. spec)
	drawn = drawn + 1
end
for _, key in ipairs({ "watchtower", "farm", "a", "", "the_longest_card_key_here" }) do
	assert(art.render(art.auto(key)), "auto art failed for '" .. key .. "'")
	drawn = drawn + 1
end
assert(art.render("hexagram:red") == nil, "an unknown shape must draw nothing")

print("render smoke ok: " .. frames .. " frames drawn, " .. drawn .. " placeholders")
