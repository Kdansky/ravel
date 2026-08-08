-- Networked play, prototype. Sits beside the engine rather than inside it: no
-- engine module requires this one, the only line it needed elsewhere is
-- flow.forget_history, and deleting this file leaves the game as it was.
--
-- It ships STATE, not moves. A move is far smaller, but applying one requires
-- the other machine to re-derive the same result — and while rng.lua now makes
-- that possible, a state cannot desync at all, because there is nothing left to
-- re-derive. So the first message of a session is a whole state, and every
-- message after it is the difference from the state both sides last agreed on,
-- which is a few hundred bytes: small enough to paste into a chat window.
--
-- The trust model, stated out loud: both players hold the full state, hidden
-- information included, and nothing here defends against a modified client.
-- This is play between friends and is not anything else.

local declaration = require("declaration")
local entity      = require("entity")
local phase       = require("phase")
local zones       = require("zones")
local flow        = require("flow")
local log         = require("log")
local json        = require("json")
local rng         = require("rng")
local targeting   = require("targeting")

local M = {}

M.PROTOCOL  = "RAVEL1"
M.seat      = nil   -- the seat this client may play as; nil = play any seat
M.on_apply  = nil   -- hook(snap) — presentation clears its caches after remote state lands
M.on_status = nil   -- hook(text) — connection news worth showing a human

-- Deflate is worth roughly 5x on this payload and exists in LÖVE and in the
-- browser, but not under the headless shim, so it is announced in the header
-- rather than assumed. A CLI player trading pastes with a browser player turns
-- it off; two browsers never think about it.
M.compress = (love and love.data and love.data.compress) ~= nil

local link      = nil   -- the active transport, see "Transports" below
local seq       = 0     -- Lamport clock: max(mine, theirs) + 1 on every publish
local baseline  = nil   -- the last state both sides are believed to share
local pending_full = false

local counter = 0
local function new_client_id()
	counter = counter + 1
	return string.format("%x-%x-%x", os.time() % 0x100000, rng.next() % 0xffff, counter)
end
M.client_id = new_client_id()

local function say(text)
	if M.on_status then M.on_status(text) end
end

---------------------------------------------------------------- base64

-- Pure Lua, because the wire format has to be identical on every host: love.data
-- exists in the browser and in LÖVE but not under the headless shim, and a CLI
-- player must be able to paste a string a browser player produced. Base64 also
-- makes a payload safe to embed in a JS string literal and to survive a chat
-- client, which is the whole reason the format looks like this.

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, 64 do B64R[B64:sub(i, i)] = i - 1 end

local function b64encode(s)
	local out, n = {}, 0
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		local e1, e2 = math.floor(v / 262144) % 64, math.floor(v / 4096) % 64
		local e3, e4 = math.floor(v / 64) % 64, v % 64
		n = n + 1
		out[n] = B64:sub(e1 + 1, e1 + 1) .. B64:sub(e2 + 1, e2 + 1)
			.. (b and B64:sub(e3 + 1, e3 + 1) or "=")
			.. (c and B64:sub(e4 + 1, e4 + 1) or "=")
	end
	return table.concat(out)
end

local function b64decode(s)
	s = s:gsub("[^A-Za-z0-9+/=]", "")   -- chat clients wrap lines; drop the damage
	local out, n = {}, 0
	for i = 1, #s, 4 do
		local d1, d2 = B64R[s:sub(i, i)], B64R[s:sub(i + 1, i + 1)]
		if not (d1 and d2) then return nil end
		local d3, d4 = B64R[s:sub(i + 2, i + 2)], B64R[s:sub(i + 3, i + 3)]
		local v = d1 * 262144 + d2 * 4096 + (d3 or 0) * 64 + (d4 or 0)
		n = n + 1
		out[n] = string.char(math.floor(v / 65536) % 256)
			.. (d3 and string.char(math.floor(v / 256) % 256) or "")
			.. (d4 and string.char(v % 256) or "")
	end
	return table.concat(out)
end

---------------------------------------------------------------- state

