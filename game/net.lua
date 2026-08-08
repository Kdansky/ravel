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
-- ============================================================================
-- CHEATING IS NOT HANDLED, AND CANNOT BE WITHOUT A DIFFERENT ARCHITECTURE.
-- ============================================================================
--
-- Two separate things are missing, and neither is a hole to be plugged:
--
--   1. Both players hold the entire state, hidden zones included. A hand is
--      hidden by the renderer, not by the protocol.
--   2. A client applies whatever state arrives. The hashes below check that a
--      message *follows* the state we agreed on — they do not check that the
--      new state is *reachable* from it by a legal move. A modified client can
--      hand you any position it likes and this will accept it.
--
-- What a fix requires, so nobody mistakes it for an afternoon's work: an
-- authoritative referee — a server, or one client designated as one — that
-- receives *moves* rather than states, validates each against the rules, owns
-- the resulting state, and sends every player only the part they are allowed to
-- see. Three of those four are new. The engine has no notion of a state filtered
-- per player, and no notion of validating a move it did not originate; flow
-- re-derives legality for local input (ARCHITECTURE invariant 2) and that is the
-- one piece which would carry over. A move-based protocol at least became
-- possible when rng.lua made a seed mean one sequence everywhere.
--
-- Until then this is play between people who trust each other, and it is not
-- anything else. Do not put it in front of strangers.

local declaration = require("declaration")
local entity      = require("entity")
local phase       = require("phase")
local zones       = require("zones")
local flow        = require("flow")
local log         = require("log")
local json        = require("json")
local rng         = require("rng")
local targeting   = require("targeting")
local netpack     = require("netpack")
local actions     = require("actions")

local M = {}

M.PROTOCOL  = "RAVEL1"
M.seat      = nil   -- the seat this client may play as; nil = play any seat
M.on_apply  = nil   -- hook(snap) — presentation clears its caches after remote state lands
M.on_status = nil   -- hook(text) — connection news worth showing a human

-- Set when the two sides stop agreeing, and left set until a whole state fixes
-- it. Interfaces show it and offer M.request_resync; it is deliberately sticky,
-- because a desync that repaired itself silently is a desync nobody learns
-- about, and the automatic request can itself go unanswered.
M.desync = nil

-- When we last heard anything at all from the far end. Linking a transport
-- always "succeeds" — a broadcast channel with nobody else on it is a perfectly
-- healthy channel — so this is the only thing that can tell a connected player
-- from a player talking to an empty room.
M.last_heard = nil

local link      = nil   -- the active transport, see "Transports" below
local seq       = 0     -- Lamport clock: max(mine, theirs) + 1 on every publish
local baseline  = nil   -- the last state both sides are believed to share
local baseline_hash = nil   -- ...and its fingerprint, kept rather than recomputed
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

-- djb2. Not a cryptographic hash and not trying to be: this catches two people
-- holding different things, not somebody constructing a collision. Cheating is
-- out of scope by design (see the header).
local function djb2(text)
	local h = 5381
	for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
	return string.format("%08x", h)
end

-- A fingerprint of a state, and the whole of the delta protocol's safety. A
-- patch names the fingerprint it was computed against and the one it should
-- produce; a receiver whose own state hashes to something else refuses it and
-- asks for a full copy instead of applying a diff to the wrong thing.
-- json.encode sorts map keys, so the same state hashes the same on both
-- clients.
function M.fingerprint(snap)
	snap = snap or M.snapshot()
	return djb2(json.encode({ snap.ents, snap.phases, snap.rng, snap.fired }))
end

-- The hash of a game *file*, which answers a different question: not "are we in
-- the same position" but "are we even playing the same game". Two people with
-- different versions of lost_cities.json produce states that diff cleanly and
-- mean different things, and that is the failure worth catching at the door
-- rather than three moves later. Cached per filename — the file does not change
-- under a running game, and re-reading it per message would be silly.
local file_hashes = {}

function M.game_hash(filename)
	filename = filename or declaration.filename
	if not filename then return nil end
	if file_hashes[filename] == nil then
		local text = M.game_text(filename)
		file_hashes[filename] = text and djb2(text) or false
	end
	return file_hashes[filename] or nil
end

