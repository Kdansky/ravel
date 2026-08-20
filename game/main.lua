local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local targeting   = require("targeting")
local actions     = require("actions")
local flow        = require("flow")
local rng         = require("rng")
-- Required before RESOLVE below captures flow.play_card: net wraps flow's
-- mutators at require time so a networked seat cannot move out of turn, and a
-- wrapper installed after the capture would never be reached from the GUI. It
-- is inert until a transport is linked.
local net         = require("net")
local netpanel    = require("netpanel")
-- Beside net and for the same reason: requiring it is what makes save_game and
-- load_save do anything, and nothing in the engine requires it back. Nothing
-- here calls into it, so nothing here holds it.
require("save")
local render      = require("render")
local tooltip     = require("tooltip")
local inspect     = require("inspect")
local anim        = require("anim")
local fx          = require("fx")
local debugserver = require("debugserver")
local validate    = require("validate")
local log         = require("log")

-- The offer that is open, if one is: the only hidden zone a click may reach.
-- Mirrors what render draws for an overlay phase, and per_seat resolves to the
-- seat being asked, so the other player's copy stays untouchable.
local function open_offer()
	local cur = phase.is_overlay() and phase.current()
	return cur and zones.find_id(cur.zone or "hand") or nil
end

-- Both live in zones, beside zone_at, because the three have to agree about
-- what is reachable and disagreeing is invisible until a click vanishes.
local function slot_at(x, y) return zones.slot_at(x, y, open_offer()) end
local function card_at(x, y) return zones.card_at(x, y, open_offer()) end

-- What ctrl+hover is pointing at, or nil. Held here rather than in inspect.lua
-- because finding it is this module's job (it owns the hit tests) and drawing
-- it is that one's.
local inspecting = nil

local function ctrl_down()
	return love.keyboard ~= nil and love.keyboard.isDown ~= nil
		and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl"))
end

-- Which ability the open targeting session is for, when the player picked one
-- out of a chooser. Kept here rather than in targeting because it is a fact
-- about the question being asked, not about the answers.
local aiming_at = nil

-- What confirming a targeting session does, by intent. flow.activate returns
-- false on refusal, so this cannot be an and/or chain.
local RESOLVE = {
	play     = function(cid, targs) return flow.play_card(cid, targs) end,
	activate = function(cid, targs) return flow.activate(cid, targs, aiming_at) end,
}

-- Give up on targeting without offering anything back. The plain version of
-- changing your mind, and the only version when there was never a choice.
local function abandon_targeting()
	targeting.clear()
	render.set_selected(nil)
	aiming_at = nil
end

-- Cancelling a choice that came out of a chooser puts the chooser back: the
-- player asked "what can this do", picked one, and changed their mind — landing
-- them on an empty board having spent nothing would be a dead end they did not
-- ask for.
--
-- Only where a chooser is what they would go back *to*. Reopening is asked of
-- the card rather than assumed from having been aiming: a card with one ability
-- was reaching for a chooser that declines to open, and — worse — an ability
-- with nothing to aim at cancels itself the instant it starts, so reopening put
-- the same dead entry in front of the player who had just picked it. Picking it
-- again did the same thing, for as long as they were willing to.
local function cancel_targeting()
	local reopen = aiming_at and targeting.card_id or nil
	abandon_targeting()
	if reopen and #flow.usable_abilities(reopen) > 1 then flow.offer_abilities(reopen) end
end

local function confirm_targeting()
	local cid, targs, kind = targeting.card_id, targeting.targets, targeting.kind
	local resolve = RESOLVE[targeting.intent] or flow.play_card
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
	targeting.clear()
	render.set_selected(nil)
	if resolve(cid, targs) then
		for _, h in ipairs(hits) do fx.hit(h.x, h.y) end
	end
	aiming_at = nil
end

