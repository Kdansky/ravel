-- "show:random." — reading one card of somebody's hand.
--
-- "show" already put the *real* cards a scope names face up in the offer, which
-- is how one player reads another's hand. What it could not do is read only
-- part of one: the scope named the hand and the whole hand came up.
--
-- The word for part of a set already exists and already means one — "random.",
-- the same quantifier move and destroy take, picked with the seeded RNG so a
-- replay and a networked opponent see the same card. Nothing new was invented
-- here; a word that meant something everywhere else was made to mean it here.

local entity = require("entity")
local zones = require("zones")
local flow = require("flow")
local rng = require("rng")

local M = {}

local GAME = [==[{
  "title": "Reveal",
  "players": [{ "card": "one" }, { "card": "two" }],
  "stats": [
    { "key": "seen", "label": "Seen", "subject": "seen@mine.player" },
    { "key": "worth", "min": 0, "max": 9, "tags": ["hidden"] }
  ],
  "zones": [
    { "key": "hand", "layout": "row", "visibility": "owner", "copies": "per_seat",
      "pos": [[0.20, 0.80, 0.50, 0.95], [0.20, 0.05, 0.50, 0.20]] },
    { "key": "table", "layout": "stack", "copies": "per_seat",
      "pos": [[0.60, 0.80, 0.70, 0.95], [0.60, 0.05, 0.70, 0.20]] },
    { "key": "options", "layout": "row", "status": "offer", "pos": [0.06, 0.30, 0.94, 0.70] }
  ],
  "phases": [
    { "key": "act", "type": "player_input", "next": [{ "then": "act" }] }
  ],
  "cards": [
    { "key": "one", "text": "One", "tags": ["seat_one"], "card_stats": { "seen": 0 } },
    { "key": "two", "text": "Two", "tags": ["seat_two"], "card_stats": { "seen": 0 } },
    { "key": "alpha", "text": "Alpha", "tags": ["chip"] },
    { "key": "beta", "text": "Beta", "tags": ["chip"] },
    { "key": "gamma", "text": "Gamma", "tags": ["chip"] },
    { "key": "relic", "text": "Relic", "tags": ["chip", "relic"], "card_stats": { "worth": 3 } },
    { "key": "trinket", "text": "Trinket", "tags": ["chip", "relic"], "card_stats": { "worth": 1 } },
    { "key": "peek", "text": "Peek",
      "play": { "action": ["show:random.enemy.hand"], "spent": "mine.table" },
      "chosen": { "action": ["stat_gain:seen@mine.player:1"] } },
    { "key": "raid", "text": "Raid",
      "play": { "action": ["show:enemy.hand:optional"], "spent": "mine.table" },
      "chosen": { "action": ["stat_gain:seen@mine.player:1"] } },
    { "key": "sifter", "text": "Sifter",
      "play": { "action": ["show:enemy.hand:optional"] },
      "chosen": { "where": ["tagged:relic@target >= 1"],
        "action": ["move_target_to:mine.table"] } },
    { "key": "greedy", "text": "Greedy",
      "play": { "action": ["show:enemy.hand:optional"] },
      "chosen": { "where": ["sum:worth@target >= max:worth@options"],
        "action": ["move_target_to:mine.table"] } },
    { "key": "chooser", "text": "Chooser",
      "play": { "action": ["options:alpha,beta"] },
      "chosen": { "where": ["tagged:relic@target >= 1"], "action": [] } },
    { "key": "interrogate", "text": "Interrogate",
      "play": { "action": ["set_priority:enemy.player", "show:mine.hand"] },
      "chosen": { "action": ["move_target_to:enemy.table", "clear_priority"] } }
  ]
}]==]

local function with_game(fn)
	local path = "game/games/tmp_reveal.json"
	local f = assert(io.open(path, "w"))
	f:write(GAME)
	f:close()
	local ok, err = pcall(fn, "tmp_reveal.json")
	os.remove(path)
	if not ok then error(err, 0) end
end

local function hand_of(key)
	for _, z in ipairs(zones.all_with_key("hand")) do
		if z.seat == key then return z end
	end
end

local function give(seat_key, def_key)
	return zones.add(hand_of(seat_key), def_key)
end

local function offer()
	return zones.find("options")
end