-- Everything ARCHITECTURE.md lists as state, plus the RNG position and the file
-- it all belongs to. Two things are reshaped on the way out:
--   * `place` is dropped. The renderer rewrites it from scratch every frame, it
--     is a third of the payload, and the two clients are not the same size
--     window anyway.
--   * the phase stack carries keys, not phase defs. phase.snapshot holds a
--     reference to the template table, which would inline every phase
--     definition into every message and re-import it as a stranger.
function M.snapshot()
	local ph, phases = phase.snapshot(), {}
	for i, f in ipairs(ph.stack) do phases[i] = { key = f.def.key, fresh = f.fresh and true or false } end

	local fired = {}
	for i, cond in ipairs(declaration.G.end_conditions or {}) do fired[i] = cond.fired and true or false end

	local ents = entity.snapshot()
	for _, e in ipairs(ents) do e.place = nil end

	return {
		game    = declaration.filename,
		phases  = phases,
		wrapped = ph.wrapped and true or false,
		fired   = fired,
		rng     = rng.state(),
		log     = log.tail(1e9),
		ents    = ents,
	}
end

-- A fingerprint of a state, and the whole of the delta protocol's safety. A
-- patch names the fingerprint it was computed against; a receiver whose own
-- state hashes to something else refuses it and asks for a full copy instead of
-- applying a diff to the wrong thing. json.encode sorts map keys, so the same
-- state hashes the same on both clients. djb2 over the canonical text.
function M.fingerprint(snap)
	snap = snap or M.snapshot()
	local text = json.encode({ snap.ents, snap.phases, snap.rng, snap.fired })
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
	return string.format("%08x", h)
end

---------------------------------------------------------------- deltas

local function deep_copy(x)
	if type(x) ~= "table" then return x end
	local c = {}
	for k, v in pairs(x) do c[k] = deep_copy(v) end
	return c
end

