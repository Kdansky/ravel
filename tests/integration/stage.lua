-- A click played back a beat at a time.
--
-- `stage` is presentation, so none of this proves anything about the rules —
-- what it proves is that the rules can be watched: that the order things
-- happened in survives the frame they happened in, that a card can be held
-- where the player last saw it while the board runs on ahead, and that every
-- way out of a run puts every held card back down again.

local entity = require("entity")
local zones  = require("zones")
local flow   = require("flow")
local stage  = require("stage")
local anim   = require("anim")

local M = {}

local GAME = [==[{
  "title": "Stage",
  "players": [{ "card": "one" }],
  "zones": [
    { "key": "deck", "layout": "stack", "pos": [0.05, 0.40, 0.15, 0.60],
      "contents": ["ash", "birch", "cedar"] },
    { "key": "hand", "layout": "row", "pos": [0.20, 0.80, 0.80, 0.95] },
    { "key": "bin", "layout": "stack", "pos": [0.85, 0.40, 0.95, 0.60] },
    { "key": "box", "layout": "grid", "grid": [1, 1], "status": "supply",
      "contents": ["cedar:9"], "pos": [0.05, 0.05, 0.15, 0.20] }
  ],
  "phases": [{ "key": "act", "type": "player_input", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One" },
    { "key": "ash", "text": "Ash" },
    { "key": "birch", "text": "Birch" },
    { "key": "cedar", "text": "Cedar" }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_stage.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	stage.clear()
	anim.clear()
	zones.on_change = function(what, id) stage.record(what, id) end
	local ok, err = pcall(fn, "tmp_stage.json")
	zones.on_change = nil
	stage.clear()
	anim.clear()
	os.remove(path)
	if not ok then error(err, 0) end
end

local function card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

-- Cards are drawn from wherever the layout put them, and headless has no
-- layout, so the rects here are made up. Only the fact that one is *kept* is
-- being tested.
local function stand(e, x)
	e.place = { x = x, y = 100, w = 40, h = 60 }
end

-- What the layout does on the frame after a click: every moved card is asked
-- for the flight it is about to make. A held one keeps the request instead of
-- setting off, which is the whole trick.
local function layout(e, x)
	anim.move(e.id, e.place, { x = x, y = 400, w = 40, h = 60 }, "glide")
end

-- One frame of love.update, in its order: the layout has already spoken, the
-- run lets go of whatever is due, and the tweens then advance.
local function frame(dt)
	stage.update(dt)
	anim.update(dt * stage.speed())
end

function M.test_a_run_plays_in_the_order_it_happened(check)
	with_game(function(name)
		flow.init(name, 1)
		local hand = zones.find_id("hand")
		local ash, birch = card("ash"), card("birch")
		stand(ash, 10)
		stand(birch, 20)

		stage.arm()
		zones.move_card(ash.id, hand)
		zones.move_card(birch.id, hand)
		stage.seal()

		layout(ash, 300)
		layout(birch, 360)
		check("the run is holding both cards", stage.busy())
		check("ash has not set off yet", anim.visual_place(ash.id).x == 10)
		check("nor has birch", anim.visual_place(birch.id).x == 20)

		frame(0.05)
		check("ash goes first", anim.visual_place(ash.id).x > 10)
		check("birch is still waiting its turn", anim.visual_place(birch.id).x == 20)

		frame(0.20)
		check("birch follows a beat later", anim.visual_place(birch.id).x > 20)
		check("and the run is over", not stage.busy())
	end)
end

function M.test_a_card_that_moved_twice_does_not_fly(check)
	with_game(function(name)
		flow.init(name, 1)
		local ash = card("ash")
		stand(ash, 10)

		stage.arm()
		zones.move_card(ash.id, zones.find_id("hand"))
		zones.move_card(ash.id, zones.find_id("bin"))
		stage.seal()
		layout(ash, 800)

		-- A chip discarded, shuffled back in and drawn again would sail from the
		-- board to the hand, which is a trip it never made and a shuffle nobody
		-- may see the result of. So it waits where it was, and then it is simply
		-- somewhere else.
		check("it waits where it stood", anim.visual_place(ash.id).x == 10)
		frame(0.05)
		check("and then draws no line at all", anim.visual_place(ash.id) == nil)
		check("with nothing left queued behind it", not stage.busy())
	end)
end

-- A crash in Puzzle Strike is a `fill`: gems are conjured into the other pile
-- and the bank's stock is docked by a separate action, with nothing linking the
-- two. So the most important thing on the board happened in no time at all —
-- the gems had never been anywhere to travel from. The supply that stocks the
-- kind is the honest answer to where they were.
function M.test_a_conjured_card_comes_from_the_supply_that_stocks_it(check)
	with_game(function(name)
		flow.init(name, 1)
		local box = zones.find("box")
		check("the box keeps one real cedar and counts the rest",
			#box.cards == 1 and entity.get(box.cards[1]).stats.stock == 9)
		check("and it is what stocks a cedar", zones.supply_of("cedar").id == box.cards[1])
		check("nothing stocks an ash", zones.supply_of("ash") == nil)

		stage.arm()
		zones.add(zones.find("hand"), "cedar")
		stage.seal()

		local made
		for e in entity.each("card") do
			if e.def_key == "cedar" and e.zone_id == zones.find_id("hand") then made = e end
		end
		check("the new card is held, so the run can hand it a beat", made and anim.holding(made.id))
	end)
end

function M.test_nothing_outside_a_run_waits(check)
	with_game(function(name)
		flow.init(name, 1)
		local ash = card("ash")
		stand(ash, 10)

		-- No arm: a state that arrived from somewhere else, an undo, a load.
		zones.move_card(ash.id, zones.find_id("hand"))
		check("no run started", not stage.busy())

		local played = false
		stage.record("stat", ash.id, function() played = true end)
		check("a step outside a run plays as it is recorded", played)
	end)
end

function M.test_impatience_speeds_a_run_up(check)
	with_game(function(name)
		flow.init(name, 1)
		local ash, birch, cedar = card("ash"), card("birch"), card("cedar")
		stand(ash, 10)
		stand(birch, 20)
		stand(cedar, 30)

		stage.arm()
		for _, e in ipairs({ ash, birch, cedar }) do
			zones.move_card(e.id, zones.find_id("hand"))
		end
		stage.seal()

		frame(0.01)
		check("at rest the run takes its time", stage.busy())
		stage.hurry()
		check("and the clock speeds up", stage.speed() > 1)
		frame(0.09)
		check("which finishes it early", not stage.busy())
		check("the speed resets with the run", stage.speed() == 1)
	end)
end

function M.test_every_way_out_puts_the_cards_down(check)
	with_game(function(name)
		flow.init(name, 1)
		local ash = card("ash")
		stand(ash, 10)

		stage.arm()
		zones.move_card(ash.id, zones.find_id("hand"))
		stage.seal()
		layout(ash, 300)
		check("held while the run waits", anim.visual_place(ash.id).x == 10)

		-- What an undo does, and a load, and a game that reset underneath us.
		stage.clear()
		check("clearing the run ends it", not stage.busy())
		anim.update(0.05)
		check("and lets the card go", anim.visual_place(ash.id).x > 10)
	end)
end

function M.test_a_cascade_is_not_recorded_for_ever(check)
	with_game(function(name)
		flow.init(name, 1)
		local hand, bin = zones.find_id("hand"), zones.find_id("bin")
		local ash = card("ash")
		stand(ash, 10)

		stage.arm()
		-- Far more steps than a run keeps. Past the cap they are not recorded,
		-- so the tail lands the way it always did rather than being watched.
		local played = 0
		for _ = 1, 200 do
			zones.move_card(ash.id, hand)
			zones.move_card(ash.id, bin)
			stage.record("stat", ash.id, function() played = played + 1 end)
		end
		stage.seal()
		check("the tail played as it was recorded", played > 0)

		local guard = 0
		while stage.busy() and guard < 1000 do
			frame(0.05)
			guard = guard + 1
		end
		check("and the run still ends", not stage.busy())
	end)
end

return M