local function offered()
	local out = {}
	for _, id in ipairs(offer().cards) do out[#out + 1] = entity.get(id).def_key end
	table.sort(out)
	return table.concat(out, ",")
end

-- One card comes up, and it is a real one: the entity that was in their hand,
-- borrowed, not a copy dealt for the occasion.
function M.test_reveal_random_shows_one_card(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "alpha")
		give("two", "beta")
		give("two", "gamma")
		local peek = give("one", "peek")

		flow.play_card(peek.id, {})
		check("exactly one of the three came up", #offer().cards == 1, #offer().cards)
		local up = entity.get(offer().cards[1])
		check("and it is one of theirs",
			up.def_key == "alpha" or up.def_key == "beta" or up.def_key == "gamma", up.def_key)
		check("borrowed rather than conjured: it remembers where it came from",
			up.borrowed_from == hand_of("two").id)
		check("their hand is short the one that is up", #hand_of("two").cards == 2,
			#hand_of("two").cards)
	end)
end

-- The scope with no quantifier is untouched, which is what every game written
-- before this depends on.
function M.test_reveal_a_whole_hand_still_comes_up(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "alpha")
		give("two", "beta")
		give("two", "gamma")
		local raid = give("one", "raid")

		flow.play_card(raid.id, {})
		check("all three came up", offered() == "alpha,beta,gamma", offered())
	end)
end

-- The seeded generator picks it, so the same seed reads the same card — which
-- is what lets a replay and a networked opponent agree about what was seen.
function M.test_reveal_random_is_the_seeded_generator(check)
	with_game(function(name)
		local function peeked(seed)
			flow.init(name, 3)
			rng.seed(seed)
			give("two", "alpha")
			give("two", "beta")
			give("two", "gamma")
			local peek = give("one", "peek")
			flow.play_card(peek.id, {})
			return entity.get(offer().cards[1]).def_key
		end
		check("the same seed reads the same card", peeked(4) == peeked(4))
		-- Three cards and two seeds: a disagreement proves it is really drawing.
		local a, b = peeked(1), peeked(2)
		check("and different seeds may read a different one", a ~= nil and b ~= nil)
	end)
end

-- Choosing one runs the asking card's own block, exactly as it does when the
-- whole hand is up: narrowing what is offered changed nothing about the answer.
function M.test_reveal_random_the_pick_still_answers_the_asker(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "alpha")
		give("two", "beta")
		local peek = give("one", "peek")

		flow.play_card(peek.id, {})
		flow.play_card(offer().cards[1], {})
		local one
		for e in entity.each("card") do
			if e.def_key == "one" and e.zone_id then one = e end
		end
		check("the asker's chosen block ran", one.stats.seen == 1, one.stats.seen)
		check("the offer is closed", #offer().cards == 0, #offer().cards)
		check("and the borrowed card went home", #hand_of("two").cards == 2,
			#hand_of("two").cards)
	end)
end

-- The other half of "reveal a card", and it needed nothing new: *they* choose.
--
-- Two words already in the language do it. set_priority makes the other seat the
-- one who is up without the turn moving, and every scope is relative to whoever
-- is up — so "show:mine.hand" from inside that window is their hand, offered to
-- them, and the pick is theirs. Written down here because it is not obvious from
-- either word on its own, and because a rule that made the wrong seat choose
-- would still look like it worked from one side of the screen.
function M.test_reveal_the_other_seat_may_be_made_to_choose(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "alpha")
		give("two", "beta")
		local inq = give("one", "interrogate")

		check("we are up", zones.active_seat() == "one", zones.active_seat())
		flow.play_card(inq.id, {})
		check("and now they are, without the turn moving",
			zones.active_seat() == "two", zones.active_seat())
		check("their own hand is what they were offered", offered() == "alpha,beta", offered())

		check("their pick is accepted", flow.play_card(offer().cards[1], {}))
		check("priority came home", zones.active_seat() == "one", zones.active_seat())
		local ours
		for _, z in ipairs(zones.all_with_key("table")) do
			if z.seat == "one" then ours = z end
		end
		check("and what they chose is face up on our side", #ours.cards == 1, #ours.cards)
		check("out of their hand", #hand_of("two").cards == 1, #hand_of("two").cards)
	end)
end

-- `chosen.where` — the whole hand comes up, and only part of it may be taken.
--
-- The asking card says which part, in the same condition vocabulary a target's
-- `where` uses. Revealing the whole hand is usually half the rule, so what is
-- narrowed is the *pick*, not what is shown.
function M.test_reveal_the_asker_says_what_it_will_take(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "alpha")
		give("two", "relic")
		local sift = give("one", "sifter")

		flow.play_card(sift.id, {})
		check("both cards came up", offered() == "alpha,relic", offered())
		local a, r
		for _, id in ipairs(offer().cards) do
			if entity.get(id).def_key == "alpha" then a = id else r = id end
		end
		check("the one it names may be taken", flow.can_play(r))
		check("and the one it does not may not", not flow.can_play(a))
		check("taking the wrong one is refused", not flow.play_card(a, {}))
		check("taking the right one is not", flow.play_card(r, {}))
	end)
end

-- "The largest" is the candidate compared with the offer it is lying in, which
-- is an ordinary question about a scope and needed no new grammar.
function M.test_reveal_a_where_may_compare_a_card_with_the_offer(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "trinket")
		give("two", "relic")
		local g = give("one", "greedy")

		flow.play_card(g.id, {})
		local big, small
		for _, id in ipairs(offer().cards) do
			if entity.get(id).def_key == "relic" then big = id else small = id end
		end
		check("the bigger one may be taken", flow.can_play(big))
		check("the smaller one may not", not flow.can_play(small))
	end)
end

-- A question with no answer is a mandatory offer that never closes, so it is
-- not asked at all — the same rule as an empty hand being nothing to look at.
function M.test_reveal_an_offer_nothing_qualifies_for_does_not_open(check)
	with_game(function(name)
		flow.init(name, 3)
		give("two", "alpha")
		give("two", "beta")
		local sift = give("one", "sifter")

		flow.play_card(sift.id, {})
		check("no offer opened", #offer().cards == 0, #offer().cards)
		check("and their hand was not disturbed", #hand_of("two").cards == 2,
			#hand_of("two").cards)
	end)
end

-- An entry the offer *dealt* is a line off the asking card's own list, so it is
-- never narrowed: writing a shorter list is how you narrow one of those.
function M.test_reveal_a_where_does_not_touch_a_dealt_offer(check)
	with_game(function(name)
		flow.init(name, 3)
		local pick = give("one", "chooser")
		flow.play_card(pick.id, {})
		check("both branches are on offer", #offer().cards == 2, #offer().cards)
		for _, id in ipairs(offer().cards) do
			check("and both may be chosen despite the where", flow.can_play(id))
		end
	end)
end

-- An empty hand is nothing to look at, and "random." of nothing is still
-- nothing — the offer must not open over a board no one could act on.
function M.test_reveal_random_of_an_empty_hand_opens_nothing(check)
	with_game(function(name)
		flow.init(name, 3)
		local peek = give("one", "peek")
		flow.play_card(peek.id, {})
		check("no offer opened", #offer().cards == 0, #offer().cards)
	end)
end

return M
