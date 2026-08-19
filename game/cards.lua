local entity      = require("entity")
local declaration = require("declaration")
local json        = require("json")
local art         = require("art")

local M = {}

local EMPTY = {}

-- The look a card's tags add up to: every style they name, merged. Two styles
-- claiming the same property is an authoring conflict the validator reports, so
-- nothing here has to invent a winner.
--
-- The definition tags are merged once at load (`def.style`). Only a style word
-- that is also a *computed* tag can change while the game runs, and the parse
-- knows which those are — so a game with none returns the cached table and pays
-- nothing, and one with them pays only for the entities carrying them.
function M.style(e)
	local G    = declaration.G
	local def  = e and M.def(e)
	local base = (def and def.style) or EMPTY
	local dyn  = G.dynamic_styles
	if not e or not dyn or #dyn == 0 then return base end
	local out
	for _, name in ipairs(dyn) do
		if require("tags").entity_has(e, name) then
			if not out then
				out = {}
				for k, v in pairs(base) do out[k] = v end
			end
			for k, v in pairs(G.style_defs[name]) do out[k] = v end
		end
	end
	return out or base
end

-- Image cache: def_key → love.graphics.Image or false
local img_cache = {}
-- Web-asset fetches in flight: url id -> job. The two platforms keep different
-- shapes in here ({ at = last poll } in the browser, { thread, channel } on the
-- desktop) and share the table safely only because exactly one of them ever
-- runs — see the branch in M.asset_image.
local pending   = {}

-- Strict allowlist for URLs that get spliced into a generated JS program
-- (see fetch_browser below): only the characters RFC 3986 actually permits
-- unencoded in a URL. This is the real defense, not the escaping further
-- down — it outright refuses anything containing a quote, backslash, angle
-- bracket, raw whitespace/control byte, or non-ASCII byte (which includes
-- the U+2028/U+2029 line separators JS string literals forbid raw), so
-- there is no character left that could ever break out of the string
-- literal it's placed in. A malformed/suspicious asset is treated exactly
-- like a missing one — refused, not "cleaned up".
local URL_SAFE_PATTERN = "^https?://[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]+$"

function M.url_is_safe(url)
	return type(url) == "string" and #url > 0 and #url < 2000
		and url:match(URL_SAFE_PATTERN) ~= nil
end

function M.reset()
	img_cache = {}
	pending   = {}
end

-- Give a card a stat it does not have yet, from what the game file wrote.
--
-- A number is a bare current value with no ceiling. A list is the bounds
-- written where a reader can see them:
--
--   "hp": 4               current 4, no floor and no ceiling
--   "hp": [4, 4]          current 4, ceiling 4
--   "hp": [0, 4, 4]       floor 0, current 4, ceiling 4
--
-- The floor left out is whatever the global "stats" entry says, and nothing if
-- it says nothing — so a card only writes a bound it actually differs on.
--
-- **The three live in three tables, and only this function knows that.** A
-- stat is read as `e.stats[key]` everywhere it was before; the ceiling and the
-- floor sit beside it rather than inside it, which is what stops "hp_max" being
-- a stat in its own right that conditions count, actions spend and a tooltip
-- lists as if the player had one point of maximum.
--
-- Untrusted content: every value is coerced to a real number here so nothing
-- downstream can be tricked into arithmetic on a string or a table.
function M.attach_stat(e, key, value)
	local lo, cur, hi
	if type(value) == "table" then
		local n = #value
		if n >= 3 then
			lo, cur, hi = tonumber(value[1]), tonumber(value[2]), tonumber(value[3])
		elseif n == 2 then
			cur, hi = tonumber(value[1]), tonumber(value[2])
		else
			cur = tonumber(value[1])
		end
	else
		cur = tonumber(value)
	end
	e.stats[key] = cur or 0
	if hi then e.stat_max[key] = hi end
	if lo then e.stat_min[key] = lo end
end

