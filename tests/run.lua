-- Headless engine tests. Run from the repo root:
--   luajit tests/run.lua      (LuaJIT = LÖVE's interpreter)
--   lua tests/run.lua

require("headless")

math.randomseed(7)
require("rng").seed(7)   -- the engine's generator, so unseeded loads reproduce

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local actions     = require("actions")
local targeting   = require("targeting")
local flow        = require("flow")
local log         = require("log")
local json        = require("json")
local validate    = require("validate")
local predicate   = require("predicate")
local geometry    = require("geometry")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. name)
	end
end

local function find_card(def_key, zone_key)
	local zid = zone_key and zones.find_id(zone_key)
	for e in entity.each("card") do
		if e.def_key == def_key and (not zid or e.zone_id == zid) then return e end
	end
end

-- Lost Cities opens by asking how you want to play — an overlay of two cards,
-- which is how a game says "this one can be played with a friend" without the
-- engine guessing. Tests that care about the game itself answer "both sides,
-- here" and get on with it.
local function dismiss_mode()
	if phase.is_overlay() and phase.current().key == "mode" then
		flow.pick(zones.find("mode").cards[1])
	end
end

-- The menu is two levels now — New game, then the list — so a test that only
-- wants to start a game should not have to know that. Scoped to the zone
-- because a destroyed card is still an entity, and an unscoped find would keep
-- matching the screen we just left.
local function menu_play(def_key)
	if not find_card(def_key, "menu") then
		flow.play_card(find_card("m_new", "menu").id, {})
	end
	flow.play_card(find_card(def_key, "menu").id, {})
end

local function zone_count(key)
	local z = zones.find(key)
	return z and #z.cards or -1
end

local function empty_slot()
	for e in entity.each("slot") do
		if not e.occupant then return e.id end
	end
end

local function board_hp()
	local total = 0
	for e in entity.each("card") do
		local z = entity.get(e.zone_id)
		if z and z.zone_type == "grid" then total = total + (e.stats.hp or 0) end
	end
	return total
end

-- Run a single action then settle, like the debug server's `eval`.
local function eval(str)
	actions.execute(str, {})
	flow.settle()
end

-- === json ===
local t  = { a = 1, b = { 1, 2, 3 }, c = 'x"y\n', d = { nested = true } }
local rt = json.decode(json.encode(t))
check("json round trip",
	rt.a == 1 and rt.b[3] == 3 and rt.c == 'x"y\n' and rt.d.nested == true)

