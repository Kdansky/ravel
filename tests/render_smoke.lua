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

-- direct bursts and floating deltas
fx.hit(300, 200)
fx.impact(400, 300, 1)
local gx, gy = render.stat_pos("gold")
fx.float(gx, gy, "+2 gold", { 0.4, 1, 0.5 })
fx.float(480, 260, "-1 morale", { 1, 0.4, 0.35 })
for _ = 1, 30 do frame(0.016) end

print("render smoke ok: " .. frames .. " frames drawn")
