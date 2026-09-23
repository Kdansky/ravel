-- **The stack: what has been announced and is waiting to be answered.** Records
-- go up, priority moves to whoever may answer, forced answers fire, and the top
-- resolves once everyone able has passed. Settle drives it. Flow keeps the three
-- things about it that are a player's move — casting, answering and passing —
-- because a move checkpoints and settles, and those are flow's.
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

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local targeting   = require("targeting")
local predicate   = require("predicate")
local reactions   = require("reactions")
local log         = require("log")
local costs       = require("costs")

local M = {}

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

-- The record's own fields, named. It was nine positional arguments in the order
-- they happened to be written, which meant a caller with nothing to say about
-- the second-to-last still had to write a nil for it, and a reader had to count
-- commas to find out which of two card ids was the subject.
--
-- The zone is worked out here rather than handed in. Every caller asked
-- stack_zone() for it and passed the answer straight back, which is a thing the
-- callee already knows how to find.
local function push_event(e)
	local z = stack_zone()
	if not z then return end
	if #z.cards >= STACK_LIMIT then
		local msg = "!! the stack reached " .. STACK_LIMIT
			.. " — a reaction is answering its own answer; stopped"
		log.add(msg)
		print(msg)
		return
	end
	local c = zones.add(z, "event")
	if not c then return end
	c.re_action, c.re_verb    = e.action or {}, e.verb
	-- The subject is what the record is *about*; the event is what a deferred
	-- action reads as @event. They are the same thing except where the record
	-- stands for an answer rather than a move, so one defaults to the other.
	c.re_subject              = e.subject
	c.re_event                = e.event or e.subject
	c.re_targets, c.re_let    = e.targets or {}, e.let
	-- The standing each target had when it was aimed at, so a record that waits
	-- while the board changes resolves against what is still what was pointed at.
	-- Taken here when the caller has none, which is every announcement that *is*
	-- the aim; a play pins before answering the aim and hands its own down.
	c.re_aimed                = e.aimed or predicate.standing(c.re_targets)
	c.re_source, c.re_spent   = e.source, e.spent
	-- Which of the source's abilities this is, when it is one. Only a key, so it
	-- costs a snapshot nothing — and it is the only way back to what the thing may
	-- be aimed at, which "redirect" has to know. A play record needs none: its
	-- spec is the source card's own.
	c.re_ability              = e.ability
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
-- undoing across it would rewrite a decision that was not theirs. The same is
-- true of a question asked of somebody else, which is the other caller.
local function give_priority(seat)
	local sys = zones.system_card()
	if not sys then return end
	local i = (seat and declaration.G.seat_index[seat]) or 0
	if (sys.stats.priority or 0) ~= i then
		sys.stats.priority = i
		if actions.on_seat_change then actions.on_seat_change() end
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
-- and "purge:self" in a deferred crash means the chip that crashed, not the
-- record standing in for it.
--
-- The record always goes, with no question about whether it moved itself —
-- nothing on the stack is a game card, so there is nothing a game action could
-- have moved.
local function resolve_top(top)
	give_priority(top.re_actor)
	cards.mark_acted(nil)
	local prev = resolving
	resolving  = top
	actions.run(top.re_action, { card_id = top.re_source,
		event = top.re_event, targets = top.re_targets, aimed = top.re_aimed,
		let = top.re_let, answering = top.re_answering })
	resolving  = prev
	send_spent(top.re_source, top.re_spent)
	zones.purge_card(top.id)
end

-- Say it again, aimed as it already was. A record is the one thing a copy needs
-- no help with: it went up carrying its targets, so there is nothing to ask and
-- nothing to imagine — the same announcement, a second time.
--
-- What does not come with it is "spent". The card that announced it is spent
-- once, however many times the announcement happens; the copy is spent nowhere,
-- exactly as an imaginary card is. Nor does the actor: push_event stamps whoever
-- is up, which during a reaction is the seat copying — the copy is theirs, the
-- way a copied play belongs to the copier.
function M.copy_event(record_id)
	local top = entity.get(record_id)
	if not (top and top.re_action) then return false end
	return push_event { verb = top.re_verb, action = top.re_action,
		subject = top.re_subject, event = top.re_event, targets = top.re_targets,
		aimed = top.re_aimed, source = top.re_source, let = top.re_let } ~= nil
end

-- What a record may be aimed at: the spec whoever announced it was answering.
-- A play record's is the source card's own; an ability record's is the ability
-- it names, which is why the key rides along.
local function aim_spec(top)
	local src = top.re_source and entity.get(top.re_source)
	local def = src and cards.def(src)
	if not def then return nil end
	if not top.re_ability then return def.play and def.play.target end
	for _, a in ipairs(cards.abilities(src) or {}) do
		if a.key == top.re_ability then return a.target end
	end