-- The file's text, wherever it came from. A game an opponent sent us is as real
-- as one on disk, and has to hash the same on both sides.
function M.game_text(filename)
	filename = filename or declaration.filename
	if not filename then return nil end
	return declaration.provided[filename] or love.filesystem.read("games/" .. filename)
end

-- Registering a shared game invalidates its cached hash, which was "false"
-- (meaning "we do not have this") a moment ago.
function M.accept_game(filename, text)
	if type(filename) ~= "string" or type(text) ~= "string" then return false end
	declaration.provide(filename, text)
	file_hashes[filename] = nil
	return true
end

-- The current state's hash, kept beside the state rather than recomputed on
-- demand: the browser panel asks for it every frame, and hashing 19 KB of JSON
-- sixty times a second to draw one line of text is not a trade worth making.
-- Invalidated by the same wrappers that publish, which see every mutation.
local cached_hash = nil

function M.state_hash()
	cached_hash = cached_hash or M.fingerprint()
	return cached_hash
end

local function forget_hash()
	cached_hash = nil
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

-- RAVEL1:<label>:<game>:<seq>:<kind><enc>:<payload>
--   label init · t<round>p<seat> · resync — what this message *is*, in words
--   kind  F full state · D delta · R "I am lost, send me a full state"
--         H "I am here" — carries nothing, and exists because a transport that
--           connects successfully to nobody looks exactly like one that works
--         Q "I do not have that game, send it" · G the game file itself
--   enc   x base64(lzss(json)) · j base64(json), when lzss found nothing
--
-- The header is deliberately plain text and deliberately first. Someone reading
-- a chat log, or a bug report with a blob pasted into it, can see that this is
-- turn 3 of player 1 in lost_cities.json without decoding anything — and the
-- receiver can drop a stale message without unpacking it either. `luajit
-- packet.lua '<blob>'` turns the rest into readable text.
--
-- The label is descriptive, never load-bearing: nothing branches on it, so a
-- sender that got it wrong is a cosmetic bug rather than a protocol one.
--
-- Every message carries three hashes, and they answer three different questions:
--
--   gh    the game *file* — "are we even playing the same game?"  A mismatch is
--         fatal and says so: no amount of resyncing fixes two different files.
--   prev  the state this message follows — "did we start from the same place?"
--         A delta that does not fit is refused rather than applied to the wrong
--         thing. Absent only on a cold full state, which follows nothing.
--   post  the state this message produces — "did we end up in the same place?"
--         Checked after applying, so a divergence is caught the moment it
--         happens instead of surfacing as a rejected delta several turns later.

local function envelope(body, from_hash, to_hash)
	body.gh   = M.game_hash(body.game)
	body.prev = from_hash
	body.post = to_hash
	return body
end

-- The snapshot is shallow-copied before the envelope goes on it, so the table
-- kept as `baseline` stays a state and never quietly becomes a message.
local function as_message(snap)
	local m = {}
	for k, v in pairs(snap) do m[k] = v end
	return m
end

-- Where the game has got to, in four characters. Reads off the system card,
-- which is where the engine keeps the round counter and whose turn it is.
function M.marker()
	local round, turn = 0, 0
	for e in entity.each("card") do
		if e.def_key == "system" and e.zone_id then
			round = math.floor(tonumber(e.stats.round) or 0)
			turn  = math.floor(tonumber(e.stats.turn) or 0)
			break
		end
	end
	if #(declaration.G.seat_list or {}) < 2 then return "t" .. round end
	return ("t%dp%d"):format(round, turn)
end

local function pack(kind, body, label)
	local text = body and json.encode(body) or ""
	local enc  = "j"
	if #text > 0 then
		-- A three-line delta sometimes has nothing to repeat, and base64 charges
		-- its 33% either way, so send whichever actually came out shorter.
		local z = netpack.compress(text)
		if #z < #text then text, enc = z, "x" end
	end
	return table.concat({ M.PROTOCOL, label or M.marker(),
		(body and body.game) or declaration.filename or "?",
		tostring(seq), kind .. enc, netpack.encode(text) }, ":")
end

