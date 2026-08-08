-- Transports for net.lua: the ways a wire string can reach the other player.
-- Every one of them is a table with send/recv, and net.lua knows nothing else
-- about any of them. Nothing in the engine requires this file.
--
-- What exists, cheapest first:
--   loopback   two ends in one process (tests)
--   folder     a file per side in a shared directory — two terminals on one
--              machine, or any folder that syncs itself between two machines
--   browser    BroadcastChannel between two tabs of the same page, no server
--
-- The copy/paste path needs nothing here: net.export/net.import are the whole
-- of it, and a chat window is the transport.

local M = {}

---------------------------------------------------------------- loopback

-- Two ends of one wire, in one process. Mostly for tests, but also the honest
-- way to demonstrate that the protocol has no idea where messages come from.
function M.loopback()
	local a, b = {}, {}
	local function make(name, mine, theirs)
		return {
			name = name,
			send = function(text) theirs[#theirs + 1] = text end,
			recv = function() return table.remove(mine, 1) end,
			status = function() return #mine .. " waiting" end,
		}
	end
	return make("loopback:a", a, b), make("loopback:b", b, a)
end

---------------------------------------------------------------- folder

-- One file per side, last write wins. That is exactly the right shape for a
-- protocol that ships whole states and deltas keyed to a fingerprint: there is
-- no queue to preserve, only "the newest thing my opponent said". Point both
-- players at a synced folder (Syncthing, Dropbox, a mounted share) and it is a
-- cross-machine transport with no server and no code.
function M.folder(dir, me, them)
	dir = (dir or "."):gsub("/$", "")
	local mine, seen = dir .. "/" .. (them or "b") .. ".ravel", nil
	local out = dir .. "/" .. (me or "a") .. ".ravel"
	return {
		name = "folder:" .. (me or "a"),
		send = function(text)
			local f = io.open(out, "w")
			if not f then return end
			f:write(text)
			f:close()
		end,
		recv = function()
			local f = io.open(mine, "r")
			if not f then return nil end
			local text = f:read("*a")
			f:close()
			if text == seen or text == "" then return nil end
			seen = text
			return text
		end,
		status = function() return "watching " .. mine end,
	}
end

---------------------------------------------------------------- browser

-- Getting data out of a browser tab turned out to be possible without touching
-- the love.js build, and not by the route cards.lua guesses at: there is no
-- love.js.eval in the 2dengine runtime this project serves. What there is:
--
--   * player.js overrides window.open, so love.system.openURL("javascript:…")
--     runs the code and parks its result in window._output;
--   * player.js also overrides window.prompt to hand back window._output, and
--     emscripten's stdin is implemented by calling window.prompt — so io.read
--     returns whatever the last snippet evaluated to.
--
-- That is a synchronous, repeatable, two-way bridge, and it is the documented
-- 2dengine interop path rather than a trick. Both halves are verified in
-- tests/net.lua's notes; here they are just used.
--
-- One measured constraint shapes everything below. Emscripten's tty hands stdin
-- back one byte at a time via Array.shift(), which is quadratic in the length of
-- a single reply: 40 KB arrives in 41 ms as one string and in 2.2 ms as 8 KB
-- chunks. So outbound is one call and inbound is always chunked.

local CHUNK = 8192

local function js_string(s)
	return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"')
		:gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
end

-- Evaluate a snippet and return its result as a Lua string. The snippet must
-- always yield a string: a null reply reaches Lua as end-of-file, and a closed
-- stdin never reopens.
local function eval(code)
	if not (love and love.system and love.system.openURL) then return nil end
	local ok = pcall(love.system.openURL, "javascript:" .. code)
	if not ok then return nil end
	local ok2, line = pcall(io.read, "*l")
	if not ok2 then return nil end
	return line
end

local function guarded(body)
	return '(function(){try{' .. body .. '}catch(e){return "!"+String(e&&e.message||e)}})()'
end

-- Stage a value JS-side, then pull it across in fixed-size pieces.
local function eval_long(body)
	local head = eval(guarded('window.__ravel_q=String(' .. body .. ');return "#"+window.__ravel_q.length'))
	if not head then return nil end
	if head:sub(1, 1) == "!" then return nil, head:sub(2) end
	local total = tonumber(head:match("^#(%d+)"))
	if not total then return nil, "bridge returned " .. head end
	if total == 0 then return "" end
	local parts, got = {}, 0
	while got < total do
		local piece = eval(guarded(
			("return window.__ravel_q.substr(%d,%d)"):format(got, CHUNK)))
		if not piece or piece == "" or piece:sub(1, 1) == "!" then break end
		parts[#parts + 1] = piece
		got = got + #piece
	end
	return table.concat(parts)
end

-- True when this process can reach the page at all. Costs one round trip and is
-- the only thing that should ever be used to decide whether to offer networking:
-- the desktop build has openURL too, and there it opens a web browser.
-- The platform check comes first and is not optional. On a desktop LÖVE,
-- openURL launches a real web browser and io.read blocks on a real stdin — so
-- probing for the bridge by trying it would hang the game and open a window.
-- Only the emscripten build reports "Web".
function M.browser_available()
	if not (love and love.system and love.system.getOS and love.system.openURL) then return false end
	if love.system.getOS() ~= "Web" then return false end
	return eval(guarded('return "ravel-bridge"')) == "ravel-bridge"
end

-- Two tabs of the same page, no server and no signalling: BroadcastChannel is
-- same-origin by definition, which is exactly the scope of "two browser tabs".
-- It does not deliver a message back to its sender, so the only echo protection
-- needed is net's own client id, and that is belt-and-braces.
function M.browser(room)
	room = tostring(room or "ravel")
	local started = eval(guarded([[
		var W = window;
		W.__ravel = W.__ravel || {};
		var N = W.__ravel;
		if (N.ch && N.room === ]] .. js_string(room) .. [[) return "again";
		if (N.ch) { try { N.ch.close(); } catch (e) {} }
		N.room = ]] .. js_string(room) .. [[;
		N.inbox = [];
		N.ch = new BroadcastChannel("ravel:" + N.room);
		N.ch.onmessage = function (ev) {
			if (typeof ev.data === "string") N.inbox.push(ev.data);
		};
		return "ok";
	]]))
	if started ~= "ok" and started ~= "again" then
		return nil, "no browser bridge (" .. tostring(started) .. ")"
	end

	return {
		name = "browser:" .. room,
		send = function(text)
			-- Outbound is one call: the payload rides in the snippet's source,
			-- and only the reply pays the tty's per-byte cost.
			eval(guarded('window.__ravel.ch.postMessage(' .. js_string(text) .. ');return "ok"'))
		end,
		recv = function()
			local n = eval(guarded('return String((window.__ravel.inbox||[]).length)'))
			if not n or (tonumber(n) or 0) == 0 then return nil end
			return (eval_long('window.__ravel.inbox.shift()'))
		end,
		status = function()
			local n = eval(guarded('return String((window.__ravel.inbox||[]).length)'))
			return "room " .. room .. ", " .. tostring(n or "?") .. " waiting"
		end,
		close = function()
			eval(guarded('if(window.__ravel&&window.__ravel.ch)window.__ravel.ch.close();'
				.. 'window.__ravel={};return "ok"'))
		end,
	}
end

-- Exposed because the control panel needs the same door, and because a person
-- debugging this at 1am will want to poke the page by hand.
M.eval      = eval
M.eval_long = eval_long
M.guarded   = guarded
M.js_string = js_string

return M
