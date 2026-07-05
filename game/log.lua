-- Chronological record of what happened, shown in the GUI corner and echoed
-- by the CLI. flow's checkpoints mark positions here, so undo removes exactly
-- the lines the undone action wrote.

local M = {}

local entries = {}

function M.add(text)
	entries[#entries + 1] = text
end

function M.count()
	return #entries
end

function M.truncate(n)
	for i = #entries, n + 1, -1 do entries[i] = nil end
end

-- Up to n most recent entries, oldest first.
function M.tail(n)
	local out = {}
	for i = math.max(1, #entries - n + 1), #entries do out[#out + 1] = entries[i] end
	return out
end

function M.clear()
	entries = {}
end

return M