local function unpack_msg(text)
	if type(text) ~= "string" then return nil, "not a string" end
	-- No field can legitimately contain whitespace — game files are bare names
	-- and base64 has none — so the cheapest way to survive a chat client that
	-- hard-wraps a long line, or a paste that picked up a stray newline, is to
	-- take the whitespace out before reading anything.
	text = text:gsub("%s+", "")
	local label, game, msg_seq, mode, body =
		text:match(M.PROTOCOL .. ":([^:]*):([^:]*):([^:]*):(%a%a):([A-Za-z0-9+/=]*)")
	if not game then return nil, "not a " .. M.PROTOCOL .. " message" end
	local kind, enc = mode:sub(1, 1), mode:sub(2, 2)
	local out = { kind = kind, label = label, game = game, enc = enc,
		seq = tonumber(msg_seq) or 0 }
	if kind == "R" or kind == "H" or kind == "Q" then return out end

	local raw = netpack.decode(body)
	if not raw then return nil, "corrupt base64" end
	if enc == "x" then
		raw = netpack.decompress(raw)
		if not raw then return nil, "corrupt payload" end
	elseif enc ~= "j" then
		return nil, "unknown encoding '" .. tostring(enc) .. "'"
	end

	local ok, snap = pcall(json.decode, raw)
	if not ok or type(snap) ~= "table" then return nil, "payload is not JSON" end
	if kind == "G" then
		if type(snap.text) ~= "string" or type(snap.game) ~= "string" then
			return nil, "payload is not a game file"
		end
		out.body = snap
		return out
	end
	if type(snap.ents) ~= "table" or type(snap.phases) ~= "table" then
		return nil, "payload is not a game state"
	end
	-- The header is written from the body, so the two disagreeing means the
	-- message was damaged or edited in transit. Cheap to check, and it keeps the
	-- header meaningful rather than decorative.
	if snap.game and game ~= "" and snap.game ~= game then
		return nil, "header says " .. game .. " but the payload says " .. tostring(snap.game)
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

-- The first check, and the only one that is fatal. Two people holding different
-- versions of a game file produce states that diff perfectly cleanly and mean
-- entirely different things, so this refuses at the door and says why rather
-- than asking for a resync that cannot help.
local function same_game(body)
	if not body.gh then return true end          -- older sender, nothing to check
	local mine = M.game_hash(body.game)
	if not mine then
		return false, "you do not have " .. tostring(body.game)
	end
	if mine ~= body.gh then
		return false, ("different versions of %s — theirs %s, yours %s. You both need the same file.")
			:format(tostring(body.game), body.gh, mine)
	end
	return true
end

-- Some refusals are worth retrying with a whole state and some are not. A delta
-- that does not fit is the first kind; a game file that does not match is the
-- second, and asking for a resync there just sends the same wrong thing again.
local function missing_game(err)
	return tostring(err):find("you do not have ") == 1
end

local function fatal(err)
	return tostring(err):find("different versions of ") == 1
		or tostring(err):find("you do not have ") == 1
end

-- When the two engines disagree about what a state hashes to, every delta is
-- going to be rejected forever. Rather than loop on resync requests, say so
-- once and fall back to whole states, which always apply.
M.divergent = false

local function check_landing(body)
	forget_hash()
	if not body.post then return end
	local got = M.state_hash()
	if got == body.post then return end
	M.desync = ("applied their message and landed somewhere else (theirs %s, mine %s)")
		:format(body.post, got)
	if not M.divergent then
		M.divergent = true
		say(M.desync .. " — sending whole states from now on; a different engine "
			.. "version is the usual cause")
	end
end

function M.apply_full(snap)
	if type(snap) ~= "table" then return false, "nothing to apply" end
	local ok, err = same_game(snap)
	if not ok then return false, err end
	ok, err = ensure_game(snap.game)
	if not ok then return false, err end

	local ents = snap.ents
	ok, err = restore(snap, ents)
	if not ok then return false, err end

	log.clear()
	for _, line in ipairs(snap.log or {}) do
		if type(line) == "string" then log.add(line) end
	end
	check_landing(snap)
	if not M.divergent then M.desync = nil end   -- a whole state is the cure
	baseline, baseline_hash = M.snapshot(), M.state_hash()
	if M.on_apply then M.on_apply(snap) end
	return true
end

