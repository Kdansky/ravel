-- Acting on an announcement rather than on a card.
--
-- A record on the stack is not a card and is not a copy of one: it is the fact
-- that something was announced, and it went up carrying what it was aimed at.
-- That is the whole reason these two words are cheap. Copying a *card* needs
-- somebody to aim the copy, which is why a copied play makes an imaginary card
-- and a copied ability is refused; copying a *record* needs nothing asked at
-- all. And re-aiming one is only possible because the aim is written down where
-- a rule can reach it.
--
-- `answered` is how a reaction names the thing it is answering — the same
-- addressing `counterspell` has always used, said out loud so that two more
-- verbs can share it.

local entity = require("entity")
local zones  = require("zones")
local flow   = require("flow")

local M = {}

local GAME = [==[{
  "title": "On the Stack",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "hp", "label": "HP", "on": ["unit"], "start": 5, "min": 0, "max": 9 }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "board", "layout": "grid", "status": "board", "grid": [4, 1], "copies": "per_seat",
      "pos": [[0.20, 0.55, 0.80, 0.70], [0.20, 0.25, 0.80, 0.40]] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.60, 0.70, 0.78] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "tags": {
    "spell": { "emits": { "play": "cast" } }
  },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"] },
    { "key": "two", "text": "Two", "tags": ["seat_two"] },
    { "key": "grunt", "text": "Grunt", "tags": ["unit"] },
    { "key": "rock", "text": "Rock", "tags": ["stone"] },
    { "key": "bolt", "text": "Bolt", "tags": ["spell"],
      "play": { "target": { "type": "card", "tags": ["unit"], "zones": ["board"], "owner": "anyone", "count": 1 },
        "action": ["stat_damage:hp@target:1"], "spent": "mine.table" } },
    { "key": "echo", "text": "Echo", "tags": ["unit"],
      "reactions": [{ "to": "cast", "whose": "enemy", "in": "board", "key": "again", "text": "Again",
        "action": ["copy:answered"] }] },
    { "key": "jandra", "text": "Jandra", "tags": ["unit"],
      "reactions": [{ "to": "cast", "whose": "enemy", "in": "board", "key": "take_it", "text": "Take it", "needs": { "event": ["not_self@target"] }, "action": ["redirect:answered:self"] }] },
    { "key": "crook", "text": "Crook", "tags": ["unit"],
      "reactions": [{ "to": "cast", "whose": "enemy", "in": "board", "key": "shove", "text": "Shove",
        "action": ["redirect:answered:stone"] }] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_on_the_stack.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_on_the_stack.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function stack_count()
	return #(zones.find("stack") or { cards = {} }).cards
end

local function board_of(key)
	for _, z in ipairs(zones.all_with_key("board")) do
		if z.seat == key then return z end
	end
end

-- Answer the window with the reaction the card offers. The reactor must be the
-- seat that is up, which the window has already handed priority to.
local function react_with(card_id, index)
	return flow.react(card_id, index or 1)
end

-- The plain case, and the one that says why a record is the easy thing to copy:
-- nothing is asked, because the announcement already knows what it is pointed at.
function M.test_on_the_stack_a_copied_record_keeps_its_aim(check)
	with_game(function(name)
		flow.init(name, 3)
		local mark = zones.add(board_of("one"), "grunt")
		zones.add(board_of("two"), "echo")
		local bolt = zones.add(hand_of("one"), "bolt")

		flow.play_card(bolt.id, { mark.id })
		check("the bolt is announced rather than resolved", stack_count() == 1, stack_count())
		check("and nothing has been hit yet", entity.get(mark.id).stats.hp == 5,
			entity.get(mark.id).stats.hp)

		local ec
		for e in entity.each("card") do if e.def_key == "echo" then ec = e end end
		check("the echo answers it", react_with(ec.id))
		flow.settle()
		check("the grunt was hit twice, at the aim the first one already had",
			entity.get(mark.id).stats.hp == 3, entity.get(mark.id).stats.hp)
		check("and the stack is empty again", stack_count() == 0, stack_count())
	end)
end

-- **Jandra.** *"Spells and abilities aimed at your other cards hit Jandra
-- instead"* — an aim redirected after it is made, which a counter cannot say and
-- a card cannot either, because by then the aim is on the stack and not on the
-- card. The condition is the half that needed the plumbing: a reaction could not
-- see what the announcement was pointed at, so "aimed at my *other* cards" had
-- no way to be written.
function M.test_on_the_stack_a_record_may_be_aimed_somewhere_else(check)
	with_game(function(name)
		flow.init(name, 3)
		local mark = zones.add(board_of("one"), "grunt")
		local jan  = zones.add(board_of("two"), "jandra")
		local bolt = zones.add(hand_of("one"), "bolt")

		flow.play_card(bolt.id, { mark.id })
		check("Jandra may answer, because the bolt is aimed at somebody else",
			react_with(jan.id))
		flow.settle()
		check("she took it instead", entity.get(jan.id).stats.hp == 4,
			entity.get(jan.id).stats.hp)
		check("and the grunt was not touched", entity.get(mark.id).stats.hp == 5,
			entity.get(mark.id).stats.hp)
	end)
end

-- The condition reads the record's aim, so a bolt already pointed at Jandra
-- offers her nothing to do. Without the targets reaching a reaction's "where",
-- this reads as answering everything.
function M.test_on_the_stack_a_reaction_can_read_what_was_aimed_at(check)
	with_game(function(name)
		flow.init(name, 3)
		local jan  = zones.add(board_of("two"), "jandra")
		local bolt = zones.add(hand_of("one"), "bolt")

		flow.play_card(bolt.id, { jan.id })
		check("a bolt already aimed at her raises no window at all",
			not react_with(jan.id))
		flow.settle()
		check("and it lands on her the ordinary way", entity.get(jan.id).stats.hp == 4,
			entity.get(jan.id).stats.hp)
	end)
end

-- **Legal by the announcement's rule, not the redirector's.** The bolt may only
-- be aimed at a unit on the board; a card that tries to put it anywhere else
-- changes nothing rather than half of it, and the aim it had stands.
function M.test_on_the_stack_a_redirect_may_not_launder_an_illegal_aim(check)
	with_game(function(name)
		flow.init(name, 3)
		local mark  = zones.add(board_of("one"), "grunt")
		local crook = zones.add(board_of("two"), "crook")
		zones.add(board_of("two"), "rock")
		local bolt  = zones.add(hand_of("one"), "bolt")

		flow.play_card(bolt.id, { mark.id })
		react_with(crook.id)
		flow.settle()
		check("the bolt landed where it was aimed", entity.get(mark.id).stats.hp == 4,
			entity.get(mark.id).stats.hp)
		check("and the crook took nothing", entity.get(crook.id).stats.hp == 5,
			entity.get(crook.id).stats.hp)
		local said = table.concat(require("log").tail(8), " | ")
		check("with the refusal said out loud", said:find("redirect:", 1, true), said)
	end)
end

return M