function M.create(def_key, zone_id)
	local def = declaration.G.card_defs[def_key]
	assert(def, "Unknown card def: " .. tostring(def_key))
	local e = {
		kind      = "card",
		def_key   = def_key,
		zone_id   = zone_id,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		stats     = {},    -- per-entity stats: the current value of each
		stat_max  = {},    -- the ceiling of each, where one was declared
		stat_min  = {},    -- the floor of each, where one was declared
		parent_id = nil,   -- set when attached to another card
		attached  = {},    -- IDs of cards attached to this card
	}
	if def.card_stats then
		for k, v in pairs(def.card_stats) do M.attach_stat(e, k, v) end
	end
	entity.register(e)
	local zone = entity.get(zone_id)
	-- **A card is born owned, and stays owned.** Ownership is a property of the
	-- card, not of wherever it happens to be lying: dealt out of a seat's own
	-- deck, it is that seat's through the hand, the board and the discard, and
	-- only something that says so in as many words takes it away. Derived from
	-- the zone instead, it was a fact that evaporated the moment a card was
	-- played onto a shared board — which is where "a board can be shared while
	-- the pieces on it are not" quietly stopped being true.
	--
	-- A card created in a shared zone has no owner and never gains one by
	-- moving, which is what keeps a discard pile a discard pile: Lost Cities
	-- deals from one shared deck, so either player may take from either pile.
	-- setup.place writes its own owner straight after this, and so does
	-- transform, so an explicit answer still wins.
	if zone and zone.seat then
		e.stats.owner = (declaration.G.seat_index or {})[zone.seat]
	end
	if zone then table.insert(zone.cards, e.id) end
	return e
end

function M.def(card_entity)
	return declaration.G.card_defs[card_entity.def_key]
end

