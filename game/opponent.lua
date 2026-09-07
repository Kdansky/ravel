-- A seat the engine could play: every move legal right now, as closures.
--
-- **This is not test scaffolding, and it is not dead code.** It lived in
-- `tests/run.lua` for as long as its only caller was the random terminator, and
-- moving it out is the first step of an engine-played opponent — see
-- [ideas/34](../ideas/34-an-opponent.md). A random opponent is `M.legal()` and
-- one `math.random`; what the rest of that track waits on is a game file being
-- able to say what winning looks like as a *number*, which is a format word
-- nobody has agreed yet. So a file with one function and two callers is the
-- expected shape here — do not fold it back into the tests.
--
-- Optional and additive: nothing in the engine requires it. It reads `flow`,
-- `zones`, `targeting` and `cards`, which is the same door the interfaces use,
-- so an opponent is another interface rather than a new layer.

local entity    = require("entity")
local zones     = require("zones")
local cards     = require("cards")
local phase     = require("phase")
local targeting = require("targeting")
local flow      = require("flow")

local M = {}

-- Every move available to whoever is up, as a list of closures. Calling one
-- makes it; the list is stale the moment any of them is called.
function M.legal()
	local moves = {}
	local cur = phase.current()
	if cur and cur.type == "overlay" then
		local oz = zones.find(cur.zone or "hand")
		for _, cid in ipairs(oz and oz.cards or {}) do
			moves[#moves + 1] = function() flow.play_card(cid, {}) end
		end
		return moves
	end
	local h = zones.find("hand")
	for _, cid in ipairs(h and h.cards or {}) do
		if flow.can_play(cid) then
			local spec = cards.def(entity.get(cid)).target
			moves[#moves + 1] = function()
				local targets = {}
				if spec then
					targeting.start(cid, spec)
					for k = 1, math.min(spec.min or spec.count or 0, #targeting.eligible) do
						targets[k] = targeting.eligible[k]
					end
					targeting.clear()
				end
				flow.play_card(cid, targets)
			end
		end
	end
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		-- Asked of the card, because a cost may be paid *with* it: "exhaust" asks
		-- whether this one is still ready, and a cost asked in the abstract has
		-- no answer. usable_abilities asks all of that, one entry at a time.
		if z and z.layout == "grid" then
			for _, u in ipairs(flow.usable_abilities(e.id)) do
				local id, idx = e.id, u.index
				moves[#moves + 1] = function() flow.activate(id, {}, idx) end
			end
		end
	end
	return moves
end

return M
