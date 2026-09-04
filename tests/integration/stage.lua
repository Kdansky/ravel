-- A click played back a beat at a time.
--
-- `stage` is presentation, so none of this proves anything about the rules —
-- what it proves is that the rules can be watched: that the order things
-- happened in survives the frame they happened in, that the board a player is
-- looking at is a state the rules have already left behind, and that every way
-- out of a run puts the live state back.

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
-- for the flight it is about to make.
local function layout(e, x)
	anim.move(e.id, e.place, { x = x, y = 400, w = 40, h = 60 }, "glide")
end

-- Where the drawing path would find a card this frame, which is the whole of
-- what stage 2 is: during a run it is a state the rules have moved on from.
local function shown(id)
	stage.enter()
	local e = entity.get(id)
	local zone = e and e.zone_id
	stage.leave()
	return zone
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
		local hand, deck = zones.find_id("hand"), zones.find_id("deck")
		local ash, birch = card("ash"), card("birch")

		stage.arm()
		zones.move_card(ash.id, hand)
		zones.move_card(birch.id, hand)
		stage.seal()

		check("a run is playing", stage.busy())
		check("the rules have both cards in hand already",
			ash.zone_id == hand and birch.zone_id == hand)
		check("but the board still shows them where they were",
			shown(ash.id) == deck and shown(birch.id) == deck)

		frame(0.05)
		check("ash arrives first", shown(ash.id) == hand)
		check("birch is still waiting its turn", shown(birch.id) == deck)

		frame(0.20)
		check("birch follows a beat later", shown(birch.id) == hand)
		check("and the run is over", not stage.busy())
		check("which hands the live state back", shown(birch.id) == hand)
	end)
end

-- Stage 1 could only cut here: with one state on screen, a chip discarded and
-- then drawn again had no honest flight left, so it waited and was afterwards
-- simply somewhere else. A state per step is what replaces the cut with the
-- journey — it went to the bin, and then it came back.
function M.test_a_card_that_moved_twice_makes_both_moves(check)
	with_game(function(name)
		flow.init(name, 1)
		local hand, bin, deck = zones.find_id("hand"), zones.find_id("bin"), zones.find_id("deck")
		local ash = card("ash")

		stage.arm()
		zones.move_card(ash.id, bin)
		zones.move_card(ash.id, hand)
		stage.seal()

		check("it starts where the player last had it", shown(ash.id) == deck)
		frame(0.05)
		check("the first move is shown", shown(ash.id) == bin)
		frame(0.10)
		check("and then the second", shown(ash.id) == hand)
		check("with nothing left queued behind it", not stage.busy())
	end)
end

-- A card that appears out of nothing has no earlier position by definition. What
-- a state per step buys is that it is not drawn at all until its beat, rather
-- than standing in the destination from the first frame of the run.
function M.test_a_conjured_card_is_not_there_before_its_beat(check)
	with_game(function(name)
		flow.init(name, 1)
		local box, hand = zones.find("box"), zones.find("hand")
		check("the box keeps one real cedar and counts the rest",
			#box.cards == 1 and entity.get(box.cards[1]).stats.stock == 9)
		check("and it is what stocks a cedar", zones.supply_of("cedar").id == box.cards[1])
		check("nothing stocks an ash", zones.supply_of("ash") == nil)

		stage.arm()
		zones.take(entity.get(box.cards[1]), hand.id)
		stage.seal()

		local made
		for e in entity.each("card") do
			if e.def_key == "cedar" and e.zone_id == hand.id then made = e end
		end
		check("the rules made it", made ~= nil)
		check("but the board has not got it yet", shown(made.id) == nil)
		check("and the box still reads nine on screen", (function()
			stage.enter()
			local n = entity.get(box.cards[1]).stats.stock
			stage.leave()
			return n
		end)() == 9)

		frame(0.05)
		check("it arrives on its beat", shown(made.id) == hand.id)
		check("and the box is docked at the same moment",
			entity.get(box.cards[1]).stats.stock == 8)
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
		check("the board is a step behind while the run waits",
			shown(ash.id) == zones.find_id("deck"))

		-- What an undo does, and a load, and a game that reset underneath us.
		stage.clear()
		check("clearing the run ends it", not stage.busy())
		check("and hands the live state straight back",
			shown(ash.id) == zones.find_id("hand"))
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
