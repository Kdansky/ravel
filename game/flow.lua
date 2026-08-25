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
local function pickable(c)
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

-- Where a card goes once its play is over, said by the play block rather than by
-- the action list. **However it ends**: resolved, or countered before it ever
-- ran. An MTG sorcery goes to the graveyard either way, and a Puzzle Strike chip
-- to the table either way, and neither the action nor the counter should have to
-- be the one that remembers.
--
-- Opt-in, so nothing changes for a card that does not say it: declare it and
-- that is where the card lands, leave it out and the action list is answerable
-- for its own card as it always was.
-- Run as the card's *owner*, not as whoever is up. A counter resolves while the
-- answering seat holds priority, and "mine.table" written on my chip has to mean
-- my table however it ended — otherwise being countered posts the card to the
-- player who countered it.
local function send_spent(card_id, spent)
	if not spent then return end
	local c = card_id and entity.get(card_id)
	if not c or not c.zone_id then return end
	zones.as_seat(predicate.seat_of(c), function()
		actions.execute("move_to:" .. spent, { card_id = card_id })
	end)
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
			zones.destroy_card(cid)
		else
			if grave then zones.move_top(hand.id, grave) else zones.destroy_card(cid) end
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

-- A full round completed: each card on a grid zone runs its on_turn actions.
-- Cards at 0 hp are ruined and don't act.
local function run_on_turn()
	for e in entity.each("card") do
		local def = cards.def(e)
		local z   = entity.get(e.zone_id)
		if def.on_turn and z and z.status == "board" and (e.stats.hp or 1) > 0 then
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
		-- Outcomes wait until any open overlay (a pending choice) is closed.
		if rstate ~= "resolved" and (phase.is_overlay() or not fire_end_condition()) then
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
			local zkey = e.zone or def.to_zone or cards.home_zone(def) or "board"
			for _, to in ipairs(zones.all_with_key(zkey)) do
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

-- The card a player most recently played or activated. One at a time, and it
-- lingers until the next thing a player does — which is exactly the window en
-- passant needs, and closes it the instant the opponent does anything at all
-- rather than one turn later.
--
-- A mark on the card rather than a pointer somewhere, because the question a
-- rule asks is "is *this* one it" — about the occupant of some square it is
-- considering — and only a mark composes that way. Being an ordinary stat, it
-- rides undo with everything else: snapshots deep-copy the entities.
--
-- Set from the two player intents and nowhere else. Dealing, drawing and an
-- automatic phase's actions are not somebody acting, and would clobber it
-- between turns.
local function mark_acted(card_id)
	for e in entity.each("card") do
		if e.stats and e.stats.last_acted then e.stats.last_acted = nil end
	end
	local c = card_id and entity.get(card_id)
	if c then
		c.stats = c.stats or {}
		c.stats.last_acted = 1
	end
end

-- True if a cost table like { gold = 2 } can be paid. nil cost = free.
-- "sacrifice:<tag>" entries are paid in board cards instead of stats; every
-- other key is a subject, so it may carry a scope and quantifier
-- ({ "hp@each.follower": 1 } — each follower must have one to give).
-- Lives here rather than in cards because it reads the live entity graph and
-- every caller is a legality gate, and because payment is right below it.
-- **"A plain arrow can be spent as a red one."** The substitution is declared on
-- the *stat* (`pays_for`), not on the cards that might use it, so a cost stays
-- one map of what is owed and nothing has to say twice how it may be settled.
--
-- Working out which pool pays which part of a cost is a matching, and this is
-- the greedy that is exact for the shape games have:
--
--   **the most constrained demand first** — the one fewest pools can serve;
--   **and its own stat before any substitute** — a substitute is by definition
--   the more useful of the two elsewhere.
--
-- MTG's "4 generic and 3 red" is the case that needs both halves: against three
-- red and two blue, spending red on the generic loses a cost that was payable.
-- Red is served by one pool and generic by five, so red is settled first, out
-- of red. `validate` refuses a substitution graph this greedy could get wrong —
-- two pools whose sets overlap without nesting — so what the engine accepts, it
-- pays correctly.
local function stat_name(subject)
	return subject:match("^([^@]+)") or subject
end

local function same_scope(subject, stat)
	return stat .. (subject:match("^[^@]+(@.*)$") or "")
end

