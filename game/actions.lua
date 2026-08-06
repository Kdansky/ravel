local entity      = require("entity")
local declaration = require("declaration")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local tags        = require("tags")
local predicate   = require("predicate")
local log         = require("log")

local M = {}

M.pending_load   = nil   -- set by load_game, consumed by flow after the action list
M.on_stat_change = nil   -- optional hook(entity, key, delta) for visual feedback
M.on_effect      = nil   -- optional hook(name, ctx): presentation plays the named effect

function M.take_load()
	local f = M.pending_load
	M.pending_load = nil
	return f
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

-- Every numeric slot accepts a number, "count:<tag>" (board cards with that
-- tag) or "card:<key>" (board instances of that template), e.g.
-- "gain_stat:gold:count:economic". One rule everywhere.
local function amount(p, i, default)
	if p[i] == "count" or p[i] == "card" then
		return predicate.total(p[i] .. ":" .. tostring(p[i + 1]))
	end
	return tonumber(p[i]) or default or 0
end

-- Find the first entity that holds this stat (has a non-nil value for it).
local function stat_holder(key)
	for e in entity.each() do
		if e.stats and e.stats[key] ~= nil then return e end
	end
end

-- Change a stat on an entity, clamped to the stat's declared min/max and,
-- when a "<key>_max" companion stat exists, to [0, <key>_max].
local function change_stat(e, key, delta)
	if not e or not e.stats then return end
	local old = e.stats[key] or 0
	local v   = old + delta
	local def = declaration.G.stat_defs[key]
	if def then
		if def.min and v < def.min then v = def.min end
		if def.max and v > def.max then v = def.max end
	end
	local cap = e.stats[key .. "_max"]
	if cap then v = math.max(0, math.min(v, cap)) end
	e.stats[key] = v
	if v ~= old then
		local txt = string.format("%+d %s", v - old, key)
		if e.kind == "card" then
			local d = declaration.G.card_defs[e.def_key]
			txt = (d and d.text or e.def_key) .. " " .. txt
		end
		log.add(txt)
		if M.on_stat_change then M.on_stat_change(e, key, v - old) end
	end
end