-- Start targeting for a card's spec, or act at once when the spec asks for
-- nothing (or nothing is eligible and none is required). Shared by playing
-- from hand and activating an ability on the board.
local function begin_action(cid, spec, intent, ability_index)
	aiming_at = ability_index
	if select(2, targeting.bounds(spec)) > 0 then
		render.set_selected(cid)
		targeting.start(cid, spec, intent)
		if #targeting.eligible == 0 then
			-- Nothing to aim at is not the player changing their mind, so it does
			-- not reopen anything: it puts the board back and lets them pick
			-- something that can actually happen.
			if targeting.can_confirm() then confirm_targeting() else abandon_targeting() end
		end
	else
		RESOLVE[intent](cid, {})
	end
end

-- Open the detail view for whatever is at x,y (card, or a browsable zone).
local function inspect_at(x, y)
	local cid = card_at(x, y)
	if cid then
		-- Reading a card is looking at it, and the rule is the one that decides
		-- whether it is drawn face up: an opponent's hand shows backs, and must
		-- not become readable by right-clicking it.
		if not zones.visible(entity.get(cid)) then return false end
		render.set_detail(cid)
		return true
	end
	local zid = zones.zone_at(x, y)
	local z   = zid and entity.get(zid)
	-- A deck is browsable too: what is *in* it is public in most games — you
	-- know what the market holds — and what must stay secret is already marked
	-- "hidden", which nothing can click anyway. The order is the secret, and
	-- the browser is what keeps it (see draw_zone_browse).
	if z and #z.cards > 0 and zones.peekable(z) then
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

	-- Overlay: clicking an offered card plays it, which is what choosing is.
	-- Nothing else on screen reacts while one is open.
	if cur.type == "overlay" then
		local cid = card_at(x, y)
		if not cid then return end
		-- A menu entry is not a card being played: it is the card that asked,
		-- acting. So the offer closes and the *source* takes over, which is what
		-- keeps "@self" meaning the same thing whether or not anything was
		-- chosen in between.
		local pick = flow.menu_choice(cid)
		if pick then
			flow.close_offer()
			begin_action(pick.source, pick.ability.target, "activate", pick.index)
		else
			flow.play_card(cid, {})
		end
		return
	end

	if cur.type ~= "player_input" and cur.type ~= "draw_and_play" then return end

	-- During targeting: add eligible targets; click source card to cancel.
	if targeting.active() then
		local clicked = card_at(x, y) or slot_at(x, y)
		-- Pointing at a place, not a thing: the card lying in the zone is not
		-- what "discard it" means, so a zone-typed spec reads the zone under the
		-- cursor. Cards still answer first, so clicking the source cancels.
		if targeting.kind == "zone" and clicked ~= targeting.card_id then
			clicked = zones.zone_at(x, y) or clicked
		end
		-- The mirror of that, and the reason a capture is clickable: pointing at
		-- a piece means pointing at its square when the spec wants a square.
		clicked = targeting.aim(clicked)
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

		-- A zone tagged "activate" is where abilities are used; anywhere else,
		-- clicking a card plays it. The zone says which, so a board, a discard
		-- you may take from and a hand need no special cases here.
		if z and z.tags.activate then
			local sole = flow.sole_ability(cid)
			if sole then
				begin_action(cid, sole.ability.target, "activate", sole.index)
			else
				-- More than one thing this card can do, so the card stops being
				-- the question and the chooser becomes it.
				flow.offer_abilities(cid)
			end
			return
		end

		if not flow.can_play(cid) then return end
		begin_action(cid, def.target, "play")
		return
	end

	local zid = zones.zone_at(x, y)
	if zid then flow.activate_zone(zid) end
end

