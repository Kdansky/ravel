-- Chronological record of what happened, shown beside the system column and
-- echoed by the CLI. flow's checkpoints mark positions here, so undo removes
-- exactly the lines the undone action wrote.

local M = {}

local entries = {}

-- How much of it is shown. Not game state: it is never saved, sent or undone,
-- because how long a panel is is the player's business and not the table's.
local VIEWS = { short = 3, full = 24 }
local ORDER = { "short", "full" }
M.view = "short"

-- A named view, or "next" for the one after this — which is what clicking the
-- log card means, and what L has always meant.
function M.set_view(v)
	if VIEWS[v] then M.view = v; return end
	for i, name in ipairs(ORDER) do
		if name == M.view then M.view = ORDER[i % #ORDER + 1]; return end
	end
end

function M.lines()
	return M.tail(VIEWS[M.view] or VIEWS.short)
end

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
