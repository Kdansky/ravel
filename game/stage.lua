-- One click, played back a beat at a time.
--
-- The rules resolve a whole click in a single frame: `flow.play_card` runs, the
-- automatic phases behind it run, and the call returns with the board already in
-- its next state. Everything in between — which card set off first, what it
-- passed on the way, what died — lived for the length of one call stack and was
-- thrown away, so a click cut to its result instead of playing it. Order is the
-- one thing the presentation cannot work out afterwards, because
-- `render.sync_places` diffs two *frames* and never two *steps*.
--
-- This is where that order is kept: a step is recorded as it happens, the run is
-- sealed when the input handler returns, and playback lets one step go at a time
-- while input is held.
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

local anim = require("anim")

local M = {}

-- What the board waits before taking the next step. Anything not listed is
-- recorded and costs no time: a destroyed card and one conjured out of a supply
-- have nothing to show until the presentation draws a state of its own, and a
-- beat of dead air is worse than a cut.
local GAP = { move = 0.10, add = 0.10, stat = 0.14, effect = 0.10 }

-- The steps that put a card somewhere, and so are the ones a card can be held
-- back for. A conjured card counts: a crash is a `fill`, and a gem arriving in
-- the pile it will end you from is the most important thing on the board.
local FLIGHT = { move = true, add = true }

-- A cascade runs up to sixty-four phase transitions and an each_seat loop inside
-- one of them can move the whole table. Past this the run stops being recorded
-- and the tail lands the way it always did — the alternative is making somebody
-- watch an upkeep resolve card by card.
local MAX_STEPS = 40

local steps, queue = {}, {}
local held  = {}
local armed = false
local clock, rate = 0, 1

local function fire(s)
	if held[s.id] then
		held[s.id] = nil
		if s.cut then anim.cut(s.id) else anim.release(s.id) end
	end
	if s.play then s.play() end
end

-- Everything still waiting, now. How a run ends, and what is owed to a click
-- that arrives after one has already been abandoned.
local function drain()
	for _, s in ipairs(queue) do fire(s) end
	for id in pairs(held) do anim.release(id) end
	queue, held = {}, {}
	clock, rate = 0, 1
end

-- `play` is what a step looks like, for the steps that have a look of their own.
-- A move has none: the tween it wants is the one the layout is already asking
-- for, and all this has to do is stop holding the card back.
function M.record(what, id, play)
	if not armed or #steps >= MAX_STEPS then
		if play then play() end
		return
	end
	steps[#steps + 1] = { what = what, id = id, play = play }
end

-- Whatever the rules do between these two is one run.
function M.arm()
	if #queue > 0 then drain() end
	steps, armed = {}, true
end

function M.seal()
	armed = false
	-- One card, one moment: whatever a card did in a run, it does it once, when
	-- it last did it. Until then it waits where the player last saw it.
	local moves, final = {}, {}
	for i, s in ipairs(steps) do
		if FLIGHT[s.what] then
			moves[s.id] = (moves[s.id] or 0) + 1
			final[s.id] = i
		end
	end
	local at = 0
	for i, s in ipairs(steps) do
		if not FLIGHT[s.what] or i == final[s.id] then
			if FLIGHT[s.what] then
				-- A card that moved once flies. One that moved several times has
				-- no honest flight left: a chip discarded, shuffled back in and
				-- drawn again would sail from the board to the hand, which is a
				-- journey it never made and a shuffle nobody may see the result
				-- of. It cuts instead — no line drawn, nothing claimed.
				s.cut      = moves[s.id] > 1
				held[s.id] = true
				anim.hold(s.id)
			end
			s.at = at
			at = at + (GAP[s.what] or 0)
			queue[#queue + 1] = s
		end
	end
	steps = {}
end

function M.update(dt)
	if #queue == 0 then return end
	clock = clock + dt * rate
	while queue[1] and queue[1].at <= clock do
		fire(table.remove(queue, 1))
	end
	-- A card pinned by a step that is no longer coming would sit there for the
	-- rest of the game, so the end of a run answers for every one of them.
	if #queue == 0 then drain() end
end

function M.busy()
	return #queue > 0
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
	drain()
	steps, armed = {}, false
end

return M
