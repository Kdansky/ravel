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
local geometry    = require("geometry")

-- An entry that names no square still places one card, wherever there is room.
local NOWHERE     = { true }
local predicate   = require("predicate")
local reactions   = require("reactions")
local tags        = require("tags")
local validate    = require("validate")
local log         = require("log")
local stats       = require("stats")
local costs       = require("costs")
local stack       = require("stack")

local unpack = table.unpack or unpack

local M = {}

-- Asked by every interface, and answered by the planner.
M.can_afford    = costs.can_afford
M.play_payments = costs.play_payments
M.rule_payments = costs.rule_payments
M.payment_legal = costs.legal

-- And by the ones that answer, of the stack.
M.pending_event    = stack.pending_event
M.usable_reactions = stack.usable_reactions
M.can_react        = stack.can_react
M.sole_reaction    = stack.sole_reaction
M.react_step       = stack.react_step
M.release_priority = stack.release_priority
M.defer_play       = stack.defer_play
M.defer_activation = stack.defer_activation
M.emit             = stack.emit
M.copy_event       = stack.copy_event
M.redirect         = stack.redirect
M.counterspell     = stack.counterspell

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
-- A card you may act on: your piece, or nobody's. Asked of the card rather than
-- of the zone it lies in, because a board can be shared while the pieces on it
-- are not — otherwise white could move black's rook, both being "on the board".
local function reachable(c)
	-- A card lent to an offer is being looked at, not owned there. The offer was
	-- opened for whoever is up, and asking whose chip it is would make `show:`
	-- open a window nobody could reach through — an opponent's hand is never the
	-- reader's, which is the whole point of reading it.
	local z = c.zone_id and entity.get(c.zone_id)
	if z and z.status == "offer" then return true end
	local seat = predicate.owner_of(c)
	return seat == nil or seat == zones.active_seat()
end

