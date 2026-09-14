local entity      = require("entity")
local tags        = require("tags")
local zones       = require("zones")
local geometry    = require("geometry")
local predicate   = require("predicate")
local declaration = require("declaration")

local M = {}

M.card_id  = nil
M.kind     = nil   -- "slot" or "card"
M.intent   = nil   -- "play" or "activate": what confirming these targets does
M.spec     = nil   -- { min, max, tags, zone_set }
M.targets  = {}
M.eligible = {}

-- **Paying is picking, so it is the same session.** Once the targets are in, a
-- cost with more than one answer is settled by pointing at the cards that
-- settle it — which is the gesture the player has just been making. A second
-- stage of the aim rather than a question of its own, so the highlight, the
-- cancel and the confirm all keep working and none of them needs a second word.
M.stage    = "aim"   -- "aim" while the targets are being picked, "pay" while the cost is
M.ways     = {}      -- the ways the cost may still be settled, narrowed by each pick
M.aimed    = {}      -- the targets, held while M.targets is holding the payment picks

-- What may already be standing on a slot for it to be offered. "empty" is the
-- default, and was the only answer any game wanted until pieces started taking
-- each other: capture is a move onto an occupied square, so the square has to be
-- clickable before anything else can be built on top of it.
--
--   empty  nothing there                          (unchanged behaviour)
--   enemy  a piece another seat owns
--   open   either of the above — "not blocked by my own"
--   any    anything at all
local function slot_offered(slot, fill, active)
	if fill == nil or fill == "empty" then return slot.occupant == nil end
	if fill == "any" then return true end
	if slot.occupant == nil then return fill == "open" end
	local seat = predicate.seat_of(entity.get(slot.occupant))
	return seat ~= nil and seat ~= active
end