local function same(a, b)
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Per entity, per top-level field. A changed field travels whole rather than
-- being diffed further: what actually changes in a turn is a zone's card list
-- and a card's stats, both already tiny, and a nested diff would cost more in
-- code than it saves in bytes. Entity IDs are array indices and identical on
-- both clients (same file, same seed, same creation order), which is what makes
-- an index a legal name for a thing on the other machine.
local function diff_ents(old, new)
	local out = {}
	for i, e in ipairs(new) do
		local o, d = old[i], nil
		if not o then
			d = {}
			for k, v in pairs(e) do d[k] = v end
		else
			local gone = nil
			for k, v in pairs(e) do
				if not same(v, o[k]) then d = d or {}; d[k] = v end
			end
			for k in pairs(o) do
				if e[k] == nil then gone = gone or {}; gone[#gone + 1] = k end
			end
			if gone then d = d or {}; table.sort(gone); d["-"] = gone end
		end
		if d then out[tostring(i)] = d end
	end
	return out
end

-- Undo shortens the log; a move lengthens it. Both are "keep this many lines,
-- then append these", which is one shape instead of two.
local function diff_log(old, new)
	local n = 0
	while n < #old and n < #new and old[n + 1] == new[n + 1] do n = n + 1 end
	local add = {}
	for i = n + 1, #new do add[#add + 1] = new[i] end
	return { keep = n, add = add }
end

local function make_delta(from, to)
	return {
		game    = to.game,
		base    = M.fingerprint(from),
		phases  = to.phases,
		wrapped = to.wrapped,
		fired   = to.fired,
		rng     = to.rng,
		log     = diff_log(from.log, to.log),
		count   = #to.ents,
		ents    = diff_ents(from.ents, to.ents),
	}
end

---------------------------------------------------------------- wire format

-- RAVEL1:<game>:<seq>:<kind><enc>:<payload>
--   kind  F full state · D delta · R "I am lost, send me a full state"
--   enc   j base64(json) · z base64(deflate(json))
-- Game and clock ride in the header as plain text so a human can read them in a
-- chat window and a receiver can drop a stale message without inflating it.

local function pack(kind, body)
	local text = body and json.encode(body) or ""
	local enc  = "j"
	if M.compress and #text > 0 then
		local ok, z = pcall(love.data.compress, "string", "deflate", text, 9)
		if ok and type(z) == "string" then text, enc = z, "z" end
	end
	return table.concat({ M.PROTOCOL, (body and body.game) or declaration.filename or "?",
		tostring(seq), kind .. enc, b64encode(text) }, ":")
end

local function unpack_msg(text)
	if type(text) ~= "string" then return nil, "not a string" end
	-- No field can legitimately contain whitespace — game files are bare names
	-- and base64 has none — so the cheapest way to survive a chat client that
	-- hard-wraps a long line, or a paste that picked up a stray newline, is to
	-- take the whitespace out before reading anything.
	text = text:gsub("%s+", "")
	local game, msg_seq, mode, body =
		text:match(M.PROTOCOL .. ":([^:]*):([^:]*):(%a%a):([A-Za-z0-9+/=]*)")
	if not game then return nil, "not a " .. M.PROTOCOL .. " message" end
	local kind, enc = mode:sub(1, 1), mode:sub(2, 2)
	local out = { kind = kind, game = game, seq = tonumber(msg_seq) or 0 }
	if kind == "R" then return out end

	local raw = b64decode(body)
	if not raw then return nil, "corrupt base64" end
	if enc == "z" then
		if not (love and love.data and love.data.decompress) then
			return nil, "message is compressed and this build has no love.data"
		end
		local ok, plain = pcall(love.data.decompress, "string", "deflate", raw)
		if not ok then return nil, "cannot inflate payload" end
		raw = plain
	elseif enc ~= "j" then
		return nil, "unknown encoding '" .. tostring(enc) .. "'"
	end

	local ok, snap = pcall(json.decode, raw)
	if not ok or type(snap) ~= "table" then return nil, "payload is not JSON" end
	if type(snap.ents) ~= "table" or type(snap.phases) ~= "table" then
		return nil, "payload is not a game state"
	end
	out.body = snap
	return out
end

---------------------------------------------------------------- applying

-- Content that arrived over a wire is untrusted in exactly the way invariant 5
-- means it: every field is checked before it is believed, and a bad message
-- leaves the game untouched rather than half-updated.
local function restore(snap, ents)
	local stack = {}
	for i, f in ipairs(snap.phases) do
		local def = type(f) == "table" and declaration.G.phase_by_key[f.key]
		if not def then return false, "unknown phase: " .. tostring(type(f) == "table" and f.key) end
		stack[i] = { def = def, fresh = f.fresh and true or false }
	end

	-- entity.restore adopts the array it is handed rather than copying it, which
	-- is right for undo (a popped checkpoint is used once) and a trap here: the
	-- caller's snapshot would become the live state and drift as the game is
	-- played. Applying a state must never consume the thing it was given.
	ents = deep_copy(ents)
	for _, e in ipairs(ents) do
		if type(e) ~= "table" then return false, "malformed entity list" end
		-- Hit-testing reads place before the renderer's first sync, and a
		-- freshly created entity carries exactly this rect.
		e.place = { x = 0, y = 0, w = 0, h = 0 }
	end

	entity.restore(ents)
	-- Rects are derived from the window, so they arrive blank and have to be
	-- re-derived here rather than a frame later: zone rects are what the
	-- renderer computes card rects *from*, so a zeroed world stays zeroed and
	-- the draw path is handed a card of negative size. flow.init does the same
	-- call for the same reason.
	zones.resize()
	phase.restore({ wrapped = snap.wrapped and true or false, stack = stack })
	rng.set_state(snap.rng or rng.state())
	for i, cond in ipairs(declaration.G.end_conditions or {}) do
		cond.fired = (snap.fired and snap.fired[i]) or nil
	end
	targeting.clear()
	-- The local undo stack describes states the sender never had; undoing into
	-- one of them would silently fork the game.
	flow.forget_history()
	if flow.on_reset then flow.on_reset() end
	return true
end

local function ensure_game(name)
	if not name or name == declaration.filename then return true end
	local ok, err = pcall(flow.init, name)
	if not ok then return false, "cannot load " .. tostring(name) .. ": " .. tostring(err) end
	return true
end

function M.apply_full(snap)
	if type(snap) ~= "table" then return false, "nothing to apply" end
	local ok, err = ensure_game(snap.game)
	if not ok then return false, err end

	local ents = snap.ents
	ok, err = restore(snap, ents)
	if not ok then return false, err end

	log.clear()
	for _, line in ipairs(snap.log or {}) do
		if type(line) == "string" then log.add(line) end
	end
	baseline = M.snapshot()
	if M.on_apply then M.on_apply(snap) end
	return true
end

function M.apply_delta(patch)
	if type(patch) ~= "table" then return false, "nothing to apply" end
	-- Deliberately not ensure_game: loading the file would replace the very
	-- state this patch is a difference *from*, and the patch would then be
	-- rejected against the thing that replaced it. A delta only ever describes
	-- a step inside one game; crossing files is what a full state is for.
	if patch.game and patch.game ~= declaration.filename then
		return false, "delta is for " .. tostring(patch.game) .. ", this is " .. tostring(declaration.filename)
	end

	local here = M.snapshot()
	if patch.base and patch.base ~= M.fingerprint(here) then
		return false, "delta does not fit this state"
	end

	local ents = here.ents
	for k, d in pairs(patch.ents or {}) do
		local i = tonumber(k)
		if i and i >= 1 and type(d) == "table" then
			local e = ents[i] or {}
			for f, v in pairs(d) do if f ~= "-" then e[f] = v end end
			for _, f in ipairs(type(d["-"]) == "table" and d["-"] or {}) do e[f] = nil end
			ents[i] = e
		end
	end
	-- Undo shortens the array; nothing else does.
	for i = #ents, (tonumber(patch.count) or #ents) + 1, -1 do ents[i] = nil end

	ok, err = restore(patch, ents)
	if not ok then return false, err end

	local lg = type(patch.log) == "table" and patch.log or { keep = log.count(), add = {} }
	log.truncate(math.max(0, math.min(tonumber(lg.keep) or 0, log.count())))
	for _, line in ipairs(lg.add or {}) do
		if type(line) == "string" then log.add(line) end
	end
	baseline = M.snapshot()
	if M.on_apply then M.on_apply(patch) end
	return true
end

---------------------------------------------------------------- turn gating

-- Which seat this client may move. nil means "whoever is up", which is what a
-- solo game, a hot-seat game and a spectator all want.
function M.may_act()
	if not M.seat then return true end
	return zones.active_seat() == M.seat
end

function M.seats()
	return declaration.G.seat_list or {}
end

---------------------------------------------------------------- transports
--
-- A transport is a table:
--   send(text)   queue one wire string for the other side
--   recv()       the next wire string received, or nil
--   status()     short human-readable state (optional)
--   close()      tear down (optional)
--
-- net does not care how it moves. netlink.lua has the implementations; the
-- copy/paste path needs no transport at all (export/import, below).

function M.link(transport)
	if link and link.close then pcall(link.close) end
	link = transport
	-- The baseline deliberately survives: two players who both ran net.begin
	-- already share a state, and throwing that away would make the first
	-- message a full state for no reason. A peer who did *not* start there
	-- refuses the delta and asks for a full copy, which costs one round trip
	-- and needs no pessimism here.
	pending_full = baseline == nil
	if link then say("linked: " .. (link.name or "?")) end
	return link
end

function M.unlink()
	if link and link.close then pcall(link.close) end
	link, baseline = nil, nil
	say("offline")
end

function M.linked() return link ~= nil end

function M.status()
	if not link then return "offline" end
	local ok, s = pcall(link.status or function() end)
	return (link.name or "linked") .. ((ok and type(s) == "string") and (" — " .. s) or "")
end

-- A game change is not a difference, it is a different game: entity IDs mean
-- other things on the far side of a load_game, so the first message after one
-- has to carry everything.
local function usable_baseline(cur)
	return baseline ~= nil and baseline.game == cur.game
end

local function transmit(text)
	if not link or not link.send then return false end
	return pcall(link.send, text) and true or false
end

-- Push the current state to the other side: a delta when both sides are known
-- to share a starting point, a whole state otherwise. Silent when offline, so
-- the wrappers at the bottom of this file can call it unconditionally.
function M.publish(force_full)
	if not link then return false end
	seq = seq + 1
	local cur = M.snapshot()
	local text
	if usable_baseline(cur) and not force_full and not pending_full then
		text = pack("D", make_delta(baseline, cur))
	else
		text = pack("F", cur)
	end
	baseline, pending_full = cur, false
	return transmit(text)
end

-- Pull whatever has arrived and apply it. Self-sent and stale messages are
-- dropped: some transports echo to every listener including the sender, and
-- out-of-order delivery must never roll the game backwards.
function M.poll()
	if not link or not link.recv then return false end
	local applied = false
	for _ = 1, 32 do
		local ok, text = pcall(link.recv)
		if not ok or not text or text == "" then break end
		local msg, err = unpack_msg(text)
		if not msg then
			say("ignored a message: " .. tostring(err))
		elseif msg.kind == "R" then
			say("peer asked for a full state")
			M.publish(true)
		elseif msg.seq <= seq and msg.kind ~= "F" then
			-- already past this one
		else
			local done, aerr
			if msg.kind == "D" then done, aerr = M.apply_delta(msg.body)
			else done, aerr = M.apply_full(msg.body) end
			if done then
				seq     = math.max(seq, msg.seq)
				applied = true
			else
				say("could not apply: " .. tostring(aerr))
				-- A delta we cannot fit means the two sides drifted. Ask for a
				-- whole state rather than guessing.
				if msg.kind == "D" then transmit(pack("R", nil)) end
			end
		end
	end
	return applied
end

M.update = M.poll   -- what a love.update caller wants to say

---------------------------------------------------------------- shared start

-- The cheapest possible handshake, and the one that makes copy/paste practical:
-- both players start the same file with the same seed, so they already hold
-- byte-identical states and the first message can be a 300-byte delta instead
-- of a 25 KB state. Now that the engine owns its randomness (rng.lua), "the
-- same seed" finally means the same deck on both machines.
--
-- The invite is short enough to type into a chat window:  RAVEL1I:<game>:<seed>
function M.invite(seed)
	return table.concat({ M.PROTOCOL .. "I", declaration.filename or "?", tostring(seed) }, ":")
end

function M.begin(file, seed)
	local ok, err = pcall(flow.init, file, seed)
	if not ok then return false, tostring(err) end
	seq, baseline, pending_full = 0, M.snapshot(), false
	say("started " .. tostring(file) .. " at seed " .. tostring(seed))
	return true
end

-- Accepts either an invite string or the two parts.
function M.accept(text)
	local file, seed = tostring(text or ""):match(M.PROTOCOL .. "I:([^:]+):(-?%d+)")
	if not file then return false, "not an invite" end
	return M.begin(file, tonumber(seed))
end

---------------------------------------------------------------- manual mode

-- The transport of last resort and the one that always works: a string the
-- player copies into Discord, email or a text message and the other player
-- pastes back. No link required. A first export is a whole state; after that
-- each side exports the difference from the last state it exchanged, which is
-- the difference between a few hundred bytes and a few tens of kilobytes.
function M.export(force_full)
	seq = seq + 1
	local cur = M.snapshot()
	local text
	if usable_baseline(cur) and not force_full then
		text = pack("D", make_delta(baseline, cur))
	else
		text = pack("F", cur)
	end
	baseline = cur
	return text
end

function M.import(text)
	local msg, err = unpack_msg(text)
	if not msg then return false, err end
	if msg.kind == "R" then return false, "that is a request for a full state, not a state" end
	local ok, aerr
	if msg.kind == "D" then ok, aerr = M.apply_delta(msg.body)
	else ok, aerr = M.apply_full(msg.body) end
	if ok then seq = math.max(seq, msg.seq) end
	return ok, aerr
end

---------------------------------------------------------------- flow wrapping

-- Every mutation the interfaces can trigger. Wrapped once, at require time,
-- because main.lua captures flow.play_card and flow.activate into a dispatch
-- table when it loads — a wrapper installed later would never be called from
-- the GUI. They are inert until a transport is linked or a seat is claimed, so
-- requiring this module changes nothing on its own.
for _, name in ipairs({ "play_card", "activate", "pick", "zone_click", "undo" }) do
	local inner = flow[name]
	flow[name] = function(...)
		if not (link or M.seat) then return inner(...) end
		if not M.may_act() then
			say("not your turn — " .. tostring(zones.active_seat()) .. " to play")
			return false
		end
		local result = inner(...)
		if result ~= false then M.publish() end
		return result
	end
end

-- The same gate on the questions the interfaces ask *before* acting, so waiting
-- for your opponent looks like waiting: the renderer dims a card it cannot
-- play, the CLI says so, and nobody starts picking targets for a move that is
-- going to be refused at the end of it.
for _, name in ipairs({ "can_play", "can_activate" }) do
	local inner = flow[name]
	flow[name] = function(...)
		if M.seat and not M.may_act() then return false end
		return inner(...)
	end
end

return M
