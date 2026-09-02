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

-- One file per side, appended to, one message per line. Point both players at a
-- folder that syncs itself (Syncthing, a mounted share) and it is a
-- cross-machine transport with no server and no code.
--
-- It began as last-write-wins on a single file, which was fine while every
-- message was a state or a delta — a newer one simply supersedes an older one.
-- It stopped being fine the moment messages started meaning different things:
-- a "hello" overwrote a "send me the game you are playing", and both sides then
-- waited politely forever. A transport may not lose messages, whatever the
-- protocol above it happens to tolerate today.
--
-- Newline-delimited is safe because a message never contains one: the header is
-- bare text and the payload is base64.
function M.folder(dir, me, them)
	dir = (dir or "."):gsub("/$", "")
	local inbox = dir .. "/" .. (them or "b") .. ".ravel"
	local out   = dir .. "/" .. (me or "a") .. ".ravel"
	local taken = 0   -- lines of theirs already handed upward

	return {
		name = "folder:" .. (me or "a"),
		send = function(text)
			local f = io.open(out, "a")
			if not f then return end
			f:write(text, "\n")
			f:close()
		end,
		recv = function()
			local f = io.open(inbox, "r")
			if not f then return nil end
			local n, line = 0, nil
			for l in f:lines() do
				n = n + 1
				if n > taken then line = l; break end
			end
			f:close()
			if not line then return nil end
			taken = taken + 1
			return line
		end,
		status = function() return "watching " .. inbox .. ", " .. taken .. " read" end,
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

-- Every eval is a fresh parse: the browser cannot cache a string it has not
-- seen before, so a 200-character snippet evaluated sixty times a second is
-- sixty compiles a second. The hot paths — "is anything waiting", "give me the
-- next command" — are installed once as named functions and then called with a
-- few characters. They do their own try/catch and always return a string, which
-- is the contract eval depends on (a null reply closes stdin for good).
local HELPERS = [==[
	var W = window;
	W.__rvn = function () {   // how much is waiting, both transports
		try {
			var a = ((W.__ravel || {}).inbox || []).length;
			var b = ((W.__ravelRTC || {}).inbox || []).length;
			return String(a + b);
		} catch (e) { return "0" }
	};
	W.__rvc = function () {   // the next panel command, or ""
		try {
			var c = (W.__ravel || {}).cmds;
			return (c && c.length) ? String(c.shift()) : "";
		} catch (e) { return "" }
	};
	W.__rvs = function () {   // the peer-to-peer channel's state
		try {
			var R = W.__ravelRTC || {};
			return (R.pc ? R.pc.connectionState : "none") + "/" + (R.ch ? R.ch.readyState : "no channel");
		} catch (e) { return "?" }
	};
	return "ok";
]==]

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
--
-- **The value must be single-line ASCII**, which base64 is and which is why
-- nothing met this until something else was sent: a piece comes back through
-- io.read("*l") and stops at a newline, and the offset counts Lua bytes against
-- a JavaScript length, which agree only below U+0080. A caller with anything
-- else to send encodes it — openfile percent-encodes a game file for exactly
-- this reason.
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
-- Calling one of the installed helpers above. Short enough that the parse is
-- free, which is the whole point of installing them.
local function call(name)
	return eval(name .. "()")
end

local helpers_up = false

local function install_helpers()
	if helpers_up then return true end
	helpers_up = eval(guarded(HELPERS)) == "ok"
	return helpers_up
end

-- The platform check comes first and is not optional. On a desktop LÖVE,
-- openURL launches a real web browser and io.read blocks on a real stdin — so
-- probing for the bridge by trying it would hang the game and open a window.
-- Only the emscripten build reports "Web".
function M.browser_available()
	if not (love and love.system and love.system.getOS and love.system.openURL) then return false end
	if love.system.getOS() ~= "Web" then return false end
	if eval(guarded('return "ravel-bridge"')) ~= "ravel-bridge" then return false end
	return install_helpers()
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
			if (tonumber(call("__rvn")) or 0) == 0 then return nil end
			return (eval_long('window.__ravel.inbox.shift()'))
		end,
		status = function()
			return "room " .. room .. ", " .. tostring(call("__rvn") or "?") .. " waiting"
		end,
		close = function()
			eval(guarded('if(window.__ravel&&window.__ravel.ch)window.__ravel.ch.close();'
				.. 'window.__ravel={};return "ok"'))
		end,
	}
end

---------------------------------------------------------------- webrtc

-- Two computers, over the internet, with nothing in the middle — and with the
-- signalling done by the copy/paste channel that already exists. That is the
-- whole trick: WebRTC's reputation for needing a server is really a reputation
-- for needing *signalling*, and a chat window is signalling.
--
-- One blob each way, 956 characters measured, so each fits in a single Discord
-- message. After the second blob lands the data channel is open and nothing
-- else is ever pasted: it is a live peer-to-peer link.
--
-- Two honest caveats:
--
--   * ICE needs to learn each side's public address, which is what a STUN
--     server is for. It carries no game data and sees only an IP and a port,
--     but it is a third party, so it is a list you can change or empty. Empty
--     works on a LAN.
--   * Symmetric NAT — common on mobile networks and some ISPs — defeats
--     hole-punching, and the usual answer is a TURN relay, which is exactly the
--     server this project declined. There is no fix here, only a fallback: the
--     copy/paste transport, which never fails.
--
-- No port forwarding is needed. That is what ICE is for.

