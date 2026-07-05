-- Validate a game file without running it. From the repo root:
--   luajit check.lua mygame.json

require("headless")

local declaration = require("declaration")
local validate    = require("validate")

local file = arg[1] or "menu.json"
local ok, G = pcall(declaration.parse, file)
if not ok then
	print(tostring(G))
	os.exit(1)
end

local problems = validate.check(G)
for _, p in ipairs(problems) do print("  " .. p) end
if #problems == 0 then
	print(file .. ": no problems found")
else
	print(file .. ": " .. #problems .. " problem" .. (#problems == 1 and "" or "s") .. " found")
end
os.exit(#problems == 0 and 0 or 1)
