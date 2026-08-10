-- The test harness: one tally, one way to say what a test found, and the
-- loader for tests/integration.
--
-- An integration file is an ordinary Lua module that returns a table, and every
-- exported function whose name begins with "test" is a test. It is handed
-- `check` and nothing else, which is the whole contract:
--
--   local M = {}
--   function M.test_a_pawn_may_step_forward(check)
--       flow.init("chess.json", 1)
--       check("it reaches e3 and e4", ...)
--   end
--   return M
--
-- A test starts from its own `flow.init` and may assume nothing about what ran
-- before it — that independence is what tests/run.lua's own body, a single
-- script whose sections inherit each other's state, cannot offer.

local M = { passed = 0, failed = 0 }

-- `detail` is printed only when the check fails, so a call site can carry the
-- number it compared or the error it got without adding noise to a green run.
function M.check(name, cond, detail)
	if cond then
		M.passed = M.passed + 1
	else
		M.failed = M.failed + 1
		print("FAIL: " .. name .. (detail ~= nil and ("\n      " .. tostring(detail)) or ""))
	end
end

-- Every test in `dir`, sorted by name so a run is the same run twice. Sorting
-- by name rather than by file is deliberate: which file a test lives in is a
-- filing decision, and should not quietly become an ordering one.
function M.discover(dir)
	local tests = {}
	local ls = io.popen("ls " .. dir .. "/*.lua 2>/dev/null")
	if not ls then return tests end
	for path in ls:lines() do
		local ok, exported = pcall(dofile, path)
		if not ok then
			M.failed = M.failed + 1
			print("FAIL: loading " .. path .. "\n      " .. tostring(exported))
		else
			for name, fn in pairs(type(exported) == "table" and exported or {}) do
				if type(fn) == "function" and name:match("^test") then
					tests[#tests + 1] = { name = name, fn = fn, file = path }
				end
			end
		end
	end
	ls:close()
	table.sort(tests, function(a, b) return a.name < b.name end)
	return tests
end

-- Run them one by one. A test that raises is one failure with its traceback,
-- not the end of the suite: the rest still have something to say.
function M.run(dir, filter)
	local tests, ran = M.discover(dir), 0
	for _, t in ipairs(tests) do
		if not filter or t.name:find(filter) then
			ran = ran + 1
			local ok, err = xpcall(function() return t.fn(M.check) end, debug.traceback)
			if not ok then
				M.failed = M.failed + 1
				print("FAIL: " .. t.name .. " raised\n" .. tostring(err))
			end
		end
	end
	print(("integration: %d test%s from %s"):format(ran, ran == 1 and "" or "s", dir))
	return ran
end

function M.finish()
	print(string.format("%d passed, %d failed", M.passed, M.failed))
	os.exit(M.failed == 0 and 0 or 1)
end

return M
