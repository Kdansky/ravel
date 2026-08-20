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

phase.on_leave = function(pd)
	if pd.tags_set and pd.tags_set.discard_hand then discard_hand(pd) end
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
					if phase.arrived() then actions.run(cur.on_enter, {}) end
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
function M.can_afford(cost, ctx)
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
			if #tags.find_targets({ tag }, { grid = true }) < (tonumber(n) or 0) then
				return false
			end
		elseif not predicate.awaits_targets(subject, ctx)
			-- A cost is "this subject, at least this much" and nothing else, so
			-- it says so through the one condition door rather than carrying a
			-- second comparison of its own. Parsed once per distinct string, and
			-- the set of them is what the game file spends.
			and not predicate.holds(subject .. " >= " .. tostring(n), ctx) then
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
		if stat == "exhaust" then
			local c = ctx and ctx.card_id and entity.get(ctx.card_id)
			if c then c.exhausted = true end
		elseif tag then
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
	if choosing(c) then return true end
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
	if asker and entity.get(asker) then targets = { asker } end
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
	actions.run(cards.behaviour(c, "on_play"), ctx)
	if offer and entity.get(card_id) and entity.get(card_id).zone_id == offer then
		zones.destroy_card(card_id)
	end
	-- An offer outlives its question by nothing: the choices not taken go too,
	-- and the offer forgets what it was for. Leaving them would leave invisible
	-- cards lying over the board, which is a bug this engine has already had
	-- once. Only an "options" zone is cleared — a page overlay deals its own
	-- cards and decides for itself what stays.
	local oz = offer and entity.get(offer)
	if oz and oz.zone_type == "options" then
		local left = {}
		for i, cid in ipairs(oz.cards) do left[i] = cid end
		for _, cid in ipairs(left) do zones.destroy_card(cid) end
		-- Both flags, together: they describe one offer, and leaving the second
		-- behind hands the *next* offer a permission it never asked for. A
		-- promotion opened after the pawn has already moved would then be
		-- declinable, and a pawn would sit on the eighth rank as a pawn.
		oz.asked_by, oz.dismissable = nil, nil
	end
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
	-- Whether abilities work here is the zone's to say, not something to infer
	-- from its shape: a board and a Lost Cities discard both allow it, a hand
	-- and an MTG graveyard both do not, and neither pair shares a zone type.
	local z = entity.get(c.zone_id)
	if not (z and z.tags.activate) then return {} end
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
		if has_ability(a.action) and phase_ok(a.phases)
			and M.can_afford(a.cost, { card_id = card_id })
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

-- Open the chooser for a card that has more than one thing to do. The offer is
-- the same one `options` deals, and it remembers the card that asked, so the
-- menu entry chosen knows whose ability it was.
function M.offer_abilities(card_id)
	local usable = M.usable_abilities(card_id)
	if #usable < 2 then return false end
	local zone_id = zones.find_id("options")
	if not zone_id then return false end
	local owner = (entity.get(card_id).stats or {}).owner
	for _, u in ipairs(usable) do
		local made = cards.create(u.ability.menu_card, zone_id)
		-- Which ability this entry means is written on the entry, not baked into
		-- its definition: *which number* an ability is depends on the zone the
		-- card is lying in, because a zone's "applies" adds to the list. The same
		-- menu card dealt for a rook in a pile and a rook on the board would
		-- otherwise resolve to two different abilities.
		made.stats.ability = u.index
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

-- Decline an offer that may be declined. Answers whether it did, so an input
-- layer can fall through to whatever a right-click otherwise means.
function M.dismiss_offer()
	local z = zones.find("options")
	-- The *open* overlay has to be the offer being dismissed. "An overlay is
	-- open" is not the same question: a reveal stacked on top of an options
	-- phase would otherwise be popped by a click meant for the chooser
	-- underneath it, taking the chooser's cards with it.
	local cur = phase.current()
	if not (z and z.dismissable and cur and cur.type == "overlay" and cur.zone == "options") then
		return false
	end
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
	local left = {}
	for i, cid in ipairs(z.cards) do left[i] = cid end
	for _, cid in ipairs(left) do zones.destroy_card(cid) end
	z.asked_by, z.dismissable = nil, nil
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
	local ctx = { card_id = card_id, targets = targets or {} }
	if not M.can_afford(a.cost, ctx) then return false end
	checkpoint()
	mark_acted(card_id)
	log.add("Activated " .. (def.text or c.def_key)
		.. (a.text and #usable > 1 and (" — " .. a.text) or ""))
	pay(a.cost, ctx)
	actions.run(a.action, ctx)
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

-- An action may hand the turn over (set_active_seat), and the undo history goes
-- with the seat that had it. Closed here rather than in actions, which may not
-- require this file.
actions.on_seat_change = M.forget_history

return M
