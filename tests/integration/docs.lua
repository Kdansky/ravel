-- The examples in AUTHORING.md, run through the validator.
--
-- Both walkthroughs are written to be copied, and both had quietly stopped
-- working: the minimal game pushed a phase it never declared and put its hand
-- under the undo button, and the story game still spoke a vocabulary the engine
-- had dropped. Nothing noticed, because a document cannot fail.
--
-- Only whole games are checked. The rest of the file is fragments and ellipses
-- on purpose — a reference entry is clearer for showing one field than for
-- being runnable — so anything that does not parse as a game file is skipped
-- rather than mangled into one.

local declaration = require("declaration")
local validate = require("validate")
local json = require("json")

local M = {}

local function examples()
	local f = assert(io.open("AUTHORING.md"), "AUTHORING.md should be at the repo root")
	local text = f:read("*a")
	f:close()
	local out = {}
	for body in text:gmatch("```json\n(.-)```") do
		local ok, d = pcall(json.decode, body)
		if ok and type(d) == "table" and d.cards and d.zones and d.phases then
			out[#out + 1] = { title = d.title or "untitled", text = body }
		end
	end
	return out
end

function M.test_docs_every_whole_game_example_validates(check)
	local found = examples()
	check("AUTHORING carries complete game examples", #found >= 2, tostring(#found) .. " found")
	for _, ex in ipairs(found) do
		local path = "game/games/tmp_docs_test.json"
		local f = assert(io.open(path, "w"))
		f:write(ex.text)
		f:close()
		local ok, G = pcall(declaration.parse, "tmp_docs_test.json")
		os.remove(path)
		if not ok then
			check("'" .. ex.title .. "' parses", false, tostring(G))
		else
			local problems = validate.check(G)
			check("'" .. ex.title .. "' validates clean", #problems == 0,
				table.concat(problems, "; "))
		end
	end
end

return M
