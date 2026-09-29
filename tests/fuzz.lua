-- Mutation fuzzer: every game file is untrusted content (ARCHITECTURE invariant 5),
-- so no value of the wrong type may crash the engine.
--
--   luajit tests/fuzz.lua [seed] [iterations] [net]
--
-- Each iteration takes a shipped game, replaces one to three values anywhere in it
-- with something of the wrong type, loads it and plays random legal moves. With
-- `net` it is a state from the other machine that is mangled instead: a game played
-- a while, sent through JSON as the wire sends it, and applied as a peer's message.
-- The message may be refused; it may not crash anything, then or in the moves after.
-- A
-- crash is reported once per source line, with the mutation that caused it and
-- the first frames inside the engine, and an iteration taking over ten seconds is
-- reported as slow. Silent on success; exits 1 on any crash.
-- Seeds are independent, so several may run side by side.

require("headless")
local json     = require("json")
local flow     = require("flow")
local opponent = require("opponent")
local net      = require("net")

local seed  = tonumber(arg[1]) or 1
local iters = tonumber(arg[2]) or 200
local mode  = arg[3]
local tmp   = "tmp_fuzz_" .. seed .. ".json"

local say = print
-- The engine prints every validator warning; the fuzzer wants only crashes.
print = function() end

local games, texts = {}, {}
for path in io.popen("ls game/games/*.json"):lines() do
	local name = path:match("([^/]+)$")
	if name ~= "menu.json" and name ~= "system.json" and not name:match("^tmp") then
		games[#games + 1] = name
		local f = io.open(path)
		texts[name] = f:read("*a")
		f:close()
	end
end

local WRONG = {
	function() return "x" end, function() return "" end, function() return "@" end,
	function() return {} end, function() return { "a" } end, function() return { a = 1 } end,
	function() return -3 end, function() return 0 end, function() return 0.5 end, function() return 1e9 end,
	function() return true end,
}

local function leaves(t, out, path)
	for k, v in pairs(t) do
		if type(v) == "table" then leaves(v, out, path .. "." .. tostring(k)) end
		out[#out + 1] = { t = t, k = k, path = path .. "." .. tostring(k) }
	end
end

local function frames(trace)
	local out = {}
	for line in trace:gmatch("\n\t([^\n]+)") do
		local at = line:match("^(game/[^:]+:%d+)")
		if at and #out < 4 then out[#out + 1] = at end
	end
	return table.concat(out, " < ")
end

math.randomseed(seed)
local seen, crashes = {}, 0
local function mangle(doc, wrong)
	local all, said = {}, {}
	leaves(doc, all, "")
	for _ = 1, math.random(1, 3) do
		local l = all[math.random(#all)]
		local v = wrong[math.random(#wrong)]()
		l.t[l.k] = v
		said[#said + 1] = l.path .. "=" .. json.encode(v)
	end
	return said
end

local function play(n)
	for _ = 1, n do
		local moves = opponent.legal()
		if #moves == 0 then break end
		moves[math.random(#moves)]()
	end
end

for it = 1, iters do
	local name = games[math.random(#games)]
	local said = {}
	local started = os.clock()
	local ok, err = xpcall(function()
		if mode == "net" then
			flow.init(name, it)
			play(math.random(0, 40))
			local snap = json.decode(json.encode(net.snapshot()))
			-- A peer can also send the right type naming the wrong thing: an id that is
			-- an index, only of some other entity.
			local wrong, n = { unpack(WRONG) }, #snap.ents
			for _ = 1, 4 do wrong[#wrong + 1] = function() return math.random(n) end end
			-- Or leave a field out altogether.
			wrong[#wrong + 1] = function() return nil end
			said = mangle(snap, wrong)
			net.apply_full(snap)
		else
			local doc = json.decode(texts[name])
			said = mangle(doc, WRONG)
			local f = io.open("game/games/" .. tmp, "w")
			f:write(json.encode(doc))
			f:close()
			flow.init(tmp, it)
		end
		play(60)
	end, function(e) return debug.traceback(e, 2) end)
	-- A hang is a crash that takes longer to notice: loops on content are meant to be budgeted.
	if os.clock() - started > 10 then
		say(("slow: %.0f s"):format(os.clock() - started))
		say("    " .. name .. " " .. table.concat(said, "  "))
	end
	if not ok then
		local first = tostring(err):match("^[^\n]*")
		local at = first:match("^([^:]+:%d+)") or first
		if not seen[at] then
			seen[at] = true
			crashes = crashes + 1
			say(first)
			say("    in " .. frames(tostring(err)))
			say("    " .. name .. " " .. table.concat(said, "  "))
		end
	end
end
os.remove("game/games/" .. tmp)
say(("fuzz seed %d: %d iterations, %d distinct crash sites"):format(seed, iters, crashes))
os.exit(crashes == 0 and 0 or 1)
