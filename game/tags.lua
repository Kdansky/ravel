local entity      = require("entity")
local declaration = require("declaration")

local M = {}

-- True if entity e has the given tag (direct def tag or computed tag from G).
function M.entity_has(e, tag)
    local G = declaration.G
    if e.kind == "card" then
        local def = G.card_defs[e.def_key]
        if def and def.tags_set and def.tags_set[tag] then return true end
    end
    local cd = G.computed_tags and G.computed_tags[tag]
    if not cd then return false end
    local s = e.stats or {}
    local v = s[cd.stat]
    if v == nil then return false end
    if cd.less_than      then return v < (tonumber(cd.less_than) or s[cd.less_than] or 0) end
    if cd.less_than_stat then return v < (s[cd.less_than_stat] or 0) end
    if cd.at_least       then return v >= (tonumber(cd.at_least) or 0) end
    if cd.equals         then return v == (tonumber(cd.equals) or 0) end
    return false
end

-- Return array of card entity IDs matching ALL filter_tags.
-- zone_set: {zone_type=true} restricts which zones to search; nil = any non-deck.
function M.find_targets(filter_tags, zone_set)
    local res = {}
    for e in entity.each("card") do
        local z = entity.get(e.zone_id)
        if z and z.zone_type ~= "deck" then
            local zone_ok = not zone_set or zone_set[z.zone_type] or zone_set[z.key]
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
