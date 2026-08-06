-- Game flow: every state change that follows from player intent lives here.
-- No love.* dependency except through zones.resize, so the whole game logic
-- runs headless (tests, debug server). Input and rendering live in main.lua.

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local targeting   = require("targeting")
local predicate   = require("predicate")
local tags        = require("tags")
local validate    = require("validate")
local log         = require("log")

local M = {}

M.on_reset      = nil   -- hook for main.lua to clear visual state (anim, selection)
M.default_seed  = nil   -- applied to every game load (CLI arg / RAVEL_SEED env)

local history     = {}
local MAX_HISTORY = 50

local function player()
	for e in entity.each("player") do return e end
end

local function fired_flags()
	local f = {}
	for i, cond in ipairs(declaration.G.end_conditions) do f[i] = cond.fired end
	return f
end

local function checkpoint()
	history[#history + 1] = {
		ents     = entity.snapshot(),
		phases   = phase.snapshot(),
		fired    = fired_flags(),
		log_mark = log.count(),
	}
	if #history > MAX_HISTORY then table.remove(history, 1) end
end

function M.can_undo()
	return #history > 0
end

function M.undo()
	local h = table.remove(history)
	if not h then return false end
	entity.restore(h.ents)
	phase.restore(h.phases)
	for i, cond in ipairs(declaration.G.end_conditions) do cond.fired = h.fired[i] end
	log.truncate(h.log_mark)
	targeting.clear()
	if M.on_reset then M.on_reset() end
	return true
end

-- The first matching condition fires; all are then marked fired so a game has
-- exactly one outcome. Undo restores the flags.
local function fire_end_condition()
	local conds = declaration.G.end_conditions
	for _, cond in ipairs(conds) do
		if not cond.fired and predicate.met(cond) then
			for _, c in ipairs(conds) do c.fired = true end
			actions.run(cond["then"], {})
			return true
		end
	end
	return false
end

