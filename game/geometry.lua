-- Grid arithmetic: which squares a pattern reaches from a square. Pure — no
-- session state, no presentation — so the rules layer and the tests ask the
-- same question and get the same answer.
--
-- The one idea this file rests on: **a pattern's pair is a direction, not a
-- destination.** Applying it repeatedly is what a path *is*, so blocking,
-- leaping and limited range stop being three rules and become one loop bound
-- and one break. A knight leaps because [1,2] applied once has nothing before
-- it, not because anything was declared about knights.

local entity = require("entity")

local M = {}

-- The slot at (col, row), or nil when that is off the board. Row-major and
-- 1-based, the same arithmetic zones uses to build and to draw them.
function M.slot_at(z, col, row)
	local cols, rows = z.grid[1], z.grid[2]
	if col < 1 or col > cols or row < 1 or row > rows then return nil end
	return z.slots[(row - 1) * cols + col]
end

-- Which way "forward" points for a seat, so one pawn template serves both
-- colours. Rows count downward from the top of the board and the first seat
-- sits nearest the viewer, so it advances toward row 1.
--
-- Only a two-seat board has an honest answer here. A game with four players
-- around a table has no shared notion of forward at all, and rather than
-- invent one this returns "away from the top" for everyone else — such games
-- should write their vectors out per seat instead of leaning on this.
function M.facing(seat, seat_list)
	return seat_list[1] == seat and -1 or 1
end

-- A piece's rank: its row counted from its *owner's* own side, so the home row
-- is 2 for both colours and the far side is 8 for both. Stamped onto the piece
-- by zones as it takes a square.
function M.rank(z, row, facing)
	return facing < 0 and (z.grid[2] + 1 - row) or row
end

-- The named squares of an absolute pattern. No anchor, no facing, no walking:
-- the pairs are cells, so there is no path to be blocked and nothing to repeat.
function M.squares(pat, z)
	local out = {}
	if not (z and z.grid) then return out end
	for _, v in ipairs(pat.vectors or {}) do
		local sid = M.slot_at(z, v[1], v[2])
		if sid then out[#out + 1] = sid end
	end
	return out
end

-- Every slot `pat` reaches from `from_id`.
--
-- A destination is offered even when something stands on it — whether landing
-- there is legal is the "fill" word's business, not geometry's — but an
-- occupied square *stops* the ray, so a rook takes the first enemy on the file
-- and nothing behind it. `phasing` is the piece that ignores that.
function M.reach(from_id, pat, facing)
	local from = entity.get(from_id)
	local z    = from and from.zone_id and entity.get(from.zone_id)
	if not (z and z.grid and from.stats) then return {} end
	-- An absolute pattern names where to go, so where it is asked from only
	-- decides which board is meant.
	if pat.absolute then return M.squares(pat, z) end
	-- A ray is bounded by the board: no vector survives more repetitions than
	-- the longest side, and this is also what keeps an unbounded range finite.
	local limit = math.min(pat.range or 1, math.max(z.grid[1], z.grid[2]))
	local out, seen = {}, {}
	for _, v in ipairs(pat.vectors or {}) do
		local dx, dy   = v[1], v[2] * (facing or 1)
		local col, row = from.stats.col, from.stats.row
		for _ = 1, limit do
			col, row = col + dx, row + dy
			local sid = M.slot_at(z, col, row)
			if not sid then break end
			if not seen[sid] then
				seen[sid]    = true
				out[#out + 1] = sid
			end
			if not pat.phasing and entity.get(sid).occupant then break end
		end
	end
	return out
end

return M
