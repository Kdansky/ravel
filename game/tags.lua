local entity      = require("entity")
local declaration = require("declaration")

local M = {}

-- A computed tag asked about while it is being worked out. Cheaper than the
-- validator's cycle walk and not a substitute for it: this is the seatbelt,
-- exactly as `busy` is for buffs, so a bad file gets a defined answer instead of
-- a stack that runs out. Keyed on the tag rather than the card, because a tag
-- asking about a tag asks about one card all the way down.
local resolving = {}

-- True if entity e has the given tag: one it was defined with, one the zone it
-- sits in grants ("applies"), or a computed one, whose condition is asked with
-- this card as @self.
-- Where a card *is* can therefore decide what it is — bounded on purpose to the
-- tags a game declares, and to a fixed list on the zone. A computed tag's
-- condition is worked out on every ask rather than stored, which is what keeps
-- it honest: there is no cached answer to fall out of step with the card.
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
    if resolving[tag] then return false end
    resolving[tag] = true
    local worn
    -- **A union, which is how the format says "or" about kinds.** A condition
    -- list is an `and` and a scope names one tag, so "a CURSE or an ICE" had no
    -- spelling at all: the two cards have nothing in common to point at. Naming
    -- the union once, centrally, gives it something -- and because every tag
    -- question in the engine comes through here, the name then works wherever a
    -- tag works: in a scope, in `tagged:`, in a count, in a target spec.
    --
    -- It is the only thing here that is not a condition, because it is the only
    -- one a condition cannot say. Its counterpart went: "every one of these
    -- tags" is a list of `tagged:` conditions, and a list already means and.
    if cd.any_of then
        worn = false
        for _, t in ipairs(cd.any_of) do
            if M.entity_has(e, t) then worn = true; break end
        end
    else
        -- **The one condition grammar, asked about one card.** This used to be
        -- six fields -- stat, less_than, less_than_stat, less_than_max, at_least
        -- and equals -- which between them made a second comparison language
        -- with three operators, no "greater than" and no "not equal", beside the
        -- one the rest of the file is written in. "hp@self < 1" says it in the
        -- words a needs, a route and an end condition already use.
        --
        -- Every subject wants its @self: a bare stat means the seat that is up,
        -- and this is asked about a particular card. The card is the ctx, so
        -- @self is it.
        --
        -- Required here rather than at the top of the file: predicate is built
        -- on tags, so naming it up there would be a cycle. By the time anything
        -- asks about a tag, both are loaded.
        worn = require("predicate").meets_all(cd.needs, { card_id = e.id })
    end
    resolving[tag] = nil
    return worn
end

-- **A tag may shift a stat, and the shift is never written down.** "elite" says
-- `"buffs": { "atk": 1 }` and every card wearing it reads one higher, for as
-- long as it wears it — which is the whole of a continuous effect. Nothing is
-- applied when the tag arrives and nothing is restored when it goes, because
-- there is no stored number to get out of step: the tag *is* the effect, and a
-- card that stops wearing it stops reading higher in the same instant.
--
-- That is why this is a read and not an action. A +1/+1 written as `stat_gain`
-- has to be undone by whoever took it away, on every path it could leave by,
-- and a game gets one of those paths wrong. Codex kept a hidden `elited` stat
-- for exactly that bookkeeping and undid it in ten places.
--
-- The three tag sources all count, so the shift can come from what a card *is*
-- (a printed keyword), from where it *stands* (a zone's `applies` — the whole
-- of "gets +1 while in the duel"), or from how it *is doing* (a computed tag —
-- "gets +1 while damaged"). The last one is why a cycle is possible at all, and
-- why the validator refuses a computed tag that buffs the stat it reads.
-- A stat asked for while it is already being worked out. The validator refuses
-- the shape that causes it, so this is the seatbelt: a bad file gets a defined
-- answer instead of a stack that runs out.
local busy = {}

function M.buff(e, key)
    local list = declaration.G.buff_index and declaration.G.buff_index[key]
    if not list or not e or busy[key] then return 0 end
    busy[key] = true
    local n = 0
    for _, b in ipairs(list) do
        if M.entity_has(e, b.tag) then n = n + b.n end
    end
    busy[key] = nil
    return n
end

-- What a stat *is*, as against what is stored on the card. Everything that
-- asks the board a question comes through here; only the writer in actions.lua
-- touches `e.stats` directly, and it stores the base back after clamping.
function M.stat(e, key)
    if not (e and e.stats) then return 0 end
    return (tonumber(e.stats[key]) or 0) + M.buff(e, key)
end

-- A ceiling rises with the value it bounds. Without this a 1/1 handed +1/+1
-- would be clamped straight back to 1 and the buff would do nothing at all —
-- and `damaged` (below its own maximum) would call a freshly buffed card hurt.
function M.stat_max(e, key)
    local hi = e and e.stat_max and e.stat_max[key]
    if hi == nil then hi = (declaration.G.stat_defs[key] or {}).max end
    if hi == nil then return nil end
    return hi + M.buff(e, key)
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
-- zone_set: {layout=true} restricts which zones to search; M.IN_PLAY means
-- wherever cards are in play; nil = anywhere cards can be used at all.
function M.find_targets(filter_tags, zone_set)
    local res = {}
    for e in entity.each("card") do
        local z = entity.get(e.zone_id)
        if z and z.use ~= "none" then
            local zone_ok
            if zone_set == M.IN_PLAY then zone_ok = z.status == "board"
            else zone_ok = not zone_set or zone_set[z.layout] or zone_set[z.key] end
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
