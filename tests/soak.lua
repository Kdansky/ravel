-- Random play through every shipped game, checking the two promises the snapshot
-- design makes: undo puts back exactly the state before the move, and a state
-- that has been through JSON (a save, a network message) plays on exactly as the
-- live one does.
--
--   luajit tests/soak.lua [trials]
--
-- Too slow for the suite, and a random walk rather than a fixed case: run it
-- after touching entities, flow's checkpoint or net's snapshot.

require("headless")
local json        = require("json")
local flow        = require("flow")
local net         = require("net")
local opponent    = require("opponent")
local declaration = require("declaration")

local trials = tonumber(arg[1]) or 5
local say = print
print = function() end

local games = {}
for path in io.popen("ls game/games/*.json"):lines() do
	local name = path:match("([^/]+)$")
	if name ~= "system.json" and not name:match("^tmp") then games[#games + 1] = name end
end

local failures = 0
local function fail(msg)
	failures = failures + 1
	say(msg)
end

-- A move that loads another game has left the one being tested.
local function still(name) return declaration.filename == name end

local function play(n, name)
	for _ = 1, n do
		local moves = opponent.legal()
		if #moves == 0 or not still(name) then return end
		moves[math.random(#moves)]()
	end
end

-- Undo after every move that left a checkpoint, then make the same move again.
local function undo_walk(name, trial)
	flow.init(name, trial)
	math.randomseed(trial)
	for step = 1, 80 do
		local moves = opponent.legal()
		if #moves == 0 or not still(name) then return end
		local before = net.fingerprint()
		local pick = math.random(#moves)
		moves[pick]()
		if not still(name) then return end
		if flow.can_undo() then
			local after = net.fingerprint()
			flow.undo()
			if after ~= before and net.fingerprint() ~= before then
				return fail(("undo: %s trial %d step %d does not come back to where it was"):format(name, trial, step))
			end
			local again = opponent.legal()
			if #again < pick then return end
			again[pick]()
		end
	end
end

-- The live state and its JSON copy, each played on with the same random moves.
local function round_trip(name, trial)
	flow.init(name, trial)
	math.randomseed(trial)
	play(15 * trial, name)
	if not still(name) then return end
	local wire = json.decode(json.encode(net.snapshot()))
	math.randomseed(99)
	play(40, name)
	local live = net.fingerprint()
	assert(net.apply_full(wire))
	math.randomseed(99)
	play(40, name)
	if net.fingerprint() ~= live then
		fail(("round trip: %s trial %d plays differently after going through JSON"):format(name, trial))
	end
end

for _, name in ipairs(games) do
	for trial = 1, trials do
		for _, walk in ipairs({ undo_walk, round_trip }) do
			local ok, err = pcall(walk, name, trial)
			if not ok then fail(("crash: %s trial %d: %s"):format(name, trial, tostring(err))) end
		end
	end
end
say(("soak: %d games, %d trials each, %d failures"):format(#games, trials, failures))
os.exit(failures == 0 and 0 or 1)
