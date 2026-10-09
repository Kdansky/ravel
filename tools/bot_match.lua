-- The engine seat against random play, headless, to measure a game's `bot`
-- section. Run from the repo root:
--   luajit tools/bot_match.lua puzzle_strike.json 10      (ten games)
--   luajit tools/bot_match.lua codex.json 4 2              (budget of 2 s a decision)
-- The engine takes the first seat in odd games and the second in even ones.
-- Every seat but the engine's moves at random; a cooperative game is won or
-- lost by everybody, so there the engine plays every seat.
require("headless")
local flow = require("flow")
local zones = require("zones")
local net = require("net")
local opponent = require("opponent")

local file, games = arg[1], tonumber(arg[2]) or 6
opponent.BUDGET = tonumber(arg[3]) or opponent.BUDGET
local STEPS = tonumber(os.getenv("STEPS")) or 3000
local clock = os.clock

local wins, losses, open, slowest, spent, decisions = 0, 0, 0, 0, 0, 0
for g = 1, games do
	math.randomseed(g)
	flow.init(file, g)
	local seats = net.seats()
	local coop = os.getenv("COOP") ~= nil
	local mine = seats[(g - 1) % #seats + 1]
	opponent.leave()
	if coop then
		for _, k in ipairs(seats) do opponent.take(k) end
	else
		opponent.take(mine)
	end
	local steps, t0 = 0, clock()
	while steps < STEPS do
		if flow.victor() or flow.outcome() then break end
		steps = steps + 1
		if opponent.due() then
			local t = clock()
			if not opponent.act() then break end
			local d = clock() - t
			spent, decisions, slowest = spent + d, decisions + 1, math.max(slowest, d)
		else
			local moves
			net.unattended(function() moves = opponent.legal() end)
			if #moves == 0 then break end
			net.unattended(moves[math.random(#moves)])
		end
	end
	local won, word = flow.victor(), flow.outcome()
	local res
	if won then
		res = (won == mine or coop) and "won" or "lost"
	elseif word == "victory" or word == "defeat" then
		res = word == "victory" and "won" or "lost"
	else
		res = "open"
	end
	if res == "won" then wins = wins + 1 elseif res == "lost" then losses = losses + 1 else open = open + 1 end
	print(("game %d: engine as %s %s after %d steps, %.0f s"):format(g, mine, res, steps, clock() - t0))
	io.stdout:flush()
end
print(("%s: %d won, %d lost, %d unfinished; %d decisions, %.2f s mean, %.2f s slowest"):format(
	file, wins, losses, open, decisions, decisions > 0 and spent / decisions or 0, slowest))