-- Entities in a subject's scope that actually carry its stat. Filtering here
-- matters: change_stat would happily invent the stat on a card that never had
-- one, so "every beast loses hp" must not give hp to something that has none.
local function bearers(p, ctx)
	local out = {}
	for _, e in ipairs(predicate.entities_in_scope(p.scope, ctx)) do
		if e.stats and e.stats[p.arg] ~= nil then out[#out + 1] = e end
	end
	return out
end

-- Apply a delta to whatever a subject names, honouring its quantifier:
-- each/target/self reach every member, random picks one with the seeded RNG,
-- and the pooled default lands on the first. A subject with no scope keeps the
-- old behaviour exactly — whoever holds the stat.
local function apply_stat(subject, delta, ctx)
	local p = predicate.parse_subject(subject)
	if not p then return end
	if not p.scope then
		change_stat(stat_holder(p.arg), p.arg, delta)
		return
	end
	local ents = bearers(p, ctx)
	if #ents == 0 then return end
	if p.quant == "each" then
		for _, e in ipairs(ents) do change_stat(e, p.arg, delta) end
	elseif p.quant == "random" then
		change_stat(ents[math.random(#ents)], p.arg, delta)
	else
		change_stat(ents[1], p.arg, delta)
	end
end

-- Spend n of a subject. "each" takes n from every member; the pooled default
-- drains members in id order until n is covered — deterministic, so a seeded
-- replay pays the same cards in the same order.
function M.spend(subject, n, ctx)
	local p = predicate.parse_subject(subject)
	if not p then return end
	if not p.scope then
		change_stat(stat_holder(p.arg), p.arg, -n)
		return
	end
	local ents = bearers(p, ctx)
	if p.quant == "each" then
		for _, e in ipairs(ents) do change_stat(e, p.arg, -n) end
		return
	end
	table.sort(ents, function(a, b) return a.id < b.id end)
	local left = n
	for _, e in ipairs(ents) do
		if left <= 0 then break end
		local take = math.min(tonumber(e.stats[p.arg]) or 0, left)
		if take > 0 then
			change_stat(e, p.arg, -take)
			left = left - take
		end
	end
end

local HANDLERS = {}

HANDLERS["fill"] = function(p)
	-- fill:zone:card_key:n
	local zone = zones.find(p[2] or "")
	if not zone then
		content_error("fill: unknown zone " .. tostring(p[2]))
		return
	end
	if not declaration.G.card_defs[p[3] or ""] then
		content_error("fill: unknown card " .. tostring(p[3]))
		return
	end
	for _ = 1, amount(p, 4, 1) do
		if not zones.has_room(zone) then break end
		zones.auto_slot(cards.create(p[3], zone.id).id)
	end
end

HANDLERS["shuffle"] = function(p)
	local zone_id = zones.find_id(p[2])
	if zone_id then zones.shuffle(zone_id) end
end

HANDLERS["draw_from"] = function(p)
	-- draw_from:from:to:n  (n defaults to 1)
	local from_id = zones.find_id(p[2])
	local to_id   = zones.find_id(p[3] or "hand")
	if not from_id or not to_id then return end
	for _ = 1, amount(p, 4, 1) do
		if not zones.move_top(from_id, to_id) then break end
	end
end

-- The only grid zone, when there is exactly one — the fallback destination
-- for cards without a home tag in single-board games.
local function sole_grid()
	local found
	for z in entity.each("zone") do
		if z.zone_type == "grid" then
			if found then return nil end
			found = z.key
		end
	end
	return found
end

HANDLERS["move_to"] = function(p, ctx)
	-- move_to:zone  —  moves ctx.card_id to zone; if first target is a slot in that zone, uses place_in_slot.
	-- Without a zone the card's home (a tag naming a zone) decides, falling
	-- back to the only board; the validator flags the ambiguous cases.
	if not ctx or not ctx.card_id then return end
	local dest = p[2]
	if not dest then
		local c   = entity.get(ctx.card_id)
		local def = c and declaration.G.card_defs[c.def_key]
		dest = (def and cards.home_zone(def)) or sole_grid()
	end
	local to_id = dest and zones.find_id(dest)
	if not to_id then return end
	local t1  = ctx.targets and ctx.targets[1]
	local tgt = t1 and entity.get(t1)
	if tgt and tgt.kind == "slot" and tgt.zone_id == to_id then
		zones.place_in_slot(ctx.card_id, tgt.id)
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
		if not zones.has_room(zone) then break end
		zones.auto_slot(cards.create(def.key, zone.id).id)
	end
end

HANDLERS["add_to"] = function(p, ctx)
	-- add_to:zone  —  same as move_to but never slot-targeted (overlay on_pick context)
	local to_id = zones.find_id(p[2])
	if to_id and ctx and ctx.card_id then
		zones.move_card(ctx.card_id, to_id)
	end
end

HANDLERS["gain_stat"] = function(p, ctx)
	apply_stat(p[2], amount(p, 3), ctx)
end

HANDLERS["lose_stat"] = function(p, ctx)
	apply_stat(p[2], -amount(p, 3), ctx)
end

HANDLERS["spend_stat"] = HANDLERS["lose_stat"]

HANDLERS["set_stat"] = function(p, ctx)
	local sp = predicate.parse_subject(p[2])
	if not sp then return end
	if not sp.scope then
		local e = stat_holder(sp.arg)
		if e then e.stats[sp.arg] = amount(p, 3) end
		return
	end
	for _, e in ipairs(predicate.entities_in_scope(sp.scope, ctx)) do
		if e.stats and e.stats[sp.arg] ~= nil then e.stats[sp.arg] = amount(p, 3) end
	end
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

-- destroy:zone  — remove every card in the zone from play.
HANDLERS["destroy"] = function(p)
	local z = zones.find(p[2])
	if not z then return end
	while #z.cards > 0 do zones.destroy_card(z.cards[#z.cards]) end
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

-- reveal_top:zone  — turn over the top card of a (usually hidden, shuffled)
-- deck into the page overlay: a secret outcome decided by the shuffle.
HANDLERS["reveal_top"] = function(p)
	local from  = zones.find(p[2] or "")
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

	local passed = predicate.meets_all(def.requires)
	log.add((def.text or c.def_key) .. (passed and " — passed" or " — failed"))
	M.run(passed and def.on_pass or def.on_fail, ctx)
end

-- return_to:from_zone:to_zone  — move ALL cards currently in from_zone to
-- to_zone. Bounded by the starting count: a refill_when_empty source would
-- otherwise refill mid-drain and loop forever.
HANDLERS["return_to"] = function(p)
	local from = zones.find(p[2])
	local to_id = zones.find_id(p[3])
	if not from or not to_id then return end
	for _ = 1, #from.cards do
		if not zones.move_top(from.id, to_id) then break end
	end
end

-- These three are now special cases of the scope grammar, kept as aliases so
-- shipped games keep working:
--   gain_target_stat:hp:2   ==  gain_stat:hp@target:2
--   lose_target_stat:hp:2   ==  lose_stat:hp@target:2
--   damage_random:beast:hp:2 == lose_stat:hp@random.beast:2
HANDLERS["gain_target_stat"] = function(p, ctx)
	apply_stat(p[2] .. "@target", amount(p, 3), ctx)
end

HANDLERS["lose_target_stat"] = function(p, ctx)
	apply_stat(p[2] .. "@target", -amount(p, 3), ctx)
end

-- move_target_to:zone  — move each targeted card to zone.
HANDLERS["move_target_to"] = function(p, ctx)
	local to_id = zones.find_id(p[2])
	if not to_id then return end
	for _, tid in ipairs(ctx and ctx.targets or {}) do
		zones.move_card(tid, to_id)
	end
end

-- damage_random:tag:stat:n  — a random on-board card with the tag loses n.
HANDLERS["damage_random"] = function(p, ctx)
	apply_stat(tostring(p[3]) .. "@random." .. tostring(p[2]), -amount(p, 4, 1), ctx)
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
-- Types: zone, card, stat, cardstat (a stat carried by cards), phase, tag,
-- n (amount: number, count:<tag> or card:<key>), any. A trailing "?" marks
-- the argument optional.
local SPEC = {
	fill              = "zone card n",
	shuffle           = "zone",
	draw_from         = "zone zone n",
	return_to         = "zone zone",
	move_to           = "zone?",
	add_to            = "zone",
	move_target_to    = "zone",
	gain_stat         = "stat n",
	lose_stat         = "stat n",
	spend_stat        = "stat n",
	set_stat          = "stat n",
	gain_target_stat  = "cardstat n",
	lose_target_stat  = "cardstat n",
	damage_random     = "tag cardstat n",
	attach_to_target  = "",
	resolve_challenge = "",
	next_phase        = "",
	push_phase        = "phase",
	pop_phase         = "",
	load_game         = "gamefile",
	destroy           = "zone",
	destroy_self      = "",
	reveal            = "card",
	reveal_top        = "zone",
	gain              = "card n",
	effect            = "effect",
}

-- True if the op exists; used by the load-time validator.
function M.known(op)
	return HANDLERS[op] ~= nil
end

-- The full op vocabulary, for the validator's suggestions.
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

return M