function M.apply_delta(patch)
	if type(patch) ~= "table" then return false, "nothing to apply" end
	local ok, err = same_game(patch)
	if not ok then return false, err end
	-- Deliberately not ensure_game: loading the file would replace the very
	-- state this patch is a difference *from*, and the patch would then be
	-- rejected against the thing that replaced it. A delta only ever describes
	-- a step inside one game; crossing files is what a full state is for.
	if patch.game and patch.game ~= declaration.filename then
		return false, "delta is for " .. tostring(patch.game) .. ", this is " .. tostring(declaration.filename)
	end

	local here = M.snapshot()
	if patch.prev and patch.prev ~= M.fingerprint(here) then
		M.desync = "their move follows state " .. patch.prev
			.. ", we are at " .. M.fingerprint(here)
		return false, M.desync
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
	check_landing(patch)
	baseline, baseline_hash = M.snapshot(), M.state_hash()
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
	M.last_heard = nil
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
	link, baseline, baseline_hash = nil, nil, nil
	M.last_heard = nil
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
	local text = M.compose(force_full)
	return transmit(text)
end

-- Builds the next message and moves the baseline forward. Shared by publish and
-- export, because a string pasted into Discord and a string pushed down a data
-- channel are the same string.
function M.compose(force_full)
	local cur  = M.snapshot()
	local to   = M.fingerprint(cur)
	local from = baseline_hash
	local text
	-- The label says what kind of message this is, in words, before anything is
	-- decoded: a whole state sets the receiver up from scratch, so it reads
	-- "init"; a delta is one turn, so it reads "t3p1".
	if usable_baseline(cur) and not force_full and not pending_full and not M.divergent then
		text = pack("D", envelope(make_delta(baseline, cur), from, to), M.marker())
	else
		text = pack("F", envelope(as_message(cur), from, to), "init")
	end
	baseline, baseline_hash, pending_full = cur, to, false
	cached_hash = to
	return text
end

-- "Ask them for everything." The automatic version fires when a delta does not
-- fit; this is the one a player presses when the two screens plainly disagree
-- and nothing has repaired itself — a message can be lost, and a lost message
-- means the automatic request was lost too.
-- Sharing the game itself. An opponent who has never seen the file can still be
-- dealt into it: the position is meaningless without the rules, so the rules
-- travel too. 12.5 KB on the wire for Lost Cities, sent once and only when
-- asked, which is why it is not folded into the invite — that has to stay small
-- enough to paste into a chat message.
--
-- What does *not* travel is anything the file only points at. A game whose cards
-- name local image files will render as text on the far side; one using
-- "placeholder_art" looks identical, because that art is generated rather than
-- fetched.
function M.share_game()
	if not link then return false end
	local name = declaration.filename
	local text = M.game_text(name)
	if not text then return false end
	seq = seq + 1
	transmit(pack("G", { game = name, text = text }, "game"))
	return M.publish(true)   -- the rules, then the position
end

local asked_for = nil   -- the game we have already begged for, so we ask once

function M.request_game(name)
	if not link or asked_for == name then return false end
	asked_for = name
	seq = seq + 1
	say("asking them for " .. tostring(name))
	return transmit(pack("Q", nil, "need-game"))
end

function M.request_resync()
	if not link then return false, "not connected" end
	seq = seq + 1
	pending_full = true    -- whatever we send next must be whole, too
	say("asked them for a full state")
	return transmit(pack("R", nil, "resync"))
end