-- Deal from the phase's deck into its zone (hand by default). Drawn cards are
-- pre-stamped with the deck's rect so the renderer flies them to their spot.
-- A phase with a pass_card also gets that card added to the hand: forced-play
-- phases must always have a playable out.
local function deal(ph)
	local to = zones.find(ph.zone or "hand")
	if ph.deck and to then
		local from  = zones.find(ph.deck)
		local drawn = 0
		if from then
			for _ = 1, ph.draw or 1 do
				if #from.cards == 0 then break end
				local top = entity.get(from.cards[#from.cards])
				if from.place.w > 0 then
					top.place = { x = from.place.x, y = from.place.y, w = from.place.w, h = from.place.h }
				end
				zones.move_top(from.id, to.id)
				drawn = drawn + 1
			end
			if drawn > 0 and from.label then
				log.add("Drew " .. drawn .. " — " .. from.label)
			end
		end
	end
	if ph.pass_card and to then
		-- Stale tokens from a previous phase never accumulate: sweep them
		-- before dealing this phase's fresh pass/router cards.
		for i = #to.cards, 1, -1 do
			local cdef = cards.def(entity.get(to.cards[i]))
			if cdef and cdef.tags_set and cdef.tags_set.token then
				zones.destroy_card(to.cards[i])
			end
		end
		local pcs = type(ph.pass_card) == "table" and ph.pass_card or { ph.pass_card }
		for _, key in ipairs(pcs) do
			cards.create(key, to.id)
		end
	end
end

-- Discard a phase's remaining hand: unplayed cards go to the graveyard when
-- one exists (destroyed otherwise); tokens always just vanish. Fired by the
-- phase.on_leave hook for phases marked discard_hand.
local function discard_hand(ph)
	local hand = zones.find(ph.zone or "hand")
	if not hand then return end
	local grave = zones.find_id("graveyard")
	local n = 0
	while #hand.cards > 0 do
		local cid  = hand.cards[#hand.cards]
		local cdef = cards.def(entity.get(cid))
		if cdef and cdef.tags_set and cdef.tags_set.token then
			zones.destroy_card(cid)
		else
			if grave then zones.move_top(hand.id, grave) else zones.destroy_card(cid) end
			n = n + 1
		end
	end
	if n > 0 then log.add("Discarded " .. n .. " unplayed") end
end

phase.on_leave = function(pd)
	if pd.discard_hand then discard_hand(pd) end
end

-- A full round completed: each card on a grid zone runs its on_turn actions.
-- Cards at 0 hp are ruined and don't act.
local function run_on_turn()
	for e in entity.each("card") do
		local def = cards.def(e)
		local z   = entity.get(e.zone_id)
		if def.on_turn and z and z.zone_type == "grid" and (e.stats.hp or 1) > 0 then
			actions.run(def.on_turn, { card_id = e.id, targets = {} })
		end
	end
end

-- Drive the game to a stable point: consume a queued load, fire end conditions,
-- run automatic phases, run on_turn triggers after a full round, deal freshly
-- entered phases. Loops because each step can trigger the next. The budget
-- catches routing cycles: content errors warn and halt, never hang.
function M.settle()
	local budget = 64
	while true do
		budget = budget - 1
		if budget < 0 then
			log.add("!! phase loop halted after 64 transitions")
			print("settle: transition budget exhausted — check phase routing")
			return
		end

		local fname = actions.take_load()
		if fname then
			-- fname is untrusted content (routed here from the load_game
			-- action). M.init wipes all state before it even reads the
			-- file, so a failure partway through (missing file, bad JSON,
			-- any malformed field an individual handler didn't already
			-- guard against) must not crash the process or strand the
			-- player in a half-wiped state — fall back to the menu, which
			-- ships with the engine and is always valid.
			local ok, err = pcall(M.init, fname)
			if not ok then
				print("load_game failed for '" .. tostring(fname) .. "': " .. tostring(err))
				if fname ~= "menu.json" then pcall(M.init, "menu.json") end
			end
			return
		end

		-- Outcomes wait until any open overlay (a pending choice) is closed.
		if phase.is_overlay() or not fire_end_condition() then
			local cur = phase.current()
			if phase.take_wrapped() then
				-- A round completed: advance the counter, ready exhausted
				-- cards, then let board cards produce — all before the new
				-- round's phases run or deal anything (a threat dealt at
				-- dawn must not drain the day it arrives).
				local pl = player()
				if pl then
					pl.stats.round = (pl.stats.round or 1) + 1
					log.add("— Round " .. pl.stats.round .. " —")
				end
				for e in entity.each("card") do e.exhausted = nil end
				run_on_turn()
			elseif cur and cur.type == "automatic" then
				if phase.take_fresh() then
					actions.run(cur.actions, {})
				end
				-- The actions may have pushed an overlay (a revealed page):
				-- advance only once this phase is back on top.
				if not actions.pending_load and phase.current() == cur then
					phase.next()
				end
			elseif cur and phase.take_fresh() then
				-- Fresh entry starts a new hand: the per-phase play counter
				-- resets here (and only here — resuming after a pop doesn't).
				local pl = player()
				if pl then pl.stats.plays = 0 end
				deal(cur)
			else
				return
			end
		end
	end
end

function M.init(filename, seed)
	entity.reset()
	zones.reset()
	cards.reset()
	targeting.clear()
	actions.take_load()
	history = {}
	log.clear()
	if M.on_reset then M.on_reset() end

	local G = declaration.load(filename)

	-- Seed precedence: explicit argument > CLI/env default > the game doc.
	-- Seeded before zone contents are created, so shuffles are reproducible.
	local s = seed or M.default_seed or G.seed
	if s then math.randomseed(s) end

	for _, key in ipairs(G.zone_list) do zones.create(G.zone_defs[key]) end

	for _, problem in ipairs(validate.check(G)) do
		print("validate " .. filename .. ": " .. problem)
		log.add("! " .. problem)
	end

	local pl = { kind = "player", stats = { round = 1, plays = 0 } }
	-- setup.player is untrusted content: coerce to numbers so later stat
	-- arithmetic can never be handed a string/table and crash.
	for k, v in pairs(G.setup.player or {}) do pl.stats[k] = tonumber(v) or 0 end
	entity.register(pl)

	-- Cards that start in play (e.g. the throne room), placed onto their zone/slot.
	-- Walked in file order, never with pairs: entity IDs are handed out in
	-- creation order, and Lua's hash order is not stable across interpreters
	-- (or, in 5.4, across processes). Setup has to build the same board every
	-- time for seeds to reproduce and for replays to line up.
	for _, key in ipairs(G.card_list) do
		local def = G.card_defs[key]
		if def.auto_play then
			local to = zones.find(def.to_zone or cards.home_zone(def) or "board")
			if to then
				local e = cards.create(def.key, to.id)
				local slot_id = def.to_slot and to.slots[def.to_slot]
				if slot_id then zones.place_in_slot(e.id, slot_id) else zones.auto_slot(e.id) end
				actions.run(def.on_play, { card_id = e.id, targets = {} })
			end
		end
	end

	phase.init(G)
	if G.phase_list[1] then phase.push(G.phase_list[1]) end
	zones.resize()
	M.settle()
end

-- Pay a cost: stats are spent through their subject (so a scope and
-- quantifier are honoured), "sacrifice:<tag>" entries destroy board cards
-- carrying the tag (oldest first — affordability was already checked).
-- Keys are walked in sorted order, never pairs: clamping makes payment order
-- observable, and a seeded replay has to pay identically.
local function pay(cost, ctx)
	local subjects = {}
	for k in pairs(cost or {}) do subjects[#subjects + 1] = k end
	table.sort(subjects)
	for _, stat in ipairs(subjects) do
		local n   = cost[stat]
		local tag = stat:match("^sacrifice:(.+)$")
		if tag then
			for _ = 1, n do
				local ids = tags.find_targets({ tag }, { grid = true })
				if #ids == 0 then break end
				local victim = entity.get(ids[1])
				local vdef   = cards.def(victim)
				log.add("Sacrificed " .. (vdef and vdef.text or victim.def_key))
				zones.destroy_card(victim.id)
			end
		else
			actions.spend(stat, tonumber(n) or 0, ctx)
		end
	end
end

-- A card is playable when its cost is affordable and its needs are met.
-- Escape hatch: a needs-gated card becomes playable when nothing else in its
-- zone is, so a mandatory play can never soft-lock a hand.
function M.can_play(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	local ctx = { card_id = card_id, targets = {} }
	if not def or not cards.can_afford(def.cost, ctx) then return false end
	if predicate.meets_all(def.needs, ctx) then return true end
	local z = entity.get(c.zone_id)
	for _, cid in ipairs(z and z.cards or {}) do
		if cid ~= card_id then
			local od = cards.def(entity.get(cid))
			if od and cards.can_afford(od.cost) and predicate.meets_all(od.needs) then
				return false
			end
		end
	end
	return true
end

-- Play a card: pay its cost and run on_play. In a draw_and_play phase, playing
-- one card ends the turn (discard hand, advance) — unless the play changed the
-- phase stack (pushed an overlay) or queued a game load.
function M.play_card(card_id, targets)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not M.can_play(card_id) then return false end
	-- Flow is the single legality gate: target counts are enforced here, not
	-- only in the input layers, so scripts and the debug API can't skip them.
	if def.target then
		local n = #(targets or {})
		if n < (def.target.min or def.target.count or 0)
			or n > (def.target.max or def.target.count or 0) then
			return false
		end
	end
	local ctx = { card_id = card_id, targets = targets or {} }
	-- A cost the targets pay could not be judged before they were chosen.
	if not cards.can_afford(def.cost, ctx) then return false end
	checkpoint()
	log.add("Played " .. (def.text or c.def_key))
	local pl = player()
	if pl then pl.stats.plays = (pl.stats.plays or 0) + 1 end
	pay(def.cost, ctx)
	local before = phase.current()
	actions.run(def.on_play, ctx)
	if def.irreversible then
		history = {}
		log.add("— no turning back —")
	end

	-- A phase with a play limit ends itself once it's reached (MTG-style:
	-- the phase's own rule, not the card's). Discarding is the on_leave
	-- hook's job, so card-driven next_phase gets the same treatment.
	local cur = phase.current()
	if not actions.pending_load and cur == before and cur and cur.ends_after
		and pl and (pl.stats.plays or 0) >= cur.ends_after then
		phase.next()
	end
	M.settle()
	return true
end

-- A board card offers its ability when it has one, is ready, and its
-- activation cost is affordable. Split out so the input layers can decide
-- whether to open targeting before committing to the activation.
function M.can_activate(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	return def ~= nil and def.on_activate ~= nil and not c.exhausted
		and cards.can_afford(def.activate_cost, { card_id = card_id, targets = {} })
end

-- Activate a board card's ability. Activation exhausts the card until the
-- round wraps and readies it again — unless the card declares
-- "exhausts": false, which is how a permanently available button (a "pass the
-- time" card) is expressed.
function M.activate(card_id, targets)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	if not M.can_activate(card_id) then return false end
	local c   = entity.get(card_id)
	local def = cards.def(c)
	-- Flow is the single legality gate, exactly as in play_card: target counts
	-- are enforced here, not only in the input layers, so scripts and the
	-- debug API can't skip them.
	if def.activate_target then
		local n = #(targets or {})
		if n < (def.activate_target.min or def.activate_target.count or 0)
			or n > (def.activate_target.max or def.activate_target.count or 0) then
			return false
		end
	end
	local ctx = { card_id = card_id, targets = targets or {} }
	if not cards.can_afford(def.activate_cost, ctx) then return false end
	checkpoint()
	log.add("Activated " .. (def.text or c.def_key))
	pay(def.activate_cost, ctx)
	if def.exhausts ~= false then c.exhausted = true end
	actions.run(def.on_activate, ctx)
	M.settle()
	return true
end

-- Pick a card from the active overlay's offer zone.
function M.pick(card_id)
	local cur = phase.current()
	if not cur or cur.type ~= "overlay" then return false end
	local offer_id = zones.find_id(cur.zone or "hand")
	local c = entity.get(card_id)
	if not c or c.zone_id ~= offer_id then return false end
	checkpoint()
	local def = cards.def(c)
	log.add("Chose " .. (def and def.text or c.def_key))
	if cur.page then
		-- Page overlays run the revealed card's own on_pick. Pop first so a
		-- chained reveal lands on top; the read page vanishes unless its
		-- actions moved it somewhere.
		phase.pop()
		actions.run(def and def.on_pick, { card_id = card_id, targets = {} })
		if entity.get(card_id).zone_id == offer_id then
			zones.destroy_card(card_id)
		end
	else
		actions.run(cur.on_pick, { card_id = card_id, targets = {} })
	end
	if def and def.irreversible then
		history = {}
		log.add("— no turning back —")
	end
	M.settle()
	return true
end

-- The outcome announced by the open ending screen: "victory" or "defeat"
-- from the offered card's def, nil while the game is still live. Purely
-- derived, so undo needs no extra state.
function M.outcome()
	local cur = phase.current()
	if not cur or cur.type ~= "overlay" then return nil end
	local z = zones.find(cur.zone or "hand")
	for _, cid in ipairs(z and z.cards or {}) do
		local def = cards.def(entity.get(cid))
		if def and def.outcome then return def.outcome end
	end
end

-- One entry per visible stat, for the end-of-run summary.
function M.summary()
	local G   = declaration.G
	local out = {}
	for _, key in ipairs(G.stat_defs_list or {}) do
		local def = G.stat_defs[key]
		if not (def and def.hidden) then
			out[#out + 1] = (def and def.label or key) .. " " .. entity.sum_stat(key)
		end
	end
	return out
end

function M.zone_click(zone_id)
	local z = entity.get(zone_id)
	if not z or #z.on_click == 0 then return false end
	checkpoint()
	actions.run(z.on_click, { zone_id = zone_id })
	M.settle()
	return true
end

return M
