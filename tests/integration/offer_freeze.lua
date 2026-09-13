-- Nothing about whose game it is moves while a question is on the table.
--
-- An offer is asked in a phase, of a seat, holding priority. End the phase while
-- it stands and the cards it borrowed have nowhere to come home to: the overlay
-- is still on the stack under a phase that has moved on, and Puzzle Strike's
-- whole eighteen-chip bank sat in it, unreachable, for exactly one afternoon.
--
-- **So the list waits.** It used to be refused where it stood, which was the
-- safe half of the answer and not the whole of it: "then end your action phase"
-- is a thing cards say, and a rule that drops it silently is a rule the file
-- cannot express. An action that asks a question parks the rest of its list on
-- the offer, and settle runs it once the question is answered — so the phase
-- still does not move while the offer is open, and it does move afterwards.
--
-- The refusal stays underneath as a backstop for anything that reaches those
-- verbs another way.

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local declaration = require("declaration")
local validate    = require("validate")

local M = {}

local GAME = [==[{
  "title": "Offer Freeze",
  "players": [{ "card": "one" }, { "card": "two" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.4, 0.9, 0.2], [0.05, 0.62, 0.9, 0.2]] },
    { "key": "vault", "layout": "row", "pos": [0.05, 0.05, 0.9, 0.25],
      "contents": ["gem:3"] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "rest" }] },
    { "key": "rest", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "gem", "text": "Gem", "tags": ["gem"] },
    { "key": "walker", "text": "Walker",
      "play": { "phases": ["act"], "action": ["show:vault", "end_phase"], "spent": "void" } },
    { "key": "hander", "text": "Hander",
      "play": { "phases": ["act"], "action": ["show:vault", "set_priority:enemy.player"],
                "spent": "void" } },
    { "key": "waiter", "text": "Waiter",
      "play": { "phases": ["act"], "action": ["show:vault"], "spent": "void" },
      "chosen": { "action": ["end_phase"] } }
  ]
}]==]

-- A card that asks two questions: which card to resolve, and then whatever the
-- resolved card asks in turn. Kept apart from GAME because the shape it tests
-- is the *nesting*, and mixing it into the freeze game would leave neither
-- reading as the thing it is about.
local NESTED = [==[{
  "title": "Nested Offer",
  "players": [{ "card": "one" }, { "card": "two" }],
  "zones": [
    { "key": "hand", "layout": "row", "copies": "per_seat", "visibility": "owner",
      "pos": [[0.05, 0.4, 0.9, 0.2], [0.05, 0.62, 0.9, 0.2]] },
    { "key": "vault", "layout": "row", "pos": [0.05, 0.05, 0.4, 0.25],
      "contents": ["inner:1"] },
    { "key": "shelf", "layout": "row", "pos": [0.5, 0.05, 0.4, 0.25],
      "contents": ["gem:3"] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "zone": "hand", "next": [{ "then": "act" }] }],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "gem", "text": "Gem" },
    { "key": "inner", "text": "Inner",
      "abilities": [{ "key": "ask", "action": ["show:shelf:optional"] }] },
    { "key": "asker", "text": "Asker",
      "play": { "phases": ["act"], "action": ["show:vault"], "spent": "void" },
      "chosen": { "action": ["copy:target:activate"] } }
  ]
}]==]