function love.load()
	math.randomseed(os.time())        -- fx.lua's particle jitter
	rng.seed(os.time())               -- and the game's own, once per process
	love.graphics.setDefaultFilter("linear", "linear")
	render.rescale()
	flow.on_reset = function()
		anim.clear()
		fx.clear()
		render.set_selected(nil)
		render.set_detail(nil)
	end
	-- How far into a run of cards acting we are, so a whole zone resolving at
	-- once still reads left to right. Zero outside a run, which is every
	-- ordinary click.
	local beat = 0
	actions.on_act = function(_, ordinal) beat = ordinal or 0 end

	-- Stat changes float up from where they happened (card, or the HUD row).
	-- A card losing health also takes a small damage burst, and whoever did it
	-- leans into them — a number changing across the board says nothing about
	-- where it came from, and that is most of what there is to follow.
	actions.on_stat_change = function(e, key, delta, ctx)
		local txt   = (delta > 0 and "+" or "") .. delta .. " " .. key
		local col   = delta > 0 and { 0.45, 0.95, 0.50 } or { 1.00, 0.45, 0.35 }
		local delay = math.max(0, beat - 1) * 0.16
		if e.kind == "card" and e.place and e.place.w > 0 then
			-- Read the rect now: by the time a delayed burst plays, the rules
			-- have long finished and the card may have been sent home.
			local cx, cy = e.place.x + e.place.w * 0.5, e.place.y + e.place.h * 0.5
			local top    = e.place.y
			fx.after(delay, function()
				fx.float(cx, top, txt, col)
				-- Any number going down on a card takes a knock. Which stats
				-- *hurt* is the game's business and naming them here was the
				-- engine learning one game's word for health.
				if delta < 0 then
					fx.play({ base = "damage", size = 0.7 }, cx, cy)
				end
			end)
			local actor = ctx and ctx.card_id and entity.get(ctx.card_id)
			if actor and actor.id ~= e.id and actor.place and actor.place.w > 0 then
				local ax, ay = actor.place.x + actor.place.w * 0.5, actor.place.y + actor.place.h * 0.5
				anim.bump(actor.id, cx - ax, cy - ay)
			end
		else
			local x, y = render.stat_pos(key)
			fx.after(delay, function() fx.float(x, y, txt, col) end)
		end
	end

	-- Named card effects land on the acting card (or mid-screen without one).
	actions.on_effect = function(name, ctx)
		local def = declaration.G.effect_defs[name]
		if not def then return end
		local e = ctx and ctx.card_id and entity.get(ctx.card_id)
		if e and e.place and e.place.w > 0 then
			fx.play(def, e.place.x + e.place.w * 0.5, e.place.y + e.place.h * 0.5)
		else
			fx.play(def, love.graphics.getWidth() * 0.5, love.graphics.getHeight() * 0.5)
		end
	end
	if os.getenv("RAVEL_DEBUG") then debugserver.start() end
	flow.default_seed = tonumber(os.getenv("RAVEL_SEED") or "")
	flow.init("menu.json")
	-- Only the browser build has a page to draw controls on; everywhere else
	-- this returns false and networking stays available through the module.
	netpanel.setup()
end

function love.resize()
	zones.resize()
	render.rescale()
end

function love.keypressed(key)
	-- Ctrl+C on what ctrl+hover is showing: a dump is only half useful if it
	-- cannot leave the window and go into the game file.
	if key == "c" and inspecting and ctrl_down() then
		local text = inspect.text(inspecting)
		if text and love.system and love.system.setClipboardText then
			pcall(love.system.setClipboardText, text)
			log.add("copied JSON of #" .. inspecting)
		end
		return
	end
	if key == "escape" then
		if render.get_detail() then
			render.set_detail(nil)
		elseif flow.dismiss_offer() then     -- same as a right-click
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
	-- Reading a card must not risk playing it: while ctrl is held the pointer
	-- is a magnifying glass and nothing else.
	if ctrl_down() then return end
	if button == 2 then
		if render.get_detail() then
			render.set_detail(nil)
		-- A chooser is a question, and a question you were not obliged to ask
		-- can be taken back. One the rules opened stays put and this falls
		-- through, so the cards in it can still be inspected.
		elseif flow.dismiss_offer() then     -- nothing else: the offer is gone
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

-- Only the *direction* of a wheel event is portable. Natively one notch is a
-- small integer; under love.js it is the browser's pixel delta, so multiplying
-- by it scrolled the inspector eighty rows a click and the middle of a dump
-- could not be reached at all.
function love.wheelmoved(_, dy)
	if inspecting and dy ~= 0 then inspect.scroll_by(dy > 0 and -6 or 6) end
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

