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
local rng         = require("rng")
local predicate   = require("predicate")
local tags        = require("tags")
local validate    = require("validate")
local log         = require("log")

local M = {}

M.on_reset      = nil   -- hook for main.lua to clear visual state (anim, selection)
M.default_seed  = nil   -- applied to every game load (CLI arg / RAVEL_SEED env)

local history     = {}
local MAX_HISTORY = 50

-- The engine's own two cards. Seats are named by their player card's key, so
-- the acting seat's card is the one whose def_key the active seat names — a
-- game can promote its hero to be it (castle's throne room) instead of
-- carrying an invisible one. The system card is found by key too, because it
-- is never content.
local function player()
	local seat = zones.active_seat()
	for e in entity.each("card") do
		if e.def_key == seat and e.zone_id then return e end
	end
end

-- A card in another seat's zone is not yours to play, whatever an interface
-- lets you click. Cards in shared zones belong to nobody and stay reachable.
local function reachable(c)
	local z = c and c.zone_id and entity.get(c.zone_id)
	return not (z and z.seat) or z.seat == zones.active_seat()
end

-- You play out of the phase's own zone — but only where the phase says which
-- one. A phase that names no zone keeps the freedom every shipped game was
-- written against (the menu plays out of a zone called "menu", and has no hand
-- at all). A phase that declares one means it, which is what lets a draw step
-- be a draw step instead of a chance to empty your hand.
local function in_play_zone(c)
	local cur = phase.current()
	if not cur or not cur.zone then return true end
	local z = zones.find(cur.zone)
	return z ~= nil and c ~= nil and c.zone_id == z.id
end

-- A stack is reached from the top, and only from the top. Decks and piles draw
-- one card and hit-test one card, so the rules have to say the same thing or
-- the two disagree in both directions at once: Lost Cities offered its discard
-- marker as a legal target long after it was buried under a card no click
-- could see past, and a script or a network peer could name anything in the
-- pile. This is the rule the renderer has always followed.
local STACKED = { deck = true, pile = true }
local function on_top(c)
	local z = c and c.zone_id and entity.get(c.zone_id)
	if not z or not STACKED[z.zone_type] then return true end
	return z.cards[#z.cards] == c.id
end

-- When a card may be used at all. A card — or a tag its zone grants it —
-- names the phases it works in, which is how "cast only during your main
-- phase" is said, and how a discard pile can be pickable during the draw step
-- and inert for the rest of the turn. Naming none means any phase, which is
-- what every card ever written for this engine assumed.
--
-- Phase *keys*, not seat-qualified ones: both players share a phase, because a
-- rule that had to be written once per seat would be written twice and drift.
local function phase_ok(def_phases)
	if def_phases == nil then return true end
	local cur = phase.current()
	if not cur then return false end
	if type(def_phases) == "string" then return def_phases == cur.key end
	for _, key in ipairs(type(def_phases) == "table" and def_phases or {}) do
		if key == cur.key then return true end
	end
	return false
end

-- An ability with nothing in it is no ability, so an empty action list never
-- makes a card look usable and then do nothing when clicked.
local function has_ability(list)
	return type(list) == "table" and #list > 0
end

local function system_card()
	for e in entity.each("card") do
		if e.def_key == "system" and e.zone_id then return e end
	end
end

-- Handing over. The undo history goes with the seat that had it: undoing
-- across a handover would either show a player something they were never
-- meant to see, or rewrite a decision that was not theirs.
local function rotate_seat()
	local seats = declaration.G.seat_list or {}
	local sys   = system_card()
	if #seats < 2 or not sys then return end
	sys.stats.turn = (sys.stats.turn or 1) % #seats + 1
	history = {}
	local def = declaration.G.card_defs[seats[sys.stats.turn]]
	log.add("— " .. ((def and def.text) or seats[sys.stats.turn]) .. " to play —")
end

-- Which targets the rules allow, re-derived rather than trusted. Counts were
-- always enforced here; identity never was, so a script or the debug API could
-- name any card as a target of anything. targeting.eligible is what a player
-- was *offered* — this is what the rules permit, and now that a destination
-- can refuse a card ("accepts") the difference matters.
local function targets_legal(card_id, spec, targets)
	if #(targets or {}) == 0 then return true end
	local ok = {}
	for _, id in ipairs(targeting.candidates(card_id, spec or {})) do ok[id] = true end
	for _, id in ipairs(targets) do
		if not ok[id] then return false end
	end
	return true
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
		rng      = rng.state(),
	}
	if #history > MAX_HISTORY then table.remove(history, 1) end
end

function M.can_undo()
	return #history > 0
end

-- Drop the undo stack without touching state. Handing over already does this
-- (rotate_seat, above); net.lua needs it too, because a state that arrived
-- from another client makes every local checkpoint describe a game that
-- client never played.
function M.forget_history()
	history = {}
end

function M.undo()
	local h = table.remove(history)
	if not h then return false end
	entity.restore(h.ents)
	phase.restore(h.phases)
	rng.set_state(h.rng)
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
				local sys = system_card()
				if sys then
					sys.stats.round = (sys.stats.round or 1) + 1
					log.add("— Round " .. sys.stats.round .. " —")
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
				-- Fresh entry starts a new hand: the seat changes first, so the
				-- counter that resets and the hand that is dealt are the new
				-- player's. The per-phase play counter resets here and only
				-- here — resuming after a pop doesn't.
				if cur.seat == "next" then rotate_seat() end
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

	-- Seed precedence: explicit argument > CLI/env default > the game doc. With
	-- none of those the generator is left exactly where it is, so whatever the
	-- process seeded at startup still governs — a caller that wants a
	-- reproducible run seeds once and gets it, which is what tests/run.lua does
	-- and what reseeding from the clock here quietly took away. Seeded before
	-- zone contents are created, so shuffles reproduce. The generator is the
	-- engine's own (rng.lua): a seed has to mean the same sequence on every
	-- interpreter, or a replay, a golden trace and a networked opponent all
	-- disagree about the deck.
	local s = seed or M.default_seed or G.seed
	if s then rng.seed(s) end

	for _, key in ipairs(G.zone_list) do zones.create(G.zone_defs[key]) end

	for _, problem in ipairs(validate.check(G)) do
		print("validate " .. filename .. ": " .. problem)
		log.add("! " .. problem)
	end

	-- Cards that start in play (the player card, the system card, a throne
	-- room), placed onto their zone/slot.
	-- Walked in file order, never with pairs: entity IDs are handed out in
	-- creation order, and Lua's hash order is not stable across interpreters
	-- (or, in 5.4, across processes). Setup has to build the same board every
	-- time for seeds to reproduce and for replays to line up.
	for _, key in ipairs(G.card_list) do
		local def = G.card_defs[key]
		if def.auto_play then
			-- Into every instance of the zone, which is one for a shared zone
			-- and one per seat otherwise: a per-seat board wants its marker in
			-- each seat's copy, not a single one in whoever happens to be first.
			local zkey = def.to_zone or cards.home_zone(def) or "board"
			for _, to in ipairs(zones.all_with_key(zkey)) do
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

-- True if a cost table like { gold = 2 } can be paid. nil cost = free.
-- "sacrifice:<tag>" entries are paid in board cards instead of stats; every
-- other key is a subject, so it may carry a scope and quantifier
-- ({ "hp@each.follower": 1 } — each follower must have one to give).
-- Lives here rather than in cards because it reads the live entity graph and
-- every caller is a legality gate, and because payment is right below it.
function M.can_afford(cost, ctx)
	for subject, n in pairs(cost or {}) do
		local tag = type(subject) == "string" and subject:match("^sacrifice:(.+)$")
		if tag then
			if #tags.find_targets({ tag }, { grid = true }) < (tonumber(n) or 0) then
				return false
			end
		elseif not predicate.awaits_targets(subject, ctx)
			and not predicate.meets_all({ [subject] = n }, ctx) then
			return false
		end
	end
	return true
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

local function playable(def, ctx)
	return def ~= nil and M.can_afford(def.cost, ctx) and predicate.meets_all(def.needs, ctx)
end

-- A card is playable when its cost is affordable and its needs are met.
-- Escape hatch: a needs-gated card becomes playable when nothing else in its
-- zone is, so a mandatory play can never soft-lock a hand. The gates leave
-- ctx.targets unset: nothing has been chosen yet, and a cost the targets would
-- pay cannot be judged until they are.
function M.can_play(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not reachable(c) or not in_play_zone(c) or not on_top(c) then return false end
	if not phase_ok(cards.behaviour(c, "phases")) then return false end
	if not M.can_afford(def.cost, { card_id = card_id }) then return false end
	if predicate.meets_all(def.needs, { card_id = card_id }) then return true end
	local z = entity.get(c.zone_id)
	for _, cid in ipairs(z and z.cards or {}) do
		if cid ~= card_id and playable(cards.def(entity.get(cid)), { card_id = cid }) then
			return false
		end
	end
	return true
end

-- Play a card: pay its cost and run on_play. A phase with a play limit then
-- ends itself; discarding its hand is the on_leave hook's job.
function M.play_card(card_id, targets)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not M.can_play(card_id) then return false end
	-- Flow is the single legality gate: target counts are enforced here, not
	-- only in the input layers, so scripts and the debug API can't skip them.
	local lo, hi = targeting.bounds(def.target)
	if #(targets or {}) < lo or #(targets or {}) > hi then return false end
	if not targets_legal(card_id, def.target, targets) then return false end
	local ctx = { card_id = card_id, targets = targets or {} }
	-- A cost the targets pay could not be judged before they were chosen.
	if not M.can_afford(def.cost, ctx) then return false end
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
-- Note what this does *not* ask: in_play_zone. An ability is used where the
-- card lies, which is the whole point of a discard pile you can take from — the
-- pile is not the phase's zone and never will be. The phase restriction above
-- is what bounds it instead, which is why that rule had to exist before this
-- one could be safe.
function M.can_activate(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or c.exhausted or not reachable(c) or not on_top(c) then return false end
	-- Whether abilities work here is the zone's to say, not something to infer
	-- from its shape: a board and a Lost Cities discard both allow it, a hand
	-- and an MTG graveyard both do not, and neither pair shares a zone type.
	local z = entity.get(c.zone_id)
	if not (z and z.tags.activate) then return false end
	if not has_ability(cards.behaviour(c, "on_activate")) then return false end
	if not phase_ok(cards.behaviour(c, "phases")) then return false end
	return M.can_afford(def.activate_cost, { card_id = card_id })
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
	local lo, hi = targeting.bounds(def.activate_target)
	if #(targets or {}) < lo or #(targets or {}) > hi then return false end
	if not targets_legal(card_id, def.activate_target, targets) then return false end
	local ctx = { card_id = card_id, targets = targets or {} }
	if not M.can_afford(def.activate_cost, ctx) then return false end
	checkpoint()
	log.add("Activated " .. (def.text or c.def_key))
	pay(def.activate_cost, ctx)
	if cards.behaviour(c, "exhausts") ~= false then c.exhausted = true end
	actions.run(cards.behaviour(c, "on_activate"), ctx)
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
			out[#out + 1] = (def and def.label or key) .. " " .. predicate.total(def and def.subject or key)
		end
	end
	return out
end

-- A zone click is a player action, so a pending choice locks it exactly as it
-- locks playing and activating. Note that nothing else gates it: an on_click
-- fires in any phase, which is why "take the top of that pile" belongs on a
-- card in the phase's own zone (where in_play_zone already bounds it) rather
-- than on the pile. Lost Cities learned that the expensive way.
function M.zone_click(zone_id)
	if phase.is_overlay() then return false end
	local z = entity.get(zone_id)
	if not z or #z.on_click == 0 then return false end
	checkpoint()
	actions.run(z.on_click, { zone_id = zone_id })
	M.settle()
	return true
end

return M