-- === menu ===
flow.init("menu.json")
check("menu loads", declaration.G.title == "Ravel")
check("menu deals every game it lists",
	zone_count("menu") == #declaration.G.zone_defs.menu.contents)
check("menu phase is waiting", phase.current().key == "waiting")

-- === demo: basics ===
-- The menu is two levels now: the first screen offers New game / Join, and the
-- game list is built by playing "New game". That is ordinary card behaviour —
-- destroy the zone's contents, fill it with different cards — so navigating it
-- is just playing cards.
-- Scoped to the zone throughout: a destroyed card is still an entity, so an
-- unscoped find would keep matching the screen we just left.
flow.play_card(find_card("m_new", "menu").id, {})
check("New game reveals the game list", find_card("play_demo", "menu") ~= nil)
check("...and a way back", find_card("m_back", "menu") ~= nil)
flow.play_card(find_card("m_back", "menu").id, {})
check("Back returns to the first screen",
	find_card("m_new", "menu") ~= nil and find_card("play_demo", "menu") == nil)
flow.play_card(find_card("m_new", "menu").id, {})
flow.play_card(find_card("play_demo", "menu").id, {})
check("menu card loads demo", declaration.G.title == "The Wandering Road")
check("demo starts with 1 hand card", zone_count("hand") == 1)
check("road holds the other 10 cards", zone_count("road") == 10)
check("player starts at 5 hp", predicate.total("hp") == 5)

eval("fill:hand:storm:1")
local storm = find_card("storm", "hand")
local hp0   = predicate.total("hp")
flow.play_card(storm.id, {})
check("demo card applies its effect", predicate.total("hp") == hp0 - 1)
check("played card goes to past", zone_count("past") == 1)
check("a new card was drawn", zone_count("hand") == 2)

eval("set_stat:hp:10")
eval("gain_stat:hp:3")
check("hp clamps at declared max", predicate.total("hp") == 10)

-- === demo: undo (state and log together) ===
local hp_before   = predicate.total("hp")
local hand_before = zones.find("hand").cards[1]
local log_before  = log.count()
flow.play_card(hand_before, {})
check("plays write log lines", log.count() > log_before)
check("undo works", flow.undo())
check("undo restores hp and hand",
	predicate.total("hp") == hp_before and zones.find("hand").cards[1] == hand_before)
check("undo erases the undone log lines", log.count() == log_before)

-- === demo: defeat ===
eval("set_stat:hp:0")
check("defeat overlay pushed at 0 hp", phase.current().key == "defeat")
check("fate card dealt to offer", zone_count("offer") == 1)
flow.pick(zones.find("offer").cards[1])
check("picking the fate card returns to menu", declaration.G.title == "Ravel")

-- === demo: victory (picking through any crossroads choice on the way) ===
menu_play("play_demo")
for _ = 1, 30 do
	local key = phase.current().key
	if key == "victory" or key == "defeat" then break end
	if phase.is_overlay() then
		flow.pick(zones.find("offer").cards[1])
	else
		eval("set_stat:hp:5")
		local h = zones.find("hand")
		if #h.cards == 0 then break end
		flow.play_card(h.cards[1], {})
	end
end
check("victory overlay after surviving the road", phase.current().key == "victory")
flow.pick(zones.find("offer").cards[1])
check("victory returns to menu", declaration.G.title == "Ravel")

-- === demo: outcomes wait while a choice is open ===
flow.init("demo.json")
eval("push_phase:path_choice")
check("path options dealt from their deck", zone_count("offer") == 3 and zone_count("paths") == 0)
eval("destroy:road")
eval("destroy:hand")
check("no victory while the choice is open", phase.current().key == "path_choice")
flow.pick(zones.find("offer").cards[1])
check("picked path lands in hand", zone_count("hand") == 1)
check("unpicked paths return to their deck", zone_count("paths") == 2)
flow.play_card(zones.find("hand").cards[1], {})
check("victory once the path resolves", phase.current().key == "victory")

-- === seeded RNG ===
flow.init("demo.json", 42)
local seq_a = {}
for _, cid in ipairs(zones.find("road").cards) do seq_a[#seq_a + 1] = entity.get(cid).def_key end
flow.init("demo.json", 42)
local seq_b = {}
for _, cid in ipairs(zones.find("road").cards) do seq_b[#seq_b + 1] = entity.get(cid).def_key end
check("seeded loads shuffle identically", table.concat(seq_a, ",") == table.concat(seq_b, ","))

-- === castle: setup ===
flow.init("castle.json")
local G = declaration.G
check("castle loads", G.title == "Castle Lord")
check("castle starts in build1", phase.current().key == "build1")
check("hand dealt 3 plus the pass card", zone_count("hand") == 4)
check("throne auto-played to board", find_card("throne_room", "board") ~= nil)
check("throne sits in its slot", entity.get(find_card("throne_room").slot_id).slot_idx == 13)
check("starting gold is 20", predicate.total("gold") == 20)
check("round counter starts at 1", predicate.total("round") == 1)
check("build deck has 15 minus 3 dealt", zone_count("build_deck") == 12)
for _, key in ipairs(G.phase_list) do
	check("overlay phase not in sequence: " .. key, G.phase_by_key[key].type ~= "overlay")
end

-- === castle: the pass card, the forced-play escape hatch ===
local pass_id
for _, cid in ipairs(zones.find("hand").cards) do
	if entity.get(cid).def_key == "pass" then pass_id = cid end
end
check("pass card dealt with the hand", pass_id ~= nil)
flow.play_card(pass_id, {})
check("pass advances the phase", phase.current().key == "build2")
check("pass vanishes instead of joining the discard", zone_count("graveyard") == 3)
flow.undo()
check("undo returns to build1 with the pass in hand", phase.current().key == "build1"
	and entity.get(pass_id).zone_id == zones.find_id("hand"))

-- === castle: activation cost ===
local throne = find_card("throne_room")
eval("set_stat:gold:0")
check("cannot inspire without gold", flow.activate(throne.id) == false)
eval("set_stat:gold:3")
local morale0 = predicate.total("morale")
check("inspire succeeds with gold", flow.activate(throne.id))
check("morale +1 and gold -2",
	predicate.total("morale") == morale0 + 1 and predicate.total("gold") == 1)
check("activation exhausts the throne", throne.exhausted == true)
check("exhausted cards cannot activate again", flow.activate(throne.id) == false)

-- === castle: abilities that take targets ===
local tdef = declaration.G.card_defs.throne_room
tdef.activate_target = { type = "card", count = 1, tags = { "building" }, zones = { "board" } }
tdef.on_activate     = { "gain_stat:defense@target:1" }
entity.get(throne.id).exhausted = nil
eval("set_stat:gold:9")
check("an ability with a target refuses none", flow.activate(throne.id, {}) == false)
check("an ability with a target refuses too many",
	flow.activate(throne.id, { throne.id, throne.id }) == false)
local defense0 = entity.get(throne.id).stats.defense or 0
check("an ability with the right target count fires", flow.activate(throne.id, { throne.id }))
check("the ability reached its target",
	entity.get(throne.id).stats.defense == defense0 + 1)

-- A repeatable ability (the "pass the time" pattern) opts out of exhausting.
tdef.exhausts = false
entity.get(throne.id).exhausted = nil
check("exhausts:false leaves the card ready",
	flow.activate(throne.id, { throne.id }) and not entity.get(throne.id).exhausted)
check("a repeatable ability fires again at once",
	flow.activate(throne.id, { throne.id }))

tdef.exhausts        = nil
tdef.activate_target = nil
tdef.on_activate     = { "gain_stat:morale:1" }
entity.get(throne.id).exhausted = nil

-- === castle: play cost gating ===
eval("set_stat:gold:0")
eval("fill:hand:mercenaries:1")
check("cannot afford mercenaries at 0 gold",
	flow.play_card(find_card("mercenaries", "hand").id, {}) == false)

-- === castle: slot targeting ===
eval("set_stat:gold:5")
eval("fill:hand:farm:1")
local farm  = find_card("farm", "hand")
local slot  = empty_slot()
local gold0 = predicate.total("gold")
flow.play_card(farm.id, { slot })
check("farm placed on board", farm.zone_id == zones.find_id("board"))
check("farm occupies the chosen slot", entity.get(slot).occupant == farm.id)
check("farm cost 1 gold", predicate.total("gold") == gold0 - 1)
check("turn ended into build2", phase.current().key == "build2")
check("hand redealt with 3 plus the pass card", zone_count("hand") == 4)

-- === castle: stat clamping on cards (overheal fix) ===
actions.execute("lose_stat:hp@target:2", { targets = { farm.id } })
check("farm damaged to 1 hp", farm.stats.hp == 1)
actions.execute("gain_stat:hp@target:9", { targets = { farm.id } })
check("healing clamps at hp_max", farm.stats.hp == 3)

-- === castle: computed-tag targeting ===
actions.execute("lose_stat:hp@target:1", { targets = { farm.id } })
eval("fill:hand:repair:1")
local rep = find_card("repair", "hand")
targeting.start(rep.id, cards.def(rep).target)
check("damaged farm eligible for repair", targeting.is_eligible(farm.id))
check("undamaged throne not eligible", not targeting.is_eligible(throne.id))
targeting.clear()
actions.execute("gain_stat:hp@target:1", { targets = { farm.id } })

-- === castle: draft overlay via architect ===
eval("set_stat:gold:5")
eval("fill:hand:architect:1")
local deck0 = zone_count("build_deck")
local hand0 = zone_count("hand")
flow.play_card(find_card("architect", "hand").id, {})
check("draft overlay active", phase.current().key == "draft")
check("3 cards offered", zone_count("offer") == 3)
local pick_id = zones.find("offer").cards[1]
flow.pick(pick_id)
check("picked card lands in hand", entity.get(pick_id).zone_id == zones.find_id("hand"))
check("offer cleared", zone_count("offer") == 0)
check("unpicked cards returned to deck", zone_count("build_deck") == deck0 - 1)
check("draft resumes build2 without redealing", phase.current().key == "build2")
check("hand kept its size (architect out, pick in)", zone_count("hand") == hand0)

-- === castle: sub-card choice via an internal deck (royal decree) ===
eval("set_stat:gold:9")
eval("fill:hand:royal_decree:1")
flow.play_card(find_card("royal_decree", "hand").id, {})
check("decree opens the edict overlay", phase.current().key == "decree")
check("three edicts offered from their deck",
	zone_count("offer") == 3 and zone_count("edicts") == 0)
check("decree cost was paid", predicate.total("gold") == 7)

flow.undo()
check("undo backs out of the whole choice",
	phase.current().key == "build2" and zone_count("offer") == 0
	and zone_count("edicts") == 3
	and find_card("royal_decree", "hand") ~= nil and predicate.total("gold") == 9)

flow.play_card(find_card("royal_decree", "hand").id, {})
local pick
for _, cid in ipairs(zones.find("offer").cards) do
	if entity.get(cid).def_key == "tax_levy" then pick = cid end
end
flow.pick(pick)
check("picked edict lands in hand", entity.get(pick).zone_id == zones.find_id("hand"))
check("unpicked edicts return to their deck",
	zone_count("edicts") == 2 and zone_count("offer") == 0)
check("choice resumes build2", phase.current().key == "build2")

local gold1 = predicate.total("gold")
flow.play_card(pick, {})
check("tax levy grants 3 gold", predicate.total("gold") == gold1 + 3)
check("played edict recycles into its deck", zone_count("edicts") == 3)
check("playing the edict ended the turn", phase.current().key == "challenge")

-- === castle: on_turn income on round wrap ===
local expected_income = 0
for e in entity.each("card") do
	local z = entity.get(e.zone_id)
	if z and z.zone_type == "grid" and (e.stats.hp or 1) > 0 then
		for _, a in ipairs(cards.def(e).on_turn or {}) do
			local n = a:match("^gain_stat:gold:(%d+)$")
			if n then expected_income = expected_income + tonumber(n) end
		end
	end
end

local challenge_card
for _, cid in ipairs(zones.find("hand").cards) do
	local k = entity.get(cid).def_key
	if k ~= "merchant" and k ~= "pass" then challenge_card = cid end
end
local gold_before = predicate.total("gold")
flow.play_card(challenge_card, {})
check("round wrapped back to build1", phase.current().key == "build1")
check("on_turn gold income applied", predicate.total("gold") == gold_before + expected_income)
check("round counter advanced", predicate.total("round") == 2)
-- re-fetch by ID: undo replaced the entity tables, old references are stale
check("the new round readies exhausted cards", entity.get(throne.id).exhausted == nil)

-- === castle: refill_when_empty ===
local bd = zones.find("build_deck")
eval("draw_from:build_deck:graveyard:" .. #bd.cards)
check("emptied build deck refills from contents", #bd.cards == 15)

-- === castle: a random board card takes the hit ===
local hp_before_dmg = board_hp()
eval("lose_stat:hp@random.building:2")
check("a random building took 2 damage", board_hp() == hp_before_dmg - 2)

-- === castle: end conditions ===
eval("set_stat:morale:0")
check("castle defeat at 0 morale", phase.current().key == "defeat")
flow.pick(zones.find("offer").cards[1])
check("castle defeat returns to menu", declaration.G.title == "Ravel")

flow.init("castle.json")
eval("set_stat:morale:10")
check("castle victory at 10 morale", phase.current().key == "victory")
flow.pick(zones.find("offer").cards[1])
check("castle victory returns to menu", declaration.G.title == "Ravel")

-- === template editing ===
flow.init("castle.json")
local fdef = declaration.G.card_defs["farm"]
check("edit: plain string value",
	cards.edit("farm", "tooltip", "Test tooltip") and fdef.tooltip == "Test tooltip")
check("edit: json value",
	cards.edit("farm", "cost", '{"gold": 7}') and fdef.cost.gold == 7)

eval("set_stat:gold:3")
eval("fill:hand:farm:1")
check("edited cost gates play immediately",
	flow.play_card(find_card("farm", "hand").id, {}) == false)

check("edit: tags rebuild tags_set",
	cards.edit("farm", "tags", '["shiny"]') and fdef.tags_set.shiny and not fdef.tags_set.building)

local inst = find_card("farm", "hand")
cards.edit("farm", "card_stats", '{"hp": 9, "hp_max": 9}')
check("edit: card_stats re-stamps instances", inst.stats.hp == 9)

check("edit: null clears a field", cards.edit("farm", "cost", "null") and fdef.cost == nil)
check("edit: unknown card fails", cards.edit("bogus", "cost", "1") == false)

local dump = cards.dump("farm")
check("dump omits derived tags_set", not dump:find("tags_set"))
check("dump round-trips", json.decode(dump).card_stats.hp == 9)

check("reload succeeds", cards.reload())
local fdef2 = declaration.G.card_defs["farm"]
check("reload restores template from disk",
	fdef2.cost.gold == 1 and fdef2.tags_set.building and fdef2.tooltip ~= "Test tooltip")
check("reload re-stamps changed instances", inst.stats.hp == 3)

-- === web asset URLs: the charset allowlist that guards the JS bridge ===
check("a plain https image URL is accepted",
	cards.url_is_safe("https://i.imgur.com/0vnj0kx.jpeg"))
check("a URL with a quote is refused (would break out of the JS string)",
	not cards.url_is_safe('https://evil.example.com/x".onerror=alert;//'))
check("a URL with a backslash is refused",
	cards.url_is_safe("https://evil.example.com/x\\") == false)
check("a URL with a raw newline is refused",
	cards.url_is_safe("https://evil.example.com/x\ny") == false)
check("a non-string asset is refused, not a crash",
	cards.url_is_safe(nil) == false and cards.url_is_safe(42) == false)
check("a non-http(s) scheme is refused",
	cards.url_is_safe("javascript:alert(1)") == false)

-- === content validation ===
for _, f in ipairs({ "menu.json", "demo.json", "castle.json", "kingdom.json",
	"tower.json", "road.json", "starter_cyoa.json", "vigil.json" }) do
	local problems = validate.check(declaration.parse(f))
	check(f .. " validates clean", #problems == 0)
	for _, p in ipairs(problems) do print("  " .. f .. ": " .. p) end
end

local bad = declaration.parse("castle.json")
bad.phase_by_key.build1.next = { { ["then"] = "nope" } }
check("validator catches unknown routing target", #validate.check(bad) > 0)

-- === kingdom: creation drafting and routing ===
flow.init("kingdom.json", 5)
check("kingdom loads at the origin", phase.current().key == "origin")
check("all three origins offered plus decline", zone_count("hand") == 4)

flow.play_card(find_card("warlord", "hand").id, {})
check("origin grants its stats", predicate.total("might") == 3 and predicate.total("progress") == 3)
check("origin auto-slotted onto the board", find_card("warlord", "board").slot_id ~= nil)
check("routing entered the market", phase.current().key == "market_visit")
check("ends_round advanced the round", predicate.total("round") == 2)
check("market hand: 4 cards plus 3 routers", zone_count("hand") == 7)

local function hand_router(key)
	for _, cid in ipairs(zones.find("hand").cards) do
		if entity.get(cid).def_key == key then return cid end
	end
end
check("router gated until something is played", flow.can_play(hand_router("to_barracks")) == false)

local first_play
for _, cid in ipairs(zones.find("hand").cards) do
	local d = cards.def(entity.get(cid))
	if not (d.tags_set and d.tags_set.token) and flow.can_play(cid) then first_play = cid; break end
end
flow.play_card(first_play, {})
check("router unlocks after one play", flow.can_play(hand_router("to_barracks")) == true)
flow.play_card(hand_router("to_barracks"), {})
check("router chose the barracks", phase.current().key == "barracks_visit")

-- === kingdom: counting synergies ===
eval("fill:hand:homestead:2")
flow.play_card(find_card("homestead", "hand").id, {})
flow.play_card(find_card("homestead", "hand").id, {})
-- count board farms independently (the random market play may have added one)
local farms = 0
for e in entity.each("card") do
	local z = entity.get(e.zone_id)
	local d = cards.def(e)
	if z and z.zone_type == "grid" and d.tags_set and d.tags_set.farm then
		farms = farms + 1
	end
end
local food0 = predicate.total("food")
eval("gain_stat:food:count:farm")
check("count amounts resolve board tags",
	farms >= 2 and predicate.total("food") == food0 + farms)

eval("fill:hand:rally_banner:1")
check("count-needs gate blocks below threshold",
	flow.can_play(find_card("rally_banner", "hand").id) == false)
eval("fill:hand:militia:1")
flow.play_card(find_card("militia", "hand").id, {})
check("count-needs gate opens at threshold",
	flow.can_play(find_card("rally_banner", "hand").id) == true)

-- === kingdom: trials via progress routing ===
eval("set_stat:progress:15")
eval("set_stat:plays:1")
flow.play_card(hand_router("to_market"), {})
check("progress routed into tier-2 trials", phase.current().key == "trial2")
check("trial hand: 2 trials plus rest, tokens swept", zone_count("hand") == 3)

local rest_id = hand_router("rest")
check("rest gated until both trials faced", flow.can_play(rest_id) == false)
-- snapshot first: playing mutates the hand array under iteration
local trial_cards = {}
for _, cid in ipairs(zones.find("hand").cards) do
	local d = cards.def(entity.get(cid))
	if not (d.tags_set and d.tags_set.token) then trial_cards[#trial_cards + 1] = cid end
end
for _, cid in ipairs(trial_cards) do flow.play_card(cid, {}) end
check("rest unlocks after both trials", flow.can_play(rest_id) == true)
local round0 = predicate.total("round")
flow.play_card(rest_id, {})
check("rest marches into the wartime market", phase.current().key == "wartime_market")
check("each trial pair is a round", predicate.total("round") == round0 + 1)
check("the wartime market deals supplies", zone_count("hand") == 4)
flow.play_card(hand_router("march_on"), {})
check("marching on returns to the trials", phase.current().key == "trial2")

-- === named effects fire through the presentation hook ===
local fired = {}
actions.on_effect = function(name) fired[#fired + 1] = name end
flow.init("road.json", 9)
flow.pick(zones.find("reveal").cards[1])
eval("fill:hand:outrider:1")
flow.play_card(find_card("outrider", "hand").id, {})
flow.activate(find_card("outrider", "battlefield").id)
actions.on_effect = nil
check("activations fire their named effect", fired[#fired] == "sabre_hit")

local fxmod = require("fx")
local agree = true
for b in pairs(fxmod.bases()) do
	if not validate.EFFECT_BASES[b] then agree = false end
end
for b in pairs(validate.EFFECT_BASES) do
	if not fxmod.bases()[b] then agree = false end
end
check("validator and fx agree on the base effects", agree)

-- === endings announce themselves ===
flow.init("kingdom.json", 5)
check("no outcome while the game runs", flow.outcome() == nil)
check("the summary reports the visible stats", #flow.summary() >= 5)
eval("set_stat:progress:24")
check("the coronation is a victory", flow.outcome() == "victory")
flow.init("kingdom.json", 5)
eval("set_stat:stability:0")
check("the collapse is a defeat", flow.outcome() == "defeat")
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("lose_stat:hp:99")
check("story pages carry outcomes too", flow.outcome() == "defeat")

-- === phases end and discard like MTG turns ===
flow.init("kingdom.json", 5)
flow.play_card(find_card("warlord", "hand").id, {})
eval("fill:hand:laborers:1")
flow.play_card(find_card("laborers", "hand").id, {})
local grave0 = zone_count("graveyard")
flow.play_card(hand_router("to_market"), {})
check("leaving a phase discards the unplayed hand", zone_count("graveyard") > grave0)
check("the next visit deals only the fresh hand", zone_count("hand") == 7)

declaration.G.phase_by_key.market_visit.ends_after = 1
local r_ea = predicate.total("round")
local first_ea
for _, cid in ipairs(zones.find("hand").cards) do
	local d = cards.def(entity.get(cid))
	if not (d.tags_set and d.tags_set.token) and flow.can_play(cid) then first_ea = cid; break end
end
flow.play_card(first_ea, {})
check("ends_after advances the phase by itself", predicate.total("round") == r_ea + 1)
check("the phase it advanced into dealt fresh", zone_count("hand") == 7)

-- === kingdom: failed trials persist as crises ===
flow.init("kingdom.json", 5)
flow.play_card(find_card("warlord", "hand").id, {})
eval("set_stat:might:0")
eval("fill:hand:war_host:1")
flow.play_card(find_card("war_host", "hand").id, {})
check("a failed trial squats on the board as a crisis", find_card("war_host", "board") ~= nil)
local stab1 = predicate.total("stability")
flow.play_card(hand_router("to_market"), {})
check("an unanswered crisis drains stability each round",
	predicate.total("stability") == stab1 - 1)
local crisis = find_card("war_host", "board")
eval("set_stat:might:9")
flow.activate(crisis.id)
check("answering the crisis clears it from the board", find_card("war_host", "board") == nil)

-- === kingdom: the three endings ===
eval("set_stat:stability:0")
check("stability 0 collapses the realm", phase.current().key == "collapse")
flow.pick(zones.find("offer").cards[1])
check("collapse returns to menu", declaration.G.title == "Ravel")

flow.init("kingdom.json", 5)
eval("set_stat:progress:24")
check("progress 24 crowns you", phase.current().key == "coronation")

flow.init("kingdom.json", 5)
eval("set_stat:round:20")
check("round 20 fades to twilight", phase.current().key == "twilight_years")

-- === tower: classical CYOA — reveal pages, secret gates, irreversible ===
local function top_page()
	local r = zones.find("reveal")
	return r and r.cards[#r.cards] and entity.get(r.cards[#r.cards]).def_key
end

flow.init("tower.json", 3)
check("tower opens on a page overlay", phase.is_overlay() and phase.current().page == true)
check("the opening page is the shore", top_page() == "p_shore")

flow.pick(zones.find("reveal").cards[1])
check("the intro advanced once the page closed", phase.current().key == "story")
check("the shore offers three choices", zone_count("hand") == 3)
check("the read page vanished", zone_count("reveal") == 0)

flow.play_card(find_card("c_search", "hand").id, {})
check("searching revealed the beach", top_page() == "p_beach")
flow.undo()
check("undo closed the page again",
	not phase.is_overlay() and zone_count("hand") == 3 and zone_count("reveal") == 0)

flow.play_card(find_card("c_door", "hand").id, {})
check("the door without the key reveals the locked page", top_page() == "p_door_locked")
flow.pick(zones.find("reveal").cards[1])
check("the locked door keeps the hand for another try", zone_count("hand") == 3)

flow.play_card(find_card("c_search", "hand").id, {})
flow.pick(zones.find("reveal").cards[1])
check("the beach puts keepsakes on the board", zone_count("board") == 2)
check("keepsakes occupy board slots", find_card("rusty_key", "board").slot_id ~= nil)
check("the beach trims the choices", zone_count("hand") == 2)

local hp_lantern = predicate.total("hp")
eval("gain_stat:hp:card:lantern")
check("card amounts resolve template presence", predicate.total("hp") == hp_lantern + 1)

flow.play_card(find_card("c_door", "hand").id, {})
check("the door with the key reveals the hall", top_page() == "p_hall")
flow.pick(zones.find("reveal").cards[1])

local chest0 = zone_count("chest_deck")
flow.play_card(find_card("c_chest", "hand").id, {})
local secret = top_page()
check("the chest reveals one of its two secrets",
	secret == "p_chest_pearl" or secret == "p_chest_mimic")
check("the other secret stays face-down", zone_count("chest_deck") == chest0 - 1)
flow.pick(zones.find("reveal").cards[1])

flow.play_card(find_card("c_descend", "hand").id, {})
check("the lantern lights the stair", top_page() == "p_stair_lit")
flow.pick(zones.find("reveal").cards[1])
check("the bell room offers the finale", find_card("c_bell", "hand") ~= nil)

eval("fill:board:pearl:1")
check("undo is available before the bell", flow.can_undo() == true)
flow.play_card(find_card("c_bell", "hand").id, {})
check("the pearl earns the good ending", top_page() == "e_pearl")
check("irreversible cleared the undo stack", flow.can_undo() == false)
flow.pick(zones.find("reveal").cards[1])
check("the ending returns to the menu", declaration.G.title == "Ravel")

flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("lose_stat:hp:99")
check("death fires the collapse page", phase.is_overlay() and top_page() == "e_collapse")

-- === placement: tag homes and the single-board fallback ===
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("gain:pearl:1")
check("gain places a homed card on its board", find_card("pearl", "board") ~= nil)
check("gained card takes a slot", find_card("pearl", "board").slot_id ~= nil)
eval("gain:c_flee:1")
check("gain without a home goes to hand", find_card("c_flee", "hand") ~= nil)
actions.execute("move_to", { card_id = find_card("c_search", "hand").id, targets = {} })
flow.settle()
check("bare move_to falls back to the only board", find_card("c_search", "board") ~= nil)

-- === sacrifice costs: board cards as currency ===
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
cards.edit("c_flee", "cost", '{"sacrifice:keepsake": 1}')
eval("fill:hand:c_flee:1")
local flee = find_card("c_flee", "hand")
check("a sacrifice cost gates without the board card", flow.can_play(flee.id) == false)
eval("gain:pearl:1")
check("the sacrifice cost opens with it on the board", flow.can_play(flee.id) == true)
flow.play_card(flee.id, {})
check("paying destroyed the sacrificed card", zone_count("board") == 0)
local logged = false
for _, l in ipairs(log.tail(8)) do
	if l:find("Sacrificed The Pearl", 1, true) then logged = true end
end
check("the sacrifice is logged", logged)
check("the play still resolved its reveal", phase.is_overlay())
check("sacrifice costs read as text", cards.cost_text({ ["sacrifice:farm"] = 2 }) == "sacrifice 2 farm")

-- === flow is the single legality gate ===
flow.init("castle.json")
eval("fill:hand:watchtower:1")
local wt2 = find_card("watchtower", "hand")
check("play with missing targets is refused", flow.play_card(wt2.id, {}) == false)
check("the refused card stayed in hand", entity.get(wt2.id).zone_id == zones.find_id("hand"))
flow.play_card(wt2.id, { empty_slot() })
check("the same play with a slot target works", find_card("watchtower", "board") ~= nil)

-- === grid capacity: full boards refuse new arrivals ===
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("gain:pearl:8")
check("gain stops at the board's capacity", zone_count("board") == 5)
local held = find_card("c_search", "hand")
check("a move onto a full board is refused",
	zones.move_card(held.id, zones.find_id("board")) == false)
check("the refused card stayed put", entity.get(held.id).zone_id == zones.find_id("hand"))

-- === the long road: two boards, tag homes, threats and marches ===
local function battlefield_threat()
	for e in entity.each("card") do
		local d = cards.def(e)
		if e.zone_id == zones.find_id("battlefield") and d.tags_set and d.tags_set.threat then
			return e
		end
	end
end

flow.init("road.json", 9)
check("the road opens on its title page", phase.is_overlay() and top_page() == "p_depart")
flow.pick(zones.find("reveal").cards[1])
check("dawn dealt a threat onto the battlefield", battlefield_threat() ~= nil)
check("camp offers a draft plus both marches", zone_count("hand") == 5)

eval("fill:hand:outrider:1")
flow.play_card(find_card("outrider", "hand").id, {})
check("units muster on the battlefield by tag", find_card("outrider", "battlefield") ~= nil)
eval("fill:hand:torch:1")
flow.play_card(find_card("torch", "hand").id, {})
check("items stow in the wagons by tag", find_card("torch", "inventory") ~= nil)

local th  = battlefield_threat()
local hp0 = th.stats.hp
flow.activate(find_card("outrider", "battlefield").id)
check("units wound threats once per day", th.stats.hp < hp0)
eval("lose_stat:hp@random.threat:9")
check("a dead threat is slain, not gone", th.stats.hp == 0 and th.zone_id ~= nil)

eval("fill:hand:scavenge:1")
flow.play_card(find_card("scavenge", "hand").id, { th.id })
check("scavenging clears the corpse for supplies",
	entity.get(th.id).zone_id == zones.find_id("graveyard"))

local d0, s0 = predicate.total("distance"), predicate.total("supplies")
local m0 = predicate.total("morale")
flow.play_card(hand_router("march"), {})
check("marching trades a supply for a mile",
	predicate.total("distance") == d0 + 1 and predicate.total("supplies") == s0 - 1)
check("a threat never drains on the day it arrives", predicate.total("morale") == m0)
check("the road loops back to camp", phase.current().key == "camp")
check("a new day has dawned", predicate.total("round") == 2)
check("camp discards yesterday's leftovers", zone_count("hand") == 5)

local far0 = zone_count("road_far")
eval("set_stat:distance:7")
flow.play_card(hand_router("hard_march"), {})
check("past six miles the far road deals the threats", zone_count("road_far") == far0 - 1)

eval("fill:hand:burn_the_wagons:1")
flow.play_card(find_card("burn_the_wagons", "hand").id, {})
check("burning the wagons sacrificed the unit", find_card("outrider", "battlefield") == nil)

eval("set_stat:distance:12")
check("twelve miles ends the run at home", phase.is_overlay() and top_page() == "e_home")
flow.pick(zones.find("reveal").cards[1])
check("the road returns to the menu", declaration.G.title == "Ravel")

-- === validator: conflicts, ambiguity, and friendly messages ===
local function has_problem(list, needle)
	for _, p in ipairs(list) do
		if p:find(needle, 1, true) then return true end
	end
	return false
end

local vg = declaration.parse("tower.json")
vg.zone_defs.battlefield = { key = "battlefield", type = "grid",
	grid = { 3, 1 }, pos = { 0, 0, 1, 1 }, tags_set = {} }
vg.card_defs.c_flee.on_play = { "move_to" }
local vp = validate.check(vg)
check("ambiguous placement across two boards is flagged",
	has_problem(vp, "card 'c_flee'") and has_problem(vp, "boards"))

vg.tag_defs.relic = { zone = "battlefield" }
vg.card_defs.pearl.tags = { "keepsake", "relic" }
vg.card_defs.pearl.tags_set = { keepsake = true, relic = true }
vp = validate.check(vg)
check("tags that disagree about a card's home are flagged", has_problem(vp, "disagree"))

-- Write a temp game file, parse and validate it, and always clean up —
-- even when the parse itself blows up.
local function with_fixture(content)
	local path = "game/games/tmp_fixture_test.json"
	local f = assert(io.open(path, "w"))
	f:write(content)
	f:close()
	local ok, result = pcall(function()
		return validate.check(declaration.parse("tmp_fixture_test.json"))
	end)
	os.remove(path)
	if not ok then error(result, 2) end
	return result
end

local bp = with_fixture([[{
  "title": "Broken",
  "templats": [],
  "stats": [ { "key": "gold" }, { "key": "gold" } ],
  "zones": [
    { "key": "board", "type": "gird", "pos": [0, 0, 1, 1], "grid": [3, 1] },
    { "key": "hand", "type": "hand", "pos": [0, 0, 1, 1] }
  ],
  "templates": [
    { "key": "sword", "onplay": ["destroy_self"], "cost": { "gold": "2" },
      "on_play": ["gain_stat:gld:1"] },
    { "key": "axe", "on_activate": "gain_stat:gold:1" },
    { "key": "dagger" },
    { "key": "dagger" }
  ],
  "phases": [ { "key": "start", "type": "playerinput" } ]
}]])
check("a typo'd section name is reported", has_problem(bp, "templats"))
check("duplicate keys are reported as conflicts", has_problem(bp, "share the key 'dagger'") and has_problem(bp, "share the key 'gold'"))
check("an unknown card field suggests the right one", has_problem(bp, "did you mean 'on_play'"))
check("an unknown stat suggests the right one", has_problem(bp, "did you mean 'gold'"))
check("a non-number cost value is explained", has_problem(bp, "'gold' should be a number"))
check("a lone string instead of an action list is explained", has_problem(bp, "list of actions"))
check("unknown zone and phase types suggest the right ones",
	has_problem(bp, "did you mean 'grid'") and has_problem(bp, "did you mean 'player_input'"))

-- === validator: every error message, once ===
-- One case per distinct message: mutate a freshly parsed (clean) tower
-- definition, run the validator, require the message. A case that stops
-- firing means the check silently died.
local CASES = {
	-- condition subjects
	{ "an unknown tag in a count", "counts the tag 'dragons'",
		function(g) g.card_defs.c_flee.needs = { ["count:dragons"] = 1 } end },
	{ "a card check for a missing template", "checks for the card 'excalibur'",
		function(g) g.card_defs.c_flee.requires = { ["card:excalibur"] = 1 } end },
	{ "an unknown stat in routing", "uses the stat 'mana'",
		function(g) g.phase_by_key.story.next = { { stat = "mana", at_least = 1, ["then"] = "story" } } end },
	{ "a zone_empty that isn't a list", "zone_empty should be a list",
		function(g) g.end_conditions[2] = { zone_empty = "hand", ["then"] = {} } end },
	{ "a zone_empty watching a missing zone", "watches zone 'vault'",
		function(g) g.end_conditions[2] = { zone_empty = { "vault" }, ["then"] = {} } end },
	{ "an art spec the engine can't draw", "isn't a shape the engine can draw",
		function(g) g.card_defs.c_flee.asset = "hexagram:red" end },
	{ "a comparison against a bare word", "is a bare word",
		function(g) g.end_conditions[2] = { stat = "hp", at_least = "lots", ["then"] = {} } end },
	{ "a condition with no comparison", "no comparison",
		function(g) g.end_conditions[2] = { stat = "hp", ["then"] = {} } end },
	{ "an end condition with no then", "has no 'then'",
		function(g) g.end_conditions[2] = { stat = "hp", equals = 3 } end },
	-- maps and shapes
	{ "a cost that isn't a map", 'should be written like { "gold"',
		function(g) g.card_defs.c_flee.cost = "2 gold" end },
	{ "an unknown stat in a cost", "uses the stat 'mana'",
		function(g) g.card_defs.c_flee.cost = { mana = 1 } end },
	{ "a pos with the wrong count", "pos should be a list of 4 numbers",
		function(g) g.zone_defs.hand.pos = { 0, 0, 1 } end },
	{ "a pos with a non-number", "pos should contain only numbers",
		function(g) g.zone_defs.hand.pos = { 0, 0, 1, "x" } end },
	{ "a color with the wrong count", "color should be a list of 3 numbers",
		function(g) g.card_defs.c_flee.color = { 1, 2 } end },
	-- actions
	{ "an unknown action with a suggestion", "'moove_to' is not an action",
		function(g) g.card_defs.c_flee.on_play = { "moove_to:board" } end },
	{ "an action pointing at a missing zone", "points at zone 'vault'",
		function(g) g.card_defs.c_flee.on_play = { "draw_from:vault:hand:1" } end },
	{ "a gain of a missing card", "names the card 'excalibur'",
		function(g) g.card_defs.c_flee.on_play = { "gain:excalibur:1" } end },
	{ "a push_phase to a missing phase", "points at phase 'finale'",
		function(g) g.card_defs.c_flee.on_play = { "push_phase:finale" } end },
	{ "a load_game path-traversal attempt", "no folders or '..' are allowed",
		function(g) g.card_defs.c_flee.on_play = { "load_game:../../../etc/passwd" } end },
	{ "a load_game target that doesn't exist", "doesn't exist",
		function(g) g.card_defs.c_flee.on_play = { "load_game:no_such_game.json" } end },
	{ "an action missing its argument", "'reveal' is missing its card argument",
		function(g) g.card_defs.c_flee.on_play = { "reveal" } end },
	{ "an unknown tag in an action amount", "counts the tag 'dragons'",
		function(g) g.card_defs.c_flee.on_play = { "gain_stat:hp:count:dragons" } end },
	{ "a missing card in an action amount", "checks for the card 'excalibur'",
		function(g) g.card_defs.c_flee.on_play = { "gain_stat:hp:card:excalibur" } end },
	{ "a return_to draining a refilling zone", "refills itself when empty",
		function(g)
			g.zone_defs.chest_deck.tags_set.refill_when_empty = true
			g.card_defs.c_flee.on_play = { "return_to:chest_deck:hand" }
		end },
	{ "a non-string in an action list", "every action must be a text string",
		function(g) g.card_defs.c_flee.on_play = { 5 } end },
	-- stats
	{ "min/max on an engine-managed stat", "managed by the engine",
		function(g) g.stat_defs.round = { key = "round", min = 0 } end },
	{ "a stat with min above max", "greater than max",
		function(g) g.stat_defs.hp.min = 9 end },
	-- tag behaviour
	{ "a tag definition that isn't a map", 'should be written like { "zone"',
		function(g) g.tag_defs.keepsake = "board" end },
	{ "a tag homed in a missing zone", "sends cards to zone 'vault'",
		function(g) g.tag_defs.keepsake = { zone = "vault" } end },
	{ "a tag that is also computed", "defined under both",
		function(g) g.computed_tags.keepsake = { stat = "hp", equals = "0" } end },
	{ "a tag with behaviour nobody carries", "no card carries this tag",
		function(g) g.tag_defs.ghost = { zone = "board" } end },
	-- computed tags
	{ "a computed tag that isn't a map", 'should be written like { "stat"',
		function(g) g.computed_tags.ruined = 5 end },
	{ "a computed tag reading a missing card stat", "reads the card stat 'durability'",
		function(g) g.computed_tags.ruined = { stat = "durability", equals = "0" } end },
	-- cards
	{ "card tags that aren't a list", "tags should be a list",
		function(g) g.card_defs.c_flee.tags = "keepsake" end },
	{ "card_stats that aren't a map", "card_stats should be written like",
		function(g) g.card_defs.c_flee.card_stats = 3 end },
	{ "a non-number card stat", "the value of 'hp' should be a number",
		function(g) g.card_defs.c_flee.card_stats = { hp = "3" } end },
	{ "a target of an unknown type", "type should be 'card', 'slot' or 'zone'",
		function(g) g.card_defs.c_flee.target = { type = "hand", max = 1 } end },
	{ "a zone target naming no zones", "targets a zone but names none",
		function(g) g.card_defs.c_flee.target = { type = "zone", count = 1 } end },
	{ "a zone target filtering by tag", "zones are named, not tagged",
		function(g) g.card_defs.c_flee.target =
			{ type = "zone", count = 1, zones = { "board" }, tags = { "keepsake" } } end },
	{ "a card limited to a phase that does not exist", "no phase has that key",
		function(g) g.card_defs.c_flee.phases = { "nowhere" } end },
	{ "a zone handing out a tag nothing defines", "which nothing defines or reads",
		function(g) g.zone_defs.board.applies = { "flurble" } end },
	{ "a target looking for a missing tag", "looks for the tag 'dragons'",
		function(g) g.card_defs.c_flee.target = { type = "card", max = 1, tags = { "dragons" } } end },
	{ "a target searching a missing zone", "searches zone 'vault'",
		function(g) g.card_defs.c_flee.target = { type = "card", max = 1, zones = { "vault" } } end },
	{ "a bare move_to with no board at all", "no board zone to put it on",
		function(g)
			g.zone_defs.board = nil
			g.card_defs.c_flee.on_play = { "move_to" }
		end },
	{ "an auto_play into a missing zone", "starts in play, but its zone 'vault'",
		function(g)
			g.card_defs.c_flee.auto_play = true
			g.card_defs.c_flee.to_zone = "vault"
		end },
	-- zones
	{ "a board without grid dimensions", 'a board needs "grid"',
		function(g) g.zone_defs.board.grid = nil end },
	{ "grid dimensions with the wrong count", "grid should be a list of 2 numbers",
		function(g) g.zone_defs.board.grid = { 4 } end },
	{ "contents naming a missing card", "starts with the card 'excalibur'",
		function(g) g.zone_defs.chest_deck.contents = { "excalibur" } end },
	{ "a malformed contents entry", "should look like 'card' or 'card:3'",
		function(g) g.zone_defs.chest_deck.contents = { "p_chest_pearl:" } end },
	{ "contents that aren't a list", "contents should be a list",
		function(g) g.zone_defs.chest_deck.contents = "p_chest_pearl" end },
	-- phases
	{ "a phase with no type", "has no type",
		function(g) g.phase_by_key.story.type = nil end },
	{ "a phase drawing from a missing deck", "draws from 'vault'",
		function(g) g.phase_by_key.story.deck = "vault" end },
	{ "a phase dealing into a missing zone", "deals into 'vault'",
		function(g) g.phase_by_key.story.zone = "vault" end },
	{ "a draw that isn't a number", "draw should be a number",
		function(g) g.phase_by_key.story.draw = "two" end },
	{ "a pass card with no template", "its pass card 'excalibur'",
		function(g) g.phase_by_key.story.pass_card = "excalibur" end },
	{ "a forced-play phase without a pass card", "forces a play every turn",
		function(g) g.phase_by_key.story.type = "draw_and_play" end },
	{ "actions on a non-automatic phase", "only automatic phases run them",
		function(g) g.phase_by_key.story.actions = { "shuffle:chest_deck" } end },
	{ "on_pick outside an overlay", "only overlay phases use it",
		function(g) g.phase_by_key.story.on_pick = { "destroy:hand" } end },
	{ "routing that isn't a list", "next should be a list of routes",
		function(g) g.phase_by_key.story.next = "story" end },
	{ "routing on an overlay", "overlays pop back",
		function(g) g.phase_by_key.reveal.next = { { ["then"] = "story" } } end },
	{ "an unreachable route", "can never be reached",
		function(g) g.phase_by_key.story.next = { { ["then"] = "intro" }, { ["then"] = "story" } } end },
	{ "a route into an overlay", "which is an overlay",
		function(g) g.phase_by_key.story.next = { { ["then"] = "reveal" } } end },
	{ "automatic phases running in a circle", "in a circle",
		function(g) g.phase_by_key.intro.next = { { ["then"] = "intro" } } end },
	-- setup
	{ "an unknown setup section", "did you mean 'player'",
		function(g) g.setup.playr = {} end },
	{ "a non-number starting value", "the starting value of 'hp'",
		function(g) g.setup.player.hp = "six" end },
	-- persona-audit additions
	{ "a negative cost", "'gold' is negative",
		function(g) g.card_defs.c_flee.cost = { gold = -5 } end },
	{ "a sacrifice of an uncarried tag", "sacrifices the tag 'dragons'",
		function(g) g.card_defs.c_flee.cost = { ["sacrifice:dragons"] = 1 } end },
	{ "a sacrifice outside a cost", "belongs in cost or activate_cost",
		function(g) g.card_defs.c_flee.needs = { ["sacrifice:keepsake"] = 1 } end },
	{ "a missing image file", "is not in games/assets",
		function(g) g.card_defs.c_flee.asset = "no_such_file.png" end },
	{ "a web asset URL with characters that could break out of generated JS",
		"characters that aren't valid in a URL",
		function(g) g.card_defs.c_flee.asset = 'https://evil.example.com/x".onerror=alert;//' end },
	{ "a zone squatting on the UI corner", "lower-left corner",
		function(g) g.zone_defs.hand.pos = { 0.00, 0.60, 0.97, 0.97 } end },
	{ "a non-number ends_after", "ends_after should be a number",
		function(g) g.phase_by_key.story.ends_after = "two" end },
	{ "ends_after on an automatic phase", "only phases where cards are played",
		function(g) g.phase_by_key.intro.ends_after = 1 end },
	{ "discard_hand on an overlay", "overlays pop back — it never fires",
		function(g) g.phase_by_key.reveal.discard_hand = true end },
	{ "a misspelled outcome", "outcome should be 'victory' or 'defeat'",
		function(g) g.card_defs.e_pearl.outcome = "vctory" end },
	{ "an unknown base effect", "is not a base effect",
		function(g) g.effect_defs.oops = { base = "sparkles" } end },
	{ "an effect the game never defines", "defines no such effect",
		function(g) g.card_defs.c_flee.on_play = { "effect:big_boom" } end },
	{ "a non-number effect size", "size should be a number",
		function(g) g.effect_defs.bell_toll.size = "big" end },
	{ "contents beyond the board's capacity", "only has 5 slots",
		function(g) g.zone_defs.board.contents = { "pearl:9" } end },
	{ "an automatic phase that can stall", "when none matches, the game stalls",
		function(g) g.phase_by_key.intro.next = { { stat = "hp", at_least = 99, ["then"] = "story" } } end },
	{ "half of the reveal pair replaced", "define both or neither",
		function(g) g.zone_defs.reveal.injected = nil end },
	{ "an uncarried tag near a carried one", "did you mean 'keepsake'",
		function(g) g.tag_defs.keepsakes = { zone = "board" } end },
	{ "an activate_target with no ability", "no ability for it to target",
		function(g) g.card_defs.c_flee.activate_target = { type = "card", count = 1 } end },
	{ "a non-boolean exhausts", "exhausts should be true or false",
		function(g) g.card_defs.c_flee.exhausts = "no" end },
	{ "an unknown fill word", "fill should be 'empty', 'enemy', 'open' or 'any'",
		function(g) g.card_defs.c_flee.target = { type = "slot", count = 1, fill = "friendly" } end },
	{ "a pattern that isn't a list of pairs", "should be a list of [x, y] pairs",
		function(g) g.raw_patterns = { hop = { vectors = "north" } } end },
	{ "a direction that isn't a pair", "every direction is a pair of whole numbers",
		function(g) g.raw_patterns = { hop = { { 1, 2, 3 } } } end },
	{ "a direction that goes nowhere", "[0,0] is not a direction",
		function(g) g.raw_patterns = { hop = { { 0, 0 } } } end },
	{ "a class list that isn't a list", "\"class\" should be a list",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, class = "ray" } } end },
	{ "an unknown way of walking a pattern", "is not a way of walking a pattern",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, class = { "slide" } } } end },
	{ "a distance on something that is not a ray", "only 'ray' takes a distance",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, class = { "step:2" } } } end },
	{ "a piece moving by a pattern nobody declared", "but none is declared under",
		function(g)
			g.card_defs.c_flee.move_rules = { { patterns = { "line_ortho" }, fill = "open" } }
		end },
	{ "a move with an unknown fill", "a move's fill should be",
		function(g)
			g.raw_patterns = { hop = { { 1, 0 } } }
			g.pattern_defs.hop = { vectors = { { 1, 0 } }, range = 1 }
			g.card_defs.c_flee.move_rules = { { patterns = { "hop" }, fill = "friendly" } }
		end },
	{ "a piece that moves but does nothing on arrival", "no on_activate",
		function(g) g.card_defs.c_flee.moves = { "hop" }; g.card_defs.c_flee.on_activate = nil end },
	{ "a walking word on an absolute pattern", "has no path to describe",
		function(g)
			g.raw_patterns = { home = { vectors = { { 1, 1 } }, class = { "absolute", "ray" },
				zone = "board" } }
		end },
	{ "a zone named by a pattern of directions", "only an absolute pattern names a",
		function(g) g.raw_patterns = { hop = { vectors = { { 1, 0 } }, zone = "board" } } end },
	{ "an absolute pattern pointing at no such zone", "no zone has that key",
		function(g)
			g.raw_patterns = { home = { vectors = { { 1, 1 } }, class = { "absolute" },
				zone = "vault" } }
		end },
	{ "fill on something that isn't a square", "only applies to \"type\": \"slot\"",
		function(g) g.card_defs.c_flee.target = { type = "card", count = 1, fill = "empty" } end },
	{ "a move_to that names no such tray", "happens to a piece already standing there",
		function(g) g.card_defs.c_flee.on_play = { "move_to:target:vault" } end },
	{ "an unknown zone fit", "fit should be 'card' or 'fill'",
		function(g) g.zone_defs.board.fit = "stretch" end },
	{ "a checker that isn't a pair of colours", "checker should be two colours",
		function(g) g.zone_defs.board.checker = { "cream" } end },
	{ "a checker colour that isn't one", "is not a colour",
		function(g) g.zone_defs.board.checker = { "cream", "octarine" } end },
	{ "painting squares no pattern names", "no pattern has that name",
		function(g) g.zone_defs.board.paint = { throne = "gold" } end },
	{ "painting by a pattern of directions", "only an absolute pattern names squares",
		function(g)
			g.raw_patterns = { hop = { { 1, 0 } } }
			g.pattern_defs.hop = { vectors = { { 1, 0 } }, range = 1 }
			g.zone_defs.board.paint = { hop = "gold" }
		end },
	{ "a tag and a zone sharing a name", "both a zone and a tag",
		function(g) g.tag_defs.board = { zone = "board" } end },
	{ "a tag claiming a reserved scope name", "reserves for conditions",
		function(g) g.tag_defs.self = { zone = "board" } end },
	{ "a zone claiming a reserved scope name", "reserves for conditions",
		function(g) g.zone_defs.all = { key = "all", type = "hand" } end },
	{ "a scope that names nothing", "neither a zone nor a tag",
		function(g) g.card_defs.c_flee.needs = { ["hp@nowhere"] = 1 } end },
	{ "a scope with a typo suggests the right one", "did you mean 'keepsake'",
		function(g) g.card_defs.c_flee.needs = { ["hp@keepsakes"] = 1 } end },
	{ "a measuring fn used as a cost", "cannot be a cost",
		function(g) g.card_defs.c_flee.cost = { ["count:keepsake"] = 1 } end },
	{ "two zones drawn on top of each other", "overlaps zone",
		function(g) g.zone_defs.board.pos = { 0.2, 0.2, 0.9, 0.9 }
			g.zone_defs.hand.pos = { 0.3, 0.3, 0.8, 0.8 } end },
}
for _, c in ipairs(CASES) do
	local g = declaration.parse("tower.json")
	c[3](g)
	check("validator flags " .. c[1], has_problem(validate.check(g), c[2]))
end

-- The validator derives its checks from each op's declared shape: every
-- handler must declare one, or new actions silently skip validation.
local unspecced = {}
for op in pairs(actions.ops()) do
	if not actions.spec(op) then unspecced[#unspecced + 1] = op end
end
check("every action declares its argument shape", #unspecced == 0)
for _, op in ipairs(unspecced) do print("  missing spec: " .. op) end

-- === security: content from other people must never crash the engine ===
-- Games are meant to be authored by people other than the engine's own
-- developer. The validator only warns about a malformed field — content
-- keeps running regardless — so the runtime itself must survive every one
-- of these without an uncaught Lua error, not just report them.

-- predicate.met / predicate.meets_all: previously `v >= cond.at_least` (etc)
-- raised "attempt to compare number with X" the instant a routing
-- condition, end_condition, or requires/needs map held a non-number.
check("a non-number at_least fails closed instead of crashing",
	predicate.met({ stat = "hp", at_least = "lots" }) == false)
check("a non-number at_most fails closed instead of crashing",
	predicate.met({ stat = "hp", at_most = {} }) == false)
check("a non-number equals fails closed instead of crashing",
	predicate.met({ stat = "hp", equals = "zero" }) == false)
check("a condition with no stat/zone_empty is just false",
	predicate.met({}) == false)
check("a zone_empty that isn't a list fails closed",
	predicate.met({ zone_empty = "hand" }) == false)
check("meets_all with a non-number requirement fails closed",
	predicate.meets_all({ hp = "plenty" }) == false)
check("meets_all tolerates a non-table argument",
	predicate.meets_all("garbage") == true)
check("total tolerates a non-string subject",
	predicate.total(42) == 0 and predicate.total(nil) == 0)

-- Stat values are coerced to numbers at the point they're written (card
-- creation, setup.player), so a malformed content value can never reach
-- gain_stat/lose_stat arithmetic as a string and crash there instead.
do
	local g = declaration.parse("tower.json")
	g.card_defs.pearl.card_stats = { charge = "lots" }
	declaration.G = g
	local e = cards.create("pearl", zones.find_id("hand"))
	check("a non-number card_stats value is coerced, not stored raw",
		type(e.stats.charge) == "number")
end

-- load_game path traversal / bogus targets: refused by the handler itself,
-- and a failed load_game (bad file, bad JSON) must recover to the menu
-- rather than crash or strand the player in a half-reset state.
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
eval("effect:nope")   -- an unknown effect name must not raise either
eval("load_game:../../../etc/passwd")
check("path-traversal load_game is refused and the game keeps running",
	declaration.G.title == "The Drowned Tower")
eval("load_game:this_game_does_not_exist.json")
check("a load_game to a missing file recovers to the menu, not a crash",
	declaration.G.title == "Ravel")

-- A pathologically deep JSON payload can blow the parser's (recursive
-- descent) C stack. pcall catches that cleanly, and the load_game path
-- above already runs through a pcall boundary — prove that chain holds
-- for this specific shape of attack, not just for a missing file.
flow.init("tower.json", 3)
flow.pick(zones.find("reveal").cards[1])
local deep_path = "game/games/tmp_deep_nest.json"
local df = assert(io.open(deep_path, "w"))
df:write(string.rep("[", 200000) .. string.rep("]", 200000))
df:close()
eval("load_game:tmp_deep_nest.json")
os.remove(deep_path)
check("a stack-overflow JSON payload recovers to the menu, not a crash",
	declaration.G.title == "Ravel")

-- Parse-level messages need real files: entries with no key, duplicate
-- zone/phase keys, and a section written as an object instead of a list.
local kp = with_fixture([[{
  "templates": [ { "text": "No Key" } ],
  "zones": [
    { "type": "hand", "pos": [0, 0, 1, 1] },
    { "key": "dup", "type": "hand", "pos": [0, 0, 1, 1] },
    { "key": "dup", "type": "hand", "pos": [0, 0, 1, 1] }
  ],
  "stats": [ { "label": "No Key" } ],
  "phases": [
    { "type": "automatic" },
    { "key": "p", "type": "player_input" },
    { "key": "p", "type": "player_input" }
  ]
}]])
check("entries without keys are reported for every kind",
	has_problem(kp, "a template has no") and has_problem(kp, "a zone has no")
	and has_problem(kp, "a stat has no") and has_problem(kp, "a phase has no"))
check("duplicate zone and phase keys are conflicts",
	has_problem(kp, "two zones share the key 'dup'")
	and has_problem(kp, "two phases share the key 'p'"))

local sp = with_fixture('{ "templates": { "key": "x" } }')
check("a section that isn't a list is explained",
	has_problem(sp, "the 'templates' section should be a list"))

-- === random terminator: every game ends at the menu ===
-- All currently legal moves, as closures. Shared by the terminator and the
-- undo fuzz below.
local function legal_moves()
	local moves = {}
	local cur = phase.current()
	if cur and cur.type == "overlay" then
		local oz = zones.find(cur.zone or "hand")
		for _, cid in ipairs(oz and oz.cards or {}) do
			moves[#moves + 1] = function() flow.pick(cid) end
		end
		return moves
	end
	local h = zones.find("hand")
	for _, cid in ipairs(h and h.cards or {}) do
		if flow.can_play(cid) then
			local spec = cards.def(entity.get(cid)).target
			moves[#moves + 1] = function()
				local targets = {}
				if spec then
					targeting.start(cid, spec)
					for k = 1, math.min(spec.min or spec.count or 0, #targeting.eligible) do
						targets[k] = targeting.eligible[k]
					end
					targeting.clear()
				end
				flow.play_card(cid, targets)
			end
		end
	end
	for e in entity.each("card") do
		local z   = entity.get(e.zone_id)
		local def = cards.def(e)
		if z and z.zone_type == "grid" and def and def.on_activate
			and not e.exhausted and flow.can_afford(def.activate_cost) then
			local id = e.id
			moves[#moves + 1] = function() flow.activate(id) end
		end
	end
	return moves
end

-- Random legal moves (with a little undo fuzzing) must reach the menu
-- within a step budget: this catches softlocks nothing else will.
local function random_playthrough(file, seed)
	flow.init(file, seed)
	math.randomseed(seed * 7919)
	for step = 1, 400 do
		if declaration.G.title == "Ravel" then return true end
		local moves = legal_moves()
		if #moves == 0 then return false, "no legal moves at step " .. step end
		if flow.can_undo() and math.random() < 0.04 then
			flow.undo()
		else
			moves[math.random(#moves)]()
		end
	end
	return false, "step budget exhausted"
end

for _, file in ipairs({ "demo.json", "castle.json", "kingdom.json",
	"tower.json", "road.json", "starter_cyoa.json" }) do
	for _, seed in ipairs({ 1, 2, 3 }) do
		local ok, why = random_playthrough(file, seed)
		check(file .. " seed " .. seed .. " terminates at the menu", ok)
		if not ok then print("  " .. file .. " seed " .. seed .. ": " .. tostring(why)) end
	end
end

-- === undo invariant: a random run fully rewinds to its opening state ===
local function fingerprint()
	local parts = {}
	for e in entity.each() do
		local bits = { tostring(e.id), e.kind or "", e.def_key or "",
			tostring(e.zone_id), tostring(e.slot_id), tostring(e.exhausted) }
		local keys = {}
		for k in pairs(e.stats or {}) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do bits[#bits + 1] = k .. "=" .. tostring(e.stats[k]) end
		if e.cards then bits[#bits + 1] = "cards:" .. table.concat(e.cards, ",") end
		if e.kind == "slot" then bits[#bits + 1] = "occ:" .. tostring(e.occupant) end
		parts[#parts + 1] = table.concat(bits, "|")
	end
	local cur = phase.current()
	parts[#parts + 1] = "phase:" .. (cur and cur.key or "-") .. " log:" .. log.count()
	return table.concat(parts, "\n")
end

flow.init("kingdom.json", 11)
math.randomseed(11)
local fp0, steps = fingerprint(), 0
for _ = 1, 12 do
	local moves = legal_moves()
	if #moves == 0 then break end
	moves[math.random(#moves)]()
	steps = steps + 1
end
check("the fuzz run actually moved", steps > 0)
for _ = 1, steps do flow.undo() end
check("undo rewinds a random run to its opening state", fingerprint() == fp0)

-- === scoped subjects: quantifiers ===
-- castle's farm carries "economic"; the throne carries "building" but not
-- "economic", which is what makes the two scopes distinguishable here.
flow.init("castle.json", 7)
eval("fill:board:farm:3")
local board_id  = zones.find_id("board")
local function scope_hp(pred)
	local s = 0
	for e in entity.each("card") do
		if e.zone_id == board_id and pred(e) then s = s + (e.stats.hp or 0) end
	end
	return s
end
local econ_hp = scope_hp(function(e) return e.def_key == "farm" end)
check("three farms are on the board",         predicate.total("card:farm@board") == 3)
check("a pooled tag scope sums its members",  predicate.total("hp@economic") == econ_hp)
check("max: reads the largest, not the sum",  predicate.total("max:hp@economic") == 3)
check("count: can be scoped to a zone",       predicate.total("count:economic@board") == 3)
check("a bare tag count is unchanged",        predicate.total("count:economic") == 3)
check("a wider tag catches the throne too",
	predicate.total("hp@building") == econ_hp + entity.get(find_card("throne_room").id).stats.hp)
check("each: every farm has 3 hp",     predicate.met({ stat = "hp@each.economic", at_least = 3 }))
check("each: not every farm has 4 hp", predicate.met({ stat = "hp@each.economic", at_least = 4 }) == false)
check("any: the pool reaches 9",       predicate.met({ stat = "hp@any.economic", at_least = 9 }))

-- A tag reaches cards in play, never a hand: "@economic" is not "every farm I own".
eval("fill:hand:farm:1")
check("a tag scope ignores cards in hand", predicate.total("hp@economic") == econ_hp)

eval("lose_stat:hp@each.economic:1")
check("each: the effect reached all three", predicate.total("hp@economic") == econ_hp - 3)
eval("lose_stat:hp@any.economic:1")
check("any: the effect reached exactly one", predicate.total("hp@economic") == econ_hp - 4)

-- The rule that stops a cost being free precisely when it cannot be paid.
check("each over an empty scope is false",
	predicate.met({ stat = "hp@each.wyrm", at_least = 1 }) == false)
check("each over an empty scope is unaffordable",
	flow.can_afford({ ["hp@each.wyrm"] = 1 }) == false)
check("each is affordable only if every member can pay",
	flow.can_afford({ ["hp@each.economic"] = 1 })
	and flow.can_afford({ ["hp@each.economic"] = 3 }) == false)

local pooled_before = predicate.total("hp@economic")
actions.spend("hp@any.economic", 4, {})
check("a pooled spend takes exactly what it needs",
	predicate.total("hp@economic") == pooled_before - 4)

-- ctx.targets nil means "not chosen yet" (the gates that dim a card), an empty
-- list means "chose none". Only the first is unjudgeable.
check("a target-paid cost is unjudged before targeting",
	flow.can_afford({ ["hp@target"] = 1 }, { card_id = 1 }))
check("a target-paid cost is refused once nothing is chosen",
	flow.can_afford({ ["hp@target"] = 1 }, { card_id = 1, targets = {} }) == false)

local throne = find_card("throne_room")
check("self reaches the acting card",
	predicate.total("hp@self", { card_id = throne.id }) == throne.stats.hp)
local two = {}
for e in entity.each("card") do
	if e.def_key == "farm" and e.zone_id == board_id and #two < 2 then two[#two + 1] = e end
end
check("target reaches the chosen cards",
	predicate.total("hp@target", { targets = { two[1].id, two[2].id } })
	== two[1].stats.hp + two[2].stats.hp)

-- === the player is a card ===
-- There is no player entity. A game that says nothing gets an invisible card
-- injected from setup.player; one that wants a visible hero tags it. Either
-- way a bare subject and a bare write land on the same card.
flow.init("demo.json", 1)
local kinds = {}
for e in entity.each() do kinds[e.kind] = true end
check("entity kinds are zone, slot and card — nothing else",
	kinds.zone and kinds.slot and kinds.card and kinds.player == nil)

local you = find_card("player")
check("setup.player became a card in the hidden system zone",
	you ~= nil and entity.get(you.zone_id).key == "system")
check("a bare read resolves to that card", predicate.total("hp") == you.stats.hp)
local hp_you = you.stats.hp
eval("lose_stat:hp:1")
check("a bare write lands on the same card it reads from",
	you.stats.hp == hp_you - 1 and predicate.total("hp") == hp_you - 1)

-- The round belongs to the game, not to whoever is holding it: two seats must
-- not get two calendars, and a hero who dies must not take one with them.
local sys = find_card("system")
check("the round counter sits on the system card, not on the player",
	sys ~= nil and sys.stats.round == 1 and you.stats.round == nil)
check("a bare read still reaches it", predicate.total("round") == 1)

-- castle declares its own player, so nothing is injected for it.
flow.init("castle.json", 7)
check("a game that tags its hero gets no injected stat bag",
	find_card("player") == nil and predicate.total("card:player") == 0)
check("the hero is the player card",
	predicate.total("gold@player") == entity.get(find_card("throne_room").id).stats.gold)

-- The bug the whole model exists to make unwriteable: defense used to be a
-- global running total, so a watchtower reduced to rubble defended the castle
-- forever. It is a stat on the tower now, read by an aggregate over the
-- buildings still standing.
local base_defense = predicate.total("sum:defense@standing")
eval("fill:board:watchtower:1")
local tower = find_card("watchtower", "board")
check("a watchtower defends the castle",
	predicate.total("sum:defense@standing") == base_defense + 2)
tower.stats.hp = 0
check("a ruined watchtower stops defending",
	predicate.total("sum:defense@standing") == base_defense)

-- === a party of players ===
-- The test of whether "the player is a card" is the right model: four
-- characters with their own stats, needing no new engine concept at all.
local function play_fixture(content, seed)
	local path = "game/games/tmp_play_test.json"
	local f = assert(io.open(path, "w"))
	f:write(content)
	f:close()
	local ok, err = pcall(flow.init, "tmp_play_test.json", seed)
	os.remove(path)
	if not ok then error(err, 2) end
end

play_fixture([[{
  "title": "The Company",
  "stats": [
    { "key": "might", "label": "Might", "subject": "sum:might@party" },
    { "key": "mana",  "label": "Mana" }
  ],
  "zones": [
    { "key": "party", "type": "grid", "pos": [0.0, 0.0, 0.8, 0.5], "grid": [4, 1],
      "tags": ["activate"] },
    { "key": "hand",  "type": "hand", "pos": [0.19, 0.62, 0.97, 0.97] }
  ],
  "phases": [ { "key": "adventuring", "type": "player_input", "label": "Adventuring" } ],
  "templates": [
    { "key": "ranger", "text": "Ranger", "tags": ["player", "ranger"],
      "card_stats": { "hp": 6, "might": 3 }, "auto_play": true, "to_zone": "party" },
    { "key": "cleric", "text": "Cleric", "tags": ["player", "cleric"],
      "card_stats": { "hp": 5, "might": 2 }, "auto_play": true, "to_zone": "party" },
    { "key": "dwarf",  "text": "Dwarf",  "tags": ["player", "dwarf"],
      "card_stats": { "hp": 8, "might": 4 }, "auto_play": true, "to_zone": "party" },
    { "key": "mage",   "text": "Mage",   "tags": ["player", "mage"],
      "card_stats": { "hp": 4, "might": 1, "mana": 3 },
      "auto_play": true, "to_zone": "party",
      "activate_cost": { "mana@self": 1 },
      "on_activate":   ["gain_stat:might@self:1"] }
  ]
}]], 1)

check("a party fixture validates clean", #validate.check(declaration.G) == 0)
check("four characters, no injected stat bag",
	zone_count("party") == 4 and find_card("player") == nil)
check("the party's might is an aggregate over the zone",
	predicate.total("sum:might@party") == 10)
check("each character is addressable on its own",
	predicate.total("might@ranger") == 3 and predicate.total("might@mage") == 1)
-- Honest about the hot-seat gap: several cards tagged "player" means a bare
-- subject is the whole company. Telling them apart by seat is idea 02's job.
check("a bare subject is every player card at once", predicate.total("might") == 10)

local mage = find_card("mage")
check("a character pays from her own mana",
	flow.can_afford({ ["mana@self"] = 1 }, { card_id = mage.id }))
check("one who has none cannot",
	flow.can_afford({ ["mana@self"] = 1 }, { card_id = find_card("dwarf").id }) == false)
flow.activate(mage.id, {})
check("the cost came out of her own pool, and the gain went to her",
	mage.stats.mana == 2 and mage.stats.might == 2
	and predicate.total("sum:might@party") == 11)

zones.destroy_card(find_card("dwarf").id)
check("a character who dies takes her might with her",
	predicate.total("sum:might@party") == 7)

-- === two seats ===
-- A zone can belong to a seat, and an unqualified key means the active seat's.
-- Ownership is a third axis beside scope and quantifier: every combination of
-- the three is meaningful, which is the test that it belongs beside them.
play_fixture([==[{
  "title": "The Duel",
  "stats": [ { "key": "gold", "label": "Gold" } ],
  "zones": [
    { "key": "arena", "type": "grid", "grid": [3, 1], "per_seat": true,
      "pos": [[0.02, 0.05, 0.60, 0.30], [0.02, 0.32, 0.60, 0.57]] },
    { "key": "hand", "type": "hand", "per_seat": true,
      "pos": [[0.19, 0.62, 0.97, 0.78], [0.19, 0.80, 0.97, 0.97]] },
    { "key": "commons", "type": "grid", "pos": [0.62, 0.05, 0.98, 0.30], "grid": [2, 1] }
  ],
  "phases": [
    { "key": "north_turn", "type": "player_input", "label": "North", "seat": "next" },
    { "key": "south_turn", "type": "player_input", "label": "South", "seat": "next" }
  ],
  "templates": [
    { "key": "north", "text": "North", "tags": ["player", "north_side"], "card_stats": { "gold": 5 } },
    { "key": "south", "text": "South", "tags": ["player", "south_side"], "card_stats": { "gold": 2 } },
    { "key": "wolf",  "text": "Wolf",  "tags": ["creature"], "card_stats": { "hp": 3 } },
    { "key": "statue","text": "Statue","tags": ["creature"], "card_stats": { "hp": 9 } },
    { "key": "banner","text": "Banner","tags": ["gear"],
      "target": { "type": "card", "tags": ["creature"], "count": 1, "zones": ["arena", "commons"] },
      "on_play": ["move_to:target"] }
  ]
}]==], 1)

check("a two-seat fixture validates clean", #validate.check(declaration.G) == 0)
check("both seats exist, neither on a board",
	find_card("north") ~= nil and find_card("south") ~= nil
	and entity.get(find_card("north").zone_id).key == "system")
-- A seat is addressable two ways: by an ordinary tag it carries, and by the
-- owner words — which reach it even though it sits in a shared zone, because a
-- seat card is its own seat.
check("each seat keeps its own stats",
	predicate.total("gold@north_side") == 5 and predicate.total("gold@south_side") == 2)
check("the owner words reach the seat cards themselves",
	predicate.total("gold@mine.player") == 5 and predicate.total("gold@enemy.player") == 2)

-- The per-seat zone is instanced, and a bare key means the active seat's.
local north_arena = zones.find("arena")
check("north is on the clock", zones.active_seat() == "north")
check("a per_seat zone is one entity per seat", #zones.all_with_key("arena") == 2)
eval("fill:arena:wolf:1")
eval("fill:enemy.arena:wolf:2")
eval("fill:commons:statue:1")
check("a bare key filled the active seat's arena", #north_arena.cards == 1)
check("an owner word filled the other one", #zones.find("arena", "enemy").cards == 2)

-- The three owner words over the same tag.
check("mine sees only my creatures", predicate.total("count:creature@mine.creature") == 1)
check("enemy sees only theirs",      predicate.total("count:creature@enemy.creature") == 2)
-- "anyone" filters by nothing, exactly as writing no owner word does. It earns
-- its place by saying so out loud on a card that means everyone's, not as a
-- different set from the bare form.
check("anyone is the bare form, said explicitly",
	predicate.total("count:creature@anyone.creature") == 4
	and predicate.total("count:creature@creature") == 4)
check("and both include the unowned statue in the shared zone",
	predicate.total("count:creature@mine.creature")
	+ predicate.total("count:creature@enemy.creature") == 3)
check("hp sums follow the same words",
	predicate.total("hp@mine.creature") == 3 and predicate.total("hp@enemy.creature") == 6)

-- Ownership composes with the quantifier rather than replacing it.
eval("lose_stat:hp@each.enemy.creature:1")
check("each.enemy reached both of theirs and none of mine",
	predicate.total("hp@enemy.creature") == 4 and predicate.total("hp@mine.creature") == 3)

-- destroy: takes a scope expression now, and a bare zone key is one.
eval("destroy:each.enemy.creature")
check("a board wipe spared my own",
	#zones.find("arena", "enemy").cards == 0 and #north_arena.cards == 1)
eval("destroy:commons")
check("destroy:<zone> still means what it always did", zone_count("commons") == 0)

-- The play gate: a card in the other seat's zone is not yours to play.
local mine  = cards.create("wolf", zones.find_id("hand"))
local yours = cards.create("wolf", zones.find_id("hand", "enemy"))
check("I can play from my own hand", flow.can_play(mine.id))
check("I cannot play out of the other seat's hand", flow.can_play(yours.id) == false)

-- Handover: the seat rotates, the bare key follows it, and undo does not
-- survive the handover.
flow.play_card(mine.id, {})
check("undo is available within a turn", flow.can_undo())
phase.next()
flow.settle()
check("the seat rotated", zones.active_seat() == "south")
check("the bare key now means the other arena", zones.find("arena").id ~= north_arena.id)
check("mine and enemy swapped with it",
	predicate.total("count:creature@enemy.creature") == 1
	and predicate.total("count:creature@mine.creature") == 0)
check("now south may play what north could not", flow.can_play(yours.id))
check("undo history did not cross the handover", flow.can_undo() == false)

-- A target spec that names zones means yours, exactly as a destination does,
-- so it never offers the other seat's copy of one. move_to:target then puts
-- the acting card where the player pointed — the only way one card can offer
-- two destinations, which is what "advance or discard" needs.
eval("fill:arena:wolf:1")          -- south's arena now, the seat having rotated
eval("fill:commons:statue:1")
local banner = cards.create("banner", zones.find_id("hand"))
targeting.start(banner.id, cards.def(banner).target, "play")
local offered = {}
for _, id in ipairs(targeting.eligible) do
	offered[entity.get(entity.get(id).zone_id).key] = true
end
check("a zone-named spec offers mine and the shared one, never the other seat's",
	offered.arena and offered.commons and #targeting.eligible == 2)
local south_wolf = zones.find("arena").cards[1]
targeting.clear()
flow.play_card(banner.id, { south_wolf })
check("move_to:target put the card where the player pointed",
	entity.get(banner.id).zone_id == zones.find_id("arena"))

-- === a shared board with owned pieces ===
-- Everything a board game needs before a piece can be said to move: squares
-- that know where they are, pieces that know whose they are while sharing one
-- zone, a way to point at an occupied square, and a way to take what stands
-- there.
play_fixture([==[{
  "title": "Skirmish",
  "zones": [
    { "key": "board", "type": "grid", "grid": [3, 3], "pos": [0.02, 0.05, 0.60, 0.60],
      "tags": ["activate"] },
    { "key": "taken", "type": "pile", "pos": [0.62, 0.05, 0.98, 0.40] },
    { "key": "hand",  "type": "hand", "pos": [0.19, 0.62, 0.97, 0.97] }
  ],
  "phases": [ { "key": "battle", "type": "player_input", "label": "Battle" } ],
  "templates": [
    { "key": "white", "text": "White", "tags": ["player"] },
    { "key": "black", "text": "Black", "tags": ["player"] },
    { "key": "w_rook", "text": "White Rook", "tags": ["white", "piece"],
      "auto_play": true, "to_zone": "board",
      "activate_target": { "type": "slot", "zones": ["board"], "fill": "open", "count": 1 },
      "on_activate": ["move_to:target:taken"] },
    { "key": "w_ghost", "text": "White Ghost", "tags": ["white", "piece"],
      "auto_play": true, "to_zone": "board",
      "activate_target": { "type": "slot", "zones": ["board"], "fill": "open", "count": 1 },
      "on_activate": ["move_to:target"] },
    { "key": "b_pawn", "text": "Black Pawn", "tags": ["black", "piece"],
      "auto_play": true, "to_zone": "board",
      "activate_target": { "type": "slot", "zones": ["board"], "fill": "empty", "count": 1 },
      "on_activate": ["move_to:target"] }
  ]
}]==], 3)

check("a board fixture validates clean", #validate.check(declaration.G) == 0)

local function slot_of(card) return entity.get(entity.get(card.id).slot_id) end
local rook, ghost, pawn = find_card("w_rook"), find_card("w_ghost"), find_card("b_pawn")

-- Squares carry their own coordinates, so a condition reads them with the
-- vocabulary it already has rather than a second one invented for boards.
check("a slot knows where it is, as ordinary stats",
	slot_of(rook).stats.col == 1 and slot_of(rook).stats.row == 1
	and slot_of(pawn).stats.col == 3 and slot_of(pawn).stats.row == 1)
check("a square is readable as a subject once it is the target",
	predicate.total("row@target", { targets = { slot_of(pawn).id } }) == 1
	and predicate.total("col@target", { targets = { slot_of(pawn).id } }) == 3)

-- One board, two owners. The zone has no seat at all, so this can only come
-- from the pieces themselves.
check("a piece on a shared board belongs to the seat it names",
	predicate.owner_of(rook) == "white" and predicate.owner_of(pawn) == "black")
check("the board itself still belongs to nobody", zones.find("board").seat == nil)
check("mine and enemy tell the pieces apart",
	predicate.total("count:piece@mine.board") == 2
	and predicate.total("count:piece@enemy.board") == 1)
check("you may act with your pieces and not your opponent's",
	flow.can_activate(rook.id) and flow.can_activate(pawn.id) == false)

-- Nine squares, three of them taken. What "fill" offers is the whole of the
-- difference between placing a card and capturing one.
local function offered(card, fill)
	return #targeting.candidates(card.id,
		{ type = "slot", zones = { "board" }, fill = fill, count = 1 })
end
check("fill defaults to the empty squares, as it always did",
	offered(rook, nil) == 6 and offered(rook, "empty") == 6)
check("open adds the squares an enemy stands on", offered(rook, "open") == 7)
check("enemy offers only those", offered(rook, "enemy") == 1)
check("any offers the whole board", offered(rook, "any") == 9)
check("your own pieces are never something to land on",
	offered(rook, "open") == offered(rook, "empty") + 1)

local victim_slot = slot_of(pawn).id
local ghost_slot  = slot_of(ghost).id

-- Saying nothing about the occupant still means "refuse", which is what every
-- game written before board movement assumed. The ability runs either way — it
-- is the move inside it that declines.
check("a move that says nothing about the occupant is refused",
	flow.activate(ghost.id, { victim_slot })
	and entity.get(ghost.id).slot_id == ghost_slot
	and entity.get(victim_slot).occupant == pawn.id)

-- Capture. The taken piece leaves first, so the square it was standing on is
-- free by the time the attacker arrives.
check("an occupied square is a legal target once fill says so",
	flow.activate(rook.id, { victim_slot }))
check("the attacker is standing where the defender was",
	entity.get(rook.id).slot_id == victim_slot)
check("and the defender is in the tray, not in play",
	entity.get(pawn.id).zone_id == zones.find_id("taken"))
check("the vacated square is genuinely the attacker's now",
	entity.get(victim_slot).occupant == rook.id)

-- === four seats: where a thing is, versus whose it is ===
-- These come apart as soon as a game has more than two players. A planet held
-- by player three, sitting inside player two's system, is player three's to
-- lose and player one's to attack — so the piece's own claim has to outrank the
-- seat of the zone holding it, and every owner word has to agree.
play_fixture([==[{
  "title": "Four Empires",
  "zones": [
    { "key": "system", "type": "grid", "grid": [2, 1], "per_seat": true, "tags": ["activate"],
      "pos": [[0.02, 0.05, 0.30, 0.30], [0.32, 0.05, 0.60, 0.30],
              [0.02, 0.32, 0.30, 0.57], [0.32, 0.32, 0.60, 0.57]] },
    { "key": "hand", "type": "hand", "pos": [0.19, 0.62, 0.97, 0.97] }
  ],
  "phases": [ { "key": "turn", "type": "player_input", "label": "Turn" } ],
  "templates": [
    { "key": "p1", "text": "Empire One",   "tags": ["player"] },
    { "key": "p2", "text": "Empire Two",   "tags": ["player"] },
    { "key": "p3", "text": "Empire Three", "tags": ["player"] },
    { "key": "p4", "text": "Empire Four",  "tags": ["player"] },
    { "key": "colony",  "text": "Colony",  "tags": ["p3", "planet"] },
    { "key": "capital", "text": "Capital", "tags": ["p2", "planet"] },
    { "key": "cruiser", "text": "Cruiser", "tags": ["p1", "ship"],
      "activate_target": { "type": "card", "zones": ["system"], "tags": ["planet"],
                           "owner": "enemy", "count": 1 },
      "on_activate": ["destroy:target"] }
  ]
}]==], 5)

check("a four-seat fixture validates clean", #validate.check(declaration.G) == 0)
local sys = zones.all_with_key("system")
check("a per_seat zone instanced once per seat", #sys == 4 and zones.active_seat() == "p1")

-- Player three's colony, parked inside player two's system.
local colony  = cards.create("colony",  sys[2].id)
local capital = cards.create("capital", sys[2].id)
local cruiser = cards.create("cruiser", sys[1].id)
zones.auto_slot(colony.id); zones.auto_slot(capital.id); zones.auto_slot(cruiser.id)

check("the colony sits in player two's system", colony.zone_id == sys[2].id)
check("but it belongs to player three, who is not the seat of that zone",
	predicate.owner_of(colony) == "p3" and sys[2].seat == "p2")
check("a piece with no claim of its own still belongs to the zone's seat",
	predicate.owner_of(capital) == "p2")

-- Every owner word has to agree, or "attack that planet" works in the targeting
-- arrow and is refused by the rules, or the other way about.
check("enemy reaches both foreign planets wherever they physically sit",
	predicate.total("count:planet@enemy.system") == 2)
check("mine reaches neither", predicate.total("count:planet@mine.system") == 0)
check("player one may not act with a piece in someone else's colours",
	flow.can_activate(colony.id) == false and flow.can_activate(cruiser.id))

local shots = targeting.candidates(cruiser.id, cards.def(cruiser).activate_target)
local shot_at = {}
for _, id in ipairs(shots) do shot_at[entity.get(id).def_key] = true end
check("player one may attack a planet in player two's system that player three holds",
	shot_at.colony and shot_at.capital and #shots == 2)
check("and the rules gate agrees, so the shot actually lands",
	flow.activate(cruiser.id, { colony.id }) and entity.get(colony.id).zone_id == nil)

-- === comparisons and products ===
-- Two gaps a real published game found: a gate that compares downwards, and a
-- multiplication that repeated addition cannot stand in for.
flow.init("castle.json", 7)
eval("fill:board:watchtower:2")
check("a bare number in a map still means at_least",
	predicate.meets_all({ ["sum:defense@standing"] = 4 })
	and predicate.meets_all({ ["sum:defense@standing"] = 5 }) == false)
check("a comparison map can ask the other way",
	predicate.meets_all({ ["sum:defense@standing"] = { at_most = 4 } })
	and predicate.meets_all({ ["sum:defense@standing"] = { at_most = 3 } }) == false)
check("and can ask for exactly", predicate.meets_all({ ["max:hp@building"] = { equals = 20 } }))
check("a malformed comparison fails closed, it does not crash",
	predicate.meets_all({ gold = { at_most = "lots" } }) == false)

local throne = find_card("throne_room")
throne.stats.gold = 0
eval("gain_stat:gold:sum:defense@standing:x:count:military")
check("a product multiplies two measured terms", throne.stats.gold == 8)
eval("set_stat:gold:3:x:2")
check("plain numbers multiply too", throne.stats.gold == 6)
eval("gain_stat:gold:sum:defense@standing")
check("a sum: term needs no product to be an amount", throne.stats.gold == 10)

-- === lost cities ===
-- A real published two-player game. Its rule — a card may advance an
-- expedition only if it is worth at least what is already there, but may
-- always be discarded — is legality that depends on both cards at once, which
-- is what "accepts" on the destination exists for.
flow.init("lost_cities.json", 11)
dismiss_mode()

do   -- scoped: Lua 5.4 allows only 200 live locals in the main chunk,
     -- and these are all Lost Cities' own
	local function has(list, id)
		for _, v in ipairs(list) do if v == id then return true end end
		return false
	end
	local function drawn(key)
		eval("fill:hand:" .. key .. ":1")
		local c = find_card(key, "hand")
		return c, targeting.candidates(c.id, cards.def(c).target)
	end

	-- A place to put a card is a zone, not a marker card standing in one.
	local my_red   = zones.find("red")
	local red_pile = zones.find("red_discard")
	check("both seats got their own expedition, not one between them",
		#zones.all_with_key("red") == 2 and zones.find("red", "enemy").id ~= my_red.id)
	check("setup dealt eight cards to each seat",
		#zones.find("hand", "mine").cards == 8 and #zones.find("hand", "enemy").cards == 8)
	check("nothing is standing in the expedition to be pointed at",
		#my_red.cards == 0 and #red_pile.cards == 0)

	local c7, k7 = drawn("red_7")
	check("an empty expedition accepts anything", has(k7, my_red.id) and has(k7, red_pile.id))
	check("and never the other seat's expedition",
		has(k7, zones.find("red", "enemy").id) == false)
	flow.play_card(c7.id, { my_red.id })
	check("the card advanced the expedition", #my_red.cards == 1)

	local c5, k5 = drawn("red_5")
	check("a lower card is refused by the expedition", has(k5, my_red.id) == false)
	check("but may always be discarded", has(k5, red_pile.id))
	check("flow refuses an illegal target even when handed one directly",
		flow.play_card(c5.id, { my_red.id }) == false)

	local cw = drawn("red_w1")
	local _, kw = cw, select(2, drawn("red_w2"))
	check("a wager cannot follow a number", has(kw, my_red.id) == false)

	check("a full expedition holds all three wagers and all nine numbers",
		#my_red.slots == 12)

	-- The scoring arithmetic, end to end: (sum - 20) x (1 + wagers), written as
	-- (sum - 20) plus (sum - 20) x wagers because a product cannot add one
	-- inside itself. Red holds a single 7 here, and no wagers.
	local score0 = predicate.total("score@mine.player")
	eval("gain_stat:score@mine.player:sum:value@mine.red")
	eval("lose_stat:score@mine.player:20")
	eval("gain_stat:score@mine.player:sum:value@mine.red:x:count:wager@mine.red")
	eval("lose_stat:score@mine.player:20:x:count:wager@mine.red")
	check("an expedition scores (sum - 20) x (1 + wagers)",
		predicate.total("score@mine.player") == score0 - 13)
end

-- Taking from a discard is the pile's top card offering an ability, granted by
-- the pile through "applies" and confined to the draw step by "phases". Every
-- check below is a bug that shipped in an earlier shape: the pile's on_click
-- ran in any phase (so the play step could be spent on a second draw), an empty
-- pile handed over the marker that said where discards go, and once anything
-- covered that marker the colour could never be discarded to again.
do
	local function hand_size() return #zones.find("hand", "mine").cards end
	local function pile(key) return zones.find(key) end
	local function top_of(key)
		local z = pile(key)
		return z.cards[#z.cards]
	end

	flow.init("lost_cities.json", 11)
	dismiss_mode()
	check("both seats share one play step and one draw step",
		phase.current().key == "play" and declaration.G.phase_by_key.north_play == nil)
	check("the draw option is not on the table during the play step",
		#zones.find("choice").cards == 0)

	-- Discard one card, which is what carries us into the draw step.
	local c = entity.get(zones.find("hand", "mine").cards[1])
	local dest
	for _, id in ipairs(targeting.candidates(c.id, cards.def(c).target)) do
		if entity.get(id).key:match("_discard$") then dest = id end
	end
	local pile_key = entity.get(dest).key
	flow.play_card(c.id, { dest })
	check("discarding puts the card on the pile and reaches the draw step",
		phase.current().key == "draw" and #pile(pile_key).cards == 1)

	local empty = pile_key == "red_discard" and "green_discard" or "red_discard"
	check("an empty pile has no top card to take", top_of(empty) == nil)
	check("the pile you just discarded to offers its top card",
		flow.can_activate(top_of(pile_key)) == true)
	check("a hand card cannot be played during the draw step",
		flow.can_play(zones.find("hand", "mine").cards[1]) == false)

	local before = hand_size()
	flow.activate(top_of(pile_key), {})
	check("taking the top of a pile draws it and hands over",
		hand_size() == before + 1 and #pile(pile_key).cards == 0
		and phase.current().key == "play")
	check("and the draw option is swept off the table", #zones.find("choice").cards == 0)

	-- The bug the stack rule exists for: discard twice to the same colour.
	-- Whichever card in hand is the right colour for that pile.
	local function discard_once()
		for _, cid in ipairs(zones.find("hand", "mine").cards) do
			local card = entity.get(cid)
			for _, id in ipairs(targeting.candidates(cid, cards.def(card).target)) do
				if entity.get(id).key == pile_key then
					return flow.play_card(cid, { id })
				end
			end
		end
		return false
	end
	local first = discard_once()
	flow.play_card(zones.find("choice").cards[1], {})   -- draw from the deck, hand over
	check("a pile with a card on it is still a legal place to discard",
		first and discard_once() and #pile(pile_key).cards == 2)
	check("and the card underneath the top one cannot be taken",
		flow.can_activate(pile(pile_key).cards[1]) == false)

	-- The pile's ability is the pile's, not the card's: the same card in a hand
	-- has none, and no card may be taken outside the draw step.
	flow.play_card(zones.find("choice").cards[1], {})   -- draw, back to a play step
	check("the top of a pile is inert during the play step",
		phase.current().key == "play" and flow.can_activate(top_of(pile_key)) == false)

	-- Presentation reads the granted ability too, or the only discoverable fact
	-- about a pickup is that clicking sometimes does nothing.
	local top = entity.get(top_of(pile_key))
	-- Where a card is decides what it can do: the zone answers first, and the
	-- card's own definition answers only where the zone is silent.
	local in_hand = entity.get(zones.find("hand", "mine").cards[1])
	check("the zone it lies in decides its behaviour",
		cards.behaviour(top, "on_activate") ~= nil
		and cards.behaviour(top, "tooltip") == "Take this card into your hand.")
	check("and the card answers for itself where the zone says nothing",
		cards.behaviour(top, "target") == cards.def(top).target
		and cards.behaviour(in_hand, "on_activate") == nil
		and cards.behaviour(in_hand, "tooltip") == cards.def(in_hand).tooltip)
	check("the zone's grant is separately readable, so prose can show both",
		cards.zone_grant(top, "tooltip") == "Take this card into your hand."
		and cards.zone_grant(in_hand, "tooltip") == nil)
end

-- "immutable" is scenery: the interface is a game like any other, so the
-- live-edit tools and every targeting spec point straight at it unless
-- something says not to.
do
	flow.init("menu.json")
	local ok, why = cards.edit("play_castle", "text", '"HACKED"')
	check("an immutable card refuses a template edit",
		ok == false and tostring(why):find("immutable") ~= nil
		and declaration.G.card_defs.play_castle.text == "Castle Lord")
	local menu = zones.find("menu")
	check("and nothing can target it",
		#menu.cards > 0
		and #targeting.candidates(menu.cards[1], { type = "card", count = 1, zones = { "menu" } }) == 0)

	flow.init("castle.json", 7)
	check("an ordinary card is still editable in place",
		cards.edit("farm", "text", '"Renamed"') == true
		and declaration.G.card_defs.farm.text == "Renamed")

	-- === subject grammar ===
	-- Pure parsing, no game loaded: the one place the scope syntax is decided.
end

local function subj(s)
	local p = predicate.parse_subject(s)
	if not p then return "nil" end
	return table.concat({ p.fn or "-", p.arg or "-", p.quant or "-", p.scope or "-" }, "/")
end
check("a bare stat has no scope",            subj("gold") == "-/gold/-/-")
check("a tag scope defaults to any",         subj("hp@follower") == "-/hp/any/follower")
check("an explicit each quantifier",         subj("hp@each.follower") == "-/hp/each/follower")
check("an explicit random quantifier",       subj("hp@random.follower") == "-/hp/random/follower")
check("targets default to each, not any",    subj("hp@target") == "-/hp/each/target")
check("self is a scope, not a quantifier",   subj("hp@self") == "-/hp/any/self")
check("fn forms take a scope too",           subj("count:farm@board") == "count/farm/any/board")
check("sum over a zone",                     subj("sum:defense@board") == "sum/defense/any/board")
check("card: is still a fn",                 subj("card:king") == "card/king/-/-")
check("an unknown fn is part of the name",   subj("wibble:farm") == "-/wibble:farm/-/-")
check("an unknown quantifier is the scope",  subj("hp@some.tag") == "-/hp/any/some.tag")
check("a non-string subject is nil",         subj(nil) == "nil")
check("an empty subject is nil",             subj("@board") == "nil")

-- === placeholder art ===
-- Parsing is pure — no love, no state — which is why the validator can check a
-- spec at load time and why this runs headless. Drawing is covered by
-- tests/render_smoke.lua.
local art = require("art")
local function spec(s)
	local p = art.parse(s)
	if not p then return "nil" end
	return string.format("%s/%s/%02x%02x%02x", p.shape, tostring(p.n),
		math.floor(p.fg[1] * 255 + 0.5), math.floor(p.fg[2] * 255 + 0.5),
		math.floor(p.fg[3] * 255 + 0.5))
end
check("a shape and a named colour",      spec("circle:teal"):match("^circle/nil/") ~= nil)
check("a counted shape",                 spec("polygon:5:green"):match("^polygon/5/") ~= nil)
check("a hex colour is taken literally", spec("square:#ff8000") == "square/nil/ff8000")
check("a count is clamped to the shape", art.parse("polygon:99:red").n == 12
	and art.parse("polygon:1:red").n == 3)
check("a shape with no count ignores one", art.parse("circle:4:red").n == nil)
check("an unknown shape is not art",     spec("hexagram:red") == "nil")
check("an unknown colour is not art",    spec("circle:puce") == "nil")
check("a missing colour is not art",     spec("circle") == "nil")
check("trailing junk is a typo",         spec("circle:red:navy:extra") == "nil")
check("a filename is never a shape",     spec("castle_hill.jpg") == "nil")
check("a non-string is not art",         spec(nil) == "nil" and spec(42) == "nil")
check("one colour still gets a backdrop",
	art.parse("circle:teal").bg ~= nil and art.parse("circle:teal").bg[1] < 0.3)

-- auto must be stable: same key, same art, on every machine and every run,
-- and it must never consume an RNG draw or it would shift the shuffle.
math.randomseed(1)
local a1 = art.auto("watchtower")
math.randomseed(999)
local a2 = art.auto("watchtower")
check("auto art is derived from the key, not the RNG", a1 == a2)
check("auto art parses as a real spec", art.parse(a1) ~= nil)
check("different keys get different art", art.auto("watchtower") ~= art.auto("farm"))

-- The trap this feature exists to avoid: art must never be reachable from the
-- rules. Nothing below the presentation line may require it.
for _, mod in ipairs({ "predicate", "actions", "flow", "zones", "phase", "entity", "tags" }) do
	local src = assert(io.open("game/" .. mod .. ".lua")):read("*a")
	check(mod .. " does not require art", src:find('require%("art"%)') == nil)
end

-- === the engine's own RNG ===
-- The point of rng.lua is that a seed means one sequence everywhere, so the
-- test that matters is against a published reference rather than against
-- itself. This is std::minstd_rand: the C++ standard requires that seeding
-- with 1 and drawing 10000 values yields 399268537.
do
	local rng = require("rng")
	rng.seed(1)
	local x
	for _ = 1, 10000 do x = rng.next() end
	check("minstd_rand matches the published test vector", x == 399268537)

	rng.seed(42)
	local first = {}
	for i = 1, 8 do first[i] = rng.int(6) end
	rng.seed(42)
	local again = true
	for i = 1, 8 do again = again and rng.int(6) == first[i] end
	check("the same seed replays the same rolls", again)

	for _, n in ipairs({ 1, 2, 6, 52 }) do
		local ok = true
		for _ = 1, 200 do
			local v = rng.int(n)
			ok = ok and v >= 1 and v <= n and v == math.floor(v)
		end
		check("rng.int stays in 1.." .. n, ok)
	end

	-- One integer of state, which is what lets undo and the wire format carry
	-- it without knowing anything about generators.
	rng.seed(99)
	rng.int(6); rng.int(6)
	local mark, after = rng.state(), { rng.int(100), rng.int(100), rng.int(100) }
	rng.set_state(mark)
	check("restoring the state replays the same draws",
		rng.int(100) == after[1] and rng.int(100) == after[2] and rng.int(100) == after[3])

	local deck = {}
	for i = 1, 52 do deck[i] = i end
	rng.seed(5)
	rng.shuffle(deck)
	local seen, all = {}, true
	for _, v in ipairs(deck) do seen[v] = true end
	for i = 1, 52 do all = all and seen[i] end
	check("shuffle is a permutation", all and #deck == 52)

	-- The reason this module exists at all: no math.random below the
	-- presentation line, where fx.lua's particle jitter deliberately keeps it.
	for _, mod in ipairs({ "zones", "actions", "flow", "predicate", "targeting" }) do
		local src = assert(io.open("game/" .. mod .. ".lua")):read("*a")
		check(mod .. " does not use the host RNG", src:find("math%.random%a*%s*%(") == nil)
	end
end

-- An undo across a shuffle has to replay that shuffle, not a different one:
-- the generator's position is state like any other, so it rides in the
-- checkpoint. Without that, undo-then-redo quietly deals a different hand.
do
	local rng = require("rng")
	flow.init("castle.json", 11)
	local hand = zones.find("hand")
	flow.play_card(hand.cards[1], {})
	local after = rng.state()
	zones.shuffle(zones.find_id("build_deck"))
	local shuffled = table.concat(zones.find("build_deck").cards, ",")
	flow.undo()
	check("undo restores the RNG position", rng.state() == after)

	-- Re-fetch: undo replaced every entity table (invariant 1). Replaying the
	-- same deck from the same position has to deal the same order.
	flow.play_card(zones.find("hand").cards[1], {})
	zones.shuffle(zones.find_id("build_deck"))
	check("the replayed shuffle is the same shuffle",
		table.concat(zones.find("build_deck").cards, ",") == shuffled)
end

-- === calling a local before it is declared ===
-- Lua does not complain: the name simply resolves as a global, is nil, and the
-- call fails at runtime, on whatever path happens to reach it first. That cost
-- a browser round trip to find once (netpanel's refresh calling an invitable()
-- declared fifty lines below it), which is fifty times longer than this check
-- takes to run.
do
	local names = {}
	local ls = io.popen("ls game/*.lua")
	for l in ls:lines() do names[#names + 1] = l end
	ls:close()
	check("there are modules to scan", #names > 10)

	local bad = {}
	for _, path in ipairs(names) do
		local lines = {}
		for l in io.lines(path) do lines[#lines + 1] = l end
		local declared = {}
		for i, l in ipairs(lines) do
			local n = l:match("^%s*local%s+function%s+([%w_]+)%s*%(")
			if n and not declared[n] then declared[n] = i end
		end
		for name, decl in pairs(declared) do
			for i = 1, decl - 1 do
				local l = lines[i]:gsub("%-%-.*$", "")   -- calls in comments are prose
				-- A bare call, not a field or method access on something else.
				if l:find("[^%w_%.:]" .. name .. "%s*%(") or l:find("^" .. name .. "%s*%(") then
					bad[#bad + 1] = ("%s:%d calls %s(), declared at %d"):format(path, i, name, decl)
				end
			end
		end
	end
	check("no local function is called before it is declared",
		#bad == 0, table.concat(bad, "; "))
end

-- === the wire's own encoding ===
-- base64 and LZSS are hand-rolled so that one format works on every host, which
-- means they get tested like the load-bearing things they are: a decoder that
-- drops a byte corrupts a game state in a way nobody would trace back here.
do
	local netpack = require("netpack")

	local cases = { "", "a", "ab", "abc", "abcd",
		("a"):rep(64), ("abc"):rep(400), ("the quick brown fox "):rep(50),
		"\0\1\2\254\255", "\0", ("\0"):rep(100), '{"a":1,"a":1,"a":1}' }
	local every = {}
	for i = 0, 255 do every[#every + 1] = string.char(i) end
	cases[#cases + 1] = table.concat(every)                    -- every byte value
	cases[#cases + 1] = table.concat(every) .. table.concat(every)
	local noise = {}
	for i = 1, 500 do noise[i] = string.char((i * 37 + i * i) % 256) end
	cases[#cases + 1] = table.concat(noise)

	local b64_ok, lz_ok, both_ok = 0, 0, 0
	for _, c in ipairs(cases) do
		if netpack.decode(netpack.encode(c)) == c then b64_ok = b64_ok + 1 end
		if netpack.decompress(netpack.compress(c)) == c then lz_ok = lz_ok + 1 end
		if netpack.decode(netpack.encode(netpack.compress(c))) == netpack.compress(c) then
			both_ok = both_ok + 1
		end
	end
	check("base64 round-trips every case", b64_ok == #cases, b64_ok .. "/" .. #cases)
	check("lzss round-trips every case", lz_ok == #cases, lz_ok .. "/" .. #cases)
	check("the two compose", both_ok == #cases, both_ok .. "/" .. #cases)

	-- Overlapping copies are how a run of one byte is encoded, so this is the
	-- case a naive "slice from the output" decoder gets wrong.
	check("lzss handles overlapping matches",
		netpack.decompress(netpack.compress(("xy"):rep(500))) == ("xy"):rep(500))

	-- Compression has to actually pay on the thing it exists for.
	flow.init("lost_cities.json", 7)
	dismiss_mode()
	local text = json.encode(require("net").snapshot())
	local small = netpack.compress(text)
	check("a game state compresses at least three-fold", #small * 3 < #text,
		#text .. " -> " .. #small)
	check("...losslessly", netpack.decompress(small) == text)

	-- Garbage in must not mean a crash or a wrong answer out.
	check("a truncated stream decodes to nil or a prefix",
		pcall(netpack.decompress, small:sub(1, 40)))
	check("base64 rejects a corrupt body", netpack.decode("!!!!") == "")
end

-- === networked play ===
-- One process cannot hold two engines, so "the other client" is played by
-- rewinding to the state both sides shared and applying what arrived. That is
-- exactly what the far machine does, minus the wire.
do
	local net = require("net")

	local function first_playable()
		local cur = phase.current()
		local z   = cur and zones.find(cur.zone or "hand")
		for _, cid in ipairs(z and z.cards or {}) do
			if flow.can_play(cid) then
				local spec = cards.def(entity.get(cid)).target
				local want = spec and (spec.min or spec.count or 0) or 0
				local targets = {}
				if want > 0 then
					targeting.start(cid, spec)
					for i = 1, want do targets[i] = targeting.eligible[i] end
					targeting.clear()
				end
				if #targets >= want then return cid, targets end
			end
		end
	end

	-- A whole state, out and back. The log carries em dashes, so this is also
	-- the check that multi-byte text survives base64 and JSON intact — a
	-- transport that drops a byte would show up here and nowhere friendlier.
	local function log_text() return table.concat(log.tail(1e9), "\n") end
	for _, file in ipairs({ "lost_cities.json", "castle.json", "kingdom.json" }) do
		net.begin(file, 7)
		local want = net.fingerprint()
		local full = net.export(true)
		flow.init("menu.json")
		local ok, err = net.import(full)
		check(file .. " survives encode/decode/apply", ok, err)
		check(file .. " lands on the same state", net.fingerprint() == want)
	end

	net.begin("lost_cities.json", 7)
	dismiss_mode()
	local said = log_text()
	check("the fixture's log has multi-byte text", said:find("—") ~= nil)
	local msg0 = net.export(true)
	flow.init("menu.json")
	net.import(msg0)
	check("multi-byte log text survives the wire", log_text() == said)

	-- A move, as a delta against the state both sides last shared.
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	local shared = net.export(true)          -- what the opponent is holding
	local cid, targets = first_playable()
	check("the fixture has a playable card", cid ~= nil)
	flow.play_card(cid, targets)
	local moved = net.fingerprint()
	local delta = net.export()
	-- The absolute bound is the one that matters; the ratio is here to catch a
	-- delta that has quietly become a whole state. It was 20x when a Lost
	-- Cities turn moved one card, and is ~8x now that finishing a play deals
	-- the six draw options into the choice zone — six creations the opponent
	-- has to hear about. Still 714 bytes against 6 KB.
	check("a delta is far smaller than a state", #delta * 5 < #shared and #delta < 1000,
		#delta .. " vs " .. #shared)

	net.import(shared)                        -- rewind: be the opponent
	local ok, err = net.import(delta)
	check("a delta applies on the shared state", ok, err)
	check("a delta reproduces the sender's state exactly", net.fingerprint() == moved)

	-- ...and refuses to apply anywhere else, which is the whole safety story.
	net.begin("lost_cities.json", 99)
	dismiss_mode()
	check("a delta is refused against a state it does not fit", not net.import(delta))
	net.begin("castle.json", 7)
	check("a delta is refused across a game change", not net.import(delta))

	-- A chat client may wrap the line; the format has to survive that, and has
	-- to reject everything else without disturbing the game.
	net.begin("castle.json", 7)
	local before = net.fingerprint()
	local wrapped = net.export(true):gsub("(.....................)", "%1\n")
	net.begin("menu.json", 7)
	check("a line-wrapped paste still decodes", net.import(wrapped))
	for _, junk in ipairs({ "", "hello", "RAVEL1:x:1:Fj:!!!not base64!!!",
		"RAVEL1:x:1:Fj:" .. ("QUJD"), "RAVEL1:x:1:Zz:QUJD" }) do
		local fp = net.fingerprint()
		local okj = net.import(junk)
		check("junk is refused: " .. junk:sub(1, 22), not okj)
		check("...and the game is untouched", net.fingerprint() == fp)
	end
	net.import(wrapped)
	check("the wrapped paste carried the real state", net.fingerprint() == before)

	-- The generator's position travels with the state, or the two sides deal
	-- different cards from the same deck the moment either one shuffles.
	local rng = require("rng")
	net.begin("castle.json", 3)
	rng.int(1000); rng.int(1000)
	local pos = rng.state()
	local msg = net.export(true)
	rng.seed(1)
	net.import(msg)
	check("the RNG position travels with the state", rng.state() == pos)

	-- Seat gating. flow is what enforces it, so ask flow.
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	check("with no seat claimed, anyone may act", net.may_act())
	net.seat = zones.active_seat()
	check("the active seat may act", net.may_act())
	local mine, my_targets = first_playable()
	check("...and can play", mine ~= nil and flow.play_card(mine, my_targets))
	net.seat = "south"
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	net.seat = "south"                        -- north is up first
	check("the inactive seat may not act", not net.may_act())
	local theirs = zones.find("hand")
	check("the inactive seat's cards read as unplayable",
		theirs and #theirs.cards > 0 and not flow.can_play(theirs.cards[1]))
	check("...and flow refuses the play outright", not flow.play_card(theirs.cards[1], {}))
	net.seat = nil

	-- The invite: the whole handshake for a copy/paste game.
	-- Deliberately not dismissed: an invite puts both players at the game's
	-- actual opening, mode question and all, which is the state they must share.
	net.begin("lost_cities.json", 4242)
	local invite = net.invite(4242)
	local started = net.fingerprint()
	check("an invite is short enough to type", #invite < 40, invite)
	net.begin("castle.json", 1)
	check("an invite is accepted", net.accept(invite))
	check("both players start from the identical state", net.fingerprint() == started)
	check("garbage is not an invite", not net.accept("RAVEL1I:nonsense"))

	-- The three hashes, and the three different questions they answer.
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	check("a game file has a hash", (net.game_hash() or ""):match("^%x%x%x%x%x%x%x%x$") ~= nil)
	check("a different file hashes differently",
		net.game_hash("lost_cities.json") ~= net.game_hash("castle.json"))
	check("the cached state hash matches a fresh one", net.state_hash() == net.fingerprint())

	-- Playing changes it, and the cache notices.
	local was = net.state_hash()
	local pcid2, ptarg2 = first_playable()
	flow.play_card(pcid2, ptarg2)
	check("a move changes the state hash", net.state_hash() ~= was)
	check("...and the cache is not stale", net.state_hash() == net.fingerprint())

	-- Two people with different versions of the same file: refused at the door,
	-- with a message that says what is wrong rather than asking for a resync
	-- that cannot possibly help.
	net.begin("castle.json", 7)
	local honest = net.export(true)
	local forged = honest:gsub("^(RAVEL1:[^:]*:)castle%.json:", "%1kingdom.json:")
	check("the test actually forged something", forged ~= honest)
	local okf, errf = net.import(forged)
	check("a header that disagrees with its payload is refused", not okf)
	check("...and says so", tostring(errf):find("header says") ~= nil, tostring(errf))

	-- The label is what a person reads in a chat window before decoding anything.
	check("a whole state is labelled init", honest:find("^RAVEL1:init:castle%.json:") ~= nil,
		honest:sub(1, 40))
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	local shared2 = net.export(true)
	local lc, lt = first_playable()
	flow.play_card(lc, lt)
	local labelled = net.export()
	check("a later message is labelled with the turn",
		labelled:find("^RAVEL1:t%d+p%d+:lost_cities%.json:") ~= nil, labelled:sub(1, 40))
	check("a one-seat game leaves the player out of the label",
		(function() net.begin("castle.json", 7); return net.marker():find("^t%d+$") ~= nil end)())
	do
		-- Same file, but the sender's copy hashed differently: exactly the
		-- "you two have different versions" case, and the error must say so.
		local body = { game = "castle.json", gh = "deadbeef", ents = {}, phases = {} }
		local okg, errg = net.apply_full(body)
		check("a game-file mismatch is refused", not okg)
		check("...and the error names both hashes",
			tostring(errg):find("different versions") ~= nil, tostring(errg))
	end

	-- The chain: a delta says which state it follows, and is refused elsewhere.
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	local at = net.export(true)
	local c3, t3 = first_playable()
	flow.play_card(c3, t3)
	local step = net.export()
	net.import(at)
	check("a delta names the state it follows", net.import(step))
	net.begin("lost_cities.json", 7)
	dismiss_mode()
	local c4, t4 = first_playable()
	flow.play_card(c4, t4)                     -- somewhere else entirely
	local okc, errc = net.import(step)
	check("a delta is refused from the wrong place", not okc)
	check("...and the error names both states",
		tostring(errc):find("follows state") ~= nil, tostring(errc))

	-- Networking as cards. The engine knows the words; net.lua supplies the
	-- meaning, and a build without it leaves them as silent no-ops.
	do
		local acts = require("actions")
		for _, op in ipairs({ "net_invite", "net_join", "net_panel", "net_seat", "net_offline" }) do
			check(op .. " is an action the engine knows", acts.spec(op) ~= nil)
		end

		net.begin("lost_cities.json", 7)
		dismiss_mode()
		local asked = {}
		net.on_ui = function(what) asked[#asked + 1] = what end

		eval("net_invite")
		eval("net_join")
		check("a card can ask for the invite UI", asked[1] == "invite" and asked[2] == "join",
			table.concat(asked, ","))

		-- Sitting down is local, and needs no UI at all.
		eval("net_seat:south")
		check("a card can claim a seat", net.seat == "south")
		eval("net_seat:any")
		check("...and give it up", net.seat == nil)

		-- Without a UI hook the ops must be harmless, not fatal: that is the
		-- headless and desktop case, and the case where net.lua is deleted.
		net.on_ui = nil
		local before = net.state_hash()
		check("with no UI, asking for one does not error", pcall(eval, "net_invite"))
		check("...and changes nothing", net.state_hash() == before)

		-- And the menu actually uses them, which is the point of the exercise.
		local menu = love.filesystem.read("games/menu.json")
		check("the menu offers joining as a card", menu:find("net_join") ~= nil)
		local lc = love.filesystem.read("games/lost_cities.json")
		check("and the two-player game offers hosting as one",
			lc:find("net_invite") ~= nil and lc:find("net_seat") ~= nil)
	end

	-- Four things arrive in one box, and one function decides which is which.
	net.begin("lost_cities.json", 4242)
	dismiss_mode()
	check("a state is recognised", net.kind_of(net.export(true)) == "state")
	check("an invite is recognised", net.kind_of(net.invite(4242)) == "invite")
	check("an offer is recognised", net.kind_of(net.wrap_sdp("offer", "c2Rw")) == "offer")
	check("an answer is recognised", net.kind_of(net.wrap_sdp("answer", "c2Rw")) == "answer")
	check("nothing else is", net.kind_of("hello") == nil and net.kind_of(nil) == nil)
	check("an offer survives its envelope", net.unwrap_sdp(net.wrap_sdp("offer", "c2Rw")) == "c2Rw")
	check("a wrapped blob tolerates line wrapping",
		net.unwrap_sdp(net.wrap_sdp("answer", "c2Rw"):gsub("1A", "1A\n")) == "c2Rw")
	-- The signalling envelope is not a state, and must not be treated as one.
	check("a signalling blob is refused by import", not net.import(net.wrap_sdp("offer", "c2Rw")))

	-- A transport is only send/recv, and net does not care which one it has.
	local netlink = require("netlink")
	local a, b = netlink.loopback()
	net.begin("castle.json", 5)
	net.link(a)
	local base = net.fingerprint()
	local pcid, ptargets = first_playable()
	flow.play_card(pcid, ptargets)            -- the wrapper publishes for us
	local sent = b.recv()
	check("a move publishes itself over the transport", type(sent) == "string")
	net.unlink()
	net.import(sent)
	check("what arrived is the state that was played", net.fingerprint() ~= base)

	-- Sharing the game itself, so somebody who has never seen the file can be
	-- dealt into it. The position is meaningless without the rules.
	do
		local decl = require("declaration")
		local text = love.filesystem.read("games/castle.json")
		check("a game we do have hashes", net.game_hash("castle.json") ~= nil)
		check("a game we do not have does not", net.game_hash("no_such_game.json") == nil)

		-- Handed the text, we can play it without it ever being on disk.
		check("an unknown game can be accepted", net.accept_game("gift.json", text))
		check("...and then hashes like the sender's",
			net.game_hash("gift.json") == net.game_hash("castle.json"))
		check("...and loads", (net.begin("gift.json", 4)))
		check("...as the real thing", declaration.G.title == "Castle Lord",
			tostring(declaration.G.title))

		-- A state for a game we do not have names that, so the receiver knows to
		-- ask rather than to give up.
		decl.provided["gift.json"] = nil
		net.begin("castle.json", 4)
		local orphan = { game = "still_missing.json", gh = "12345678", ents = {}, phases = {} }
		local okm, errm = net.apply_full(orphan)
		check("a state for a game we lack is refused", not okm)
		check("...saying which game", tostring(errm):find("you do not have still_missing") ~= nil,
			tostring(errm))
	end

	-- Hello. A transport that connects to nobody looks exactly like one that
	-- works, so the peer heard from second announces itself back.
	do
		local ha, hb = netlink.loopback()
		net.begin("castle.json", 3)
		check("nothing heard before anything is linked", net.last_heard == nil)
		net.link(ha)
		while hb.recv() do end
		-- Their side speaks first; ours must answer so they know we are here.
		net.begin("castle.json", 3)
		net.link(ha)
		while hb.recv() do end
		local theirs = (function()
			net.begin("castle.json", 3)
			local t = net.export(true)
			net.begin("castle.json", 3)
			net.link(ha)
			while hb.recv() do end
			return t
		end)()
		hb.send(theirs)              -- arrives on our end
		net.poll()
		check("hearing anything is recorded", net.last_heard ~= nil)
		local replies = {}
		while true do local r = hb.recv(); if not r then break end; replies[#replies + 1] = r end
		local said_hello = false
		for _, r in ipairs(replies) do if r:find("^RAVEL1:hello:") then said_hello = true end end
		check("first contact is answered with a hello", said_hello,
			table.concat(replies, " | "):sub(1, 60))

		-- ...exactly once, or two clients would greet each other forever.
		hb.send(theirs)
		net.poll()
		local again = false
		while true do
			local r = hb.recv(); if not r then break end
			if r:find("^RAVEL1:hello:") then again = true end
		end
		check("and only once", not again)

		-- A hello carries nothing and must never disturb the game.
		local before = net.state_hash()
		hb.send("RAVEL1:hello:castle.json:99:Hj:")
		net.poll()
		check("a hello changes nothing", net.state_hash() == before)
		net.unlink()
	end

	-- Out of sync, and the button that fixes it.
	do
		local la, lb = netlink.loopback()
		net.begin("lost_cities.json", 7)
		dismiss_mode()
		net.link(la)
		check("a fresh game is not out of sync", net.desync == nil)

		-- Build a move from somewhere else entirely, then hand it over.
		local elsewhere
		net.begin("lost_cities.json", 21)
		dismiss_mode()
		local xc, xt = first_playable()
		flow.play_card(xc, xt)
		elsewhere = net.export()

		net.begin("lost_cities.json", 7)
		dismiss_mode()
		net.link(la)
		local okd = net.import(elsewhere)
		check("a move from another game is refused", not okd)
		check("...and that is recorded as being out of sync", net.desync ~= nil, net.desync)

		-- The manual button: it puts a resync request on the wire, labelled so.
		check("resync needs a connection", (function()
			net.unlink(); return not net.request_resync()
		end)())
		net.link(la)
		while lb.recv() do end            -- earlier moves are still queued
		check("resync is sent", net.request_resync())
		local asked = lb.recv()
		check("the request is labelled resync",
			type(asked) == "string" and asked:find("^RAVEL1:resync:") ~= nil, tostring(asked))
		check("the request carries a resync kind",
			type(asked) == "string" and asked:find(":R%a:") ~= nil)

		-- And a whole state is the cure.
		net.begin("lost_cities.json", 7)
		dismiss_mode()
		net.link(la)
		net.import(elsewhere)
		check("still out of sync before the fix", net.desync ~= nil)
		net.begin("lost_cities.json", 21)
		dismiss_mode()
		local whole = net.export(true)
		net.begin("lost_cities.json", 7)
		dismiss_mode()
		net.desync = "pretend we never recovered"
		check("a whole state applies", net.import(whole))
		check("...and clears the out-of-sync flag", net.desync == nil)
		net.unlink()
	end

	net.seat = nil
	net.unlink()
	check("networking leaves nothing behind", not net.linked() and net.seat == nil)
end

-- === golden traces ===
-- Reworking the stat machinery must not change what actually happens in a
-- game. These play a fixed seeded script and compare the entire event log to a
-- committed transcript. The log records every stat change together with the
-- entity it landed on, which is exactly what a scoping change could get wrong,
-- so a silent behaviour shift shows up as a diff instead of as nothing.
-- Regenerate deliberately: RAVEL_GOLDEN=write luajit tests/run.lua
local function scripted_play(file, seed, steps)
	flow.init(file, seed)
	for _ = 1, steps do
		if flow.outcome() then break end
		local cur = phase.current()
		if not cur then break end
		local acted = false
		if cur.type == "overlay" then
			local z = zones.find(cur.zone or "hand")
			if z and #z.cards > 0 then acted = flow.pick(z.cards[1]) end
		else
			local hand = zones.find(cur.zone or "hand")
			for _, cid in ipairs(hand and hand.cards or {}) do
				local def  = cards.def(entity.get(cid))
				local spec = def and def.target
				local want = spec and (spec.min or spec.count or 0) or 0
				local targets = {}
				if want > 0 then
					targeting.start(cid, spec)
					for i = 1, want do targets[i] = targeting.eligible[i] end
					targeting.clear()
				end
				if #targets == want and flow.play_card(cid, targets) then
					acted = true
					break
				end
			end
		end
		if not acted then break end
	end
	return table.concat(log.tail(100000), "\n") .. "\n"
end

-- === chess: a scripted opening ===
-- The strongest test the board layer can have, and the cheapest: a fixed
-- sequence of real moves with the position asserted along the way. It covers
-- what unit tests cover badly — that blocking, capture, facing and the turn
-- order all agree with each other over several moves.
flow.init("chess.json", 1)

local board = zones.find("board")
local function sq(name)   -- "e4" → the slot on that square
	return geometry.slot_at(board, string.byte(name, 1) - 96, 9 - tonumber(name:sub(2)))
end
local function piece(key)
	for e in entity.each("card") do
		if e.def_key == key and e.zone_id then return e end
	end
end
local function at(name)   -- what stands on a square, by template key
	local occ = entity.get(sq(name)).occupant
	return occ and entity.get(occ).def_key
end
local function move(key, to)
	local p = piece(key)
	return p ~= nil and flow.activate(p.id, { sq(to) })
end
local function reach(key)
	local p, out = piece(key), {}
	for _, sid in ipairs(targeting.candidates(p.id, cards.def(p).activate_target)) do
		local s = entity.get(sid)
		out[#out + 1] = string.char(96 + s.stats.col) .. tostring(9 - s.stats.row)
	end
	table.sort(out)
	return table.concat(out, " ")
end

check("thirty-two pieces, white to move", #board.cards == 32 and zones.active_seat() == "white")
check("a piece's rank counts from its own side, so home is 2 for both colours",
	piece("w_pawn_e").stats.rank == 2 and piece("b_pawn_e").stats.rank == 2
	and at("e2") == "w_pawn_e" and at("e7") == "b_pawn_e")

-- The opening position: everything on the back rank is boxed in except the
-- knights, which is the whole of "leaping" falling out of the geometry rather
-- than out of a flag.
check("a rook, a queen and a king all start with nowhere to go",
	reach("w_rook_a") == "" and reach("w_queen_d") == "" and reach("w_king_e") == "")
check("a knight leaps its own pawns", reach("w_knight_b") == "a3 c3")
check("a pawn on its home rank offers the step and the opening run",
	reach("w_pawn_e") == "e3 e4")

check("1. e4 — and the turn passes", move("w_pawn_e", "e4") and zones.active_seat() == "black")
check("black may not move white's pieces", flow.can_activate(piece("w_pawn_d").id) == false)
check("1... d5", move("b_pawn_d", "d5") and zones.active_seat() == "white")
check("the bishop is freed down the diagonal it was blocked on",
	reach("w_bishop_f") == "a6 b5 c4 d3 e2")
check("a pawn that has left its home rank has no opening run left",
	reach("w_pawn_e") == "d5 e5")

check("2. exd5 — a capture", move("w_pawn_e", "d5") and at("d5") == "w_pawn_e")
check("the taken pawn is in a tray, off the board",
	entity.get(piece("b_pawn_d").id).zone_id == zones.find_id("taken", "anyone")
	and #board.cards == 31)

check("2... Qxd5 — and the recapture", move("b_queen_d", "d5") and at("d5") == "b_queen_d")
check("3. Nc3", move("w_knight_b", "c3"))
-- Read off the position by hand: three clear rays, four cut short by a pawn it
-- may take, and two cut short by one it may not.
check("the queen sees exactly what a queen on d5 sees",
	reach("b_queen_d") == "a2 a5 b3 b5 c4 c5 c6 d2 d3 d4 d6 d7 d8 e4 e5 e6 f3 f5 g2 g5 h5")

check("a rook still cannot move through its own pawn", move("w_rook_a", "a5") == false)
check("and a piece cannot move out of turn", move("w_knight_b", "b1") == false)

-- === pointing at a piece means pointing at its square ===
-- Every test above reached targeting.candidates directly, so all of them passed
-- while capture was unclickable in the actual game: the interface hit-tests the
-- topmost card, the eligible list holds slots, and the two never met. This is
-- that path, without a mouse.
flow.init("chess.json", 1)
board = zones.find("board")
move("w_pawn_e", "e4"); move("b_pawn_d", "d5")

local victim = piece("b_pawn_d")
targeting.start(piece("w_pawn_e").id, cards.def(piece("w_pawn_e")).activate_target, "activate")
check("the square under an enemy is eligible, but the enemy card itself is not",
	targeting.is_eligible(victim.slot_id) and targeting.is_eligible(victim.id) == false)
check("so aiming at the piece resolves to the square it stands on",
	targeting.aim(victim.id) == victim.slot_id and targeting.add(targeting.aim(victim.id)))
targeting.clear()

-- The two things aim must not do.
targeting.start(piece("w_pawn_e").id, cards.def(piece("w_pawn_e")).activate_target, "activate")
check("the acting card still answers as itself, so clicking it cancels",
	targeting.aim(targeting.card_id) == targeting.card_id)
local empty = geometry.slot_at(board, 5, 5)
check("and a square with nothing on it is already what was meant",
	targeting.aim(empty) == empty and targeting.aim(nil) == nil)
targeting.clear()

-- A card-typed spec must keep meaning the card: aim is for specs that want a place.
targeting.start(piece("w_pawn_e").id, { type = "card", count = 1, tags = { "piece" } }, "activate")
check("a card-typed spec still means the card, not the square under it",
	targeting.aim(victim.id) == victim.id)
targeting.clear()

-- === a requirement is not always a plain number ===
-- cost_text renders needs and accepts as well as costs, and only a cost is
-- always a number. Hovering the first card whose needs carried a comparison map
-- concatenated a table and took the interface down.
check("a comparison map renders instead of crashing",
	cards.cost_text({ ["moves_made@w_king_e"] = { equals = 0 } })
		== "exactly 0 moves_made@w_king_e"
	and cards.cost_text({ hp = { at_most = 3 } })  == "at most 3 hp"
	and cards.cost_text({ hp = { at_least = 3 } }) == "at least 3 hp")
check("a plain number still reads as itself", cards.cost_text({ gold = 2 }) == "2 gold")
check("and a sacrifice still reads as one",
	cards.cost_text({ ["sacrifice:farm"] = 2 }) == "sacrifice 2 farm")
check("every shipped card's tooltip text can be built without crashing", (function()
	for _, g in ipairs({ "chess.json", "lost_cities.json", "castle.json", "kingdom.json" }) do
		flow.init(g, 3)
		for _, def in pairs(declaration.G.card_defs) do
			local ok = pcall(function()
				return cards.cost_text(def.cost or {}) .. cards.cost_text(def.needs or {})
					.. cards.cost_text(def.accepts or {}) .. cards.cost_text(def.activate_cost or {})
			end)
			if not ok then return false end
		end
	end
	return true
end)())

-- === patterns as scopes, and castling ===
-- A pattern names a shape, and a shape answers "what is standing there" as
-- readily as "where may I go". That is what lets castling's "these squares must
-- be empty" be an ordinary condition rather than a condition invented for it.
flow.init("chess.json", 1)
board = zones.find("board")

check("a relative pattern is a neighbourhood, anchored on the acting card",
	predicate.total("count:piece@adjacent", { card_id = piece("w_king_e").id }) == 5)
check("...and names nothing for a card that is not standing on a square",
	predicate.total("count:piece@adjacent", { card_id = piece("w_castle_k").id }) == 0)
check("an absolute pattern names squares outright, with no anchor at all",
	predicate.total("count:piece@w_castle_k_path") == 2)

-- Castling is a card, not a move: its destinations are constants, so it needs
-- no targeting — and a played card is gated by "needs", which an activated one
-- is not.
check("castling is refused while its squares are occupied",
	flow.can_play(piece("w_castle_k").id) == false)
move("w_pawn_e", "e4"); move("b_pawn_e", "e5")
move("w_bishop_f", "c4"); move("b_bishop_f", "c5")
check("still refused with only one square cleared",
	predicate.total("count:piece@w_castle_k_path") == 1
	and flow.can_play(piece("w_castle_k").id) == false)
move("w_knight_g", "f3"); move("b_knight_g", "f6")
check("offered once both squares are clear",
	predicate.total("count:piece@w_castle_k_path") == 0
	and flow.can_play(piece("w_castle_k").id))
check("the queenside card is still refused, its own three squares being full",
	flow.can_play(piece("w_castle_q").id) == false)

check("castling moves both pieces at once", flow.play_card(piece("w_castle_k").id, {})
	and at("g1") == "w_king_e" and at("f1") == "w_rook_h"
	and at("e1") == nil and at("h1") == nil)
check("and hands over", zones.active_seat() == "black")
check("a king that has castled has moved, so it may not castle again",
	flow.can_play(piece("w_castle_k").id) == false
	and flow.can_play(piece("w_castle_q").id) == false)

-- === a stat nobody carries is absent, not zero ===
-- Reading a missing value as 0 would make "this rook has never moved" true of a
-- rook captured twenty moves ago — a gate that opens exactly when the thing it
-- guards stops existing.
flow.init("chess.json", 1)
board = zones.find("board")
check("an unmoved rook satisfies the gate",
	predicate.meets_all({ ["moves_made@w_rook_h"] = { equals = 0 } }))
zones.destroy_card(piece("w_rook_h").id)
check("a captured rook does not, though its absent stat would sum to zero",
	predicate.meets_all({ ["moves_made@w_rook_h"] = { equals = 0 } }) == false)
check("...and no comparison against it succeeds, not just equality",
	predicate.meets_all({ ["moves_made@w_rook_h"] = { at_most = 5 } }) == false
	and predicate.meets_all({ ["moves_made@w_rook_h"] = { at_least = 0 } }) == false)
check("so castling is refused once its rook is gone",
	flow.can_play(piece("w_castle_k").id) == false)

-- The counting forms keep meaning what they say: no farms is a count of zero,
-- and that is how "these squares are empty" is written.
check("a count of nothing is still zero",
	predicate.meets_all({ ["count:piece@w_castle_k_path"] = { equals = 0 } }) == false
	and predicate.total("count:piece@nowhere_at_all") == 0)
check("and an aggregate over an empty pool is still zero, being asked of a pool",
	predicate.meets_all({ ["sum:moves_made@w_rook_h"] = { equals = 0 } }))

-- These used to be recorded under LuaJIT and skipped everywhere else, because
-- math.random was the host's and no two hosts agreed. rng.lua ended that: one
-- seed is now one sequence on every interpreter, so the strongest test in the
-- suite — "does this file still play exactly as recorded" — runs for everyone.
for _, g in ipairs({ { "castle.json", 7, 120 }, { "kingdom.json", 5, 120 } }) do
	local text = scripted_play(g[1], g[2], g[3])
	local path = "tests/golden/" .. g[1]:gsub("%.json$", "") .. ".log"
	if os.getenv("RAVEL_GOLDEN") == "write" then
		local out = assert(io.open(path, "w"))
		out:write(text)
		out:close()
		print("wrote " .. path .. " (" .. select(2, text:gsub("\n", "")) .. " lines)")
	else
		local f    = io.open(path, "r")
		local want = f and f:read("*a")
		if f then f:close() end
		check(g[1] .. " plays exactly as recorded", want == text)
		if want and want ~= text then
			local a, b = {}, {}
			for l in want:gmatch("[^\n]*") do a[#a + 1] = l end
			for l in text:gmatch("[^\n]*") do b[#b + 1] = l end
			for i = 1, math.max(#a, #b) do
				if a[i] ~= b[i] then
					print(("  first difference at line %d:\n    was: %s\n    now: %s")
						:format(i, tostring(a[i]), tostring(b[i])))
					break
				end
			end
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