-- Pull whatever has arrived and apply it. Self-sent and stale messages are
-- dropped: some transports echo to every listener including the sender, and
-- out-of-order delivery must never roll the game backwards.
function M.poll()
	if not link or not link.recv then return false end
	local applied = false
	-- Whether this poll is the first time we have heard anything at all. The
	-- peer that links second is heard by the peer that linked first, and hears
	-- nothing back — so first contact is answered with a hello, once, which is
	-- what stops "connected to nobody" and "connected" looking identical.
	local first_contact = M.last_heard == nil
	for _ = 1, 32 do
		local ok, text = pcall(link.recv)
		if not ok or not text or text == "" then break end
		M.last_heard = os.time()
		local msg, err = unpack_msg(text)
		if not msg then
			say("ignored a message: " .. tostring(err))
		elseif msg.kind == "H" then
			-- Presence only. M.last_heard above is the entire point of it.
		elseif msg.kind == "Q" then
			say("they do not have this game — sending it")
			M.share_game()
		elseif msg.kind == "G" then
			if M.accept_game(msg.body.game, msg.body.text) then
				say("received the game " .. msg.body.game .. " (" .. #msg.body.text .. " bytes)")
				asked_for = nil
			end
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
				-- Three different repairs. A delta that does not fit means the
				-- two sides drifted, and a whole state fixes it. A game we do
				-- not have is a thing to ask for. Two different *versions* of
				-- one file is the only genuinely fatal case, because whose copy
				-- is right is not ours to decide.
				if missing_game(aerr) then M.request_game(msg.game)
				elseif msg.kind == "D" and not fatal(aerr) then
					transmit(pack("R", nil, "resync"))
				end
			end
		end
	end
	-- Deliberately a hello and not a state: we may have just *refused* what they
	-- sent (a different game file, say), and answering that by overwriting them
	-- with our own position would turn a clear error into a silent one.
	if first_contact and M.last_heard then transmit(pack("H", nil, "hello")) end
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

-- Four things can arrive in the same box, so one function decides which is
-- which and the interfaces route on the answer. The alternative is the panel
-- and the CLI each growing their own opinion about the grammar.
--
--   RAVEL1:…    a state or a delta        RAVEL1I:…   an invite
--   RAVEL1O:…   a peer-to-peer offer      RAVEL1A:…   its answer
function M.kind_of(text)
	text = tostring(text or ""):gsub("%s+", "")
	for suffix, kind in pairs({ I = "invite", O = "offer", A = "answer" }) do
		if text:find("^" .. M.PROTOCOL .. suffix .. ":") then return kind end
	end
	if text:find("^" .. M.PROTOCOL .. ":") then return "state" end
	return nil
end

-- The signalling blobs travel in the same envelope, so a player only ever has
-- one box to paste into and never has to know which of the four they hold.
function M.wrap_sdp(kind, blob)
	return M.PROTOCOL .. (kind == "offer" and "O" or "A") .. ":" .. blob
end

function M.unwrap_sdp(text)
	return (tostring(text or ""):gsub("%s+", ""):match("^" .. M.PROTOCOL .. "[OA]:(.+)$"))
end

function M.begin(file, seed)
	local ok, err = pcall(flow.init, file, seed)
	if not ok then return false, tostring(err) end
	seq, baseline, pending_full = 0, M.snapshot(), false
	M.divergent, M.desync = false, nil
	forget_hash()
	baseline_hash = M.state_hash()
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
	return M.compose(force_full)
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

---------------------------------------------------------------- as cards
--
-- Networking is a thing a card does. That is invariant 7 — *when in doubt,
-- decks and cards* — applied to the last corner of the engine that still had a
-- bespoke UI policy: the panel used to ask "does this game have two seats, and
-- should I therefore offer an invite?", which is a question about content
-- answered in the presentation layer. Now a two-player game deals a card that
-- says "play this with a friend", a solitaire game deals no such card, and
-- nothing anywhere has to guess.
--
-- It also generalises for free. Three seats, a spectator invite, or a card that
-- sits you in a particular chair are all different arguments to the same ops
-- rather than different branches in a panel.
--
-- These are the one kind of action that changes no game state: they ask the
-- presentation layer to show something. The engine already has that shape —
-- actions.on_effect does exactly this for particle effects — and it is why the
-- op is safe to play while nothing is connected, which is precisely when you
-- need it.

M.on_ui = nil   -- hook(what) — the presentation layer opens its networking UI

-- actions.lua declares the words; this supplies the meaning. Assigning the hook
-- on require is what makes the net_* ops do anything, and not requiring this
-- file is what makes them silent.
actions.on_net = function(what, arg)
	if what == "seat" then
		-- Which chair you are sitting in. Local, not game state: it says who
		-- *you* are, not what is true of the game, so it is never published.
		M.seat = (arg and arg ~= "" and arg ~= "any") and arg or nil
		say(M.seat and ("you are " .. M.seat) or "playing any seat")
	elseif what == "offline" then
		M.unlink()
	elseif M.on_ui then
		M.on_ui(what)
	else
		say("this build has no networking UI (try the CLI's 'n' commands)")
	end
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
		if (link or M.seat) and not M.may_act() then
			say("not your turn — " .. tostring(zones.active_seat()) .. " to play")
			return false
		end
		local result = inner(...)
		-- Unconditionally, even when nobody is connected: these wrappers are the
		-- only things that see every mutation, so they are the only place the
		-- cached hash can be invalidated from. Skipping it while offline left a
		-- stale hash for whoever linked later.
		forget_hash()
		if result ~= false then M.publish() end   -- silent when offline
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