-- Every activated ability this card has right now: its own, then any its zone
-- hands out. **Added, not substituted** — a zone that grants an ability used to
-- hide the card's own, so a rook lying in a discard pile could be taken and no
-- longer moved. One card can do two things, and the player is asked which.
-- Everything this card can do, in the order it is asked.
--
--   1. its own, written on the card
--   2. what lying *here* lets it do, from the zone's "applies"
--   3. what its own tags give it — its keywords
--
-- **Keywords come last on purpose.** A keyword is usually an addition to
-- whatever else applies, and one that changes an *outcome* has to run after the
-- outcome: Overwhelm sends the damage past a dead blocker onwards, and there is
-- nothing to send until the blocker has been struck.
function M.abilities(card_entity)
	local out = {}
	local def = M.def(card_entity)
	for _, a in ipairs((def and def.abilities) or EMPTY) do out[#out + 1] = a end
	local z = card_entity and card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		for _, a in ipairs((td and td.abilities) or EMPTY) do out[#out + 1] = a end
	end
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		for _, a in ipairs((td and td.abilities) or EMPTY) do out[#out + 1] = a end
	end
	return out
end

-- Only what the zone a card lies in hands it, through "applies". Prose wants
-- this on its own: "advance the expedition" and "take this into your hand"
-- describe different acts, and the tooltip shows both.
function M.zone_grant(card_entity, field)
	local z = card_entity.zone_id and entity.get(card_entity.zone_id)
	for _, tag in ipairs(z and z.applies or {}) do
		local td = declaration.G.tag_defs[tag]
		if td and td[field] ~= nil then return td[field] end
	end
end

-- What a card does *here*. Where a card is decides what it can do, so the zone
-- answers first and the card's own definition answers when the zone says
-- nothing: a creature lying in a graveyard that grants "return to hand" offers
-- that, not the tap ability it had on the board. There is no card-wins rule
-- behind it — a card and its zone defining the same behaviour is an authoring
-- conflict, which the validator reports rather than silently picking a winner.
--
-- Deliberately not folded into def(): that is a bare table lookup on the
-- per-frame path for render, targeting, costs and tooltips, and it must stay
-- one. Only the handful of sites that ask "can this be used" come through here.
function M.behaviour(card_entity, field)
	local granted = M.zone_grant(card_entity, field)
	if granted ~= nil then return granted end
	local def = M.def(card_entity)
	return def and def[field]
end

-- What a card's *own* tags say about it, in the order the card wrote them.
--
-- A keyword is a tag with a meaning, and the meaning belongs in one place: the
-- game says once what Tough does and every card that has it inherits the
-- sentence, instead of thirty templates each carrying their own copy for
-- somebody to keep in step. The tag itself is what the *rules* read; this is
-- only what a player reads.
--
-- Distinct from zone_grant, which answers for tags a zone hands out through
-- "applies" — that is what a card can do *here*, and this is what it is
-- everywhere.
function M.keywords(card_entity)
	local out = {}
	local def = M.def(card_entity)
	for _, tag in ipairs(type(def) == "table" and type(def.tags) == "table" and def.tags or EMPTY) do
		local td = declaration.G.tag_defs[tag]
		if td and type(td.tooltip) == "string" and td.tooltip ~= "" then
			out[#out + 1] = { tag = tag, text = td.tooltip }
		end
	end
	return out
end

-- The zone a card's tags call home: the first of its tags whose tag
-- definition names a zone. nil when no tag does.
function M.home_zone(def)
	if type(def.tags) ~= "table" then return nil end
	for _, t in ipairs(def.tags) do
		local td = declaration.G.tag_defs[t]
		if td and td.zone then return td.zone end
	end
end

-- Overwrite instance stats with the template's card_stats. Used when a
-- template's stats change: immediate dev feedback beats preserving damage.
local function restamp(def_key, card_stats)
	for e in entity.each("card") do
		-- skip destroyed husks (no zone): they must stay stat-less
		if e.def_key == def_key and e.zone_id then
			e.stats, e.stat_max, e.stat_min = {}, {}, {}
			for k, v in pairs(card_stats or {}) do M.attach_stat(e, k, v) end
		end
	end
end

-- Edit a card template in place, for live development. Instances only hold a
-- def_key, so every one of them reflects the change immediately. `raw` is
-- parsed as JSON; if that fails it's taken as a plain string. "null" clears
-- the field.
function M.edit(def_key, field, raw)
	local def = declaration.G.card_defs[def_key]
	if not def then return false, "unknown card: " .. tostring(def_key) end
	-- Scenery is not content. The menu is a game like any other, which means the
	-- live-edit tools point straight at it; "immutable" is how a card says it is
	-- part of the furniture and must not be rewritten under the player.
	if def.tags_set and def.tags_set.immutable then
		return false, "immutable card: " .. tostring(def_key)
	end
	local ok, value = pcall(json.decode, raw)
	if not ok then value = raw end
	def[field] = value
	if field == "tags" then
		def.tags_set = {}
		if type(value) == "table" then
			for _, t in ipairs(value) do def.tags_set[t] = true end
		end
	elseif field == "card_stats" then
		restamp(def_key, value)
	elseif field == "asset" then
		img_cache[def_key] = nil
	end
	return true
end

-- Copy of a template without derived fields, for dumps and the debug API.
function M.template(def_key)
	local def = declaration.G.card_defs[def_key]
	if not def then return nil, "unknown card: " .. tostring(def_key) end
	local copy = {}
	for k, v in pairs(def) do
		if k ~= "tags_set" then copy[k] = v end
	end
	return copy
end

-- Template as pretty JSON, ready to paste back into the game file.
function M.dump(def_key)
	local copy, err = M.template(def_key)
	return copy and json.encode(copy, true), err
end

local function stats_equal(a, b)
	a, b = a or {}, b or {}
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Re-read templates from the current game file: edit the JSON in your editor,
-- reload, keep playing. Only template-ish data is swapped — zones and phases
-- are structural and need a full game load. Instances whose card_stats
-- changed on disk are re-stamped.
function M.reload()
	local ok, fresh = pcall(declaration.parse, declaration.filename)
	if not ok then return false, fresh end
	local G = declaration.G
	for key, def in pairs(fresh.card_defs) do
		local old = G.card_defs[key]
		if not (old and stats_equal(old.card_stats, def.card_stats)) then
			restamp(key, def.card_stats)
		end
	end
	for _, k in ipairs(declaration.TEMPLATE_FIELDS) do G[k] = fresh[k] end
	img_cache = {}
	return true
end

-- A condition as prose. "gold >= 3" is exact and is written for the game file;
-- a tooltip is read by somebody who has never seen one, so the operator becomes
-- a phrase and the two operands swap into English order.
local WORDS = { [">="] = "at least ", ["<="] = "at most ", [">"] = "more than ",
	["<"] = "fewer than ", ["=="] = "exactly ", ["!="] = "anything but " }

local function condition_text(s)
	-- Required here rather than at the top: predicate reaches zones, and zones
	-- reaches this file. The parse is pure, so late is as good as early.
	local c = require("predicate").parse_condition(s)
	if not c then return tostring(s) end
	return WORDS[c.op] .. (c.right.src or tostring(c.right.n)) .. " " .. (c.left.src or tostring(c.left.n))
end

-- "2 gold, 1 food" for a cost, "at least 3 gold" for a condition. One function
-- because one tooltip row shows either: a cost is a map of what gets spent, and
-- `needs` / `accepts` are lists of conditions.
function M.cost_text(cost)
	local parts = {}
	if type(cost) ~= "table" then return "" end
	if type(cost[1]) == "string" then
		for _, s in ipairs(cost) do parts[#parts + 1] = condition_text(s) end
		return table.concat(parts, ", ")
	end
	local keys = {}
	for k in pairs(cost) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local tag = k:match("^sacrifice:(.+)$")
		parts[#parts + 1] = tag and ("sacrifice " .. tostring(cost[k]) .. " " .. tag)
			or (tostring(cost[k]) .. " " .. k)
	end
	return table.concat(parts, ", ")
end

-- Web assets ("asset": "https://...") are fetched at runtime and held only
-- in the in-memory cache above — the engine never writes them to its own
-- filesystem. Desktop decodes straight from the socket response. The
-- browser build (love.js) has no sockets, so instead it asks the real
-- browser to fetch the URL with its own fetch() — the caller's actual
-- session (HTTP cache, CORS) — via the love.js.eval bridge, and
-- polls for the result; a cross-origin host without permissive CORS
-- headers will still fail, same as it would for a plain <img> tag.

local function js_escape(s)
	s = tostring(s):gsub("\\", "\\\\")
	s = s:gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
	return s
end

local id_cache = {}

local function url_id(url)
	local cached = id_cache[url]
	if cached then return cached end
	local h = 5381
	for i = 1, #url do h = (h * 33 + url:byte(i)) % 4294967296 end
	cached = string.format("%08x", h)
	id_cache[url] = cached
	return cached
end

-- Build an Image directly from a byte string, no disk involved. Returns the
-- Image, or nil and what went wrong: the failures used to arrive as one silent
-- nil, and in the browser they mean very different things.
--
-- ByteData first, and love.filesystem only as a fallback: love.js's normalize
-- shim wraps love.filesystem.newFileData and answers nil where desktop LÖVE
-- answers a FileData, which is how a perfectly good 2 MB JPEG arrived intact
-- and became "no image" in the browser and nowhere else. love.data is not
-- wrapped, and newImage takes any Data.
local function image_from_bytes(bytes)
	local head = (bytes:sub(1, 4):gsub(".", function(c) return string.format("%02X ", c:byte()) end))
	local data, why
	if love.data and love.data.newByteData then
		local ok, d = pcall(love.data.newByteData, bytes)
		data, why = ok and d or nil, (not ok) and tostring(d) or "newByteData answered nil"
	end
	if not data then
		local ok, d = pcall(love.filesystem.newFileData, bytes, "asset")
		data = ok and d or nil
		why = (not ok) and tostring(d) or why or "newFileData answered nil"
	end
	if not data then return nil, "no Data could be made from the bytes: " .. tostring(why) end
	local ok2, img = pcall(love.graphics.newImage, data)
	if not ok2 then
		return nil, ("newImage refused it (%s), first bytes %s, lua heap %d KB")
			:format(tostring(img), head, collectgarbage("count"))
	end
	return img
end

-- Desktop: the request runs on a worker thread, because it used to run inside
-- love.draw — a card with a slow host froze the frame for as long as the
-- socket took (and LÖVE 12's https module takes no timeout at all). LÖVE
-- threads get their own Lua state, so the worker requires what it needs and
-- hands back raw bytes; only the main thread may build an Image.
local FETCH_SOURCE = [[
local url, channel = ...
require("love.thread")
local body
if url:match("^https://") then
	local ok, https = pcall(require, "https")   -- LÖVE 12 only
	if ok then
		local code, b = https.request(url)
		if code == 200 then body = b end
	end
else
	local ok, http = pcall(require, "socket.http")
	if ok then
		http.TIMEOUT = 10
		local b, code = http.request(url)
		if code == 200 then body = b end
	end
end
love.thread.getChannel(channel):push(body or false)
]]

-- Returns nil while the fetch is in flight (ask again next frame), an Image on
-- success, false on failure — the same contract the browser path uses, so
-- M.image treats both platforms identically.
local function fetch_desktop(url, id)
	local job = pending[id]
	if not job then
		if not (love.thread and love.thread.newThread) then return false end
		local ok, thread = pcall(love.thread.newThread, FETCH_SOURCE)
		if not ok then return false end
		job = { thread = thread, channel = "ravel_asset_" .. id }
		pending[id] = job
		pcall(thread.start, thread, url, job.channel)
		return nil
	end

	local result = love.thread.getChannel(job.channel):pop()
	if result == nil then
		-- A worker that died would otherwise leave the card pending forever.
		local err = job.thread.getError and job.thread:getError()
		if err then
			pending[id] = nil
			print("asset fetch failed: " .. url .. " (" .. tostring(err) .. ")")
			return false
		end
		return nil
	end

	pending[id] = nil
	if result == false then
		print("asset download failed: " .. url)
		return false
	end
	local img, why = image_from_bytes(result)
	if not img then
		print(("asset unusable: %s, %d bytes, %s"):format(url, #result, tostring(why)))
		return false
	end
	return img
end

-- Browser: kick off a real fetch() in the page (once per URL), then poll a
-- JS-side global for the result. love.js.eval's calling convention isn't
-- documented, so every call is pcall-guarded; if it doesn't behave as
-- expected this just never resolves — same safe "no image" as a missing
-- asset, never a crash. Returns nil while still waiting, else Image/false.
--
-- `credentials: "same-origin"` and not "include": cookies belong to our own
-- host, and asking for them cross-origin is not merely pointless but fatal.
-- The fetch spec refuses a credentialed response whose
-- Access-Control-Allow-Origin is the wildcard, and a wildcard is what every
-- public image host answers with — i.imgur.com included. Every off-site
-- asset the engine was ever pointed at died of that, as a bare "NetworkError"
-- with no hint that the request had been the wrong shape all along.
--
-- The browser decodes the picture before Lua sees it, and hands back either the
-- original bytes or a re-encode. It re-encodes for two reasons only:
--
--   too big     4092 on the long edge is the ceiling, because pixels are what
--               the heap pays for: 4092 square is 67 MB of RGBA, and the
--               browser build's heap does not grow (index.html puts a floor
--               under it — read the note there before raising this).
--   wrong kind  LÖVE reads what stb_image reads. The browser reads far more, so
--               anything else comes back as PNG or JPEG and a remote WebP or
--               AVIF simply works.
--
-- A JPEG or PNG that already fits crosses untouched, because re-encoding a
-- picture the author chose is a quality loss for nothing.
--
-- Fetching to a blob first is what keeps the canvas untainted — an <img>
-- pointed straight at another origin poisons toDataURL, which is the usual way
-- this trick fails.
local function fetch_browser(url, id, max)
	if not pending[id] then
		pending[id] = { at = 0 }
		local kickoff = string.format([[(function(){
			window.__ravelAssets = window.__ravelAssets || {};
			var id = "%s";
			if (window.__ravelAssets[id]) return "dup";
			window.__ravelAssets[id] = { status: "pending" };
			var MAX = %d;
			var asIs = function(blob){
				return new Promise(function(res, rej){
					var fr = new FileReader();
					fr.onload = function(){ res(fr.result); };
					fr.onerror = function(){ rej(fr.error); };
					fr.readAsDataURL(blob);
				});
			};
			var shrink = function(src, type){
				var s = Math.min(1, MAX / Math.max(src.width, src.height));
				var c = document.createElement("canvas");
				c.width = Math.max(1, Math.round(src.width * s));
				c.height = Math.max(1, Math.round(src.height * s));
				c.getContext("2d").drawImage(src, 0, 0, c.width, c.height);
				return c.toDataURL(type === "image/jpeg" ? "image/jpeg" : "image/png", 0.85);
			};
			var native = function(t){ return t === "image/jpeg" || t === "image/png"; };
			var handle = function(bm, blob){
				if (native(blob.type) && Math.max(bm.width, bm.height) <= MAX) return asIs(blob);
				return shrink(bm, blob.type);
			};
			var decode = function(blob){
				if (window.createImageBitmap) {
					return createImageBitmap(blob).then(function(bm){ return handle(bm, blob); });
				}
				return new Promise(function(res, rej){
					var u = URL.createObjectURL(blob), im = new Image();
					im.onload = function(){
						var d = handle(im, blob);
						URL.revokeObjectURL(u);
						res(d);
					};
					im.onerror = function(){ URL.revokeObjectURL(u); rej(new Error("the browser could not decode it")); };
					im.src = u;
				});
			};
			fetch("%s", { credentials: "same-origin" })
				.then(function(r){ if (!r.ok) throw new Error("http " + r.status); return r.blob(); })
				.then(decode)
				.then(function(durl){ window.__ravelAssets[id] = { status: "ok", data: durl }; })
				.catch(function(e){ window.__ravelAssets[id] = { status: "error", message: String(e && e.message || e) }; });
			return "started";
		})()]], id, max, js_escape(url))
		pcall(love.js.eval, kickoff)
	end

	local now = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
	if now - pending[id].at < 0.2 then return nil end   -- throttle polling
	pending[id].at = now

	local poll = string.format([[(function(){
		var a = (window.__ravelAssets || {})["%s"];
		if (!a) return "";
		if (a.status === "ok") return a.data;
		if (a.status === "error") return "ERROR:" + a.message;
		return "";
	})()]], id)
	local ok, result = pcall(love.js.eval, poll)
	if not ok or type(result) ~= "string" or result == "" then return nil end

	pending[id] = nil
	if result:sub(1, 6) == "ERROR:" then
		print("asset download failed: " .. url .. " (" .. result:sub(7) .. ")")
		return false
	end
	-- Everything below this line used to fail by returning nil or false without
	-- a word, so a picture that never appeared looked exactly like a picture
	-- still on its way. The bytes have crossed by now; say what became of them.
	print(("asset arrived: %s (%d bytes across the bridge)"):format(url, #result))
	local b64 = result:match("^data:[^,]*,(.*)$")
	if not b64 then
		print("asset unusable: not a data URL, starts " .. string.format("%q", result:sub(1, 40)))
		return false
	end
	if not (love.data and love.data.decode) then
		print("asset unusable: this build has no love.data.decode")
		return false
	end
	local ok2, bytes = pcall(love.data.decode, "string", "base64", b64)
	if not ok2 then
		print("asset unusable: base64 would not decode (" .. tostring(bytes) .. ")")
		return false
	end
	local img, why = image_from_bytes(bytes)
	if not img then
		print(("asset unusable: %d bytes decoded, %s"):format(#bytes, tostring(why)))
		return false
	end
	return img
end

-- Load (and cache) the asset image for a card def, returns nil if missing
-- (or, for a browser URL asset, not yet fetched — ask again next frame).
-- Load an asset spec — a bare filename in games/assets, an http(s) URL, or a
-- shape the art module draws — and cache it under `key`.
--
-- Split out of M.image because none of this ever cared which *card* asked: a
-- zone wants a picture on its board by the same rules, with the same allowlist
-- and the same refusals. Callers own the cache key, so a zone named like a card
-- cannot collide with it.
-- A name with no source in it — no extension, no scheme, no shape colon — is a
-- key into the game's `assets` table, which is the only place that carries
-- options. Resolving here rather than at every call site also makes the name
-- the cache key, so twenty cards drawn from one picture cost one download and
-- one texture.
local DEFAULT_MAX = 1024

-- A picture that cannot be produced draws a generated one, never nothing.
--
-- The reasons a picture goes missing are mostly not the author's: a remote host
-- is down or refuses the fetch, or — the common one — somebody is playing a game
-- file that arrived over the network, which carries the JSON and not the art
-- sitting in the sender's assets folder. A card with no image at all reads as a
-- bug in the game; a shape derived from its key reads as a card.
--
-- The **key** is hashed, not the text, because the key is the card's identity
-- and the text is presentation: renaming a card's title should not give it a
-- different picture, and a saved game should not change under a copy-edit.
--
-- Said once per key rather than per frame, which img_cache gives for free — the
-- caller is a draw path and would otherwise print sixty times a second.
local function placeholder(key, why)
	print(("no picture for '%s' (%s) — drawing a generated one"):format(tostring(key), why))
	-- A placeholder is a drawing, and drawing needs a canvas. The headless shim
	-- has no graphics layer and nothing to show it to, so there answering nil is
	-- the honest result rather than an error on a path that only ever runs
	-- because something else already went wrong.
	local ok, img = pcall(art.render, art.auto(tostring(key)))
	return ok and img or nil
end

-- Which seat a card belongs to, as an index. Its own `owner` first — that is
-- placement state and beats everything — then the seat of the zone it lies in,
-- so a per-seat hand works without every card being stamped.
local function seat_of(e)
	if type(e) ~= "table" then return nil end
	if e.stats and e.stats.owner then return e.stats.owner end
	local seat = require("tags").owner_of(e)
	return seat and declaration.G.seat_index and declaration.G.seat_index[seat] or nil
end

function M.asset_image(asset, key, e)
	local named = asset and declaration.G.asset_defs and declaration.G.asset_defs[asset]
	local max = DEFAULT_MAX
	if named then
		local src = named.src
		-- One name, one picture per seat. A rook is a rook — whose it is decides
		-- only which sprite is drawn — and that is what lets six cards stand for
		-- thirty-two pieces. The seat index is part of the cache key, or the
		-- second player is handed the first one's rook.
		if type(src) == "table" then
			local i = seat_of(e) or 1
			key, src = "asset:" .. asset .. "#" .. i, src[i] or src[1]
		else
			key = "asset:" .. asset
		end
		asset, max = src, named.max or DEFAULT_MAX
	end
	if img_cache[key] ~= nil then return img_cache[key] or nil end
	if not asset then img_cache[key] = false; return nil end
	local def_key = key
	if tostring(asset):match("^https?://") then
		if not M.url_is_safe(asset) then
			img_cache[def_key] = placeholder(key, "that URL has characters no URL may contain") or false
			return img_cache[def_key] or nil
		end
		-- A real branch, not `cond and browser(...) or desktop(...)`: both of the
		-- browser fetch's unfinished answers are falsy — nil while in flight,
		-- false on failure — so `or` ran the desktop path too, which found the
		-- browser's job in `pending` and asked for its nonexistent thread
		-- channel. Every web asset in the browser build crashed on the first
		-- frame it was drawn.
		-- The size is part of the identity: the same URL asked for at two sizes
		-- is two different pictures, and one id would hand the second asker the
		-- first one's answer.
		local id = url_id(asset .. "|" .. max)
		local img
		if love.js and love.js.eval then img = fetch_browser(asset, id, max)
		else img = fetch_desktop(asset, id) end
		if img == nil then return nil end   -- still fetching
		if img == false then img = placeholder(key, "the fetch failed") or false end
		img_cache[def_key] = img
		return img or nil
	end
	-- A local asset is untrusted content too: require a bare filename (no
	-- path separators or "..") so it can only ever name a file directly in
	-- games/assets, never traverse elsewhere. Filenames carry an extension and
	-- shape specs never do, so the two can't be confused.
	if not tostring(asset):match("^[%w_%-]+%.[%w]+$") then
		local drawn = art.render(asset)
		if drawn then img_cache[def_key] = drawn; return drawn end
		local why = (art.parse(asset) == nil and asset:find(":"))
			and ("'" .. tostring(asset) .. "' is not a shape the engine knows")
			or ("'" .. tostring(asset) .. "' is neither a plain filename nor a shape")
		img_cache[def_key] = placeholder(key, why) or false
		return img_cache[def_key] or nil
	end
	local ok, i = pcall(love.graphics.newImage, "games/assets/" .. asset)
	if not ok then i = placeholder(key, "'" .. tostring(asset) .. "' is not in games/assets") end
	img_cache[def_key] = i or false
	return img_cache[def_key] or nil
end

-- Takes the card entity, because a picture can depend on whose card it is.
-- A bare key still works and means "the template's own picture".
function M.image(e)
	local def_key = type(e) == "table" and e.def_key or e
	local def   = declaration.G.card_defs[def_key]
	local asset = def and def.asset
	-- `generate_art` is a card asking for a shape derived from its key, which is
	-- what a card with nothing to show should look like rather than a bare
	-- colour. A tag and not a field, because a thing a card either does or does
	-- not do is exactly what a tag is: the boolean field this replaced could
	-- only ever be set for a whole game at once, so a file could not have six
	-- generated cards among thirty-five photographs.
	if not asset and def and def.tags_set and def.tags_set.generate_art then asset = "auto" end
	if asset == "auto" then asset = art.auto(def_key) end
	return M.asset_image(asset, def_key, type(e) == "table" and e or nil)
end

return M