-- What is owed, and out of which pools, in the order they should be drained.
-- nil when some part of it cannot be paid.
local function plan(cost, ctx)
	local demands = {}
	for subject, n in pairs(cost or {}) do
		if subject ~= "exhaust" and not subject:match("^sacrifice:") then
			local need = tonumber(n) or 0
			local p    = predicate.parse_subject(subject)
			-- Only a pool takes part in the matching. "each" asks a different
			-- question — *every* member paying, not a total — and substituting
			-- across members would answer neither; a cost the targets pay cannot
			-- be judged before they are chosen. Both are owed exactly as
			-- written, and checked the way they always were.
			if not p or p.quant == "each" or p.fn or predicate.awaits_targets(subject, ctx) then
				demands[#demands + 1] = { subject = subject, need = need, as_written = true }
			else
				local from = { subject }
				for _, s in ipairs((declaration.G.pays_for_index or {})[stat_name(subject)] or {}) do
					from[#from + 1] = same_scope(subject, s)
				end
				demands[#demands + 1] = { subject = subject, need = need, from = from }
			end
		end
	end
	-- Fewest pools first; the key breaks ties, so a seeded replay pays the same
	-- way twice.
	table.sort(demands, function(a, b)
		local na, nb = a.from and #a.from or 1, b.from and #b.from or 1
		if na ~= nb then return na < nb end
		return a.subject < b.subject
	end)
	local left, out = {}, {}
	for _, d in ipairs(demands) do
		local owed = d.need
		if d.as_written then
			if not predicate.awaits_targets(d.subject, ctx)
				and not predicate.holds(d.subject .. " >= " .. tostring(owed), ctx) then
				return nil
			end
			out[#out + 1] = { subject = d.subject, n = owed }
		else
			for _, src in ipairs(d.from) do
				if owed <= 0 then break end
				if left[src] == nil then left[src] = predicate.total(src, ctx) end
				local take = math.min(owed, left[src])
				if take > 0 then
					left[src] = left[src] - take
					out[#out + 1] = { subject = src, n = take }
					owed = owed - take
				end
			end
			if owed > 0 then return nil end
		end
	end
	return out
end

-- The parts of a cost that are not stats and so have no substitutes: a card
-- spending itself, and a card spending somebody else.
local function extras_afford(cost, ctx)
	for subject, n in pairs(cost or {}) do
		local tag = type(subject) == "string" and subject:match("^sacrifice:(.+)$")
		-- Tapping, in the MTG sense: the card spends *itself* being ready. A
		-- card already spent cannot pay it, which is the whole of "once per
		-- round" — and saying it as a cost rather than as a consequence is what
		-- lets one card have an ability that taps beside one that does not.
		if subject == "exhaust" then
			local c = ctx and ctx.card_id and entity.get(ctx.card_id)
			if not c or c.exhausted then return false end
		elseif tag then
			if #tags.find_targets({ tag }, tags.IN_PLAY) < (tonumber(n) or 0) then
				return false
			end
		end
	end
	return true
end

function M.can_afford(cost, ctx)
	return extras_afford(cost, ctx) and plan(cost, ctx) ~= nil
end

-- Pay a cost: stats are spent through their subject (so a scope and
-- quantifier are honoured), "sacrifice:<tag>" entries destroy board cards
-- carrying the tag (oldest first — affordability was already checked).
-- Keys are walked in sorted order, never pairs: clamping makes payment order
-- observable, and a seeded replay has to pay identically.
local function pay(cost, ctx)
	-- The same planner can_afford asked, so the two cannot disagree about which
	-- pool settles which part.
	for _, step in ipairs(plan(cost, ctx) or {}) do
		actions.spend(step.subject, step.n, ctx)
	end
	local subjects = {}
	for k in pairs(cost or {}) do
		if k == "exhaust" or k:match("^sacrifice:") then subjects[#subjects + 1] = k end
	end
	table.sort(subjects)
	for _, stat in ipairs(subjects) do
		local n   = cost[stat]
		local tag = stat:match("^sacrifice:(.+)$")
		if stat == "exhaust" then
			local c = ctx and ctx.card_id and entity.get(ctx.card_id)
			if c then c.exhausted = true end
		elseif tag then
			for _ = 1, n do
				local ids = tags.find_targets({ tag }, tags.IN_PLAY)
				if #ids == 0 then break end
				local victim = entity.get(ids[1])
				local vdef   = cards.def(victim)
				log.add("Sacrificed " .. (vdef and vdef.text or victim.def_key))
				zones.destroy_card(victim.id)
			end
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
	-- A card lying in an open offer is the answer to the question the offer is,
	-- and the gates below are about playing a card from a hand. The one thing
	-- that may still refuse it is the asking card saying which of them it will
	-- take — "trash their *largest gem*" opens the whole hand and accepts one
	-- card out of it, and without this the whole hand was acceptable.
	if choosing(c) then return pickable(c) end
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
	if not M.can_afford(def.cost, { card_id = card_id }) then return false end
	if predicate.meets_all(def.needs, { card_id = card_id }) then return true end
	local z = entity.get(c.zone_id)
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
		if cid ~= card_id and playable(cards.def(entity.get(cid)), { card_id = cid }) then
			return false
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
local function clear_offer(oz)
	local left = {}
	for i, cid in ipairs(oz.cards) do left[i] = cid end
	for _, cid in ipairs(left) do
		local c    = entity.get(cid)
		local home = c and c.borrowed_from
		if home and entity.get(home) then
			c.borrowed_from = nil
			zones.move_card(cid, home)
		else
			zones.destroy_card(cid)
		end
	end
	oz.asked_by, oz.dismissable = nil, nil
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
function M.play_card(card_id, targets)
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
	if asker and entity.get(asker) and not lent then targets = { asker } end
	local ctx = { card_id = card_id, targets = targets or {} }
	-- A cost the targets pay could not be judged before they were chosen.
	if not overlay and not M.can_afford(def.cost, ctx) then return false end
	checkpoint()
	log.add((overlay and "Chose " or "Played ") .. (def.text or c.def_key))
	local pl = player()
	-- An overlay is a phase of its own, and the counter that bounds a hand
	-- belongs to the phase underneath it: counting a choice as a play would end
	-- that phase early, since the count survives the pop.
	if pl and not overlay then pl.stats.plays = (pl.stats.plays or 0) + 1 end
	if not overlay then pay(def.cost, ctx) end
	-- A choice taken out of an offer is not a card acting, it is the card that
	-- opened the offer still acting — so the mark stays where it was.
	if not overlay then mark_acted(card_id) end
	if overlay then phase.pop() end
	local before = phase.current()
	-- Through behaviour, so a zone can grant what playing a card lying in it
	-- does — which is how one offer deals a card the game has other plans for.
	local lender = lent and asker and entity.get(asker)
	if lender then
		actions.run(cards.behaviour(lender, "on_chosen"), { card_id = asker, targets = { card_id } })
	elseif not M.defer_play(card_id, targets) then
		-- Unless the play was put up to be answered, in which case it happens when
		-- the stack says so and not before — and the spending goes with it.
		actions.run(cards.behaviour(c, "on_play"), ctx)
		send_spent(card_id, cards.behaviour(c, "spent"))
	end
	-- A borrowed card is not spent by being picked: clear_offer sends whatever
	-- is left home, and that includes this one when the rule did not move it.
	if offer and not lent and entity.get(card_id) and entity.get(card_id).zone_id == offer then
		zones.destroy_card(card_id)
	end
	-- An offer outlives its question by nothing. Only an "options" zone is
	-- cleared — a page overlay deals its own cards and decides for itself what
	-- stays.
	local oz = offer and entity.get(offer)
	if oz and oz.status == "offer" then clear_offer(oz) end
	if tags.entity_has(c, "no_undo") then
		history = {}
		log.add("— no turning back —")
	end

	-- A phase with a play limit ends itself once it's reached (MTG-style:
	-- the phase's own rule, not the card's). Discarding is the on_leave
	-- hook's job, so card-driven next_phase gets the same treatment.
	local cur = phase.current()
	if not overlay and not actions.pending_load and cur == before and cur and cur.ends_after
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
-- Which of a card's abilities may be used right now, in the order it declared
-- them. A card is clickable when this is not empty, and when it holds more than
-- one the player is asked which — the chooser exists because the answer stopped
-- being obvious, not because every card wants one.
--
-- Exhaustion is not asked here any more: it is a cost, and "exhaust" is checked
-- like the rest. A card with a tap ability beside a free one keeps offering the
-- free one after the first is spent, which is half the reason it moved.
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
	local out = {}
	for i, a in ipairs(cards.abilities(c)) do
		-- An ability that can reach nothing is not on offer. Without this a
		-- chooser lists dead entries, and a piece with a conditional move looks
		-- like it has two things to do when it has one. It used to ask only
		-- about `moves`, which is one kind of target out of three: The Crew's
		-- radio has twelve abilities and a hand answers two or three of them,
		-- so the other nine were nine dead lines in the chooser.
		local lo = a.target and select(1, targeting.bounds(a.target)) or 0
		local reaches = lo == 0
			or (a.target.moves and #targeting.moves_by(card_id, a.target.moves) > 0)
			or (a.target.moves == nil and #targeting.candidates(card_id, a.target) >= lo)
		local ctx = predicate.bind(a.compute, { card_id = card_id })
		if has_ability(a.action) and phase_ok(a.phases)
			and predicate.meets_all(a.when, ctx)
			and M.can_afford(a.cost, ctx)
			and reaches then
			out[#out + 1] = { index = i, ability = a }
		end
	end
	return out
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

-- Deal one menu entry per choice into the offer and open it. Two things a card
-- gets asked about — which of its abilities to use, and which of its reactions
-- to answer with — and they differ only in the word written on the entry.
--
-- Which one an entry means is written on the entry, not baked into its
-- definition: *which number* an ability is depends on the zone the card is lying
-- in, because a zone's "applies" adds to the list. The same menu card dealt for a
-- rook in a pile and a rook on the board would otherwise resolve to two
-- different abilities.
local function offer_choices(card_id, picks, stat)
	if #picks < 2 then return false end
	local zone_id = zones.find_id("options")
	if not zone_id then return false end
	local owner = (entity.get(card_id).stats or {}).owner
	for _, p in ipairs(picks) do
		local made = cards.create(p.menu_card, zone_id)
		made.stats[stat] = p.index
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
	local picks = {}
	for _, u in ipairs(M.usable_abilities(card_id)) do
		picks[#picks + 1] = { menu_card = u.ability.menu_card, index = u.index }
	end
	return offer_choices(card_id, picks, "ability")
end

-- The same for a card that answers the open window more than one way. Rare, and
-- the reason the chooser is reused rather than a second surface invented: a
-- window is a player_input phase so the board stays visible, and only the one
-- card that needs a question asked about it opens an overlay.
function M.offer_reactions(card_id)
	local picks = {}
	for _, u in ipairs(M.usable_reactions()) do
		if u.card == card_id then
			picks[#picks + 1] = { menu_card = u.reaction.menu_card, index = u.index }
		end
	end
	return offer_choices(card_id, picks, "reaction")
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
	if not (def and def.menu_for) then return nil end
	local z = c.zone_id and entity.get(c.zone_id)
	local source = z and z.asked_by
	if not (source and entity.get(source)) then return nil end
	-- Which list the entry points into is the entry's own word. The two indices
	-- are into different lists and would collide if one stat carried both.
	local ridx = (c.stats or {}).reaction
	if ridx and ridx > 0 then
		local r = (cards.reactions(entity.get(source)) or {})[ridx]
		return r and { source = source, index = ridx, reaction = r } or nil
	end
	local idx = (c.stats or {}).ability
	local a = idx and (cards.abilities(entity.get(source)) or {})[idx]
	return a and { source = source, index = idx, ability = a } or nil
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
function M.activate(card_id, targets, index)
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
	local a   = chosen.ability
	local c   = entity.get(card_id)
	local def = cards.def(c)
	-- Flow is the single legality gate, exactly as in play_card: target counts
	-- are enforced here, not only in the input layers, so scripts and the
	-- debug API can't skip them.
	local lo, hi = targeting.bounds(a.target)
	if #(targets or {}) < lo or #(targets or {}) > hi then return false end
	if not targets_legal(card_id, a.target, targets) then return false end
	local ctx = predicate.bind(a.compute, { card_id = card_id, targets = targets or {} })
	if not M.can_afford(a.cost, ctx) then return false end
	checkpoint()
	mark_acted(card_id)
	log.add("Activated " .. (def.text or c.def_key)
		.. (a.text and #usable > 1 and (" — " .. a.text) or ""))
	pay(a.cost, ctx)
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
		if seats[e.def_key] and e.zone_id and (e.stats.won or 0) > 0 then return e.def_key end
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
function M.winner()
	local won = victor()
	local def = won and declaration.G.card_defs[won]
	return won and ((def and def.text) or won) or nil
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
			if not (def and def.hidden) then
				out[#out + 1] = (def and def.label or key) .. " " .. predicate.total(def and def.subject or key)
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
function M.can_activate_zone(zone_id)
	local z = entity.get(zone_id)
	if not z or not has_ability(z.on_activate) then return false end
	-- A per-seat zone answers to its seat, which is what `reachable` says for a
	-- card. A shared zone belongs to nobody and answers to whoever is playing.
	if z.seat and z.seat ~= zones.active_seat() then return false end
	if not phase_ok(z.activate_phases) then return false end
	if window_locked() then return false end
	return M.can_afford(z.activate_cost, { zone_id = zone_id })
end

function M.activate_zone(zone_id)
	if phase.is_overlay() then return false end   -- a pending choice locks other actions
	if not M.can_activate_zone(zone_id) then return false end
	local z   = entity.get(zone_id)
	local ctx = { zone_id = zone_id }
	checkpoint()
	-- A zone is nothing card-shaped, so the last thing a player did was not to a
	-- card and nothing carries the mark. Leaving a stale one would keep a window
	-- open through a draw.
	mark_acted(nil)
	log.add("Used " .. (z.label or z.key))
	pay(z.activate_cost, ctx)
	actions.run(z.on_activate, ctx)
	M.settle()
	return true
end

-- The response window, driven by settle.
--
-- The stack is a zone tagged "stack", top (last) first. **Nothing on it is a game
-- card.** Every entry is an "event" record standing for something announced, and
-- the card that announced it stays where it was — in a hand, on a table, wherever
-- the play found it. That is the whole of what keeps a counter from having to
-- know the rules: it removes a record, and the card it was about was never moved
-- in the first place, so there is nothing to put back.
--
-- The record carries what it needs to resolve later (re_action, re_event,
-- re_subject, re_actor, re_targets, re_spent), which the deep-copy snapshot keeps
-- across undo for free. Priority — who is acting right now — moves to whoever may
-- answer while the turn stays put, so the reactor pays from their own pool and
-- acts on their own cards (see zones.active_seat).
local function stack_zone()
	for z in entity.each("zone") do
		if z.tags.stack then return z end
	end
end

-- Put an effect up to be answered instead of running it, as a record of its own.
-- Two things that read alike and are not the same ride on it: re_event is what
-- the deferred action reads as @event (a spell answers itself, a counter answers
-- what it was played on), and re_subject is what *answering this record* would be
-- about. They differ exactly where the record stands for an answer rather than a
-- move — a reaction is answered as itself and acts on what it replied to.
--
-- re_source is the card that announced it, which is what "self" means to the
-- deferred action, and re_spent is where that card goes once this is over,
-- however it ends.
-- Deep enough that no real game reaches it, shallow enough to stop before
-- settle's own budget does — so a runaway says what it is rather than "phase
-- routing". A reaction that answers its own controller ("whose": "mine") is
-- what makes this reachable at all: one card may answer a record once, but the
-- answer is a new record, and a mandatory one that never leaves the board would
-- answer its own answer forever.
local STACK_LIMIT = 32

local function push_event(z, verb, action, subject, event, targets, source, spent, let)
	if #z.cards >= STACK_LIMIT then
		local msg = "!! the stack reached " .. STACK_LIMIT
			.. " — a reaction is answering its own answer; stopped"
		log.add(msg)
		print(msg)
		return
	end
	local c = zones.add(z, "event")
	if not c then return end
	c.re_action, c.re_verb    = action or {}, verb
	c.re_subject, c.re_event  = subject, event
	c.re_targets, c.re_let    = targets or {}, let
	c.re_source, c.re_spent   = source, spent
	c.re_actor, c.re_passed   = zones.active_seat(), {}
	-- Which cards have already answered this. The stack no longer holds the cards
	-- played to it, so nothing takes a reaction out of the hand it came from and
	-- it would otherwise answer the same announcement forever.
	--
	-- A list, not a set keyed by card: a state goes through JSON on its way to a
	-- save file and to the other client, and there a number key comes back a
	-- string. A set would quietly forget who had answered exactly when the game
	-- was reloaded or resynced.
	c.re_answered = {}
	return c
end

local function has_answered(top, card_id)
	for _, id in ipairs(top.re_answered) do
		if id == card_id then return true end
	end
	return false
end

-- Move priority (who acts) to a seat, dropping undo history at the boundary the
-- way a handover does: a reaction is not the turn player's move to take back, and
-- undoing across it would rewrite a decision that was not theirs.
local function react_priority(seat)
	local sys = system_card()
	if not sys then return end
	local i = (seat and declaration.G.seat_index[seat]) or 0
	if (sys.stats.priority or 0) ~= i then
		sys.stats.priority = i
		history = {}
	end
end

-- Which record is running right now, so "counterspell" written in a reaction can
-- find what that reaction was an answer to. Transient by design: it lives for one
-- action run and never reaches a snapshot, because there is no moment between two
-- players' inputs at which anything is resolving.
local resolving = nil

-- The top of the stack resolves: run what it deferred, spend the card that
-- announced it, and the record is done. Its action reads @event as what it
-- answered (a spell answers itself), so a counter whose action reads the event
-- reaches the thing it was played on. Resolved as its own controller, so "mine"
-- in the effect is the caster rather than whoever answered last.
--
-- "self" is the card that raised it: a record stands for something a card did,
-- and "destroy_self" in a deferred crash means the chip that crashed, not the
-- record standing in for it.
--
-- The record always goes, with no question about whether it moved itself —
-- nothing on the stack is a game card, so there is nothing a game action could
-- have moved.
local function resolve_top(top)
	react_priority(top.re_actor)
	mark_acted(nil)
	local prev = resolving
	resolving  = top
	actions.run(top.re_action, { card_id = top.re_source,
		event = top.re_event, targets = top.re_targets, let = top.re_let })
	resolving  = prev
	send_spent(top.re_source, top.re_spent)
	zones.destroy_card(top.id)
end

-- counterspell — what this reaction answers does not happen: its record comes off
-- the stack and the deferred action never runs.
--
-- **It names no zone, and that is the point.** The card that was countered never
-- went anywhere — the stack holds records, not cards — so there is nothing to put
-- back, and where a spent card lands was already said by its own "spent". A
-- counter that had to know where chips go would need half the rules of every game
-- it appears in.
function M.counterspell()
	local answered = resolving and resolving.re_answering and entity.get(resolving.re_answering)
	if not answered then return end
	send_spent(answered.re_source, answered.re_spent)
	zones.destroy_card(answered.id)
end

-- A forced reaction is not a question: it fires the moment it matches, and only
-- its own cost and "when" can stop it. Magic's mandatory triggered ability, and
-- the reason "forced" is an enum rather than a boolean: "you may" and "it must"
-- are both triggered abilities, and the difference is all this field says.
--
-- Fired here rather than through M.react, which checkpoints and settles — this
-- runs inside settle already. One thing it declines to do on its own: a reaction
-- that has to be aimed is a question after all, so it is offered like any other
-- rather than the engine choosing a target for the player.
local function fire_forced(z, top, r)
	local c = entity.get(r.card)
	if not reactions.matches(r.reaction, c, top.re_subject, true) then return false end
	if not M.can_afford(r.reaction.cost, { card_id = r.card }) then return false end
	if r.reaction.target and select(1, targeting.bounds(r.reaction.target)) > 0 then return false end
	pay(r.reaction.cost, { card_id = r.card })
	log.add(((cards.def(c) or {}).text or c.def_key) .. " triggers")
	local rec = push_event(z, "play", r.reaction.action, { r.card }, top.re_subject, {},
		r.card, r.reaction.spent)
	-- Marked as having had its go either way. A refused push is the stack at its
	-- limit, and a trigger that fires again on the record it just failed on is
	-- the runaway this bound exists to stop: saying it has answered lets the
	-- window move past it and unwind, instead of burning settle's budget too.
	top.re_answered[#top.re_answered + 1] = r.card
	if not rec then return false end
	rec.re_answering = top.id
	return true
end

-- One step of the response protocol, called by settle each loop. Returns
-- "waiting" (a seat must answer — stop and wait), "resolved" (an item ran — loop
-- again), or "idle" (no stack; proceed as normal, which is every existing game).
function M.react_step()
	local z = stack_zone()
	if not z then return "idle" end
	-- Something is interjected — an offer, a phase a reaction handed to the seat
	-- that played it — and resolving the rest of the stack under it would run the
	-- turn player's deferred effects while somebody else is still mid-answer. The
	-- interjection is *part* of resolving the record that opened it, so nothing
	-- below it moves until it pops.
	if phase.depth() > 1 then return "waiting" end
	local top_id = z.cards[#z.cards]
	if not top_id then
		-- The window is closed, but priority is not the stack's to give back while
		-- something else still holds it. A phase interjected mid-answer — an offer,
		-- a buy handed to the seat that just reacted — is up because *they* are, and
		-- popping the last record out from under it would hand their phase to the
		-- turn player. Priority is released when nothing wants it, and that is the
		-- whole of the rule: one seat stat, no second answer to "who is acting".
		if phase.depth() <= 1 then react_priority(nil) end
		return "idle"
	end
	local top = entity.get(top_id)
	-- Anyone who may still answer this top: a responder that answers this seat's
	-- announcements at all ("whose"), has not passed on it, and has not already
	-- answered it. The last of those three is what makes "everyone passed" a
	-- state that arrives — one card, one answer, per record — and it is what
	-- lets a reaction answer its own controller without the two of them going
	-- back and forth forever.
	for _, r in ipairs(reactions.responders(top.re_verb, top.re_subject)) do
		if reactions.answers_seat(r.reaction, r.seat, top.re_actor)
			and not top.re_passed[r.seat] and not has_answered(top, r.card) then
			react_priority(r.seat)
			-- Forced first, and as that seat: it costs them and acts on their
			-- cards, so priority has to have moved before it fires. A forced one
			-- that cannot pay falls through and the seat is asked as usual, which
			-- is the honest answer — it did not fire, and they may still have
			-- something else.
			if r.reaction.forced == "mandatory" and fire_forced(z, top, r) then return "resolved" end
			return "waiting"
		end
	end
	resolve_top(top)
	return "resolved"
end

-- Cast a card's effect onto the stack instead of running it now — a spell put up
-- to be answered before it lands. The deferral is the whole of what gives a
-- reaction something to react to; a game with no stack zone never calls this and
-- plays exactly as before.
function M.cast(card_id, targets, verb)
	local c = entity.get(card_id)
	local z = stack_zone()
	if not c or not z then return false end
	checkpoint()
	log.add("Cast " .. ((cards.def(c) or {}).text or c.def_key))
	push_event(z, verb or "play", cards.behaviour(c, "on_play") or {}, { card_id }, { card_id },
		targets, card_id, cards.behaviour(c, "spent"))
	M.settle()
	return true
end

-- Whether playing this card is put up to be answered rather than done. A card
-- announces itself through "emits" at the "play" moment — its own word or, far
-- more usefully, a tag's — and until an announcement is settled the play has not
-- happened.
--
-- What goes up is a record, never the card. The card stays in the hand it was
-- played from until the record resolves, which is the honest state: it has been
-- announced and nothing has happened yet. Where it lands afterwards is its "spent"
-- and nothing else's, so a counter can end this without knowing where chips go.
--
-- Only when a reply actually exists. Nobody able to answer means the play is the
-- play it always was, which is every card in every game that emits nothing, and
-- the caster is not counted: answering your own spell here would open a window
-- react_step then finds nobody to hold.
function M.defer_play(card_id, targets)
	local c = entity.get(card_id)
	local z = c and stack_zone()
	if not z then return false end
	for _, verb in ipairs(cards.emits(c, "play")) do
		if reactions.anyone_answers(verb, { card_id }, zones.active_seat()) then
			push_event(z, verb, cards.behaviour(c, "on_play") or {}, { card_id }, { card_id },
				targets, card_id, cards.behaviour(c, "spent"))
			return true
		end
	end
	return false
end

-- The same for using an ability, and the difference is only what is spent. Both
-- put up a record and neither moves the card; an activated card was not played,
-- only used, so nothing is spent when the record resolves. That is the whole of
-- why the two moments are asked separately: one card can be a "cast" from hand
-- and an "ability" from the board, and a reaction to one must not catch the other.
function M.defer_activation(card_id, ability, ctx)
	for _, verb in ipairs(cards.emits(entity.get(card_id), "activate")) do
		if M.emit(verb, { card_id }, ability.action, card_id, ctx) then return true end
	end
	return false
end

-- Raise an event nothing was played to cause: a crash, a summon, a buy. The verb
-- says what happened and the subject carries the tags a reaction reads, so the
-- emitter still names nobody who might answer.
--
-- What is deferred is whatever the emitter handed over — the rest of the crash,
-- the ability's effect — waiting to see whether it is countered. Nothing answers
-- → false, and the caller simply runs it now, which is Filter A and is why an
-- emit costs a game with no reactions exactly nothing.
--
-- The ctx rides along, because an action deferred is the same action: its targets
-- were chosen before the window opened, and any compute it bound was worked out
-- against the board as it stood then.
function M.emit(verb, subject, action, source, ctx)
	local z = stack_zone()
	if not z or not reactions.anyone_answers(verb, subject, zones.active_seat()) then return false end
	return push_event(z, verb, action, subject, subject, ctx and ctx.targets, source, nil,
		ctx and ctx.let) ~= nil
end

-- What is waiting to be answered, if anything. An input layer has to ask,
-- because a response window looks like nothing from the outside: the turn has
-- not moved and the phase has not changed, and the only thing that did is who
-- may act. nil is every game without a stack and every moment its stack is empty.
function M.pending_event()
	local z = stack_zone()
	local top = z and z.cards[#z.cards]
	return top and entity.get(top)
end

-- What the seat holding priority may answer the top of the stack with, as
-- { card, index, reaction }. This is usable_abilities for the response window,
-- and it is asked for the same reason: an interface offers what this returns and
-- refuses to guess past it.
--
-- Cost is weighed here rather than in reactions.matches, which answers a
-- different question — whether the reaction answers this event at all. The
-- window opens on that; what is on offer inside it is this.
function M.usable_reactions()
	local top = M.pending_event()
	local seat = zones.active_seat()
	if not top then return {} end
	local out = {}
	-- Strict: this is what the answering seat is offered, and they can see their
	-- own cards. The window may have opened on a card that only *might* be in
	-- their hand — that is what keeps the prompt from being evidence — but
	-- offering them one that is really in their bag would be a lie to their face.
	for _, r in ipairs(reactions.responders(top.re_verb, top.re_subject, true)) do
		if r.seat == seat and reactions.answers_seat(r.reaction, seat, top.re_actor)
			and not has_answered(top, r.card)
			and M.can_afford(r.reaction.cost, { card_id = r.card }) then
			out[#out + 1] = { card = r.card, index = r.index, reaction = r.reaction }
		end
	end
	return out
end

-- Whether this card is one of the answers on offer. The renderer asks, because a
-- card that may answer must not be drawn dead: inside a window it is neither
-- playable nor activatable, and both of those say "dim" at the very moment it is
-- being asked for.
function M.can_react(card_id)
	for _, u in ipairs(M.usable_reactions()) do
		if u.card == card_id then return true end
	end
	return false
end

-- The reaction a bare click means: the only one this card offers. With several
-- the caller has to have chosen, exactly as with abilities — and nothing yet
-- asks, so a card offering two is unreachable from the GUI.
function M.sole_reaction(card_id)
	local only
	for _, u in ipairs(M.usable_reactions()) do
		if u.card == card_id then
			if only then return nil end
			only = u
		end
	end
	return only
end

-- Answer the top of the stack with one of this card's reactions, played out of
-- turn under priority. It goes on the stack above what it answers, so it too can
-- be answered before it resolves — which is arbitrary depth, LOR and Magic both,
-- for free.
function M.react(card_id, index, targets)
	local z = stack_zone()
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
	if predicate.seat_of(c) ~= seat or has_answered(top, card_id) then return false end
	local r = cards.reactions(c)[index or 1]
	if not r or not reactions.answers_seat(r, seat, top.re_actor) then return false end
	if not reactions.matches(r, c, top.re_subject, true) then return false end
	if not M.can_afford(r.cost, { card_id = card_id }) then return false end
	checkpoint()
	pay(r.cost, { card_id = card_id })
	log.add(((cards.def(c) or {}).text or c.def_key) .. " in response")
	local rec = push_event(z, "play", r.action, { card_id }, top.re_subject, targets, card_id, r.spent)
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
actions.on_counter = M.counterspell

return M
