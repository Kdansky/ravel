-- **What a number on a card comes to.** One module for the whole of a stat: what
-- is written on the card, what that comes to once the tags it wears have had
-- their say, the floor and ceiling it is held between, and the clamp that holds
-- it there.
--
-- It sits here rather than in tags.lua because a buff is one contributor to a
-- number and not the number itself, and it sits in one module rather than two
-- because the read and the clamp are halves of a single rule: **arithmetic on
-- what the stat is, storage of what is left after the tags had their say.** They
-- were split — the read in tags.lua, the clamp in actions.lua — and each had its
-- own copy of "the ceiling rises with the buff", written out twice with the same
-- three-line comment. Five call sites across the engine had drifted onto the
-- stored number instead of this one before anything noticed.
--
-- Everything that asks the board about a number comes through here. Only
-- actions.lua writes `e.stats`, and it writes back what is left after the buff.
local declaration = require("declaration")
local tags        = require("tags")

local M = {}
local EMPTY = {}

-- What is written on the card. The printed number plus whatever has been done to
-- it, and **not** what any tag says about it — a level-up setting attack to 2
-- prints 2 and still reads 3 in the elite post, because the bonus belongs to the
-- tag and goes when the tag does.
function M.stored(e, key)
	if not (e and e.stats) then return 0 end
	return tonumber(e.stats[key]) or 0
end

-- What the card *has*. Every condition, compute, cost, amount and badge in the
-- game asks this one.
function M.current(e, key)
	if not (e and e.stats) then return 0 end
	return M.stored(e, key) + tags.buff(e, key)
end

-- **The ceiling rises with the value it bounds, and the floor does not.** A 1/1
-- handed +1/+1 has to be able to reach 2, or the buff is clamped away before it
-- is worth anything — and it has to be able to reach 0, or two damage leaves it
-- alive on the one point it was printed with. Those are the two ends and they
-- want different treatment, which is why they are two functions and not a pair.
--
-- The card's own bound wins over the stat's, and a stat with neither is
-- unbounded rather than bounded at nought: a stat with no ceiling grows, and one
-- with no floor may go negative, which is what lets a blocker carry its own
-- overkill.
function M.ceiling(e, key)
	local hi = e and e.stat_max and e.stat_max[key]
	if hi == nil then hi = (declaration.G.stat_defs[key] or EMPTY).max end
	if hi == nil then return nil end
	return hi + tags.buff(e, key)
end

function M.floor(e, key)
	local lo = e and e.stat_min and e.stat_min[key]
	if lo == nil then lo = (declaration.G.stat_defs[key] or EMPTY).min end
	return lo
end

-- Held between the two. Either end may be absent, which is what an unbounded
-- stat is; nothing is invented to stand in for one.
function M.clamp(e, key, v)
	local lo, hi = M.floor(e, key), M.ceiling(e, key)
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end

return M
