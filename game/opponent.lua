-- A seat the engine plays: every move legal right now, as closures, and a seat
-- that picks one of them at random.
--
-- **This is not test scaffolding, and it is not dead code.** It lived in
-- `tests/run.lua` for as long as its only caller was the random terminator, and
-- moving it out was the first step of an engine-played opponent — see
-- [ideas/34](../ideas/34-an-opponent.md). A random opponent is `M.legal()` and
-- one `math.random`; what the rest of that track waits on is a game file being
-- able to say what winning looks like as a *number*, which is a format word
-- nobody has agreed yet.
--
-- Optional and additive: nothing in the engine requires it. It reads `flow`,
-- `zones`, `targeting` and `cards` — the same door the interfaces use, so an
-- opponent is another interface rather than a new layer — and `net`, which is
-- the one thing an interface is allowed to require and an engine module is not.

local entity    = require("entity")
local zones     = require("zones")
local cards     = require("cards")
local targeting = require("targeting")
local flow      = require("flow")
local net       = require("net")

local M = {}

-- The seats this machine plays, by key. Empty is every game as it has always
-- been played: by whoever is at the screen.
M.seats = {}

function M.take(seat)
	if seat then M.seats[seat] = true end
end

-- No name stands every engine seat up at once, which is what leaving a game and
-- loading another one wants.
function M.leave(seat)
	if seat then M.seats[seat] = nil else M.seats = {} end
end

-- Targets for a spec, chosen at random and committed now rather than inside the
-- closure: a move that cannot fill its spec is not a move, and the only moment
-- to find that out is while the list is being written. `candidates` is asked
-- rather than `targeting.start`, because starting would wipe the aim a player
-- at this screen is halfway through taking.
--
-- Only the minimum is picked. An optional target is therefore never taken,
-- which is a real gap and a small one: nothing in the corpus turns on it.
local function targets_for(card_id, spec)
	local min = targeting.bounds(spec)
	if min == 0 then return {} end
	local pool = targeting.candidates(card_id, spec)
	if #pool < min then return nil end
	local out = {}
	for k = 1, min do out[k] = table.remove(pool, math.random(#pool)) end
	return out
end

-- Every move available to whoever is up, as a list of closures. Calling one
-- makes it; the list is stale the moment any of them is called.
function M.legal()
	local moves = {}
	-- A window is open, so the only move is to answer it — which is what
	-- `window_locked` already tells can_play and usable_abilities, and why
	-- asking them here would find nothing. Passing is always available, and it
	-- is what closes a window nobody wants to answer.
	if flow.pending_event() then
		for _, u in ipairs(flow.usable_reactions()) do
			local id, idx = u.card, u.index
			local targets = targets_for(id, u.rule.target)
			if targets then
				moves[#moves + 1] = function() flow.react(id, idx, targets) end
			end
		end
		moves[#moves + 1] = function() flow.pass_react() end
		return moves
	end
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		-- The system column is outside the game — Save, Menu, the event log —
		-- and a phase naming no zone makes its cards look playable to the one
		-- gate that would otherwise refuse them.
		if z and not flow.is_system_card(e.id) then
			if flow.can_play(e.id) then
				local targets = targets_for(e.id, cards.def(e).target)
				if targets then
					local id = e.id
					moves[#moves + 1] = function() flow.play_card(id, targets) end
				end
			end
			for _, u in ipairs(flow.usable_abilities(e.id)) do
				local id, idx = e.id, u.index
				local targets = targets_for(id, u.rule.target)
				if targets then
					moves[#moves + 1] = function() flow.activate(id, targets, idx) end
				end
			end
		end
	end
	for z in entity.each("zone") do
		for _, u in ipairs(flow.usable_zone_abilities(z.id)) do
			local id, idx = z.id, u.index
			moves[#moves + 1] = function() flow.activate_zone(id, idx) end
		end
	end
	return moves
end

-- Whether the engine is owed a move. Asked before act() by a driver that has to
-- pay for something first — the GUI snapshots the board to record a run, which
-- is not a thing to do every frame for a seat that is not the engine's.
function M.due()
	-- The empty case first: asking who is up walks the cards, and the GUI asks
	-- this every frame of every game nobody has handed a seat over in.
	if not next(M.seats) then return false end
	local seat = zones.active_seat()
	return seat ~= nil and M.seats[seat] == true
end

-- One move for a seat the engine plays, when it is that seat's turn. False when
-- there is nothing here to do — a human is up, no engine seat, or the game is
-- over — so a caller may loop on it and stop.
--
-- `math.random` and not `rng`: the game's own generator must not have its
-- sequence depend on how many moves an opponent weighed, or the deal would
-- change with the quality of the player.
function M.act()
	if not M.due() then return false end
	local moved = false
	-- The turn gate is about the human at this screen. Claiming a seat is how
	-- you hide the opponent's hand, and without this it would also be what
	-- forbids the opponent from moving.
	net.unattended(function()
		local moves = M.legal()
		if #moves == 0 then return end
		moves[math.random(#moves)]()
		moved = true
	end)
	return moved
end

return M
