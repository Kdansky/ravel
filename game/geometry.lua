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
-- A square by the name a player would say: a column letter and a rank counted
-- from the bottom, "a1" through "h8" on a chessboard. Ranks count up from the
-- near edge because that is what algebraic notation means; the grid indexes
-- rows from the top, and this is the one place the two meet.
--
-- Not chess-only: any grid can be addressed this way, and a setup that says
-- "e1" instead of "slot 61" is a setup a person can check against a board.
function M.square(z, name)
	if type(name) ~= "string" or not z.grid then return nil end
	local letters, rank = name:lower():match("^(%a+)(%d+)$")
	if not letters then return nil end
	local col = 0
	for i = 1, #letters do col = col * 26 + (letters:byte(i) - 96) end
	return col, tonumber(rank)
end

function M.slot_named(z, name)
	local col, rank = M.square(z, name)
	return col and M.slot_at(z, col, rank) or nil
end

-- **The one place a rank becomes a row.** Everything above this line counts
-- from the bottom-left, the way a player reads a board; the cells themselves
-- are laid out top-down because that is the order they are drawn in. Keeping
-- the conversion to a single function is what stops the two being confused,
-- which they were: castling once put the white king on g8 because a rank was
-- passed where a row was wanted, and the file still validated.
function M.slot_at(z, col, rank)
	local cols, rows = z.grid[1], z.grid[2]
	if col < 1 or col > cols or rank < 1 or rank > rows then return nil end
	local row = rows + 1 - rank
	return z.slots[(row - 1) * cols + col]
end

-- Which way "forward" points for a seat, so one pawn template serves both
-- colours. The first seat sits nearest the viewer and advances up the board,
-- which is now +1: a vector's y is a rank, and ranks grow away from you.
--
-- Only a two-seat board has an honest answer here. A game with four players
-- around a table has no shared notion of forward at all, and rather than
-- invent one this returns "away from the bottom" for everyone else — such
-- games should write their vectors out per seat instead of leaning on this.
function M.facing(seat, seat_list)
	return seat_list[1] == seat and 1 or -1
end

-- A piece's rank counted from its *owner's* own side, given one counted from
-- the bottom of the board: the home rank is 2 for both colours and the far side
-- is 8 for both. Stamped onto the piece by zones as it takes a square.
function M.rank(z, rank, facing)
	return facing < 0 and (z.grid[2] + 1 - rank) or rank
end

-- The named squares of an absolute pattern. No anchor, no facing, no walking:
-- the pairs are cells, so there is no path to be blocked and nothing to repeat.
-- An absolute pattern names squares the way a player says them: "e1", not a
-- column and a row counted from the top corner. The row a grid indexes by and
-- the rank a person counts are not the same number, and every place the two met
-- was a place to get it backwards — this file is now the only one that knows.
function M.squares(pat, z)
	local out = {}
	if not (z and z.grid) then return out end
	for _, v in ipairs(pat.vectors or {}) do
		local sid = M.slot_named(z, v)
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
	-- A direction is written from the near edge outwards: [0,1] is one square
	-- forward — up the board, whoever is looking — and forward is a bigger
	-- rank. Which cell that is on a screen is slot_at's problem and nobody
	-- else's.
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
