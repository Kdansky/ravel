-- A seat the engine plays: every move legal right now, as closures, and a seat
-- that picks one of them at random.
--
-- **This is not test scaffolding, and it is not dead code.** It lived in
-- `tests/run.lua` for as long as its only caller was the random terminator, and
-- moving it out was the first step of an engine-played opponent — see
-- [ideas/34](../ideas/34-an-opponent.md). A game without a `bot` section gets a
-- random opponent; one with it gets every move tried, played out and scored by
-- the number the section names.
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
local phase = require("phase")
local predicate = require("predicate")
local declaration = require("declaration")
local actions = require("actions")
local rng = require("rng")

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

-- Single player, as one gesture: you keep the seat you are watching and the
-- engine takes the rest. Sitting down is part of it, because an opponent implies
-- a side to be on — and claiming a seat is also what turns the other hand face
-- down, which is the half a player would otherwise have to know to ask for.
-- Returns the seat left to you, or nil in a game with nobody to play against.
function M.engage()
	local seats = declaration.G.seat_list or {}
	if #seats < 2 then return nil end
	local mine = zones.watching() or net.claim_seat(seats[1])
	for _, k in ipairs(seats) do
		if k ~= mine then M.take(k) end
	end
	return mine
end

-- `bot_seats` is written beside the `load_game` it goes with, and runs before
-- the load lands: the seats it means are the next game's. So it is a request,
-- and every load answers it — standing the engine down first, since seats are
-- names and the next game may have a North of its own.
local wanted = false
actions.on_bot = function() wanted = true end

