-- Two people, one game, and a text field between them.
--
-- One process cannot hold two engines, so "the other client" is played by
-- rewinding to the state both sides shared and applying what arrived. That is
-- exactly what the far machine does, minus the wire.

local declaration = require("declaration")
local entity      = require("entity")
local zones       = require("zones")
local cards       = require("cards")
local phase       = require("phase")
local targeting   = require("targeting")
local actions     = require("actions")
local flow        = require("flow")
local log         = require("log")
local net         = require("net")
local netlink     = require("netlink")
local rng         = require("rng")

local M = {}

-- Lost Cities opens by asking how many players; every test that wants to reach
-- the game itself has to answer that first.
local function dismiss_mode()
	if phase.is_overlay() and phase.current().key == "mode" then
		flow.pick(zones.find("mode").cards[1])
	end
end

-- Run a single action then settle, like the debug server's `eval`.
local function eval(str)
	actions.execute(str, {})
	flow.settle()
end

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

local function log_text() return table.concat(log.tail(1e9), "\n") end

function M.test_net_a_state_survives_the_wire(check)
	-- A whole state, out and back. The log carries em dashes, so this is also
	-- the check that multi-byte text survives base64 and JSON intact — a
	-- transport that drops a byte would show up here and nowhere friendlier.
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
end

function M.test_net_delta_is_small_and_lands_where_it_belongs(check)
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
end

function M.test_net_paste_survives_a_chat_window(check)
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
end

function M.test_net_rng_position_travels_with_the_state(check)
	-- The generator's position travels with the state, or the two sides deal
	-- different cards from the same deck the moment either one shuffles.
	net.begin("castle.json", 3)
	rng.int(1000); rng.int(1000)
	local pos = rng.state()
	local msg = net.export(true)
	rng.seed(1)
	net.import(msg)
	check("the RNG position travels with the state", rng.state() == pos)
end

function M.test_net_seat_gating(check)
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
end

function M.test_net_invite(check)
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
end

function M.test_net_three_hashes(check)
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
end

function M.test_net_refuses_a_header_that_disagrees(check)
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
end

function M.test_net_delta_names_the_state_it_follows(check)
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
end

function M.test_net_ops_are_cards(check)
	-- Networking as cards. The engine knows the words; net.lua supplies the
	-- meaning, and a build without it leaves them as silent no-ops.
	do
		for _, op in ipairs({ "net_invite", "net_join", "net_panel", "net_seat", "net_offline" }) do
			check(op .. " is an action the engine knows", actions.spec(op) ~= nil)
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
end

function M.test_net_recognises_what_arrives(check)
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
end

function M.test_net_any_transport_will_do(check)
	-- A transport is only send/recv, and net does not care which one it has.
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
end

function M.test_net_sharing_the_game_file_itself(check)
	-- Sharing the game itself, so somebody who has never seen the file can be
	-- dealt into it. The position is meaningless without the rules.
	do
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
		declaration.provided["gift.json"] = nil
		net.begin("castle.json", 4)
		local orphan = { game = "still_missing.json", gh = "12345678", ents = {}, phases = {} }
		local okm, errm = net.apply_full(orphan)
		check("a state for a game we lack is refused", not okm)
		check("...saying which game", tostring(errm):find("you do not have still_missing") ~= nil,
			tostring(errm))
	end
end

function M.test_net_first_contact_is_answered_once(check)
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
end

function M.test_net_desync_and_the_button_that_fixes_it(check)
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
end

-- Every test above leaves the module as it found it, and this is what "as it
-- found it" means. It used to be the last few lines of one enormous block, and
-- so only ever asserted that the block had tidied up after itself; now that a
-- test is a unit, it can say the thing that actually matters — that a game can
-- be put back to solitaire from any state the others might leave.
function M.test_net_leaves_nothing_behind(check)
	local a = netlink.loopback()
	net.begin("lost_cities.json", 7)
	net.link(a)
	net.seat = "south"
	check("a linked, seated game is not offline", net.linked() and net.seat ~= nil)
	net.seat = nil
	net.unlink()
	check("networking leaves nothing behind", not net.linked() and net.seat == nil)
end

return M
