-- The four games that are written by a script, held to their script.
--
-- A generated file that has been hand-edited is a trap with a fuse on it: the
-- game works, the tests pass, and the next person to run the generator silently
-- deletes the work. That is not hypothetical — make_puzzle_strike.py drifted
-- seventy-six cards behind puzzle_strike.json while reactions were being built,
-- and running it would have thrown the whole feature away without an error.
--
-- Comparing the *parsed* documents rather than the bytes, because formatting is
-- jsonfmt's business and a hand-edit that only rewrapped a line is not a
-- divergence worth failing over. What matters is that the script still knows
-- everything the shipped game knows.
--
-- The other half of the fix is in tools/guard.py: a generator refuses to write
-- its game file at all while the tree has uncommitted work in it, so the worst
-- case is a diff to review rather than work that is simply gone.

local json = require("json")

local M = {}

local GENERATED = { "lost_cities", "puzzle_strike", "splendor", "the_crew" }

local function read(path)
	local f = io.open(path)
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end

-- Deep equality with a path, so a failure names the field rather than saying
-- the documents differ. Tables here are plain JSON — no cycles, no metatables.
local function same(a, b, path)
	if type(a) ~= type(b) then return false, path .. " is a " .. type(a) .. " there and a " .. type(b) .. " here" end
	if type(a) ~= "table" then
		if a == b then return true end
		return false, ("%s is %s in the game file and %s from the generator"):format(
			path, tostring(a), tostring(b))
	end
	for k, v in pairs(a) do
		local ok, why = same(v, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in pairs(b) do
		if a[k] == nil then return false, path .. "." .. tostring(k) .. " is only in the generator's output" end
	end
	return true
end

function M.test_generators_still_write_the_game_they_ship(check)
	for _, name in ipairs(GENERATED) do
		local shipped = read("game/games/" .. name .. ".json")
		check(name .. ".json is there", shipped ~= nil)

		-- "--out" writes somewhere harmless, so the shipped file is never
		-- touched and the clean-tree guard has nothing to refuse: a generator
		-- refuses to overwrite the game it ships while there is uncommitted
		-- work, and the suite runs on a dirty tree every time.
		local tmp = os.tmpname()
		local ran = os.execute(("python3 tools/make_%s.py --out %s > /dev/null 2>&1")
			:format(name, tmp))
		local made = read(tmp)
		os.remove(tmp)

		check("tools/make_" .. name .. ".py runs", ran == true or ran == 0, tostring(ran))
		if made then
			local a, b = json.decode(shipped), json.decode(made)
			local ok, why = same(a, b, name)
			check("and writes the game that ships", ok,
				(why or "") .. " — hand-edit the generator, not the game file")
		end
	end
end

return M
