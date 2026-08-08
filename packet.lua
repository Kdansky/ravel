-- Turn a network packet back into something a person can read. From the repo
-- root, with the blob quoted or on stdin:
--
--   luajit packet.lua 'RAVEL1:t1p1:lost_cities.json:2:Dx:AHsi…'
--   pbpaste | luajit packet.lua
--   luajit packet.lua --json 'RAVEL1:…'     the decoded payload, raw
--
-- Entity IDs are resolved to card and zone names by loading the game the packet
-- names. That works — and is the reason this tool is worth having — because IDs
-- are handed out in file order at load, so they mean the same thing on every
-- client regardless of seed. The shuffle permutes a zone's card list, never the
-- IDs themselves.

require("headless")

local net     = require("net")
local netpack = require("netpack")
local json    = require("json")
local flow    = require("flow")
local entity  = require("entity")
local cards   = require("cards")

local args, want_json = {}, false
for _, a in ipairs(arg) do
	if a == "--json" then want_json = true else args[#args + 1] = a end
end

local text = args[1]
if not text or text == "-" then text = io.read("*a") end
if not text or text:match("^%s*$") then
	print("usage: luajit packet.lua [--json] '<packet>'   (or pipe it on stdin)")
	os.exit(1)
end

---------------------------------------------------------------- header

text = text:gsub("%s+", "")
local label, game, seq, mode, body =
	text:match("(RAVEL1[IOA]?):?([^:]*):?([^:]*):?([^:]*):?(%a?%a?):?([A-Za-z0-9+/=]*)")

-- The two signalling envelopes are a different shape and worth naming rather
-- than failing on.
local sdp = text:match("^RAVEL1([OA]):(.+)$")
if sdp then
	local kind = text:sub(7, 7) == "O" and "offer" or "answer"
	local raw  = netpack.decode(text:match("^RAVEL1[OA]:(.+)$")) or ""
	print(("RAVEL1 %s — a WebRTC %s, %d chars"):format(kind, kind, #text))
	print("  this is signalling, not game state. It contains the sender's IP")
	print("  addresses, which is what it is for.")
	local addrs = {}
	for a in raw:gmatch("c=IN IP4 ([%d%.]+)") do addrs[#addrs + 1] = a end
	for a in raw:gmatch("candidate:%S+ %d+ %S+ %d+ ([%d%.]+)") do addrs[#addrs + 1] = a end
	local seen, uniq = {}, {}
	for _, a in ipairs(addrs) do
		if not seen[a] then seen[a] = true; uniq[#uniq + 1] = a end
	end
	print("  addresses: " .. (next(uniq) and table.concat(uniq, ", ") or "none found"))
	if want_json then print(raw) end
	os.exit(0)
end

local invite_game, invite_seed = text:match("^RAVEL1I:([^:]+):(-?%d+)$")
if invite_game then
	print(("RAVEL1 invite — start %s at seed %s"):format(invite_game, invite_seed))
	print("  both players run this; from then on every message is a delta.")
	os.exit(0)
end

-- The loose match above only existed to spot the signalling envelopes; a game
-- packet gets the strict one.
label, game, seq, mode, body =
	text:match("RAVEL1:([^:]*):([^:]*):([^:]*):(%a%a):([A-Za-z0-9+/=]*)")
if not label then
	print("not a RAVEL1 packet: " .. text:sub(1, 60))
	os.exit(1)
end

local kind, enc = mode:sub(1, 1), mode:sub(2, 2)
local KINDS = {
	F = "full state — everything, applied wholesale",
	D = "delta — the difference from one named state to another",
	R = "resync request — 'I am lost, send me everything'",
	H = "hello — presence only, carries nothing",
}
local LABELS = {
	init   = "a whole state, which is what a player needs to start",
	resync = "a request, carrying nothing",
	hello  = "proof somebody is listening, carrying nothing",
}

print(("RAVEL1 packet, %d characters"):format(#text))
print(("  label     %-10s %s"):format(label,
	LABELS[label] or (label:match("^t(%d+)p(%d+)$")
		and ("turn " .. label:match("^t(%d+)") .. ", player " .. label:match("p(%d+)$"))
		or (label:match("^t(%d+)$") and ("turn " .. label:match("^t(%d+)")) or ""))))
print(("  game      %s"):format(game))
print(("  seq       %s"):format(seq))
print(("  kind      %s  %s"):format(kind, KINDS[kind] or "unknown"))

if kind == "R" or kind == "H" then
	print("  (no payload)")
	os.exit(0)
end

---------------------------------------------------------------- payload

local packed = netpack.decode(body)
if not packed then print("  payload: corrupt base64"); os.exit(1) end
local raw = packed
if enc == "x" then
	raw = netpack.decompress(packed)
	if not raw then print("  payload: corrupt lzss"); os.exit(1) end
elseif enc ~= "j" then
	print("  payload: unknown encoding '" .. enc .. "'"); os.exit(1)
end

print(("  encoding  %s  %s"):format(enc, enc == "x" and "lzss" or "plain"))
print(("  sizes     %d json → %d compressed (%.1fx) → %d on the wire (base64 +33%%)")
	:format(#raw, #packed, #raw / math.max(1, #packed), #text))

local ok, p = pcall(json.decode, raw)
if not ok or type(p) ~= "table" then print("  payload is not JSON: " .. tostring(p)); os.exit(1) end

if want_json then
	print(json.encode(p, true))
	os.exit(0)
end

print("  hashes")
print(("    game file %s  %s"):format(tostring(p.gh),
	(function()
		local mine = net.game_hash(game)
		if not mine then return "(you do not have " .. game .. ")" end
		return mine == p.gh and "— matches your copy" or ("— YOURS IS " .. mine .. ", THESE DIFFER")
	end)()))
print(("    follows   %s"):format(tostring(p.prev or "nothing (a cold start)")))
print(("    produces  %s"):format(tostring(p.post)))

---------------------------------------------------------------- names

-- Load the named game purely to learn what each entity ID is. Any seed will do.
local names = {}
if net.game_hash(game) then
	local loaded = pcall(flow.init, game, 1)
	if loaded then
		for e in entity.each() do
			if e.kind == "card" then
				local def = cards.def(e)
				names[e.id] = "card " .. e.def_key
					.. ((def and def.text and def.text ~= e.def_key) and (" (" .. def.text .. ")") or "")
			elseif e.kind == "zone" then
				names[e.id] = "zone " .. tostring(e.key) .. (e.seat and ("@" .. e.seat) or "")
			elseif e.kind == "slot" then
				names[e.id] = "slot " .. tostring(e.slot_idx)
			end
		end
	end
end

-- A card created during play is in no fresh load, so it has no name from the
-- game file — but the patch that creates it carries its def_key, which is the
-- same thing said a different way.
local function name_of(id, patch)
	local known = names[tonumber(id) or -1]
	if known then return known end
	if type(patch) == "table" and patch.def_key then
		return "card " .. tostring(patch.def_key) .. " (new)"
	end
	return "entity " .. tostring(id)
end

local function brief(v)
	if type(v) ~= "table" then return tostring(v) end
	local n = 0
	for _ in pairs(v) do n = n + 1 end
	if #v == n and n > 4 then return "[" .. n .. " ids]" end
	return (json.encode(v):gsub("%s+", " "))
end

---------------------------------------------------------------- what changed

if kind == "F" then
	local n = 0
	for _ in ipairs(p.ents or {}) do n = n + 1 end
	print(("  state     %d entities, %d log lines, rng at %s"):format(n, #(p.log or {}), tostring(p.rng)))
	local ph = {}
	for _, f in ipairs(p.phases or {}) do ph[#ph + 1] = f.key end
	print("  phases    " .. table.concat(ph, " / "))
	print("  (a full state replaces everything; there is no 'what changed'.)")
	os.exit(0)
end

local ids = {}
for k in pairs(p.ents or {}) do ids[#ids + 1] = tonumber(k) end
table.sort(ids)
print(("  changed   %d entities"):format(#ids))
for _, id in ipairs(ids) do
	local d = p.ents[tostring(id)]
	local bits = {}
	for f, v in pairs(d) do
		if f ~= "-" then bits[#bits + 1] = f .. "=" .. brief(v) end
	end
	table.sort(bits)
	for _, f in ipairs(type(d["-"]) == "table" and d["-"] or {}) do
		bits[#bits + 1] = "removed " .. f
	end
	print(("    #%-4d %-34s %s"):format(id, name_of(id, d), table.concat(bits, "  ")))
end

local lg = p.log or {}
if lg.keep or lg.add then
	print(("  log       keep %s, add %d"):format(tostring(lg.keep), #(lg.add or {})))
	for _, line in ipairs(lg.add or {}) do print("    + " .. line) end
end

local ph = {}
for _, f in ipairs(p.phases or {}) do ph[#ph + 1] = f.key end
print("  phases    " .. table.concat(ph, " / "))
print(("  rng       at %s"):format(tostring(p.rng)))
