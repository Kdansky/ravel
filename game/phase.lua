local predicate = require("predicate")

local M = {}

M.on_leave = nil   -- hook(def) fired when a phase transitions away (flow discards its hand)

-- Stack frames are { def = phase_def, fresh = bool }. `fresh` is true until the
-- phase's entry work (dealing cards) has run, so resuming after a pop doesn't re-deal.
local stack   = {}
local G       = nil
local wrapped = false   -- set when the phase list loops back to the start (= a full round)

function M.init(game_G)
	G       = game_G
	stack   = {}
	wrapped = false
end

function M.push(key)
	local pd = G.phase_by_key[key]
	assert(pd, "Unknown phase: " .. tostring(key))
	stack[#stack + 1] = { def = pd, fresh = true }
end

function M.pop()
	stack[#stack] = nil
end

function M.current()
	local top = stack[#stack]
	return top and top.def
end

-- True exactly once per entry into the current phase.
function M.take_fresh()
	local top = stack[#stack]
	if top and top.fresh then top.fresh = false; return true end
	return false
end

-- True exactly once after the phase list wraps around.
function M.take_wrapped()
	local w = wrapped
	wrapped = false
	return w
end

-- Advance to the next phase. A phase with a "next" routing table picks the
-- first entry whose condition holds (an entry without a condition always
-- matches); round boundaries are declared there via "ends_round", never
-- inferred from list order. Without routing: next in list, wrapping to the
-- first non-automatic phase (the wrap marks a round).
function M.next()
	local cur = M.current()
	if not cur then return end

	if cur.next then
		for _, r in ipairs(cur.next) do
			local unconditional = r.stat == nil and r.zone_empty == nil
			if unconditional or predicate.met(r) then
				local pd = G.phase_by_key[r["then"]]
				if pd then
					if M.on_leave then M.on_leave(cur) end
					if r.ends_round then wrapped = true end
					stack[#stack] = { def = pd, fresh = true }
				end
				return
			end
		end
		return   -- no route matched: stay put (the validator flags automatic phases that can stall here)
	end

	local nxt
	for i, key in ipairs(G.phase_list) do
		if key == cur.key then nxt = G.phase_list[i + 1]; break end
	end
	if not nxt then
		wrapped = true
		for _, key in ipairs(G.phase_list) do
			if G.phase_by_key[key].type ~= "automatic" then nxt = key; break end
		end
	end
	if nxt then
		if M.on_leave then M.on_leave(cur) end
		stack[#stack] = { def = G.phase_by_key[nxt], fresh = true }
	end
end

function M.is_overlay()
	local cur = M.current()
	return cur ~= nil and cur.type == "overlay"
end

function M.snapshot()
	local s = { wrapped = wrapped, stack = {} }
	for i, f in ipairs(stack) do s.stack[i] = { def = f.def, fresh = f.fresh } end
	return s
end

function M.restore(s)
	wrapped = s.wrapped
	stack   = {}
	for i, f in ipairs(s.stack) do stack[i] = { def = f.def, fresh = f.fresh } end
end

return M
