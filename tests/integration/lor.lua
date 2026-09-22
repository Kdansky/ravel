-- Runeterra, milestone 1: the board, the round, and combat on the lanes.
--
-- Every board game gets a scripted test ([01](ideas/01-boardgames.md)). This one
-- covers the round loop — both seats draw and refill, playing a unit hands
-- priority over, a round ends on two passes *in succession* — and then the
-- fight: attackers and blockers are **placements**, a lane is the pairing, and
-- what a unit does when the lanes are walked is a rule written on the zone
-- rather than on any of the ten templates.
--
-- The deck is a mirror — both seats play the same ten templates — so an
-- asymmetric result here is a bug rather than a matter of opinion.

local entity = require("entity")
local zones = require("zones")
local cards = require("cards")
local flow = require("flow")
local phase = require("phase")
local predicate = require("predicate")
local targeting = require("targeting")
local tags = require("tags")
local actions = require("actions")
local declaration = require("declaration")
local stats       = require("stats")

local M = {}

local function zone_of(key, seat)
	for _, z in ipairs(zones.all_with_key(key)) do
		if z.seat == seat then return z end
	end
end

local function stat(seat, key)
	return predicate.total(key .. "@" .. seat .. "_side")
end

-- Each seat has its own controls, beside its own deck, so a button is that
-- seat's by the zone it was dealt into rather than by anything the file says.
local function button(def_key, seat)
	for _, z in ipairs(zones.all_with_key("controls")) do
		for _, id in ipairs(z.cards) do
			local e = entity.get(id)
			if e.def_key == def_key and predicate.owner_of(e) == seat then return e.id end
		end
	end
end

-- Passing is a card on the table with a flag on it, so this is an ordinary
-- activation of an ordinary card — there is nothing here the engine knows about.
--
-- The flag is cleared in one place, the "hand_over" phase, and the trick is that
-- it clears the **enemy's**. That phase runs after the round-end check and before
-- the seat rotates, so "enemy" there is the player whose turn is about to begin:
-- clearing their pass is exactly "your pass only counts until you act again".
local function pass()
	return flow.activate(button("pass_button", zones.active_seat()), {})
end

local function passed()
	return predicate.total("count:passed")
end

-- The squares this unit's *own* ability offers right now, asked through the game
-- file's own target spec rather than a copy of it — so a test of "which lanes
-- may I enter" is a test of what the file says and not of what this file thinks
-- it says.
local function lanes(card_id)
	local u = flow.usable_abilities(card_id)[1]
	return u and targeting.candidates(card_id, u.rule.target) or {}
end

local function bench_put(seat, key, col)
	local b = zone_of("bench", seat)
	local c = cards.create(key, b.id)
	zones.place_in_slot(c.id, b.slots[col])
	return c.id
end

local function on_bench(seat, key)
	for _, id in ipairs(zone_of("bench", seat).cards) do
		if entity.get(id).def_key == key then return entity.get(id) end
	end
end

-- Blocks settle and then both seats are asked again, which is where a fast spell
-- lives. Two passes in succession carry the lanes into the strike, exactly as
-- two carry a round to its end — the same pass button, counted the same way.
local function resolve()
	flow.activate(button("pass_button", zones.active_seat()), {})
	flow.activate(button("pass_button", zones.active_seat()), {})
end

-- One rigged combat: north attacks with `atk`, south blocks with `blk` or lets
-- it through. Both seats' hands are emptied first, so nothing but the fight can
-- move. North holds the attack token in round one.
--
-- `before` runs with the two cards once both are in their lanes and before the
-- last pass resolves them, which is the only moment a test can rig a number the
-- strike is about to read.
local function fight(atk_key, blk_key, before)
	flow.init("lor.json", 5)
	for _, seat in ipairs({ "north", "south" }) do
		local h = zone_of("hand", seat)
		for i = #h.cards, 1, -1 do zones.purge_card(h.cards[i]) end
	end
	local a = bench_put("north", atk_key, 1)
	local b = blk_key and bench_put("south", blk_key, 1)

	flow.activate(button("attack_button", "north"), {})
	flow.activate(a, { lanes(a)[1] })
	flow.activate(button("pass_button", "north"), {})
	if b then flow.activate(b, { lanes(b)[1] }) end
	if before then before(a, b) end
	flow.activate(button("pass_button", "south"), {})
	resolve()
	return a, b
end

