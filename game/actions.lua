local entity      = require("entity")
local declaration = require("declaration")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local predicate   = require("predicate")
local log         = require("log")
local geometry    = require("geometry")
local rng         = require("rng")

local M = {}

local EMPTY = {}

M.pending_load   = nil   -- set by load_game, consumed by flow after the action list
M.pending_slot   = nil   -- set by load_save, consumed the same way
M.on_net         = nil   -- optional hook(what, arg): the networking layer's UI, if one is loaded
M.on_save        = nil   -- optional hook(what, slot): the save layer, if one is loaded
M.on_stat_change = nil   -- optional hook(entity, key, delta, ctx) for visual feedback
-- optional hook(card_id, ordinal): a zone's cards acting in turn, so the
-- presentation can space them out. ordinal 0 with no card means the run is over.
M.on_act         = nil
M.on_effect      = nil   -- optional hook(name, ctx): presentation plays the named effect
-- optional hook(): the turn changed hands, so whatever is scoped to a turn ends.
-- Set by flow, which owns the undo history and may not be required from here.
M.on_seat_change = nil

function M.take_load()
	local f = M.pending_load
	M.pending_load = nil
	return f
end

function M.take_slot()
	local s = M.pending_slot
	M.pending_slot = nil
	return s
end

-- Content errors surface in the event log (the GUI has no console) and on
-- stdout, then the action is skipped: a typo must never kill a running game.
local function content_error(msg)
	log.add("! " .. msg)
	print(msg)
end