-- The squares a piece's own movement reaches, which is the whole of "where may
-- this go". Each rule brings its own patterns and its own answer to what may be
-- standing on the far square, so a pawn's step (empty only) and its capture
-- (an enemy only) are two rules over the same piece rather than two pieces.
--
-- A rule may carry "needs", judged of the piece itself — that is the pawn's
-- opening run, which is a movement it has only from its home rank.
--
-- A piece not standing on a square reaches nothing: movement is from somewhere.
local function find_moves(card_id, rules)
	local c = entity.get(card_id)
	if not (c and c.slot_id) then return {} end
	-- Whose move this is, which is not always whose turn it is. Asking what an
	-- *idle* enemy piece could do is how check is answered, and measuring "enemy"
	-- against the seat to play would invert it — that piece's own colleagues
	-- would read as capturable and its opponents as friends.
	local mover  = predicate.owner_of(c) or zones.active_seat()
	local facing = geometry.facing(mover, declaration.G.seat_list or {})
	local out, seen = {}, {}
	for _, rule in ipairs(rules) do
		if rule.needs == nil or predicate.meets_all(rule.needs, { card_id = card_id }) then
			for _, name in ipairs(rule.patterns) do
				local pat = (declaration.G.pattern_defs or {})[name]
				for _, sid in ipairs(pat and geometry.reach(c.slot_id, pat, facing) or {}) do
					-- `fill` asks what is standing on the square; `where` asks
					-- anything else about it, with the square as the target and
					-- as the anchor for any pattern inside. That is the whole
					-- difference from `needs`, which is asked once for the rule
					-- and cannot tell one candidate from another.
					if not seen[sid] and slot_offered(entity.get(sid), rule.fill, mover)
						and (rule.where == nil or predicate.meets_all(rule.where,
							{ card_id = card_id, anchor = sid, targets = { sid } })) then
						seen[sid]     = true
						out[#out + 1] = sid
					end
				end
			end
		end
	end
	return out
end

local function find_slots(zone_set, fill)
	local res, active = {}, zones.active_seat()
	for z in entity.each("zone") do
		if z.layout == "grid" and z.slots then
			local zone_ok = not zone_set or zone_set[z.key] or zone_set[z.layout]
				or tags.zone_tagged(z, zone_set)
			if zone_ok then
				for _, slot_id in pairs(z.slots) do
					local slot = entity.get(slot_id)
					if slot and slot_offered(slot, fill, active) then
						res[#res + 1] = slot_id
					end
				end
			end
		end
	end
	return res
end

-- How many targets a spec asks for. "count" is shorthand for both bounds.
-- The one definition: flow gates on it, the input layers decide whether to
-- open targeting at all, and targeting.start sizes itself from it.
-- How many picks an aim takes, and both ends of it. "spread" is the third way of
-- saying it and the one that says *what is being counted*: not cards but points,
-- all of which have to go somewhere, so it fixes both bounds the way "count"
-- does and reads back as an amount rather than a flag on a number.
function M.bounds(spec)
	if type(spec) ~= "table" then return 0, 0 end
	if spec.spread then return spec.spread, spec.spread end
	return spec.min or spec.count or 0, spec.max or spec.count or 0
end

function M.active()
	return M.card_id ~= nil
end

-- Who this card could legally be played onto. Pure: no session state, so flow
-- can ask the same question independently and refuse a target no interface
-- ever offered. Targeting is advisory; this is the legality.
-- Every instance of the named zones. A place to put a card is a thing you can
-- point at in its own right: "discard it" means the pile, not whatever card
-- happens to be lying on the pile, and a destination that has to be represented
-- by a marker card stops working the moment something covers the marker.
local function find_zones(zone_set)
	local res = {}
	for z in entity.each("zone") do
		local named = zone_set and (zone_set[z.key] or tags.zone_tagged(z, zone_set))
		if named and z.display ~= "offscreen" then res[#res + 1] = z.id end
	end
	return res
end

-- The squares one set of move rules offers, for asking whether an ability has
-- anywhere to go before offering it.
function M.moves_by(card_id, rules)
	return find_moves(card_id, rules)
end

-- Where this piece could move, right now. The reach half of `candidates`, with
-- none of the filtering that decides what a *player* may pick — a condition
-- asking what the enemy threatens is not choosing anything.
function M.moves_of(card_id)
	local e = entity.get(card_id)
	if not e then return {} end
	local out, seen = {}, {}
	for _, a in ipairs(require("cards").abilities(e)) do
		local spec = a.target
		if spec and spec.moves then
			for _, sid in ipairs(find_moves(card_id, spec.moves)) do
				if not seen[sid] then seen[sid] = true; out[#out + 1] = sid end
			end
		end
	end
	return out
end

function M.candidates(card_id, spec)
	local kind     = spec.type or "card"
	local zone_set = nil
	if spec.zones then
		zone_set = {}
		for _, zk in ipairs(spec.zones) do zone_set[zk] = true end
	end
	local out = kind == "slot" and (spec.moves and find_moves(card_id, spec.moves)
			or find_slots(zone_set, spec.fill))
		or kind == "zone" and find_zones(zone_set)
		or tags.find_targets(spec.tags or {}, zone_set)
	-- "Choose an enemy creature" is the same word the scopes use, so the
	-- player-chooses case needs no syntax of its own. Naming zones implies one
	-- too: "zones": ["red", "red_discard"] means *my* red expedition and the
	-- shared discard, exactly as a destination reads, so a spec that lists
	-- zones never offers another seat's copy of one unless it says so.
	local owner = spec.owner or (zone_set and "not_enemy")
	if owner then
		local active, kept = zones.active_seat(), {}
		for _, id in ipairs(out) do
			local e = entity.get(id)
			local seat = predicate.seat_of(e)
			local ok = owner == "anyone"
				or (owner == "not_enemy" and (seat == nil or seat == active))
				or (owner == "mine"      and seat ~= nil and seat == active)
				or (owner == "enemy"     and seat ~= nil and seat ~= active)
			if ok then kept[#kept + 1] = id end
		end
		out = kept
	end

	-- `where` asks anything else about a candidate, with the candidate as
	-- @target and as the anchor for any pattern inside. It is the same word a
	-- move rule already carries and the same question — asked one level up, so
	-- a destination nothing walks to can be narrowed too. A blocker's lane is
	-- the case: it is not somewhere the unit *moves*, it is a cell picked out of
	-- a grid, and "the row that is mine, opposite something that is attacking"
	-- has nowhere else to be said.
	if spec.where then
		local kept = {}
		for _, id in ipairs(out) do
			local e = entity.get(id)
			local anchor = e and (e.kind == "slot" and id or e.slot_id)
			if predicate.meets_all(spec.where,
				{ card_id = card_id, anchor = anchor, targets = { id } }) then
				kept[#kept + 1] = id
			end
		end
		out = kept
	end

	-- A stack offers its top card and nothing else. The renderer has always
	-- drawn and hit-tested exactly that, so a candidate buried in a pile was one
	-- the player was shown and could never click: Lost Cities' discard marker
	-- stayed "eligible" for the whole game while the first card discarded on top
	-- of it made it unreachable, and that colour could never be discarded to
	-- again. Whatever is on top is the destination now, which is what a pile
	-- meant all along.
	local reachable = {}
	for _, id in ipairs(out) do
		local e = entity.get(id)
		local z = e and e.kind == "card" and e.zone_id and entity.get(e.zone_id)
		if not z or z.reach ~= "top" or z.cards[#z.cards] == id then
			reachable[#reachable + 1] = id
		end
	end
	out = reachable

	-- Legality that depends on both cards at once lives on the destination:
	-- "accepts" is asked of each candidate with itself as @self and the
	-- arriving card as @target, so a pile can say what it takes without every
	-- card in the game having to know about every pile. A candidate with no
	-- accepts takes anything, which is what every game before this assumed.
	-- "immutable" is the engine's own word for scenery: menu entries, labels,
	-- anything that is furniture rather than a game object. Nothing may target
	-- it and nothing may edit it, so a stray "destroy every card here" or a
	-- misaimed spell cannot eat the interface.
	--
	-- A supply's cards are out for the same reason said the other way round. One
	-- card there stands for a whole stock of identical ones, so there is no
	-- single thing to point at — and it is that nobody can point that lets the
	-- engine keep one card where the game file wrote sixty-four. Two games said
	-- this by hand, tagging every counter "immutable"; the zone says it now.
	local visible = {}
	for _, id in ipairs(out) do
		local e = entity.get(id)
		local z = e and e.zone_id and entity.get(e.zone_id)
		if not (e and e.kind == "card"
			and (tags.entity_has(e, "immutable") or (z and z.status == "supply"))) then
			visible[#visible + 1] = id
		end
	end
	out = visible

	-- Legality that depends on both sides at once lives on the destination.
	-- A zone answers for itself, exactly as a card does — which is what lets
	-- "cards must ascend" be one line on the expedition rather than a rule every
	-- card in the game has to know.
	--
	-- The spec's verb rides along, so the ward can ask what kind of aim this is
	-- and not only who is making it. "Cannot be targeted by spells" is not a
	-- question about the caster — the hero that casts is the hero that attacks —
	-- so without it the exception had to be written on every spell in the game.
	local kept = {}
	for _, id in ipairs(out) do
		local e = entity.get(id)
		-- Through behaviour for a card, so a ward may be a keyword: its own
		-- block, its zone's, its tags' and whatever it is wearing right now. A
		-- zone wears no tags, so it answers for itself.
		local list = e and (e.kind == "card" and require("cards").accepts(e)
			or e.kind == "zone" and (declaration.G.zone_defs[e.key] or {}).accepts)
		if not (list and #list > 0) then
			kept[#kept + 1] = id
		elseif predicate.meets_all(list, { card_id = id, zone_id = e.kind == "zone" and id or nil,
			targets = { card_id }, verb = spec.verb }) then
			kept[#kept + 1] = id
		end
	end
	return kept
end

function M.start(card_id, spec, intent)
	local min, max = M.bounds(spec)
	M.card_id  = card_id
	M.kind     = spec.type or "card"
	M.intent   = intent or "play"
	M.spec     = { min = min, max = max, tags = spec.tags or {}, spread = spec.spread }
	M.targets  = {}
	M.eligible = M.candidates(card_id, spec)
	M.stage, M.ways, M.aimed = "aim", {}, {}
end

-- What a plan takes off each card: a pooled step says how much, and a sacrifice
-- names cards, where taking one is one.
local function spend_of(plan)
	local out = {}
	for _, step in ipairs(plan or {}) do
		if step.sacrifice then
			for _, id in ipairs(step.ids or {}) do out[id] = (out[id] or 0) + 1 end
		elseif step.id then
			out[step.id] = (out[step.id] or 0) + step.n
		end
	end
	return out
end

-- How many times this card has been named as paying.
local function paid(id)
	local n = 0
	for _, tid in ipairs(M.targets) do
		if tid == id then n = n + 1 end
	end
	return n
end

-- The cards still worth pointing at: those some remaining way spends more of
-- than has been named so far.
local function payable()
	local out, seen = {}, {}
	for _, plan in ipairs(M.ways) do
		for id, n in pairs(spend_of(plan)) do
			if n > paid(id) and not seen[id] then
				seen[id], out[#out + 1] = true, id
			end
		end
	end
	table.sort(out)
	return out
end

-- Move to the paying stage. The aim is stashed, because the picks about to be
-- made go in the same list the render already lights up — a card being spent
-- and a card being aimed at look the same to the player, and should.
--
-- False when there is nothing to ask: one way to pay, or a cost that names no
-- card. The caller then commits as it always did.
-- False when there is nothing to ask — one way to pay, or a cost that names no
-- card — and the caller then commits as it always did. It opens the session
-- itself rather than being stacked on an aim, because a move with nothing to
-- target still has a cost to settle.
function M.begin_payment(ways, card_id, intent, aim)
	if #(ways or {}) < 2 then return false end
	local owed = 0
	for _, n in pairs(spend_of(ways[1])) do owed = owed + n end
	if owed == 0 then return false end
	M.card_id  = card_id
	M.intent   = intent
	M.stage, M.ways, M.aimed = "pay", ways, aim or {}
	M.kind     = "card"
	M.spec     = { min = owed, max = owed, tags = {}, spread = true }
	M.targets  = {}
	M.eligible = payable()
	return true
end

-- The way the picks have settled on: one that spends exactly what was named and
-- no more. nil while there is still something to say.
function M.payment()
	if M.stage ~= "pay" then return nil end
	for _, plan in ipairs(M.ways) do
		local ok = true
		local spend = spend_of(plan)
		for id, n in pairs(spend) do
			if paid(id) ~= n then ok = false break end
		end
		if ok then
			for _, tid in ipairs(M.targets) do
				if (spend[tid] or 0) == 0 then ok = false break end
			end
		end
		if ok then return plan end
	end
	return nil
end

-- What pointing at something means for the spec in play.
--
-- The interface hit-tests topmost-card-first, because that is what a player is
-- looking at. But a spec may want the *place* rather than the thing standing on
-- it: a slot-typed spec wants a square, and a piece on a square is that square.
-- Without this a capture cannot be clicked at all — the eligible list holds
-- slots, a click on an occupied square yields the card covering it, and the two
-- never match however legal the move is.
--
-- Pure, and living here rather than in the input layer, so the rule is one the
-- tests can ask about instead of one only a human at a mouse can find.
function M.aim(id)
	if id == nil or id == M.card_id then return id end
	local e = entity.get(id)
	if M.kind == "slot" and e and e.kind == "card" and e.slot_id then
		return e.slot_id
	end
	return id
end

function M.is_eligible(id)
	for _, eid in ipairs(M.eligible) do
		if eid == id then return true end
	end
	return false
end

function M.is_selected(id)
	for _, tid in ipairs(M.targets) do
		if tid == id then return true end
	end
	return false
end

-- How many of the aim's picks this card is holding. One for an ordinary target,
-- and the whole of "3 damage divided as you choose" for a spread one — the share
-- *is* the number of times it was picked, so nothing has to carry an amount
-- beside the list of what was aimed at.
function M.share(id)
	local n = 0
	for _, tid in ipairs(M.targets) do
		if tid == id then n = n + 1 end
	end
	return n
end

-- **An aim that spends points may land on the same card twice.** "Deal 3 damage
-- divided as you choose among one, two or three patrollers" is three picks, each
-- worth what the action says, and the division is which card the player points
-- at each time. Nothing downstream needed teaching: "@target" already means
-- every pick in the order they were made, and a card named twice takes it twice.
function M.add(id)
	if not M.is_eligible(id) then return false end
	if M.is_selected(id) and not (M.spec and M.spec.spread) then return false end
	M.targets[#M.targets + 1] = id
	-- A payment is not built up, it is what is left once everything it is not
	-- has been ruled out: each pick drops every way that does not spend at least
	-- that much off that card, and what may still be pointed at follows.
	if M.stage == "pay" then
		local kept = {}
		for _, plan in ipairs(M.ways) do
			local spend, ok = spend_of(plan), true
			for _, tid in ipairs(M.targets) do
				if (spend[tid] or 0) < paid(tid) then ok = false break end
			end
			if ok then kept[#kept + 1] = plan end
		end
		M.ways = kept
		M.eligible = payable()
	end
	return true
end

function M.is_full()
	return M.spec and #M.targets >= M.spec.max
end

function M.can_confirm()
	return M.spec and #M.targets >= M.spec.min
end

function M.clear()
	M.card_id  = nil
	M.kind     = nil
	M.intent   = nil
	M.spec     = nil
	M.targets  = {}
	M.eligible = {}
	M.stage    = "aim"
	M.ways     = {}
	M.aimed    = {}
end

return M
