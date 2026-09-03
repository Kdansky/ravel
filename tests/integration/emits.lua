-- Announcing, and what it costs when nobody is listening.
--
-- Two ways a thing says it happened. A card says it by carrying "emits" — almost
-- always from a tag, so one "spell" line makes every spell in the game answerable
-- — and the interaction named there then puts it up instead of resolving it. An
-- action says it with "emit:<verb>", for the things no card was played to cause:
-- a crash, a summon, a buy.
--
-- "emits" is keyed by the moment because one card is often two things. The altar
-- below is a spell from hand and a machine on the board, answered as a "cast"
-- when it is played and an "ability" when it is used, and the two reactions that
-- watch for those must not catch each other.
--
-- The half these tests care most about is the negative one. An announcement
-- nobody can answer must be *exactly* the play it always was: no stack, no
-- window, no prompt. That is what lets a game sprinkle emits about without
-- turning every click into a question.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")

local M = {}

local GAME = [==[{
  "title": "Emits",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "landed", "label": "Landed", "subject": "landed@mine.player" },
    { "key": "crashed", "label": "Crashed", "subject": "crashed@mine.player" }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "board", "layout": "grid", "use": "abilities", "grid": [4, 1],
      "pos": [0.20, 0.35, 0.50, 0.50] },
    { "key": "bag", "layout": "stack", "visibility": "secret", "copies": "per_seat",
      "pos": [[0.05, 0.80, 0.15, 0.95], [0.05, 0.05, 0.15, 0.20]] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "stack", "layout": "stack", "tags": ["stack"], "pos": [0.55, 0.45, 0.70, 0.65] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "tags": {
    "spell": { "emits": { "play": "cast" }, "tooltip": "Goes on the stack, and may be answered." },
    "engine": { "emits": { "activate": "ability" }, "tooltip": "Using it may be answered." }
  },
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "landed": 0, "crashed": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "landed": 0, "crashed": 0 } },
    { "key": "fireball", "text": "Fireball", "tags": ["spell", "fireball"],
      "play": { "action": ["stat_gain:landed@mine.player:1"], "spent": "mine.table" } },
    { "key": "dagger", "text": "Dagger", "tags": ["fireball"],
      "play": { "action": ["stat_gain:landed@mine.player:1"] } },
    { "key": "gem", "text": "Gem", "tags": ["gem"],
      "play": { "action": ["emit:crash:stat_gain:crashed@mine.player:1"], "spent": "mine.table" } },
    { "key": "altar", "text": "Altar", "tags": ["spell", "engine", "fireball"],
      "play": { "action": ["move_to:board"] },
      "activate": { "action": ["stat_gain:landed@mine.player:1"] } },
    { "key": "flame_counter", "text": "Flame Counter", "tags": ["counter"],
      "reactions": [
        { "to": "cast", "where": ["tagged:fireball@event"], "action": ["counterspell"] }
      ] },
    { "key": "crash_counter", "text": "Crash Counter", "tags": ["counter"],
      "reactions": [
        { "to": "crash", "where": ["tagged:gem@event"], "action": ["counterspell"] }
      ] },
    { "key": "prism", "text": "Prism", "tags": ["counter"],
      "reactions": [
        { "to": "cast", "key": "deny", "text": "Deny it", "action": ["counterspell"] },
        { "to": "cast", "key": "profit", "text": "Take one instead",
          "action": ["stat_gain:landed@mine.player:1"] }
      ] },
    { "key": "ward", "text": "Ward", "tags": ["counter"],
      "reactions": [
        { "to": "cast", "forced": "mandatory", "where": ["tagged:fireball@event"],
          "action": ["counterspell"], "spent": "mine.table" }
      ] },
    { "key": "silence", "text": "Silence", "tags": ["counter"],
      "reactions": [
        { "to": "ability", "action": ["counterspell"] }
      ] }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_emits.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_emits.json")
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

local function bag_of(key)
	for _, z in ipairs(zones.all_with_key("bag")) do
		if z.seat == key then return z end
	end
end

local function table_of(key)
	for _, z in ipairs(zones.all_with_key("table")) do
		if z.seat == key then return z end
	end
end

local function stack_count()
	return #(zones.find("stack") or { cards = {} }).cards
end