M.stun = {
	"stun:stun.l.google.com:19302",
	"stun:stun.cloudflare.com:3478",
}

local function ice_json()
	local urls = {}
	for _, s in ipairs(M.stun) do urls[#urls + 1] = js_string(s) end
	return "[{urls:[" .. table.concat(urls, ",") .. "]}]"
end

-- role "host" builds the offer; "guest" answers one. Returns at once — ICE
-- gathering takes a second or two, so the blob is collected by rtc_blob below.
function M.rtc_start(role, remote)
	local code = ([[
		var W = window, R = W.__ravelRTC = W.__ravelRTC || {};
		if (R.pc) { try { R.pc.close(); } catch (e) {} }
		R.inbox = []; R.sdp = null; R.err = null; R.role = %s;
		var pc = new RTCPeerConnection({ iceServers: %s });
		R.pc = pc;
		// Outbound is queued until the channel opens. setRemoteDescription
		// returns long before ICE has finished, so the host's opening state —
		// the one that makes both sides agree in the first place — was being
		// handed to a channel in state "connecting" and dropped on the floor.
		// The two players then sat there looking connected and disagreeing.
		R.out = [];
		var flush = function () {
			while (R.ch && R.ch.readyState === "open" && R.out.length) {
				R.ch.send(R.out.shift());
			}
		};
		R.flush = flush;
		var wire = function (ch) {
			R.ch = ch;
			ch.onmessage = function (e) { if (typeof e.data === "string") R.inbox.push(e.data); };
			ch.onopen = flush;
			if (ch.readyState === "open") flush();   // guest may be handed one already open
		};
		if (R.role === "host") wire(pc.createDataChannel("ravel"));
		else pc.ondatachannel = function (e) { wire(e.channel); };

		// Non-trickle: one blob has to contain everything, because the person
		// carrying it is going to paste it exactly once. Whatever candidates
		// exist after five seconds beat waiting forever for a straggler.
		var gathered = function () {
			return new Promise(function (res) {
				if (pc.iceGatheringState === "complete") return res();
				var done = false, fin = function () { if (!done) { done = true; res(); } };
				pc.onicegatheringstatechange = function () {
					if (pc.iceGatheringState === "complete") fin();
				};
				setTimeout(fin, 5000);
			});
		};

		var go = R.role === "host"
			? pc.createOffer().then(function (o) { return pc.setLocalDescription(o); })
			: pc.setRemoteDescription({ type: "offer", sdp: atob(%s) })
				.then(function () { return pc.createAnswer(); })
				.then(function (a) { return pc.setLocalDescription(a); });

		go.then(gathered)
			.then(function () { R.sdp = btoa(pc.localDescription.sdp); })
			.catch(function (e) { R.err = String(e && e.message || e); });
		return "ok";
	]]):format(js_string(role), ice_json(), js_string(remote or ""))
	return eval(guarded(code)) == "ok"
end

-- nil while ICE is still gathering; the local blob when it is done; false plus
-- a reason if the browser refused.
function M.rtc_blob()
	local r = eval(guarded(
		'var R=window.__ravelRTC||{};'
		.. 'if(R.err)return "!"+R.err; return R.sdp?"#":""'))
	if not r or r == "" then return nil end
	if r:sub(1, 1) == "!" then return false, r:sub(2) end
	return eval_long('window.__ravelRTC.sdp')
end

-- The host, applying the answer that came back. setRemoteDescription is async,
-- so a refusal lands in R.err a moment later rather than in this return value —
-- the status line is what tells the truth about whether the channel opened.
function M.rtc_finish(remote)
	local r = eval(guarded(
		'var R=window.__ravelRTC;if(!R||!R.pc)return "none";'
		.. 'R.pc.setRemoteDescription({type:"answer",sdp:atob(' .. js_string(remote) .. ')})'
		.. '.catch(function(e){R.err=String(e&&e.message||e)});return "ok"'))
	return r == "ok"
end

function M.rtc()
	return {
		name = "webrtc",
		send = function(text)
			return eval(guarded('var R=window.__ravelRTC;'
				.. 'if(!R||!R.ch)return "none";'
				.. 'R.out.push(' .. js_string(text) .. ');'
				.. 'R.flush();'
				.. 'return R.out.length ? "queued" : "ok"'))
		end,
		recv = function()
			if (tonumber(call("__rvn")) or 0) == 0 then return nil end
			return (eval_long('window.__ravelRTC.inbox.shift()'))
		end,
		status = function()
			local s2 = call("__rvs") or "?"
			local q = eval(guarded('return String(((window.__ravelRTC||{}).out||[]).length)'))
			if (tonumber(q) or 0) > 0 then s2 = s2 .. ", " .. q .. " waiting to send" end
			return s2
		end,
		close = function()
			eval(guarded('var R=window.__ravelRTC;if(R&&R.pc)R.pc.close();'
				.. 'window.__ravelRTC={};return "ok"'))
		end,
	}
end

-- Exposed because the control panel needs the same door, and because a person
-- debugging this at 1am will want to poke the page by hand.
M.call      = call
M.eval      = eval
M.eval_long = eval_long
M.guarded   = guarded
M.js_string = js_string

return M
