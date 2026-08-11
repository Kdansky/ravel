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

function M.create(def_key, zone_id)
	local def = declaration.G.card_defs[def_key]
	assert(def, "Unknown card def: " .. tostring(def_key))
	local e = {
		kind      = "card",
		def_key   = def_key,
		zone_id   = zone_id,
		place     = { x = 0, y = 0, w = 0, h = 0 },
		stats     = {},    -- per-entity stats (e.g. hp, hp_max for buildings)
		parent_id = nil,   -- set when attached to another card
		attached  = {},    -- IDs of cards attached to this card
	}
	if def.card_stats then
		-- card_stats is untrusted content: coerce every value to a real
		-- number here so nothing downstream (gain_stat, comparisons...)
		-- can be tricked into doing arithmetic on a string/table and crash.
		for k, v in pairs(def.card_stats) do e.stats[k] = tonumber(v) or 0 end
	end
	entity.register(e)
	local zone = entity.get(zone_id)
	if zone then table.insert(zone.cards, e.id) end
	return e
end

function M.def(card_entity)
	return declaration.G.card_defs[card_entity.def_key]
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
			e.stats = {}
			for k, v in pairs(card_stats or {}) do e.stats[k] = tonumber(v) or 0 end
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

-- How much of something a requirement asks for. A bare number means "at least
-- this many" and reads as itself; the comparison form the condition vocabulary
-- allows ({ "at_most": 6 }) has to be spelled out instead. This function renders
-- `needs` and `accepts` as well as `cost`, and only costs are always numbers —
-- concatenating the map form is what took the interface down when the first
-- card carrying one was hovered.
local function amount_text(v)
	if type(v) ~= "table" then return tostring(v), "" end
	if v.equals   ~= nil then return tostring(v.equals),   "exactly " end
	if v.at_least ~= nil then return tostring(v.at_least), "at least " end
	if v.at_most  ~= nil then return tostring(v.at_most),  "at most " end
	return "?", ""
end

-- "2 gold, 1 food" for a cost table, stat keys sorted for stable display.
function M.cost_text(cost)
	local keys = {}
	for k in pairs(cost or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local n, qualifier = amount_text(cost[k])
		local tag = k:match("^sacrifice:(.+)$")
		parts[#parts + 1] = tag and ("sacrifice " .. n .. " " .. tag)
			or (qualifier .. n .. " " .. k)
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

function M.asset_image(asset, key)
	local named = asset and declaration.G.asset_defs and declaration.G.asset_defs[asset]
	local max = DEFAULT_MAX
	if named then
		key, asset, max = "asset:" .. asset, named.src, named.max or DEFAULT_MAX
	end
	if img_cache[key] ~= nil then return img_cache[key] or nil end
	if not asset then img_cache[key] = false; return nil end
	local def_key = key
	if tostring(asset):match("^https?://") then
		if not M.url_is_safe(asset) then
			print("asset URL refused (contains characters not valid in a URL): " .. tostring(asset))
			img_cache[def_key] = false
			return nil
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
		if art.parse(asset) == nil and asset:find(":") then
			print("asset refused (not a shape the engine knows): " .. tostring(asset))
		elseif not asset:find(":") then
			print("asset refused (must be a plain filename or a shape): " .. tostring(asset))
		end
		img_cache[def_key] = false
		return nil
	end
	local ok, i = pcall(love.graphics.newImage, "games/assets/" .. asset)
	img_cache[def_key] = ok and i or false
	return img_cache[def_key] or nil
end

function M.image(def_key)
	local def   = declaration.G.card_defs[def_key]
	local asset = def and def.asset
	-- A game may opt every card without art into a generated placeholder, so a
	-- brand-new file has visual differentiation from its first save.
	if not asset and declaration.G.placeholder_art then asset = "auto" end
	if asset == "auto" then asset = art.auto(def_key) end
	return M.asset_image(asset, def_key)
end

return M
