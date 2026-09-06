-- What a player-visible string may say about the thing it is written on.
--
-- A board shows what is where and says nothing about whose it is or which part
-- of the turn this is. Three labels were read off the engine instead of printed
-- — `current_phase`, `current_player`, `owning_player` — and each was the whole
-- string, so "Deck" and "whose deck" could not be said in one breath. This is
-- the same idea with the brace round it:
--
--   { "key": "deck", "label": "{owner}'s deck" }
--   { "key": "shards", "text": "{stats.count} of eight" }
--
-- `{` is the mark because it is the one that was free: `$` is Puzzle Strike's
-- money nineteen times over, and `<` and `[` are commoner still in card prose.
--
-- **Only the drawing substitutes.** The log, the network and every condition
-- name a thing by what the file called it, so a label is a caption and never an
-- identity.
--
-- Substituted once for an ordinary label. A seat's own text is the one
-- exception — {owner}/{active} resolve to it, and it may itself be a
-- template a set_name verb feeds — so that one path recurses, capped below.
local declaration = require("declaration")
local entity      = require("entity")
local phase       = require("phase")
local predicate   = require("predicate")
local zones       = require("zones")

local M = {}

-- The three that are not fields of anything. `owner` is about the thing wearing
-- the label — a per_seat zone drawn twice needs to say which copy this is — and
-- the other two are about the moment, so they answer the same wherever written.
M.RESERVED = { phase = true, active = true, owner = true }

-- Letters, digits, underscore and the dots between them. Anything else inside
-- braces is prose that happens to have a brace in it, and is left alone.
local NAME = "{([%w_%.]+)}"

-- Every name a string asks for, in order, without the braces. The validator
-- reads this; nothing else here is any use to it.
function M.names(s)
	local out = {}
	if type(s) == "string" then
		for name in s:gmatch(NAME) do out[#out + 1] = name end
	end
	return out
end

-- The seat's own card, live rather than the def: a renamed seat's card carries
-- its new name as an entity field, and only the entity sees it.
local function seat_card(seat)
	for e in entity.each("card") do
		if e.def_key == seat and e.zone_id then return e end
	end
end

-- Run through fill rather than read raw, so a seat whose text is "{name}"
-- shows the name a set_name verb gave it rather than the literal braces.
local function seat_text(seat)
	local def = seat and declaration.G.card_defs[seat]
	if not def then return seat end
	return M.fill(def.text, seat_card(seat))
end
M.seat_text = seat_text

local function dig(t, name)
	local v = t
	for part in name:gmatch("[^%.]+") do
		if type(v) ~= "table" then return nil end
		v = v[part]
	end
	return v
end

local function def_of(e)
	if e.kind == "zone" then return declaration.G.zone_defs[e.key] end
	if e.def_key then return declaration.G.card_defs[e.def_key] end
	return nil
end

-- The live entity first, its definition second. A card's `text` is on the def
-- and its `stats.health` is on the entity, and an author should not have to
-- know which — but the entity wins, because the entity is the current answer.
local function value(name, e)
	if name == "phase" then
		local cur = phase.current()
		return cur and (cur.label or cur.key)
	elseif name == "active" then
		return seat_text(zones.active_seat())
	elseif name == "owner" then
		if not e then return nil end
		return seat_text(e.kind == "zone" and e.seat or predicate.seat_of(e))
	end
	if not e then return nil end
	local v = dig(e, name)
	if v == nil then
		local def = def_of(e)
		v = def and dig(def, name) or nil
	end
	return v
end

-- 3, not 3.0: a label prints a count, and a count has no decimal point unless
-- the game put one there. A table or a boolean is not something a caption can
-- say, so it is treated as no answer at all and the braces stay.
local function shown(v)
	if type(v) == "string" then return v end
	if type(v) == "number" then
		return v % 1 == 0 and ("%d"):format(v) or tostring(v)
	end
	return nil
end

-- A name with no answer is left standing in its braces rather than blanked. A
-- label that reads "{ownr}'s deck" says where the typo is; one that reads "'s
-- deck" says a field went missing and not which.
--
-- Guarded rather than one-shot as the header still promises: seat_text now
-- calls back into fill to resolve a renamed seat's own text, and a seat whose
-- text names "{owner}" of itself would otherwise recurse without end. Depth
-- 4 is more than any real chain — zone -> owner -> seat -> name -- needs.
local depth = 0
function M.fill(s, e)
	if type(s) ~= "string" or not s:find("{", 1, true) or depth >= 4 then return s end
	depth = depth + 1
	local out = s:gsub(NAME, function(name)
		return shown(value(name, e)) or ("{" .. name .. "}")
	end)
	depth = depth - 1
	return out
end

return M
