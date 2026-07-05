local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local targeting   = require("targeting")
local actions     = require("actions")
local flow        = require("flow")
local render      = require("render")
local tooltip     = require("tooltip")
local anim        = require("anim")
local fx          = require("fx")
local debugserver = require("debugserver")
local validate    = require("validate")
local log         = require("log")

-- Find a slot entity at the given screen position.
local function slot_at(x, y)
	for e in entity.each("slot") do
		if zones.contains(e.place, x, y) then return e.id end
	end
end

-- Topmost face-up card at screen position. Decks are never clickable;
-- piles only expose their top card.
local function card_at(x, y)
	local result
	for z in entity.each("zone") do
		if z.zone_type ~= "deck" and zones.contains(z.place, x, y) then
			local list = z.zone_type == "pile" and { z.cards[#z.cards] } or z.cards
			for _, cid in ipairs(list) do
				local c = entity.get(cid)
				if c and c.place and zones.contains(c.place, x, y) then result = cid end
			end
		end
	end
	return result
end

local function cancel_targeting()
	targeting.clear()
	render.set_selected(nil)
end

local function confirm_targeting()
	local cid, targs, kind = targeting.card_id, targeting.targets, targeting.kind
	-- Capture hit locations now: resolving the play may move things around.
	local hits = {}
	if kind == "card" then
		for _, tid in ipairs(targs) do
			local t = entity.get(tid)
			if t and t.place and t.place.w > 0 then
				hits[#hits + 1] = { x = t.place.x + t.place.w * 0.5, y = t.place.y + t.place.h * 0.5 }
			end
		end
	end
	cancel_targeting()
	if flow.play_card(cid, targs) then
		for _, h in ipairs(hits) do fx.hit(h.x, h.y) end
	end
end

-- Open the detail view for whatever is at x,y (card, or a browsable zone).
local function inspect_at(x, y)
	local cid = card_at(x, y)
	if cid then
		render.set_detail(cid)
		return true
	end
	local zid = zones.zone_at(x, y)
	local z   = zid and entity.get(zid)
	if z and #z.cards > 0 and not z.tags.no_peek
		and (z.zone_type ~= "deck" or z.tags.face_up) then
		render.set_detail(zid)
		return true
	end
	return false
end

-- The primary (left-click / tap) action. Runs on release, so a long press
-- can turn into an inspect instead of a play.
local function primary_action(x, y)
	if render.get_detail() then
		render.set_detail(nil)
		return
	end

	local btn = render.hit_button(x, y)
	if btn == "undo" then
		flow.undo()
		return
	elseif btn == "confirm" then
		if targeting.active() and targeting.can_confirm() then confirm_targeting() end
		return
	elseif btn == "cancel" then
		if targeting.active() then cancel_targeting() end
		return
	end

	local cur = phase.current()
	if not cur then return end

	-- Overlay: clicking an offered card picks it; nothing else reacts.
	if cur.type == "overlay" then
		local cid = card_at(x, y)
		if cid then flow.pick(cid) end
		return
	end

	if cur.type ~= "player_input" and cur.type ~= "draw_and_play" then return end

	-- During targeting: add eligible targets; click source card to cancel.
	if targeting.active() then
		local clicked = card_at(x, y) or slot_at(x, y)
		if clicked == targeting.card_id then
			cancel_targeting()
		elseif clicked and targeting.add(clicked) and targeting.is_full() then
			confirm_targeting()
		end
		return
	end

	local cid = card_at(x, y)
	if cid then
		local c   = entity.get(cid)
		local def = cards.def(c)
		local z   = entity.get(c.zone_id)

		if z and z.zone_type == "grid" then
			flow.activate(cid)
			return
		end

		if not flow.can_play(cid) then return end

		local spec = def.target
		if spec and (spec.count or spec.max or 0) > 0 then
			render.set_selected(cid)
			targeting.start(cid, spec)
			if #targeting.eligible == 0 then
				if targeting.can_confirm() then confirm_targeting() else cancel_targeting() end
			end
		else
			flow.play_card(cid, {})
		end
		return
	end

	local zid = zones.zone_at(x, y)
	if zid then flow.zone_click(zid) end
end

function love.load()
	math.randomseed(os.time())
	love.graphics.setDefaultFilter("linear", "linear")
	render.rescale()
	flow.on_reset = function()
		anim.clear()
		fx.clear()
		render.set_selected(nil)
		render.set_detail(nil)
	end
	-- Stat changes float up from where they happened (card, or the HUD row).
	actions.on_stat_change = function(e, key, delta)
		local txt = (delta > 0 and "+" or "") .. delta .. " " .. key
		local col = delta > 0 and { 0.45, 0.95, 0.50 } or { 1.00, 0.45, 0.35 }
		if e.kind == "card" and e.place and e.place.w > 0 then
			fx.float(e.place.x + e.place.w * 0.5, e.place.y, txt, col)
		else
			local x, y = render.stat_pos(key)
			fx.float(x, y, txt, col)
		end
	end
	if os.getenv("RAVEL_DEBUG") then debugserver.start() end
	flow.default_seed = tonumber(os.getenv("RAVEL_SEED") or "")
	flow.init("menu.json")
end

function love.resize()
	zones.resize()
	render.rescale()
end

function love.keypressed(key)
	if key == "escape" then
		if render.get_detail() then
			render.set_detail(nil)
		elseif targeting.active() then
			cancel_targeting()
		end
	elseif key == "return" then
		if targeting.active() and targeting.can_confirm() then confirm_targeting() end
	elseif key == "z" then
		if not targeting.active() then flow.undo() end
	elseif key == "l" then
		render.toggle_log()
	end
end

-- Left input is release-based so a long press (touch-friendly) inspects
-- instead of playing. Right-click keeps its immediate desktop shortcuts.
local press      = nil
local LONG_PRESS = 0.45

function love.mousepressed(x, y, button)
	if button == 2 then
		if render.get_detail() then
			render.set_detail(nil)
		elseif targeting.active() then
			if targeting.can_confirm() then confirm_targeting() else cancel_targeting() end
		else
			inspect_at(x, y)
		end
		return
	end
	if button == 1 then
		press = { x = x, y = y, at = love.timer.getTime(), long = false }
	end
end

function love.mousereleased(x, y, button)
	if button ~= 1 or not press then return end
	local was_long = press.long
	press = nil
	if not was_long then primary_action(x, y) end
end

-- Template hot-reload: poll the current game file's modtime and re-read
-- templates when it changes on disk. Inert under love.js (files live in a
-- static zip) and on LÖVE versions without getInfo.
local watch_poll, watched, watched_mtime = 0, nil, nil

local function watch_game_file(dt)
	if not love.filesystem.getInfo then return end
	watch_poll = watch_poll + dt
	if watch_poll < 0.5 then return end
	watch_poll = 0
	local path  = "games/" .. declaration.filename
	local info  = love.filesystem.getInfo(path)
	local mtime = info and info.modtime
	if path == watched and mtime and watched_mtime and mtime ~= watched_mtime then
		if cards.reload() then
			for _, p in ipairs(validate.check(declaration.G)) do
				print("validate: " .. p)
				log.add("! " .. p)
			end
		end
	end
	watched, watched_mtime = path, mtime
end

function love.update(dt)
	anim.update(dt)
	fx.update(dt)
	render.sync_places()
	render.set_can_undo(flow.can_undo())
	watch_game_file(dt)

	-- A held press becomes an inspect; the release is then consumed.
	if press and not press.long
		and love.timer.getTime() - press.at > LONG_PRESS
		and not targeting.active() and not render.get_detail() then
		press.long = true
		inspect_at(press.x, press.y)
	end

	local hover = nil
	if not render.get_detail() then
		local mx, my = love.mouse.getPosition()
		local cid = card_at(mx, my)
		local c   = cid and entity.get(cid)
		local z   = c and entity.get(c.zone_id)
		if z and not z.tags.no_peek then hover = cid end
	end
	tooltip.update(dt, hover)

	debugserver.update()
end

function love.draw()
	render.draw()
	tooltip.draw()
end
