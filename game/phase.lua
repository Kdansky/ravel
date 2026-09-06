local declaration = require("declaration")
local entity      = require("entity")
local predicate   = require("predicate")
local zones       = require("zones")

local M = {}

M.on_leave = nil   -- hook(def) fired when a phase transitions away (flow discards its hand)

-- Stack frames are { def, fresh, arrived, seat, turn, turn_seat }. `fresh` is true until the
-- phase's entry work (dealing cards) has run, so resuming after a pop doesn't
-- re-deal. `arrived` says the entry came from a *different* phase, which is what
-- separates beginning a turn from carrying on with one. `seat` is the route's
-- override of the phase's own, since a phase that leads back to itself is asked
-- for the opposite answer by different games: Splendor's turn continues with the
-- same player, The Crew's draft passes to the next.
--
-- `turn` is the group a phase is running inside, and it is carried *on* the
-- frame rather than stacked underneath it. So `current` stays the phase actually
-- running — its label, its zones and its `ends_when` are read exactly as they
-- were before groups existed — and an overlay still pushes over the top without
-- the group losing its place. `turn_seat` is the seat the group wants up, taken
-- once on entry, because handing over is flow's business and not this file's.
local stack   = {}
local G       = nil
local wrapped = false   -- set when the phase list loops back to the start (= a full round)

function M.init(game_G)
	G       = game_G
	stack   = {}
	wrapped = false
end

-- What a seat card says about itself. A seat is a card, so the number a group
-- orders by is an ordinary stat on it, and a seat that never took part in that
-- arithmetic counts as nought rather than as missing.
local function seat_stat(seat, stat)
	for e in entity.each("card") do
		if e.def_key == seat and e.zone_id then return e.stats[stat] or 0 end
	end
	return 0
end

-- The seats a group visits, in the order it visits them.
--
-- Without an `order` the table goes round from whoever is next, which is what a
-- pair of phases both saying `seat: "next"` used to mean. With one, the seats
-- are sorted by a stat their cards carry — `highest:initiative` leads with
-- whoever holds it — and **the sort is settled once, on entry**. Recomputed per
-- seat, a player who scores during their own turn would change who comes after
-- them, and could take two turns or none; every printed game fixes the order at
-- the top of the round, and this is that.
--
-- Ties keep seat order, so a table where nobody leads still plays round in the
-- order the game listed its players.
local function seat_order(order)
	local G     = declaration.G
	local seats = G.seat_list or {}
	if #seats < 2 then return { seats[1] } end
	local out = {}
	for i, s in ipairs(seats) do out[i] = s end
	local dir, stat = tostring(order or ""):match("^(%l+):([%w_]+)$")
	if dir then
		local n, idx = {}, G.seat_index or {}
		for _, s in ipairs(seats) do n[s] = seat_stat(s, stat) end
		table.sort(out, function(a, b)
			if n[a] ~= n[b] then
				if dir == "highest" then return n[a] > n[b] end
				return n[a] < n[b]
			end
			return (idx[a] or 0) < (idx[b] or 0)
		end)
		return out
	end
	local sys = zones.system_card()
	local at  = sys and (sys.stats.turn or 0) or 0
	for i = 1, #seats do out[i] = seats[(at + i - 1) % #seats + 1] end
	return out
end

-- Beginning a phase, which for a group means beginning its first member. A group
-- is never on the stack itself: what runs is one of its phases, wearing the
-- group as a `turn`.
local function enter(def, arrived, seat)
	if def.type ~= "turn" then
		return { def = def, fresh = true, arrived = arrived, seat = seat }
	end
	-- A group naming a phase that does not exist is a content error the validator
	-- reports; here it becomes an ordinary phase with nothing to do, so the game
	-- routes past it rather than stopping on a frame with no phase in it.
	local first = G.phase_by_key[(def.phases or {})[1]]
	if not first then return { def = def, fresh = true, arrived = arrived, seat = seat } end
	local t = { def = def, at = 1 }
	if def.seat == "each" then
		t.seats, t.seat_at = seat_order(def.order), 1
	end
	return { def = first, fresh = true, arrived = true, turn = t,
		turn_seat = t.seats and t.seats[1] }
end

