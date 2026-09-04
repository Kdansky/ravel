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
-- along for free: numbers, flips, pile counts, hidden hands, a destroyed card
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
-- **Outside a click a step plays the moment it is recorded.** A state that
-- arrived over the network, an undo, a game being loaded: none of them have an
-- order, because the moves that made them were not made in this process. That is
-- not a gap to be filled in later. It is the answer `render.sync_places` already
-- gives, which is to animate the difference rather than the journey.

local entity = require("entity")

local M = {}

-- What the board waits before taking the next step. A shuffle is one gesture
-- however many cards it touched, and a beat of dead air after it is worse than
-- letting the next thing follow straight on.
local GAP = { move = 0.10, add = 0.10, destroy = 0.10, stat = 0.14, effect = 0.10 }

-- A cascade runs up to sixty-four phase transitions and an each_seat loop inside
-- one of them can move the whole table. Past this the run stops being recorded
-- and the tail lands the way it always did — the alternative is making somebody
-- watch an upkeep resolve card by card.
local MAX_STEPS = 40

local steps, queue = {}, {}
local armed = false
local before                 -- the state the click started from
local presented, live        -- what is on screen, and what the rules are using
local clock, rate = 0, 1

-- `play` is what a step looks like, for the steps that have a look of their own.
-- A move has none: the state it lands in puts the card somewhere else, and the
-- layout the renderer asks for on the next frame is the flight.
local function fire(s)
	presented = s.ents or presented
	if s.play then s.play() end
end

-- Everything still waiting, now. How a run ends, and what is owed to a click
-- that arrives after one has already been abandoned.
local function drain()
	for _, s in ipairs(queue) do fire(s) end
	queue = {}
	presented, before = nil, nil
	clock, rate = 0, 1
end

function M.record(what, id, play)
	if not armed or #steps >= MAX_STEPS then
		if play then play() end
		return
	end
	-- After the change, so the state a step carries is the one it produced.
	steps[#steps + 1] = { what = what, id = id, play = play, ents = entity.snapshot() }
end

-- Whatever the rules do between these two is one run.
function M.arm()
	if #queue > 0 then drain() end
	steps, armed = {}, true
	before = entity.snapshot()
end

function M.seal()
	armed = false
	local at = 0
	for _, s in ipairs(steps) do
		s.at = at
		at = at + (GAP[s.what] or 0)
		queue[#queue + 1] = s
	end
	-- A run with nothing in it is not a run, and presenting the state the click
	-- started from would hold the board a frame behind for no reason.
	presented = #queue > 0 and before or nil
	steps, before = {}, nil
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
	steps, armed = {}, false
end

return M