-- The tag does the wiring. Nothing on the fireball says "stack me": it carries
-- "spell", the tag says spells announce a cast, and playing it puts it up.
function M.test_emits_a_tag_defers_the_play(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		give("two", "flame_counter")

		flow.play_card(fb.id, {})
		check("the spell is waiting on the stack", stack_count() == 1, stack_count())
		check("and has not landed", seat("one").stats.landed == 0, seat("one").stats.landed)
		check("the other seat may answer", zones.active_seat() == "two", zones.active_seat())
		check("while the turn stays where it was", zones.turn_seat() == "one", zones.turn_seat())
	end)
end

-- The whole of the suppression: the same card, the same tag, nobody holding an
-- answer. It plays the instant it is clicked and never touches the stack.
function M.test_emits_unanswerable_play_is_immediate(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")

		flow.play_card(fb.id, {})
		check("it landed at once", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("nothing was put up", stack_count() == 0, stack_count())
		check("and the turn seat is still acting", zones.active_seat() == "one", zones.active_seat())
	end)
end

-- A card the counter would happily answer, that never announces itself. Filter A
-- is about the verb, so an unspoken cast is not a cast.
function M.test_emits_a_card_without_the_tag_never_asks(check)
	with_game(function(name)
		flow.init(name, 3)
		local dg = give("one", "dagger")
		give("two", "flame_counter")

		flow.play_card(dg.id, {})
		check("it landed at once", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("nothing was put up", stack_count() == 0, stack_count())
	end)
end

-- Answering it. The counter cancels the cast, so the spell is spent without ever
-- doing what it said.
function M.test_emits_the_deferred_play_can_be_cancelled(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local fc = give("two", "flame_counter")

		flow.play_card(fb.id, {})
		flow.react(fc.id, 1, {})
		check("the spell never landed", seat("one").stats.landed == 0, seat("one").stats.landed)
		-- Spent, not destroyed. The stack never held the card, so being countered
		-- did not have to put it anywhere — its own "spent" already said.
		check("and is spent", entity.get(fb.id).zone_id == table_of("one").id)
		check("the stack cleared", stack_count() == 0, stack_count())
		check("priority went back to the turn", zones.active_seat() == "one", zones.active_seat())
	end)
end

-- Declining lets it through, which is the other half of a window meaning
-- anything at all.
function M.test_emits_passing_lets_the_deferred_play_land(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		give("two", "flame_counter")

		flow.play_card(fb.id, {})
		flow.pass_react()
		check("it landed after the pass", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("the stack is empty", stack_count() == 0, stack_count())
	end)
end

-- Priority lets the answering seat act out of turn, and that is *all* it lets
-- them do. The unlock is deliberately narrow: "reactions" is ravel's only
-- spelling for a card played out of turn, so a plain card in the same hand stays
-- refused — otherwise moving priority would hand the reactor a free turn inside
-- the other player's.
function M.test_emits_a_window_unlocks_answering_and_nothing_else(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local fc = give("two", "flame_counter")
		local dg = give("two", "dagger")

		flow.play_card(fb.id, {})
		check("the answering seat is up", zones.active_seat() == "two", zones.active_seat())
		check("but an ordinary card of theirs is not playable", not flow.can_play(dg.id))
		check("and playing it is refused outright", flow.play_card(dg.id, {}) == false)
		check("nothing of theirs landed", seat("two").stats.landed == 0, seat("two").stats.landed)
		check("while answering still works", flow.react(fc.id, 1, {}))
		check("and the spell was cancelled", seat("one").stats.landed == 0, seat("one").stats.landed)
	end)
end

-- The prompt must not be evidence. A hand and the bag behind it are the same
-- place from across the table, so a counter sitting in the bag opens the window
-- exactly as one in hand does: the engine knows which, the opponent does not, and
-- if the *appearance* of a window were driven by a hidden hand the window would
-- announce what is in it. The cost is a pass now and then.
function M.test_emits_a_hidden_counter_still_opens_the_window(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local fc = zones.add(bag_of("two"), "flame_counter")

		flow.play_card(fb.id, {})
		check("the defender is asked", zones.active_seat() == "two", zones.active_seat())
		check("even though the counter is in their bag",
			entity.get(fc.id).zone_id == bag_of("two").id)
		-- Asked, and with nothing to answer: they can see their own hand, so what
		-- they are *offered* is the truth even when the question was a guess.
		check("but nothing is on offer", #flow.usable_reactions() == 0, #flow.usable_reactions())
		check("and reaching for it anyway is refused", flow.react(fc.id, 1, {}) == false)
		flow.pass_react()
		check("passing lets the spell land", seat("one").stats.landed == 1, seat("one").stats.landed)
	end)
end

-- A public zone is not a guess. The table is face up, so nobody has to be asked
-- about a counter lying there — and this is why the loose reading needs no
-- setting to switch off: a game that hides nothing gets the exact one for free.
function M.test_emits_a_counter_in_a_public_zone_is_read_exactly(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		zones.add(table_of("two"), "flame_counter")

		flow.play_card(fb.id, {})
		check("nothing was asked", stack_count() == 0, stack_count())
		check("the spell landed", seat("one").stats.landed == 1, seat("one").stats.landed)
	end)
end

-- "mandatory" is not "may": it fires on its own, nobody is asked, and the seat that
-- holds it never gets priority to decide. The whole of Magic's mandatory
-- triggered ability, and the reason the field is an enum.
function M.test_emits_a_forced_reaction_fires_unasked(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local wd = give("two", "ward")

		flow.play_card(fb.id, {})
		check("nobody was asked", zones.active_seat() == "one", zones.active_seat())
		check("the spell never landed", seat("one").stats.landed == 0, seat("one").stats.landed)
		check("the ward is spent", entity.get(wd.id).zone_id == table_of("two").id)
		check("and the stack cleared itself", stack_count() == 0, stack_count())
	end)
end

-- One card, two ways to answer with it. A bare click cannot mean either, so the
-- card stops being the question and the chooser becomes it — the same offer an
-- ability with two uses opens, because a reaction is an ability with a
-- subscription on the front.
function M.test_emits_a_card_answering_two_ways_is_asked_which(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		local pr = give("two", "prism")

		flow.play_card(fb.id, {})
		check("both ways are on offer", #flow.usable_reactions() == 2, #flow.usable_reactions())
		check("so a bare click means neither", flow.sole_reaction(pr.id) == nil)
		check("and the chooser opens", flow.offer_reactions(pr.id))

		local entries = zones.find("options").cards
		check("with one entry each", #entries == 2, #entries)
		local pick = flow.menu_choice(entries[2])
		check("and the second entry is the second reaction",
			pick ~= nil and pick.reaction ~= nil and pick.index == 2)
		flow.close_offer()
		check("answering that way works", flow.react(pick.source, pick.index, {}))
		check("it took one rather than denying", seat("two").stats.landed == 1,
			seat("two").stats.landed)
		check("so the spell still landed", seat("one").stats.landed == 1, seat("one").stats.landed)
	end)
end

-- Only the other seat is asked. Holding the answer yourself is not a window: it
-- would open one that finds nobody to hold it and closes again.
function M.test_emits_your_own_answer_opens_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local fb = give("one", "fireball")
		give("one", "flame_counter")

		flow.play_card(fb.id, {})
		check("it landed at once", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("nothing was put up", stack_count() == 0, stack_count())
	end)
end

-- The card that is two things. Played, it is a cast: the flame counter answers
-- it and the silence, which watches for an ability, does not.
function M.test_emits_the_play_moment_is_asked_on_play(check)
	with_game(function(name)
		flow.init(name, 3)
		local al = give("one", "altar")
		give("two", "silence")

		flow.play_card(al.id, {})
		check("silence does not answer a cast", stack_count() == 0, stack_count())
		check("so the altar reached the board",
			entity.get(al.id).zone_id == zones.find_id("board"))
		check("and the turn seat is still acting", zones.active_seat() == "one")
	end)
end

-- What resolves is a card, and a card that put itself somewhere is there. The
-- stack unmakes only what is still lying on it when the action is done: a spell
-- that says nothing about where it goes is spent, and one whose own action moved
-- it to the board has already answered the question. Destroying either way ate
-- every card whose play ends "move_to", which in Puzzle Strike is most of them.
function M.test_emits_a_resolved_card_goes_where_its_action_put_it(check)
	with_game(function(name)
		flow.init(name, 3)
		local al = give("one", "altar")
		give("two", "flame_counter")

		flow.play_card(al.id, {})
		check("it was put up to be answered", stack_count() == 1, stack_count())
		flow.pass_react()
		check("and resolving left it on the board",
			entity.get(al.id) ~= nil and entity.get(al.id).zone_id == zones.find_id("board"))
		check("with the stack empty behind it", stack_count() == 0, stack_count())
	end)
end

-- The same card, used where it now lies. That is the other moment, so the other
-- reaction answers — and what goes up is the *effect*: the altar stays on the
-- board, because it was not played, only used.
function M.test_emits_the_activate_moment_is_asked_on_use(check)
	with_game(function(name)
		flow.init(name, 3)
		local al = give("one", "altar")
		flow.play_card(al.id, {})
		local sl = give("two", "silence")

		flow.activate(al.id, {}, 1)
		check("using it is waiting to be answered", stack_count() == 1, stack_count())
		check("and has done nothing yet", seat("one").stats.landed == 0, seat("one").stats.landed)
		check("the altar is still on the board",
			entity.get(al.id).zone_id == zones.find_id("board"))
		check("the other seat holds priority", zones.active_seat() == "two", zones.active_seat())

		flow.react(sl.id, 1, {})
		check("silenced, so the ability never ran", seat("one").stats.landed == 0,
			seat("one").stats.landed)
		check("the altar survived being silenced",
			entity.get(al.id) ~= nil and entity.get(al.id).zone_id == zones.find_id("board"))
		check("the stack cleared", stack_count() == 0, stack_count())
	end)
end

-- And with nobody watching for an ability, using it is the plain activation it
-- has always been.
function M.test_emits_an_unanswered_ability_runs_at_once(check)
	with_game(function(name)
		flow.init(name, 3)
		local al = give("one", "altar")
		flow.play_card(al.id, {})

		flow.activate(al.id, {}, 1)
		check("it ran immediately", seat("one").stats.landed == 1, seat("one").stats.landed)
		check("nothing was put up", stack_count() == 0, stack_count())
	end)
end

-- An emit from inside an action: the gem is played, announces a crash, and the
-- part written after the verb is what waits. The subject is the acting card, so
-- the reaction reads the gem's own tags.
function M.test_emits_an_action_raises_its_own_event(check)
	with_game(function(name)
		flow.init(name, 3)
		local gm = give("one", "gem")
		give("two", "crash_counter")

		flow.play_card(gm.id, {})
		check("the crash is waiting to be answered", stack_count() == 1, stack_count())
		check("and has not happened", seat("one").stats.crashed == 0, seat("one").stats.crashed)
		check("the other seat holds priority", zones.active_seat() == "two", zones.active_seat())
		check("the gem itself is not on the stack — the event stands for it",
			entity.get(gm.id).zone_id ~= zones.find_id("stack"))
	end)
end

-- Cancelling an emitted event. What comes off is the entry, not the subject: the
-- gem is still there and the crash simply did not happen.
function M.test_emits_an_emitted_event_can_be_cancelled(check)
	with_game(function(name)
		flow.init(name, 3)
		local gm = give("one", "gem")
		local cc = give("two", "crash_counter")

		flow.play_card(gm.id, {})
		flow.react(cc.id, 1, {})
		check("the crash never happened", seat("one").stats.crashed == 0, seat("one").stats.crashed)
		check("the gem survived it", entity.get(gm.id) ~= nil and entity.get(gm.id).zone_id ~= nil)
		check("the stack cleared", stack_count() == 0, stack_count())
		check("the turn seat is acting again", zones.active_seat() == "one", zones.active_seat())
	end)
end

-- Passing on an emitted event runs the part that was waiting, at the moment the
-- window closes rather than when it was written.
function M.test_emits_an_unanswered_emit_runs_what_waited(check)
	with_game(function(name)
		flow.init(name, 3)
		local gm = give("one", "gem")
		give("two", "crash_counter")

		flow.play_card(gm.id, {})
		flow.pass_react()
		check("the crash happened after the pass", seat("one").stats.crashed == 1,
			seat("one").stats.crashed)
		check("the stack is empty", stack_count() == 0, stack_count())
	end)
end

-- And with nobody able to answer a crash, "emit" is not there at all: the tail
-- runs in place, in the same action list, with no stack entry in between.
function M.test_emits_an_unanswerable_emit_runs_in_place(check)
	with_game(function(name)
		flow.init(name, 3)
		local gm = give("one", "gem")

		flow.play_card(gm.id, {})
		check("the crash happened immediately", seat("one").stats.crashed == 1,
			seat("one").stats.crashed)
		check("nothing was put up", stack_count() == 0, stack_count())
	end)
end

return M
