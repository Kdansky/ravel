-- Spellstorm, and the four rules its battle is made of.
--
-- None of them is a new engine word, and each is the kind of thing a rules
-- summary cannot confirm. Countering is one condition read across two battle
-- zones. Resolution order is set_active_seat pointed at a computed tag, which
-- matters because "mine" inside a card's own effect means whoever is up, so a
-- card resolved under the wrong seat heals the wrong player. Blast Scoring is
-- a subtraction that has to clamp at zero rather than go negative. And the
-- Power Track is six tokens becoming a Tier, which is the only arithmetic in
-- the game the action grammar cannot say in one line.

local declaration = require("declaration")
local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")
local predicate = require("predicate")

local M = {}

local function seat_card(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if seat == nil or z.seat == seat then return z end
	end
end

local function find(def_key, zone_key)
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if e.def_key == def_key and z and (zone_key == nil or z.key == zone_key) then
			return e
		end
	end
end

-- Start a game and pick the two wizards named, in seat order. Everything below
-- runs after this, because nothing about a seat exists until it is chosen.
local function opening(seed, one, two)
	flow.init("spellstorm.json", seed)
	for _, name in ipairs({ one, two }) do
		local picked = false
		for _, id in ipairs(zones.find("options").cards) do
			if entity.get(id).def_key == "pick_" .. name then
				flow.play_card(id, {})
				picked = true
				break
			end
		end
		assert(picked, "no such wizard in the offer: " .. name)
	end
	-- The weather may ask before anybody plays: Falling Star offers the Storm
	-- Cloud to each seat in turn, and those offers are waiting when the round
	-- opens. A test that wants the start of play declines them; the one that is
	-- about Falling Star drives it itself.
	while phase.current().key == "options" and flow.dismiss_offer() do end
end

-- Put one named card into a seat's battle spot, whatever it was holding.
local function stage_battle(seat, def_key)
	local b = zone_of("battle", seat)
	for _, id in ipairs({ unpack(b.cards) }) do
		zones.move_card(id, zone_of("discard", seat).id)
	end
	local e = find(def_key)
	assert(e, "no " .. def_key .. " anywhere to stage")
	zones.move_card(e.id, b.id)
	-- A starting card was dealt into a seat's deck and carries that seat, so one
	-- lifted out of the wrong deck would still read as theirs and "enemy.battle"
	-- would not see it. Hand it to the spot it is now standing in.
	e.stats.owner = nil
	return e
end

local function hand_of(seat) return zone_of("hand", seat) end

-- Put a named seat up. The seat cards carry no tag naming themselves, so there
-- is nothing for set_active_seat to point at; handing over until the right one
-- is up says the same thing with the words the game has.
local function become(seat)
	for _ = 1, 4 do
		if zones.active_seat() == seat then return end
		actions.execute("set_active_seat:enemy.player", {})
	end
	assert(zones.active_seat() == seat, "cannot make " .. seat .. " the active seat")
end

-- A Research Token on every journal space. The token is a flag on the space
-- itself now, not a threshold on a counter, so lighting one is naming it.
local function research(...)
	local which = { ... }
	if #which == 0 then for n = 1, 8 do which[n] = n end end
	for _, n in ipairs(which) do
		find("r_journal_" .. n).stats.researched = 1
	end
end

local function empty_hand(seat)
	local h = hand_of(seat)
	for _, id in ipairs({ unpack(h.cards) }) do
		zones.move_card(id, zone_of("deck", seat).id)
	end
end


-- "Resolve that card" means the card, not the first line of it.
--
-- `copy` used to run ability one and stop, which quietly dropped every rider
-- with an if in it and every question the card asks -- and a card that asks
-- keeps the asking in a later ability, so the offer opens after the rest of the
-- resolution has run. A copied Lapis drew and never offered its discard.
function M.test_spellstorm_a_copied_card_asks_what_it_would_have_asked(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	local lapis = stage_battle(one, "lapis")

	local keys = {}
	for _, a in ipairs(require("cards").abilities(lapis)) do keys[#keys + 1] = a.key end
	check("Lapis keeps its asking in a later ability, after the drawing",
		table.concat(keys, ",") == "cast,cast_ask", table.concat(keys, ","))

	local deck = #zone_of("deck", one).cards
	actions.execute("copy:target:activate", { card_id = lapis.id, targets = { lapis.id } })
	check("copying it drew, which is the deterministic half",
		#zone_of("deck", one).cards == deck - 1, #zone_of("deck", one).cards)
	check("and opened the question the card asks, which is the other half",
		phase.current().key == "options", phase.current().key)
	check("with the hand in it to choose from", #zones.find("options").cards > 0,
		#zones.find("options").cards)
end

-- The other half of the same rule: a discard effect is *not* part of resolving.
-- It is not an ability at all -- an ability is something the card does, and
-- every rule that runs abilities would then run this one. It is a `leaves`,
-- triggered by the card going from a hand to a discard, so no rule about
-- resolving has to know it exists and no card has to carry a condition saying
-- so on the off chance somebody copies it.
function M.test_spellstorm_a_copy_does_not_fire_a_discard_effect(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local seat = seat_card(one)

	-- Heart Gem heals 3 when resolved and costs 1 health when discarded, so the
	-- two halves pull opposite ways and the number tells which ran. Room to heal
	-- into first, or a full wizard hides the heal behind the cap.
	seat.stats.health = seat.stats.health - 5
	local hp = seat.stats.health
	local hg = stage_battle(one, "heartgem")
	actions.execute("copy:target:activate", { card_id = hg.id, targets = { hg.id } })
	check("the copy healed 3, so its cast ran", seat.stats.health == hp + 3,
		seat.stats.health .. " from " .. hp)

	-- And the same card, discarded out of the hand, pays the 1 it is printed
	-- with. Same card, same effect, and nothing about it says "unless".
	zones.move_card(hg.id, hand_of(one).id)
	hp = seat.stats.health
	zones.move_card(hg.id, zone_of("discard", one).id)
	check("discarded from hand, it costs the 1", seat.stats.health == hp - 1,
		seat.stats.health .. " from " .. hp)
end

-- VOIDing is not discarding, which the rulebook says once and the card now says
-- not at all: "into" already names the only landing that counts.
function M.test_spellstorm_voiding_a_card_is_not_discarding_it(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local seat = seat_card(one)
	seat.stats.health = seat.stats.health - 5

	local hg = find("heartgem")
	zones.move_card(hg.id, hand_of(one).id)
	local hp = seat.stats.health
	zones.move_card(hg.id, zones.find_id("void"))
	check("voided out of the hand, it costs nothing", seat.stats.health == hp,
		seat.stats.health .. " from " .. hp)
end

function M.test_spellstorm_the_box_is_the_published_one(check)
	flow.init("spellstorm.json", 1)
	local defs = require("declaration").G.card_defs
	local n = { wizard_card = 0, wizard_spell = 0, dragon = 0, weather = 0, essence = 0 }
	for _, def in pairs(defs) do
		for kind in pairs(n) do
			if (def.tags_set or {})[kind] then n[kind] = n[kind] + 1 end
		end
	end
	check("eight wizards", n.wizard_card == 8, tostring(n.wizard_card))
	check("two Wizard Spell Cards each", n.wizard_spell == 16, tostring(n.wizard_spell))
	check("five Dragons", n.dragon == 5, tostring(n.dragon))
	check("three Essence cards", n.essence == 3, tostring(n.essence))
	-- Nineteen designs rather than twenty-four cards: the print run doubles up
	-- four of the standard weather and one of the calm.
	check("nineteen weather designs", n.weather == 19, tostring(n.weather))

	-- The Essences start on the shelf, which is what the setup page says, and
	-- the shelf is filled to five from the deck before anybody acts.
	check("the Storm Cloud holds five", #zones.find("storm_cloud").cards == 5,
		tostring(#zones.find("storm_cloud").cards))
	local essences = 0
	for _, id in ipairs(zones.find("storm_cloud").cards) do
		if (entity.get(id).def_key or ""):find("essence$") then essences = essences + 1 end
	end
	check("three of them are the Essences", essences == 3, tostring(essences))

	-- Six ICE, six ASH, six CURSE. They are real stacks rather than a supply,
	-- so a pile that runs out really has run out.
	for _, k in ipairs({ "ice", "ash", "curse" }) do
		check("six " .. k, #zones.find(k .. "_pile").cards == 6,
			tostring(#zones.find(k .. "_pile").cards))
	end
end


function M.test_spellstorm_a_wizard_configures_the_seat(check)
	opening(5, "derby", "croh")
	local one, two = seat_card("seat_one"), seat_card("seat_two")
	check("Derby starts on 13 health", one.stats.health == 13, tostring(one.stats.health))
	check("Croh starts on 20", two.stats.health == 20, tostring(two.stats.health))

	-- Healing may not pass the wizard's starting health, and the ceiling is the
	-- only thing saying so -- a heal is written the same on every card.
	actions.execute("set_active_seat:seat_one", {})
	actions.execute("stat_gain:health@mine.player:10", {})
	check("Derby cannot heal past 13", one.stats.health == 13, tostring(one.stats.health))

	-- The lower Initiative rating begins with the tracker: Derby is 3, Croh 8.
	check("Derby holds the Initiative Tracker", one.stats.initiative == 1,
		tostring(one.stats.initiative))
	check("and Croh does not", two.stats.initiative == 0, tostring(two.stats.initiative))
	check("exactly one tracker exists",
		one.stats.initiative + two.stats.initiative == 1)

	-- Both wizards' spell cards are shuffled into their own starting deck, and
	-- neither is holding the other's.
	local mine = 0
	for _, where in ipairs({ "deck", "hand", "discard" }) do
		for _, id in ipairs(zone_of(where, "seat_one").cards) do
			local d = require("declaration").G.card_defs[entity.get(id).def_key]
			if (d.tags_set or {}).wizard_spell then mine = mine + 1 end
		end
	end
	check("Derby's two Wizard Spell Cards are shuffled into his own deck",
		mine == 2, tostring(mine))
end


function M.test_spellstorm_countering_draws_a_card(check)
	opening(5, "derby", "eve")
	-- Fire beats Earth, Earth beats Water, Water beats Fire. Countering the
	-- opponent draws you a card; being countered draws you nothing.
	local trials = {
		{ "fireball",   "twopower",   1, 0, "Fire counters Earth" },
		{ "twopower",   "block",      1, 0, "Earth counters Water" },
		{ "block",      "fireball",   1, 0, "Water counters Fire" },
		{ "fireball",   "magicdart",  0, 0, "Fire against Fire counters neither" },
	}
	for _, t in ipairs(trials) do
		local mine, theirs, want_one, want_two, why = t[1], t[2], t[3], t[4], t[5]
		stage_battle("seat_one", mine)
		stage_battle("seat_two", theirs)
		local h1, h2 = #hand_of("seat_one").cards, #hand_of("seat_two").cards
		actions.execute("each_seat:activate_zone:rules:by_column:check", {})
		check(why, #hand_of("seat_one").cards - h1 == want_one
			and #hand_of("seat_two").cards - h2 == want_two,
			("%+d / %+d"):format(#hand_of("seat_one").cards - h1,
				#hand_of("seat_two").cards - h2))
	end
end


function M.test_spellstorm_cards_resolve_in_initiative_order(check)
	opening(5, "derby", "eve")
	local one, two = seat_card("seat_one"), seat_card("seat_two")

	-- The whole reason resolution order is set by set_active_seat rather than
	-- walked both battle zones in turn: "mine" inside a card's own effect means
	-- whoever is up, so a card resolved under the wrong seat pays the wrong
	-- player. Magic Dart gains its caster a mana; run the pair and check the
	-- mana landed on the seat that played it.
	stage_battle("seat_two", "magicdart")
	stage_battle("seat_one", "sapphire")
	local m1, m2 = one.stats.mana, two.stats.mana
	local hp1 = one.stats.health

	actions.execute("set_active_seat:has_init", {})
	check("the seat with Initiative resolves first",
		zones.active_seat() == "seat_one", tostring(zones.active_seat()))
	actions.execute("activate_zone:mine.battle:by_column:cast", {})
	check("Sapphire's mana did not move", one.stats.mana == m1)
	actions.execute("set_active_seat:enemy.player", {})
	check("then the other seat", zones.active_seat() == "seat_two",
		tostring(zones.active_seat()))
	actions.execute("activate_zone:mine.battle:by_column:cast", {})
	check("Magic Dart's mana went to the seat that played it",
		two.stats.mana == m2 + 1 and one.stats.mana == m1,
		("%d / %d"):format(one.stats.mana, two.stats.mana))
	check("and Derby took no damage from it, having Initiative himself",
		one.stats.health == hp1, tostring(one.stats.health))
end


function M.test_spellstorm_blast_scoring(check)
	opening(5, "derby", "eve")
	local one, two = seat_card("seat_one"), seat_card("seat_two")

	-- The single highest Blast Score takes two Shards; a tie takes one each.
	local function score(a, b)
		empty_hand("seat_one"); empty_hand("seat_two")
		for i = 1, a do
			zones.move_card(find("moonstone", "spellstorm_deck")
				and find("moonstone", "spellstorm_deck").id
				or zone_of("deck", "seat_one").cards[1], hand_of("seat_one").id)
		end
		for i = 1, b do
			zones.move_card(zone_of("deck", "seat_two").cards[1], hand_of("seat_two").id)
		end
		actions.execute("each_seat:stat_set:ice_pen@mine.player:0", {})
		actions.execute("each_seat:activate_zone:rules:by_column:score", {})
		actions.execute("each_seat:activate_zone:rules:by_column:award_win", {})
		actions.execute("each_seat:activate_zone:rules:by_column:award_tie", {})
	end

	local s1, s2 = one.stats.shards, two.stats.shards
	score(3, 1)
	check("the higher Blast Score takes two Storm Shards",
		one.stats.shards == s1 + 2 and two.stats.shards == s2,
		("%d / %d"):format(one.stats.shards - s1, two.stats.shards - s2))

	s1, s2 = one.stats.shards, two.stats.shards
	score(2, 2)
	check("a tie takes one each",
		one.stats.shards == s1 + 1 and two.stats.shards == s2 + 1,
		("%d / %d"):format(one.stats.shards - s1, two.stats.shards - s2))

	-- Each ICE discarded in Regroup is -1, and a Blast Score never goes below
	-- nothing -- the stat's floor is what does the clamping.
	empty_hand("seat_one"); empty_hand("seat_two")
	zones.move_card(zone_of("deck", "seat_one").cards[1], hand_of("seat_one").id)
	actions.execute("set_active_seat:seat_one", {})
	actions.execute("stat_set:ice_pen@mine.player:5", {})
	actions.execute("activate_zone:rules:by_column:score", {})
	check("five ICE against one card is a Blast Score of nothing, not minus four",
		one.stats.blast == 0, tostring(one.stats.blast))
end


function M.test_spellstorm_the_power_track_becomes_a_tier(check)
	opening(5, "derby", "eve")
	local one = seat_card("seat_one")
	actions.execute("set_active_seat:seat_one", {})

	check("everyone starts at Tier I", one.stats.tier == 1, tostring(one.stats.tier))
	actions.execute("stat_set:power@mine.player:5", {})
	actions.execute("activate_zone:rules:by_column:tier_up", {})
	check("five tokens is not a Tier", one.stats.tier == 1 and one.stats.power == 5)

	-- Six fills the track: the Tier goes up and the six go back to the supply.
	-- The overflow is kept, which is why this is a subtraction and not a reset.
	actions.execute("stat_set:power@mine.player:8", {})
	actions.execute("activate_zone:rules:by_column:tier_up", {})
	check("a filled track is a Tier", one.stats.tier == 2, tostring(one.stats.tier))
	check("and the two spare tokens stay on it", one.stats.power == 2,
		tostring(one.stats.power))

	-- At Tier III a filled track is a Dragon instead.
	actions.execute("stat_set:tier@mine.player:3", {})
	actions.execute("stat_set:power@mine.player:6", {})
	local before = #hand_of("seat_one").cards
	actions.execute("activate_zone:rules:by_column:tier_gem", {})
	check("at Tier III a filled track gains a Dragon",
		#hand_of("seat_one").cards == before + 1, tostring(#hand_of("seat_one").cards - before))
	check("and the Tier does not go past III", one.stats.tier == 3, tostring(one.stats.tier))
	local top = entity.get(hand_of("seat_one").cards[#hand_of("seat_one").cards])
	check("what arrived is a Dragon",
		(require("declaration").G.card_defs[top.def_key].tags_set or {}).dragon == true,
		top.def_key)
end


function M.test_spellstorm_the_shelf_is_gated_by_tier(check)
	opening(5, "derby", "eve")
	actions.execute("set_active_seat:seat_one", {})
	-- Fireball II is Tier III. A Tier I wizard may look at it and not take it.
	local sc = zones.find("storm_cloud")
	for _, id in ipairs({ unpack(sc.cards) }) do
		zones.move_card(id, zones.find_id("spellstorm_deck"))
	end
	zones.move_card(find("fireball2").id, sc.id)
	zones.move_card(find("fireball").id, sc.id)
	local high, low = find("fireball2", "storm_cloud"), find("fireball", "storm_cloud")
	-- Taking a card off the shelf is an ability, and its "needs" is the Tier gate.
	phase.push("gain")
	check("a Tier III card is out of reach at Tier I", not flow.can_activate(high.id))
	check("a Tier I card is not", flow.can_activate(low.id))
	actions.execute("stat_set:tier@mine.player:3", {})
	check("and at Tier III it is", flow.can_activate(high.id))

	-- ICE cannot be played out of a hand, ever -- it carries no play block at
	-- all, which is the whole of "this can't be played".
	local ice = zones.find("ice_pile").cards[1]
	zones.move_card(ice, hand_of("seat_one").id)
	check("ICE cannot be played from a hand", not flow.can_play(ice))
end


-- The face-down half of a simultaneous reveal. Worth its own test because it is
-- the one rule here that no action performs: a card is unreadable because of
-- where it lies, so the only proof is to ask the renderer's own question.
--
-- Asked through `as_seat` rather than by reading the turn, because that is what
-- the two cases really are: over the wire each client answers as the seat it
-- claimed, and in hot-seat the seat to play answers for the screen. One
-- function, both readings.
function M.test_spellstorm_a_played_card_is_face_down_until_the_showdown(check)
	opening(11, "derby", "eve")
	check("a round opens with the first seat playing", phase.current().key == "play_card",
		phase.current().key)

	local one = zones.active_seat()
	local played
	for _, id in ipairs(hand_of(one).cards) do
		if flow.can_play(id) then played = id; flow.play_card(id, {}); break end
	end
	assert(played, "seat one had nothing playable")
	local card = entity.get(played)

	check("the card went to the commit spot, not the battle spot",
		zone_of("commit", one).cards[1] == played,
		tostring(#zone_of("battle", one).cards))

	local mine, theirs
	zones.as_seat(one, function() mine = zones.visible(card) end)
	check("its own seat may read it", mine)

	-- The turn has passed by now, which is the whole of the question: the second
	-- player is choosing, and this is what they are choosing against.
	local two = zones.active_seat()
	-- One phase key now, taken twice: what says the turn has passed is the seat,
	-- which is the thing the rule was ever about.
	check("the second seat is up", two ~= one and phase.current().key == "play_card",
		phase.current().key)
	zones.as_seat(two, function()
		theirs = zones.visible(card)
		check("nor may they look inside the zone holding it",
			not zones.peekable(zone_of("commit", one)))
	end)
	check("and the second seat cannot read the first card", not theirs)

	for _, id in ipairs(hand_of(two).cards) do
		if flow.can_play(id) then flow.play_card(id, {}); break end
	end

	-- Both cards down, and the rest of the round runs itself: showdown reveals,
	-- the two resolve steps fire, and round_end sweeps the battle spots into the
	-- discards. So the card is not caught standing in the battle zone -- what is
	-- worth checking is that it left the face-down zone and became readable.
	check("the commit spot is empty again", #zone_of("commit", one).cards == 0,
		tostring(#zone_of("commit", one).cards))
	zones.as_seat(two, function() theirs = zones.visible(card) end)
	check("and the card is in the open once the round has run", theirs)

	-- The reveal itself, pinned on its own: the showdown's first action is what
	-- turns the cards over, and everything after it reads `battle`.
	local staged = stage_battle(one, "magicdart")
	zones.move_card(staged.id, zone_of("commit", one).id)
	actions.execute("each_seat:move:mine.commit:mine.battle", {})
	check("the showdown's move is what puts a card in the battle spot",
		zone_of("battle", one).cards[1] == staged.id,
		tostring(#zone_of("commit", one).cards))
end

-- **Omar's Shuriken (Water).** *"**SPECIAL: this card ALWAYS goes first.** Gain
-- `[INIT]`. `[DRAW]` OR chosen opponent discards their revealed card (it does not
-- resolve) and they `[DRAW]`. `[ULT]`."*
--
-- **The duel already takes its order off a stat, so the card is a second stat and
-- not a second rule.** `lead` is written at the reveal -- where what was played is
-- known and the group that reads it has not been entered yet -- and a revealed
-- Shuriken outweighs the Tracker by more than the Tracker can ever be worth.
function M.test_spellstorm_shuriken_goes_first_whoever_holds_the_tracker(check)
	local function resolves_first(played)
		opening(3, "omar", "eve")
		-- The Tracker is the *other* seat's, which is the whole of the question.
		seat_card("seat_one").stats.initiative = 0
		seat_card("seat_two").stats.initiative = 1
		stage_battle("seat_one", played)
		stage_battle("seat_two", "magicdart")
		actions.execute("each_seat:stat_set:lead@mine.player:sum:initiative@mine.player", {})
		actions.execute("each_seat:activate_zone:rules:by_column:first_strike", {})
		phase.push("duel")
		-- The group picks its order on entry; handing the seat over is the next
		-- step the flow takes, which is what settling runs.
		flow.settle()
		return zones.active_seat()
	end

	check("the Tracker says who resolves first",
		resolves_first("magicdart") == "seat_two", resolves_first("magicdart"))
	check("and a revealed Shuriken goes first without it",
		resolves_first("omar_shuriken") == "seat_one", resolves_first("omar_shuriken"))
end

-- The other half of the card, and the half that needed nothing at all: **"it does
-- not resolve" is what going first already means.** Shuriken takes the card out of
-- the battle spot, and the seat that played it is not up yet -- so when it is, the
-- zone its resolution walks has nothing in it.
function M.test_spellstorm_shuriken_knocks_a_card_out_before_it_resolves(check)
	opening(3, "omar", "eve")
	local shuriken = stage_battle("seat_one", "omar_shuriken")
	local theirs = stage_battle("seat_two", "fireball2")
	local me = seat_card("seat_one")
	local hp, cards = me.stats.health, #hand_of("seat_two").cards

	become("seat_one")
	-- The ask is split out of the cast and run last, which is what keeps every
	-- rider on the card from reading a hand that has been lent to a question.
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = shuriken.id })
	check("the card offers its two branches, and neither of them is nothing",
		phase.current().key == "options" and #zones.find("options").cards == 2,
		phase.current().key .. " " .. #zones.find("options").cards)

	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == "shuriken_strike" then flow.play_card(id, {}) end
	end
	check("their revealed card is in their discard",
		entity.get(theirs.zone_id).key == "discard",
		entity.get(theirs.zone_id).key)
	check("and they drew for it", #hand_of("seat_two").cards == cards + 1,
		#hand_of("seat_two").cards)

	-- Their resolve step, run against a battle spot the Shuriken emptied.
	become("seat_two")
	actions.execute("activate_zone:mine.battle:by_column:cast", {})
	check("and the fireball never went off", me.stats.health == hp, me.stats.health)
end

-- **Glittering Dust (Weather).** *"`[DRAW]` `[DRAW]`. `[EARTH]` cards do nothing
-- when resolved but Heal 2."*
--
-- **"Does nothing when resolved" is said by not being there to do it.** The step
-- runs at the top of every resolution, ahead of the four cast columns, and takes
-- the Earth card where the round would have sent it anyway. Nothing is written on
-- any Earth card, which is the whole point: a weather card that rewrote every
-- Earth card would want rewriting every time one was printed.
function M.test_spellstorm_glittering_dust_replaces_what_an_earth_card_does(check)
	local function resolve(weather_key, played)
		opening(5, "derby", "eve")
		local card = stage_battle("seat_one", played)
		actions.execute("move:weather_now:weather_discard", {})
		zones.move_card(find(weather_key).id, zones.find("weather_now").id)
		become("seat_one")
		local me = seat_card("seat_one")
		me.stats.health = 8
		local power = me.stats.power
		actions.execute("activate_zone:rules:by_column:dust", {})
		actions.execute("activate_zone:mine.battle:by_column:cast", {})
		return me.stats.health, me.stats.power - power, entity.get(card.zone_id).key
	end

	local hp, gained, where = resolve("gemlightomen", "powergem")
	check("under any other weather the gem powers up", gained == 1, gained)
	check("and it is still standing in the battle spot", where == "battle", where)
	check("and nobody healed", hp == 8, hp)

	hp, gained, where = resolve("glitteringdust", "powergem")
	check("under the Dust it heals 2 instead", hp == 10, hp)
	check("and does nothing", gained == 0, gained)
	check("because it is not there to do it", where == "discard", where)

	-- Only Earth. The Dust names an element, and a Fire card is a Fire card.
	hp, gained, where = resolve("glitteringdust", "fireball2")
	check("a card of another element resolves as it always did",
		where == "battle" and hp == 8, where .. " " .. hp)
end

function M.test_spellstorm_a_battle_is_four_rounds_then_a_regroup(check)
	opening(7, "derby", "eve")
	-- Play the first playable card each time it is asked, take the first thing
	-- offered, and watch the shape of a battle rather than its content.
	local seen, guard, asked = {}, 0, 0
	while guard < 400 do
		guard = guard + 1
		local p = phase.current().key
		seen[p] = (seen[p] or 0) + 1
		if p == "reveal" then break end
		if flow.pending_event() then asked = asked + 1 end
		-- A card carrying the Ultimate icon has announced itself and the round
		-- waits on an answer. This driver casts no Ultimates, so it declines --
		-- which is the other half of a window and has to be reachable, or the
		-- resolution behind it never runs.
		if flow.pending_event() and phase.depth() <= 1 then
			if not flow.pass_react() then break end
		elseif p:find("^play") then
			local h, done = hand_of(zones.active_seat()), false
			for _, id in ipairs(h.cards) do
				if flow.can_play(id) then flow.play_card(id, {}); done = true; break end
			end
			if not done then
				-- A hand of nothing but ICE, ASH and CURSE. The board button is
				-- the rule for it, and a player has to press it.
				local btn
				for _, id in ipairs(zones.find("controls").cards) do
					if entity.get(id).def_key == "btn_unplayable" then btn = id end
				end
				if btn and flow.can_activate(btn) then flow.activate(btn, {}) else break end
			end
		elseif p:find("^gain") then
			local took = false
			for _, id in ipairs(zones.find("storm_cloud").cards) do
				if flow.can_activate(id) then flow.activate(id, {}); took = true; break end
			end
			if not took then
				local ip = zones.find("ice_pile")
				local top = ip.cards[#ip.cards]
				if top and flow.can_activate(top) then flow.activate(top, {}); took = true end
			end
			if not took then break end
		elseif p == "options" then
			-- An offer over an empty hand has nothing to pick, and declining is
			-- what a player does with it.
			-- Take the first card the offer will actually part with. A [GAIN]
			-- only offers what is at or below your Tier, so the first card up is
			-- often not one of them -- and an offer nobody can take from is one a
			-- player declines.
			local o, took = zones.find("options"), false
			for _, id in ipairs({ unpack(o.cards) }) do
				if flow.can_play(id) then flow.play_card(id, {}); took = true; break end
			end
			if not took and not flow.dismiss_offer() then break end
		else
			break
		end
		-- Not while a question is still up: Soothing Rain asks both players every
		-- time it comes round, and stopping the driver on an open offer would
		-- leave borrowed cards in it and prove nothing.
		-- Counted per seat now, because one phase key is taken by both of them:
		-- three regroups is six gains, and four rounds of two plays is eight.
		if (seen.gain_card or 0) >= 6 and phase.current().key ~= "options" then break end
	end
	check("the battle ran its four rounds and regrouped, three times over",
		(seen.gain_card or 0) >= 6, tostring(seen.gain_card))
	check("four plays per seat per battle",
		(seen.play_card or 0) >= 24, tostring(seen.play_card))
	check("the Storm Cloud is still five deep after all of it",
		#zones.find("storm_cloud").cards == 5,
		tostring(#zones.find("storm_cloud").cards))
	check("nothing got stuck in the offer",
		#zones.find("options").cards == 0, tostring(#zones.find("options").cards))
	-- The wiring, in a real round rather than a pushed phase: cards carrying the
	-- Ultimate icon came up and the round stopped to ask about them.
	check("and the icon opened windows along the way", asked > 0, tostring(asked))
end


-- The Ultimate icon, which used to mean nothing at all.
--
-- The printed rule is that you may cast your Ultimate while resolving a card
-- carrying the icon. There was no way to open a player decision inside an
-- automatic step, so an Ultimate was a button during your own play phase
-- instead -- spent before the reveal turned anything over, and the icon was
-- decoration. It is a reaction now: the card announces "resolving", the wizard
-- answers, and the resolution waits behind the window.
--
-- No engine word was needed for any of it. The announce is a phase of its own,
-- and a phase is the engine's word for "and then".
function M.test_spellstorm_an_ultimate_answers_a_card_that_carries_the_icon(check)
	opening(7, "derby", "eve")
	seat_card("seat_one").stats.initiative = 1
	seat_card("seat_two").stats.initiative = 0
	seat_card("seat_one").stats.mana = 9
	local dart = stage_battle("seat_one", "magicdart")
	local hurt = seat_card("seat_two").stats.health

	phase.push("duel")
	flow.settle()
	local top = flow.pending_event()
	check("the card announced itself", top ~= nil and top.re_verb == "resolving",
		top and top.re_verb or "(nothing announced)")
	-- The subject is the card rather than a rule about the round, which is what
	-- lets the window say which card opened it.
	check("and the window names the card that carries the icon",
		top ~= nil and top.re_subject[1] == dart.id)
	check("the seat resolving is the one with Initiative",
		zones.active_seat() == "seat_one", tostring(zones.active_seat()))
	check("its resolution has not run yet", seat_card("seat_one").stats.mana == 9,
		tostring(seat_card("seat_one").stats.mana))

	local answers = flow.usable_reactions()
	check("one wizard may answer, and it is the resolving seat's own",
		#answers == 1 and entity.get(answers[1].card).def_key == "wiz_derby",
		#answers .. " " .. (answers[1] and entity.get(answers[1].card).def_key or "-"))

	flow.react(answers[1].card, answers[1].index, {})
	-- The phase was pushed to reach it, and nothing under an interjection may
	-- resolve while it stands -- which is the rule that keeps a reaction's own
	-- offer from being run over. Stepping back off it is what a routed ult
	-- never has to do.
	phase.pop()
	flow.settle()
	-- Six for the Ultimate and two back from it: Derby deals 2, and thirteen
	-- health is an odd number, which is what the second mana is for.
	check("the Ultimate was paid for and fired", seat_card("seat_one").stats.mana == 5,
		tostring(seat_card("seat_one").stats.mana))
	check("and it hit", seat_card("seat_two").stats.health == hurt - 2,
		("%d, was %d"):format(seat_card("seat_two").stats.health, hurt))
	check("with nothing left waiting", flow.pending_event() == nil)
end


-- **Derby Pocket, ULTIMATE (6) -- Flaming Yardstick.** *"Deal 2 damage. If you
-- have an odd number of health, `[MANA]` `[MANA]`."*
--
-- **The number is the condition, so the card has no condition.** A remainder
-- says "an odd number of health" as an amount -- `health@mine.player % 2 * 2` --
-- and a gain of nothing is a gain of nothing, so the even case needs no second
-- rule and no branch the format does not have.
--
-- Worked out when the wizard answers rather than when the record resolves. That
-- is not a detail here: an Ultimate waits behind its own window, and the blow it
-- deals is not the only thing that could change a number in the meantime.
function M.test_spellstorm_derbys_ultimate_pays_at_an_odd_number_of_health(check)
	local function ultimate(health)
		opening(7, "derby", "eve")
		seat_card("seat_one").stats.initiative = 1
		seat_card("seat_two").stats.initiative = 0
		seat_card("seat_one").stats.mana = 9
		seat_card("seat_one").stats.health = health
		stage_battle("seat_one", "magicdart")

		phase.push("duel")
		flow.settle()
		local a = flow.usable_reactions()
		flow.react(a[1].card, a[1].index, {})
		phase.pop()
		flow.settle()
		return seat_card("seat_one").stats.mana - 3
	end

	check("an odd number of health is two mana", ultimate(11) == 2, ultimate(11))
	check("and one more health is none", ultimate(12) == 0, ultimate(12))
	check("one health is odd, which the smallest number often is not",
		ultimate(1) == 2, ultimate(1))
end


-- The other half of an icon meaning something: a card without one is quiet, and
-- a round of ordinary cards never stops to ask.
function M.test_spellstorm_a_card_without_the_icon_announces_nothing(check)
	opening(7, "derby", "eve")
	seat_card("seat_one").stats.initiative = 1
	seat_card("seat_two").stats.initiative = 0
	stage_battle("seat_one", "block")

	phase.push("duel")
	flow.settle()
	check("nothing announced itself", flow.pending_event() == nil,
		flow.pending_event() and flow.pending_event().re_verb or "-")
	check("and no wizard is being asked", #flow.usable_reactions() == 0)
end


-- "Discards a random card" is a selection and a coin toss, and the engine had
-- both words all along: `random.` narrows a scope to one of what it named, and
-- `move` obeys it. Six cards said "the top of their hand" instead, which is the
-- one card a player can plan around.
function M.test_spellstorm_a_random_discard_is_not_the_top_of_the_hand(check)
	opening(3, "eve", "croh")
	local two = "seat_two"
	empty_hand(two)
	local hand = hand_of(two)
	local order = { "magicdart", "block", "powergem", "ice" }
	for _, key in ipairs(order) do zones.add(hand, key) end

	local taken = {}
	for _ = 1, #order do
		actions.execute("move:random.enemy.hand:enemy.discard",
			{ card_id = seat_card("seat_one").id, targets = {} })
		local d = zone_of("discard", two)
		taken[#taken + 1] = entity.get(d.cards[#d.cards]).def_key
	end
	check("one card left the hand each time, and the hand is empty",
		#hand.cards == 0, #hand.cards)
	check("and they did not come off in the order they were held",
		table.concat(taken, ",") ~= table.concat(order, ","), table.concat(taken, ","))
end


-- The board prints what to do when a pile runs out, and until now running one
-- dry was a *reward*: giving from an empty pile did nothing at all.
function M.test_spellstorm_an_empty_pile_bites_instead_of_nothing(check)
	opening(3, "eve", "croh")
	local one, two = "seat_one", "seat_two"
	become(one)
	local pile = zones.find("curse_pile")
	check("the pile has CURSE in it to start with", #pile.cards > 0, #pile.cards)

	local health = seat_card(two).stats.health
	actions.execute("activate_zone:rules:by_column:dry_give_curse", {})
	check("with cards in the pile, the empty rule is quiet",
		seat_card(two).stats.health == health, seat_card(two).stats.health)

	for _, id in ipairs({ unpack(pile.cards) }) do zones.move_card(id, zones.find_id("void")) end
	actions.execute("activate_zone:rules:by_column:dry_give_curse", {})
	check("empty, being given a CURSE is a point of damage instead",
		seat_card(two).stats.health == health - 1, seat_card(two).stats.health)
end


-- Croh's DOOM Tokens come only from failure states, which is the trap his whole
-- design is built on: a token when he has none, and a token for a CURSE pile he
-- has already emptied. Both are ifs, and an if lives in an ability.
function M.test_spellstorm_dooms_arrive_only_from_failure(check)
	opening(3, "croh", "eve")
	local one = "seat_one"
	become(one)
	actions.execute("stat_set:doom@mine.player:0", {})
	actions.execute("activate_zone:rules:by_column:croh_doom", {})
	check("with no DOOM Token, the Ultimate grants one",
		seat_card(one).stats.doom == 1, seat_card(one).stats.doom)
	actions.execute("activate_zone:rules:by_column:croh_doom", {})
	check("holding one, it grants nothing",
		seat_card(one).stats.doom == 1, seat_card(one).stats.doom)

	local sinking = stage_battle(one, "croh_sinking")
	actions.execute("activate_zone:mine.battle:by_column:cast2",
		{ card_id = sinking.id, targets = {} })
	check("and Sinking Strike grants none while the CURSE pile is stocked",
		seat_card(one).stats.doom == 1, seat_card(one).stats.doom)
	local pile = zones.find("curse_pile")
	for _, id in ipairs({ unpack(pile.cards) }) do zones.move_card(id, zones.find_id("void")) end
	actions.execute("activate_zone:mine.battle:by_column:cast2",
		{ card_id = sinking.id, targets = {} })
	check("emptied, it does", seat_card(one).stats.doom == 2, seat_card(one).stats.doom)
end


-- Rapid Fire comes back to hand, which it could always have done: the round-end
-- sweep moves what is still standing in a battle spot, and a card that left is
-- not there to be swept.
function M.test_spellstorm_rapid_fire_comes_back(check)
	opening(3, "eve", "croh")
	local one = "seat_one"
	become(one)
	actions.execute("stat_set:initiative@mine.player:0", {})
	local rf = stage_battle(one, "rapidfire")
	actions.execute("activate_zone:mine.battle:by_column:cast2", { card_id = rf.id, targets = {} })
	check("without Initiative it stays where it fell",
		entity.get(rf.id).zone_id == zone_of("battle", one).id)

	-- With Initiative the redraw is offered rather than taken: "you *may*
	-- redraw this" is a part of the card you may decline, and a cost is one map
	-- settled in full, so the only way to say it is an offer of one.
	actions.execute("stat_set:initiative@mine.player:1", {})
	actions.execute("activate_zone:mine.battle:by_column:cast2", { card_id = rf.id, targets = {} })
	check("with it, the card asks", phase.current().key == "options"
		and #zones.find("options").cards == 1, phase.current().key)
	flow.play_card(zones.find("options").cards[1], {})
	check("and taking the offer puts it back in the hand",
		entity.get(rf.id).zone_id == hand_of(one).id,
		entity.get(entity.get(rf.id).zone_id).key)
	actions.execute("each_seat:move:mine.battle:mine.discard", {})
	check("so the sweep at the end of the round never sees it",
		entity.get(rf.id).zone_id == hand_of(one).id)

	-- And declined, it is left standing to be swept like any other card.
	local rf2 = stage_battle(one, "rapidfire")
	actions.execute("activate_zone:mine.battle:by_column:cast2", { card_id = rf2.id, targets = {} })
	check("declining leaves it in the battle spot", flow.dismiss_offer()
		and entity.get(rf2.id).zone_id == zone_of("battle", one).id,
		entity.get(entity.get(rf2.id).zone_id).key)
end


-- Abragail's journal asks three of its eight questions, and an offer is one at a
-- time: an action list has no cursor, so an ask has to be the last thing a phase
-- does. Each question therefore gets a phase, and each phase one seat -- two
-- Abragails would otherwise hold up both hands into the same offer.
function M.test_spellstorm_the_journal_asks_one_question_at_a_time(check)
	-- One journal is enough to ask with, and two seats cannot both be Abragail.
	opening(3, "abra", "eve")
	research()

	actions.execute("each_seat:activate_zone:rules:by_column:bstart", {})
	check("the silent spaces fire in the battle-start sweep and ask nothing",
		phase.current().key ~= "options", phase.current().key)

	-- The cards themselves rather than how many: declining the last question runs
	-- the chain on into the next round, which deals, so a total would be counting
	-- the weather's draw as well. What is being asked is whether any of *these*
	-- went missing.
	local held = {}
	for _, k in ipairs({ "seat_one", "seat_two" }) do
		for _, id in ipairs(hand_of(k).cards) do held[#held + 1] = id end
	end
	phase.push("journal")
	flow.settle()
	check("the space that asks opens its offer in its own phase",
		phase.current().key == "options", phase.current().key)
	local n = #zones.find("options").cards
	check("holding one seat's hand rather than both",
		n > 0 and n <= #hand_of("seat_one").cards + n, n)
	check("and it may be declined, since the printed space says you *may*",
		flow.can_dismiss())
	-- Declining is not losing. Shutting one question moves the game straight on
	-- to the next -- the journal has two more spaces that ask, and each is a
	-- phase -- so the chain is declined to the end and then counted.
	while phase.current().key == "options" and flow.dismiss_offer() do end
	check("declining sends every borrowed card home",
		#zones.find("options").cards == 0, #zones.find("options").cards)
	local home = 0
	for _, id in ipairs(held) do
		local z = entity.get(id) and entity.get(entity.get(id).zone_id)
		if z and z.key == "hand" then home = home + 1 end
	end
	check("with nothing lost on the way", home == #held, home .. " of " .. #held)
end


-- Oren's Ultimate is a loop, and a loop is a phase. Each potion costs a number
-- of one Element off the Chemistry Board and does nothing when the beaker is too
-- low; a third TOXIC ends the whole thing and hands him one of each junk card.
function M.test_spellstorm_the_potion_loop_pays_and_ends_itself(check)
	opening(7, "oren", "derby")
	local one = "seat_one"
	become(one)
	local seat = seat_card(one)
	check("the beakers start at three",
		seat.stats.fire_el == 3 and seat.stats.earth_el == 3 and seat.stats.water_el == 3,
		("%d/%d/%d"):format(seat.stats.fire_el, seat.stats.earth_el, seat.stats.water_el))

	actions.execute("push_phase:potion", {})
	local draw
	for _, z in ipairs(zones.all_with_key("sidecar")) do
		for _, id in ipairs(z.cards) do
			if entity.get(id).def_key == "btn_potion_draw" then draw = id end
		end
	end
	check("the draw button is reachable, and only here", draw ~= nil and #flow.usable_abilities(draw) == 1)

	local sips, guard = 0, 0
	while phase.current().key ~= "play_card" and guard < 40 do
		guard = guard + 1
		flow.settle()
		if phase.current().key == "reveal" then
			local id = zones.find("reveal").cards[1]
			if id and flow.can_play(id) then sips = sips + 1; flow.play_card(id, {}) end
		else
			local u = flow.usable_abilities(draw)
			if #u == 0 then break end
			flow.activate(draw, {}, u[1].index)
		end
	end
	check("drinking until a third TOXIC ends the Ultimate on its own",
		phase.current().key == "play_card", phase.current().key)
	check("and it took more than one potion to get there", sips > 1, sips)
	check("the beakers go back to three afterwards",
		seat.stats.fire_el == 3 and seat.stats.earth_el == 3 and seat.stats.water_el == 3,
		("%d/%d/%d"):format(seat.stats.fire_el, seat.stats.earth_el, seat.stats.water_el))
	local junk = 0
	for _, id in ipairs(zone_of("discard", one).cards) do
		local d = require("cards").def(entity.get(id))
		for _, t in ipairs(d.tags or {}) do if t == "junk" then junk = junk + 1 end end
	end
	check("and a third TOXIC costs an ASH, a CURSE and an ICE", junk >= 3, junk)
end


-- Riot says "discard your hand without triggering any discard effects", and it
-- means it. An On Discard fires on a card going from a hand to a discard; the
-- detour through `quiet` is neither half of that, so the cards land where the
-- card says they land and nothing is heard on the way.
function M.test_spellstorm_riot_discards_a_hand_in_silence(check)
	opening(3, "eve", "croh")
	local one = "seat_one"
	become(one)
	empty_hand(one)
	local hand = hand_of(one)
	-- Three cards that each say something on the way out: a Power Token, a
	-- point of damage, and a point off the Blast Score.
	for _, key in ipairs({ "powergem", "curse", "ice" }) do zones.add(hand, key) end
	local seat = seat_card(one)
	seat.stats.power, seat.stats.ice_pen = 0, 0
	local health = seat.stats.health

	local riot = stage_battle(one, "eve_riot")
	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = riot.id, targets = {} })

	-- Two cards back in it, because Riot draws two once the hand is gone.
	check("the hand went to the discard", #hand.cards == 2, #hand.cards)
	check("and the quiet is empty again, as it is between every pair of steps",
		#zones.find("quiet").cards == 0, #zones.find("quiet").cards)
	check("no Power Token from the Gem", seat.stats.power == 0, seat.stats.power)
	check("no damage from the CURSE", seat.stats.health == health, seat.stats.health)
	check("no Blast penalty from the ICE", seat.stats.ice_pen == 0, seat.stats.ice_pen)

	-- The same three cards discarded the ordinary way still speak up, which is
	-- what makes the silence Riot's doing rather than the engine's.
	empty_hand(one)
	for _, key in ipairs({ "powergem", "curse", "ice" }) do zones.add(hand, key) end
	seat.stats.power, seat.stats.ice_pen = 0, 0
	seat.stats.health = health
	actions.execute("move:mine.hand:mine.discard", { card_id = riot.id, targets = {} })
	check("discarded any other way, all three fire",
		seat.stats.power == 1 and seat.stats.health == health - 1 and seat.stats.ice_pen == 1,
		("%d/%d/%d"):format(seat.stats.power, seat.stats.health, seat.stats.ice_pen))
end


-- "Gain a Fire card" is two questions, not one, and the engine has a word for
-- each. Which cards come up is the *scope* -- `<zone>.<tag>`, one place and one
-- kind -- and it narrows what is shown, because a card that never comes up is
-- one nobody has to be told they may not click. Which of them may be taken is
-- `chosen.where`, and it is separate because it can ask about the player: your
-- Tier is not a property of the card you are looking at.
function M.test_spellstorm_an_offer_is_narrowed_to_one_kind(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	empty_hand(one)
	local hand = hand_of(one)
	for _, key in ipairs({ "fireball", "block", "powergem" }) do zones.add(hand, key) end

	local flame = stage_battle(one, "flame")
	actions.execute("activate_zone:mine.battle:by_column:cast_ask",
		{ card_id = flame.id, targets = {} })
	check("the offer opened", phase.current().key == "options", phase.current().key)
	local shown = {}
	for _, id in ipairs(zones.find("options").cards) do
		shown[#shown + 1] = entity.get(id).def_key
	end
	table.sort(shown)
	check("and it holds the Fire card and nothing else",
		table.concat(shown, ",") == "fireball", table.concat(shown, ","))
	check("the Water and Earth cards never left the hand", #hand.cards == 2, #hand.cards)
end

-- The other half: a question with no answer is not asked at all. Flame with no
-- Fire card in hand deals its damage and stops, which is what the card says.
function M.test_spellstorm_an_offer_of_nothing_does_not_open(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	empty_hand(one)
	for _, key in ipairs({ "block", "powergem" }) do zones.add(hand_of(one), key) end
	local flame = stage_battle(one, "flame")
	actions.execute("activate_zone:mine.battle:by_column:cast_ask",
		{ card_id = flame.id, targets = {} })
	check("no Fire card, no question", phase.current().key ~= "options", phase.current().key)
end

-- The Tier limit is the half a scope cannot say. Fire Essence offers the Fire
-- cards on the shelf and lets you take one at Tier I or II, so a Tier III card
-- comes up -- you can see what is there -- and cannot be clicked.
function M.test_spellstorm_the_tier_limit_gates_the_take(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	-- Staged first: the Essences start on the shelf, and clearing it would take
	-- the card under test with it.
	local essence = stage_battle(one, "fireessence")
	local shelf = zones.find("storm_cloud")
	for _, id in ipairs({ unpack(shelf.cards) }) do zones.purge_card(id) end
	for _, key in ipairs({ "fireball", "fireball2", "block" }) do zones.add(shelf, key) end
	actions.execute("activate_zone:mine.battle:by_column:cast_ask",
		{ card_id = essence.id, targets = {} })
	local shown, pickable = {}, {}
	for _, id in ipairs(zones.find("options").cards) do
		local key = entity.get(id).def_key
		shown[#shown + 1] = key
		if flow.can_play(id) then pickable[#pickable + 1] = key end
	end
	table.sort(shown)
	check("both Fire cards come up, and the Water one does not",
		table.concat(shown, ",") == "fireball,fireball2", table.concat(shown, ","))
	check("but only the Tier I one may be taken",
		table.concat(pickable, ",") == "fireball", table.concat(pickable, ","))
end


-- "At all times exactly one player holds the Initiative Tracker" -- it decides
-- the order of every step of the round that has one, so a game where nobody
-- holds it quietly turns "starting with the player who has Initiative" into
-- "starting with whoever happens to be up". The lower rating takes it, and a
-- mirror match, where the ratings are equal, used to leave it on the table.
function M.test_spellstorm_exactly_one_seat_holds_initiative(check)
	for _, pair in ipairs({ { "derby", "eve" }, { "bunny", "croh" }, { "may", "omar" } }) do
		opening(5, pair[1], pair[2])
		local held = seat_card("seat_one").stats.initiative
			+ seat_card("seat_two").stats.initiative
		check(pair[1] .. " v " .. pair[2] .. ": exactly one holds it", held == 1, held)
	end

	-- The tie, which no opening can reach any more: the eight ratings are eight
	-- different numbers and the roster stops the same wizard being taken twice,
	-- so a mirror match — the case "first_tie" was written for — is now
	-- unreachable in play. The rule is still the answer to *nobody holds it*,
	-- which a card could yet cause, so the state is made by hand and the two
	-- abilities are run in the order `battle_start` runs them.
	opening(5, "derby", "eve")
	for _, k in ipairs({ "seat_one", "seat_two" }) do
		seat_card(k).stats.initiative = 0
		seat_card(k).stats.init_rating = 4
	end
	actions.execute("each_seat:activate_zone:rules:by_column:first", {})
	actions.execute("activate_zone:rules:by_column:first_tie", {})
	local tied = seat_card("seat_one").stats.initiative + seat_card("seat_two").stats.initiative
	check("equal ratings still leave exactly one holding it", tied == 1, tied)

	opening(5, "derby", "eve")
	check("and it is the lower rating that has it",
		seat_card("seat_one").stats.initiative == 1
		and seat_card("seat_one").stats.init_rating < seat_card("seat_two").stats.init_rating,
		("%d/%d rating, %d/%d tracker"):format(
			seat_card("seat_one").stats.init_rating, seat_card("seat_two").stats.init_rating,
			seat_card("seat_one").stats.initiative, seat_card("seat_two").stats.initiative))
end


-- The round is ordered by the tracker, and every phase that cares names its own
-- seat rather than inheriting one -- so nothing accumulates across rounds. The
-- player with Initiative commits first, resolves first, and is asked first.
function M.test_spellstorm_the_round_is_ordered_by_initiative(check)
	opening(11, "derby", "eve")
	check("the Initiative holder plays first",
		seat_card(zones.active_seat()).stats.initiative == 1, zones.active_seat())
	-- Hand it over, run the round out, and the order follows the tracker rather
	-- than remembering who went first last time.
	actions.execute("set_active_seat:has_init", {})
	local was = zones.active_seat()
	seat_card("seat_one").stats.initiative = 1 - seat_card("seat_one").stats.initiative
	seat_card("seat_two").stats.initiative = 1 - seat_card("seat_two").stats.initiative
	phase.push("weather")
	flow.settle()
	while phase.current().key == "options" and flow.dismiss_offer() do end
	check("after it changes hands the other seat plays first",
		zones.active_seat() ~= was, zones.active_seat())
	check("and it is the one holding the tracker",
		seat_card(zones.active_seat()).stats.initiative == 1, zones.active_seat())
end


-- Mirrored, not rotated. Two people read the same board from opposite sides of a
-- table, so the second seat's row is the first one's reflected across the middle
-- -- wizard, hand, deck, discard, left to right on both -- and not turned through
-- half a circle. A rotated board puts your deck where your opponent's wizard is,
-- which is only right if you are really sitting opposite each other.
function M.test_spellstorm_the_board_is_mirrored_not_rotated(check)
	opening(5, "derby", "eve")
	-- "commit" is not in the list because it has no rect of its own: it sits on
	-- "battle", so the card turns over where it lay and one assertion covers both.
	check("the face-down spot is the battle spot",
		declaration.G.zone_defs.commit.pos == "battle", declaration.G.zone_defs.commit.pos)
	for _, key in ipairs({ "wizard", "hand", "deck", "discard", "battle" }) do
		local zs = zones.all_with_key(key)
		check(key .. ": one for each seat", #zs == 2, #zs)
		check(key .. ": the same place left to right for both seats",
			zs[1].pos[1] == zs[2].pos[1] and zs[1].pos[3] == zs[2].pos[3],
			("%s vs %s"):format(zs[1].pos[1] .. ".." .. zs[1].pos[3],
				zs[2].pos[1] .. ".." .. zs[2].pos[3]))
		-- And on their own side of it: the first seat is the near half.
		check(key .. ": each on their own side", zs[1].pos[2] > zs[2].pos[2],
			zs[1].pos[2] .. " vs " .. zs[2].pos[2])
	end
end


-- The plain [GAIN] icon, whose limit is your own Tier rather than a number the
-- card prints -- which is exactly why it is a `chosen.where` and not a narrower
-- scope. No tag on the card being looked at could say whether it is at or below
-- somebody's Tier, because it is not a fact about that card.
function M.test_spellstorm_a_gain_is_limited_to_your_own_tier(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	local shelf = zones.find("storm_cloud")
	for _, id in ipairs({ unpack(shelf.cards) }) do zones.purge_card(id) end
	for _, key in ipairs({ "fireball", "rapidfire", "fireball2" }) do zones.add(shelf, key) end

	local gem = stage_battle(one, "twopower")
	seat_card(one).stats.tier = 2
	actions.execute("activate_zone:mine.battle:by_column:cast_ask",
		{ card_id = gem.id, targets = {} })
	local shown, pickable = {}, {}
	for _, id in ipairs(zones.find("options").cards) do
		local key = entity.get(id).def_key
		shown[#shown + 1] = key
		if flow.can_play(id) then pickable[#pickable + 1] = key end
	end
	table.sort(shown)
	table.sort(pickable)
	check("the whole shelf comes up -- seeing it is half the decision",
		table.concat(shown, ",") == "fireball,fireball2,rapidfire", table.concat(shown, ","))
	check("but only Tier I and II may be taken at Tier II",
		table.concat(pickable, ",") == "fireball,rapidfire", table.concat(pickable, ","))

	-- And the gained card goes to hand, which is what the rulebook says a gain
	-- does unless the card says otherwise. Power Gem is the one that says so.
	local before = #hand_of(one).cards
	for _, id in ipairs({ unpack(zones.find("options").cards) }) do
		if flow.can_play(id) then flow.play_card(id, {}); break end
	end
	flow.settle()
	check("and it goes to the hand", #hand_of(one).cards == before + 1,
		("%d, was %d"):format(#hand_of(one).cards, before))
end


-- "A CURSE or ICE from your discard or your hand" is two unions met in the
-- middle, and until a union could be named the card had neither half: a scope
-- names one tag and one place. Now the kinds are a tag, the places are a tag,
-- and the two meet in a third.
function M.test_spellstorm_doom_bauble_offers_two_kinds_in_two_places(check)
	opening(3, "eve", "croh")
	local one = "seat_one"
	become(one)
	empty_hand(one)
	local hand, discard = hand_of(one), zone_of("discard", one)
	for _, id in ipairs({ unpack(discard.cards) }) do zones.move_card(id, zone_of("deck", one).id) end
	zones.add(hand, "curse")
	zones.add(hand, "magicdart")
	zones.add(discard, "ice")
	zones.add(discard, "block")
	-- Two that must not come up: one of the right kind in the wrong place, and
	-- one in the right place belonging to the wrong seat.
	zones.add(zone_of("battle", one), "curse")
	zones.add(zone_of("discard", "seat_two"), "ice")

	-- The Ultimate's own line, run on its own: what is under test is the offer,
	-- not the two cards it draws first.
	actions.execute("show:mine.held.curse_or_ice:optional",
		{ card_id = find("wiz_eve", "wizard").id, targets = {} })

	local shown = {}
	for _, id in ipairs(zones.find("options").cards) do
		shown[#shown + 1] = entity.get(id).def_key
	end
	table.sort(shown)
	check("the CURSE in hand and the ICE in the discard, and nothing else",
		table.concat(shown, ",") == "curse,ice", table.concat(shown, ","))
end


function M.test_spellstorm_both_endings_are_reachable(check)
	opening(5, "derby", "eve")
	-- End conditions are asked when the game comes to rest, so a play is what
	-- makes it look. Any legal one will do.
	actions.execute("set_active_seat:seat_one", {})
	actions.execute("stat_set:shards@mine.player:8", {})
	for _, id in ipairs(hand_of("seat_one").cards) do
		if flow.can_play(id) then flow.play_card(id, {}) break end
	end
	check("eight Storm Shards ends the game",
		phase.current().key == "reveal" or #zones.find("reveal").cards > 0,
		phase.current().key)

	opening(5, "derby", "eve")
	actions.execute("set_active_seat:seat_two", {})
	actions.execute("stat_set:health@mine.player:0", {})
	actions.execute("set_active_seat:seat_one", {})
	for _, id in ipairs(hand_of("seat_one").cards) do
		if flow.can_play(id) then flow.play_card(id, {}) break end
	end
	check("nought health ends it too",
		phase.current().key == "reveal" or #zones.find("reveal").cards > 0,
		phase.current().key)
end


-- The weather deck is dealt at the counts the box prints, not one of each
-- design. Five cards appear twice, and how often a design comes round is the
-- whole of what a deck of twenty-four four-card battles is measuring.
function M.test_spellstorm_the_weather_deck_is_dealt_at_its_printed_counts(check)
	opening(5, "derby", "eve")
	local seen = {}
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if z and (z.key or ""):find("^weather") then seen[e.def_key] = (seen[e.def_key] or 0) + 1 end
	end
	local total = 0
	for _, n in pairs(seen) do total = total + n end
	check("twenty-four cards in all", total == 24, total)
	check("and Crystal Flurries is two of them", seen.crystalflurries == 2, seen.crystalflurries)
	check("as is Soothing Rain", seen.soothingrain == 2, seen.soothingrain)
end


-- Soothing Rain asks every player whether to VOID a junk card, which is two
-- questions over two hands nobody else may read -- the shape the offer queue
-- was built for. Where the answer goes is the other half: a VOIDed junk card
-- goes back onto its own pile rather than into the VOID, because a pile running
-- dry is a rule, and which pile depends on what was picked.
function M.test_spellstorm_soothing_rain_voids_a_junk_card_onto_its_own_pile(check)
	opening(5, "derby", "eve")
	local one, two = "seat_one", "seat_two"
	-- Hands and discards both, because "your hand or discard pile" is what the
	-- card says and a wizard who opens holding an ICE would otherwise be offered
	-- two of them.
	for _, seat in ipairs({ one, two }) do
		empty_hand(seat)
		for _, id in ipairs({ unpack(zone_of("discard", seat).cards) }) do
			zones.move_card(id, zone_of("deck", seat).id)
		end
	end
	local ice = find("ice", "ice_pile")
	local ash = find("ash", "ash_pile")
	zones.move_card(ice.id, hand_of(one).id)
	zones.move_card(ash.id, hand_of(two).id)
	local piles = #zones.find("ice_pile").cards

	local rain = find("soothingrain")
	actions.execute("move:weather_now:weather_discard", {})
	zones.move_card(rain.id, zones.find("weather_now").id)
	become(one)
	actions.execute("each_seat:activate_zone:weather_now:by_column:wx", {})
	flow.settle()

	check("the first seat is asked", phase.current().key == "options", phase.current().key)
	local asked, wrong = zones.find("options"), nil
	for _, id in ipairs(asked.cards) do
		local home = entity.get(entity.get(id).borrowed_from)
		if home.seat ~= one or not require("tags").entity_has(entity.get(id), "junk") then
			wrong = entity.get(id).def_key .. " from " .. home.key .. "/" .. tostring(home.seat)
		end
	end
	check("about their own junk, out of their hand or their discard and nowhere else",
		#asked.cards > 0 and not wrong, wrong or #asked.cards)
	local held = false
	for _, id in ipairs(asked.cards) do if id == ice.id then held = true end end
	check("the ICE they are holding among it", held)
	check("and may decline, since the printed card says you may", flow.can_dismiss())
	flow.play_card(ice.id, {})
	check("the ICE went back onto the ICE pile",
		entity.get(ice.id).zone_id == zones.find("ice_pile").id)
	check("which is one deeper for it", #zones.find("ice_pile").cards == piles + 1,
		#zones.find("ice_pile").cards)

	check("and the second seat is asked next, not at the same time",
		phase.current().key == "options", phase.current().key)
	local second, theirs = zones.find("options"), false
	for _, id in ipairs(second.cards) do if id == ash.id then theirs = true end end
	check("about the ASH that one is holding", theirs, #second.cards)
	flow.dismiss_offer()
	check("declining leaves it where it was",
		entity.get(ash.id).zone_id == hand_of(two).id)
end


-- Energy Wave is the weather card that gives a player something to *do*. An
-- Ultimate is a reaction to one of your own cards announcing that it is
-- resolving, so a round in which anybody may cast one is a round in which
-- something else does the announcing -- and once both spells have resolved,
-- this card says the same word they say, once per seat.
function M.test_spellstorm_energy_wave_opens_an_ultimate_window(check)
	opening(5, "derby", "eve")
	local wave = find("energywave")
	actions.execute("move:weather_now:weather_discard", {})
	zones.move_card(wave.id, zones.find("weather_now").id)
	for _, k in ipairs({ "seat_one", "seat_two" }) do seat_card(k).stats.mana = 9 end

	-- What the `aftermath` phase does, run where the phase runs it. Pushed
	-- instead, the window would never open: an interjected phase holds the stack
	-- exactly so that a reaction's own offer resolves before anything under it.
	actions.execute("each_seat:activate_zone:weather_now:by_column:wz", {})
	flow.settle()
	local top = flow.pending_event()
	check("the weather announced a resolution of its own", top and top.re_verb == "resolving",
		top and top.re_verb)
	local usable = flow.usable_reactions()
	check("and the seat holding priority is offered their Ultimate", #usable == 1, #usable)
	check("out of their wizard zone",
		#usable == 1 and entity.get(entity.get(usable[1].card).zone_id).key == "wizard")

	-- Without the mana there is nothing to offer, which is the "still need the
	-- required mana" half of the printed card.
	for _, k in ipairs({ "seat_one", "seat_two" }) do seat_card(k).stats.mana = 0 end
	check("and nothing at all when they cannot pay", #flow.usable_reactions() == 0)
end


-- Amber is the one [GAIN] in the box that says MUST, and it says it twice. Both
-- halves needed the offer queue: one card asking two questions, and neither of
-- them declinable.
function M.test_spellstorm_amber_gains_twice_and_takes_no_for_an_answer(check)
	opening(5, "derby", "eve")
	local one = zones.active_seat()
	local amber = stage_battle(one, "amber")
	local held = #hand_of(one).cards

	actions.execute("copy:target:activate", { card_id = amber.id, targets = { amber.id } })
	check("it asks", phase.current().key == "options", phase.current().key)
	check("and there is no way out of the question", not flow.can_dismiss())
	local took = 0
	for _ = 1, 2 do
		for _, id in ipairs({ unpack(zones.find("options").cards) }) do
			if flow.can_play(id) then flow.play_card(id, {}); took = took + 1; break end
		end
	end
	check("twice over", took == 2, took)
	check("and both cards are in hand", #hand_of(one).cards == held + 2,
		#hand_of(one).cards)
	check("with the Storm Cloud refilled behind them",
		#zones.find("storm_cloud").cards == 5, #zones.find("storm_cloud").cards)
end


-- Potion Gun gives a card away and gains 2 of the Element it matched -- which
-- means reading the pick, and a `chosen` action cannot be told to ask. What it
-- can do is count: the pick is the only card left in the offer while those
-- actions run, so "count:fire@options" is one when a Fire card was chosen.
function M.test_spellstorm_potion_gun_reads_the_element_it_gave_away(check)
	opening(7, "oren", "derby")
	local one = "seat_one"
	become(one)
	empty_hand(one)
	local gun  = stage_battle(one, "oren_potion")
	local ball = find("fireball")
	zones.move_card(ball.id, hand_of(one).id)
	local own = find("oren_unstable")
	zones.move_card(own.id, hand_of(one).id)
	local fire = seat_card(one).stats.fire_el

	actions.execute("copy:target:activate", { card_id = gun.id, targets = { gun.id } })
	check("it opens the hand", phase.current().key == "options", phase.current().key)
	check("a Wizard Spell Card is not one you may give away", not flow.can_play(own.id))
	check("an ordinary card is", flow.can_play(ball.id))

	flow.play_card(ball.id, {})
	check("the card went to the opponent",
		entity.get(ball.id).zone_id == zone_of("hand", "seat_two").id)
	check("and two Fire came back for it", seat_card(one).stats.fire_el == fire + 2,
		seat_card(one).stats.fire_el)
	check("and nothing else moved on the board",
		seat_card(one).stats.water_el == 3 and seat_card(one).stats.earth_el == 3,
		seat_card(one).stats.water_el .. "/" .. seat_card(one).stats.earth_el)
end


-- "Lower any one Element by 2 to raise another by 2" is six moves, and the six
-- are the offer. Each carries its own rule, because a beaker with less than two
-- in it has nothing to pour.
function M.test_spellstorm_unstable_formula_pours_one_beaker_into_another(check)
	opening(7, "oren", "derby")
	local one = "seat_one"
	become(one)
	local card = stage_battle(one, "oren_unstable")
	seat_card(one).stats.fire_el = 1

	actions.execute("copy:target:activate", { card_id = card.id, targets = { card.id } })
	check("six pours are offered", #zones.find("options").cards == 6,
		#zones.find("options").cards)
	check("and it may be declined", flow.can_dismiss())
	local dry, wet
	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == "pour_fire_earth"  then dry = id end
		if entity.get(id).def_key == "pour_earth_fire" then wet = id end
	end
	-- A beaker below two has nothing to pour, and an offered card's own `needs`
	-- is not read -- so the rule is an ability on the entry instead, and picking
	-- that pour spends the choice and does nothing.
	flow.play_card(dry, {})
	check("pouring from a beaker with one in it does nothing",
		seat_card(one).stats.fire_el == 1 and seat_card(one).stats.earth_el == 3,
		seat_card(one).stats.fire_el .. "/" .. seat_card(one).stats.earth_el)

	seat_card(one).stats.fire_el = 1
	actions.execute("copy:target:activate", { card_id = card.id, targets = { card.id } })
	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == "pour_earth_fire" then wet = id end
	end
	flow.play_card(wet, {})
	check("and pouring from one with three moves the two across",
		seat_card(one).stats.earth_el == 1 and seat_card(one).stats.fire_el == 3,
		seat_card(one).stats.earth_el .. "/" .. seat_card(one).stats.fire_el)
end


-- "Your next Potion Card's effect happens twice (pay the cost once)." The only
-- card in the game that reaches forward to the next one, which it does with a
-- flag: Gasoline sets it, every other potion spends it.
function M.test_spellstorm_gasoline_doubles_the_next_potion(check)
	opening(7, "oren", "derby")
	local one = "seat_one"
	become(one)
	local pl = seat_card(one)
	local function sip(def_key)
		local e = find(def_key)
		zones.move_card(e.id, zones.find("reveal").id)
		actions.run(require("cards").behaviour(entity.get(e.id), "on_play"), { card_id = e.id, targets = {} })
	end

	local hp = pl.stats.health
	sip("pot_gasoline")
	check("the gasoline costs a point of health", pl.stats.health == hp - 1, pl.stats.health)
	check("and leaves the next one doubled", pl.stats.doubled == 1, pl.stats.doubled)

	pl.stats.fire_el, pl.stats.mana, pl.stats.power = 6, 0, 0
	sip("pot_purple")
	check("so Purple Stuff pours twice", pl.stats.mana == 4, pl.stats.mana)
	check("for one beaker's worth of Fire", pl.stats.fire_el == 4, pl.stats.fire_el)
	check("and the doubling is spent", pl.stats.doubled == 0, pl.stats.doubled)

	pl.stats.mana = 0
	sip("pot_storm")
	check("the one after that is an ordinary potion", pl.stats.power == 3, pl.stats.power)
end


-- "Resolve the top card of the Dragon Deck" -- resolve, not gain. `copy:` runs a
-- card's whole list where it lies, which is the difference between drinking the
-- elixir and pocketing the bottle.
function M.test_spellstorm_dragon_elixir_resolves_rather_than_gains(check)
	opening(7, "oren", "derby")
	local one = "seat_one"
	become(one)
	local deck = zones.find("dragon_deck")
	local top  = entity.get(deck.cards[#deck.cards])
	local n, held = #deck.cards, #hand_of(one).cards
	local hp = seat_card("seat_two").stats.health

	local e = find("pot_dragon")
	zones.move_card(e.id, zones.find("reveal").id)
	seat_card(one).stats.earth_el = 6
	actions.run(require("cards").behaviour(entity.get(e.id), "on_play"), { card_id = e.id, targets = {} })

	check("the Dragon stays where it lies", entity.get(top.id).zone_id == deck.id,
		entity.get(entity.get(top.id).zone_id).key)
	check("and the deck is no shorter", #zones.find("dragon_deck").cards == n,
		#zones.find("dragon_deck").cards)
	check("but it went off", seat_card("seat_two").stats.health < hp
		or #hand_of(one).cards ~= held or phase.current().key == "options",
		top.def_key)
end


-- May's Dangerous Download: at the end of a round she may spend an Energy and a
-- mana to resolve the opponent's revealed Tier II card. A thing a player may do,
-- at a cost, at a named moment -- which is a reaction, and the moment is the
-- round saying out loud that it is over.
function M.test_spellstorm_may_answers_the_end_of_a_round(check)
	opening(5, "may", "derby")
	local may, them = "seat_one", "seat_two"
	stage_battle(them, "rapidfire")
	seat_card(may).stats.energy = 2
	seat_card(may).stats.mana   = 3

	actions.execute("each_seat:activate_zone:rules:by_column:round_close", {})
	flow.settle()
	local top = flow.pending_event()
	check("the round announced itself", top and top.re_verb == "round_over",
		top and top.re_verb)
	check("and it is May who was asked", zones.active_seat() == may, zones.active_seat())
	check("with the download on offer", #flow.usable_reactions() == 1, #flow.usable_reactions())

	-- The cost is the whole of the "may", so without it there is nothing to take.
	seat_card(may).stats.energy = 0
	check("and nothing on offer when she cannot pay", #flow.usable_reactions() == 0)

	-- A Tier I card is not what the passive answers.
	opening(5, "may", "derby")
	stage_battle("seat_two", "fireball")
	seat_card("seat_one").stats.energy = 2
	seat_card("seat_one").stats.mana   = 3
	actions.execute("each_seat:activate_zone:rules:by_column:round_close", {})
	flow.settle()
	check("a Tier I card opens no window at all", flow.pending_event() == nil,
		flow.pending_event() and flow.pending_event().re_verb)
end


-- Abragail's *New Curriculum* asks three questions about one shelf and means two
-- different things by the answers: VOID up to 2, then gain 1. A card has one
-- `chosen` block, so the VOIDs are asked by the rule that is about VOIDing --
-- and each asker owns its own answer, which is why declining any of them leaves
-- the others saying what they always said.
function M.test_spellstorm_new_curriculum_voids_and_gains_from_one_shelf(check)
	opening(5, "abra", "eve")
	local one = zones.active_seat()
	local card = stage_battle(one, "abra_newcurriciulum")
	local held, voided = #hand_of(one).cards, #zones.find("void").cards

	actions.execute("copy:target:activate", { card_id = card.id, targets = { card.id } })
	-- It carries the Ultimate icon, so activating the whole card announces a
	-- resolution too. In a round that window is `ult`, a phase of its own;
	-- here it is in the way, and passing it is what the resolve phase waits for.
	-- Passing once is enough: the record stays on the stack while the offer it
	-- let through is open, so passing again does nothing but spin.
	if flow.pending_event() then flow.pass_react() end
	check("it asks", phase.current().key == "options", phase.current().key)

	-- Both VOIDs taken, then the gain: three questions, one shelf, two fates.
	local first = zones.find("options").cards[1]
	flow.play_card(first, {})
	check("the first pick went to the VOID",
		entity.get(first).zone_id == zones.find("void").id,
		entity.get(entity.get(first).zone_id).key)

	local second = zones.find("options").cards[1]
	check("and a second card is asked about", second ~= nil)
	flow.play_card(second, {})
	check("which goes to the VOID as well",
		entity.get(second).zone_id == zones.find("void").id,
		entity.get(entity.get(second).zone_id).key)

	check("then the gain is asked, and it is a different question",
		phase.current().key == "options", phase.current().key)
	local took
	for _, id in ipairs({ unpack(zones.find("options").cards) }) do
		if flow.can_play(id) then took = id; flow.play_card(id, {}); break end
	end
	check("and its answer goes to hand, not the VOID",
		took and entity.get(took).zone_id == hand_of(one).id,
		took and entity.get(entity.get(took).zone_id).key)
	check("so the hand is one longer", #hand_of(one).cards == held + 1, #hand_of(one).cards)
	check("and the VOID two", #zones.find("void").cards == voided + 2,
		#zones.find("void").cards)
	check("with the shelf refilled behind all three",
		#zones.find("storm_cloud").cards == 5, #zones.find("storm_cloud").cards)
end


-- "Up to 2" is the half a counter could never have carried: declining a VOID
-- must not turn the gain that follows it into one.
function M.test_spellstorm_a_declined_void_leaves_the_gain_a_gain(check)
	opening(5, "abra", "eve")
	local one = zones.active_seat()
	local card = stage_battle(one, "abra_newcurriciulum")
	local held, voided = #hand_of(one).cards, #zones.find("void").cards

	actions.execute("copy:target:activate", { card_id = card.id, targets = { card.id } })
	-- Passing once is enough: the record stays on the stack while the offer it
	-- let through is open, so passing again does nothing but spin.
	if flow.pending_event() then flow.pass_react() end
	check("both VOIDs may be declined", flow.can_dismiss())
	flow.dismiss_offer()
	check("and the second one too", flow.can_dismiss())
	flow.dismiss_offer()

	check("the gain is still waiting", phase.current().key == "options", phase.current().key)
	local took
	for _, id in ipairs({ unpack(zones.find("options").cards) }) do
		if flow.can_play(id) then took = id; flow.play_card(id, {}); break end
	end
	check("and it still gains", took and entity.get(took).zone_id == hand_of(one).id,
		took and entity.get(entity.get(took).zone_id).key)
	check("with nothing VOIDed on the way", #zones.find("void").cards == voided,
		#zones.find("void").cards)
	check("and one card gained", #hand_of(one).cards == held + 1, #hand_of(one).cards)
end

-- A seat is a chair until somebody sits in it. Both seat cards print "{name}"
-- and start as Player One and Player Two; the wizard's own pick action writes
-- its text over that, so every place the engine already said whose something
-- is — a per_seat zone's label, the phase banner, the end-of-game line — says
-- the wizard rather than the number.
function M.test_spellstorm_picking_a_wizard_names_the_chair(check)
	local label = require("label")
	flow.init("spellstorm.json", 5)
	check("before a pick the seats are numbered",
		label.seat_text("seat_one") == "Player One", label.seat_text("seat_one"))
	opening(5, "derby", "eve")
	check("seat one is the wizard sitting in it",
		label.seat_text("seat_one") == "Derby Pocket", label.seat_text("seat_one"))
	check("and so is seat two",
		label.seat_text("seat_two") == "Eve Williams", label.seat_text("seat_two"))
end

-- The rules button opened a sparkle and nothing else: the rules themselves were
-- in its tooltip, which is a thing you hover, on a card that plainly wants
-- clicking. Now the click is what opens them.
function M.test_spellstorm_the_rules_button_opens_the_rules(check)
	opening(7, "derby", "eve")
	local btn = find("btn_rules", "menu")
	check("the button is in the engine's column", btn ~= nil)
	local usable = flow.usable_abilities(btn.id)
	check("and it has one thing to do", #usable == 1, #usable)
	flow.activate(btn.id, {}, usable[1].index)
	check("which is a page", phase.current() and phase.current().key == "reveal",
		phase.current() and phase.current().key)
	local page = zones.find("reveal")
	check("holding the rules", page and #page.cards == 1
		and entity.get(page.cards[1]).def_key == "rules_page")
end

-- The chair and the wizard are one box. The seat card used to sit wherever the
-- middle of the board had room, which was nowhere near the thing it is read
-- beside.
function M.test_spellstorm_a_seat_sits_beside_its_own_wizard(check)
	opening(7, "derby", "eve")
	for _, seat in ipairs({ "seat_one", "seat_two" }) do
		local z = zone_of("wizard", seat)
		check(seat .. " has a wizard box", z ~= nil)
		local keys = {}
		for _, id in ipairs(z and z.cards or {}) do keys[entity.get(id).def_key] = true end
		check("the chair is in it", keys[seat], seat)
		check("and nobody else's is", not keys[seat == "seat_one" and "seat_two" or "seat_one"])
	end
end

-- A card dies into the pile it is lying beside, and nothing writes down whose
-- it is.
--
-- Cards cross the table in this game: Crossfire posts itself to the other
-- player's discard, Lava Bat lifts one out of theirs, and Eve's Ultimate feeds
-- them junk. Whoever a card started with, the side whose deck it is now in is
-- the side who discards it -- so the discard is a `status: "grave"` and the
-- Regroup, which throws away both hands in one line, says `destroy` and names
-- no pile at all.
function M.test_spellstorm_a_card_dies_in_the_pile_it_lives_in(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local two = one == "seat_one" and "seat_two" or "seat_one"
	empty_hand(one)
	empty_hand(two)

	-- Played rather than placed, because being played is the only moment that
	-- ever stamped an owner on a card, and the one this is about.
	local cf = find("crossfire")
	zones.move_card(cf.id, hand_of(one).id)
	check("Crossfire is cast", flow.play_card(cf.id, {})
		and entity.get(cf.id).zone_id == zone_of("commit", one).id)

	-- Where its own rule puts it: their pile, on the way to their deck.
	zones.move_card(cf.id, zone_of("discard", two).id)
	zones.move_card(cf.id, hand_of(two).id)

	local before = #zone_of("discard", one).cards
	actions.execute("each_seat:destroy:mine.hand", {})
	check("the hand they were holding it in is the hand it died out of",
		entity.get(cf.id).zone_id == zone_of("discard", two).id,
		entity.get(entity.get(cf.id).zone_id).key)
	check("and it did not go home to the wizard who sent it",
		#zone_of("discard", one).cards == before, #zone_of("discard", one).cards)
end

-- A card that has already left is not discarded on top of leaving.
--
-- Flame resolves another Fire card out of your hand and then discards it. An
-- Essence resolving is an Essence VOIDing itself, so by the time the discard
-- comes round the card is gone -- and it stayed gone only once the discard
-- became a death. Written as a move it named a pile and got one, dragging the
-- card back out of the VOID it had just printed its way into.
function M.test_spellstorm_a_voided_card_is_not_discarded_afterwards(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local ess = find("fireessence")
	zones.move_card(ess.id, hand_of(one).id)
	ess.stats.owner = nil
	local fl = stage_battle(one, "flame")
	local pile = #zone_of("discard", one).cards

	actions.execute("copy:target:activate", { card_id = fl.id, targets = { fl.id } })
	check("Flame asks for a Fire card out of the hand",
		phase.current().key == "options" and #zones.find("options").cards > 0)
	flow.play_card(ess.id, {})
	local landed = entity.get(entity.get(ess.id).zone_id)
	check("the Essence resolved, which is the Essence VOIDing itself",
		landed.key == "void", landed.key)
	check("and the discard that followed left it there",
		#zone_of("discard", one).cards == pile, #zone_of("discard", one).cards)
end

-- The other direction, and the one that needs a word: a card taken off them is
-- yours from then on.
--
-- Everything gained from the Storm Cloud is nobody's until it lands, so the
-- pile it lies in answers for it. A starting card is not -- it was dealt into a
-- seat's deck and carries that seat -- so Lava Bat, which lifts a card out of
-- their discard and puts it in yours, has to hand it over, or the next time you
-- throw it away it goes home to them.
function M.test_spellstorm_a_stolen_card_changes_hands(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local two = one == "seat_one" and "seat_two" or "seat_one"

	local loot
	for e in entity.each("card") do
		if e.def_key == "magicdart" and e.zone_id == zone_of("deck", two).id then loot = e end
	end
	check("they were dealt a Magic Dart of their own", loot ~= nil)
	zones.move_card(loot.id, zone_of("discard", two).id)

	local lb = stage_battle(one, "lavabat")
	actions.execute("copy:target:activate", { card_id = lb.id, targets = { lb.id } })
	-- "From any discard to any other discard" is two directions, so the card
	-- asks which way round before it asks which card.
	check("the two directions come up", phase.current().key == "options"
		and #zones.find("options").cards == 2, #zones.find("options").cards)
	flow.play_card(find("bat_take", "options").id, {})
	check("then their discard comes up", phase.current().key == "options"
		and #zones.find("options").cards > 0, phase.current().key)
	flow.play_card(loot.id, {})
	check("the card is in your discard now",
		entity.get(loot.id).zone_id == zone_of("discard", one).id,
		entity.get(entity.get(loot.id).zone_id).key)

	-- And stays there once it is going round your deck.
	zones.move_card(loot.id, hand_of(one).id)
	actions.execute("destroy:mine.hand", {})
	check("thrown away again, it comes back to you",
		entity.get(loot.id).zone_id == zone_of("discard", one).id,
		tostring(entity.get(entity.get(loot.id).zone_id).seat))
end


-- Three rules the game could not say when it was written, said now with words
-- the engine grew afterwards. Each was a to-do in the generator that outlived
-- the reason for it, which is the failure mode a gap list has: a sentence the
-- format could not carry stays written down long after it can.


-- Derby's *Distributor Connection*: "Gain Earth Essence into your discard."
--
-- There is one Earth Essence in the box and setup puts it on the shelf, so the
-- opening takes the real card and the shelf refills behind it -- which is the
-- whole effect, and why this is a move and not a fresh copy. It was a draw of
-- nought cards for a long time, from before a tag could name one card.
function M.test_spellstorm_derby_opens_by_taking_the_earth_essence(check)
	opening(1, "derby", "eve")
	local ess = find("earthessence")
	check("the Earth Essence is in Derby's discard",
		ess.zone_id == zone_of("discard", "seat_one").id,
		entity.get(ess.zone_id).key)
	check("and the shelf was refilled behind it",
		#zones.find("storm_cloud").cards == 5, #zones.find("storm_cloud").cards)
	-- "(do not trigger its discard effect)" comes free: On Discard is a `leaves`
	-- answering a hand, and this card never was in one.
	check("nobody powered up on the way", predicate.total("power@mine.player", {}) == 0)

	-- Nobody else's opening moves it, which is what makes it his.
	opening(1, "eve", "abra")
	check("another table leaves it on the shelf",
		entity.get(find("earthessence").zone_id).key == "storm_cloud")
end


-- Leap: "you may VOID a card from your hand or discard."
--
-- Two places and one scope, which had nowhere to be written until `held` became
-- a word both zones wear. Bloodstone and Ice Flume were given it; Leap was
-- missed and went on asking about the hand alone.
function M.test_spellstorm_leap_reaches_the_discard_as_well(check)
	opening(3, "derby", "eve")
	local one = zones.active_seat()
	local two = one == "seat_one" and "seat_two" or "seat_one"
	-- The rider only fires against a revealed Fire card.
	stage_battle(two, "fireball")
	empty_hand(one)
	for _, id in ipairs({ unpack(zone_of("discard", one).cards) }) do
		zones.move_card(id, zone_of("deck", one).id)
	end
	zones.move_card(find("arctite").id, hand_of(one).id)
	zones.move_card(find("moonstone").id, zone_of("discard", one).id)

	local leap = stage_battle(one, "leap")
	actions.execute("copy:target:activate", { card_id = leap.id, targets = { leap.id } })
	local up = {}
	for _, id in ipairs(zones.find("options").cards) do up[entity.get(id).def_key] = true end
	check("the card in hand comes up", up.arctite)
	check("and so does the one in the discard", up.moonstone)

	flow.play_card(find("moonstone").id, {})
	check("VOIDing it takes it out of the discard",
		entity.get(find("moonstone").id).zone_id == zones.find_id("void"),
		entity.get(entity.get(find("moonstone").id).zone_id).key)
end


-- Oren's *Unstable Formula*: six ways to pour one beaker into another, and a
-- beaker holding less than two cannot pour two.
--
-- The rule belongs on the entry, and for a while it could not live there: an
-- offer answered "yes" for anything lying in it, so the gate went into an
-- ability and a pour with nothing behind it was offered, picked, and did
-- nothing. A dealt entry is a line the asker wrote, so its own `needs` is the
-- gate on taking it.
function M.test_spellstorm_a_pour_needs_something_in_the_beaker(check)
	opening(3, "oren", "eve")
	become("seat_one")
	actions.execute("stat_set:fire_el@mine.player:3", {})
	actions.execute("stat_set:earth_el@mine.player:1", {})
	actions.execute("stat_set:water_el@mine.player:0", {})

	local uf = stage_battle("seat_one", "oren_unstable")
	actions.execute("copy:target:activate", { card_id = uf.id, targets = { uf.id } })
	local can = {}
	for _, id in ipairs(zones.find("options").cards) do
		can[entity.get(id).def_key] = flow.can_play(id)
	end
	check("a beaker holding 3 may pour 2", can.pour_fire_earth == true)
	check("one holding 1 may not", can.pour_earth_fire == false)
	check("and an empty one may not", can.pour_water_fire == false)

	-- And the pick is the pour: picking it used to spend the choice and run an
	-- ability that might decline to do anything.
	for _, id in ipairs({ unpack(zones.find("options").cards) }) do
		if entity.get(id).def_key == "pour_fire_earth" then flow.play_card(id, {}) end
	end
	check("Fire came down by 2", predicate.total("fire_el@mine.player", {}) == 1,
		predicate.total("fire_el@mine.player", {}))
	check("and Earth went up by 2", predicate.total("earth_el@mine.player", {}) == 3,
		predicate.total("earth_el@mine.player", {}))
end


-- Obsidian: "Take 1 damage and lose 2 mana. If you did, you may cast your
-- Ultimate here without paying its mana cost."
--
-- The one waived cost in the box, and it wanted no word for waiving one. A cost
-- is a map of what is owed, and this Ultimate is owed two ways: the wizard
-- answers the same announcement twice, once out of mana and once out of the
-- one-shot pass this card hands out, and the player gives whichever answer they
-- can. Obsidian does its own announcing, because the [ULT] icon's phase runs
-- before a card resolves and the pass does not exist yet then.
function M.test_spellstorm_obsidian_pays_for_an_ultimate_that_mana_could_not(check)
	opening(7, "derby", "eve")
	seat_card("seat_one").stats.initiative = 1
	seat_card("seat_two").stats.initiative = 0
	-- Three mana: two for Obsidian, and nowhere near Derby's six.
	seat_card("seat_one").stats.mana = 3
	stage_battle("seat_one", "obsidian")
	stage_battle("seat_two", "block")
	local hurt = seat_card("seat_two").stats.health

	phase.push("duel")
	flow.settle()
	check("the card took its two mana", seat_card("seat_one").stats.mana == 1,
		tostring(seat_card("seat_one").stats.mana))
	check("and handed out the pass", seat_card("seat_one").stats.ult_free == 1)
	check("a card with no icon still opened a window",
		flow.pending_event() ~= nil and flow.pending_event().re_verb == "resolving")

	local answers = flow.usable_reactions()
	check("one answer, and it is not the one that wants six mana",
		#answers == 1 and answers[1].index == 2,
		#answers .. " answer(s)")

	flow.react(answers[1].card, answers[1].index, {})
	phase.pop()
	flow.settle()
	check("the Ultimate fired", seat_card("seat_two").stats.health == hurt - 2,
		("%d, was %d"):format(seat_card("seat_two").stats.health, hurt))
	-- And it gives nothing back, because Obsidian's own bite is what made it
	-- give nothing: thirteen health less one is even, and Derby's Ultimate pays
	-- two mana only at an odd number. The free cast costs the mana it would have
	-- earned, which is a price the card never says out loud.
	check("and cost no mana, and earned none either",
		seat_card("seat_one").stats.mana == 1, tostring(seat_card("seat_one").stats.mana))
	check("the pass is spent", seat_card("seat_one").stats.ult_free == 0)
end


-- And with the mana as well as the pass there is still one answer, because a
-- card offering two is a card a click cannot reach: the paid Ultimate steps
-- aside while a pass is in hand rather than standing beside it.
function M.test_spellstorm_a_free_ultimate_is_the_only_one_offered(check)
	opening(7, "derby", "eve")
	seat_card("seat_one").stats.initiative = 1
	seat_card("seat_two").stats.initiative = 0
	seat_card("seat_one").stats.mana = 9
	stage_battle("seat_one", "obsidian")
	stage_battle("seat_two", "block")

	phase.push("duel")
	flow.settle()
	check("he can afford either", seat_card("seat_one").stats.mana == 7
		and seat_card("seat_one").stats.ult_free == 1)
	local answers = flow.usable_reactions()
	check("and is offered one", #answers == 1, #answers .. " answer(s)")
	check("which a bare click can reach",
		flow.sole_reaction(answers[1].card) ~= nil)
	check("it is the free one", answers[1].index == 2)
end


-- With two mana it is a waiver; with one it is a card that hurts you. "If you
-- did" is asked before the mana goes, which is the only moment that can tell
-- two mana from none.
function M.test_spellstorm_obsidian_gives_nothing_away_when_it_cannot_charge(check)
	opening(7, "derby", "eve")
	seat_card("seat_one").stats.initiative = 1
	seat_card("seat_two").stats.initiative = 0
	seat_card("seat_one").stats.mana = 1
	stage_battle("seat_one", "obsidian")
	stage_battle("seat_two", "block")

	phase.push("duel")
	flow.settle()
	check("the mana it could take, it took", seat_card("seat_one").stats.mana == 0,
		tostring(seat_card("seat_one").stats.mana))
	check("no pass", seat_card("seat_one").stats.ult_free == 0)
	check("and no window", flow.pending_event() == nil)
end


-- An unspent pass does not keep. It is offered while the card that gave it is
-- resolving, and goes out with the round.
function M.test_spellstorm_an_unspent_free_ultimate_expires(check)
	opening(7, "derby", "eve")
	become("seat_one")
	actions.execute("stat_set:ult_free@mine.player:1", {})
	phase.push("round_end")
	flow.settle()
	check("the round took it back", seat_card("seat_one").stats.ult_free == 0,
		tostring(seat_card("seat_one").stats.ult_free))
end


-- "Wizard Spell Cards can never be VOIDed for any reason" -- printed twice in
-- the rulebook, and `no_void` sat on all sixteen of them with nothing reading
-- it. The rule bites where the pick is made, so it is a `chosen.where` on the
-- six offers that void out of a player's own cards; nothing in the Storm Cloud
-- is a Wizard Spell Card and the junk piles are junk.
function M.test_spellstorm_a_wizard_spell_card_cannot_be_voided(check)
	opening(3, "derby", "eve")
	become("seat_one")
	empty_hand("seat_one")
	local h = hand_of("seat_one")
	-- Coffee Run is Derby's, and Earth -- so it answers every scope these cards
	-- narrow by, and only the rule keeps it out.
	zones.move_card(find("derby_coffee").id, h.id)
	zones.move_card(find("twopower").id, h.id)

	for _, key in ipairs({ "bloodstone", "shatter", "ultimate" }) do
		local c = find(key)
		zones.move_card(c.id, h.id)
		actions.execute("copy:target:activate", { card_id = c.id, targets = { c.id } })
		check(key .. " offers the ordinary card", flow.can_play(find("twopower").id))
		check(key .. " will not take the Wizard Spell Card",
			not flow.can_play(find("derby_coffee").id))
		while phase.current().key == "options" and flow.dismiss_offer() do end
		zones.move_card(c.id, zone_of("discard", "seat_one").id)
	end

end


-- The same rule at the two askers that are not spell cards: Abragail's journal
-- space 2, which asks through a rules card, and Bunny's Ultimate, whose printed
-- text says "reveal a non-Wizard card" and means this.
function M.test_spellstorm_the_journal_and_bunny_will_not_void_a_wizard_card(check)
	opening(3, "abra", "bunny")
	become("seat_one")
	empty_hand("seat_one")
	zones.move_card(find("abra_newcurriciulum").id, hand_of("seat_one").id)
	zones.move_card(find("twopower").id, hand_of("seat_one").id)

	research(2)
	actions.execute("activate_zone:rules:by_column:jr2", {})
	check("the journal's voiding space asks", phase.current().key == "options",
		phase.current().key)
	check("the ordinary card may go", flow.can_play(find("twopower").id))
	check("her own spell card may not",
		not flow.can_play(find("abra_newcurriciulum").id))
	while phase.current().key == "options" and flow.dismiss_offer() do end

	become("seat_two")
	empty_hand("seat_two")
	zones.move_card(find("bunny_snowday").id, hand_of("seat_two").id)
	zones.move_card(find("moonstone").id, hand_of("seat_two").id)
	actions.execute("show:mine.hand:optional", { card_id = find("wiz_bunny").id })
	check("Bunny's Ultimate asks", phase.current().key == "options",
		phase.current().key)
	check("and offers the ordinary card", flow.can_play(find("moonstone").id))
	check("but not the one it could never VOID",
		not flow.can_play(find("bunny_snowday").id))
end


-- Abragail's BATTLE START, *Did Her Research*: a Power Token at the top of every
-- battle. It was simply missing -- not a shape the engine refused, and nothing
-- about it wants the `todo` zone, which is for an imaginary card somebody must
-- play and aim. The `bstart` column is walked once per seat at the start of
-- every battle and a wizard power that happens then is a rules card whose `when`
-- is which wizard is sitting there.
function M.test_spellstorm_abragail_powers_up_at_every_battle_start(check)
	opening(3, "abra", "eve")
	check("she starts the first battle a token up",
		seat_card("seat_one").stats.power == 1,
		tostring(seat_card("seat_one").stats.power))
	check("and nobody else does", seat_card("seat_two").stats.power == 0,
		tostring(seat_card("seat_two").stats.power))

	-- Every battle, not once a game.
	phase.push("battle_start")
	flow.settle()
	check("the next battle adds another", seat_card("seat_one").stats.power == 2,
		tostring(seat_card("seat_one").stats.power))
	check("and still nobody else", seat_card("seat_two").stats.power == 0)
end


-- Three cards that print "A **or** B" and did both, or only one.
--
-- An "or" is an offer of two, and the two are cards: `options:` deals an entry
-- per branch, each carrying what that branch does and -- since a dealt entry's
-- own `needs` is read -- whether it is on the table at all. A branch that asks a
-- question of its own asks it from the entry, whose `chosen` answers it, because
-- the asker is the card standing in the offer and not the card that dealt it.

local function offered(key)
	for _, id in ipairs(zones.find("options").cards) do
		if entity.get(id).def_key == key then return id end
	end
end

-- The four passes the resolve phase makes over a battle spot, in its order.
local function resolve_battle()
	for _, col in ipairs({ "cast", "cast2", "cast3", "cast_ask" }) do
		actions.execute("activate_zone:mine.battle:by_column:" .. col, {})
	end
end

local function take(key)
	local id = offered(key)
	assert(id, "nothing called " .. key .. " is in the offer")
	flow.play_card(id, {})
end


-- Omar's *Hidden Movement*: "return a card from your discard to your hand **or**
-- draw". It drew and then offered the return, which is a different card.
function M.test_spellstorm_omars_ultimate_is_one_of_two(check)
	opening(3, "omar", "eve")
	become("seat_one")
	local held = #hand_of("seat_one").cards
	zones.move_card(find("moonstone").id, zone_of("discard", "seat_one").id)
	actions.execute("options:omar_recall,omar_draw:optional",
		{ card_id = find("wiz_omar").id })
	check("both branches are on the table",
		flow.can_play(offered("omar_recall")) and flow.can_play(offered("omar_draw")))

	take("omar_recall")
	check("picking the return opens the discard", phase.current().key == "options"
		and offered("moonstone") ~= nil, phase.current().key)
	take("moonstone")
	check("the card comes back to hand",
		entity.get(find("moonstone").id).zone_id == hand_of("seat_one").id,
		entity.get(entity.get(find("moonstone").id).zone_id).key)
	check("and that is all it did -- one card richer, not two",
		#hand_of("seat_one").cards == held + 1,
		("%d, was %d"):format(#hand_of("seat_one").cards, held))
end


-- With nothing in the discard there is nothing to return, and the branch says so
-- itself rather than opening an offer with no answer in it.
function M.test_spellstorm_a_branch_with_nothing_behind_it_is_not_offered(check)
	opening(3, "omar", "eve")
	become("seat_one")
	for _, id in ipairs({ unpack(zone_of("discard", "seat_one").cards) }) do
		zones.move_card(id, zone_of("deck", "seat_one").id)
	end
	actions.execute("options:omar_recall,omar_draw:optional",
		{ card_id = find("wiz_omar").id })
	check("the return is refused", not flow.can_play(offered("omar_recall")))
	check("the draw is not", flow.can_play(offered("omar_draw")))
end


-- May's *Void Traveler*: "a non-Wizard card from your hand **or** any card in
-- the VOID". Only the VOID half was built, and the non-Wizard rule with it.
function M.test_spellstorm_may_may_travel_from_either_place(check)
	opening(3, "may", "eve")
	become("seat_one")
	empty_hand("seat_one")
	actions.execute("options:may_hand,may_void:optional", { card_id = find("wiz_may").id })
	check("an empty hand and an empty VOID offer nothing",
		not flow.can_play(offered("may_hand"))
		and not flow.can_play(offered("may_void")))
	while phase.current().key == "options" and flow.dismiss_offer() do end

	zones.move_card(find("may_starshot").id, hand_of("seat_one").id)
	zones.move_card(find("twopower").id, hand_of("seat_one").id)
	actions.execute("options:may_hand,may_void:optional", { card_id = find("wiz_may").id })
	check("cards in hand open that half", flow.can_play(offered("may_hand")))
	check("the VOID is still empty", not flow.can_play(offered("may_void")))

	take("may_hand")
	check("the ordinary card may be resolved", flow.can_play(offered("twopower")))
	check("her own spell card may not -- it is the non-Wizard rule",
		not flow.can_play(offered("may_starshot")))
	take("twopower")
	check("and the card it resolved goes under the Spellstorm Deck",
		entity.get(find("twopower").id).zone_id == zones.find_id("spellstorm_deck"),
		entity.get(entity.get(find("twopower").id).zone_id).key)
end


-- May's *Data Breach*: "lose 1 **or** 2 Energy Tokens, and power up that many
-- times. If you still have 2 Energy Tokens, ..." The card read the 2 as the gate
-- on paying rather than as a choice, which put both ifs on the same number.
function M.test_spellstorm_data_breach_asks_how_much_to_spend(check)
	opening(3, "may", "eve")
	become("seat_one")
	actions.execute("stat_set:energy@mine.player:3", {})
	local db = stage_battle("seat_one", "may_data")
	local theirs = #hand_of("seat_two").cards

	resolve_battle()
	check("both prices are offered at 3 Energy",
		flow.can_play(offered("may_lose1")) and flow.can_play(offered("may_lose2")))

	-- Spending one leaves two, which is what buys the second half.
	take("may_lose1")
	check("one Energy went", seat_card("seat_one").stats.energy == 2,
		tostring(seat_card("seat_one").stats.energy))
	check("and one Power came", seat_card("seat_one").stats.power == 1,
		tostring(seat_card("seat_one").stats.power))
	check("their hand is open to her", phase.current().key == "options"
		and #zones.find("options").cards == theirs, phase.current().key)
	flow.play_card(zones.find("options").cards[1], {})
	check("and she picked what they lost",
		#hand_of("seat_two").cards == theirs - 1,
		("%d, was %d"):format(#hand_of("seat_two").cards, theirs))
end


-- The other branch, and the trade the card is made of: spending two leaves one,
-- so the powering up is all you get.
function M.test_spellstorm_spending_two_energy_buys_no_breach(check)
	opening(3, "may", "eve")
	become("seat_one")
	actions.execute("stat_set:energy@mine.player:3", {})
	local db = stage_battle("seat_one", "may_data")
	local theirs = #hand_of("seat_two").cards

	resolve_battle()
	take("may_lose2")
	check("two Energy went", seat_card("seat_one").stats.energy == 1,
		tostring(seat_card("seat_one").stats.energy))
	check("and two Power came", seat_card("seat_one").stats.power == 2,
		tostring(seat_card("seat_one").stats.power))
	check("their hand stays their own", phase.current().key ~= "options",
		phase.current().key)
	check("and they keep every card",
		#hand_of("seat_two").cards == theirs)
end


-- Abragail's journal: eight spaces, six tokens, and *which six* is the whole of
-- her. It was one counter doing two jobs -- how many tokens she had spent, and
-- which spaces were lit, through `research >= n` -- so the spaces were forced
-- into a fixed order and spaces 7 and 8 were unreachable by a number that stops
-- at six. Split in two: `research` is the budget, and a token is a flag on the
-- space it sits on.
function M.test_spellstorm_a_research_token_goes_where_she_puts_it(check)
	opening(3, "abra", "eve")
	become("seat_one")
	local function level_up()
		actions.execute("show:rules.jspace:optional", { card_id = find("wiz_abra").id })
	end
	local function space(n)
		for _, id in ipairs(zones.find("options").cards) do
			if entity.get(id).def_key == "r_journal_" .. n then return id end
		end
	end

	level_up()
	check("all eight spaces come up", #zones.find("options").cards == 8,
		#zones.find("options").cards)
	check("including the two a counter could never reach",
		flow.can_play(space(7)) and flow.can_play(space(8)))

	-- The first token goes on the last space, which is the thing the counter
	-- made impossible.
	flow.play_card(space(8), {})
	check("the token sits on the space she chose",
		find("r_journal_8").stats.researched == 1)
	check("and on no other", find("r_journal_1").stats.researched == 0)
	check("one of the six is spent", seat_card("seat_one").stats.research == 1,
		tostring(seat_card("seat_one").stats.research))

	level_up()
	check("a space already researched is not offered again",
		not flow.can_play(space(8)))
	check("the empty ones still are", flow.can_play(space(1)))
	while phase.current().key == "options" and flow.dismiss_offer() do end

	-- And it fires, alone, at the top of a battle.
	local held = #hand_of("seat_one").cards
	actions.execute("activate_zone:rules:by_column:bstart", {})
	check("space 8 draws her a card", #hand_of("seat_one").cards == held + 1,
		("%d, was %d"):format(#hand_of("seat_one").cards, held))
end


-- Six tokens never fill eight slots, which is the shape of the printed journal
-- and the reason the Ultimate is the cheapest in the game.
function M.test_spellstorm_the_journal_runs_out_of_tokens_before_spaces(check)
	opening(3, "abra", "eve")
	become("seat_one")
	local function level_up()
		actions.execute("show:rules.jspace:optional", { card_id = find("wiz_abra").id })
	end
	for _, n in ipairs({ 1, 2, 3, 4, 5, 6 }) do
		level_up()
		for _, id in ipairs({ unpack(zones.find("options").cards) }) do
			if entity.get(id).def_key == "r_journal_" .. n then flow.play_card(id, {}) end
		end
	end
	check("six tokens are spent", seat_card("seat_one").stats.research == 6,
		tostring(seat_card("seat_one").stats.research))

	level_up()
	check("and the seventh Ultimate has nowhere to put one",
		phase.current().key ~= "options", phase.current().key)
	check("so two spaces stay dark",
		find("r_journal_7").stats.researched == 0
		and find("r_journal_8").stats.researched == 0)
end


-- Six simplifications that were content work, not engine work.
--
-- Each was written down as a limit and each was reachable with words that had
-- arrived since -- which is the whole failure this corpus keeps tripping over: a
-- sentence the format could not carry outlives the reason for it, and the note
-- goes on asserting a limit somebody lifted.


-- Coffee Run: "`[GAIN]`. If you gained an `[EARTH]` card, gain `[INIT]`." The
-- rider asks about the card just chosen, which is the only card still lying in
-- the offer while a `chosen` list runs -- the reading Potion Gun takes its
-- Element from. Counted before the move, since a card in hand is not in the
-- offer to be counted.
function M.test_spellstorm_coffee_run_reads_what_was_gained(check)
	for _, case in ipairs({ { "twopower", 1 }, { "fireball", 0 } }) do
		local pick, want = case[1], case[2]
		opening(3, "derby", "eve")
		become("seat_one")
		seat_card("seat_one").stats.initiative = 0
		seat_card("seat_two").stats.initiative = 1
		local sc = zones.find("storm_cloud")
		for _, id in ipairs({ unpack(sc.cards) }) do
			zones.move_card(id, zones.find_id("spellstorm_deck"))
		end
		zones.move_card(find(pick).id, sc.id)

		local cr = stage_battle("seat_one", "derby_coffee")
		actions.execute("copy:target:activate", { card_id = cr.id, targets = { cr.id } })
		flow.play_card(find(pick, "options").id, {})
		check(("gaining %s leaves Initiative at %d"):format(pick, want),
			seat_card("seat_one").stats.initiative == want,
			tostring(seat_card("seat_one").stats.initiative))
		check("and the card is in hand either way",
			entity.get(find(pick).zone_id).key == "hand")
	end
end


-- Star Shot: "Discard a card to deal 1 damage. If it was Tier II, deal 1 more."
-- The same reading, of a number rather than a tag.
function M.test_spellstorm_star_shot_reads_the_tier_it_discarded(check)
	for _, case in ipairs({ { "obsidian", 2 }, { "fireball", 1 } }) do
		local pick, want = case[1], case[2]
		opening(3, "may", "eve")
		become("seat_one")
		empty_hand("seat_one")
		zones.move_card(find(pick).id, hand_of("seat_one").id)
		local hp = seat_card("seat_two").stats.health

		local ss = stage_battle("seat_one", "may_starshot")
		actions.execute("copy:target:activate", { card_id = ss.id, targets = { ss.id } })
		flow.play_card(find(pick, "options").id, {})
		check(("discarding %s deals %d"):format(pick, want),
			hp - seat_card("seat_two").stats.health == want,
			tostring(hp - seat_card("seat_two").stats.health))
	end
end


-- Wind Dragon: "You may resolve up to two cards from your hand." Two `show:`
-- lines on one card are two questions, both answered by the one `chosen` -- the
-- idiom Amber gains twice with. Driven through the resolve columns, because a
-- second question asked from inside a `copy:` is swept (see 09).
function M.test_spellstorm_wind_dragon_resolves_two(check)
	opening(3, "derby", "eve")
	become("seat_one")
	empty_hand("seat_one")
	for _, k in ipairs({ "fireball", "moonstone", "twopower" }) do
		zones.move_card(find(k).id, hand_of("seat_one").id)
	end
	stage_battle("seat_one", "winddragon")
	for _, col in ipairs({ "cast", "cast2", "cast3", "cast_ask" }) do
		actions.execute("activate_zone:mine.battle:by_column:" .. col, {})
	end
	check("it asks once", phase.current().key == "options"
		and #zones.find("options").cards == 3, phase.current().key)
	flow.play_card(find("fireball", "options").id, {})
	check("and again", phase.current().key == "options"
		and #zones.find("options").cards == 2, phase.current().key)
	flow.play_card(find("moonstone", "options").id, {})
	check("both resolved and both went to the discard",
		entity.get(find("fireball").zone_id).key == "discard"
		and entity.get(find("moonstone").zone_id).key == "discard")
end


-- Croh's DOOOOOOOOOM!: "For each DOOM Token you have, you may redraw a card of
-- your choice from your discard to your hand OR `[DRAW]`."
--
-- A number of questions worked out from a stat, which has no other spelling: an
-- action list is written once and a stat is read as it runs. One rules card per
-- token he might hold, each gated on holding that many.
function M.test_spellstorm_croh_asks_once_per_doom_token(check)
	opening(3, "croh", "eve")
	become("seat_one")
	seat_card("seat_one").stats.doom = 3
	empty_hand("seat_one")
	-- A deck to draw from, so a draw is a draw and the discard is not swept
	-- into it halfway through.
	for _, id in ipairs({ unpack(zone_of("discard", "seat_one").cards) }) do
		zones.move_card(id, zone_of("deck", "seat_one").id)
	end
	local deck = #zone_of("deck", "seat_one").cards

	actions.execute("activate_zone:rules:by_column:croh_redraw", {})
	local asked = 0
	for _ = 1, 6 do
		if phase.current().key ~= "options" then break end
		asked = asked + 1
		flow.play_card(find("croh_draw", "options").id, {})
	end
	check("three tokens, three questions", asked == 3, asked)
	check("and three cards drawn", #hand_of("seat_one").cards == 3,
		#hand_of("seat_one").cards)
	check("off the deck", #zone_of("deck", "seat_one").cards == deck - 3)
end


-- An empty supply pile: "whoever would have been given one VOIDs a card of that
-- kind from their hand or discard and takes the penalty instead."
--
-- Every ICE is the same card, so *which* one looks immaterial -- and is not:
-- one in your hand costs a Blast Score and one in your discard costs a draw. So
-- the holder is asked, and when the junk was being *given*, the holder is the
-- other player. `set_priority` is the whole of that: from inside the window,
-- `mine` is theirs.
function M.test_spellstorm_a_dry_pile_asks_the_player_it_bites(check)
	opening(3, "eve", "croh")
	become("seat_one")
	local pile = zones.find("curse_pile")
	local held = { unpack(pile.cards) }
	zones.move_card(held[1], hand_of("seat_two").id)
	zones.move_card(held[2], zone_of("discard", "seat_two").id)
	for i = 3, #held do zones.move_card(held[i], zones.find_id("void")) end
	check("the pile is empty", #pile.cards == 0)

	actions.execute("activate_zone:rules:by_column:dry_give_curse", {})
	check("the offer went to the player being given the CURSE",
		zones.active_seat() == "seat_two", tostring(zones.active_seat()))
	check("and holds both of theirs, hand and discard",
		#zones.find("options").cards == 2, #zones.find("options").cards)

	flow.play_card(zones.find("options").cards[1], {})
	check("the card they chose goes back on the pile", #pile.cards == 1, #pile.cards)
end

-- **Accursed.** *"Whenever you would normally heal damage, ignore all healing and
-- give 1 CURSE instead."*
--
-- The healing does not arrive smaller, it does not arrive at all — so no `by`
-- reaches it, and `adjusts.instead` is the word that does. What it needed from
-- the game was for healing to *be* a moment: the engine's own stat_gain is
-- unwatchable on purpose, so every heal in the box goes through a declared verb
-- and this is the one rule that answers it.
--
-- It was a battle-start sweep before — one CURSE at the top of each battle,
-- whether anyone had tried to heal him or not, and he could still heal.
function M.test_spellstorm_croh_never_heals_and_the_curse_goes_the_other_way(check)
	opening(3, "croh", "eve")
	become("seat_one")
	local croh = seat_card("seat_one")
	local their_discard = zone_of("discard", "seat_two")
	actions.execute("stat_damage:health@mine.player:5", {})
	local hurt, junk = croh.stats.health, #their_discard.cards

	actions.execute("heal:health@mine.player:3", {})
	check("the healing never lands", croh.stats.health == hurt, croh.stats.health)
	check("and a CURSE went to the other seat instead",
		#their_discard.cards == junk + 1, #their_discard.cards)
	check("which is a CURSE and not whatever was on top",
		entity.get(their_discard.cards[#their_discard.cards]).def_key == "curse",
		entity.get(their_discard.cards[#their_discard.cards]).def_key)

	-- The aura is printed on Croh's card and covers his seat, so the other
	-- wizard heals the way everybody else does.
	become("seat_two")
	local eve = seat_card("seat_two")
	actions.execute("stat_damage:health@mine.player:5", {})
	local eve_hurt, his_discard = eve.stats.health, #zone_of("discard", "seat_one").cards
	actions.execute("heal:health@mine.player:3", {})
	check("Eve heals in full", eve.stats.health == eve_hurt + 3, eve.stats.health)
	check("and gave nobody anything",
		#zone_of("discard", "seat_one").cards == his_discard,
		#zone_of("discard", "seat_one").cards)
end


-- **Double Stitch.** *"You can heal beyond your starting health, to a maximum of
-- 10 health."* **Triple Stitch!** *"If you heal when already at 10 health,
-- [DRAW] for each point of wasted healing."*
--
-- The note on his card claimed the first was free — that his ceiling was 10 from
-- the start and only the overheal draw was missing. It was not: every wizard's
-- ceiling was their printed health, so Bunny stopped at 8 like everybody else and
-- neither passive existed. A ceiling of his own is one number; the draw is the
-- aura, and what it needed was the size of the heal it was cancelling.
function M.test_spellstorm_bunny_heals_past_his_start_and_draws_the_rest(check)
	opening(3, "bunny", "eve")
	become("seat_one")
	local bunny = seat_card("seat_one")
	check("he starts at 8", bunny.stats.health == 8, bunny.stats.health)

	actions.execute("heal:health@mine.player:1", {})
	check("and heals past it, which nobody else may", bunny.stats.health == 9,
		bunny.stats.health)
	actions.execute("heal:health@mine.player:5", {})
	check("up to ten and no further", bunny.stats.health == 10, bunny.stats.health)

	local hand, deck = #hand_of("seat_one").cards, #zone_of("deck", "seat_one").cards
	actions.execute("heal:health@mine.player:3", {})
	check("at the ceiling the healing is dropped", bunny.stats.health == 10,
		bunny.stats.health)
	check("and drawn instead, a card for every wasted point",
		#hand_of("seat_one").cards == hand + 3, #hand_of("seat_one").cards)
	check("off his own deck", #zone_of("deck", "seat_one").cards == deck - 3)
end


-- **Omar's Traps.** *"Kept face-down on his character card; revealed at will
-- after the trigger event, then left face up and inactive until swapped by the
-- next Ultimate."*
--
-- > **Mud Trap** — You may reveal this if you COUNTER with a `[FIRE]` card.
-- > Deal 1 damage. `[MANA]`, gain `[INIT]`.
--
-- The note said a trap was unreachable because "an opponent is dealing damage to
-- you" is not a moment the engine announces. Nothing announced it because nothing
-- had said it out loud: these two trigger on **countering**, already a rules card
-- firing in the showdown, and one `emit:countered` there makes a trap an ordinary
-- reaction — the same shape as the Ultimate answering `resolving`. *Dodge!* below
-- is the same two lines with `damaging` in place of `countered`.
--
-- The draw is the emit's *held* action, not the line beside it: an action list
-- runs to completion, so a draw written after the announcement would land before
-- anybody had answered it.
function M.test_spellstorm_a_trap_answers_the_counter_it_was_laid_for(check)
	opening(3, "omar", "eve")
	become("seat_one")
	local mud = find("trap_mud")
	check("his traps start on the pile", entity.get(mud.zone_id).key == "trap_pile",
		entity.get(mud.zone_id).key)
	zones.move_card(mud.id, zone_of("traps", "seat_one").id)

	-- Fire beats Earth, which is the counter this trap is laid for.
	stage_battle("seat_one", "fireball")
	stage_battle("seat_two", "twopower")
	local them, me = seat_card("seat_two"), seat_card("seat_one")
	local hp, mana, hand = them.stats.health, me.stats.mana, #hand_of("seat_one").cards

	actions.execute("activate_zone:rules:by_column:check", {})
	check("countering announced itself", #flow.usable_reactions() == 1,
		#flow.usable_reactions())
	check("and the draw is still waiting behind the window",
		#hand_of("seat_one").cards == hand, #hand_of("seat_one").cards)

	flow.react(mud.id, 1, {})
	check("the trap dealt its damage", them.stats.health == hp - 1, them.stats.health)
	check("and paid its mana", me.stats.mana == mana + 1, me.stats.mana)
	check("and took the Initiative", me.stats.initiative == 1, me.stats.initiative)
	check("the counter's own draw came after", #hand_of("seat_one").cards == hand + 1,
		#hand_of("seat_one").cards)
	check("and the trap is spent where it lies",
		mud.stats.sprung == 1 and entity.get(mud.zone_id).key == "traps",
		entity.get(mud.zone_id).key)

	-- Spent is spent: the same counter next round finds nothing to answer it.
	actions.execute("activate_zone:rules:by_column:check", {})
	check("it does not answer twice", #flow.usable_reactions() == 0,
		#flow.usable_reactions())
end

-- *Ice Bomb* is the same shape with a different counter and a rider that matters:
-- it carries the Ultimate icon, so revealing it is a second chance to cast. A
-- reaction that announces a moment of its own, answered from inside the window
-- the first one opened.
function M.test_spellstorm_a_trap_may_open_the_ultimate_window(check)
	opening(3, "omar", "eve")
	become("seat_one")
	local ice = find("trap_ice")
	zones.move_card(ice.id, zone_of("traps", "seat_one").id)
	-- Water beats Fire.
	stage_battle("seat_one", "lapis")
	stage_battle("seat_two", "fireball")
	local junk = #zone_of("discard", "seat_two").cards
	seat_card("seat_one").stats.mana = 9

	actions.execute("activate_zone:rules:by_column:check", {})
	check("the bomb is on offer", #flow.usable_reactions() == 1, #flow.usable_reactions())
	flow.react(ice.id, 1, {})
	check("it gave an ICE", #zone_of("discard", "seat_two").cards == junk + 1,
		#zone_of("discard", "seat_two").cards)
	check("and its own icon opened the Ultimate behind it",
		#flow.usable_reactions() == 1, #flow.usable_reactions())
end

-- The other half: a trap is laid by the Ultimate, and the one coming off is not
-- among the ones offered. That order *is* "you can't play the same Trap twice in
-- a row" — the swap happens on the pick, so the offer was built before it.
function M.test_spellstorm_the_ultimate_swaps_the_trap_that_is_armed(check)
	opening(3, "omar", "eve")
	become("seat_one")
	local armed = zone_of("traps", "seat_one")
	local ice = find("trap_ice")
	zones.move_card(ice.id, armed.id)
	ice.stats.sprung = 1

	-- The offer his Ultimate opens, asked by the card that owns the answer.
	local omar = find("wiz_omar")
	actions.execute("show:trap_pile", { card_id = omar.id })
	local offered = {}
	for _, id in ipairs(zones.find("options").cards) do
		offered[entity.get(id).def_key] = true
	end
	check("only the trap that is not armed is offered",
		offered.trap_mud and not offered.trap_ice,
		tostring(offered.trap_mud) .. "/" .. tostring(offered.trap_ice))

	flow.play_card(find("trap_mud", "options").id, {})
	check("the new trap is armed", entity.get(find("trap_mud").zone_id).key == "traps",
		entity.get(find("trap_mud").zone_id).key)
	check("the old one went back to the pile",
		entity.get(ice.zone_id).key == "trap_pile", entity.get(ice.zone_id).key)
	check("and is no longer spent, so it may be laid again later",
		ice.stats.sprung == 0, ice.stats.sprung)
end


-- **Dodge!** *"You may reveal this when an opponent is dealing damage to you. The
-- first 2 points of damage you take this round are negated."*
--
-- Both halves were filed as missing and neither was. Damage is a moment as soon
-- as the game says so, and every blow in the box comes out of one lambda — so
-- `emit:damaging` announces it and *holds* the landing, which is what puts the
-- shield up before the hit arrives rather than after it.
function M.test_spellstorm_dodge_answers_a_blow_aimed_at_you(check)
	opening(3, "omar", "eve")
	local dodge = find("trap_dodge")
	zones.move_card(dodge.id, zone_of("traps", "seat_one").id)

	become("seat_two")
	local them = stage_battle("seat_two", "fireball2")
	local me = seat_card("seat_one")
	local hp = me.stats.health
	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = them.id })

	become("seat_one")
	check("the blow announced itself", #flow.usable_reactions() == 1,
		#flow.usable_reactions())
	check("and has not landed yet", me.stats.health == hp, me.stats.health)

	flow.react(dodge.id, 1, {})
	check("the two points it stopped were the blow it was revealed against",
		me.stats.health == hp, me.stats.health)
	check("and they were spent stopping it", dodge.stats.guard == 0, dodge.stats.guard)
	check("the trap is spent where it lies",
		dodge.stats.sprung == 1 and entity.get(dodge.zone_id).key == "traps",
		entity.get(dodge.zone_id).key)
end

-- The budget, which is the half this really turned on. `by` takes a number and
-- not a measure, so "the first 2 points" is two shifts of one, each asking
-- whether that much is still there — and the spending is `stat_damage` on the
-- budget itself, which stops at the floor, so a blow bigger than what is left
-- uses up the rest and no more.
--
-- Two verbs, because one would not do: the hit is replaced by a *wound* of the
-- same size, and the shifts are about the wound. A hit that re-dealt itself as a
-- hit would find this same rule on the way down and never arrive.
function M.test_spellstorm_dodge_is_spent_as_it_is_used(check)
	opening(3, "omar", "eve")
	local dodge = find("trap_dodge")
	zones.move_card(dodge.id, zone_of("traps", "seat_one").id)
	dodge.stats.guard = 2
	-- Already revealed, so no window opens and what is left is the aura alone.
	dodge.stats.sprung = 1

	become("seat_two")
	local me = seat_card("seat_one")
	local hp = me.stats.health

	actions.execute("hit:health@opponent:1", {})
	check("one point off two is stopped whole", me.stats.health == hp, me.stats.health)
	check("and one point of it is gone", dodge.stats.guard == 1, dodge.stats.guard)

	actions.execute("hit:health@opponent:3", {})
	check("three against the last point lands two", me.stats.health == hp - 2,
		me.stats.health)
	check("and takes the rest of the shield and no more", dodge.stats.guard == 0,
		dodge.stats.guard)

	actions.execute("hit:health@opponent:2", {})
	check("with nothing left it is an ordinary blow", me.stats.health == hp - 4,
		me.stats.health)
end

-- *This round*: what is left of the shield goes out with the round, the way
-- Obsidian's unspent pass does. And the Trap takes nothing back to the pile — a
-- Trap re-armed with a budget still on it would soak before it was ever revealed.
function M.test_spellstorm_dodge_does_not_keep_past_the_round(check)
	opening(3, "omar", "eve")
	local dodge = find("trap_dodge")
	zones.move_card(dodge.id, zone_of("traps", "seat_one").id)
	dodge.stats.guard = 2

	actions.execute("each_seat:stat_set:guard@mine.traps:0", {})
	check("the round took what was left", dodge.stats.guard == 0, dodge.stats.guard)

	dodge.stats.guard = 2
	dodge.stats.sprung = 1
	become("seat_one")
	local omar = find("wiz_omar")
	actions.execute("show:trap_pile", { card_id = omar.id })
	flow.play_card(find("trap_mud", "options").id, {})
	check("the swapped-out trap went back clean",
		dodge.stats.guard == 0 and dodge.stats.sprung == 0,
		dodge.stats.guard .. "/" .. dodge.stats.sprung)
end


-- **Buddy System.** *"Tier I players `[POWER]`. You `[POWER]` `[MANA]`. You may
-- resolve a different revealed `[EARTH]` card."*
--
-- The last clause was the note on the card, and it was reachable: "revealed" is
-- the battle spots, which `battle` already names across both seats, and "a
-- different one" is `others.` — the pool with the asking card taken out of it. So
-- the card cannot offer itself and nothing has to say which card is meant.
function M.test_spellstorm_buddy_system_offers_the_other_earth_card(check)
	opening(3, "bunny", "eve")
	become("seat_one")
	local buddy = stage_battle("seat_one", "bunny_buddy")

	-- The element is read, not assumed. Buddy System is itself Earth and is the
	-- only Earth card revealed, so `others.` leaves nothing and nothing is asked.
	stage_battle("seat_two", "fireball")
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = buddy.id })
	check("a Fire card opposite is no offer at all", phase.current().key ~= "options",
		phase.current().key)

	stage_battle("seat_two", "twopower")
	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = buddy.id })
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = buddy.id })
	check("an Earth card opposite is", phase.current().key == "options",
		phase.current().key)

	local offered = {}
	for _, id in ipairs(zones.find("options").cards) do
		offered[entity.get(id).def_key] = true
	end
	check("the other seat's revealed Earth card is on offer", offered.twopower,
		tostring(offered.twopower))
	check("and it does not offer itself", not offered.bunny_buddy,
		tostring(offered.bunny_buddy))

	local power = seat_card("seat_one").stats.power
	flow.play_card(find("twopower", "options").id, {})
	check("taking it resolves that card", seat_card("seat_one").stats.power > power,
		seat_card("seat_one").stats.power)
end


-- **Deep Gems.** *"`[DRAW]` `[MANA]`. You may lose 1 Power Token to resolve and
-- then VOID a Water card from the Storm Cloud."*
--
-- The token was never spent. `chosen` has no `cost` — the two things it carries
-- are `where` and `action` — so the price is said with both: the gate is the
-- `where` and the payment is the first thing the answer does. Declining owes
-- nothing, which the optional offer already said.
--
-- And the gate does better than refuse the pick: an offer where nothing may be
-- taken does not open, so with no Power Token he is not asked at all.
function M.test_spellstorm_deep_gems_charges_for_the_answer(check)
	opening(3, "abra", "eve")
	become("seat_one")
	local gems = stage_battle("seat_one", "abra_deepgems")
	local me = seat_card("seat_one")
	me.stats.power = 0

	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = gems.id })
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = gems.id })
	check("with nothing to pay with, nothing is asked",
		phase.current().key ~= "options", phase.current().key)
	check("though the Water card is sitting there",
		find("wateressence", "storm_cloud") ~= nil)

	me.stats.power = 3
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = gems.id })
	check("with a token, he is", phase.current().key == "options", phase.current().key)
	flow.play_card(find("wateressence", "options").id, {})
	check("taking it costs the token", me.stats.power == 2, me.stats.power)
	check("and the card went to the VOID",
		entity.get(find("wateressence").zone_id).key == "void",
		entity.get(find("wateressence").zone_id).key)
end


-- **Ruby.** *"Discard the top 3 cards of your deck. Deal 1 damage per `[FIRE]`
-- card discarded OR you may VOID one of the discarded cards."*
--
-- Nothing named the three cards, because nothing had picked them — so they are
-- given a zone of their own instead of going straight to the discard, and a zone
-- is a name. The other half of the "or" is a card minted into that same zone, so
-- **one question holds all four**: the player reads the three before deciding,
-- and the branch is which card came back.
--
-- That works because a pick leaves the offer holding exactly the card taken —
-- `flow.lua` sends the rest home before the chosen actions run — so `@options`
-- inside `chosen` is the answer and not the question.
--
-- The minted card says what it is worth in its own text. A card's text is filled
-- like any label, so `{stats.counted}` is a number written onto it a step before
-- the question opened.
function M.test_spellstorm_ruby_asks_beside_the_cards_it_is_about(check)
	opening(3, "eve", "abra")
	become("seat_one")
	local ruby = stage_battle("seat_one", "ruby")
	local deck = zone_of("deck", "seat_one")
	for _, id in ipairs({ unpack(deck.cards) }) do zones.move_card(id, zones.find_id("void")) end
	for _, key in ipairs({ "fireball", "twopower", "swampsilt" }) do
		zones.move_card(require("cards").create(key, deck.id).id, deck.id)
	end

	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = ruby.id })
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = ruby.id })
	check("it asks", phase.current().key == "options", phase.current().key)
	check("and the question holds the three cards and the other choice",
		#zones.find("options").cards == 4, #zones.find("options").cards)

	local burn = find("ruby_burn", "options")
	check("the flame counted the Fire among them", burn.stats.counted == 2,
		burn.stats.counted)
	check("and says so in its own text",
		require("label").fill(require("cards").def(burn).text, burn) == "Deal 2 damage",
		require("label").fill(require("cards").def(burn).text, burn))

	local them = seat_card("seat_two")
	local hp, disc = them.stats.health, #zone_of("discard", "seat_one").cards
	flow.play_card(burn.id, {})
	check("taking it deals that much", them.stats.health == hp - 2, them.stats.health)
	check("the three go to the discard", #zone_of("discard", "seat_one").cards == disc + 3,
		#zone_of("discard", "seat_one").cards)
	check("and the flame is gone", find("ruby_burn") == nil)
end

-- The other branch: take one of the three and it is VOIDed, and no damage is
-- dealt. Same question, same cards — only the answer differs.
function M.test_spellstorm_ruby_voids_the_card_you_take_instead(check)
	opening(3, "eve", "abra")
	become("seat_one")
	local ruby = stage_battle("seat_one", "ruby")
	local deck = zone_of("deck", "seat_one")
	for _, id in ipairs({ unpack(deck.cards) }) do zones.move_card(id, zones.find_id("void")) end
	for _, key in ipairs({ "fireball", "twopower", "swampsilt" }) do
		zones.move_card(require("cards").create(key, deck.id).id, deck.id)
	end

	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = ruby.id })
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = ruby.id })
	local them = seat_card("seat_two")
	local hp, disc = them.stats.health, #zone_of("discard", "seat_one").cards
	local picked = find("twopower", "options")
	flow.play_card(picked.id, {})
	check("no damage was dealt", them.stats.health == hp, them.stats.health)
	check("the card taken is VOIDed", entity.get(picked.zone_id).key == "void",
		entity.get(picked.zone_id).key)
	check("the other two go to the discard",
		#zone_of("discard", "seat_one").cards == disc + 2,
		#zone_of("discard", "seat_one").cards)
	check("and the flame is gone", find("ruby_burn") == nil)
	check("leaving nothing behind in the sifting zone",
		#zones.find("sifting").cards == 0, #zones.find("sifting").cards)
end


-- **Diamond.** *"If you hold 3 or more other cards, discard 3 of them and
-- `[POWER]` `[POWER]` `[POWER]`."*
--
-- "Exactly 3, and you pick them" looked like it wanted a number on an offer, and
-- an offer has no word for one: `chosen` says which cards may be taken and never
-- how many. It does not need one. Three offers with no way out *are* a count,
-- and the queue holds them one at a time.
--
-- The gate is the part that could have gone wrong. It reads the hand, and the
-- hand empties under the very questions it gated — but an ability's `when` is
-- read once, before its action list runs, so all three are queued while the hand
-- is still whole and the third does not close behind the second.
function M.test_spellstorm_diamond_discards_three_of_your_choosing(check)
	opening(3, "eve", "abra")
	become("seat_one")
	local diamond = stage_battle("seat_one", "diamond")
	local hand = zone_of("hand", "seat_one")
	for _, id in ipairs({ unpack(hand.cards) }) do zones.move_card(id, zones.find_id("void")) end
	for _, key in ipairs({ "fireball", "twopower", "swampsilt", "sift" }) do
		require("cards").create(key, hand.id)
	end

	local me = seat_card("seat_one")
	local power, disc = me.stats.power, #zone_of("discard", "seat_one").cards
	actions.execute("activate_zone:mine.battle:by_column:cast2", { card_id = diamond.id })
	check("holding four, it asks", phase.current().key == "options", phase.current().key)
	check("it powered up three times", me.stats.power == power + 3, me.stats.power)

	for _, key in ipairs({ "fireball", "twopower", "sift" }) do
		check("and asks again for " .. key, phase.current().key == "options", phase.current().key)
		flow.play_card(find(key, "options").id, {})
	end
	check("three questions, three answers, and it stops asking",
		phase.current().key ~= "options", phase.current().key)
	check("the three named cards went to the discard",
		#zone_of("discard", "seat_one").cards == disc + 3,
		#zone_of("discard", "seat_one").cards)
	check("and the one not named is still held",
		#hand.cards == 1 and require("cards").def(entity.get(hand.cards[1])).key == "swampsilt",
		#hand.cards)
end

-- Holding two, the gate is shut and nothing is asked — not three offers that
-- find nothing, and not two offers and a stuck question.
function M.test_spellstorm_diamond_asks_nothing_when_you_hold_too_few(check)
	opening(3, "eve", "abra")
	become("seat_one")
	local diamond = stage_battle("seat_one", "diamond")
	local hand = zone_of("hand", "seat_one")
	for _, id in ipairs({ unpack(hand.cards) }) do zones.move_card(id, zones.find_id("void")) end
	for _, key in ipairs({ "fireball", "twopower" }) do require("cards").create(key, hand.id) end

	local me = seat_card("seat_one")
	local power = me.stats.power
	actions.execute("activate_zone:mine.battle:by_column:cast2", { card_id = diamond.id })
	check("it asks nothing", phase.current().key ~= "options", phase.current().key)
	check("no power came of it", me.stats.power == power, me.stats.power)
	check("and the hand is untouched", #hand.cards == 2, #hand.cards)
end


-- **Sift.** *"`[POWER]`. Look at the top 2 cards of your deck and put them back
-- in any order."*
--
-- Looking at a card is not holding it, and the difference has a zone now: the
-- two go to `sifting`, which is off-screen until an offer borrows it. The pick
-- goes back to the deck *last*, and a deck takes a card on top, so the card you
-- name is the one you draw next.
--
-- Leaving the order alone is naming the card that was already on top, so the
-- question wants no way out — "may" and "must" are the same question here.
function M.test_spellstorm_sift_names_the_card_you_draw_next(check)
	opening(3, "eve", "abra")
	become("seat_one")
	local sift = stage_battle("seat_one", "sift")
	local deck = zone_of("deck", "seat_one")
	for _, id in ipairs({ unpack(deck.cards) }) do zones.move_card(id, zones.find_id("void")) end
	for _, key in ipairs({ "swampsilt", "twopower", "fireball" }) do
		zones.move_card(require("cards").create(key, deck.id).id, deck.id)
	end

	local me = seat_card("seat_one")
	local power, held = me.stats.power, #zone_of("hand", "seat_one").cards
	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = sift.id })
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = sift.id })
	check("it powered up", me.stats.power == power + 1, me.stats.power)
	check("and asks about two cards", phase.current().key == "options" and
		#zones.find("options").cards == 2, #zones.find("options").cards)

	-- `fireball` is on top and `twopower` under it; naming the lower one turns
	-- them over.
	flow.play_card(find("twopower", "options").id, {})
	check("nothing was drawn", #zone_of("hand", "seat_one").cards == held,
		#zone_of("hand", "seat_one").cards)
	check("both went back to the deck", #deck.cards == 3, #deck.cards)
	check("the card named is on top",
		require("cards").def(entity.get(deck.cards[#deck.cards])).key == "twopower",
		require("cards").def(entity.get(deck.cards[#deck.cards])).key)
	check("the other is under it",
		require("cards").def(entity.get(deck.cards[#deck.cards - 1])).key == "fireball",
		require("cards").def(entity.get(deck.cards[#deck.cards - 1])).key)
	check("and the sifting zone is empty again",
		#zones.find("sifting").cards == 0, #zones.find("sifting").cards)
end


-- **Lava Bat.** *"`[MANA]`. You may move a non-Wizard `[FIRE]` card from any
-- discard to any other discard. Gain `[INIT]`."*
--
-- It only went one way, and took any card. Both halves were ordinary: the
-- direction is two entries, and the filter is the scope plus a `where`. The give
-- direction needs the card to change hands, and `set_owner` says "mine" or
-- "none" and has no word for the other seat — so the other seat is made the one
-- acting for two lines, which is the flip the empty piles already use.
function M.test_spellstorm_lava_bat_can_give_as_well_as_take(check)
	opening(7, "derby", "eve")
	local one = zones.active_seat()
	local two = one == "seat_one" and "seat_two" or "seat_one"

	local mine
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if e.def_key == "magicdart" and z and z.seat == one then mine = e end
	end
	check("they started with a Magic Dart of their own", mine ~= nil)
	zones.move_card(mine.id, zone_of("discard", one).id)

	local lb = stage_battle(one, "lavabat")
	actions.execute("copy:target:activate", { card_id = lb.id, targets = { lb.id } })
	flow.play_card(find("bat_give", "options").id, {})
	check("your own Fire discard comes up", phase.current().key == "options",
		phase.current().key)
	flow.play_card(mine.id, {})
	check("the card is in their discard now",
		entity.get(mine.id).zone_id == zone_of("discard", two).id,
		entity.get(entity.get(mine.id).zone_id).key)
	check("and you are up again", zones.active_seat() == one, zones.active_seat())

	-- And it is theirs now: thrown away from their hand, it goes home to them.
	zones.move_card(mine.id, hand_of(two).id)
	become(two)
	actions.execute("destroy:mine.hand", {})
	check("thrown away again, it stays with them",
		entity.get(mine.id).zone_id == zone_of("discard", two).id,
		entity.get(entity.get(mine.id).zone_id).key)
end

-- **Lapis.** *"`[DRAW]`. You may discard up to 2 cards. Heal 1 for each `[WATER]`
-- discarded."*
--
-- "Up to 2" is the question asked twice, the shape Wind Dragon uses. "1 for each
-- Water" rides on the answer: the rule is asked while the card picked is still
-- lying in the offer, which is the one moment it can be counted — and it is
-- asked before the discard, because a card in the discard is no longer in the
-- offer.
function M.test_spellstorm_lapis_heals_for_what_you_actually_discarded(check)
	opening(3, "eve", "abra")
	become("seat_one")
	local lapis = stage_battle("seat_one", "lapis")
	empty_hand("seat_one")
	local hand = hand_of("seat_one")
	for _, key in ipairs({ "lapis", "fireball" }) do
		zones.move_card(require("cards").create(key, hand.id).id, hand.id)
	end
	local me = seat_card("seat_one")
	me.stats.health = 5

	actions.execute("activate_zone:mine.battle:by_column:cast", { card_id = lapis.id })
	actions.execute("activate_zone:mine.battle:by_column:cast_ask", { card_id = lapis.id })
	check("it asks", phase.current().key == "options", phase.current().key)

	flow.play_card(find("fireball", "options").id, {})
	check("a Fire card heals nothing", me.stats.health == 5, me.stats.health)
	check("and it asks again, because it was up to two",
		phase.current().key == "options", phase.current().key)
	flow.play_card(find("lapis", "options").id, {})
	check("a Water card heals one", me.stats.health == 6, me.stats.health)
end


return M
