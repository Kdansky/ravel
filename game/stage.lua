-- One click, played back a beat at a time — and each beat is a whole state.
--
-- The rules resolve a click in a single frame: `flow.play_card` runs, the
-- automatic phases behind it run, and the call returns with the board already in
-- its next state. Everything in between — which card set off first, what it
-- passed on the way, what died — lived for the length of one call stack and was
-- thrown away, so a click cut to its result instead of playing it. Order is the
-- one thing the presentation cannot work out afterwards, because
-- `render.sync_places` diffs two *frames* and never two *steps*.
--
-- **A step is a snapshot.** The rules push one every time something visible
-- happens, and playing a step means putting that state on screen. Because each
-- one is a real state and not a description of a difference, everything comes
-- along for free: numbers, flips, pile counts, hidden hands, a purged card
-- that is still standing there to be watched going. There is no second account
-- of the board to keep true.
--
-- The swap is the whole mechanism. `entity.restore` already points the registry
-- at a different table, so `stage.enter` puts the presented state there for the
-- length of one frame and `stage.leave` puts the live one back. Nothing on the
-- drawing path had to learn about any of this: every derived answer the renderer
-- leans on — what a zone shows, whose hand it is, where the cells are — is
-- computed from whatever the registry holds, which is the point.
--
-- Nothing in the engine requires this file, and the hooks that feed it are nil
-- unless main.lua sets them — so headless has nothing to discard. The branches
-- never fire and the rules run at the speed they always did.
--
-- **Outside a click a step plays the moment it is recorded.** An undo, a game
-- being loaded, a whole state from the network: none of them have an order, and
-- `render.sync_places` animates the difference rather than the journey. A move
-- from the network is the exception, because the sender recorded its run and sent
-- it along: `replay` plays that the way a local click plays.

local entity = require("entity")

local M = {}

-- What the board waits before taking the next step. A shuffle is one gesture
-- however many cards it touched, and a beat of dead air after it is worse than
-- letting the next thing follow straight on.
local GAP = { move = 0.10, add = 0.10, purge = 0.10, stat = 0.14, effect = 0.10 }

-- A cascade runs up to sixty-four phase transitions and an each_seat loop inside
-- one of them can move the whole table. Past this the run stops being recorded
-- and the tail lands the way it always did — the alternative is making somebody
-- watch an upkeep resolve card by card.
local MAX_STEPS = 40

local steps, queue = {}, {}
local shipped = 0            -- how many of `steps` net has already been handed
local armed = false
local before                 -- the state the click started from
local presented, live        -- what is on screen, and what the rules are using
local clock, rate = 0, 1

-- `play` is what a step looks like, for the steps that have a look of their own.
-- A move has none: the state it lands in puts the card somewhere else, and the
-- layout the renderer asks for on the next frame is the flight.
--
-- `look` is the same thing told as facts — which stat, by how much, which effect
-- — for a step that has to survive the wire, where a closure cannot go. main.lua
-- supplies it, and reads its rects when the step plays rather than when it was
-- recorded, which is also the only moment a screen of another size has them.
M.look = nil   -- hook(what, id, data)

local function show(what, id, play, data)
	if play then play()
	elseif data and M.look then M.look(what, id, data) end
end

local function fire(s)
	presented = s.ents or presented
	show(s.what, s.id, s.play, s.data)
end

-- Everything still waiting, now. How a run ends, and what is owed to a click
-- that arrives after one has already been abandoned.
local function drain()
	for _, s in ipairs(queue) do fire(s) end
	queue = {}
	presented, before = nil, nil
	clock, rate = 0, 1
end

function M.record(what, id, play, data)
	if not armed or #steps >= MAX_STEPS then
		show(what, id, play, data)
		return
	end
	-- After the change, so the state a step carries is the one it produced.
	steps[#steps + 1] = { what = what, id = id, play = play, data = data, ents = entity.snapshot() }
end

-- What has been recorded since the last ask, for a run that is also being sent
-- to another machine. Once each: a click that publishes twice must not send its
-- first half again.
function M.recorded()
	local out = {}
	for i = shipped + 1, #steps do out[#out + 1] = steps[i] end
	shipped = #steps
	return out
end

local function enqueue(list)
	local at = 0
	for _, s in ipairs(list) do
		s.at = at
		at = at + (s.data and tonumber(s.data.wait) or GAP[s.what] or 0)
		queue[#queue + 1] = s
	end
end

-- Whatever the rules do between these two is one run.
function M.arm()
	if #queue > 0 then drain() end
	steps, shipped, armed = {}, 0, true
	before = entity.snapshot()
end

function M.seal()
	armed = false
	enqueue(steps)
	-- A run with nothing in it is not a run, and presenting the state the click
	-- started from would hold the board a frame behind for no reason.
	presented = #queue > 0 and before or nil
	steps, before = {}, nil
end

-- A run somebody else clicked: the states their beats were, rebuilt by net from
-- the one both sides shared, and played exactly as a local run is. The live
-- registry already holds where it ended.
function M.replay(from, beats)
	if #queue > 0 then drain() end
	enqueue(beats)
	presented = #queue > 0 and from or nil
end

function M.update(dt)
	if #queue == 0 then return end
	clock = clock + dt * rate
	while queue[1] and queue[1].at <= clock do
		fire(table.remove(queue, 1))
	end
	-- The last beat is the state the rules are already in, so there is nothing
	-- to hand over: the live registry says the same thing.
	if #queue == 0 then drain() end
end

function M.busy()
	return #queue > 0
end

-- Draw the state the player is owed rather than the one the rules have reached.
-- Card rects are presentation and belong to whatever is being drawn, so they
-- travel across the swap in both directions: in, so a card sets off from where
-- the eye last had it, and out, so hit-testing has somewhere to point on the
-- frame the run ends.
local function carry(from, to)
	for id, e in pairs(to) do
		local other = from[id]
		if other and other.place then e.place = other.place end
	end
end

function M.enter()
	if not presented or live then return end
	live = entity.registry()
	carry(live, presented)
	entity.restore(presented)
end

function M.leave()
	if not live then return end
	carry(presented, live)
	entity.restore(live)
	live = nil
end

-- A click in the middle of a run is impatience, not a mistake: the run speeds up
-- rather than being dropped, so what the player asked to see still happens and
-- the thread from cause to effect survives it.
function M.hurry()
	rate = math.min(8, rate * 3)
end

function M.speed()
	return rate
end

function M.clear()
	M.leave()
	drain()
	steps, shipped, armed = {}, 0, false
end

return M