end

-- Aim it somewhere else. The announcement stands and its effect is unchanged;
-- only what it is pointed at moves, which is what "hits Jandra instead" means
-- and what a counter would get wrong by removing the whole thing.
--
-- **Legal by the announcement's own rule, not the redirector's.** What may be
-- aimed at is the spec of the thing announced, asked of the board as it stands
-- now — so a card cannot launder a spell onto something the spell could never
-- have chosen, and a redirect with nothing legal to offer changes nothing rather
-- than half of it.
function M.redirect(record_id, ids)
	local top = entity.get(record_id)
	if not (top and top.re_action) then return false end
	local spec = aim_spec(top)
	if not spec then
		log.add("! redirect: nothing says what this announcement may be aimed at")
		return false
	end
	local lo, hi = targeting.bounds(spec)
	local pool, kept = targeting.candidates(top.re_source, spec), {}
	for _, id in ipairs(ids) do
		for _, ok in ipairs(pool) do
			if ok == id then kept[#kept + 1] = id break end
		end
	end
	if #kept < lo or #kept > hi then
		log.add("! redirect: " .. #kept .. " of those may be aimed at, and it wants "
			.. lo .. (hi ~= lo and (" to " .. hi) or ""))
		return false
	end
	top.re_targets = kept
	-- Re-pinned, not carried: a redirect re-ran the candidate walk, so these are
	-- cards that may be aimed at *now* and the standing they have now is the one
	-- the aim was made against.
	top.re_aimed   = predicate.standing(kept)
	log.add("Redirected " .. ((cards.def(entity.get(top.re_source) or {}) or {}).text or "it"))
	return true
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
	zones.purge_card(answered.id)
end

-- What the window does when it reaches a forced reaction: "fire" on its own,
-- "ask" after all, or "no" — stand aside and let the window carry on past it.
--
-- The three are separate because only the middle one is a question, and treating
-- the last one as a question is how a trigger got lost. `responders` reads
-- *loosely* — a card face down in a bag might be the same card in a hand, and
-- opening on what is publicly possible is what keeps a prompt from being
-- evidence. A forced reaction fires by itself and leaks nothing either way, so a
-- maybe-there one is not a question: it is nothing, and asking the seat about it
-- spends the answer they had not been offered yet.
local function forced_verdict(top, r)
	local c = entity.get(r.card)
	if not reactions.matches(r.reaction, c, top.re_subject, true, top.re_targets) then return "no" end
	if not costs.can_afford(r.reaction.cost, { card_id = r.card }) then return "no" end
	-- A forced reaction that has to be aimed is a question after all, so it is
	-- offered like any other rather than the engine choosing a target.
	if r.reaction.target and select(1, targeting.bounds(r.reaction.target)) > 0 then return "ask" end
	return "fire"
end

-- A forced reaction is not a question: it fires the moment it matches, and only
-- its own cost and "when" can stop it. Magic's mandatory triggered ability, and
-- the reason "forced" is an enum rather than a boolean: "you may" and "it must"
-- are both triggered abilities, and the difference is all this field says.
--
-- Fired here rather than through flow.react, which checkpoints and settles — this
-- runs inside settle already. Its verdict is `forced_verdict`'s, asked first.
local function fire_forced(top, r)
	local c = entity.get(r.card)
	costs.pay(r.reaction.cost, { card_id = r.card })
	log.add(((cards.def(c) or {}).text or c.def_key) .. " triggers")
	local rec = push_event { verb = "play", action = r.reaction.action, subject = { r.card },
		event = top.re_subject, source = r.card, spent = r.reaction.spent }
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
-- Priority is released when nothing wants it, and that is the whole of the rule:
-- one seat stat, no second answer to "who is acting". Two things can want it —
-- a record on the stack waiting to be answered, and a question waiting to be
-- asked — and a phase interjected mid-answer is up because *that* seat is, so
-- nothing is given back under one.
--
-- Written here rather than on the stack's way past, which is where it used to
-- live: a game with no stack zone never went past, so an offer that took
-- priority would have kept it.
function M.release_priority()
	if phase.depth() > 1 then return end
	local sz = stack_zone()
	if sz and #sz.cards > 0 then return end
	local oz = zones.find("options")
	if oz and (oz.pending or oz.after or #oz.cards > 0) then return end
	give_priority(nil)
end

function M.react_step()
	local z = stack_zone()
	if not z then return "idle" end
	local top_id = z.cards[#z.cards]
	if not top_id then
		return "idle"
	end
	-- Something is interjected — an offer, a phase a reaction handed to the seat
	-- that played it — and resolving the rest of the stack under it would run the
	-- turn player's deferred effects while somebody else is still mid-answer. The
	-- interjection is *part* of resolving the record that opened it, so nothing
	-- below it moves until it pops.
	--
	-- Asked *after* the stack is known to hold something, because an empty stack
	-- has nothing to hold up: saying "waiting" there stopped settle outright, so
	-- a game with a stack zone froze its end conditions and its automatic phases
	-- for as long as any page or pushed phase was open.
	if phase.depth() > 1 then return "waiting" end
	local top = entity.get(top_id)
	-- Anyone who may still answer this top: a responder that answers this seat's
	-- announcements at all ("whose") and has not already answered it. The second
	-- is what makes "everyone passed" a state that arrives — one card, one
	-- answer, per record — and it is what lets a reaction answer its own
	-- controller without the two of them going back and forth forever.
	local responders = reactions.responders(top.re_verb, top.re_subject, nil, top.re_targets)

	-- **Every forced reaction, before any question.** A trigger is not the
	-- seat's to decline, so passing does not silence it and a card standing
	-- ahead of it in the list cannot spend its turn. One fires per step and
	-- settle comes straight back for the next, which is what queues them: an
	-- announcement with three answers owed runs all three rather than one and a
	-- shrug. As that seat, because it costs them and acts on their cards.
	for _, r in ipairs(responders) do
		if r.reaction.forced == "mandatory"
			and reactions.answers_seat(r.reaction, r.seat, top.re_actor)
			and not has_answered(top, r.card) then
			local verdict = forced_verdict(top, r)
			if verdict == "ask" then
				give_priority(r.seat)
				return "waiting"
			elseif verdict == "fire" then
				give_priority(r.seat)
				-- A refused fire is the stack at its limit. It has been marked as
				-- having had its go, so the window moves past it rather than
				-- burning settle's budget on the record it just failed on.
				if fire_forced(top, r) then return "resolved" end
			end
		end
	end

	-- Then the questions, and those a seat may decline for the whole record.
	-- Nothing forced is left to ask about: the pass above either fired it, asked
	-- for it and returned, or found it was never there. A forced reaction is not
	-- a question, so it must not be offered as one here either — offering it is
	-- what let a card that could not answer eat the seat's answer.
	for _, r in ipairs(responders) do
		if r.reaction.forced ~= "mandatory"
			and reactions.answers_seat(r.reaction, r.seat, top.re_actor)
			and not top.re_passed[r.seat] and not has_answered(top, r.card) then
			give_priority(r.seat)
			return "waiting"
		end
	end
	resolve_top(top)
	return "resolved"
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
function M.defer_play(card_id, targets, aimed)
	local c = entity.get(card_id)
	if not (c and stack_zone()) then return false end
	for _, verb in ipairs(cards.emits(c, "play")) do
		if reactions.anyone_answers(verb, { card_id }, zones.active_seat(), targets) then
			push_event { verb = verb, action = cards.behaviour(c, "on_play"),
				subject = { card_id }, targets = targets, aimed = aimed, source = card_id,
				spent = cards.behaviour(c, "spent") }
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
		if M.emit(verb, { card_id }, ability.action, card_id, ctx, ability.key) then return true end
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
function M.emit(verb, subject, action, source, ctx, ability)
	if not reactions.anyone_answers(verb, subject, zones.active_seat(), ctx and ctx.targets) then return false end
	return push_event { verb = verb, action = action, subject = subject, source = source,
		targets = ctx and ctx.targets, aimed = ctx and ctx.aimed,
		let = ctx and ctx.let, ability = ability } ~= nil
end

-- What is waiting to be answered, if anything. An input layer has to ask,
-- because a response window looks like nothing from the outside: the turn has
-- not moved and the phase has not changed, and the only thing that did is who
-- may act. nil is every game without a stack and every moment its stack is empty.
-- A record is added before its fields are written, and the presentation records a step on every add, so a state being
-- replayed can hold one that is about nothing yet. Not pending until it says what it is.
function M.pending_event()
	local z = stack_zone()
	local top = z and entity.get(z.cards[#z.cards])
	return top and top.re_action and top or nil
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
	for _, r in ipairs(reactions.responders(top.re_verb, top.re_subject, true, top.re_targets)) do
		if r.seat == seat and reactions.answers_seat(r.reaction, seat, top.re_actor)
			and not has_answered(top, r.card)
			and costs.can_afford(r.reaction.cost, { card_id = r.card }) then
			out[#out + 1] = { card = r.card, index = r.index, rule = r.reaction }
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


-- What flow asks of the stack when a player moves.
M.zone         = stack_zone
M.push         = push_event
M.has_answered = has_answered
M.give_priority = give_priority
M.send_spent   = send_spent

return M