local function with_game(fn, text)
	local path = "game/games/tmp_offer_freeze.json"
	local f = assert(io.open(path, "w"))
	f:write(text or GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_offer_freeze.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function count_in(key)
	local z = zones.find(key)
	return #((z or {}).cards or {})
end

local function play(def_key)
	local c = zones.add(zones.find("hand"), def_key)
	return flow.play_card(c.id, {})
end

function M.test_offer_freeze_the_phase_waits_for_the_answer(check)
	with_game(function(name)
		flow.init(name, 3)
		check("the vault filled", count_in("vault") == 3, count_in("vault"))
		play("walker")
		check("the offer opened and holds the borrowed cards", count_in("options") == 3,
			count_in("options"))
		check("and the phase did not move out from under it",
			phase.current().key == "options", phase.current().key)
		check("the vault is empty while they are lent out", count_in("vault") == 0)

		local pick = entity.get(zones.find("options").cards[1])
		flow.play_card(pick.id, {})
		check("choosing sends every borrowed card home", count_in("vault") == 3,
			count_in("vault"))
		check("and now the rest of the list runs", phase.current().key == "rest",
			phase.current().key)
	end)
end

-- The same for priority, and it is the half that shows the waiting is real:
-- nothing hands the game over while the question the handover was written after
-- is still being asked.
--
-- What happens to it *after* the answer is a different rule and not this one's:
-- a handover made outside a response window is released as soon as the table is
-- quiet, which is what release_priority is for.
function M.test_offer_freeze_priority_waits_too(check)
	with_game(function(name)
		flow.init(name, 3)
		local before = zones.active_seat()
		play("hander")
		check("the offer is open", count_in("options") == 3)
		check("and priority stayed with the seat that asked",
			zones.active_seat() == before, tostring(zones.active_seat()))
	end)
end

-- The permitted route, and the reason the rule is a refusal rather than a
-- silent close: "chosen" runs once the offer has been answered, so the same
-- action does exactly what it was written to do.
function M.test_offer_freeze_allows_the_change_once_the_offer_has_closed(check)
	with_game(function(name)
		flow.init(name, 3)
		play("waiter")
		check("the offer is open", phase.current().key == "options")
		flow.play_card(zones.find("options").cards[1], {})
		check("chosen moved the phase on", phase.current().key == "rest",
			phase.current().key)
		check("and the borrowed cards still went home", count_in("vault") == 3,
			count_in("vault"))
	end)
end

-- An offer opened from inside a "chosen" block used to be eaten by the cleanup
-- meant for the offer that had just closed. There is one "options" zone and it
-- knows its contents by what is lying in it, so a sweep that ran after the
-- chosen actions could not tell the second question's cards from the first
-- question's leftovers -- and took both, along with the "dismissable" flag,
-- leaving an overlay with nothing in it and no way out.
--
-- This is not a rule about nesting. It is the ordering: the leftovers go home
-- before the chosen actions run, and only the picked card waits for them.
function M.test_offer_freeze_an_offer_may_open_inside_a_chosen_block(check)
	with_game(function(name)
		flow.init(name, 3)
		play("asker")
		check("the first question is on the table", phase.current().key == "options")
		check("holding the one card it borrowed", count_in("options") == 1,
			count_in("options"))

		-- Picking it copies it, and the copy asks the second question.
		flow.play_card(zones.find("options").cards[1], {})
		check("the second question is on the table now",
			phase.current().key == "options", phase.current().key)
		check("holding its own three cards, not an empty box",
			count_in("options") == 3, count_in("options"))
		check("which are lent out of the shelf, exactly as the first was",
			count_in("shelf") == 0, count_in("shelf"))
		check("the first question's card went home rather than staying to be counted",
			count_in("vault") == 1, count_in("vault"))
		check("and the offer knows who asked it, so it can be answered",
			zones.find("options").asked_by ~= nil)
		check("and walked away from, since this one said it could be",
			flow.can_dismiss())

		-- Answering it has to work too: a live-looking offer that cannot close
		-- is the same lock wearing a better face.
		flow.play_card(zones.find("options").cards[1], {})
		check("answering the second question closes it", phase.current().key == "act",
			phase.current().key)
		check("and its cards went home", count_in("shelf") == 3, count_in("shelf"))
	end, NESTED)
end

-- The validator used to call this a mistake and send the author to "chosen".
-- Now that the list waits, writing the action where the card says it is the
-- plain spelling, and warning about it would be telling the truth backwards.
function M.test_offer_freeze_asking_and_then_acting_is_not_a_mistake(check)
	with_game(function(name)
		local G = declaration.parse(name)
		local said = table.concat(validate.check(G), "; ")
		check("no warning about ending the phase after an ask",
			not said:find("end_phase", 1, true), said)
		check("nor about handing priority over after one",
			not said:find("set_priority", 1, true), said)
	end)
end

return M
