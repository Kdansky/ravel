-- The engine's own randomness.
--
-- math.random is the host's, and the host is not one thing: LuaJIT (what LÖVE
-- ships) uses a Tausworthe generator, PUC Lua 5.4 uses xoshiro256**, and the
-- same seed hands them a different first card. That made a seeded replay a
-- property of whoever compiled the interpreter rather than of the game — the
-- reason tests/run.lua skipped its golden traces outside LuaJIT, and the
-- reason two networked clients could not have agreed on a shuffle.
--
-- Lehmer / MINSTD: x = 48271 * x mod (2^31 - 1). Thirty years old, famous,
-- and exactly what C++ standardised as std::minstd_rand — so there is a
-- published test vector to check against rather than a vague sense that the
-- numbers look shuffled (tests/run.lua asserts it). Integer-only and small:
-- the widest intermediate is 48271 * (2^31 - 2) ≈ 2^46.6, which is exact both
-- in a double and in a 64-bit integer, so Lua 5.1, LuaJIT and Lua 5.4 produce
-- an identical sequence with no bit operations and no float dependence.
--
-- It is not a good generator by modern standards, and it does not need to be.
-- It shuffles a deck.

local M = {}

local A, MOD = 48271, 2147483647   -- 2^31 - 1, prime
local state  = 1                   -- always in [1, MOD-1]; Lehmer never reaches 0

function M.seed(n)
	n = math.floor(math.abs(tonumber(n) or 0))
	state = n % MOD
	if state == 0 then state = 1 end
	return state
end

-- The raw generator: 1 .. MOD-1.
function M.next()
	state = (A * state) % MOD
	return state
end

-- 1..n, the shape every caller here wants. The modulo bias is about one part
-- in 10^8 for a deck-sized n, which is several orders of magnitude below
-- anything a card game can notice.
function M.int(n)
	n = math.floor(tonumber(n) or 1)
	if n < 2 then return 1 end
	return M.next() % n + 1
end

function M.range(lo, hi)
	return lo + M.int(hi - lo + 1) - 1
end

-- Fisher-Yates, in place.
function M.shuffle(list)
	for i = #list, 2, -1 do
		local j = M.int(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- The generator's whole state is one integer, which is what lets it join
-- flow's checkpoint and net's state transfer without either of them knowing
-- anything about generators. Undo across a shuffle replays that same shuffle;
-- a state that arrives over a wire brings its position in the sequence along.
function M.state()
	return state
end

function M.set_state(s)
	s = math.floor(tonumber(s) or 1) % MOD
	state = s == 0 and 1 or s
end

return M
