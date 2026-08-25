-- "whose" — whose announcement a reaction may answer.
--
-- Every reaction used to answer somebody else's action and only that, because
-- the window skipped the announcing seat outright. That is right for a shield
-- and wrong for half of Magic: you put a spell on the stack and then cast your
-- own instant that copies it, and nothing about that is answering an opponent.
--
-- Three readings, so a word rather than a flag, and the words are the ones a
-- scope already uses — "enemy", "mine", "anyone" — meaning here what they mean
-- there: whose, judged from the card asking. "enemy" is the default, so every
-- reaction written before the field existed answers exactly what it did.
--
-- What keeps it from running away is not the seat check. It is that **one card
-- answers one record once**: the answer is a new record with its own memory, so
-- a chain gets longer rather than looping, and the stack has a depth it will not
-- pass.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")

local M = {}

local GAME = [==[{
  "title": "Whose",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [{ "key": "landed", "label": "Landed", "subject": "landed@mine.player" }],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "tags": {
    "spell": { "emits": { "play": "cast" }, "tooltip": "Goes on the stack, and may be answered." }
  },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "landed": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "landed": 0 } },
    { "key": "bolt", "text": "Bolt", "tags": ["spell", "bolt"],
      "play": { "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.table" } },
    { "key": "shield", "text": "Shield", "tags": ["counter"],
      "reactions": [
        { "to": "cast", "text": "Deny it", "action": ["counterspell"], "spent": "mine.table" }
      ] },
    { "key": "twin", "text": "Twin", "tags": ["counter"],
      "reactions": [
        { "to": "cast", "whose": "mine", "text": "Again",
          "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.table" }
      ] },
    { "key": "meddle", "text": "Meddle", "tags": ["counter"],
      "reactions": [
        { "to": "cast", "whose": "anyone", "text": "Meddle",
          "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.table" }
      ] },
    { "key": "siren", "text": "Siren", "tags": ["noise"],
      "play": { "action": ["emit:play"], "spent": "mine.table" } },
    { "key": "echo", "text": "Echo", "tags": ["engine"],
      "reactions": [
        { "to": "play", "whose": "anyone", "forced": "mandatory", "from": "board",
          "action": ["stat_gain:landed@mine.player:1"] }
      ] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_whose.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_whose.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function seat(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function give(seat_key, def_key)
	return zones.add(hand_of(seat_key), def_key)
end

local function stack_count()
	return #(zones.find("stack") or { cards = {} }).cards
end

-- The default, stated so it stays true: no word means somebody else's, which is
-- what every reaction meant before the field existed.
function M.test_whose_defaults_to_the_other_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = give("one", "bolt")
		give("one", "shield")
		give("two", "shield")

		flow.play_card(bolt.id, {})
		check("a window opened", stack_count() == 1, stack_count())
		check("and it is the other seat holding it", zones.active_seat() == "two",
			zones.active_seat())
		check("their shield is on offer", #flow.usable_reactions() == 1,
			#flow.usable_reactions())
	end)
end

-- The caster's own shield is not on offer for the caster's own spell, which is
-- the whole of what a shield means and what must not change.
function M.test_whose_a_shield_does_not_answer_its_own_side(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = give("one", "bolt")
		local own  = give("one", "shield")
		give("two", "shield")

		flow.play_card(bolt.id, {})
		check("the window belongs to the other seat", zones.active_seat() == "two",
			zones.active_seat())
		check("and our own shield is not on offer in it",
			not flow.can_react(own.id))
		check("nor may it be played into it", not flow.react(own.id, 1, {}))
	end)
end

-- The half that was missing. A spell of your own is on the stack and you answer
-- it yourself — Magic's copy-your-own-spell, and nothing about it involves an
-- opponent.
function M.test_whose_mine_answers_your_own_announcement(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = give("one", "bolt")
		local twin = give("one", "twin")

		flow.play_card(bolt.id, {})
		check("the caster is the one holding priority", zones.active_seat() == "one",
			zones.active_seat())
		check("and their own answer is on offer", #flow.usable_reactions() == 1,
			#flow.usable_reactions())

		check("it is accepted", flow.react(twin.id, 1, {}))
		-- Nothing is left to ask: the twin has answered this record and may not
		-- answer it twice, so its own answer and then the spell both resolve.
		check("the answer and the spell both landed",
			seat("one").stats.landed == 2, seat("one").stats.landed)
		check("and the stack emptied", stack_count() == 0, stack_count())
	end)
end

-- "mine" is only your own: the other seat's announcement is not one of them.
function M.test_whose_mine_is_not_offered_to_the_other_seat(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = give("one", "bolt")
		give("two", "twin")

		-- Seat one casts. Seat two holds a reaction that answers *its own* side
		-- only, so there is nobody to ask and no window to open.
		flow.play_card(bolt.id, {})
		check("no window opened at all", stack_count() == 0, stack_count())
		check("and the spell simply landed", seat("one").stats.landed == 1,
			seat("one").stats.landed)
	end)
end

-- "anyone" is both, and the order is the one the protocol already had: the seat
-- that announced is asked first, because it is holding priority.
function M.test_whose_anyone_answers_either_side(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = give("one", "bolt")
		local mine = give("one", "meddle")
		give("two", "meddle")

		flow.play_card(bolt.id, {})
		check("the caster is asked first", zones.active_seat() == "one", zones.active_seat())
		check("their own is on offer", #flow.usable_reactions() == 1)
		flow.pass_react()
		check("and then the other seat is", zones.active_seat() == "two", zones.active_seat())
		check("with theirs on offer", #flow.usable_reactions() == 1)

		-- Back to the caster, who still has it: passing does not spend a card.
		check("the caster's is still theirs to play", entity.get(mine.id).zone_id == hand_of("one").id)
	end)
end

-- One card answers one record once. That is what stops a chain becoming a loop,
-- and it is the rule that had to hold before "mine" could be safe at all.
function M.test_whose_a_card_answers_a_record_only_once(check)
	with_game(function(name)
		flow.init(name, 3)
		local bolt = give("one", "bolt")
		local twin = give("one", "twin")

		flow.play_card(bolt.id, {})
		check("the answer is accepted once", flow.react(twin.id, 1, {}))
		-- The record it answered is underneath now, and the top is its own
		-- answer — which it has not answered, but it is no longer in a hand.
		check("and not a second time on the same record",
			not flow.react(twin.id, 1, {}))
	end)
end

-- A mandatory reaction that never leaves the board and answers anybody would
-- answer its own answer forever. The stack has a depth it will not pass, and it
-- says so rather than taking the process with it.
function M.test_whose_a_reaction_answering_its_own_answer_is_bounded(check)
	with_game(function(name)
		flow.init(name, 3)
		local echo = give("one", "echo")
		-- Onto the board, where it stays: from "board" and no "spent". It answers
		-- "play", which is the verb every *answer* goes up as — so its own answer
		-- is something it answers again.
		zones.move_card(echo.id, zones.find_id("board"))
		local siren = give("one", "siren")

		flow.play_card(siren.id, {})
		check("it stopped rather than hanging", stack_count() <= 32, stack_count())
		-- At the limit the trigger is marked as having had its go, so the seat is
		-- asked as usual and a single pass unwinds the whole chain.
		check("the seat is asked rather than the game hanging", flow.pass_react())
		check("and the stack unwound", stack_count() == 0, stack_count())
		check("with the echo having fired all the way down",
			seat("one").stats.landed > 1, seat("one").stats.landed)
	end)
end

return M