function M.push(key)
	local pd = G.phase_by_key[key]
	assert(pd, "Unknown phase: " .. tostring(key))
	-- A push is always an arrival: whatever is underneath is a different phase,
	-- or the same one being entered a second time over the top of itself.
	stack[#stack + 1] = enter(pd, true, nil)
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

-- Whether this entry arrived from a *different* phase, rather than the phase
-- leading back to itself. Not taken: take_fresh already gates the one block that
-- asks, and clearing it twice would only give it a second way to be wrong.
function M.arrived()
	local top = stack[#stack]
	return top ~= nil and top.arrived == true
end

-- What the route that led here said about the seat, or nil if it said nothing
-- and the phase's own answer stands.
function M.route_seat()
	local top = stack[#stack]
	return top and top.seat
end

-- The seat a group wants up, taken once so that entering the same phase twice
-- does not hand over twice. A group names its seat outright where a route says
-- only "next" or "same", because the order it goes round in is its own.
function M.take_turn_seat()
	local top = stack[#stack]
	if not (top and top.turn_seat) then return nil end
	local seat = top.turn_seat
	top.turn_seat = nil
	return seat
end

-- The group the current phase is running inside, if any. Read by the validator's
-- twin in flow and by anything that wants to name the group rather than the
-- phase — the HUD says the phase, which is the smaller and more useful answer.
function M.group()
	local top = stack[#stack]
	return top and top.turn and top.turn.def
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
	local top = stack[#stack]
	local cur = top and top.def
	if not cur then return end

	-- Inside a group, the group says where next: the phase after this one, or the
	-- first one again for the seat after this one. Only when both are exhausted
	-- does the group's own routing get asked, which is why a round boundary sits
	-- on the group and not on the last copy of a phase.
	local t = top.turn
	if t then
		local list = t.def.phases or {}
		local seat
		if t.at < #list then
			t.at = t.at + 1
		elseif t.seats and t.seat_at < #t.seats then
			t.at, t.seat_at = 1, t.seat_at + 1
			seat = t.seats[t.seat_at]
		else
			t = nil
		end
		if t and not G.phase_by_key[list[t.at]] then t = nil end
		if t then
			if M.on_leave then M.on_leave(cur) end
			-- Every step inside a group is an arrival, including a group of one
			-- coming round to the next seat: what makes it a fresh turn is the
			-- seat changing, not the key changing.
			stack[#stack] = { def = G.phase_by_key[list[t.at]], fresh = true,
				arrived = true, turn = t, turn_seat = seat }
			return
		end
		cur = top.turn.def
	end

	if cur.next then
		for _, r in ipairs(cur.next) do
			local unconditional = r.zone_empty == nil and r.when == nil
			if unconditional or predicate.met(r) then
				local pd = G.phase_by_key[r["then"]]
				if pd then
					if M.on_leave then M.on_leave(top.def) end
					if r.ends_round then wrapped = true end
					stack[#stack] = enter(pd, pd.key ~= cur.key, r.seat)
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
		if M.on_leave then M.on_leave(top.def) end
		stack[#stack] = enter(G.phase_by_key[nxt], nxt ~= cur.key, nil)
	end
end

-- How deep the phase stack is. One is the game's own phase and nothing over it;
-- more means something was interjected — an offer, a buy handed to the player who
-- just reacted — and whoever was up when it was pushed is still up.
function M.depth()
	return #stack
end

function M.is_overlay()
	local cur = M.current()
	return cur ~= nil and cur.type == "overlay"
end

-- A group's place in itself is state, so it is copied rather than shared: two
-- frames of one snapshot that pointed at the same counter would advance each
-- other, and an undo would land halfway through somebody else's turn. The `def`
-- inside it is a declaration and stays a reference, like every other def here.
local function copy_turn(t)
	if not t then return nil end
	local c = { def = t.def, at = t.at, seat_at = t.seat_at }
	if t.seats then
		c.seats = {}
		for i, k in ipairs(t.seats) do c.seats[i] = k end
	end
	return c
end

local function copy_frame(f)
	return { def = f.def, fresh = f.fresh, arrived = f.arrived, seat = f.seat,
		turn = copy_turn(f.turn), turn_seat = f.turn_seat }
end

function M.snapshot()
	local s = { wrapped = wrapped, stack = {} }
	for i, f in ipairs(stack) do s.stack[i] = copy_frame(f) end
	return s
end

function M.restore(s)
	wrapped = s.wrapped
	stack   = {}
	for i, f in ipairs(s.stack) do stack[i] = copy_frame(f) end
end

return M