local init = flow.init
flow.init = function(...)
	local go = wanted
	wanted = false
	init(...)
	M.leave()
	if go then M.engage() end
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
	if #pool == 0 or (#pool < min and not spec.spread) then return nil end
	local out = {}
	-- An aim that spends points spends picks rather than candidates, so the same
	-- card may come back — which is also the only way it fills its minimum when
	-- the board holds fewer things than the aim has points to spread.
	for k = 1, min do
		out[k] = spec.spread and pool[math.random(#pool)] or table.remove(pool, math.random(#pool))
	end
	return out
end

-- One move per way of paying. Nearly every cost has a single answer and is one
-- move as it always was; a sacrifice, or a pool the game said "select" over, is
-- a real fork, and an engine seat should be able to take either side of it. A
-- card being *chosen* out of an offer pays nothing at all, so an empty list is
-- still one move.
local function per_payment(moves, ways, make)
	if #ways == 0 then
		moves[#moves + 1] = make(nil)
		return
	end
	for _, p in ipairs(ways) do moves[#moves + 1] = make(p) end
end

-- Every move available to whoever is up, as a list of closures. Calling one
-- makes it; the list is stale the moment any of them is called.
function M.legal()
	local moves = {}
	-- A window is open, so the only move is to answer it — which is what
	-- `window_locked` already tells can_play and usable_abilities, and why
	-- asking them here would find nothing. Passing is always available, and it
	-- is what closes a window nobody wants to answer.
	-- The lock's own test, not "a record is stacked": an offer opened on top of
	-- one is answered first, and a seat offered only "pass" there passed forever.
	if flow.window_locked() then
		for _, u in ipairs(flow.usable_reactions()) do
			local id, idx = u.card, u.index
			local targets = targets_for(id, u.rule.target)
			if targets then
				per_payment(moves, flow.rule_payments(id, u.rule, targets), function(pay)
					return function() flow.react(id, idx, targets, pay) end
				end)
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
				-- A card in an offer is being *chosen*, not played: flow skips the
				-- target check for it and hands the choice the asker. Asking for
				-- targets it will never be given is how a seat stalled in front of
				-- a question it could have answered.
				local targets = flow.is_choosing(e.id) and {}
					or targets_for(e.id, cards.def(e).target)
				if targets then
					local id = e.id
					per_payment(moves, flow.play_payments(id, targets), function(pay)
						return function() flow.play_card(id, targets, pay) end
					end)
				end
			end
			for _, u in ipairs(flow.usable_abilities(e.id)) do
				local id, idx = e.id, u.index
				local targets = targets_for(id, u.rule.target)
				if targets then
					per_payment(moves, flow.rule_payments(id, u.rule, targets), function(pay)
						return function() flow.activate(id, targets, idx, pay) end
					end)
				end
			end
		end
	end
	for z in entity.each("zone") do
		for _, u in ipairs(flow.usable_zone_abilities(z.id)) do
			local id, idx = z.id, u.index
			per_payment(moves, flow.rule_payments(id, u.rule), function(pay)
				return function() flow.activate_zone(id, idx, pay) end
			end)
		end
	end
	return moves
end

-- How many deals a move is tried in, and how many moves each is played out for
-- at most. Spellstorm's round is a dozen moves; the cap is for a game whose
-- round never closes while random moves are being made in it.
M.TRIES = 4
M.REACH = 60

-- The number to climb now: an override naming a phase on the stack, the topmost
-- first, since an offer opened inside a phase is still that phase's decision.
local function valuation(bot)
	local frames = phase.snapshot().stack
	for i = #frames, 1, -1 do
		for _, o in ipairs(bot.per_phase or {}) do
			if o.phase == frames[i].def.key then return o.value end
		end
	end
	return bot.value
end

local function hidden(z, seat)
	return z.visibility == "secret" or (z.visibility == "owner" and z.seat ~= nil and z.seat ~= seat)
end

-- Deal again everything `seat` cannot see, so a move is weighed against what it
-- might be rather than what it is. Without this a tried move reads the other
-- hand, the card played face down and the next draw, and a game with hands is
-- no game at all.
--
-- Another seat's hidden zones are one pool: its hand, its deck and its face-down
-- play could hold any of its cards. A pile of nobody's, or one of my own, keeps
-- its contents and loses only its order. Each card takes the place another one
-- left, slot and all, so a zone ends holding as many as it held. A card on a
-- card stays put, because its host is where it is.
--
-- What a seat once saw and then lost sight of is forgotten, which is the honest
-- way to be wrong.
local function redeal(seat)
	local pools = {}
	for z in entity.each("zone") do
		if hidden(z, seat) then
			local k = z.seat ~= nil and z.seat ~= seat and z.seat or z.id
			pools[k] = pools[k] or {}
			for i, cid in ipairs(z.cards) do
				local c = entity.get(cid)
				if c and not c.parent_id then table.insert(pools[k], { z = z, i = i, id = cid, slot = c.slot }) end
			end
		end
	end
	for _, places in pairs(pools) do
		local ids = {}
		for n, p in ipairs(places) do ids[n] = p.id end
		for n = #ids, 2, -1 do
			local m = math.random(n)
			ids[n], ids[m] = ids[m], ids[n]
		end
		for n, p in ipairs(places) do
			local c = entity.get(ids[n])
			p.z.cards[p.i] = c.id
			c.zone_id, c.slot = p.z.id, p.slot
		end
	end
end

local function over()
	for _, cond in ipairs(declaration.G.end_conditions) do
		if cond.ravel_fired then return true end
	end
	return false
end

local function round()
	local sys = zones.system_card()
	return sys and sys.stats.round
end

-- Random moves for everybody until the round turns or the game ends: far enough
-- that a card played face down has met the one it was played against.
local function play_out()
	local start = round()
	for _ = 1, M.REACH do
		if over() or round() ~= start then return end
		local moves = M.legal()
		if #moves == 0 then return end
		moves[math.random(#moves)]()
	end
end

local WIN = 1e9

local function score(seat, expr)
	local won = flow.victor()
	if won then return won == seat and WIN or -WIN end
	local v = 0
	zones.as_seat(seat, function() v = predicate.value(expr, {}) end)
	return v
end

-- Nothing a tried move does may reach the screen: the hooks are what record a
-- run to play back, and undo's hook clears the one being recorded.
local function unseen(fn)
	local change, stat, effect, reset = zones.on_change, actions.on_stat_change, actions.on_effect, flow.on_reset
	zones.on_change, actions.on_stat_change, actions.on_effect, flow.on_reset = nil, nil, nil, nil
	local ok, err = pcall(net.unheard, fn)
	zones.on_change, actions.on_stat_change, actions.on_effect, flow.on_reset = change, stat, effect, reset
	if not ok then error(err, 0) end
end

-- Which of `moves` the engine makes for `seat`. Each is tried M.TRIES times in a
-- fresh deal, played out, and scored by the game's `bot` section; the best
-- total wins and a tie is broken at random. A game with no section, and a choice
-- of one, is a coin.
function M.choose(seat, moves)
	local bot = declaration.G.bot
	if not bot or #moves < 2 then return math.random(#moves) end
	local expr, G = valuation(bot), declaration.G
	local best, picks = -math.huge, {}
	unseen(function()
		for i, move in ipairs(moves) do
			local sum = 0
			for _ = 1, M.TRIES do
				flow.rehearse(function()
					redeal(seat)
					rng.seed(math.random(2 ^ 30))
					move()
					play_out()
					sum = sum + score(seat, expr)
				end)
				assert(declaration.G == G, "a move tried by the engine seat loaded another game")
			end
			if sum > best then
				best, picks = sum, { i }
			elseif sum == best then
				picks[#picks + 1] = i
			end
		end
	end)
	return picks[math.random(#picks)]
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
		moves[M.choose(zones.active_seat(), moves)]()
		moved = true
	end)
	return moved
end

return M
