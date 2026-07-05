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
		if fname then M.init(fname); return end

		-- Outcomes wait until any open overlay (a pending choice) is closed.
		if phase.is_overlay() or not fire_end_condition() then
			local cur = phase.current()
			if cur and cur.type == "automatic" then
				if phase.take_fresh() then
					actions.run(cur.actions, {})
				end
				-- The actions may have pushed an overlay (a revealed page):
				-- advance only once this phase is back on top.
				if not actions.pending_load and phase.current() == cur then
					phase.next()
				end
			elseif phase.take_wrapped() then
				-- A round completed: advance the counter, ready exhausted
				-- cards, then let board cards produce.
				local pl = player()
				if pl then
					pl.stats.round = (pl.stats.round or 1) + 1
					log.add("— Round " .. pl.stats.round .. " —")
				end
				for e in entity.each("card") do e.exhausted = nil end
				run_on_turn()
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
	for k, v in pairs(G.setup.player or {}) do pl.stats[k] = v end
	entity.register(pl)

	-- Cards that start in play (e.g. the throne room), placed onto their zone/slot.
	for _, def in pairs(G.card_defs) do
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

local function pay(cost)
	for stat, n in pairs(cost or {}) do
		actions.execute("spend_stat:" .. stat .. ":" .. n, {})
	end
end

-- A card is playable when its cost is affordable and its needs are met.
-- Escape hatch: a needs-gated card becomes playable when nothing else in its
-- zone is, so a mandatory play can never soft-lock a hand.
function M.can_play(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not cards.can_afford(def.cost) then return false end
	if predicate.meets_all(def.needs) then return true end
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
	checkpoint()
	log.add("Played " .. (def.text or c.def_key))
	local pl = player()
	if pl then pl.stats.plays = (pl.stats.plays or 0) + 1 end
	pay(def.cost)
	local before = phase.current()
	actions.run(def.on_play, { card_id = card_id, targets = targets or {} })
	if def.irreversible then
		history = {}
		log.add("— no turning back —")
	end

	local cur = phase.current()
	if not actions.pending_load and cur == before and cur and cur.type == "draw_and_play" then
		local hand  = zones.find(cur.zone or "hand")
		local grave = zones.find_id("graveyard")
		if hand and grave then
			-- Unplayed cards are discarded; tokens (pass cards) just vanish.
			local n = 0
			while #hand.cards > 0 do
				local cid  = hand.cards[#hand.cards]
				local cdef = cards.def(entity.get(cid))
				if cdef and cdef.tags_set and cdef.tags_set.token then
					zones.destroy_card(cid)
				else
					zones.move_top(hand.id, grave)
					n = n + 1
				end
			end
			if n > 0 then log.add("Discarded " .. n .. " unplayed") end
		end
		phase.next()
	end
	M.settle()
	return true
end

-- Activate a board card's ability. Activation exhausts the card until the
-- round wraps and readies it again.
function M.activate(card_id)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not def.on_activate or c.exhausted
		or not cards.can_afford(def.activate_cost) then
		return false
	end
	checkpoint()
	log.add("Activated " .. (def.text or c.def_key))
	pay(def.activate_cost)
	c.exhausted = true
	actions.run(def.on_activate, { card_id = card_id, targets = {} })
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

function M.zone_click(zone_id)
	local z = entity.get(zone_id)
	if not z or #z.on_click == 0 then return false end
	checkpoint()
	actions.run(z.on_click, { zone_id = zone_id })
	M.settle()
	return true
end

return M
