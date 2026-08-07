-- Crash-test for the presentation layer: drives render/anim/fx/tooltip
-- through their main states with a stubbed love.graphics, catching nil
-- indexing and API typos the headless suite can't see. Pixels are not
-- checked — run the real game for that. From the repo root:
--   luajit tests/render_smoke.lua   (LuaJIT only, like LÖVE itself)

require("headless")

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
	newCanvas     = function() return { newImageData = function() return {} end } end,
	newImage      = function()
		return { getDimensions = function() return 256, 256 end,
			getWidth = function() return 256 end, getHeight = function() return 256 end }
	end,
}, { __index = function() return noop end })
love.mouse = { getPosition = function() return 480, 270 end }
love.timer = { getTime = function() return os.clock() end }

math.randomseed(11)

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

-- tooltip after hover delay
local hover = zones.find("hand").cards[1]
tooltip.update(0.3, hover)
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
flow.pick(zones.find("reveal").cards[1])
for _ = 1, 8 do frame(0.016) end
flow.play_card(hand_card("c_search").id, {})
for _ = 1, 8 do frame(0.016) end
flow.pick(zones.find("reveal").cards[1])
for _ = 1, 8 do frame(0.016) end

-- every base effect animates and draws
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
