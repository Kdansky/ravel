-- Headless engine tests. Run from the repo root:
--   luajit tests/run.lua      (LuaJIT = LÖVE's interpreter)
--   lua tests/run.lua

require("headless")

math.randomseed(7)

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
flow.play_card(find_card("play_demo").id, {})
check("menu card loads demo", declaration.G.title == "The Wandering Road")
check("demo starts with 1 hand card", zone_count("hand") == 1)
check("road holds the other 10 cards", zone_count("road") == 10)
check("player starts at 5 hp", entity.sum_stat("hp") == 5)

eval("fill:hand:storm:1")
local storm = find_card("storm", "hand")
local hp0   = entity.sum_stat("hp")
flow.play_card(storm.id, {})
check("demo card applies its effect", entity.sum_stat("hp") == hp0 - 1)
check("played card goes to past", zone_count("past") == 1)
check("a new card was drawn", zone_count("hand") == 2)

eval("set_stat:hp:10")
eval("gain_stat:hp:3")
check("hp clamps at declared max", entity.sum_stat("hp") == 10)

-- === demo: undo (state and log together) ===
local hp_before   = entity.sum_stat("hp")
local hand_before = zones.find("hand").cards[1]
local log_before  = log.count()
flow.play_card(hand_before, {})
check("plays write log lines", log.count() > log_before)
check("undo works", flow.undo())
check("undo restores hp and hand",
	entity.sum_stat("hp") == hp_before and zones.find("hand").cards[1] == hand_before)
check("undo erases the undone log lines", log.count() == log_before)

-- === demo: defeat ===
eval("set_stat:hp:0")
check("defeat overlay pushed at 0 hp", phase.current().key == "defeat")
check("fate card dealt to offer", zone_count("offer") == 1)
flow.pick(zones.find("offer").cards[1])
check("picking the fate card returns to menu", declaration.G.title == "Ravel")

-- === demo: victory (picking through any crossroads choice on the way) ===
flow.play_card(find_card("play_demo").id, {})
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
check("starting gold is 20", entity.sum_stat("gold") == 20)
check("round counter starts at 1", entity.sum_stat("round") == 1)
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
local morale0 = entity.sum_stat("morale")
check("inspire succeeds with gold", flow.activate(throne.id))
check("morale +1 and gold -2",
	entity.sum_stat("morale") == morale0 + 1 and entity.sum_stat("gold") == 1)
check("activation exhausts the throne", throne.exhausted == true)
check("exhausted cards cannot activate again", flow.activate(throne.id) == false)

-- === castle: abilities that take targets ===
local tdef = declaration.G.card_defs.throne_room
tdef.activate_target = { type = "card", count = 1, tags = { "building" }, zones = { "board" } }
tdef.on_activate     = { "gain_target_stat:defense:1" }
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
local gold0 = entity.sum_stat("gold")
flow.play_card(farm.id, { slot })
check("farm placed on board", farm.zone_id == zones.find_id("board"))
check("farm occupies the chosen slot", entity.get(slot).occupant == farm.id)
check("farm cost 1 gold", entity.sum_stat("gold") == gold0 - 1)
check("turn ended into build2", phase.current().key == "build2")
check("hand redealt with 3 plus the pass card", zone_count("hand") == 4)

-- === castle: stat clamping on cards (overheal fix) ===
actions.execute("lose_target_stat:hp:2", { targets = { farm.id } })
check("farm damaged to 1 hp", farm.stats.hp == 1)
actions.execute("gain_target_stat:hp:9", { targets = { farm.id } })
check("healing clamps at hp_max", farm.stats.hp == 3)

-- === castle: computed-tag targeting ===
actions.execute("lose_target_stat:hp:1", { targets = { farm.id } })
eval("fill:hand:repair:1")
local rep = find_card("repair", "hand")
targeting.start(rep.id, cards.def(rep).target)
check("damaged farm eligible for repair", targeting.is_eligible(farm.id))
check("undamaged throne not eligible", not targeting.is_eligible(throne.id))
targeting.clear()
actions.execute("gain_target_stat:hp:1", { targets = { farm.id } })

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
check("decree cost was paid", entity.sum_stat("gold") == 7)

flow.undo()
check("undo backs out of the whole choice",
	phase.current().key == "build2" and zone_count("offer") == 0
	and zone_count("edicts") == 3
	and find_card("royal_decree", "hand") ~= nil and entity.sum_stat("gold") == 9)

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

local gold1 = entity.sum_stat("gold")
flow.play_card(pick, {})
check("tax levy grants 3 gold", entity.sum_stat("gold") == gold1 + 3)
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
local gold_before = entity.sum_stat("gold")
flow.play_card(challenge_card, {})
check("round wrapped back to build1", phase.current().key == "build1")
check("on_turn gold income applied", entity.sum_stat("gold") == gold_before + expected_income)
check("round counter advanced", entity.sum_stat("round") == 2)
-- re-fetch by ID: undo replaced the entity tables, old references are stale
check("the new round readies exhausted cards", entity.get(throne.id).exhausted == nil)

-- === castle: refill_when_empty ===
local bd = zones.find("build_deck")
eval("draw_from:build_deck:graveyard:" .. #bd.cards)
check("emptied build deck refills from contents", #bd.cards == 15)

-- === castle: damage_random ===
local hp_before_dmg = board_hp()
eval("damage_random:building:hp:2")
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
check("origin grants its stats", entity.sum_stat("might") == 3 and entity.sum_stat("progress") == 3)
check("origin auto-slotted onto the board", find_card("warlord", "board").slot_id ~= nil)
check("routing entered the market", phase.current().key == "market_visit")
check("ends_round advanced the round", entity.sum_stat("round") == 2)
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
local food0 = entity.sum_stat("food")
eval("gain_stat:food:count:farm")
check("count amounts resolve board tags",
	farms >= 2 and entity.sum_stat("food") == food0 + farms)

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
local round0 = entity.sum_stat("round")
flow.play_card(rest_id, {})
check("rest marches into the wartime market", phase.current().key == "wartime_market")
check("each trial pair is a round", entity.sum_stat("round") == round0 + 1)
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
local r_ea = entity.sum_stat("round")
local first_ea
for _, cid in ipairs(zones.find("hand").cards) do
	local d = cards.def(entity.get(cid))
	if not (d.tags_set and d.tags_set.token) and flow.can_play(cid) then first_ea = cid; break end
end
flow.play_card(first_ea, {})
check("ends_after advances the phase by itself", entity.sum_stat("round") == r_ea + 1)
check("the phase it advanced into dealt fresh", zone_count("hand") == 7)

-- === kingdom: failed trials persist as crises ===
flow.init("kingdom.json", 5)
flow.play_card(find_card("warlord", "hand").id, {})
eval("set_stat:might:0")
eval("fill:hand:war_host:1")
flow.play_card(find_card("war_host", "hand").id, {})
check("a failed trial squats on the board as a crisis", find_card("war_host", "board") ~= nil)
local stab1 = entity.sum_stat("stability")
flow.play_card(hand_router("to_market"), {})
check("an unanswered crisis drains stability each round",
	entity.sum_stat("stability") == stab1 - 1)
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

local hp_lantern = entity.sum_stat("hp")
eval("gain_stat:hp:card:lantern")
check("card amounts resolve template presence", entity.sum_stat("hp") == hp_lantern + 1)

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
eval("damage_random:threat:hp:9")
check("a dead threat is slain, not gone", th.stats.hp == 0 and th.zone_id ~= nil)

eval("fill:hand:scavenge:1")
flow.play_card(find_card("scavenge", "hand").id, { th.id })
check("scavenging clears the corpse for supplies",
	entity.get(th.id).zone_id == zones.find_id("graveyard"))

local d0, s0 = entity.sum_stat("distance"), entity.sum_stat("supplies")
local m0 = entity.sum_stat("morale")
flow.play_card(hand_router("march"), {})
check("marching trades a supply for a mile",
	entity.sum_stat("distance") == d0 + 1 and entity.sum_stat("supplies") == s0 - 1)
check("a threat never drains on the day it arrives", entity.sum_stat("morale") == m0)
check("the road loops back to camp", phase.current().key == "camp")
check("a new day has dawned", entity.sum_stat("round") == 2)
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
	{ "a comparison that isn't a number", "at_least should be a number",
		function(g) g.end_conditions[2] = { stat = "hp", at_least = "3", ["then"] = {} } end },
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
	{ "a damage tag no card carries", "looks for the tag 'wyrms'",
		function(g) g.card_defs.c_flee.on_play = { "damage_random:wyrms:hp:1" } end },
	{ "an action missing its argument", "'reveal' is missing its card argument",
		function(g) g.card_defs.c_flee.on_play = { "reveal" } end },
	{ "a target stat no card carries", "no card carries that stat",
		function(g) g.card_defs.c_flee.on_play = { "gain_target_stat:armor:1" } end },
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
	{ "a target of an unknown type", "type should be 'card' or 'slot'",
		function(g) g.card_defs.c_flee.target = { type = "zone", max = 1 } end },
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
			and not e.exhausted and cards.can_afford(def.activate_cost) then
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

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