-- You play out of the phase's own zone — but only where the phase says which
-- one. A phase that names no zone keeps the freedom every shipped game was
-- written against (the menu plays out of a zone called "menu", and has no hand
-- at all). A phase that declares one means it, which is what lets a draw step
-- be a draw step instead of a chance to empty your hand.
-- Choosing from an overlay is not buying. A card in an offer is being picked,
-- and what it costs, needs and targets describes playing it out of a hand later
-- — castle deals buildings into its draft, and paying to *choose* one would
-- charge the build price twice. So the gates below skip those three, and the
-- ones that remain (whose card it is, whether the phase's zone holds it) still
-- apply.
local function choosing(c)
	if not phase.is_overlay() then return false end
	local cur = phase.current()
	local z = zones.find(cur.zone or "hand")
	return z ~= nil and c ~= nil and c.zone_id == z.id
end

-- The same question, for anything outside this file that has to ask it. The bot
-- is the one caller: a card lying in an offer is being *chosen*, and a choice
-- takes no targets, so reaching for its target spec and dropping the move when
-- the pool is short is how a seat came to sit in front of a question it could
-- have answered.
function M.is_choosing(card_id)
	return choosing(entity.get(card_id))
end

-- Whether a card in an open offer may be the answer.
--
-- `show:` borrows the *real* cards a scope names, so the offer is somebody's
-- hand and not a list the engine wrote — and a rule about part of a hand ("a
-- gem", "a non-purple chip", "the largest one") has to say which part. The
-- asking card says it, as `chosen.where`, in the same condition vocabulary a
-- target's `where` already uses and asked the same way: the candidate is
-- @target, and the asker is @self.
--
-- Only borrowed cards are asked. An entry the offer *dealt* is a line the
-- engine wrote from the asker's own list, and narrowing a list you wrote is
-- writing a shorter list.
-- **An answer minted for the question may have a price, and it says so itself.**
-- "options:" writes the cards it deals, so one of them *is* an answer and
-- nothing else — the cost and the gate on it are the cost and the gate of taking
-- it, which is the whole of "pay more for the better half" in words a card
-- already has. Neither was read until now, so an option could ask four gold and
-- come free.
--
-- The other two things that lie in an offer are real game cards and are not
-- charged. One the offer *borrowed* with "show:" is somebody else's chip and the
-- asker is what acts. One a phase *dealt* out of a deck is a draft, and the
-- price on it is the price of playing it later, not of choosing it — Castle's
-- three buildings would otherwise cost gold to look at, and a hand nobody can
-- afford would be a question with no answer.
local function pickable(c)
	if c.minted then
		local def = cards.def(c)
		if not def then return true end
		local ctx = predicate.bind(cards.behaviour(c, "compute"), { card_id = c.id })
		return M.can_afford(def.cost, ctx) and predicate.meets_all(def.needs, ctx)
	end
	if not c.borrowed_from then return true end
	local oz = entity.get(c.zone_id)
	local asker = oz and oz.asked_by and entity.get(oz.asked_by)
	local rule = asker and cards.def(asker)
	rule = rule and rule.chosen_where
	if not rule then return true end
	return predicate.meets_all(rule, { card_id = asker.id, targets = { c.id } })
end

local function in_play_zone(c)
	local cur = phase.current()
	if not cur or not cur.zone_list then return true end
	if not c then return false end
	-- A card somebody owes is not part of the phase's furniture, so no phase
	-- lists it. It is playable wherever its owner is acting, which is the whole
	-- of what putting something in their hands means.
	local tz = c.zone_id and entity.get(c.zone_id)
	if tz and tz.status == "todo" and (tz.seat == nil or tz.seat == zones.active_seat()) then
		return true
	end
	for _, key in ipairs(cur.zone_list) do
		local z = zones.find(key)
		if z and c.zone_id == z.id then return true end
	end
	return false
end

-- A stack is reached from the top, and only from the top. Decks and piles draw
-- one card and hit-test one card, so the rules have to say the same thing or
-- the two disagree in both directions at once: Lost Cities offered its discard
-- marker as a legal target long after it was buried under a card no click
-- could see past, and a script or a network peer could name anything in the
-- pile. This is the rule the renderer has always followed.
local function on_top(c)
	local z = c and c.zone_id and entity.get(c.zone_id)
	if not z or z.reach ~= "top" then return true end
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
local function hand_to(i)
	local seats = declaration.G.seat_list or {}
	local sys   = system_card()
	if #seats < 2 or not sys or not seats[i] then return end
	sys.stats.turn = i
	history = {}
	local def = declaration.G.card_defs[seats[i]]
	log.add("— " .. ((def and def.text) or seats[i]) .. " to play —")
end

local function rotate_seat()
	local seats = declaration.G.seat_list or {}
	local sys   = system_card()
	if #seats < 2 or not sys then return end
	hand_to((sys.stats.turn or 1) % #seats + 1)
end

-- A group hands the turn to a seat it named rather than to the next one round,
-- so the handover is the same one a rotation makes and only the arithmetic
-- differs. Naming the seat that is already up is not a handover: nobody's turn
-- ended, so the undo history is still theirs and the log has nothing to say.
local function take_turn_seat()
	local seat = phase.take_turn_seat()
	if not seat then return end
	local sys = system_card()
	local i   = (declaration.G.seat_index or {})[seat]
	if i and sys and i ~= (sys.stats.turn or 0) then hand_to(i) end
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

-- How deep an aim is allowed to answer an aim. A card that kills whatever points
-- at it, pointed at by another of the same, is a circle — and the same latch
-- zones.fire_receive keeps, for the same reason.
local aiming = 0

-- **Each card answers having been pointed at**, once the aim is settled and
-- before the aiming card does anything. That order is the rule and not an
-- implementation detail: an Illusion dies *of being targeted*, so it is gone by
-- the time the spell would hit it, which is what leaves the spell with nothing
-- to resolve against. @self is the card that was aimed at and @target the card
-- doing the aiming, exactly as "accepts" is asked a moment earlier — the two are
-- one word's read half and write half and they see the same pair.
--
-- **"when" is the gate, and it is not "needs".** The two settle different
-- questions and a card wants opposite answers from them: an Illusion is
-- targetable by everything, so its "needs" refuses nothing, and it dies only to
-- a spell, so its "when" asks the verb. One list could not have said both. The
-- aim's verb rides in the ctx, so "verb:cast" reads what the target spec
-- declared rather than anything about the card that is aiming.
--
-- Only where a player actually pointed. An aim is what "accepts" gates, so this
-- gates with it: a scope that names a card is not an aim, which is why hexproof
-- stops a bolt and not a board wipe, and why an Illusion survives one too.
local function fire_aimed(targets, source, verb)
	if aiming >= 8 then
		local msg = "! aimed: cards are answering each other's aims in a circle — stopped"
		log.add(msg)
		print(msg)
		return
	end
	aiming = aiming + 1
	local ok, err = pcall(function()
		for _, id in ipairs(targets or {}) do
			local e = entity.get(id)
			local blocks = e and cards.on_receive(e) or {}
			-- **Answered as the card's own owner**, which is the half of the aim that is
			-- about the receiver. "mine" everywhere else means whoever is up, and that is
			-- right for an imperative; this is not one. Macciatus is "*your* Illusions no
			-- longer die when a spell aims at them", and asked from the aimer's side it
			-- answers about the wrong seat. An unowned card gets nil, which is no override.
			--
			-- Only "when" and "action". "needs" -- receive's other half, "accepts" -- gates
			-- whether the aim may be made at all and is honestly about the *aimer*: Codex's
			-- stealth asks "count:detector@mine.addon", meaning the detector belongs to
			-- whoever is pointing. It is checked in targeting.lua and never reaches here.
			--
			-- The gather stays outside, and needs to: a computed keyword is read as the
			-- card's own side wherever it is asked (tags.entity_has holds that seat
			-- itself), so holding it again here would say the same thing twice.
			--
			-- **"whose" gates the whole block**, this half with the other: a ward that
			-- answers only an opponent's aim must not fire on its owner's either.
			local aimer = predicate.seat_of(entity.get(source))
			if #blocks > 0 then
				zones.as_seat(predicate.seat_of(e), function()
					for _, block in ipairs(blocks) do
						local ctx = { card_id = id, targets = { source }, verb = verb }
						if predicate.answers_whose(block.whose, predicate.seat_of(e), aimer)
							and predicate.meets_all(block.needs, ctx) then
							actions.run(block.action, ctx)
						end
					end
				end)
			end
		end
	end)
	aiming = aiming - 1
	if not ok then error(err, 0) end
end

-- Whether a response window is what is holding things up. A record waiting to be
-- answered locks ordinary play for the seat holding priority: priority is the
-- whole of the out-of-turn unlock, and without the lock it unlocked *everything*
-- — the reactor could empty their hand into the turn player's turn. A card that
-- may be played out of turn says so with "reactions", ravel's only spelling for
-- it.
--
-- An interjected phase is the exception, and the reason is the same one: a phase
-- pushed for this seat is a hand-over, not a window. Playing in it is the point,
-- so the lock lifts even though records are still stacked underneath.
local function window_locked()
	return M.pending_event() ~= nil and phase.depth() <= 1
end

local function fired_flags()
	local f = {}
	for i, cond in ipairs(declaration.G.end_conditions) do f[i] = cond.ravel_fired end
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
	for i, cond in ipairs(declaration.G.end_conditions) do cond.ravel_fired = h.fired[i] end
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
		if not cond.ravel_fired and predicate.met(cond) then
			for _, c in ipairs(conds) do c.ravel_fired = true end
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
				zones.purge_card(to.cards[i])
			end
		end
		local pcs = type(ph.pass_card) == "table" and ph.pass_card or { ph.pass_card }
		for _, key in ipairs(pcs) do
			-- A card nobody declared is a typo the validator reports, and a hand without it is still a hand.
			if declaration.G.card_defs[key] then cards.create(key, to.id) end
		end
	end
end

-- Discard a phase's remaining hand: unplayed cards go to the graveyard when
-- one exists (purged otherwise); tokens always just vanish. Fired by the
-- phase.on_leave hook for phases marked discard_hand.
local function discard_hand(ph)
	local grave = zones.find_id("graveyard")
	local n = 0
	-- Every zone the phase played out of, not only the first: a hand it dealt
	-- and an open hand beside it are both this phase's, and leaving one behind
	-- would carry it into the next turn as cards nobody remembers dealing.
	for _, key in ipairs(ph.zone_list or { "hand" }) do
	local hand = zones.find(key)
	if hand then
	while #hand.cards > 0 do
		local cid  = hand.cards[#hand.cards]
		local cdef = cards.def(entity.get(cid))
		if cdef and cdef.tags_set and cdef.tags_set.token then
			zones.purge_card(cid)
		else
			if grave then zones.move_top(hand.id, grave) else zones.purge_card(cid) end
			n = n + 1
		end
	end
	end
	end
	if n > 0 then log.add("Discarded " .. n .. " unplayed") end
end

-- A phase announcing itself. The two moments a phase already has: "begin",
-- beside the actions it runs on the way in, and "end", beside the hand it
-- discards on the way out.
--
-- The subject is the player card of whoever the phase belongs to, so a reaction
-- reads @event as *whose* turn ended — which is the only question anybody asks
-- about a phase — and "whose": "mine" means what it means everywhere else.
--
-- Nothing is deferred, because a phase has no action list waiting on the
-- answer: the announcement goes up, the phase carries on, and whatever answers
-- it resolves on the other side. "At the end of your turn" is a rule about a
-- moment that has passed, which is exactly how it reads at a table.
local function announce(pd, moment)
	local verbs = pd and pd.emits and pd.emits[moment]
	if not verbs then return end
	local pl = player()
	for _, verb in ipairs(verbs) do
		M.emit(verb, pl and { pl.id } or {}, nil, pl and pl.id or nil, nil)
	end
end

phase.on_leave = function(pd)
	if pd.tags_set and pd.tags_set.discard_hand then discard_hand(pd) end
	announce(pd, "end")
end

-- A full round completed: each card on a grid zone runs its on_round actions.
-- Cards at 0 hp are ruined and don't act.
local function run_on_round()
	for e in entity.each("card") do
		local def = cards.def(e)
		local z   = entity.get(e.zone_id)
		-- Through stats.current, so a card standing up on borrowed health acts. The
		-- nil check stays separate: a card with no hp at all is not ruined, it
		-- is a card the question is not about.
		if def.on_round and z and z.status == "board"
			and (e.stats.hp == nil or stats.current(e, "hp") > 0) then
			actions.run(def.on_round, { card_id = e.id, targets = {} })
		end
	end
end

-- Drive the game to a stable point: consume a queued load, fire end conditions,
-- run automatic phases, run on_round triggers after a full round, deal freshly
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
				-- After the menu has cleared the log, or the player lands on it with no idea why.
				log.add("! " .. tostring(fname) .. " would not load: " .. tostring(err))
			end
			return
		end

		-- A saved game replaces this one whole, so it lands between action lists
		-- rather than inside one. What is in the slot is the save layer's
		-- business — no engine module may require it — and a build without one
		-- leaves the game exactly as it was. A refusal (an empty slot, a game
		-- file edited since) says so and changes nothing; a save that blows up
		-- partway *through* the restore leaves a half-wiped game, so that falls
		-- back to the menu exactly as a failed load_game does.
		local slot = actions.take_slot()
		if slot then
			if actions.on_save and not pcall(actions.on_save, "load", slot) then
				pcall(M.init, "menu.json")
			end
			return
		end

		-- The response window comes first. A stack waiting to be answered holds up
		-- outcomes and phases both, and settle is where anything "after an action"
		-- belongs (invariant 3). "waiting" means a seat must answer, so the loop
		-- stops and waits for input exactly as a fresh player_input phase does;
		-- "resolved" means a stack item ran, so loop again; "idle" is every game
		-- without a stack and every moment its stack is empty — unchanged.
		local rstate = M.react_step()
		if rstate == "waiting" then return end
		-- A question waiting to be asked holds up phases exactly as an unanswered
		-- window does, and is settled in the same place for the same reason.
		-- Before the questions, because a card owed holds those up too, and one
		-- nobody can play would hold them up for ever.
		local cleared = M.todo_step()
		local asked = M.offer_step() or cleared
		M.release_priority()
		-- Outcomes wait until any open overlay (a pending choice) is closed.
		if rstate ~= "resolved" and not asked and (phase.is_overlay() or not fire_end_condition()) then
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
				run_on_round()
			elseif cur and cur.type == "automatic" then
				if phase.take_fresh() then
					take_turn_seat()
					if phase.arrived() then actions.run(cur.on_enter, {}) end
					actions.run(cur.actions, {})
					announce(cur, "begin")
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
				--
				-- **The route may overrule the phase about the seat**, because a
				-- phase leading back to itself is asked for opposite answers by
				-- different games: Splendor's turn carries on with the same
				-- player until they are done, The Crew's draft passes round the
				-- table. Two phase keys for one turn is what that used to cost,
				-- and the second was a copy of the first with one word missing.
				local seat = phase.route_seat() or cur.seat
				if seat == "next" then rotate_seat() end
				take_turn_seat()
				local pl = player()
				if pl then pl.stats.plays = 0 end
				-- What a phase does when the turn *begins*, as against what it
				-- does every time round: a reset that runs again on the way back
				-- would undo the turn it was counting.
				--
				-- A turn begins on an arrival from another phase, and on a loop
				-- that hands the turn on — those are two ways of writing the same
				-- moment, and a draft that passes round the table by looping must
				-- not skip it. What it is *not* is a loop that keeps the same
				-- player, which is the case the whole split exists for. Run after
				-- the seat has moved, so "mine" is the player about to act.
				if phase.arrived() or seat == "next" then actions.run(cur.on_enter, {}) end
				-- What a phase does when it begins, which used to be a thing only
				-- automatic phases could say. The seat has changed by now, so
				-- "mine" here is the player about to act; the hand is dealt after,
				-- so a phase can draw into the hand it is about to deal.
				actions.run(cur.actions, {})
				announce(cur, "begin")
				deal(cur)
			elseif cur and cur.ends_when and cur.type ~= "overlay"
				and predicate.holds(cur.ends_when, {}) then
				-- **A phase says how it ends, and the answer is asked every time
				-- the game comes to rest** — which is after every action rather
				-- than only after a play. `ends_after` counts plays and cannot
				-- tell one from another, which is true of the games written so
				-- far and false of most: in a trick-taking game putting a card
				-- into the middle ends your turn and everything else you may do
				-- does not. Written as an ordinary condition, so it is the same
				-- vocabulary a route or a cost is.
				--
				-- Overlays are excluded: they are resolved by choosing, and they
				-- pop rather than advance.
				phase.next()
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
	actions.take_slot()
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

	-- Setup: the manual's arrangement, in the order it is written. A card no
	-- longer says where it starts — the cards are what comes out of the box, and
	-- this is the page that lays them out. The engine's own entries (the system
	-- card, an injected player, a seat) are prepended by declaration.parse.
	--
	-- The order is load-bearing rather than incidental: entity IDs are handed out
	-- in creation order, so a seed reproduces a board only if setup builds it the
	-- same way every time.
	for _, e in ipairs(G.setup_place or {}) do
		local def = G.card_defs[e.card]
		if def then
			-- Into every instance of the zone, which is one for a shared zone
			-- and one per seat otherwise: a per-seat board wants its marker in
			-- each seat's copy, not a single one in whoever happens to be first.
			local zkey = e.zone or cards.home_zone(def) or "board"
			-- A seat's own card is the one thing a per-seat zone does not copy:
			-- it goes in that seat's instance and in no other. Everything else
			-- is a copy each, which is what a marker every player starts with
			-- wants — but four seat boxes holding all four players apiece is a
			-- table where nobody is anywhere.
			local into = zones.all_with_key(zkey)
			if G.seat_set[e.card] then
				local own = {}
				for _, to in ipairs(into) do
					if not to.seat or to.seat == e.card then own[#own + 1] = to end
				end
				into = own
			end
			for _, to in ipairs(into) do
				-- One entry may name several squares, and then it is several
				-- pieces: eight pawns are one line naming eight squares.
				for _, at in ipairs(e.at or NOWHERE) do
					local card = cards.create(def.key, to.id)
					-- Before it is put down, not after: placing a piece stamps
					-- its rank, and a rank counts from its owner's own side.
					local owner = e.owner and G.seat_index and G.seat_index[e.owner]
					if owner then card.stats.owner = owner end
					local slot_id = at ~= true and geometry.slot_named(to, at)
					if slot_id then zones.place_in_slot(card.id, slot_id) else zones.auto_slot(card.id) end
				end
			end
		end
	end

	phase.init(G)
	if G.phase_list[1] then phase.push(G.phase_list[1]) end
	zones.resize()
	M.settle()
end

-- The ways the move an interface is about to make may be paid for. `intent` is
-- the word targeting already carries, so an interface asks with what it is
-- holding instead of finding the rule a second time.
function M.intent_payments(intent, card_id, targets, index)
	if intent == "activate" then
		for _, u in ipairs(M.usable_abilities(card_id)) do
			if u.index == index then return M.rule_payments(card_id, u.rule, targets) end
		end
		return {}
	elseif intent == "react" then
		local c = entity.get(card_id)
		local r = c and cards.reactions(c)[index or 1]
		return r and M.rule_payments(card_id, r, targets) or {}
	end
	return M.play_payments(card_id, targets)
end

-- A card is playable when its cost is affordable and its needs are met.
-- Escape hatch: a needs-gated card becomes playable when nothing else in its
-- zone is, so a mandatory play can never soft-lock a hand. The gates leave
-- ctx.targets unset: nothing has been chosen yet, and a cost the targets would
-- pay cannot be judged until they are.
--
-- Every gate but the hatch, and apart from it the needs: whether the card could
-- be played at all, and whether its needs hold. The hatch asks this of the rest
-- of the hand, because a card that blocks it has to be one the player can
-- actually play — asked less, a card with nothing to run or one for another
-- phase held the hatch shut while being unplayable itself, and the hand had no
-- move at all.
local function gates(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not reachable(c) or not in_play_zone(c) or not on_top(c) then return false end
	local z = c.zone_id and entity.get(c.zone_id)
	-- What may be done with a card here at all. The renderer and the hit-test
	-- have always honoured it (zones.card_at) and flow never did, so the top
	-- card of a face-down deck was playable to anything that did not come
	-- through a mouse — a script, the debug API, the network, an engine-played
	-- seat. Flow is the single legality gate, which has to mean this one too.
	if z and z.use ~= "play" then return false end
	-- A card lying in an open offer is the answer to the question the offer is,
	-- and the gates below are about playing a card from a hand. The one thing
	-- that may still refuse it is the asking card saying which of them it will
	-- take — "trash their *largest gem*" opens the whole hand and accepts one
	-- card out of it, and without this the whole hand was acceptable.
	if choosing(c) then return pickable(c), true end
	-- A window is open, so the only move is to answer it. The same shape as the
	-- overlay lock in activate below — a pending question locks other actions —
	-- and it bites only the seat holding priority, since nobody else is reachable
	-- anyway. Priority was the whole of the out-of-turn unlock, and without this
	-- it unlocked everything: the reactor could empty their hand into the turn
	-- player's turn. A card that may be played out of turn says so with
	-- "reactions", which is ravel's only spelling for it.
	if window_locked() then return false end
	-- A card with nothing to run is not a move. Playing it changes nothing at
	-- all — flow runs on_play and stops — so it reads as a live card, does
	-- nothing when clicked, and the escape hatch below will offer it forever
	-- because it has no cost and no needs to fail. Asked through behaviour, so a
	-- zone that grants a play still counts.
	--
	-- **Unless it says where it lands.** A card whose whole play is going
	-- somewhere — an ongoing effect laid out in front of you — does exactly one
	-- thing when clicked, and that one thing is the move. Its action list is
	-- empty because "spent" is where the going lives now, and reading the empty
	-- list as "nothing happens" made every such card unplayable.
	local on_play = cards.behaviour(c, "on_play")
	local lands   = cards.behaviour(c, "spent")
	if not ((type(on_play) == "table" and #on_play > 0) or lands) then return false end
	if not phase_ok(cards.behaviour(c, "phases")) then return false end
	-- Bound once and read by both: a card whose cost or gate is worked out from
	-- the board says the arithmetic once and names it, and the name has to mean
	-- the same number in the question and in the deed.
	local ctx = predicate.bind(cards.behaviour(c, "compute"), { card_id = card_id })
	-- An imaginary card is not the card, it is the card happening again, and a
	-- copy is free by definition — nobody paid for it twice at the table.
	if not c.imaginary and not M.can_afford(def.cost, ctx) then return false end
	return true, predicate.meets_all(def.needs, ctx), z
end

function M.can_play(card_id)
	local ok, met, z = gates(card_id)
	if not ok or met then return ok and met end
	-- A zone tagged "optional" holds buttons, not a hand: nothing in it ever has
	-- to be played, so there is no soft-lock for the hatch below to break, and
	-- opening it would offer a move the rules had just refused. Chess's castling
	-- cards are the case — all four are gated most of the game, and "nothing
	-- else here is playable" is their normal state rather than a trap.
	if z and z.tags.optional then return false end
	-- **Everything the phase would let you play, not only this card's own zone.**
	-- The hatch exists so a mandatory play cannot soft-lock a hand, and a hand is
	-- whatever the phase says it is: with a closed hand and an open one, asking
	-- only about the zone the card lies in would open the hatch for a lone gated
	-- card lying beside a hand full of legal ones — which in a trick-taking game
	-- is follow-suit quietly switching itself off.
	local cur = phase.current()
	local keys = cur and cur.zone_list
	local pool = {}
	if keys then
		for _, key in ipairs(keys) do
			local zz = zones.find(key)
			for _, cid in ipairs(zz and zz.cards or {}) do pool[#pool + 1] = cid end
		end
	else
		for _, cid in ipairs(z and z.cards or {}) do pool[#pool + 1] = cid end
	end
	for _, cid in ipairs(pool) do
		if cid ~= card_id then
			local other, fine = gates(cid)
			if other and fine then return false end
		end
	end
	return true
end

-- Emptying an offer. A card the offer *made* is spent by being chosen from — it
-- existed to be a line on a list, and leaving it would leave invisible cards
-- lying over the board, which is a bug this engine has already had once. A card
-- the offer *borrowed* is somebody's property and goes home. That is the whole
-- difference between `options:` and `show:`.
--
-- Both flags go together: they describe one offer, and leaving the second
-- behind hands the *next* offer a permission it never asked for. A promotion
-- opened after the pawn has already moved would then be declinable, and a pawn
-- would sit on the eighth rank as a pawn.
-- `keep` is the card the player just picked, whose fate the chosen actions get
-- to decide -- everything else goes home now, before those actions run, so that
-- an offer they open in turn finds the zone empty. There is one "options" zone
-- and it knows its contents by what is lying in it, so a sweep that ran
-- afterwards could not tell the first question's leftovers from the second
-- question's cards, and took both.
local function clear_offer(oz, keep)
	local left = {}
	for i, cid in ipairs(oz.cards) do left[i] = cid end
	for _, cid in ipairs(left) do
		local c    = cid ~= keep and entity.get(cid)
		local home = c and c.borrowed_from
		if home and entity.get(home) then
			zones.move_card(cid, home)
		elseif c then
			zones.purge_card(cid)
		end
	end
	oz.asked_by, oz.dismissable, oz.asked_seat = nil, nil, nil
end

-- Play a card: pay its cost and run on_play. A phase with a play limit then
-- ends itself; discarding its hand is the on_leave hook's job.
-- Playing a card out of an overlay's zone *is* choosing it: an overlay is a
-- pending choice, and a choice is resolved by playing something. So there is no
-- separate pick path — the phase's zone bounds what may be played (in_play_zone
-- does that for every phase), and the two rules an overlay adds are its own:
--
--   it pops before the action runs, so a chained reveal lands on top rather than
--   burying the overlay it came from;
--   and a card still lying in the offer afterwards is spent — a read page
--   vanishes, while one whose action moved it somewhere stays where it went.
--
-- Both used to live inside flow.pick, which also meant a card's own actions were
-- silently ignored unless the overlay declared "page".
-- The system column is outside the game, so its cards are not moves: they run
-- in any phase, including one no player is acting in, and they are not gated,
-- costed, undone or sent. A player locked out of their own menu by an automatic
-- phase would have nowhere to go. Answers whether the card was one of its own,
-- so the caller can carry on if it was not.
function M.is_system_card(card_id)
	local c = card_id and entity.get(card_id)
	local z = c and entity.get(c.zone_id)
	return z ~= nil and z.key == "menu"
end

function M.use_system_card(card_id)
	if not M.is_system_card(card_id) then return false end
	local c = entity.get(card_id)
	if tags.entity_has(c, "event_log") then
		log.set_view("next")
		return true
	end
	local def = cards.def(c)
	-- A game may put its own buttons in the column beside the engine's, and
	-- those are moves: they cost, they are gated by phase, and they belong to
	-- whoever is acting. Only a card that plays straight from the column is the
	-- engine's kind — anything else falls through to the phase, which is what
	-- decides whether an ability may be used at all.
	if not (def and def.on_play) then return false end
	actions.run(def.on_play, { card_id = card_id })
	-- Loading a game and restoring a save are both deferred: the action only
	-- asks, and settle is what carries it out. Without this the Menu button did
	-- nothing at all, and the game then changed under a player who had given up
	-- on it — on whatever later click settled for its own reasons.
	M.settle()
	return true
end

function M.play_card(card_id, targets, payment)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def or not M.can_play(card_id) then return false end
	-- Flow is the single legality gate: target counts are enforced here, not
	-- only in the input layers, so scripts and the debug API can't skip them.
	local overlay = choosing(c) and phase.current() or nil
	if not overlay then
		local lo, hi = targeting.bounds(def.target)
		if #(targets or {}) < lo or #(targets or {}) > hi then return false end
		if not targets_legal(card_id, def.target, targets) then return false end
	end
	local offer   = overlay and zones.find_id(overlay.zone or "hand")
	-- An offer remembers what it was an offer *for*, and the card chosen is
	-- played against it. That is what lets a choice act on the thing that asked
	-- — a pawn becoming a queen — without the game marking it first and hunting
	-- for the mark afterwards.
	local asker   = offer and entity.get(offer) and entity.get(offer).asked_by
	-- Which way round the offer works. An entry the engine dealt carries the
	-- rule and the asker is what it is about, so the asker is its target. A card
	-- the offer *borrowed* carries nothing of ours — it is somebody's chip — so
	-- it is the answer and the asker is the actor.
	local lent    = overlay and c.borrowed_from ~= nil
	-- Which loan this pick is. Held so the settling at the bottom can tell the
	-- card *still lying in the offer* from one a later rule has lent back into it:
	-- "discard a card, then look through your discard pile" fetches the very card
	-- just discarded, and sending it home on the strength of standing in an offer
	-- would empty the question that had just borrowed it.
	local home    = c.borrowed_from
	-- Whose price this is. A card played from a hand pays its own, and so does an
	-- answer the offer minted; a borrowed chip and a card dealt out of a deck are
	-- real game cards whose price is the price of playing them, not of taking them.
	local charged = (not overlay or c.minted == true) and not c.imaginary
	if asker and entity.get(asker) and not lent then targets = { asker } end
	-- The targets are in, so a compute that measures them measures the right
	-- ones: "deal damage equal to what you aimed at" is a number about the pair,
	-- and it is bound here so it reads them as they were pointed at rather than
	-- as whatever answering the aim leaves behind.
	--
	-- An aim is pinned only where a player pointed — a choice out of an offer
	-- swaps the targets for the asker two lines up and is not one.
	local aimed = (not overlay) and def.target and predicate.standing(targets) or nil
	local ctx = predicate.bind(cards.behaviour(c, "compute"),
		{ card_id = card_id, targets = targets or {}, aimed = aimed,
			verb = def.target and def.target.verb })
	-- A cost the targets pay could not be judged before they were chosen.
	if charged and not M.can_afford(def.cost, ctx) then return false end
	-- A payment arrives beside the targets and is checked like them: an
	-- interface collected it, but a script, the network or an engine seat may
	-- have, and flow is the one gate all four come through.
	if charged and not M.payment_legal(def.cost, ctx, payment) then return false end
	checkpoint()
	log.add((overlay and "Chose " or "Played ") .. (def.text or c.def_key))
	local pl = player()
	-- An overlay is a phase of its own, and the counter that bounds a hand
	-- belongs to the phase underneath it: counting a choice as a play would end
	-- that phase early, since the count survives the pop.
	if pl and not overlay then pl.stats.plays = (pl.stats.plays or 0) + 1 end
	if charged then costs.pay(def.cost, ctx, payment) end
	-- A choice taken out of an offer is not a card acting, it is the card that
	-- opened the offer still acting — so the mark stays where it was.
	if not overlay then cards.mark_acted(card_id) end
	if overlay then phase.pop() end
	-- The rest of the offer goes home *here*, before the chosen actions run.
	-- Those actions may open an offer of their own -- a card that resolves
	-- another card is asking two questions, and the second one is the copied
	-- card's -- and a sweep afterwards could not tell that offer's cards from
	-- this one's leftovers, so it took both and left an overlay with nothing in
	-- it and its "dismissable" flag cleared. A question with no answer and no
	-- way out.
	--
	-- The picked card is the exception and stays: what becomes of it is exactly
	-- what the chosen actions are about, and it is settled below once they have
	-- had their say.
	local oz = offer and entity.get(offer)
	if oz and oz.status == "offer" then clear_offer(oz, card_id) end
	-- Through behaviour, so a zone can grant what playing a card lying in it
	-- does — which is how one offer deals a card the game has other plans for.
	local lender = lent and asker and entity.get(asker)
	-- Before the card acts and before the announcement goes up, because being
	-- pointed at is what the aimed-at card is answering and the announcement is
	-- already the pointing: an Illusion dies to a spell that is then countered.
	if aimed then fire_aimed(targets, card_id, def.target.verb) end
	if lender then
		actions.run(cards.behaviour(lender, "on_chosen"), { card_id = asker, targets = { card_id } })
	elseif not M.defer_play(card_id, targets, aimed) then
		-- Unless the play was put up to be answered, in which case it happens when
		-- the stack says so and not before — and the spending goes with it.
		actions.run(cards.behaviour(c, "on_play"), ctx)
		stack.send_spent(card_id, cards.behaviour(c, "spent"))
	end
	-- And now the picked card, once those actions have had their say. A card the
	-- offer *dealt* is spent by being chosen and vanishes; one it *borrowed* is
	-- somebody else's and goes home. Either way only if it is still lying there:
	-- a rule that moved it somewhere has already answered this question.
	local picked = entity.get(card_id)
	if offer and picked and picked.zone_id == offer and picked.borrowed_from == home then
		if home and entity.get(home) then
			zones.move_card(card_id, home)
		else
			zones.purge_card(card_id)
		end
	end
	-- An imaginary card has done what it was made for. It never paid, so it is
	-- not spent anywhere: it simply stops existing, which is the other half of
	-- "create it out of thin air".
	if c.imaginary and entity.get(card_id) then zones.purge_card(card_id) end
	if tags.entity_has(c, "no_undo") then
		history = {}
		log.add("— no turning back —")
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
-- Which of a card's abilities may be used right now, in the order it declared
-- them. A card is clickable when this is not empty, and when it holds more than
-- one the player is asked which — the chooser exists because the answer stopped
-- being obvious, not because every card wants one.
--
-- Exhaustion is not asked here any more: it is a cost, and "exhaust" is checked
-- like the rest. A card with a tap ability beside a free one keeps offering the
-- free one after the first is spent, which is half the reason it moved.
-- Which of a list of rules may be used right now. A card's abilities, a zone's
-- abilities: the same shape, so the same question, asked once.
--
-- **The list is the argument.** What differs between a card and a place is who
-- may reach it, which the callers below answer before getting here; what a rule
-- costs, when it works and whether it says anything are the rule's own business
-- and read the same wherever it is written. That is the whole point of abilities
-- and reactions sharing a shape in the file — an engine that then wrote the test
-- twice would be keeping a distinction the format has already refused.
--
-- `ctx` seeds every rule's own bound computes: { card_id = ... } for a card's,
-- { zone_id = ... } for a place's.
local function usable_rules(list, ctx)
	local out = {}
	for i, a in ipairs(list) do
		-- A rule that can reach nothing is not on offer. Without this a chooser
		-- lists dead entries, and a piece with a conditional move looks like it
		-- has two things to do when it has one. It used to ask only about
		-- `moves`, which is one kind of target out of three: The Crew's radio has
		-- twelve abilities and a hand answers two or three of them, so the other
		-- nine were nine dead lines in the chooser.
		local id = ctx.card_id
		local lo = a.target and select(1, targeting.bounds(a.target)) or 0
		local reaches = lo == 0
			or (a.target.moves and #targeting.moves_by(id, a.target.moves) > 0)
			or (a.target.moves == nil and #targeting.candidates(id, a.target) >= lo)
		local bound = predicate.bind(a.compute, ctx)
		if has_ability(a.action) and phase_ok(a.phases)
			and predicate.meets_all(a.needs, bound)
			and M.can_afford(a.cost, bound)
			and reaches then
			out[#out + 1] = { index = i, rule = a }
		end
	end
	return out
end

function M.usable_abilities(card_id)
	local c = entity.get(card_id)
	if not c or not cards.def(c) or not reachable(c) or not on_top(c) then return {} end
	-- Locked while something waits to be answered, for the reason can_play is: a
	-- reactive ability is a "reactions" entry, not an ability that happens to be
	-- reachable because priority moved.
	if window_locked() then return {} end
	-- Whether abilities work here is the zone's to say, not something to infer
	-- from its shape: a board and a Lost Cities discard both allow it, a hand
	-- and an MTG graveyard both do not, and neither pair shares a zone type.
	local z = entity.get(c.zone_id)
	if not (z and z.use == "abilities") then return {} end
	return usable_rules(cards.abilities(c), { card_id = card_id })
end

function M.can_activate(card_id)
	return #M.usable_abilities(card_id) > 0
end

-- The ability a bare activation means: the only usable one. With several, the
-- caller has to have chosen, and the input layer is what asks.
function M.sole_ability(card_id)
	local u = M.usable_abilities(card_id)
	return #u == 1 and u[1] or nil
end

-- Deal one menu entry per usable rule into the offer and open it. Three things
-- get asked about this way — which of a card's abilities to use, which of a
-- place's, and which of a card's reactions to answer with — and they differ only
-- in the word written on the entry, because a rule is a rule.
--
-- Which one an entry means is written on the entry, not baked into its
-- definition: *which number* an ability is depends on the zone the card is lying
-- in, because a zone's "applies" adds to the list. The same menu card dealt for a
-- rook in a pile and a rook on the board would otherwise resolve to two
-- different abilities.
local function offer_choices(card_id, usable, stat)
	if #usable < 2 then return false end
	local zone_id = zones.find_id("options")
	if not zone_id then return false end
	local owner = (entity.get(card_id).stats or {}).owner
	for _, u in ipairs(usable) do
		local made = cards.create(u.rule.menu_card, zone_id)
		made.stats[stat] = u.index
		if owner then made.stats.owner = owner end
	end
	local z = entity.get(zone_id)
	z.asked_by = card_id
	-- A chooser opened by clicking a card is a question asked before anything
	-- has happened, so it may be declined and the click taken back. An offer the
	-- *rules* opened — promotion, after the pawn has already moved — may not:
	-- there is no state to return to, and a pawn cannot stay a pawn on the far
	-- rank.
	z.dismissable = true
	phase.push("options")
	return true
end

-- Open the chooser for a card that has more than one thing to do. The offer is
-- the same one `options` deals, and it remembers the card that asked, so the
-- menu entry chosen knows whose ability it was.
function M.offer_abilities(card_id)
	return offer_choices(card_id, M.usable_abilities(card_id), "ability")
end

-- The same for a place that offers more than one thing: a deck that draws one or
-- five is asked about exactly as a card with two abilities is.
function M.offer_zone_abilities(zone_id)
	return offer_choices(zone_id, M.usable_zone_abilities(zone_id), "ability")
end

-- The same for a card that answers the open window more than one way. Rare, and
-- the reason the chooser is reused rather than a second surface invented: a
-- window is a player_input phase so the board stays visible, and only the one
-- card that needs a question asked about it opens an overlay.
function M.offer_reactions(card_id)
	local mine = {}
	for _, u in ipairs(M.usable_reactions()) do
		if u.card == card_id then mine[#mine + 1] = u end
	end
	return offer_choices(card_id, mine, "reaction")
end

-- Whether the offer on screen may be walked away from. Asked by the renderer,
-- which draws the button that says so — a permission nothing shows is one
-- nobody uses, and this was right-click-only for its first two games.
--
-- The *open* overlay has to be the offer in question. "An overlay is open" is
-- not the same thing: a reveal stacked on top of an options phase would
-- otherwise be popped by a click meant for the chooser underneath it, taking
-- the chooser's cards with it.
function M.can_dismiss()
	local z   = zones.find("options")
	local cur = phase.current()
	return z ~= nil and z.dismissable == true
		and cur ~= nil and cur.type == "overlay" and cur.zone == "options"
end

-- Decline an offer that may be declined. Answers whether it did, so an input
-- layer can fall through to whatever a right-click otherwise means.
function M.dismiss_offer()
	if not M.can_dismiss() then return false end
	M.close_offer()
	return true
end

-- The ability a menu entry stands for, and the card it belongs to — nil for any
-- other card, which is every card a game wrote.
function M.menu_choice(card_id)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not (def and def.ravel_menu_for) then return nil end
	local z = c.zone_id and entity.get(c.zone_id)
	local source = z and z.asked_by
	if not (source and entity.get(source)) then return nil end
	-- Which list the entry points into is the entry's own word. The two indices
	-- are into different lists and would collide if one stat carried both. What
	-- comes back says which in a word rather than by which field is present: a
	-- reaction and an ability are one shape, and the caller is asking what to do
	-- with it, not what it is made of.
	local ridx = (c.stats or {}).reaction
	if ridx and ridx > 0 then
		local r = (cards.reactions(entity.get(source)) or {})[ridx]
		return r and { source = source, index = ridx, rule = r, kind = "reaction" } or nil
	end
	local idx = (c.stats or {}).ability
	-- A place asks with the same entries a card does, and what it is deciding
	-- between is the same list under the same name. Its own, though: a zone wears
	-- no tags and lends nothing, so there is nothing to merge in.
	local src  = entity.get(source)
	local list = src.kind == "zone" and (src.abilities or {}) or cards.abilities(src)
	local a = idx and list[idx]
	return a and { source = source, index = idx, rule = a, kind = "ability" } or nil
end

-- Shut the offer without choosing anything from it: the entries go, the offer
-- forgets, and the phase underneath comes back. Used when a choice turns into a
-- question — the chooser has done its job and the board has to be visible to
-- answer on.
function M.close_offer()
	local z = zones.find("options")
	if not z then return end
	clear_offer(z)
	if phase.is_overlay() then phase.pop() end
	-- Shutting an offer is an action like any other, and settle is where anything
	-- "after an action" belongs: the next question in the queue is asked here, and
	-- before there was a queue there was simply nothing waiting to notice.
	M.settle()
end

-- Activate a board card's ability. With several usable, `index` says which —
-- the one the chooser resolved to, since the caller has to have asked.
--
-- **Being spent is a cost, not a consequence.** An ability that may be used once
-- a round says { "exhaust": 1 } and one that stays available says nothing, where
-- this used to exhaust every card that acted and offer "stays_ready" to opt out.
-- Two reasons the cost is the right end of it: the round-long cooldown is the
-- card's rule rather than the engine's, and once a card may carry several
-- abilities "activating exhausts it" has no answer to *which* ability did — only
-- the one whose cost says so.
function M.activate(card_id, targets, index, payment)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	-- Asked once and held: each call walks every ability through can_afford and
	-- generates its moves, and this is the hot legality path — the renderer asks
	-- it per board card per frame, and the browser build has no JIT.
	local usable, chosen = M.usable_abilities(card_id), nil
	for _, u in ipairs(usable) do
		if index == nil or u.index == index then chosen = chosen or u end
	end
	-- No index and more than one to pick from is a caller that has not asked
	-- the player yet. Refusing beats guessing: choosing for them is how a
	-- click spends the wrong thing.
	if not chosen or (index == nil and #usable > 1) then return false end
	local a   = chosen.rule
	local c   = entity.get(card_id)
	local def = cards.def(c)
	-- Flow is the single legality gate, exactly as in play_card: target counts
	-- are enforced here, not only in the input layers, so scripts and the
	-- debug API can't skip them.
	local lo, hi = targeting.bounds(a.target)
	if #(targets or {}) < lo or #(targets or {}) > hi then return false end
	if not targets_legal(card_id, a.target, targets) then return false end
	local aimed = a.target and predicate.standing(targets) or nil
	local ctx = predicate.bind(a.compute,
		{ card_id = card_id, targets = targets or {}, aimed = aimed,
			verb = a.target and a.target.verb })
	if not M.can_afford(a.cost, ctx) then return false end
	-- A payment arrives beside the targets and is checked like them: an
	-- interface collected it, but a script, the network or an engine seat may
	-- have, and flow is the one gate all four come through.
	if not M.payment_legal(a.cost, ctx, payment) then return false end
	checkpoint()
	cards.mark_acted(card_id)
	log.add("Activated " .. (def.text or c.def_key)
		.. (a.text and #usable > 1 and (" — " .. a.text) or ""))
	costs.pay(a.cost, ctx, payment)
	if aimed then fire_aimed(targets, card_id, a.target.verb) end
	if not M.defer_activation(card_id, a, ctx) then
		-- Unless using it was put up to be answered, in which case it happens when
		-- the stack says so and not before.
		actions.run(a.action, ctx)
	end
	M.settle()
	return true
end

-- The word an open ending card says, for the games where one word is the whole
-- truth. Purely derived, so undo needs no extra state.
local function ending()
	local cur = phase.current()
	if not cur or cur.type ~= "overlay" then return nil end
	local z = zones.find(cur.zone or "hand")
	for _, cid in ipairs(z and z.cards or {}) do
		local def = cards.def(entity.get(cid))
		if def and def.outcome then return def.outcome end
	end
end

-- The seat that won, if one has. A win is a number on a seat rather than a word
-- on the ending card, and the difference is everything a word cannot do: it is
-- state, so the snapshot carries it to the other machine, undo takes it back,
-- and a rule can read it ("won@mine"). Every seat carries the stat from load
-- (declaration.parse), so a game says who won with one ordinary action.
local function victor()
	local seats = declaration.G.seat_set or {}
	for e in entity.each("card") do
		if seats[e.def_key] and e.zone_id and stats.current(e, "won") > 0 then return e.def_key end
	end
end

-- "victory", "defeat", or "decided" — an ending that happened to somebody other
-- than the person reading it.
--
-- A solo game says the word outright and is right to: you against the tower, and
-- nobody else for it to be wrong about. Where a seat won, the word is answered
-- against the seat *watching*, because one word cannot be true for both players
-- — congratulating the loser is the whole reason a seat is asked for here. With
-- no seat claimed there is no "you" in the room to address, so the ending is
-- announced rather than delivered: the hot-seat handover ceremony refused in
-- kinder words, one screen, one room, the winner named to it.
function M.outcome()
	local cur = phase.current()
	if not cur or cur.type ~= "overlay" then return nil end
	local won = victor()
	if won then
		local seat = zones.watching()
		if not seat then return "decided" end
		return seat == won and "victory" or "defeat"
	end
	local o = ending()
	return type(o) == "string" and o or nil
end

-- Who won, in the seat's own words. A seat is a card, so it already has the name
-- a game gave it — "White", "North" — and there is nowhere else that name should
-- come from.
-- Through seat_text rather than off the def, since a seat's text may be the
-- template a set_name verb feeds: a banner reading "{name} wins" is the third
-- read path found bypassing label.fill, and the only one a player sees.
function M.winner()
	local won = victor()
	return won and (require("label").seat_text(won) or won) or nil
end

-- One entry per visible stat, for the end-of-run summary. Read as the seat
-- watching, since a row labelled "Your score" showing the other player's is the
-- same fault as an opponent's hand drawn face up — see zones.as_seat.
function M.summary()
	local G   = declaration.G
	local out = {}
	zones.as_seat(zones.watching(), function()
		for _, key in ipairs(G.stat_defs_list or {}) do
			local def = G.stat_defs[key]
			local v = predicate.total(def and def.subject or key)
			if declaration.stat_shown(key, v) then
				out[#out + 1] = (def and def.label or key) .. " " .. v
			end
		end
	end)
	return out
end

-- A zone has abilities of its own, and they are gated like a card's.
--
-- This used to be `on_click`, which fired in *any* phase and answered to
-- nothing but the overlay lock — so DESIGN had to warn that it was not a move
-- and must not be used as one. It is a move now, and bounded like one: the
-- phase it works in, what it costs, and whose zone it is.
--
-- A deck is the case that asked for it. "Click the deck to draw" was going to
-- need the top card to become clickable, and therefore hoverable, and therefore
-- guarded by a visibility rule so that hovering a face-down deck did not read
-- out its top card. A deck has no clickable cards — it is a box — so the box
-- answers, and the problem is deleted rather than defended against.
--
-- Not gated: exhaustion. A zone is not spent by being used, and a deck that
-- could only be drawn from once a round is a rule a game would have to ask for
-- rather than one it should get by default.
function M.usable_zone_abilities(zone_id)
	local z = entity.get(zone_id)
	if not z or z.kind ~= "zone" then return {} end
	-- A per-seat zone answers to its seat, which is what `reachable` says for a
	-- card. A shared zone belongs to nobody and answers to whoever is playing.
	if z.seat and z.seat ~= zones.active_seat() then return {} end
	if window_locked() then return {} end
	return usable_rules(z.abilities or {}, { zone_id = zone_id })
end

-- With several usable, `index` says which — the one the chooser resolved to,
-- exactly as for a card, and for the same reason: no index and more than one to
-- pick from is a caller that has not asked the player yet.
function M.activate_zone(zone_id, index, payment)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	local usable, chosen = M.usable_zone_abilities(zone_id), nil
	for _, u in ipairs(usable) do
		if index == nil or u.index == index then chosen = chosen or u end
	end
	if not chosen or (index == nil and #usable > 1) then return false end
	local a   = chosen.rule
	local z   = entity.get(zone_id)
	local ctx = predicate.bind(a.compute, { zone_id = zone_id })
	-- A payment arrives beside the targets and is checked like them: an
	-- interface collected it, but a script, the network or an engine seat may
	-- have, and flow is the one gate all four come through.
	if not M.payment_legal(a.cost, ctx, payment) then return false end
	checkpoint()
	-- A zone is nothing card-shaped, so the last thing a player did was not to a
	-- card and nothing carries the mark. Leaving a stale one would keep a window
	-- open through a draw.
	cards.mark_acted(nil)
	log.add("Used " .. (z.label or z.key)
		.. (a.text and #usable > 1 and (" — " .. a.text) or ""))
	costs.pay(a.cost, ctx, payment)
	actions.run(a.action, ctx)
	M.settle()
	return true
end

-- The next question that is waiting, if the last one is finished with. There is
-- one offer zone and one overlay over it, so asks queue rather than pile up:
-- `show:` writes down the one it could not open (actions.lua), and this is where
-- the game comes back to it — in settle, which is where anything "after an
-- action" belongs, and this is after one.
--
-- Run as the seat it was asked of, since an offer is answered by whoever is up.
-- What is stored is the action itself rather than the cards it would have moved,
-- the same shape as the tail an `emit:` defers: the board has changed by now and
-- the question is about the board as it stands.
-- A card nobody can play is not an obligation, it is a lock. The offer keeps the
-- same rule already — nothing to take is nothing to look at — and a todo needs it
-- more, because a question can at least be declined and a card cannot.
--
-- All or nothing, and only when *none* of them can be played: with two owed and
-- one playable, the other may well be waiting on what the first one does.
function M.todo_step()
	local z = zones.todo_pending()
	if not z or phase.is_overlay() then return false end
	for _, id in ipairs(z.cards) do
		-- can_play does not ask whether there is anything to aim at — the
		-- interface finds that out when it opens targeting and closes it again.
		-- Here it is the difference between a card and a lock.
		local def  = cards.def(entity.get(id))
		local spec = def and def.play and def.play.target
		local need = spec and targeting.bounds(spec) or 0
		if M.can_play(id) and (need == 0 or #targeting.candidates(id, spec) >= need) then
			return false
		end
	end
	for _, id in ipairs({ unpack(z.cards) }) do
		local e = entity.get(id)
		log.add("Nothing to do with " .. ((e and cards.def(e) or {}).text or "a copy"))
		zones.purge_card(id)
	end
	return true
end

function M.offer_step()
	local z = zones.find("options")
	if not z then return false end
	-- The offer on the table is answered by whoever holds priority, so hand it to
	-- the seat that asked. Here rather than in the ask, because the ask happens
	-- mid-list and the seat must not move under the rest of that list.
	if #z.cards > 0 then
		if z.asked_seat then stack.give_priority(z.asked_seat) end
		return false
	end
	if phase.is_overlay() then return false end
	-- A card somebody owes holds everything up exactly as an unanswered question
	-- does, and for the same reason: the list that put it in their hands is not
	-- finished until they have played it.
	local todo = zones.todo_pending()
	if todo then return false end
	-- What the question just answered was holding up: the rest of the list that
	-- asked it. Before the queue, because a list that asked and then asked again
	-- wrote its second question first — Abragail's second VOID comes before the
	-- gain her next ability queued behind it.
	--
	-- One per call, because a tail may ask a question of its own, and settle has
	-- to come back round for it.
	if z.after then
		local f = table.remove(z.after, 1)
		if #z.after == 0 then z.after = nil end
		if f.seat then stack.give_priority(f.seat) end
		actions.run(f.action, { card_id = f.card, targets = f.targets or {},
			event = f.event, let = f.let, within = f.within })
		return true
	end
	for tz in entity.each("zone") do
		if tz.status == "todo" and tz.after then
			local f = table.remove(tz.after, 1)
			if #tz.after == 0 then tz.after = nil end
			if f.seat then stack.give_priority(f.seat) end
			actions.run(f.action, { card_id = f.card, targets = f.targets or {},
				event = f.event, let = f.let, within = f.within })
			return true
		end
	end
	if z.pending then
		local ask = table.remove(z.pending, 1)
		if #z.pending == 0 then z.pending = nil end
		-- The tail that was filed behind this one comes with it: it was waiting on
		-- this question and this question is now the one on the table.
		z.after = ask.after
		stack.give_priority(ask.seat)
		actions.run({ ask.action }, { card_id = ask.card, targets = {} })
		return true
	end
	return false
end

-- Cast a card's effect onto the stack instead of running it now — a spell put up
-- to be answered before it lands. The deferral is the whole of what gives a
-- reaction something to react to; a game with no stack zone never calls this and
-- plays exactly as before.
function M.cast(card_id, targets, verb)
	local c = entity.get(card_id)
	if not c or not stack.zone() then return false end
	checkpoint()
	log.add("Cast " .. ((cards.def(c) or {}).text or c.def_key))
	stack.push { verb = verb or "play", action = cards.behaviour(c, "on_play"),
		subject = { card_id }, targets = targets, source = card_id,
		spent = cards.behaviour(c, "spent") }
	M.settle()
	return true
end

-- Answer the top of the stack with one of this card's reactions, played out of
-- turn under priority. It goes on the stack above what it answers, so it too can
-- be answered before it resolves — which is arbitrary depth, LOR and Magic both,
-- for free.
function M.react(card_id, index, targets, payment)
	local z = stack.zone()
	if not z then return false end
	local top_id = z.cards[#z.cards]
	local top = top_id and entity.get(top_id)
	local c = entity.get(card_id)
	if not top or not c then return false end
	-- The same questions the window asked before it offered this: whose card it
	-- is, that this reaction answers announcements by the seat that made this one
	-- ("whose"), and that it has not already answered this record. Asked again
	-- because this is the door every input layer comes through, and only the offer
	-- upstream knew them.
	local seat = zones.active_seat()
	if predicate.seat_of(c) ~= seat or stack.has_answered(top, card_id) then return false end
	local r = cards.reactions(c)[index or 1]
	if not r or not reactions.answers_seat(r, seat, top.re_actor) then return false end
	if not reactions.matches(r, c, top.re_subject, true, top.re_targets) then return false end
	-- Worked out here and sent up with the record, because a reaction's answer
	-- waits: the window it was given closes before the action runs, and a number
	-- about the board is a number about the board *as it was answered*. Derby's
	-- Ultimate is the case -- two mana at an odd number of health -- and reading
	-- it at the bottom of the stack would be reading it after the blow.
	local ctx = predicate.bind(r.compute, { card_id = card_id, targets = targets or {} })
	if not M.can_afford(r.cost, ctx) then return false end
	-- A payment arrives beside the targets and is checked like them: an
	-- interface collected it, but a script, the network or an engine seat may
	-- have, and flow is the one gate all four come through.
	if not M.payment_legal(r.cost, ctx, payment) then return false end
	checkpoint()
	costs.pay(r.cost, ctx, payment)
	log.add(((cards.def(c) or {}).text or c.def_key) .. " in response")
	local rec = stack.push { verb = "play", action = r.action, subject = { card_id },
		event = top.re_subject, targets = targets, source = card_id, spent = r.spent,
		let = ctx.let }
	if rec then rec.re_answering = top.id end
	top.re_answered[#top.re_answered + 1] = card_id
	M.settle()
	return true
end

-- Decline to answer. The passing seat is marked on the top it declined, so the
-- window can tell "everyone able has passed" from "nobody has been asked yet" —
-- and only the first is a resolution.
function M.pass_react()
	local top = M.pending_event()
	local seat = zones.active_seat()
	if not top or not seat then return false end
	checkpoint()
	top.re_passed[seat] = true
	M.settle()
	return true
end

-- An action may hand the turn over (set_active_seat), and the undo history goes
-- with the seat that had it. Closed here rather than in actions, which may not
-- require this file. The same for "emit", which needs the stack and the window.
actions.on_seat_change = M.forget_history
actions.on_emit = M.emit
actions.on_copy_event = M.copy_event
actions.on_redirect = M.redirect
actions.on_counter = M.counterspell

return M
