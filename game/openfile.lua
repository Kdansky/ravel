-- A game file the player has, rather than one that shipped. The engine already
-- knows how to run a game it was handed as *text* — that is how a networked
-- invite carries its own rules across to somebody who has never seen the file —
-- so all that is missing is the part LÖVE cannot do: asking the machine for one.
--
-- Two surfaces, because there are two builds. In the browser it is an
-- <input type=file>, clicked from inside the click that asked for it: a picker
-- opened a frame later is no longer a user gesture and the browser refuses it,
-- which is why this cannot go through netpanel's command queue like everything
-- else there does. Everywhere else it is drag and drop, routed here by main.
--
-- Nothing in the engine requires this file, and without it `open_game` is a
-- silent no-op.

local actions     = require("actions")
local declaration = require("declaration")
local flow        = require("flow")
local netlink     = require("netlink")
local log         = require("log")

local M = {}

-- The picker is open and its answer has not come back yet. A cancelled picker
-- never answers at all, so the wait has an end.
local waiting = nil
local WAIT_LIMIT = 180

-- The name is an identity, not a path: what runs is the text we were handed.
-- It still has to survive being used as one — the file watcher builds a path out
-- of it and the net layer hashes games by name — so anything else becomes an
-- underscore, and the same file opened twice is the same game both times.
local function safe_name(name)
	local stem = tostring(name or ""):match("([^/\\]+)$") or ""
	stem = stem:gsub("%.[jJ][sS][oO][nN]$", ""):gsub("[^%w_%-]", "_"):sub(1, 40)
	if stem == "" then stem = "opened" end
	return stem .. ".json"
end

local PICKER = [[
	var W = window;
	W.__ravel = W.__ravel || {};
	var i = document.getElementById("ravel-open");
	if (!i) {
		i = document.createElement("input");
		i.type = "file";
		i.id = "ravel-open";
		i.accept = ".json,application/json";
		i.style.display = "none";
		document.body.appendChild(i);
		i.onchange = function () {
			var f = i.files && i.files[0];
			i.value = "";
			if (!f) { W.__ravel.opened = ""; return; }
			var r = new FileReader();
			r.onload = function () {
				W.__ravel.opened_name = encodeURIComponent(f.name);
				W.__ravel.opened = encodeURIComponent(String(r.result).replace(/^\uFEFF/, ""));
			};
			r.onerror = function () { W.__ravel.opened = ""; };
			r.readAsText(f);
		};
	}
	W.__ravel.opened = null;
	i.click();
	return "ok";
]]

-- **Percent-encoded, and that is not a nicety.** Everything else that has ever
-- crossed this bridge was base64, so two things about it were never discovered:
-- a reply comes back through stdin one *line* at a time, so a value with a
-- newline in it arrives cut off at the first one; and the chunking counts Lua
-- bytes against a JavaScript length, which are the same number only while the
-- text is ASCII — one em-dash in one tooltip and the pieces stop lining up.
-- encodeURIComponent answers both at once: what comes back is ASCII with no
-- newlines in it, and the length the page reported is the length Lua receives.
-- The byte order mark goes for a duller reason — a parser reads it as a stray
-- character sitting before the first brace.
function M.decoded(s)
	if not s then return nil end
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- "" while the player is still choosing, "0" if they gave up or the read failed,
-- "#n" once there is something to fetch.
local READY = [[
	var o = (window.__ravel || {}).opened;
	if (o === null || o === undefined) return "";
	return o === "" ? "0" : "#" + o.length;
]]

-- Hand the engine a game it has never seen. A file from a stranger is exactly as
-- untrusted as one arriving over the wire, and takes the same door: a failure
-- anywhere in it must not strand the player in a half-wiped world, so it falls
-- back to the menu as load_game's does.
function M.take(name, text)
	if type(text) ~= "string" or text == "" then
		log.add("! that file was empty")
		return false
	end
	local file = safe_name(name)
	declaration.provide(file, text)
	local ok, err = pcall(flow.init, file)
	if not ok then
		print("open_game failed for '" .. file .. "': " .. tostring(err))
		pcall(flow.init, "menu.json")
		log.add("! " .. file .. " would not load: " .. tostring(err))
		return false
	end
	log.add("opened " .. file)
	return true
end

actions.on_open = function()
	if not netlink.browser_available() then
		log.add("drag a .json onto the window to open it")
		return
	end
	waiting = (netlink.eval(netlink.guarded(PICKER)) == "ok") and 0 or nil
	if not waiting then log.add("! this browser would not open a file picker") end
end

-- Polled beside the networking, and only while a picker is open: a file arrives
-- asynchronously, and there is nothing to ask about the rest of the time.
function M.update(dt)
	if not waiting then return end
	waiting = waiting + (dt or 0)
	if waiting > WAIT_LIMIT then waiting = nil; return end
	local r = netlink.eval(netlink.guarded(READY))
	if not r or r == "" then return end
	waiting = nil
	if r == "0" then
		return
	end
	local name = netlink.eval(netlink.guarded('return String((window.__ravel||{}).opened_name||"")'))
	local text = netlink.eval_long('(window.__ravel.opened||"")')
	netlink.eval(netlink.guarded('window.__ravel.opened=null;return "ok"'))
	-- The page said how long it was before the fetch began, and the encoding
	-- makes that a byte count Lua can hold it to. A short answer is the bridge
	-- dropping some of it, and calling that an empty file would send somebody to
	-- look at their own work for a fault that is ours.
	local want = tonumber(r:match("^#(%d+)") or "")
	if want and #(text or "") < want then
		log.add("! only " .. #(text or "") .. " of " .. want .. " characters came back")
		return
	end
	M.take(M.decoded(name), M.decoded(text))
end

return M
