-- A phase announces itself.
--
-- Everything else that happens in this engine is caused by somebody: a card is
-- played, an ability is used, an action emits. A phase beginning and ending is
-- caused by nobody, so it announced nothing — and *"at the end of your turn"*,
-- which half the ongoing effects in every deck-builder are written as, had
-- nowhere to be said. Every rule that wanted it settled for a worse moment.
--
-- Two moments, and they are the two a phase already had: "begin", beside the
-- actions it runs on the way in, and "end", beside the hand it discards on the
-- way out. The subject is the player card of whoever the phase belongs to, so a
-- reaction reads @event as whose turn it is and "whose" means what it means
-- everywhere else.
--
-- Nothing is deferred. A phase has no action list waiting on the answer, so the
-- announcement goes up, the phase carries on, and whatever answers it resolves
-- beside it — which is how "at the end of your turn" reads at a table.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")

local M = {}

local GAME = [==[{
  "title": "Phase Emits",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "kept", "label": "Kept", "subject": "kept@mine.player" },
    { "key": "woke", "label": "Woke", "subject": "woke@mine.player" }
  ],
  "zones": [
    { "key": "hand", "type": "hand", "tags": ["per_seat"],
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "board", "type": "grid", "grid": [4, 1], "tags": ["activate"],
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "table", "type": "pile", "tags": ["per_seat"],
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "type": "pile", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "seat": "next",
      "emits": { "begin": "dawn", "end": "dusk" },
      "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "kept": 0, "woke": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "kept": 0, "woke": 0 } },
    { "key": "pass", "text": "Pass", "play": { "action": ["next_phase"] } },
    { "key": "stipend", "text": "Stipend", "tags": ["ongoing"],
      "reactions": [
        { "to": "dusk", "whose": "mine", "forced": "mandatory", "from": "board",
          "action": ["stat_gain:kept@mine.player:1"] }
      ] },
    { "key": "rooster", "text": "Rooster", "tags": ["ongoing"],
      "reactions": [
        { "to": "dawn", "whose": "mine", "forced": "mandatory", "from": "board",
          "action": ["stat_gain:woke@mine.player:1"] }
      ] },
    { "key": "vulture", "text": "Vulture", "tags": ["ongoing"],
      "reactions": [
        { "to": "dusk", "forced": "mandatory", "from": "board",
          "action": ["stat_gain:kept@mine.player:1"] }
      ] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_phase_emits.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_phase_emits.json")
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

-- Onto the board, and whose it is said out loud: a card dealt straight into a
-- shared grid belongs to nobody, and a reaction is offered to the seat that owns
-- the card carrying it.
local SEAT_INDEX = { one = 1, two = 2 }

local function lay_out(seat_key, def_key)
	local c = zones.add(hand_of(seat_key), def_key)
	zones.move_card(c.id, zones.find_id("board"))
	c.stats.owner = SEAT_INDEX[seat_key]
	return c
end

local function end_turn(seat_key)
	local p = zones.add(hand_of(seat_key), "pass")
	flow.play_card(p.id, {})
end

-- The moment that had nowhere to be said. A card on the board watches its own
-- controller's turn ending, which is "whose": "mine" over a verb only a phase
-- raises — two things that were each half of this and neither of which was
-- enough alone.
function M.test_phase_emits_a_turn_ending_is_answerable(check)
	with_game(function(name)
		flow.init(name, 3)
		lay_out("one", "stipend")

		check("nothing has fired yet", seat("one").stats.kept == 0)
		end_turn("one")
		check("the turn ending paid out", seat("one").stats.kept == 1,
			seat("one").stats.kept)
	end)
end

-- The other moment, and the other half of the pair: a phase beginning.
function M.test_phase_emits_a_turn_beginning_is_answerable(check)
	with_game(function(name)
		flow.init(name, 3)
		lay_out("two", "rooster")

		check("it has not crowed for a turn that has not begun",
			seat("two").stats.woke == 0, seat("two").stats.woke)
		-- Seat one ends its turn, so seat two's begins.
		end_turn("one")
		check("and it crows when that seat's turn opens",
			seat("two").stats.woke == 1, seat("two").stats.woke)
	end)
end

-- "whose" and a phase verb are the same two words they are anywhere else: the
-- default answers somebody *else's* turn ending, which is the reading a vulture
-- wants and the wrong one for a stipend.
function M.test_phase_emits_whose_reads_the_seat_the_phase_belongs_to(check)
	with_game(function(name)
		flow.init(name, 3)
		lay_out("two", "vulture")

		-- Seat one's turn ends. The vulture is seat two's and answers the other
		-- seat's, so it fires.
		end_turn("one")
		check("it took its cut of the other seat's turn",
			seat("two").stats.kept == 1, seat("two").stats.kept)
	end)
end

-- A phase nothing answers announces nothing, which is Filter A doing for phases
-- what it does for everything else: a game that writes "emits" on every phase
-- and has no reaction to any of them pays exactly nothing for it.
function M.test_phase_emits_nothing_answering_opens_no_window(check)
	with_game(function(name)
		flow.init(name, 3)
		local before = #(zones.find("stack") or { cards = {} }).cards
		end_turn("one")
		check("no record went up", #zones.find("stack").cards == before,
			#zones.find("stack").cards)
		check("and the turn changed hands as it always did",
			zones.active_seat() == "two", zones.active_seat())
	end)
end

-- A moment the engine does not have is refused where every other typo is: at
-- parse, the last place the authored entry exists.
function M.test_phase_emits_an_unknown_moment_is_refused(check)
	local declaration = require("declaration")
	local validate = require("validate")
	local path = "game/games/tmp_bad_phase_emits.json"
	local f = assert(io.open(path, "w"))
	f:write([==[{
		"title": "Bad Phase Emits",
		"zones": [{ "key": "board", "type": "grid", "grid": [2, 2], "tags": ["activate"] }],
		"phases": [{ "key": "turn", "type": "player_input", "emits": { "midday": "noon" } }],
		"cards": [{ "key": "thing", "text": "Thing" }]
	}]==])
	f:close()
	local ok, G = pcall(declaration.parse, "tmp_bad_phase_emits.json")
	os.remove(path)
	if not ok then error(G, 2) end
	local said = validate.check(G)
	local found = false
	for _, p in ipairs(said) do
		if p:find("emits at 'midday'", 1, true) then found = true end
	end
	check("a moment a phase does not have is refused", found, table.concat(said, "; "))
end

return M
