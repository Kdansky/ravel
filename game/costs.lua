-- What a move costs, and every way it can be paid: the planner flow asks before a
-- card is played, and the payer it calls once the move is decided. Nothing here
-- is a move of its own, so flow stays the one door legality comes through and
-- re-exports what its callers ask of this.

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local actions     = require("actions")
local predicate   = require("predicate")
local tags        = require("tags")
local log         = require("log")
local stats       = require("stats")
local auras       = require("auras")

local M = {}

-- True if a cost table like { gold = 2 } can be paid. nil cost = free.
-- "sacrifice:<tag>" entries are paid in board cards instead of stats; every
-- other key is a subject, so it may carry a scope and quantifier
-- ({ "hp@each.follower": 1 } — each follower must have one to give).
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

-- **What an aim costs on top, because of what it is aimed at.** The other half
-- of `adjusts`: a verb that `does: "target"` changes no stat on a card, it
-- changes the price of pointing at one. Resist is the whole of it — *opponents
-- pay 1 more gold each time they target this with a spell or an ability* — and
-- it is the same index, the same `covers`, the same `by` as armour, read at the
-- one moment a cost can know what it is being spent on.
--
-- Every chosen target is asked, so aiming at two resisting things costs two.
-- **Who is charged is the game's business, not the engine's**: Codex's resist
-- says *opponents* pay, and says so in the aura's own needs — "count@enemy.self",
-- the holder read from the acting seat's side. A game wanting everyone to pay
-- writes no needs at all. Nothing is charged before targeting: `can_play` and
-- the ability chooser judge affordability with no targets, so a card in hand
-- quotes its printed price and learns the surcharge once you pick.
local function resisted(stat, ctx)
	if not (ctx and ctx.targets) then return 0 end
	local more = 0
	-- Every chosen target is asked, so aiming at two resisting things costs two.
	for _, aimed in ipairs(ctx.targets) do
		more = more + auras.shift(aimed, ctx.verb, stat, ctx.card_id)
	end
	-- Signed, and the clamp belongs to the caller. An aura that made a cost
	-- *dearer* was the only one the arithmetic here allowed, because clamping the
	-- shift threw a discount away before anything could spend it — while the same
	-- word aimed at damage has always been allowed to subtract, which is the whole
	-- of what armour is. One word, one rule: several sum, and the total may not
	-- change the sign of what it adjusts.
	return more
end

-- What is owed, and out of which pools. Nothing is spent here: a cost is
-- decided in full before the first coin moves, which is the whole of what makes
-- it different from an effect. An effect that cannot happen is skipped where it
-- stands; a cost that cannot be paid has to stop the card being played at all,
-- because there is no unwinding half a payment.
--
-- A plan is a list of steps, each naming what it spends and whose:
--
--   { subject, n }            owed exactly as written — "each", a measuring fn,
--                             or a scope that waits on targets
--   { subject, n, id, stat }  n of a pool, off that one card
--   { sacrifice, n, ids }     those cards, purged
--   { exhaust }               the asking card's own readiness
local function demands_of(cost, ctx)
	local demands = {}
	for subject, n in pairs(cost or {}) do
		if subject ~= "exhaust" and not subject:match("^sacrifice:") then
			-- **A cost may be measured rather than typed.** A shop whose buy lives
			-- on the tag its zone hands out cannot write a number: the price is
			-- on the chip, and the ability is shared by everything on the shelf.
			-- Read through the same total() a condition uses, so a compute an
			-- ability bound before it ran stands here too — which is how a price
			-- with something taken off it is said, since a compute has the
			-- arithmetic a cost has no room for.
			local need = tonumber(n) or predicate.total(tostring(n), ctx)
			local p    = predicate.parse_subject(subject)
			-- Never below free: a discount that outruns the price is a price of
			-- nothing, not a card that pays you to play it.
			need = math.max(0, need + resisted(stat_name(subject), ctx))
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
				demands[#demands + 1] = { subject = subject, need = need, from = from,
					pick = p.quant == "select" }
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
	return demands
end

