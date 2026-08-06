local entity      = require("entity")
local declaration = require("declaration")
local json        = require("json")

local M = {}

-- Image cache: def_key → love.graphics.Image or false
local img_cache = {}
-- Web-asset fetches in flight: url id -> { at = last poll time } (browser only)
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

-- "2 gold, 1 food" for a cost table, stat keys sorted for stable display.
function M.cost_text(cost)
	local keys = {}
	for k in pairs(cost or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local tag = k:match("^sacrifice:(.+)$")
		parts[#parts + 1] = tag and ("sacrifice " .. cost[k] .. " " .. tag)
			or (cost[k] .. " " .. k)
	end
	return table.concat(parts, ", ")
end

-- Web assets ("asset": "https://...") are fetched at runtime and held only
-- in the in-memory cache above — the engine never writes them to its own
-- filesystem. Desktop decodes straight from the socket response. The
-- browser build (love.js) has no sockets, so instead it asks the real
-- browser to fetch the URL with its own fetch() — the caller's actual
-- session (cookies, HTTP cache, CORS) — via the love.js.eval bridge, and
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

-- Build an Image directly from a byte string, no disk involved.
local function image_from_bytes(bytes)
	local ok, fd = pcall(love.filesystem.newFileData, bytes, "asset")
	if not ok then return nil end
	local ok2, img = pcall(love.graphics.newImage, fd)
	return ok2 and img or nil
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
	return image_from_bytes(result) or false
end

-- Browser: kick off a real fetch() in the page (once per URL), then poll a
-- JS-side global for the result. love.js.eval's calling convention isn't
-- documented, so every call is pcall-guarded; if it doesn't behave as
-- expected this just never resolves — same safe "no image" as a missing
-- asset, never a crash. Returns nil while still waiting, else Image/false.
local function fetch_browser(url, id)
	if not pending[id] then
		pending[id] = { at = 0 }
		local kickoff = string.format([[(function(){
			window.__ravelAssets = window.__ravelAssets || {};
			var id = "%s";
			if (window.__ravelAssets[id]) return "dup";
			window.__ravelAssets[id] = { status: "pending" };
			fetch("%s", { credentials: "include" })
				.then(function(r){ if (!r.ok) throw new Error("http " + r.status); return r.blob(); })
				.then(function(blob){ return new Promise(function(res, rej){
					var fr = new FileReader();
					fr.onload = function(){ res(fr.result); };
					fr.onerror = function(){ rej(fr.error); };
					fr.readAsDataURL(blob);
				}); })
				.then(function(durl){ window.__ravelAssets[id] = { status: "ok", data: durl }; })
				.catch(function(e){ window.__ravelAssets[id] = { status: "error", message: String(e && e.message || e) }; });
			return "started";
		})()]], id, js_escape(url))
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
	local b64 = result:match("^data:[^,]*,(.*)$")
	if not (b64 and love.data and love.data.decode) then return false end
	local ok2, bytes = pcall(love.data.decode, "string", "base64", b64)
	if not ok2 then return false end
	return image_from_bytes(bytes) or false
end

-- Load (and cache) the asset image for a card def, returns nil if missing
-- (or, for a browser URL asset, not yet fetched — ask again next frame).
function M.image(def_key)
	if img_cache[def_key] ~= nil then return img_cache[def_key] or nil end
	local def = declaration.G.card_defs[def_key]
	local asset = def and def.asset
	if not asset then img_cache[def_key] = false; return nil end
	if tostring(asset):match("^https?://") then
		if not M.url_is_safe(asset) then
			print("asset URL refused (contains characters not valid in a URL): " .. tostring(asset))
			img_cache[def_key] = false
			return nil
		end
		local img = (love.js and love.js.eval)
			and fetch_browser(asset, url_id(asset))
			or fetch_desktop(asset, url_id(asset))
		if img == nil then return nil end   -- still fetching
		img_cache[def_key] = img
		return img or nil
	end
	-- A local asset is untrusted content too: require a bare filename (no
	-- path separators or "..") so it can only ever name a file directly in
	-- games/assets, never traverse elsewhere.
	if not tostring(asset):match("^[%w_%-]+%.[%w]+$") then
		print("asset refused (must be a plain filename): " .. tostring(asset))
		img_cache[def_key] = false
		return nil
	end
	local ok, i = pcall(love.graphics.newImage, "games/assets/" .. asset)
	img_cache[def_key] = ok and i or false
	return img_cache[def_key] or nil
end

return M
