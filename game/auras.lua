-- Auras: what a tag says about a verb aimed at a number.
--
-- Above predicate on purpose. See the note on `watching` below for why this is
-- not in tags.lua, where it lived until the layering was untangled.
local entity      = require("entity")
local declaration = require("declaration")
local predicate   = require("predicate")
local tags        = require("tags")
local zones       = require("zones")

local M = {}

-- **What is done to a card, as against what it is.** `tags.buff` answers the
-- first — what a number *is* while a card wears a word. This answers the second:
-- what a verb aimed at that number *comes to*, once every aura with an opinion
-- has spoken.
--
-- They were one module, and that is what made tags.lua need predicate. An aura
-- reads scopes, conditions and amounts, so this is built on the condition
-- language rather than under it — where a tag, which a condition asks about, has
-- to sit below. Two layers in one file is why three of tags.lua's requires had to
-- be written inside the functions that used them.
--
-- Every `adjusts` watching this verb and this stat, from every aura in play that
-- covers this card and whose own `needs` hold, handed to `fn` with the context it
-- was judged in. Two words read the one index the same way — `shift` sums what
-- the aura says the number comes to, `instead` collects what it says happens in
-- the change's place — and walking it twice was how the pair drifted apart the
-- last time there were two copies of it.
--
-- `n` is how big the change is, as a player reads it: "3 damage" is 3, never the
-- negative the engine carries. Bound as `amount`, so an aura can ask about the
-- size of what it is watching and hand it on — *draw for each point of wasted
-- healing* is one number, and there is nowhere else for it to come from. A cost
-- has no size at the moment it is judged, so resist passes nothing and the name
-- is simply not bound there.
local function watching(card_id, verb, stat, source_id, n, fn)
    local list = verb and declaration.G.adjust_index[verb .. ":" .. stat]
    if not list or not card_id then return end
    for _, entry in ipairs(list) do
        local ad = entry.adjust
        for _, holder in ipairs(zones.find_targets({ entry.tag }, zones.IN_PLAY)) do
            -- Held as the aura's own side, for entity_has's reason: an aura is
            -- read whenever anything asks what a number comes to, which is no
            -- moment and so has no seat of its own. Around the whole body, so
            -- that who it covers and whether it applies are both answered from
            -- the card the aura is printed on.
            local seat = predicate.seat_of(entity.get(holder))
            zones.as_seat(seat, function()
                -- "self" is the whole of a keyword and does not go the long way round
                -- through a scope; anything else is read from the card holding the
                -- aura, so an anthem says who it covers in the words a scope already
                -- uses.
                local covered = holder == card_id
                if not covered and ad.covers ~= "self" then
                    local sc = predicate.parse_scope(ad.covers)
                    for _, c in ipairs(sc and predicate.entities_in_scope(sc.name,
                        { card_id = holder }, sc.owner, sc.quant) or {}) do
                        if c.id == card_id then covered = true; break end
                    end
                end
                local sub = { card_id = holder, targets = { card_id }, source = source_id,
                    let = n and { amount = n } or nil }
                if covered and entity.get(holder) and predicate.meets_all(ad.needs, sub) then
                    fn(ad, sub, seat)
                end
            end)
        end
    end
end

-- The signed sum of what the watching auras say the number comes to. Signed, and
-- nothing is clamped here: what "may not change the sign" means depends on what
-- is being shifted — a delta may not turn harm into help, a price may not fall
-- below free — and neither rule belongs to the summing.
--
-- One function because there was one word and two copies of it: damage went
-- through `actions.adjusted` and a cost through `flow.resisted`, walking the same
-- index the same way, and the pair had already drifted far enough that one built
-- a set of covered cards and the other a boolean.
function M.shift(card_id, verb, stat, source_id, size)
    local n = 0
    watching(card_id, verb, stat, source_id, size, function(ad, sub)
        -- An aura that answers with an `instead` is not saying a size, and has
        -- nothing to add to a total it was never about.
        if ad.by ~= nil then
                    n = n + (tonumber(ad.by) or predicate.total(tostring(ad.by), sub))
        end
    end)
    return n
end

-- **What happens in place of the change.** The other thing an aura may say about
-- a verb it watches: not that the number arrives different, but that it does not
-- arrive at all and this happens instead. *Whenever you would normally heal
-- damage, ignore all healing and give 1 CURSE instead* is not healing less, so no
-- `by` reaches it.
--
-- One entry per aura that spoke, each with the action list, the context it was
-- judged in — the aura as @self, the card that would have changed as @target —
-- and the side to run it as, which is the holder's for `watching`'s reason.
function M.instead(card_id, verb, stat, source_id, size)
    local out = {}
    watching(card_id, verb, stat, source_id, size, function(ad, sub, seat)
        if ad.instead then out[#out + 1] = { action = ad.instead, ctx = sub, seat = seat } end
    end)
    return out
end

return M
