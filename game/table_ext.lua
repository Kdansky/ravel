-- What Lua's own `table` leaves out. Nothing game-shaped lives here: every
-- function takes a table and answers about tables, which is what keeps this
-- from becoming the "util" module that ends up holding everything.

local M = {}

-- A table copied all the way down, so a snapshot cannot be written through.
-- Non-tables are returned as they are, which makes the recursion its own base
-- case; metatables are not carried, because nothing that goes through here has
-- one and a copy that quietly kept behaviour would be worse than one that did
-- not.
function M.deep_copy(x)
	if type(x) ~= "table" then return x end
	local c = {}
	for k, v in pairs(x) do c[k] = M.deep_copy(v) end
	return c
end

return M
