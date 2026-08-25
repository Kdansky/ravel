-- Who may answer an event, and whether a window should open at all.
--
-- This is the suppression brain the response window is built on. It never
-- mutates: it reads the reaction index (Filter A), matches each candidate's
-- "where" against the event and its "when" against the reactor's own state, and
-- keeps only those the reactor could actually answer with right now (Filter B).
-- The scheduler in flow asks it one question — "does anyone answer this, and who"
-- — and opens a window only for a real answer.
--
-- Headless like every module below the presentation line: it reads state and
-- returns a list, and touches nothing love.* .

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local predicate   = require("predicate")

local M = {}

local EMPTY = {}

-- A zone the other players cannot read: a hand held up, a bag face down, or one
-- the game marks hidden outright. Everything else — a board, a discard, a table,
-- a bank — is on the table, and an inference may be drawn from it.
local function secret(z)
	if z.display == "offscreen" then return true end
	return z.visibility ~= "public"
end

-- Where the card has to be for this reaction to answer. A played reaction leaves
-- a hand; an activated or static one is in play. Asked two ways, because the
-- engine and the players know different things:
--
--   strict — where it really is. What the answering seat is offered, since they
--            can see their own cards.
--   loose  — where it could be, judged only from what everyone can see. A hand
--            and the bag behind it are the same place from across the table, so
--            a card in either might be in either.
--
-- The loose reading is what stops a prompt being evidence. The engine has full
-- information and the players do not: if the *appearance* of a window were driven
-- by a hidden hand, the window itself would announce what is in it. Opening on
-- what is publicly possible costs a pass now and then and tells nobody anything.
--
-- A game with nothing hidden needs no setting for this: no zone is secret, so the
-- two readings already say the same thing and the window is exact for free.
local function placed(e, reaction, strict)
	local z = e.zone_id and entity.get(e.zone_id)
	if not z then return false end
	if reaction.from == "board" then
		if z.status == "board" then return true end
	elseif reaction.from and reaction.from ~= "hand" then
		-- **A zone by name.** "board" is every grid and "hand" is every hand,
		-- which covers the two shapes a game usually has and not the third: a
		-- row of ongoing effects laid face up in front of one player is in play,
		-- and it is a *hand* as far as the engine's zone types go. Guessing which
		-- face-up zones count as in play gets a discard pile wrong, so the game
		-- says which zone it means, the way it names a zone everywhere else.
		if z.key == reaction.from then return true end
	elseif z.visibility == "owner" then
		return true
	end
	if strict then return false end
	return secret(z)
end

-- Does this reaction, on this card, answer this event? "where" is about the
-- event (read through @event); "when" is about the reactor, so it is asked as
-- that seat — the same read-as override the HUD uses, restored even if it raises.
--
-- `strict` refuses a card that only *might* be somewhere it could answer from.
-- Pass it wherever the answer is acted on rather than asked about.
function M.matches(reaction, e, subject, strict)
	if not placed(e, reaction, strict) then return false end
	local ctx = { event = subject, card_id = e.id, targets = {} }
	if reaction.where and not predicate.meets_all(reaction.where, ctx) then return false end
	if reaction.when then
		local seat = predicate.seat_of(e)
		local ok = true
		zones.as_seat(seat, function()
			if not predicate.meets_all(reaction.when, ctx) then ok = false end
		end)
		if not ok then return false end
	end
	return true
end

-- Every reaction that answers this event, as { seat, card = <id>, index, reaction }.
-- The index is the reaction's place in its card's own list, which is how an
-- input layer names the one it means.
-- Empty means no window: Filter A short-circuits a verb no card answers before a
-- single card is looked at, which is what stops every action prompting.
--
--   verb     the event verb ("play", "crash", "summon", ...)
--   subject  the event's subject, a list of card ids (read as @event)
function M.responders(verb, subject, strict)
	-- Filter A: nothing, ever, answers this verb.
	local answering = declaration.G.react_index[verb]
	if not answering then return {} end

	local out = {}
	for e in entity.each("card") do
		for _, hit in ipairs(answering[e.def_key] or EMPTY) do
			if M.matches(hit.reaction, e, subject, strict) then
				out[#out + 1] = { seat = predicate.seat_of(e), card = e.id,
					index = hit.index, reaction = hit.reaction }
			end
		end
	end
	return out
end

-- Whose announcement this reaction may answer, asked of one candidate.
--
-- "enemy" is the default and is what every reaction meant before the word
-- existed: somebody else's action, which is what a shield answers. "mine" is
-- the other half Magic has always had — a spell of your own on the stack, and
-- an instant of your own answering it — and "anyone" is both.
--
-- It is a word in a closed set rather than a flag because there are three
-- readings, and it is *these* words because a scope already uses them to mean
-- the same thing: whose, judged from the card asking.
function M.answers_seat(reaction, seat, actor)
	local whose = reaction.whose or "enemy"
	if whose == "anyone" then return true end
	if whose == "mine" then return seat == actor end
	return seat ~= actor
end

-- Whether opening a window for this event is worth it at all. The scheduler asks
-- this first, and only when it is true does it work out whose window to open.
--
-- "actor" is the seat whose own event it is. Each candidate is asked whether it
-- answers that seat's announcements at all (the same rule react_step enforces
-- when it picks who is up), so a verb only shields answer does not put a card on
-- the stack for a window that then finds nobody to open for.
function M.anyone_answers(verb, subject, actor)
	for _, r in ipairs(M.responders(verb, subject)) do
		if M.answers_seat(r.reaction, r.seat, actor) then return true end
	end
	return false
end

return M