-- Parse "op:p1:p2:..." into { "op", "p1", "p2", ... }
local function parse(str)
	local parts = {}
	for p in str:gmatch("[^:]+") do parts[#parts + 1] = p end
	return parts
end

-- A load_game target must be a plain <name>.json directly under games/ —
-- no path separators, no "..", no drive letters. This field is untrusted
-- content (games are meant to be authored by other people); without this,
-- a crafted card could point at an arbitrary path readable by the engine.
-- Enforced here, not just suggested by the validator, since validator
-- warnings don't stop content from running.
local function safe_game_filename(name)
	return type(name) == "string" and name:match("^[%w_%-]+%.json$") ~= nil
end

-- A zone argument is a scope expression too, so "arena" is the active seat's
-- and "enemy.arena" is the other's. A destination must resolve to exactly one
-- zone, which is why this returns an id rather than a set.
local function zone_id(arg)
	local sc = predicate.parse_scope(arg or "")
	return sc and zones.find_id(sc.name, sc.owner)
end

local function zone_of(arg)
	local id = zone_id(arg)
	return id and entity.get(id)
end

-- Every numeric slot accepts a number or a measuring fn over a subject —
-- "count:<tag>", "card:<key>", "sum:<subject>", "max:<subject>", "min:<subject>" — e.g.
-- "stat_gain:gold:count:economic". One rule everywhere.
local FN_TERMS = { count = true, card = true, sum = true, max = true, min = true }

local function term(p, i, default, ctx)
	if FN_TERMS[p[i] or ""] then
		return predicate.total(p[i] .. ":" .. tostring(p[i + 1]), ctx), i + 2
	end
	return tonumber(p[i]) or default or 0, i + 1
end

-- A slot may also be a product: "<term>:x:<term>", left to right. One operator
-- and no parentheses, so there is no precedence to remember — and a product is
-- the one thing repeated addition cannot stand in for. Lost Cities scores an
-- expedition as (sum - 20) x wagers, written as the two actions
-- "stat_gain:score:sum:value@mine.red:x:count:wager" and
-- "stat_damage:score:20:x:count:wager", which is the same arithmetic distributed.
local function amount(p, i, default, ctx)
	local v, j = term(p, i, default, ctx)
	while p[j] == "x" do
		local w
		w, j = term(p, j + 1, 1, ctx)
		v = v * w
	end
	return v
end

-- The floor and the ceiling a stat is held between on this card: its own if it
-- declared one, the global "stats" entry's otherwise, and nothing at all if
-- neither said — a stat with no ceiling grows, and one with no floor may go
-- negative, which is what lets a blocker carry its own overkill.
local function bounds(e, key)
	local def = declaration.G.stat_defs[key] or EMPTY
	local lo  = e.stat_min and e.stat_min[key]
	local hi  = e.stat_max and e.stat_max[key]
	if lo == nil then lo = def.min end
	if hi == nil then hi = def.max end
	return lo, hi
end

local function clamped(e, key, v)
	local lo, hi = bounds(e, key)
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end

-- Change a stat on an entity, held between its floor and its ceiling.
local function change_stat(e, key, delta, ctx)
	if not e or not e.stats then return end
	local old = e.stats[key] or 0
	local v   = clamped(e, key, old + delta)
	e.stats[key] = v
	if v ~= old then
		local txt = string.format("%+d %s", v - old, key)
		if e.kind == "card" then
			local d = declaration.G.card_defs[e.def_key]
			txt = (d and d.text or e.def_key) .. " " .. txt
		end
		log.add(txt)
		-- The ctx carries who did it. A number changing on a card says nothing
		-- about where it came from, and "that one hit this one" is the whole of
		-- what a player needs to follow a board.
		if M.on_stat_change then M.on_stat_change(e, key, v - old, ctx) end
	end
end

-- Who a subject designates for a change. The one place the quantifier is
-- turned into a list, so gaining, setting and spending can never disagree
-- about who "@random.beast" means: each reaches every member, random picks one
-- with the seeded RNG, the pooled default takes the first.
local function designated(p, ctx)
	local ents = predicate.bearers(p, ctx)
	if #ents == 0 or p.quant == "each" then return ents end
	if p.quant == "random" then return { ents[rng.int(#ents)] } end
	return { ents[1] }
end

local function apply_stat(subject, delta, ctx)
	local p = predicate.parse_subject(subject)
	if not p then return end
	for _, e in ipairs(designated(p, ctx)) do change_stat(e, p.arg, delta, ctx) end
end

-- Take n from a pool, in id order until it is covered — deterministic, so a
-- seeded replay pays the same cards in the same order. Choosing who pays and
-- splitting an amount across them are different problems, which is why this is
-- kept out of `designated` rather than folded into it.
local function drain(p, n, ctx)
	local ents = predicate.bearers(p, ctx)
	table.sort(ents, function(a, b) return a.id < b.id end)
	local left = n
	for _, e in ipairs(ents) do
		if left <= 0 then break end
		local take = math.min(tonumber(e.stats[p.arg]) or 0, left)
		if take > 0 then
			change_stat(e, p.arg, -take, ctx)
			left = left - take
		end
	end
end

-- Spend n of a subject: pooled scopes drain, "each" (and the unscoped form)
-- takes the full amount from everyone designated.
function M.spend(subject, n, ctx)
	local p = predicate.parse_subject(subject)
	if not p then return end
	if p.scope and p.quant ~= "each" then return drain(p, n, ctx) end
	for _, e in ipairs(designated(p, ctx)) do change_stat(e, p.arg, -n, ctx) end
end

local HANDLERS = {}

HANDLERS["fill"] = function(p)
	-- fill:zone:card_key:n
	local zone = zone_of(p[2] or "")
	if not zone then
		content_error("fill: unknown zone " .. tostring(p[2]))
		return
	end
	if not declaration.G.card_defs[p[3] or ""] then
		content_error("fill: unknown card " .. tostring(p[3]))
		return
	end
	for _ = 1, amount(p, 4, 1) do
		if not zones.add(zone, p[3]) then break end
	end
end

HANDLERS["shuffle"] = function(p)
	local zid = zone_id(p[2])
	if zid then zones.shuffle(zid) end
end

HANDLERS["draw_from"] = function(p)
	-- draw_from:from:to:n  (n defaults to 1)
	local from_id = zone_id(p[2])
	local to_id   = zone_id(p[3] or "hand")
	if not from_id or not to_id then return end
	for _ = 1, amount(p, 4, 1) do
		if not zones.move_top(from_id, to_id) then break end
	end
end

-- The only board, when there is exactly one — the fallback destination for
-- cards without a home tag in single-board games.
local function sole_grid()
	local z = zones.sole_grid()
	return z and z.key
end

HANDLERS["move_to"] = function(p, ctx)
	-- move_to:zone  —  moves ctx.card_id to zone; if first target is a slot in that zone, uses place_in_slot.
	-- Without a zone the card's home (a tag naming a zone) decides, falling
	-- back to the only board; the validator flags the ambiguous cases.
	if not ctx or not ctx.card_id then return end
	local dest = p[2]
	-- A third argument says what to do about a piece already standing there:
	-- "destroy", or the zone the taken piece goes to. Left out, an occupied
	-- square refuses the move, which is what every game before this expected.
	local on_occupied = p[3]
	-- move_to:target — the card goes where the player chose. It is the only way
	-- one card can offer two destinations ("advance the expedition, or discard
	-- it"), and it is the same verb: "target" is already a scope word.
	if dest == "target" then
		local t = ctx.targets and ctx.targets[1] and entity.get(ctx.targets[1])
		if not t then return end
		if t.kind == "slot" then zones.place_in_slot(ctx.card_id, t.id, on_occupied)
		-- Aiming at a piece means its *square* only once the author has said
		-- what becomes of it — that is what a capture is. Left unsaid, aiming at
		-- a card still means the zone it lies in, which is how "advance the
		-- expedition" reads and how it has always worked.
		elseif t.kind == "card" and t.slot_id and on_occupied then
			zones.place_in_slot(ctx.card_id, t.slot_id, on_occupied)
		elseif t.kind == "zone" then zones.move_card(ctx.card_id, t.id)
		elseif t.zone_id then zones.move_card(ctx.card_id, t.zone_id) end
		return
	end
	if not dest then
		local c   = entity.get(ctx.card_id)
		local def = c and declaration.G.card_defs[c.def_key]
		dest = (def and cards.home_zone(def)) or sole_grid()
	end
	local to_id = dest and zone_id(dest)
	if not to_id then return end
	local t1  = ctx.targets and ctx.targets[1]
	local tgt = t1 and entity.get(t1)
	if tgt and tgt.kind == "slot" and tgt.zone_id == to_id then
		zones.place_in_slot(ctx.card_id, tgt.id, on_occupied)
	else
		zones.move_card(ctx.card_id, to_id)
	end
end

-- gain:card_key:n  — create n instances of a card in its home zone (the
-- zone its tags name), or the hand when it has none.
HANDLERS["gain"] = function(p)
	local def = declaration.G.card_defs[p[2] or ""]
	if not def then
		content_error("gain: unknown card " .. tostring(p[2]))
		return
	end
	local zone = zones.find(cards.home_zone(def) or "hand")
	if not zone then return end
	for _ = 1, amount(p, 3, 1) do
		if not zones.add(zone, def.key) then break end
	end
end

HANDLERS["add_to"] = function(p, ctx)
	-- add_to:zone  —  same as move_to but never slot-targeted (overlay on_pick context)
	local to_id = zone_id(p[2])
	if to_id and ctx and ctx.card_id then
		zones.move_card(ctx.card_id, to_id)
	end
end

-- The four verbs that move a number, named so they sort together: what they
-- share is the stat, and that is the half worth reading first.
HANDLERS["stat_gain"] = function(p, ctx)
	apply_stat(p[2], amount(p, 3, 0, ctx), ctx)
end

-- Taking it away. The same arithmetic as stat_gain with the sign turned round,
-- and a separate word because "damage 2" and "gain -2" are the same instruction
-- to the engine and different sentences to everyone else.
HANDLERS["stat_damage"] = function(p, ctx)
	apply_stat(p[2], -amount(p, 3, 0, ctx), ctx)
end

-- Move the ceiling. The current value comes with it only where it has to: a
-- ceiling lowered under the number standing there would leave a stat above its
-- own maximum until something unrelated happened to touch it.
HANDLERS["stat_boost"] = function(p, ctx)
	local sp = predicate.parse_subject(p[2])
	if not sp then return end
	local d = amount(p, 3, 0, ctx)
	for _, e in ipairs(designated(sp, ctx)) do
		if e.stat_max then
			local was = e.stat_max[sp.arg]
			if was then
				e.stat_max[sp.arg] = was + d
				local now = e.stats[sp.arg]
				if now and now > was + d then change_stat(e, sp.arg, 0, ctx) end
			end
		end
	end
end

-- Write it outright, past every bound. An authoring tool rather than a game
-- rule: it is how a phase resets a counter, and it neither logs nor animates,
-- because nothing a player did caused it.
HANDLERS["stat_set"] = function(p, ctx)
	local sp = predicate.parse_subject(p[2])
	if not sp then return end
	local v = amount(p, 3, 0, ctx)
	for _, e in ipairs(designated(sp, ctx)) do e.stats[sp.arg] = v end
end

HANDLERS["next_phase"] = function()
	phase.next()
end

HANDLERS["push_phase"] = function(p)
	phase.push(p[2])
end

HANDLERS["pop_phase"] = function()
	phase.pop()
end

HANDLERS["load_game"] = function(p)
	if not safe_game_filename(p[2]) then
		content_error("load_game: refused '" .. tostring(p[2])
			.. "' (must be a plain name.json, no path)")
		return
	end
	-- Deferred: consumed by flow.settle after the action list completes.
	M.pending_load = p[2]
end

-- destroy:<scope>  — remove every card the scope names from play. A bare zone
-- key is a scope, so "destroy:hand" means exactly what it always did, and
-- "destroy:each.enemy.creature" needs no second verb. A card cannot be partly
-- destroyed, so the pooled quantifiers coincide here: only "random." narrows,
-- to one victim. Ids are collected before anything is removed — destroying
-- while walking a zone's own card list is how you skip half of it.
-- activate_zone:<zone>[:<order>]  — every card lying there does what it does.
--
-- **The order is the game's to state, not the engine's.** Without one the cards
-- act in the order they are in, which is the order the game put them there.
-- "by_column" is the one other order the engine offers: columns left to right,
-- and within a column the order the squares are indexed. That is what "strikes
-- resolve left to right" means on a board of two ranks facing each other — read
-- row by row it would resolve one whole side and then the other, which is a
-- different game, and neither is the engine's to prefer.
--
-- **One word, and the validator refuses any other.** A closed set of one is not
-- a design; it is the smallest thing that moves the decision into the file, and
-- the honest place to grow from when a game wants an order this cannot say.
--
-- This is how a *phase* makes cards act. Until now a card only acted because a
-- player clicked it or because the round wrapped, so anything that had to happen
-- at a particular moment had to be built into the engine — readying at a round
-- boundary is exactly that, and it is a rule with very specific timing in most
-- games that have it. With this, the rule goes on a card in a hidden zone and
-- the phase that should run it says so.
--
-- Ungated on purpose. A player clicking a card asks "may I?", and flow answers
-- with the phase, the cost and whose card it is. A phase running its own rules
-- has already decided it is time; a rules card that refused itself here would be
-- a rule that silently did not happen.
HANDLERS["activate_zone"] = function(p, ctx)
	local z = zone_of(p[2] or "")
	if not z then
		content_error("activate_zone: unknown zone " .. tostring(p[2]))
		return
	end
	-- Snapshot first: an ability may destroy a card, move one in, or empty the
	-- zone entirely, and the list being walked must not be the one changing.
	local order = {}
	for i, id in ipairs(z.cards) do order[i] = id end
	if p[3] == "by_column" then
		local function square(id)
			local e = entity.get(id)
			return e and e.slot_id and entity.get(e.slot_id) or nil
		end
		table.sort(order, function(a, b)
			local sa, sb = square(a), square(b)
			local ca = sa and sa.stats.col or 0
			local cb = sb and sb.stats.col or 0
			if ca ~= cb then return ca < cb end
			return (sa and sa.slot_idx or 0) < (sb and sb.slot_idx or 0)
		end)
	elseif p[3] then
		content_error("activate_zone: '" .. tostring(p[3]) .. "' is not an order the engine knows")
		return
	end
	for i, id in ipairs(order) do
		local e = entity.get(id)
		if e and e.zone_id == z.id then
			-- Which of the run this is. The rules resolve the whole zone in one
			-- instant — they have to, or a snapshot could be taken halfway
			-- through a combat — so this is the only thing the presentation has
			-- to tell one act from the next and space them out.
			if M.on_act then M.on_act(id, i) end
			for _, a in ipairs(cards.abilities(e)) do
				if type(a.action) == "table" then
					M.run(a.action, { card_id = id, targets = {} })
				end
			end
		end
	end
	if M.on_act then M.on_act(nil, 0) end
end

-- ready:<scope>  — un-spend the cards in scope. The counterpart to the "exhaust"
-- cost, and the only way a game can decide *when* being spent wears off: until
-- this existed the engine readied everything at the round wrap and no game could
-- say otherwise, which is a rule with very specific timing in most games that
-- have it at all.
HANDLERS["ready"] = function(p, ctx)
	local sc = predicate.parse_scope(p[2] or "")
	if not sc then return end
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		if e.kind == "card" then e.exhausted = nil end
	end
end

HANDLERS["destroy"] = function(p, ctx)
	local sc = predicate.parse_scope(p[2] or "")
	if not sc then return end
	local doomed = {}
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		if e.kind == "card" and e.zone_id then doomed[#doomed + 1] = e.id end
	end
	table.sort(doomed)
	if sc.quant == "random" and #doomed > 0 then
		doomed = { doomed[rng.int(#doomed)] }
	end
	for _, id in ipairs(doomed) do zones.destroy_card(id) end
end

-- move:<scope>:<zone>  — every card the scope names goes to that zone.
--
-- The scope-first sibling of move_to (the card that is acting) and
-- move_target_to (the ones a player chose). What it is for is a set nobody
-- picked and nothing is acting for — "send the survivors back to their bench",
-- where the cards are named by whose they are rather than by a click. Written
-- twice with opposite owner words it covers both seats without asking which of
-- them is up: "mine.battle → mine.bench" and "enemy.battle → enemy.bench" mean
-- the same pair of moves whoever reads them.
HANDLERS["move"] = function(p, ctx)
	local sc    = predicate.parse_scope(p[2] or "")
	local to_id = zone_id(p[3])
	if not (sc and to_id) then return end
	-- Snapshot before moving: the scope is recomputed from live zones, and a
	-- card that has already left would be counted from the zone it landed in.
	local moving = {}
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		if e.kind == "card" and e.zone_id and e.zone_id ~= to_id then moving[#moving + 1] = e.id end
	end
	table.sort(moving)
	if sc.quant == "random" and #moving > 0 then
		moving = { moving[rng.int(#moving)] }
	end
	for _, id in ipairs(moving) do zones.move_card(id, to_id) end
end

-- set_owner:<scope>:<who>  — hand those cards to a seat, or to nobody.
--
-- Whose a card is is decided once, when it is dealt, and then it *stays* decided
-- — so the only way it changes is a rule that says so out loud. Mind control is
-- "set_owner:target:mine"; a discard pile that anybody may take from is
-- "set_owner:target:none", said by the pile as things land in it rather than by
-- every card that might be thrown there.
--
-- Seats are numbered 1..N and nobody is 0, which is why "none" needs no separate
-- storage: tags.owner_of reads the number and finds no seat at 0. Unset is a
-- third thing and means "never had one", and it stays that way — a card that
-- was never anybody's is not the same as one taken away from somebody.
HANDLERS["set_owner"] = function(p, ctx)
	local sc  = predicate.parse_scope(p[2] or "")
	local who = p[3] or "none"
	if not sc then return end
	local G = declaration.G
	local i
	if who == "none" then i = 0
	elseif who == "mine" then i = (G.seat_index or {})[zones.active_seat()]
	else i = (G.seat_index or {})[who] end
	if not i then
		content_error("set_owner: '" .. tostring(who) .. "' is not a seat")
		return
	end
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		if e.kind == "card" and e.stats then e.stats.owner = i end
	end
end

-- destroy_self  — remove the acting card from play (pass cards, tokens).
HANDLERS["destroy_self"] = function(p, ctx)
	if ctx and ctx.card_id then zones.destroy_card(ctx.card_id) end
end

-- reveal:card_key  — conjure the card into the built-in page overlay. The
-- player commits blind, then reads the result; the revealed card's own
-- on_pick continues the story.
HANDLERS["reveal"] = function(p)
	local def     = declaration.G.card_defs[p[2] or ""]
	local zone_id = zones.find_id("reveal")
	if not def or not zone_id then
		content_error("reveal: unknown card " .. tostring(p[2]))
		return
	end
	cards.create(def.key, zone_id)
	phase.push("reveal")
end

-- options:<source>  — offer a choice. The source is either a zone, whose cards
-- name the choices, or a comma-separated list of card keys. Either way a fresh
-- card is dealt per choice into the offer, and the overlay opens.
--
-- The offer remembers **who asked**, because a choice is almost always about
-- something: a pawn asking what to become, a unit asking what to build. The
-- chosen card is played with the asker as its target, so it says
-- "transform:target:queen" and needs no marker stat to find it again.
--
-- Whatever is left in the offer is cleared when the choice is made — an offer
-- outlives its question by nothing. That also keeps the board free of invisible
-- cards, which is its own class of bug.
HANDLERS["options"] = function(p, ctx)
	local zone_id = zones.find_id("options")
	if not zone_id then
		content_error("options: this game has no options zone")
		return
	end
	local src, keys = p[2] or "", {}
	local from = zones.find(src)
	if from then
		for _, cid in ipairs(from.cards) do keys[#keys + 1] = entity.get(cid).def_key end
	else
		for key in src:gmatch("[^,]+") do keys[#keys + 1] = key end
	end
	if #keys == 0 then
		content_error("options: '" .. src .. "' names no zone and no cards")
		return
	end
	-- A choice about my piece is my choice, and wears my colours: the offer's
	-- cards take the asker's owner, so a named asset with one picture per player
	-- draws them the way the player expects without the game saying anything.
	local asker = ctx and ctx.card_id and entity.get(ctx.card_id)
	local owner = asker and asker.stats and asker.stats.owner
	for _, key in ipairs(keys) do
		if declaration.G.card_defs[key] then
			local made = cards.create(key, zone_id)
			if owner then made.stats.owner = owner end
		else
			content_error("options: no card is called '" .. tostring(key) .. "'")
		end
	end
	-- On the zone rather than in a module local, so it survives undo with
	-- everything else: entities are what snapshot and restore copy.
	local z = entity.get(zone_id)
	z.asked_by = ctx and ctx.card_id or nil
	-- An offer the rules opened is not a question that can be taken back — the
	-- thing that prompted it has already happened. Written every time rather
	-- than left to whatever the last offer set, which is how a mandatory choice
	-- inherited a stale permission to be declined.
	z.dismissable = nil
	phase.push("options")
end

-- reveal_top:zone  — turn over the top card of a (usually hidden, shuffled)
-- deck into the page overlay: a secret outcome decided by the shuffle.
HANDLERS["reveal_top"] = function(p)
	local from  = zone_of(p[2] or "")
	local to_id = zones.find_id("reveal")
	if from and to_id and #from.cards > 0 then
		zones.move_top(from.id, to_id)
		phase.push("reveal")
	end
end

-- effect:name  — play a named visual effect (defined under "effects" in the
-- game file) on the acting card. Pure presentation: headless runs skip it.
HANDLERS["effect"] = function(p, ctx)
	if M.on_effect and declaration.G.effect_defs[p[2] or ""] then
		M.on_effect(p[2], ctx)
	end
end

HANDLERS["resolve_challenge"] = function(p, ctx)
	if not ctx or not ctx.card_id then return end
	local c   = entity.get(ctx.card_id)
	local def = declaration.G.card_defs[c and c.def_key]
	if not def or not def.requires then return end

	-- With the context, so a challenge may ask about the card making it. Every
	-- shipped challenge asks a scope-free question ("do I hold the torch", "is
	-- there food"), which is why nothing noticed that "@self" and "@target"
	-- silently named nothing in here — a gate that reads as false whatever the
	-- board says.
	local passed = predicate.meets_all(def.requires, ctx)
	log.add((def.text or c.def_key) .. (passed and " — passed" or " — failed"))
	M.run(passed and def.on_pass or def.on_fail, ctx)
end

-- return_to:from_zone:to_zone  — move ALL cards currently in from_zone to
-- to_zone. Bounded by the starting count: a refill_when_empty source would
-- otherwise refill mid-drain and loop forever.
HANDLERS["return_to"] = function(p)
	local from = zone_of(p[2])
	local to_id = zone_id(p[3])
	if not from or not to_id then return end
	for _ = 1, #from.cards do
		if not zones.move_top(from.id, to_id) then break end
	end
end

-- move_target_to:zone  — move each targeted card to zone.
HANDLERS["move_target_to"] = function(p, ctx)
	local to_id = zone_id(p[2])
	if not to_id then return end
	for _, tid in ipairs(ctx and ctx.targets or {}) do
		zones.move_card(tid, to_id)
	end
end

-- place:<scope>:<col>:<row>  — put every card the scope names on that square of
-- the only board, 1-based, row 1 at the top. This is the move that is not a
-- move: it names where a piece ends up rather than how it travels, which is
-- what a rule with fixed destinations (castling, a return-to-base) needs and
-- what no direction can express. An occupied square refuses, so the caller's
-- gate is what makes a two-piece placement all-or-nothing.
HANDLERS["place"] = function(p, ctx)
	local sc = predicate.parse_scope(p[2] or "")
	local z  = zones.sole_grid()
	local at = p[3]
	if not (sc and z and at) then
		content_error("place: needs a scope and a square, as place:<who>:<square>")
		return
	end
	-- A square by name, or a pattern pointing at one from the acting card. The
	-- second is what lets a rule that works for both sides of a board say where
	-- something goes: "one column left of me" is the same sentence whichever end
	-- you are sitting at, where "f1" is only ever white's.
	local slot_id = geometry.slot_named(z, at)
	if not slot_id and declaration.G.pattern_defs[at] then
		slot_id = predicate.pattern_slots(at, ctx)[1]
	end
	if not slot_id then
		content_error("place: '" .. tostring(at) .. "' is neither a square nor a pattern pointing at one")
		return
	end
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		if e.kind == "card" and e.zone_id then zones.place_in_slot(e.id, slot_id) end
	end
end

-- transform:<scope>:<card>  — replace each card in scope with a new one of that
-- key, standing where it stood and belonging to whoever it belonged to.
--
-- A general verb rather than a promotion-shaped one: a pawn reaching the far
-- rank, a checker being crowned, a unit that levels up and a tile turned face
-- up are the same sentence. What carries over is *placement* — the square, the
-- zone, the owner — and nothing else, because the new card is a different card
-- and its numbers are its own.
HANDLERS["transform"] = function(p, ctx)
	local key = p[3]
	if not declaration.G.card_defs[key] then
		content_error("transform: no card is called '" .. tostring(key) .. "'")
		return
	end
	local sc = predicate.parse_scope(p[2] or "self")
	if not sc then return end
	-- Collected before any of it changes: the scope is recomputed from the
	-- board, and replacing the first card would move the ground under the rest.
	local doomed = {}
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		if e.kind == "card" and e.zone_id then doomed[#doomed + 1] = e end
	end
	for _, e in ipairs(doomed) do
		local zone, slot = e.zone_id, e.slot_id
		local owner = e.stats and e.stats.owner
		-- Out before in: the square has to be free, since place_in_slot refuses
		-- an occupied one and would otherwise leave the new card in limbo.
		zones.destroy_card(e.id)
		local new = cards.create(key, zone)
		if owner then new.stats.owner = owner end
		if slot then zones.place_in_slot(new.id, slot) else zones.auto_slot(new.id) end
		log.add(((cards.def(e) or {}).text or e.def_key) .. " became "
			.. (declaration.G.card_defs[key].text or key))
	end
end

-- attach_to_target  — attach ctx.card_id as a child of ctx.targets[1].
HANDLERS["attach_to_target"] = function(p, ctx)
	if not ctx or not ctx.card_id or not ctx.targets or #ctx.targets == 0 then return end
	local child  = entity.get(ctx.card_id)
	local parent = entity.get(ctx.targets[1])
	if not child or not parent then return end

	zones.move_card(child.id, parent.zone_id)
	child.parent_id = parent.id
	parent.attached[#parent.attached + 1] = child.id
end

-- Argument shape of every op: one word per colon-separated argument after
-- the op name. The validator derives its reference checks from this table,
-- so a new handler gets validation by declaring its shape here (the test
-- suite asserts no handler is missing).
-- Types: zone, card, stat (a full subject, so it may carry a scope),
-- phase, effect, gamefile, n (amount: number, count:<tag> or card:<key>),
-- occupied (what to do with a piece already standing there: "refuse",
-- "destroy", or the zone it goes to), any. A trailing "?" marks the argument
-- optional.
-- Networking, as something a card can do. The engine knows the *words* — so
-- the validator does too, and a game file naming them is checked like any other
-- — while the behaviour behind them lives entirely in net.lua and arrives only
-- if that module is loaded. Without it these are silent no-ops, which is the
-- right answer for a build with no networking in it.
--
-- This is invariant 7 reaching the last corner that still had a bespoke UI
-- policy. The panel used to ask "does this game have two seats, so should I
-- offer an invite?" — a question about content, answered in the presentation
-- layer. Now a two-player game deals a card that says "play this with a
-- friend", a solitaire game deals none, and nothing has to guess. Three seats,
-- a spectator, or a card that sits you in a particular chair are arguments to
-- these ops rather than branches in a panel.
local function net_ui(what)
	return function(p)
		if M.on_net then M.on_net(what, p[2]) end
	end
end

HANDLERS["net_invite"]  = net_ui("invite")
HANDLERS["net_join"]    = net_ui("join")
HANDLERS["net_panel"]   = net_ui("panel")
HANDLERS["net_seat"]    = net_ui("seat")
HANDLERS["net_offline"] = net_ui("offline")

-- set_active_seat:<scope>  — whoever the scope names becomes the seat whose turn
-- it is. Every other way of naming a seat was settled before the game started —
-- "mine" and "enemy" are relative to whoever is already up, a seat key is a
-- constant — so this is the only one that can be read off what just happened:
-- the trick winner leads the next trick, the attack token holder acts first.
--
-- **The scope names cards, and the seat is whose they are**, through the same
-- `seat_of` that "mine" asks. A seat card answers for itself, so
-- "set_active_seat:owner_of.target" and "set_active_seat:target" say the same
-- thing about an ordinary card and both work — one rule rather than two ways to
-- write it.
--
-- Naming two seats is refused: a rule that cannot say who is up has not decided
-- anything, and picking the first would make turn order depend on file order.
-- Naming none does nothing, which is an ordinary runtime state rather than a
-- mistake — the trick is not won until somebody has won it.
HANDLERS["set_active_seat"] = function(p, ctx)
	local sc = predicate.parse_scope(p[2] or "")
	local G  = declaration.G
	if not sc or #(G.seat_list or {}) < 2 then return end
	local seat
	for _, e in ipairs(predicate.entities_in_scope(sc.name, ctx, sc.owner)) do
		local k = predicate.seat_of(e)
		if k and k ~= seat then
			if seat then
				content_error("set_active_seat: '" .. p[2] .. "' names both " .. seat .. " and " .. k)
				return
			end
			seat = k
		end
	end
	local i = seat and (G.seat_index or {})[seat]
	if not i or seat == zones.active_seat() then return end
	local sys = zones.system_card()
	if not sys then return end
	sys.stats.turn = i
	-- The undo history goes with the seat that had it, exactly as it does when a
	-- turn ends normally: undoing across a handover rewrites somebody else's move.
	if M.on_seat_change then M.on_seat_change() end
	local def = G.card_defs[seat]
	log.add("— " .. ((def and def.text) or seat) .. " to play —")
end

-- Saving, and picking the game back up. The same shape as the net_ ops above:
-- the engine knows the words, so a game file naming them is validated like any
-- other, and the behaviour lives entirely in save.lua and arrives only if that
-- module is loaded. The slot is a plain word the game chooses — one autosave is
-- one word, three saves are three — so nothing here has an opinion about how
-- many saves a game keeps, and where they land is not the game's to say.
HANDLERS["save_game"] = function(p)
	if M.on_save then M.on_save("save", p[2]) end
end

-- Deferred like load_game, and for the same reason: what comes back replaces
-- every entity in the game, so the actions written after it in the list would
-- run against a world nobody wrote them for.
HANDLERS["load_save"] = function(p)
	if not p[2] then
		content_error("load_save: no slot named")
		return
	end
	M.pending_slot = p[2]
end

local SPEC = {
	fill              = "zone card n",
	shuffle           = "zone",
	draw_from         = "zone zone n",
	return_to         = "zone zone",
	move_to           = "zone? occupied?",
	add_to            = "zone",
	move_target_to    = "zone",
	place             = "scope any",
	stat_gain         = "stat n",
	stat_damage       = "stat n",
	stat_boost        = "stat n",
	stat_set          = "stat n",
	transform         = "scope card",
	attach_to_target  = "",
	net_invite        = "",
	net_join          = "",
	net_panel         = "",
	net_seat          = "any",
	net_offline       = "",
	resolve_challenge = "",
	next_phase        = "",
	push_phase        = "phase",
	pop_phase         = "",
	load_game         = "gamefile",
	destroy           = "scope",
	ready             = "scope",
	activate_zone     = "zone order?",
	move              = "scope zone",
	set_owner         = "scope seat",
	destroy_self      = "",
	options           = "any",
	reveal            = "card",
	reveal_top        = "zone",
	gain              = "card n",
	effect            = "effect",
	set_active_seat   = "scope",
	save_game         = "save",
	load_save         = "save",
}

-- The full op vocabulary, for the validator's suggestions — and for the test
-- that holds SCHEMA.json to describing every verb the engine actually runs.
function M.ops()
	local t = {}
	for k in pairs(HANDLERS) do t[k] = true end
	return t
end

-- The declared argument shape of an op (see SPEC above).
function M.spec(op)
	return SPEC[op]
end


function M.execute(str, ctx)
	local p = parse(str)
	local h = HANDLERS[p[1]]
	if h then
		h(p, ctx)
	else
		content_error("Unknown action: " .. str)
	end
end

function M.run(list, ctx)
	for _, str in ipairs(list or {}) do
		M.execute(str, ctx)
	end
end

-- A zone answering an arrival runs ordinary actions, and zones may not require
-- this file — so the dependency is closed here, at the end, where every handler
-- above already exists.
zones.run_actions = M.run

return M
