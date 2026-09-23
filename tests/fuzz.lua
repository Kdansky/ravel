-- Mutation fuzzer: every game file is untrusted content (ARCHITECTURE invariant 5),
-- so no value of the wrong type may crash the engine.
--
--   luajit tests/fuzz.lua [seed] [iterations]
--
-- Each iteration takes a shipped game, replaces one to three values anywhere in it
-- with something of the wrong type, loads it and plays random legal moves. A
-- crash is reported once per source line, with the mutation that caused it and
-- the first frames inside the engine. Silent on success; exits 1 on any crash.
-- Seeds are independent, so several may run side by side.

require("headless")
local json     = require("json")
local flow     = require("flow")
local opponent = require("opponent")

local seed  = tonumber(arg[1]) or 1
local iters = tonumber(arg[2]) or 200
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
for it = 1, iters do
	local name = games[math.random(#games)]
	local doc = json.decode(texts[name])
	local all = {}
	leaves(doc, all, "")
	local said = {}
	for _ = 1, math.random(1, 3) do
		local l = all[math.random(#all)]
		local v = WRONG[math.random(#WRONG)]()
		l.t[l.k] = v
		said[#said + 1] = l.path .. "=" .. json.encode(v)
	end
	local f = io.open("game/games/" .. tmp, "w")
	f:write(json.encode(doc))
	f:close()
	local ok, err = xpcall(function()
		flow.init(tmp, it)
		for _ = 1, 60 do
			local moves = opponent.legal()
			if #moves == 0 then break end
			moves[math.random(#moves)]()
		end
	end, function(e) return debug.traceback(e, 2) end)
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