-- Networking is polled, not pushed, and every poll is a round trip into the
-- page. Sixty a second is sixty JavaScript compiles a second for a turn-based
-- game that cannot tell 100ms from 16ms — this was most of the browser build's
-- idle CPU.
local NET_HZ, net_clock = 10, 0

function love.update(dt)
	-- Before sync_places: an applied remote state arrives with blank rects, and
	-- the renderer is what fills them in.
	net_clock = net_clock + dt
	if net_clock >= 1 / NET_HZ then
		net_clock = 0
		net.update()
		netpanel.update()
	end
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
	inspecting = nil
	if not render.get_detail() then
		local mx, my = love.mouse.getPosition()
		if ctrl_down() then
			-- Anything under the cursor, cards first, then the square they stand
			-- on, then the zone they lie in — the same order the click does. A
			-- card nobody may look at is skipped: the inspector prints its key,
			-- which is the whole of what a hidden hand is hiding.
			local under = card_at(mx, my)
			if under and not zones.visible(entity.get(under)) then under = nil end
			inspecting = under or slot_at(mx, my) or zones.zone_at(mx, my)
		end
		local cid = card_at(mx, my)
		local c   = cid and entity.get(cid)
		local z   = c and entity.get(c.zone_id)
		if z and not z.tags.no_peek then
			hover = cid
		else
			-- No card under the cursor, so ask the zone. A deck has no clickable
			-- cards — it is a box — and until now it answered nothing at all,
			-- which made the one thing you can do with it undiscoverable.
			local zid = zones.zone_at(mx, my)
			local zz  = zid and entity.get(zid)
			if zz and not zz.tags.no_peek and (zz.tooltip or zz.on_activate) then hover = zid end
		end
	end
	tooltip.update(dt, not inspecting and hover or nil)

	debugserver.update()
end

function love.draw()
	render.draw()
	if inspecting then inspect.draw(inspecting) else tooltip.draw() end
end

-- LÖVE's stock main loop with one addition: a frame cap. Nothing else caps
-- this. Desktop vsync depends on the driver and the compositor honouring it and
-- plenty do not; in the browser requestAnimationFrame follows the display, so a
-- 120 Hz monitor gets 120 frames of a turn-based card game that has no use for
-- more than 60. Either way the machine spends a core drawing frames nobody
-- asked for.
--
-- Events are pumped on every tick regardless, so input never waits on the cap.
-- Only update and draw are skipped, and the two platforms skip differently:
-- desktop hands the time back to the OS, while the browser simply returns,
-- because love.timer.sleep there blocks the page's only thread rather than
-- yielding it — the cure would be worse than the disease.
local FRAME = 1 / 60

function love.run()
	if love.load then love.load(arg) end
	if love.timer then love.timer.step() end

	local sleepable = not (love.system and love.system.getOS
		and love.system.getOS() == "Web")
	local next_frame = 0

	return function()
		if love.event then
			love.event.pump()
			for name, a, b, c, d, e, f in love.event.poll() do
				if name == "quit" and not (love.quit and love.quit()) then
					return a or 0
				end
				love.handlers[name](a, b, c, d, e, f)
			end
		end

		local now = love.timer and love.timer.getTime() or 0
		if now < next_frame then
			if sleepable then love.timer.sleep(math.min(next_frame - now, FRAME)) end
			return
		end
		-- Clamped to now, so a stall (a dragged window, a background tab) does
		-- not leave a debt of frames to be caught up on all at once.
		next_frame = math.max(next_frame + FRAME, now)

		local dt = love.timer and love.timer.step() or 0
		if love.update then love.update(dt) end

		if love.graphics and love.graphics.isActive() then
			love.graphics.origin()
			love.graphics.clear(love.graphics.getBackgroundColor())
			love.draw()
			love.graphics.present()
		end
	end
end