function M.test_lor_the_opening_deals_four_and_the_round_deals_one(check)
	flow.init("lor.json", 5)
	check("north is up", zones.active_seat() == "north")
	check("both hands hold the opening four plus round one's card",
		#zone_of("hand", "north").cards == 5 and #zone_of("hand", "south").cards == 5,
		("%d / %d"):format(#zone_of("hand", "north").cards, #zone_of("hand", "south").cards))
	check("and both decks of forty are five lighter",
		#zone_of("deck", "north").cards == 35 and #zone_of("deck", "south").cards == 35,
		("%d / %d"):format(#zone_of("deck", "north").cards, #zone_of("deck", "south").cards))
	check("each seat has a pass button and an attack button of its own, on its own side",
		#zone_of("controls", "north").cards == 2 and #zone_of("controls", "south").cards == 2)
	check("and they belong to that seat because of where they were dealt",
		predicate.owner_of(entity.get(zone_of("controls", "north").cards[1])) == "north"
		and predicate.owner_of(entity.get(zone_of("controls", "south").cards[1])) == "south")

	-- Whose button it is does the gating, which is the ordinary ownership rule
	-- and not something passing had to be taught.
	check("north may use its own pass button and not the other one",
		flow.can_activate(button("pass_button", "north"))
		and flow.can_activate(button("pass_button", "south")) == false)

	-- Mana is the round number, which is what makes it rise by one a round and
	-- stop at ten: the stat's own max does the capping.
	check("both seats have one mana in round one",
		stat("north", "mana") == 1 and stat("south", "mana") == 1)
	check("and twenty nexus each", stat("north", "nexus") == 20 and stat("south", "nexus") == 20)

	-- Six lanes a side, one shared grid: an attacker and the unit across from it
	-- are the same column of a 6x2 board, which is the whole of the pairing.
	check("the battlefield is six lanes deep on both sides", #zones.find("battle").slots == 12)
end

-- A cost is measured and paid through a *subject*, and with two seats it has to
-- be: written as a bare "mana" the engine reads the pool of both players' mana
-- and takes the amount off whichever card came first in the file. South could
-- buy a three-drop out of north's gems, which no test of a solo game could see.
function M.test_lor_a_unit_is_paid_for_by_the_seat_that_plays_it(check)
	flow.init("lor.json", 5)
	pass()
	for e in entity.each("card") do
		if e.def_key == "north" then e.stats.mana = 9 end
		if e.def_key == "south" then e.stats.mana = 9 end
	end
	local card = zone_of("hand", "south").cards[1]
	local cost = entity.get(card).stats.cost

	check("south plays out of its own hand", zones.active_seat() == "south"
		and flow.play_card(card, { zone_of("bench", "south").slots[1] }))
	check("south paid", stat("south", "mana") == 9 - cost,
		("%d, expected %d"):format(stat("south", "mana"), 9 - cost))
	check("and north paid nothing", stat("north", "mana") == 9, tostring(stat("north", "mana")))
end

function M.test_lor_a_round_ends_on_two_passes_in_succession(check)
	flow.init("lor.json", 5)
	check("north passes, and the round does not end yet", pass()
		and passed() == 1 and phase.current().key == "play")
	check("south passes after it, and the round turns", pass()
		and predicate.total("max:round") == 2)
	check("the count is back to nothing", passed() == 0)
	check("mana refilled to the new round's gems for both",
		stat("north", "mana") == 2 and stat("south", "mana") == 2)
	check("and the attack token has changed hands",
		stat("north", "attacker") == 0 and stat("south", "attacker") == 1)
end

-- Anything happening between two passes means they were not in succession.
function M.test_lor_a_play_between_two_passes_keeps_the_round(check)
	flow.init("lor.json", 5)
	check("north passes", pass())
	-- Enough mana that the play can only be refused for the reason under test:
	-- what south drew is the shuffle's business, and this is about the count.
	for e in entity.each("card") do
		if e.def_key == "south" then e.stats.mana = 9 end
	end
	check("south plays instead of passing",
		flow.play_card(zone_of("hand", "south").cards[1], { zone_of("bench", "south").slots[1] }))
	check("which clears the count", passed() == 0)
	check("north passes again", pass())
	check("and it is still round one", predicate.total("max:round") == 1,
		tostring(predicate.total("max:round")))
end

-- The token is a stat somebody holds and an attack spends it, so "once a round"
-- needs no counter: the cost is the rule.
function M.test_lor_only_the_token_holder_may_attack(check)
	flow.init("lor.json", 5)
	check("north holds this round's token", stat("north", "token") == 1 and stat("south", "token") == 0)
	check("and north's attack button is live", flow.can_activate(button("attack_button", "north")))
	check("south's is not — it is not south's turn, nor south's token",
		flow.can_activate(button("attack_button", "south")) == false)

	check("north declares", flow.activate(button("attack_button", "north"), {}))
	check("which opens the attackers phase without handing over",
		phase.current().key == "declare_attack" and zones.active_seat() == "north")
	check("and spends the token", stat("north", "token") == 0)
end

-- A lane is the pairing, so where a unit may stand *is* the rule: your own row,
-- and — blocking — opposite something that is already attacking.
function M.test_lor_a_blocker_may_only_meet_an_attacker(check)
	flow.init("lor.json", 5)
	local a = bench_put("north", "cithria", 1)
	local b = bench_put("south", "cithria", 1)

	flow.activate(button("attack_button", "north"), {})
	check("an attacker may pick any of its own six lanes", #lanes(a) == 6, tostring(#lanes(a)))
	local chosen = lanes(a)[1]
	check("it goes out", flow.activate(a, { chosen }))
	check("into north's own row of the battlefield",
		entity.get(entity.get(a).slot_id).stats.row == 2)

	flow.activate(button("pass_button", "north"), {})
	check("south is asked to block", phase.current().key == "declare_block"
		and zones.active_seat() == "south")
	check("and has exactly one lane to block into — the one opposite the attacker",
		#lanes(b) == 1, tostring(#lanes(b)))
	check("which is south's own row, in the attacker's column",
		entity.get(lanes(b)[1]).stats.row == 1
		and entity.get(lanes(b)[1]).stats.col == entity.get(chosen).stats.col)
end

function M.test_lor_an_unblocked_attacker_hits_the_nexus(check)
	fight("cithria", nil)
	check("two power lands on the nexus", stat("south", "nexus") == 18, tostring(stat("south", "nexus")))
	check("north's nexus is untouched", stat("north", "nexus") == 20)
	check("and the attacker comes home to its own bench",
		on_bench("north", "cithria") ~= nil and #zone_of("bench", "south").cards == 0)
	check("the battlefield is empty again", #zones.find("battle").cards == 0)
	-- Back in the play phase without the seat moving: after_combat routes there
	-- with seat "same", where it used to need a second phase key to say so.
	check("and it is the other seat's move", phase.current().key == "play"
		and zones.active_seat() == "south")
end

function M.test_lor_a_blocked_attacker_hits_the_blocker(check)
	fight("cithria", "cithria")
	check("nothing reaches either nexus",
		stat("south", "nexus") == 20 and stat("north", "nexus") == 20)
	check("and two twos trade", on_bench("north", "cithria") == nil
		and on_bench("south", "cithria") == nil)
end

-- Tough is a tag the game file gives a card, and it does not *do* anything: it
-- says that damage arriving at this card arrives for one less. Nothing in the
-- engine knows the word, and nothing in the game runs on its behalf.
function M.test_lor_tough_takes_one_off_every_source(check)
	fight("vanguard_lookout", "plucky_poro")
	local poro, look = on_bench("south", "plucky_poro"), on_bench("north", "vanguard_lookout")
	check("a one-power hit does nothing at all to a tough one-health blocker",
		poro ~= nil and poro.stats.health == 1, poro and tostring(poro.stats.health) or "dead")
	check("while the attacker takes its one", look ~= nil and look.stats.health == 3,
		look and tostring(look.stats.health) or "dead")

	fight("cithria", "vanguard_defender")
	local def = on_bench("south", "vanguard_defender")
	check("and two into a tough two-health blocker leaves it standing on one",
		def ~= nil and def.stats.health == 1, def and tostring(def.stats.health) or "dead")
	check("with the attacker dead", on_bench("north", "cithria") == nil)
	check("and no spill, because it has no overwhelm", stat("south", "nexus") == 20)
end

-- The case the arithmetic has to survive. Tough was once a point handed *back*
-- after the strike landed, so a source with no power healed what it hit — right
-- for every printed card, since none has zero power, and a lie the moment
-- anything deals damage equal to a count. An adjustment cannot make that
-- mistake: it may not change the sign of what it shifts, so nothing reduced
-- past zero comes out the other side as healing.
function M.test_lor_tough_never_heals_what_hits_it(check)
	local atk = fight("cithria", "plucky_poro", function(a) entity.get(a).stats.power = 0 end)
	local poro = on_bench("south", "plucky_poro")
	check("a strike with no power behind it leaves a tough blocker exactly where it was",
		poro ~= nil and poro.stats.health == 1, poro and tostring(poro.stats.health) or "dead")
	check("and the blocker still hits back", (on_bench("north", "cithria") or {}).stats.health == 1,
		tostring((on_bench("north", "cithria") or {}).stats.health))
	check("nothing was healed past where it started",
		poro.stats.health <= 1 and entity.get(atk).stats.health <= 2)

	-- A keyword that changes a number is not an ability, so there was never
	-- anything for the player to be offered. It used to be an ability fenced
	-- into one phase, and the fence was the whole of what kept it off the bench.
	flow.init("lor.json", 5)
	local benched = bench_put("north", "plucky_poro", 2)
	flow.activate(button("attack_button", "north"), {})
	local offered = flow.usable_abilities(benched)
	check("a tough unit waiting to attack is offered one thing, not two",
		#offered == 1 and offered[1].rule.key == "attack",
		#offered .. " " .. tostring(offered[1] and offered[1].rule.key))
end

-- What the keyword is really keyed to is the *moment*, not the fight. Attacking
-- is one thing that writes damage onto a unit and LoR has spells that write it
-- too, so Tough cannot be a term in the striker's formula without every one of
-- those sources having to remember it. It answers "damage", whoever deals it —
-- and the game says which of its actions are damage, so the two lines that
-- shuffle `incoming` and `spill` about are not and can never be caught by it.
function M.test_lor_anything_that_writes_the_damage_meets_tough(check)
	local hit
	fight("cithria", "plucky_poro", function(_, blk)
		-- No striker anywhere in this: three points written straight onto the
		-- blocker, which is the shape a spell has.
		actions.run({
			"stat_gain:incoming@self:3",
			"activate_zone:battle:by_column:land",
		}, { card_id = blk })
		hit = entity.get(blk).stats.health
	end)
	check("three onto a tough one-health unit takes two of them", hit == -1, tostring(hit))

	-- And the other way round: the engine's own verb is plumbing, so a game that
	-- writes it means a number moving and not a moment happening. Nothing can
	-- reach into it, which is what lets `incoming` and `spill` be shuffled about
	-- in the open without a keyword catching them by accident.
	local raw
	fight("cithria", "plucky_poro", function(_, blk)
		actions.run({ "stat_damage:health@self:3" }, { card_id = blk })
		raw = entity.get(blk).stats.health
	end)
	check("but three written as plain bookkeeping takes all three", raw == -2, tostring(raw))
end

-- Overwhelm is the same shape: a tag, and one more line on the zone. What makes
-- it expressible without a conditional is that the excess is *already* on the
-- board — a blocker struck past zero carries it as negative health.
function M.test_lor_overwhelm_spills_the_excess_into_the_nexus(check)
	fight("alpha_wildclaw", "cithria")
	check("seven into a two-health blocker sends five on", stat("south", "nexus") == 15,
		tostring(stat("south", "nexus")))

	fight("alpha_wildclaw", "plucky_poro")
	check("and tough on the blocker keeps one of them back", stat("south", "nexus") == 15,
		tostring(stat("south", "nexus")))

	fight("mighty_poro", "vanguard_lookout")
	check("a blocker that survives lets nothing through", stat("south", "nexus") == 20,
		tostring(stat("south", "nexus")))
	check("and the overwhelming attacker is still hurt",
		(on_bench("north", "mighty_poro") or {}).stats.health == 2)
end

-- The last thing milestone one owes: somebody wins, and the same state reads as
-- a victory on one machine and a defeat on the other.
-- The two fields that replaced the arithmetic. Overwhelm used to multiply by
-- two stats that are 0 or 1 to say "only an attacker, and only past a corpse";
-- it now says both out loud, and the value it deals has a name.
function M.test_lor_a_when_is_the_rule_and_not_a_permission(check)
	local G = declaration.G
	flow.init("lor.json", 5)
	local ab
	for _, a in ipairs(G.tag_defs.overwhelm.abilities) do
		if a.key == "spill" then ab = a end
	end
	check("overwhelm's spill carries a when and a compute",
		ab ~= nil and type(ab.needs) == "table" and #ab.needs == 2
		and type(ab.compute) == "table" and ab.compute[1] == "overkill")
	check("and no colon-x arithmetic is left in the file",
		#ab.action == 1 and ab.action[1]:find("x", 1, true) == nil, ab.action[1])

	-- The gate is asked of each card as the zone is walked, so a unit that is
	-- not attacking is skipped while its neighbour in the same pass is not.
	local a, b = fight("mighty_poro", "plucky_poro")
	check("the attacker spilled", (a and entity.get(a) or {}).stats == nil
		or entity.get(a).stats.spill ~= nil)
	check("and the blocker never did", b == nil or entity.get(b) == nil
		or (entity.get(b).stats.spill or 0) == 0,
		b and entity.get(b) and tostring(entity.get(b).stats.spill) or "gone")
end

-- A compute is a name for a number and nothing else knows it: it is bound where
-- the ability runs, and a stat of the same name would be two answers to one
-- word — which the validator refuses.
function M.test_lor_a_compute_is_bound_only_where_it_is_named(check)
	flow.init("lor.json", 5)
	local def = declaration.G.compute_defs.overkill
	check("overkill is declared once, with prose", def ~= nil and def.value == "0 - health@across"
		and type(def.tooltip) == "string")
	check("and it is nobody's stat", declaration.G.stat_defs.overkill == nil)

	-- Unbound, the name measures nothing rather than something wrong.
	check("outside an ability that names it, it is not a number anything answers",
		predicate.total("overkill", { card_id = nil }) == 0)

	local outer = { card_id = 1 }
	local ctx = predicate.bind({ "overkill" }, outer)
	check("bound, it is a number", type(ctx.let.overkill) == "number")
	-- An ability's bindings are its own. One that ran inside another's action
	-- list would otherwise leak a name back out of it.
	check("and binding never writes the ctx it was handed", outer.let == nil)
	check("while the card it was asked about comes along", ctx.card_id == 1)
end

function M.test_lor_a_nexus_at_zero_ends_it(check)
	flow.init("lor.json", 5)
	for e in entity.each("card") do
		if e.def_key == "south" then e.stats.nexus = 2 end
	end
	local a = bench_put("north", "cithria", 1)
	flow.activate(button("attack_button", "north"), {})
	flow.activate(a, { lanes(a)[1] })
	flow.activate(button("pass_button", "north"), {})
	flow.activate(button("pass_button", "south"), {})
	resolve()

	check("south's nexus falls", stat("south", "nexus") == 0, tostring(stat("south", "nexus")))
	check("north is written down as the winner",
		stat("north", "won") == 1 and stat("south", "won") == 0)
	check("and the ending is on the table", phase.current().key == "reveal")

	local was = zones.viewer
	zones.viewer = "north"
	check("north is told it won", flow.outcome() == "victory")
	zones.viewer = "south"
	check("south is told it lost", flow.outcome() == "defeat")
	zones.viewer = nil
	check("and with nobody in either chair the room is simply told who won",
		flow.outcome() == "decided" and flow.winner() == "North")
	zones.viewer = was
end

-- Strikes resolve left to right by board position (lor/rules.md), and on a
-- battlefield that is by *lane*: a1 a2, then b1 b2, and so on. That is a rule of
-- this game, so it is written in this game's file — the "lanes" pattern names
-- the twelve squares in the order they resolve, and the engine walks what it is
-- given. Reading the grid row by row would resolve one whole side and then the
-- other, which is a different game and nothing in the engine should prefer either.
function M.test_lor_the_lanes_resolve_left_to_right(check)
	flow.init("lor.json", 5)
	for _, seat in ipairs({ "north", "south" }) do
		local h = zone_of("hand", seat)
		for i = #h.cards, 1, -1 do zones.purge_card(h.cards[i]) end
	end
	-- Two attackers and two blockers, so there are two lanes to order.
	local a1 = bench_put("north", "vanguard_lookout", 1)
	local a2 = bench_put("north", "vanguard_lookout", 2)
	local b1 = bench_put("south", "vanguard_lookout", 1)
	local b2 = bench_put("south", "vanguard_lookout", 2)

	-- Pick the lane by its column: which of the offered slots that is depends on
	-- what is already standing out there.
	local function lane(id, col)
		for _, sid in ipairs(lanes(id)) do
			if entity.get(sid).stats.col == col then return sid end
		end
	end
	flow.activate(button("attack_button", "north"), {})
	flow.activate(a1, { lane(a1, 1) })
	flow.activate(a2, { lane(a2, 2) })
	flow.activate(button("pass_button", "north"), {})
	flow.activate(b1, { lane(b1, 1) })
	flow.activate(b2, { lane(b2, 2) })

	-- The strike is four passes over the same zone and each of them is walked in
	-- this order, so the pass to watch is the one a player sees: the landing.
	local acted = {}
	local was = actions.on_act
	actions.on_act = function(id, ordinal, step)
		if id and step == "land" then
			acted[#acted + 1] = { col = entity.get(entity.get(id).slot_id).stats.col, beat = ordinal }
		end
	end
	flow.activate(button("pass_button", "south"), {})
	resolve()
	actions.on_act = was

	check("all four struck", #acted == 4, tostring(#acted))
	check("the first lane goes first, both of it",
		acted[1].col == 1 and acted[2].col == 1,
		("%s, %s"):format(tostring(acted[1] and acted[1].col), tostring(acted[2] and acted[2].col)))
	check("then the second", acted[3].col == 2 and acted[4].col == 2)
	-- The beat is the place in the order the *file* named, which is what the
	-- presentation spaces its bursts out by. It counts acts rather than lanes,
	-- because with the order authored the engine no longer knows what a lane is.
	check("and the beat counts along that order",
		acted[1].beat == 1 and acted[2].beat == 2 and acted[3].beat == 3 and acted[4].beat == 4,
		("%d %d %d %d"):format(acted[1].beat, acted[2].beat, acted[3].beat, acted[4].beat))
end

-- A keyword is a tag with a meaning, and the meaning is written once. Ten
-- templates carried their own copy of what Tough does before this, which is ten
-- chances for one of them to drift.
function M.test_lor_a_keyword_says_what_it_means_in_one_place(check)
	flow.init("lor.json", 5)
	local cards = require("cards")
	local poro = bench_put("north", "plucky_poro", 1)
	local kw = cards.keywords(entity.get(poro))
	check("the tough unit inherits the sentence", #kw == 1 and kw[1].tag == "tough",
		tostring(#kw))
	check("and it is the game's, not the card's",
		kw[1].text:find("1 less damage", 1, true) ~= nil
		and (declaration.G.card_defs.plucky_poro.tooltip or "") == "",
		tostring(declaration.G.card_defs.plucky_poro.tooltip))

	local raider = bench_put("north", "ruthless_raider", 2)
	check("a unit with two keywords gets both, in the order it declared them",
		#cards.keywords(entity.get(raider)) == 2)

	check("and a unit with none gets none",
		#cards.keywords(entity.get(bench_put("north", "cithria", 3))) == 0)
end

-- The two numbers the whole game turns on used to be readable only in the HUD,
-- and the HUD answers for the seat *watching* — so a hot-seat player could not
-- see what they were attacking into. A seat card is an ordinary card and a zone
-- is an ordinary zone; the only thing the engine had to be told is where.
function M.test_lor_each_seat_has_a_nexus_on_the_table(check)
	flow.init("lor.json", 5)
	-- One zone with a rect each, not two zones: a seat's own card is the one
	-- thing a per-seat zone places rather than clones, so the plate that holds
	-- it is also the plate that knows whose it is.
	for _, seat in ipairs({ "north", "south" }) do
		local z
		for _, inst in ipairs(zones.all_with_key("seat_box")) do
			if inst.seat == seat then z = inst end
		end
		check(seat .. " has a plate of its own", z ~= nil and #z.cards == 1)
		local e = z and z.cards[1] and entity.get(z.cards[1])
		check("holding that seat's card", e ~= nil and e.def_key == seat)
		check("with the two numbers on it", e ~= nil and e.stats.nexus == 20 and e.stats.mana ~= nil)
	end
	-- Badges are drawn for a card in a grid zone and nowhere else, so a plate
	-- that stopped being a grid would go blank without failing anything above.
	check("the plates are grids, which is what draws a badge",
		declaration.G.zone_defs.seat_box.layout == "grid")
	check("and the card claims the style that names the badges",
		declaration.G.card_defs.north.tags_set.nexus_plate == true)

	-- The seats are placed by setup rather than by the engine's own prepend, and
	-- that must not reorder the cards it creates: an entity ID is handed out in
	-- creation order and a seed only replays a board built the same way twice.
	local seats = {}
	for _, e in ipairs(declaration.G.setup_place) do seats[#seats + 1] = e.card end
	check("and they are still created before the buttons",
		seats[2] == "north" and seats[3] == "south", table.concat(seats, ","))
end

-- ---------------------------------------------------------------------------
-- Spells
--
-- A spell is a card in hand with a play and no board to land on: it resolves,
-- and `spent` files it in the caster's own discard. Nothing in the engine knows
-- the word — "spell" is a tag this game wears so a rule may one day ask.
--
-- The three speeds are a question of *when*, so each is the phase list its
-- cards carry. Burst leaves the phase alone and the caster keeps the
-- initiative; fast and slow end it, which is this game's whole notion of
-- handing over. Text, cost and speed are Riot's, from ideas/lor/data.

local function hand_put(seat, key)
	local h = zone_of("hand", seat)
	return cards.create(key, h.id).id
end

local function rich(n)
	for e in entity.each("card") do
		if e.def_key == "north" or e.def_key == "south" then e.stats.mana = n or 10 end
	end
end

local function empty_hands()
	for _, seat in ipairs({ "north", "south" }) do
		local h = zone_of("hand", seat)
		for i = #h.cards, 1, -1 do zones.purge_card(h.cards[i]) end
	end
end

local function seat_card(seat)
	for e in entity.each("card") do
		if e.def_key == seat then return e.id end
	end
end

local function in_discard(seat, key)
	for _, id in ipairs(zone_of("discard", seat).cards) do
		if entity.get(id).def_key == key then return entity.get(id) end
	end
end

-- The two halves of Death's Hand are two lines, and the unit it kills takes the
-- same road out as one killed by a strike: into its own seat's discard, not the
-- caster's and not out of the game.
function M.test_lor_a_spell_resolves_and_is_filed_by_whose_it_is(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local poro = bench_put("south", "mighty_poro", 1)
	check("north casts it at a unit across the table",
		flow.play_card(hand_put("north", "deaths_hand"), { poro }))
	check("two damage on the unit", entity.get(poro).stats.health == 1,
		tostring(entity.get(poro).stats.health))
	check("and one on the nexus behind it", stat("south", "nexus") == 19,
		tostring(stat("south", "nexus")))
	check("three mana spent", stat("north", "mana") == 7, tostring(stat("north", "mana")))
	check("the spell is in north's discard and nowhere else",
		in_discard("north", "deaths_hand") ~= nil and #zone_of("discard", "south").cards == 0)

	-- 18 expected this to cost a move of `land` from the battle zone onto the
	-- unit tag, because combat was the only thing that could write damage. It
	-- did not: a spell writes through the `damage` verb itself, and Tough is
	-- about that verb rather than about the step combat happens to use — so a
	-- keyword written for the lanes answers a spell on the bench for free.
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local def = bench_put("south", "vanguard_defender", 1)
	flow.play_card(hand_put("north", "deaths_hand"), { def })
	check("tough on a benched unit takes one off a spell too",
		entity.get(def).stats.health == 1, tostring(entity.get(def).stats.health))
end

function M.test_lor_a_unit_killed_by_a_spell_lands_in_its_owner_s_discard(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local poro = bench_put("south", "mighty_poro", 1)
	flow.play_card(hand_put("north", "vengeance"), { poro })
	check("the unit is off the bench", on_bench("south", "mighty_poro") == nil)
	check("and lying in south's discard, though north killed it",
		in_discard("south", "mighty_poro") ~= nil and in_discard("north", "mighty_poro") == nil)

	flow.init("lor.json", 5)
	empty_hands()
	rich()
	bench_put("north", "cithria", 1)
	bench_put("south", "plucky_poro", 1)
	flow.play_card(hand_put("north", "avalanche"), {})
	check("a board wipe spares nobody's side", on_bench("north", "cithria") == nil)
	check("and files each corpse with its own seat",
		in_discard("north", "cithria") ~= nil and in_discard("south", "plucky_poro") ~= nil)
end

-- Burst is the one that does not end the phase, and that is the only difference
-- between it and the other two.
function M.test_lor_burst_keeps_the_initiative_and_slow_hands_over(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local ally = bench_put("north", "cithria", 1)
	flow.play_card(hand_put("north", "radiant_strike"), { ally })
	check("after a burst spell north is still up",
		zones.active_seat() == "north" and phase.current().key == "play")

	flow.play_card(hand_put("north", "decimate"), {})
	check("after a slow one it is south's move",
		zones.active_seat() == "south" and phase.current().key == "play", zones.active_seat())
	check("which also cleared the pass count, as any play does", passed() == 0)
end

-- The phase list is the speed. Nothing else enforces it and nothing else has to
-- — which is why blocks settling into a window of their own is what made "fast"
-- mean anything here at all.
function M.test_lor_speed_is_the_list_of_phases_a_spell_may_be_cast_in(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local atk = bench_put("north", "cithria", 1)
	local blk = bench_put("south", "cithria", 1)
	local burst = hand_put("south", "elixir_of_iron")
	local fast = hand_put("south", "vengeance")
	local slow = hand_put("south", "avalanche")

	flow.activate(button("attack_button", "north"), {})
	flow.activate(atk, { lanes(atk)[1] })
	flow.activate(button("pass_button", "north"), {})
	check("south is choosing blocks", phase.current().key == "declare_block")
	check("and may still reach for a burst spell while it does",
		flow.can_play(burst) and flow.can_play(fast) == false and flow.can_play(slow) == false)

	flow.activate(blk, { lanes(blk)[1] })
	flow.activate(button("pass_button", "south"), {})
	check("blocks settle into a window where both seats are asked again",
		phase.current().key == "combat_response" and zones.active_seat() == "north")
	flow.activate(button("pass_button", "north"), {})
	check("where south may cast burst and fast, and not slow",
		flow.can_play(burst) and flow.can_play(fast) and flow.can_play(slow) == false)
end

-- The combat trick, which is the whole reason the window exists: two health lent
-- to a blocker after the blocks are locked in, and the attacker bounces off it.
function M.test_lor_a_burst_trick_lands_after_the_blocks_are_locked_in(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local atk = bench_put("north", "cithria", 1)
	local blk = bench_put("south", "cithria", 1)
	flow.activate(button("attack_button", "north"), {})
	flow.activate(atk, { lanes(atk)[1] })
	flow.activate(button("pass_button", "north"), {})
	flow.activate(blk, { lanes(blk)[1] })
	flow.activate(button("pass_button", "south"), {})
	flow.activate(button("pass_button", "north"), {})

	check("south answers with the elixir", flow.play_card(hand_put("south", "elixir_of_iron"), { blk }))
	check("which does not hand the window over", zones.active_seat() == "south")
	flow.activate(button("pass_button", "south"), {})
	check("two passes carry the lanes into the strike", phase.current().key == "play")
	check("the blocker lived on the borrowed health", on_bench("south", "cithria") ~= nil)
	check("and traded the attacker for nothing", on_bench("north", "cithria") == nil)
end

-- "Give" lasts a round and "Grant" does not end, so they are two stats rather
-- than one with a rule about it — which is Runeterra's own distinction, printed
-- on the cards in those two words.
function M.test_lor_given_expires_with_the_round_and_granted_does_not(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local a = bench_put("north", "cithria", 1)
	local b = bench_put("north", "cithria", 2)
	flow.play_card(hand_put("north", "elixir_of_iron"), { a })
	check("two health lent", stats.current(entity.get(a), "health") == 4,
		tostring(stats.current(entity.get(a), "health")))
	flow.play_card(hand_put("north", "bloodsworn_pledge"), { a, b })
	check("and three granted on top", stats.current(entity.get(a), "health") == 7,
		tostring(stats.current(entity.get(a), "health")))
	check("to both of the two allies it named", stats.current(entity.get(b), "health") == 5,
		tostring(stats.current(entity.get(b), "health")))

	pass()
	pass()
	check("the round turned", predicate.total("max:round") == 2)
	check("the lent health went back and the granted stayed",
		stats.current(entity.get(a), "health") == 5, tostring(stats.current(entity.get(a), "health")))
end

-- The trap the round's heal answers: a unit kept alive by borrowed health would
-- fall over the moment the round called the loan in. Runeterra clears the
-- damage between rounds too, so the two happen in one place and in that order.
function M.test_lor_a_round_heals_what_a_spell_hurt(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local a = bench_put("south", "cithria", 1)
	pass()
	flow.play_card(hand_put("south", "fury_of_the_north"), { a })
	check("a two-health unit is holding six", stats.current(entity.get(a), "health") == 6,
		tostring(stats.current(entity.get(a), "health")))
	pass()
	flow.play_card(hand_put("north", "deaths_hand"), { a })
	flow.play_card(hand_put("south", "warning_shot"), {})
	flow.play_card(hand_put("north", "deaths_hand"), { a })
	check("four damage into it and it is still standing on two",
		stats.current(entity.get(a), "health") == 2, tostring(stats.current(entity.get(a), "health")))

	pass()
	pass()
	check("the loan is called in and the unit is still there",
		on_bench("south", "cithria") ~= nil)
	check("back at what it is printed with", entity.get(a).stats.health == 2,
		tostring(entity.get(a).stats.health))
end

-- Rally is the attack token handed back, which the file already had a stat for:
-- the attack button's cost is the whole of "once a round", so undoing it is one
-- line and nothing else had to learn the word.
function M.test_lor_rally_gives_the_attack_back(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local a = bench_put("north", "cithria", 1)
	flow.activate(button("attack_button", "north"), {})
	flow.activate(a, { lanes(a)[1] })
	flow.activate(button("pass_button", "north"), {})
	flow.activate(button("pass_button", "south"), {})
	resolve()
	check("north attacked and spent the token",
		stat("north", "token") == 0 and stat("south", "nexus") == 18,
		tostring(stat("south", "nexus")))
	pass()

	check("north casts the rally", flow.play_card(hand_put("north", "relentless_pursuit"), {}))
	check("which puts the token back", stat("north", "token") == 1)
	check("and only north's — a rally is not a rule about both seats",
		stat("south", "token") == 0)
	pass()
	check("so north may attack a second time this round",
		flow.can_activate(button("attack_button", "north")))
end

-- A "where" is asked of each candidate with that one as @target, so the gate is
-- the card's own sentence rather than a list the file has to keep in step.
--
-- It reads the power the card *has*, not the one printed on it. That cost a fix:
-- predicate.holds' "each" branch read e.stats[arg] straight where every other
-- read goes through tags.stat, and a bare @target parses as quant "each" — so
-- this offered a unit Elixir of Wrath had lifted to 4, while sum:power@target
-- answered correctly about the same card.
function M.test_lor_culling_strike_reads_the_power_off_each_candidate(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local small = bench_put("north", "mighty_poro", 1)
	bench_put("north", "alpha_wildclaw", 2)
	local cull = hand_put("south", "culling_strike")
	local spec = declaration.G.card_defs.culling_strike.play.target
	check("three power is within its reach and seven is not",
		#targeting.candidates(cull, spec) == 1, tostring(#targeting.candidates(cull, spec)))
	check("and the one it offers is the small one", targeting.candidates(cull, spec)[1] == small)

	-- The buff is the case the read site was getting wrong, and it is the one a
	-- player meets: three power lifted out of reach is what Elixir of Wrath is
	-- for, and the spell has to see it.
	flow.play_card(hand_put("north", "elixir_of_wrath"), { small })
	check("a spell that lifts its power carries it out of reach",
		#targeting.candidates(cull, spec) == 0, tostring(#targeting.candidates(cull, spec)))
	check("and the same question asked the other way agrees",
		predicate.meets_all({ "sum:power@target <= 3" }, { targets = { small } }) == false)

	pass()
	pass()
	check("when the round takes the power back it is killable again",
		#targeting.candidates(cull, spec) == 1, tostring(#targeting.candidates(cull, spec)))

	-- A new round refills mana to the round number, which is two here.
	rich()
	while zones.active_seat() ~= "south" do pass() end
	check("south kills it outright", flow.play_card(cull, { small }))
	check("into north's discard", in_discard("north", "mighty_poro") ~= nil)
end

-- Fast, and about the battlefield rather than the board, so the only moment it
-- reads anything is the window the blocks open.
function M.test_lor_death_lotus_reaches_only_what_is_in_the_lanes(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local atk = bench_put("north", "cithria", 1)
	local blk = bench_put("south", "plucky_poro", 1)
	local home = bench_put("south", "cithria", 2)
	flow.activate(button("attack_button", "north"), {})
	flow.activate(atk, { lanes(atk)[1] })
	flow.activate(button("pass_button", "north"), {})
	flow.activate(blk, { lanes(blk)[1] })
	flow.activate(button("pass_button", "south"), {})

	check("north casts it in the window", flow.play_card(hand_put("north", "death_lotus"), {}))
	check("the attacker took its own one", entity.get(atk).stats.health == 1,
		tostring(entity.get(atk).stats.health))
	check("tough kept the blocker whole", entity.get(blk) ~= nil and entity.get(blk).stats.health == 1)
	check("and the unit that stayed home was never in it",
		entity.get(home).stats.health == 2, tostring(entity.get(home).stats.health))
end

-- "Deal 2 to anything" is one aim over two kinds of thing, and a Nexus keeps its
-- total under a different name from a unit's. The aim is said once, as a union
-- of the two kinds; the writing is two lines, and a subject names only the cards
-- carrying its stat, so exactly one of them lands on whatever was picked.
function M.test_lor_one_aim_reaches_a_unit_or_a_nexus(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	local mine = bench_put("north", "mighty_poro", 1)
	local theirs = bench_put("south", "mighty_poro", 1)
	local shot = hand_put("north", "mystic_shot")
	local spec = declaration.G.card_defs.mystic_shot.play.target
	check("both units and both Nexuses answer it, and nothing else does",
		#targeting.candidates(shot, spec) == 4, tostring(#targeting.candidates(shot, spec)))
	check("the pass button is not a thing you may shoot",
		flow.can_activate(button("pass_button", "north")))

	check("it lands on a unit", flow.play_card(shot, { theirs }))
	check("taking two off its health", entity.get(theirs).stats.health == 1,
		tostring(entity.get(theirs).stats.health))
	check("and nothing off either Nexus",
		stat("north", "nexus") == 20 and stat("south", "nexus") == 20)
	check("nor off the unit that was not picked", entity.get(mine).stats.health == 3)

	check("a fast spell handed the turn over as it resolved", zones.active_seat() == "south")
	check("and the same spell lands on a Nexus",
		flow.play_card(hand_put("south", "mystic_shot"), { seat_card("north") }))
	check("taking two off that instead", stat("north", "nexus") == 18,
		tostring(stat("north", "nexus")))
	check("and leaving every unit standing where it was",
		entity.get(mine).stats.health == 3 and entity.get(theirs).stats.health == 1)
end

function M.test_lor_a_spell_can_take_the_last_of_a_nexus(check)
	flow.init("lor.json", 5)
	empty_hands()
	rich()
	for e in entity.each("card") do
		if e.def_key == "south" then e.stats.nexus = 4 end
	end
	flow.play_card(hand_put("north", "decimate"), {})
	check("four off a nexus standing on four", stat("south", "nexus") == 0,
		tostring(stat("south", "nexus")))
	check("north wins", stat("north", "won") == 1 and phase.current().key == "reveal")
end

-- Sixteen spells, and every one of them carries exactly one speed.
function M.test_lor_every_spell_carries_one_speed(check)
	local G = declaration.G
	local n, speeds = 0, { burst = 0, fast = 0, slow = 0 }
	for _, key in ipairs(G.card_list) do
		local d = G.card_defs[key]
		if d.tags_set and d.tags_set.spell then
			n = n + 1
			local mine = 0
			for s in pairs(speeds) do
				if d.tags_set[s] then mine, speeds[s] = mine + 1, speeds[s] + 1 end
			end
			check(key .. " is one speed and no other", mine == 1, tostring(mine))
			check(key .. " says which on its face",
				(d.tooltip or ""):match("^%u%l+%.") ~= nil, tostring(d.tooltip))
			check(key .. " is filed in the caster's discard when it is over",
				d.play.spent == "mine.discard", tostring(d.play.spent))
		end
	end
	check("the deck carries eighteen of them", n == 18, tostring(n))
	check("spread over all three speeds",
		speeds.burst > 0 and speeds.fast > 0 and speeds.slow > 0,
		("%d/%d/%d"):format(speeds.burst, speeds.fast, speeds.slow))
end

return M
