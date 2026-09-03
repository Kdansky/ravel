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

local entity  = require("entity")
local zones   = require("zones")
local phase   = require("phase")
local flow    = require("flow")
local actions = require("actions")

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
	-- A card reaches a battle spot by being played, which sets its owner along
	-- the way. Moved by hand it keeps whoever last held it, and "enemy.battle"
	-- would then not see it -- so hand it back to the zone it now lies in.
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
	-- Taking a card off the shelf is an ability, and its "when" is the Tier gate.
	phase.push("gain_1")
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
	check("a round opens with the first seat playing", phase.current().key == "play_1",
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
	check("the second seat is up", two ~= one and phase.current().key == "play_2",
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
		if (seen.gain_2 or 0) >= 3 then break end
	end
	check("the battle ran its four rounds and regrouped, three times over",
		(seen.gain_2 or 0) >= 3, tostring(seen.gain_2))
	check("four plays per seat per battle",
		(seen.play_1 or 0) >= 12, tostring(seen.play_1))
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

	phase.push("ult_1")
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
	-- offer from being run over. Stepping back off it is what a routed ult_1
	-- never has to do.
	phase.pop()
	flow.settle()
	-- Six for the Ultimate and one back from it: Derby deals 2 and gains 1.
	check("the Ultimate was paid for and fired", seat_card("seat_one").stats.mana == 4,
		tostring(seat_card("seat_one").stats.mana))
	check("and it hit", seat_card("seat_two").stats.health == hurt - 2,
		("%d, was %d"):format(seat_card("seat_two").stats.health, hurt))
	check("with nothing left waiting", flow.pending_event() == nil)
end


-- The other half of an icon meaning something: a card without one is quiet, and
-- a round of ordinary cards never stops to ask.
function M.test_spellstorm_a_card_without_the_icon_announces_nothing(check)
	opening(7, "derby", "eve")
	seat_card("seat_one").stats.initiative = 1
	seat_card("seat_two").stats.initiative = 0
	stage_battle("seat_one", "block")

	phase.push("ult_1")
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

	actions.execute("stat_set:initiative@mine.player:1", {})
	actions.execute("activate_zone:mine.battle:by_column:cast2", { card_id = rf.id, targets = {} })
	check("with it, the card is back in the hand",
		entity.get(rf.id).zone_id == hand_of(one).id)
	actions.execute("each_seat:move:mine.battle:mine.discard", {})
	check("so the sweep at the end of the round never sees it",
		entity.get(rf.id).zone_id == hand_of(one).id)
end


-- Abragail's journal asks three of its eight questions, and an offer is one at a
-- time: an action list has no cursor, so an ask has to be the last thing a phase
-- does. Each question therefore gets a phase, and each phase one seat -- two
-- Abragails would otherwise hold up both hands into the same offer.
function M.test_spellstorm_the_journal_asks_one_question_at_a_time(check)
	opening(3, "abra", "abra")
	for _, k in ipairs({ "seat_one", "seat_two" }) do seat_card(k).stats.research = 8 end

	actions.execute("each_seat:activate_zone:rules:by_column:bstart", {})
	check("the silent spaces fire in the battle-start sweep and ask nothing",
		phase.current().key ~= "options", phase.current().key)

	local held = #hand_of("seat_one").cards + #hand_of("seat_two").cards
	phase.push("journal_2a")
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
	check("with nothing lost on the way",
		#hand_of("seat_one").cards + #hand_of("seat_two").cards == held)
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
	for _, z in ipairs(zones.all_with_key("controls")) do
		for _, id in ipairs(z.cards) do
			if entity.get(id).def_key == "btn_potion_draw" then draw = id end
		end
	end
	check("the draw button is reachable, and only here", draw ~= nil and #flow.usable_abilities(draw) == 1)

	local sips, guard = 0, 0
	while phase.current().key ~= "play_1" and guard < 40 do
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
		phase.current().key == "play_1", phase.current().key)
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
	for _, id in ipairs({ unpack(shelf.cards) }) do zones.destroy_card(id) end
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
	for _, pair in ipairs({ { "derby", "eve" }, { "derby", "derby" }, { "may", "may" } }) do
		opening(5, pair[1], pair[2])
		local held = seat_card("seat_one").stats.initiative
			+ seat_card("seat_two").stats.initiative
		check(pair[1] .. " v " .. pair[2] .. ": exactly one holds it", held == 1, held)
	end
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
	for _, key in ipairs({ "wizard", "hand", "deck", "discard", "battle", "commit" }) do
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
	for _, id in ipairs({ unpack(shelf.cards) }) do zones.destroy_card(id) end
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
	actions.execute("show:mine.everywhere.curse_or_ice_held:optional",
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

return M