-- The cards a sacrifice may take. "self" is the card doing the asking, which a
-- tag cannot name: a cost already reaches its own card for "exhaust" and had no
-- way to say the same about spending itself, so a game gave one card a private
-- tag and killed the wrong copy the moment there were two.
--
-- **Nothing with a foreign owner.** Giving something up is the whole meaning of
-- the word, so no tag can widen the pool to the other side of the table:
-- "sacrifice a unit" names no owner because there is only one it could have
-- meant. Doom Grasp offered the opponent's units as well as yours, and a cost
-- that takes from the other player is a reward.
--
-- Said as a refusal rather than as "mine", because a card on a common board
-- belongs to nobody and is still yours to spend — the tower's relics and the
-- road's outriders sit in seatless zones. Whose turn it is comes from
-- active_seat, what "mine" and every other cost read, so a sacrifice paid inside
-- a response window comes off whoever is answering.
local function sacrifice_pool(tag, ctx)
	if tag == "self" then
		local c = ctx and ctx.card_id and entity.get(ctx.card_id)
		return c and { c.id } or {}
	end
	local mine, out = zones.active_seat(), {}
	for _, id in ipairs(zones.find_targets({ tag }, zones.IN_PLAY)) do
		local owner = tags.owner_of(entity.get(id))
		if owner == nil or owner == mine then out[#out + 1] = id end
	end
	return out
end

-- The parts of a cost that are not stats and so have no substitutes: a card
-- spending itself, and a card spending somebody else. Decided with the rest so
-- that affordability is one question — two that could disagree about one cost
-- is how a card gets played and then cannot pay.
-- Keys are walked in sorted order, never pairs: clamping makes payment order
-- observable, and a seeded replay has to pay identically.
local function extra_demands(cost, ctx)
	local keys = {}
	for k in pairs(cost or {}) do
		if k == "exhaust" or tostring(k):match("^sacrifice:") then keys[#keys + 1] = k end
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		if k == "exhaust" then
			-- Tapping, in the MTG sense: the card spends *itself* being ready. A
			-- card already spent cannot pay it, which is the whole of "once per
			-- round" — and saying it as a cost rather than as a consequence is
			-- what lets one card have an ability that taps beside one that does not.
			local c = ctx and ctx.card_id and entity.get(ctx.card_id)
			if not c or c.exhausted then return nil end
			out[#out + 1] = { exhaust = true }
		else
			local tag  = k:match("^sacrifice:(.+)$")
			local need = tonumber(cost[k]) or 0
			local pool = sacrifice_pool(tag, ctx)
			if #pool < need then return nil end
			out[#out + 1] = { sacrifice = tag, need = need, pool = pool }
		end
	end
	return out
end

-- Which card pays how much, as multisets: two orders of the same picks are one
-- answer, because payment is a subtraction and subtraction does not care what
-- order it happens in. Taking as much as possible off the first source first is
-- what puts the greedy plan — the one the engine has always paid — at the head
-- of the list, so a budget of one returns exactly it.
local function splits(sources, need, budget)
	local out, pick = {}, {}
	local function walk(i, left)
		if #out >= budget then return end
		if left == 0 then
			local m = {}
			for j, v in ipairs(pick) do m[j] = v end
			out[#out + 1] = m
			return
		end
		if i > #sources then return end
		local s = sources[i]
		for k = math.min(left, s.cap), 0, -1 do
			if k > 0 then
				pick[#pick + 1] = { subject = s.subject, id = s.id, stat = s.stat, n = k }
			end
			walk(i + 1, left - k)
			if k > 0 then pick[#pick] = nil end
			if #out >= budget then return end
		end
	end
	walk(1, need)
	return out
end

-- Every way to take `need` cards out of a pool. Which ones die is a choice
-- about *which*, never about how many of one, so a card is in an answer once or
-- not at all — and the first answer is the earliest cards, which is what a
-- sacrifice took before anybody was asked.
local function combinations(pool, need, budget)
	local out, pick = {}, {}
	local function walk(i)
		if #out >= budget then return end
		if #pick == need then
			local m = {}
			for j, v in ipairs(pick) do m[j] = v end
			out[#out + 1] = m
			return
		end
		for j = i, #pool do
			pick[#pick + 1] = pool[j]
			walk(j + 1)
			pick[#pick] = nil
			if #out >= budget then return end
		end
	end
	walk(1, need)
	return out
end

-- **How many answers a question may have before it stops being one.** A human
-- picks one card at a time and never sees this list; an engine seat wants all of
-- it. A wide enough pool has more splits than anyone will look at, so the list
-- stops — and because the greedy plan is always first, stopping early costs the
-- choice, never the payment.
local MAX_PLANS = 200

-- Every complete way this cost can be settled, greedy first; empty when it
-- cannot be settled at all. A part nobody has a choice about is in all of them
-- unchanged, and only two things open out: a demand whose scope said "select",
-- and a sacrifice, which is always the player's to make.
--
-- **The parts are walked in order, not multiplied.** Two of them may reach the
-- same pile — a demand the player split and one the engine settled greedily —
-- and a product of independently-enumerated answers would spend the same coin
-- twice. So what is left is carried down the walk, keyed by stat and card
-- because two scopes may name one card's one stat.
local function plans(cost, ctx, budget)
	budget = budget or MAX_PLANS
	local extras = extra_demands(cost, ctx)
	if not extras then return {} end
	local rem = {}
	local function left_on(stat, e)
		local k = stat .. "#" .. e.id
		if rem[k] == nil then rem[k] = stats.current(e, stat) end
		return rem[k]
	end
	-- Sorted by id, the order drain has always taken a pool in, so a plan nobody
	-- chose names the very cards the engine would have taken by itself.
	local function holders(src)
		local p = predicate.parse_subject(src)
		local ents = p and predicate.bearers(p, ctx) or {}
		table.sort(ents, function(a, b) return a.id < b.id end)
		return p, ents
	end
	-- The parts that are nobody's choice, settled first so that a split the
	-- player is about to choose is offered what is actually still there.
	local head, choices = {}, {}
	for _, d in ipairs(demands_of(cost, ctx)) do
		if d.as_written then
			if not predicate.awaits_targets(d.subject, ctx)
				and not predicate.holds(d.subject .. " >= " .. tostring(d.need), ctx) then
				return {}
			end
			head[#head + 1] = { subject = d.subject, n = d.need }
		elseif d.pick then
			choices[#choices + 1] = d
		else
			local owed = d.need
			for _, src in ipairs(d.from) do
				local p, ents = holders(src)
				for _, e in ipairs(ents) do
					if owed <= 0 then break end
					local take = math.min(owed, left_on(p.arg, e))
					if take > 0 then
						rem[p.arg .. "#" .. e.id] = left_on(p.arg, e) - take
						head[#head + 1] = { subject = src, n = take, id = e.id, stat = p.arg }
						owed = owed - take
					end
				end
				if owed <= 0 then break end
			end
			if owed > 0 then return {} end
		end
	end
	for _, e in ipairs(extras) do
		if e.sacrifice then choices[#choices + 1] = e else head[#head + 1] = e end
	end
	local out, acc = {}, {}
	local function walk(i)
		if #out >= budget then return end
		if i > #choices then
			local one = {}
			for _, step in ipairs(head) do one[#one + 1] = step end
			for _, step in ipairs(acc) do one[#one + 1] = step end
			out[#out + 1] = one
			return
		end
		local part = choices[i]
		if part.sacrifice then
			for _, c in ipairs(combinations(part.pool, part.need, budget)) do
				acc[#acc + 1] = { sacrifice = part.sacrifice, n = part.need, ids = c }
				walk(i + 1)
				acc[#acc] = nil
				if #out >= budget then return end
			end
			return
		end
		local sources = {}
		for _, src in ipairs(part.from) do
			local p, ents = holders(src)
			for _, e in ipairs(ents) do
				local cap = left_on(p.arg, e)
				if cap > 0 then
					sources[#sources + 1] = { subject = src, id = e.id, stat = p.arg, cap = cap }
				end
			end
		end
		for _, way in ipairs(splits(sources, part.need, budget)) do
			local n0 = #acc
			for _, step in ipairs(way) do
				acc[#acc + 1] = step
				rem[step.stat .. "#" .. step.id] = rem[step.stat .. "#" .. step.id] - step.n
			end
			walk(i + 1)
			for k = #acc, n0 + 1, -1 do
				local step = acc[k]
				rem[step.stat .. "#" .. step.id] = rem[step.stat .. "#" .. step.id] + step.n
				acc[k] = nil
			end
			if #out >= budget then return end
		end
	end
	walk(1)
	return out
end

-- The one plan the engine would pay by itself: the head of the list, asked for
-- on its own so that judging a card in hand — which happens for every card on
-- every frame — never enumerates anything.
local function plan(cost, ctx)
	return plans(cost, ctx, 1)[1]
end

function M.can_afford(cost, ctx)
	return plan(cost, ctx) ~= nil
end

-- The ways a move may be paid for, for a caller that has to pick one: an engine
-- seat weighing all of them, or an interface about to ask. The ctx is built
-- exactly as the deed builds it, targets included — a cost measured off what was
-- aimed at is a different cost per aim, and asking with a different ctx than the
-- one that pays is how a question and its deed come apart.
function M.play_payments(card_id, targets)
	local c   = entity.get(card_id)
	local def = c and cards.def(c)
	if not def then return {} end
	-- Through behaviour, like play_card's own: a zone may grant the compute the
	-- price is worked out with.
	return plans(def.cost, predicate.bind(cards.behaviour(c, "compute"),
		{ card_id = card_id, targets = targets or {}, verb = def.target and def.target.verb }))
end

-- The same for an ability or a reaction, whose rule the caller already holds.
-- `who` is the card or the zone it belongs to, since a zone's ability is asked
-- about the place and not about anything standing in it.
function M.rule_payments(who, rule, targets)
	local e = entity.get(who)
	if not (e and rule) then return {} end
	local ctx = e.kind == "zone" and { zone_id = who }
		or { card_id = who, targets = targets or {}, verb = rule.target and rule.target.verb }
	return plans(rule.cost, predicate.bind(rule.compute, ctx))
end

-- One step written down, so two payments can be compared without caring what
-- order their steps arrived in.
local function payment_key(step)
	local ids = {}
	for _, id in ipairs(step.ids or {}) do ids[#ids + 1] = tostring(id) end
	table.sort(ids)
	return table.concat({ step.exhaust and "exhaust" or "", step.sacrifice or "",
		step.subject or "", tostring(step.n or ""), tostring(step.id or ""),
		table.concat(ids, ",") }, ":")
end

local function payment_id(steps)
	local keys = {}
	for _, step in ipairs(steps) do keys[#keys + 1] = payment_key(step) end
	table.sort(keys)
	return table.concat(keys, "|")
end

-- Whether a payment that arrived from outside is one of the ways this cost may
-- actually be settled. Flow is the single legality gate, and a payment comes in
-- beside the targets — from an interface, a script, the network, an engine seat
-- — so it is checked here rather than trusted, exactly as targets are.
function M.legal(cost, ctx, payment)
	if payment == nil then return true end
	local want = payment_id(payment)
	for _, p in ipairs(plans(cost, ctx)) do
		if payment_id(p) == want then return true end
	end
	return false
end

-- Pay a cost: a pooled step spends n off the one card it names, a sacrifice
-- purges the cards its step names, "exhaust" spends the asking card's readiness,
-- and everything else is spent through its subject so a scope and quantifier are
-- honoured. Every step was decided before any of them ran, so there is no
-- half-paid cost to unwind.
function M.pay(cost, ctx, payment)
	for _, step in ipairs(payment or plan(cost, ctx) or {}) do
		if step.exhaust then
			local c = ctx and ctx.card_id and entity.get(ctx.card_id)
			if c then c.exhausted = true end
		elseif step.sacrifice then
			for _, id in ipairs(step.ids or {}) do
				local victim = entity.get(id)
				if victim then
					local vdef = cards.def(victim)
					log.add("Sacrificed " .. (vdef and vdef.text or victim.def_key))
					zones.purge_card(id)
				end
			end
		else
			actions.spend(step.subject, step.n, ctx, step.id)
		end
	end
end

return M
