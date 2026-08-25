local entity      = require("entity")
local declaration = require("declaration")

local M = {}

-- True if entity e has the given tag: one it was defined with, one the zone it
-- sits in grants ("applies"), or a computed one derived from its stats.
-- Where a card *is* can therefore decide what it is — bounded on purpose to a
-- fixed list declared on the zone, so this stays one lookup and never becomes
-- the recomputation problem that auras are.
function M.entity_has(e, tag)
    local G = declaration.G
    if e.kind == "card" then
        local def = G.card_defs[e.def_key]
        if def and def.tags_set and def.tags_set[tag] then return true end
        local z = e.zone_id and entity.get(e.zone_id)
        for _, granted in ipairs(z and z.applies or {}) do
            if granted == tag then return true end
        end
    end
    local cd = G.computed_tags and G.computed_tags[tag]
    if not cd then return false end
    local s = e.stats or {}
    local v = s[cd.stat]
    if v == nil then return false end
    if cd.less_than      then return v < (tonumber(cd.less_than) or s[cd.less_than] or 0) end
    -- Below its own ceiling: "damaged", the commonest computed tag there is.
    -- It used to be written less_than_stat: hp_max, which only worked while a
    -- maximum was a stat in its own right — the card carried a number called
    -- hp_max that counting and spending could reach as readily as hp.
    if cd.less_than_max then
        local hi = e.stat_max and e.stat_max[cd.stat]
        return hi ~= nil and v < hi
    end
    if cd.less_than_stat then return v < (s[cd.less_than_stat] or 0) end
    if cd.at_least       then return v >= (tonumber(cd.at_least) or 0) end
    if cd.equals         then return v == (tonumber(cd.equals) or 0) end
    return false
end

-- Whose *piece* this is: the seat written on it when it was placed, or failing
-- that the seat of the per-seat zone it lies in.
--
-- The stat exists for boards that are shared while the pieces on them are not.
-- A chessboard is one zone — the pieces stand on the same squares — so without
-- it every piece would be unowned and "enemy" would name nothing.
--
-- **It is placement state, and that is the point.** Ownership is decided where a
-- piece is put on the board, which is exactly where `setup.place` says it. It
-- used to be a tag the *template* wore, which forced one template per owner and
-- so a `white` and a `black` copy of every piece — thirty-two cards to say six
-- things. As a stat it snapshots for free, reads through the ordinary condition
-- vocabulary (`owner@target`), and one `rook` can be placed four times.
--
-- **A tag outranks the zone**, because a zone's seat is where a thing *is* and
-- a tag is whose it *is*, and those come apart the moment a game has more than
-- two players: a planet held by player three, sitting in player two's system,
-- is player three's to lose and player one's to attack. Ambient ownership is a
-- default; an explicit claim beats it.
--
-- A seat card is nobody's piece, including its own. A party game tags four
-- characters "player" and so has four seats, and all four must stay usable on
-- one turn — you are not among the things you own.
--
-- Lives here rather than in predicate.lua because zones needs it too (to stamp
-- a piece's rank, which counts from its owner's own side) and predicate is
-- built on top of zones.
function M.owner_of(e)
	if not e then return nil end
	if e.kind == "zone" then return e.seat end
	local G = declaration.G
	local i = e.stats and e.stats.owner
	if i then return (G.seat_list or {})[i] end
	local z = e.zone_id and entity.get(e.zone_id)
	return z and z.seat
end

-- The rules that mean "in play" ask for it by name. They used to pass
-- { grid = true } — the shape a board happened to have — which is why a row of
-- ongoing effects laid face up in front of one player could not be counted,
-- sacrificed or asked to act. A sentinel rather than a key, so no zone can
-- collide with it by being called the wrong thing.
M.IN_PLAY = {}

-- Return array of card entity IDs matching ALL filter_tags.
-- zone_set: {zone_type=true} restricts which zones to search; M.IN_PLAY means
-- wherever cards are in play; nil = any non-deck.
function M.find_targets(filter_tags, zone_set)
    local res = {}
    for e in entity.each("card") do
        local z = entity.get(e.zone_id)
        if z and z.zone_type ~= "deck" then
            local zone_ok
            if zone_set == M.IN_PLAY then zone_ok = z.status == "board"
            else zone_ok = not zone_set or zone_set[z.zone_type] or zone_set[z.key] end
            if zone_ok then
                local match = true
                for _, tag in ipairs(filter_tags) do
                    if not M.entity_has(e, tag) then match = false; break end
                end
                if match then res[#res + 1] = e.id end
            end
        end
    end
    return res
end

return M
