-- The browser's networking controls, drawn as HTML over the canvas rather than
-- inside the game. Two reasons, both practical: the renderer needs no changes
-- at all (so this experiment cannot break how the game looks), and a text box
-- you can paste 25 KB into is a thing the browser already has and LÖVE does not.
--
-- Requires netlink's bridge. Everything here is inert without it, which is the
-- desktop and headless case.

local net     = require("net")
local netlink = require("netlink")

local M = {}

local up, last_status, last_seats = false, nil, nil
local shown = false
local linked_at = nil   -- when the current transport was attached

-- Keystrokes typed into the panel must not also reach the game: LÖVE listens on
-- the window, and "z" is undo. Stopping propagation at the panel keeps the two
-- input surfaces apart.
local PANEL = [[
	if (document.getElementById("ravel-net")) return "again";
	var css = document.createElement("style");
	css.textContent =
		"#ravel-net{position:fixed;top:8px;right:8px;z-index:99;font:12px system-ui,sans-serif;" +
		"background:rgba(12,18,28,.94);color:#cfd8e3;border:1px solid #2b3a4d;border-radius:6px;" +
		"padding:8px;width:230px;box-shadow:0 4px 16px rgba(0,0,0,.5)}" +
		"#ravel-net h4{margin:0 0 6px;font-size:12px;color:#8fb4dd;font-weight:600}" +
		"#ravel-net button{font:11px system-ui;background:#1d2b3d;color:#cfd8e3;border:1px solid #35506e;" +
		"border-radius:4px;padding:3px 7px;margin:2px 2px 0 0;cursor:pointer}" +
		"#ravel-net button:hover{background:#27405c}" +
		"#ravel-net input,#ravel-net textarea{width:100%;box-sizing:border-box;background:#0a1119;" +
		"color:#cfd8e3;border:1px solid #35506e;border-radius:4px;padding:3px;font:11px monospace;margin-top:4px}" +
		"#ravel-net .s{margin-top:6px;color:#7f9ab5;font-size:11px;line-height:1.35;word-break:break-all}" +
		"#ravel-net.min{width:auto;padding:4px 8px}" +
		"#ravel-net.min .body{display:none}";
	document.head.appendChild(css);

	var d = document.createElement("div");
	d.id = "ravel-net";
	d.style.display = "none";   // a card opens this; see net.lua's net_* actions
	d.innerHTML =
		'<h4 style="cursor:pointer" id="rv-t">▾ Ravel · net</h4><div class="body">' +
		'<div><button id="rv-link" title="Only reaches other tabs of THIS browser">' +
		'Link tabs (same browser)</button>' +
		'<button id="rv-p2p" title="Another browser, or another computer">' +
		'Invite over the internet</button>' +
		'<button id="rv-off">Off</button></div>' +
		'<input id="rv-room" value="ravel" spellcheck="false">' +
		'<div id="rv-seats"></div>' +
		'<div><button id="rv-copy">Copy state</button>' +
		'<button id="rv-load">Paste &amp; apply</button>' +
		'<button id="rv-sync">Resync</button></div>' +
		'<textarea id="rv-box" rows="3" spellcheck="false" ' +
		'placeholder="paste an opponent&apos;s state here"></textarea>' +
		'<div class="s" id="rv-status">offline</div>' +
		'<div class="s" id="rv-msg" style="color:#c8a45e"></div>' +
		'<div class="s bad" id="rv-bad" style="display:none"></div></div>';
	document.body.appendChild(d);

	var W = window;
	W.__ravel = W.__ravel || {};
	W.__ravel.cmds = W.__ravel.cmds || [];
	var push = function (c) { W.__ravel.cmds.push(c); };

	["keydown", "keyup", "keypress"].forEach(function (t) {
		d.addEventListener(t, function (e) { e.stopPropagation(); }, false);
		d.addEventListener(t, function (e) { e.stopPropagation(); }, true);
	});

	document.getElementById("rv-t").onclick = function () { d.classList.toggle("min"); };
	document.getElementById("rv-link").onclick = function () {
		push("link " + (document.getElementById("rv-room").value || "ravel"));
	};
	document.getElementById("rv-p2p").onclick   = function () { push("p2p"); };
	document.getElementById("rv-off").onclick   = function () { push("unlink"); };
	document.getElementById("rv-copy").onclick  = function () { push("copy"); };
	document.getElementById("rv-sync").onclick  = function () { push("resync"); };
	document.getElementById("rv-load").onclick  = function () {
		W.__ravel.pasted = document.getElementById("rv-box").value || "";
		push("paste");
	};
	return "ok";
]]

function M.setup()
	if up then return true end
	if not netlink.browser_available() then return false end
	local r = netlink.eval(netlink.guarded(PANEL))
	up = (r == "ok" or r == "again")
	if up then
		net.on_status = function(text) M.note(text) end
		net.on_ui     = function(what) M.open(what) end
		M.refresh(true)
	end
	return up
end

function M.available()
	return up
end

-- What a net_* action asks for. The panel is not on screen until one of them
-- runs, so a solitaire game never grows a networking widget it has no use for.
--
-- The request goes into the same queue the buttons push to, rather than calling
-- a handler directly: the handlers are declared below this point, and reaching
-- backwards for one is how a local silently becomes a nil global. It also means
-- a card and a click take exactly the same path.
function M.open(what)
	if not up then return false end
	if not shown then
		shown = true
		netlink.eval(netlink.guarded(
			'var d=document.getElementById("ravel-net");if(d)d.style.display="block";return "ok"'))
		M.refresh(true)
	end
	local cmd = (what == "invite" and "p2p") or (what == "join" and "focusbox") or nil
	if cmd then
		netlink.eval(netlink.guarded(
			'var N=window.__ravel;if(N&&N.cmds)N.cmds.push(' .. netlink.js_string(cmd)
			.. ');return "ok"'))
	end
	return true
end

-- One short line of truth, refreshed only when it changes: every eval is a
-- round trip, and the status is read far more often than it moves.
local function status_text()
	local bits = { net.status() }
	if net.seat then bits[#bits + 1] = "you are " .. net.seat end
	local seats = net.seats()
	if #seats > 1 then bits[#bits + 1] = "turn: " .. tostring(require("zones").turn_seat()) end
	bits[#bits + 1] = "state " .. net.state_hash()
	return table.concat(bits, " · ")
end

-- News, on its own line. It used to overwrite the status, and then sat there
-- forever: the status only redraws when it *changes*, so a state that had gone
-- back to normal had nothing to say and said nothing.
function M.note(text)
	if not up then return end
	netlink.eval(netlink.guarded(
		'var e=document.getElementById("rv-msg");if(e)e.textContent='
		.. netlink.js_string(text) .. ';return "ok"'))
end

-- Trouble is not news, it is a condition: it stays on screen until it stops
-- being true. The caller supplies the whole sentence, because the two things
-- that land here — out of sync, and nobody listening — need different words and
-- point at different buttons.
local last_bad = nil

local function set_trouble(html)
	if html == last_bad then return end
	last_bad = html
	netlink.eval(netlink.guarded(
		'var e=document.getElementById("rv-bad");if(!e)return "no";'
		.. 'e.style.display=' .. netlink.js_string(html and "block" or "none") .. ';'
		.. 'e.innerHTML=' .. netlink.js_string(html or "") .. ';return "ok"'))
end

local function set_status(text)
	netlink.eval(netlink.guarded(
		'var e=document.getElementById("rv-status");if(e)e.textContent='
		.. netlink.js_string(text) .. ';return "ok"'))
end

-- The seat buttons are rebuilt only when the game's seat list changes, which is
-- on load. A one-seat game gets none, and never learns that seats exist.
local function rebuild_seats()
	local seats = net.seats()
	local html = {}
	if #seats > 1 then
		html[#html + 1] = "play as: "
		for _, s in ipairs(seats) do
			html[#html + 1] = ('<button class="rv-seat" data-s="%s">%s</button>'):format(s, s)
		end
		html[#html + 1] = '<button class="rv-seat" data-s="">any</button>'
	end
	netlink.eval(netlink.guarded(
		'var e=document.getElementById("rv-seats");if(!e)return "no";'
		.. 'e.innerHTML=' .. netlink.js_string(table.concat(html)) .. ';'
		.. 'Array.prototype.forEach.call(e.querySelectorAll(".rv-seat"),function(b){'
		.. 'b.onclick=function(){window.__ravel.cmds.push("seat "+b.dataset.s)}});return "ok"'))
end

-- The invite is offered where it means something: inside a game, for two or
-- more players. On the menu there is nothing to invite anybody *to*, and a
-- one-seat game has nobody to invite — the button was previously happy to build
-- a connection to a screen with nothing on it.
local function invitable()
	return #net.seats() > 1
end

function M.refresh(force)
	if not up then return end
	local seats = table.concat(net.seats(), ",")
	if force or seats ~= last_seats then
		last_seats = seats
		rebuild_seats()
	end
	local s = status_text()
	if s ~= last_status then
		last_status = s
		set_status(s)
	end
	-- Attaching a transport always succeeds, so silence is the only evidence
	-- that nobody is listening — and silence is exactly what a player reads as
	-- "it is connected". Say it out loud after a few seconds, and name the
	-- button that actually crosses browsers.
	local trouble = net.desync
		and ("<b>Out of sync.</b> " .. net.desync .. " Press <b>Resync</b> to ask them for the whole game.")
		or nil
	local lonely = nil
	if net.linked() and not net.last_heard and linked_at
		and os.time() - linked_at >= 4 then
		lonely = "Nobody has answered. <b>Link tabs</b> only reaches other tabs of "
			.. "<i>this</i> browser — for a different browser, or another computer, "
			.. "use <b>Invite over the internet</b>."
	end
	set_trouble(trouble or lonely)
end

local HANDLERS = {}

HANDLERS["link"] = function(room)
	local t, err = netlink.browser(room ~= "" and room or "ravel")
	if not t then M.note("could not link: " .. tostring(err)); return end
	net.link(t)
	linked_at = os.time()
	-- Announce ourselves, so a tab that links second is not invisible until it
	-- moves. Whoever is behind will ask for a full state on its own.
	net.publish(true)
end

HANDLERS["unlink"] = function() net.unlink(); linked_at = nil end

HANDLERS["focusbox"] = function()
	netlink.eval(netlink.guarded(
		'var b=document.getElementById("rv-box");if(b)b.focus();return "ok"'))
	M.note("Paste the invite your opponent sent you, then press Paste & apply.")
end

HANDLERS["resync"] = function()
	local ok, err = net.request_resync()
	M.note(ok and "asked them for the whole game." or ("cannot: " .. tostring(err)))
end

HANDLERS["seat"] = function(name)
	net.claim_seat(name)
end

HANDLERS["copy"] = function()
	-- Selecting is as far as this can go without a live user gesture: the click
	-- that asked for the text is over by the time Lua answers, and the clipboard
	-- API wants one. Ctrl+C from here is one keystroke and always works.
	local text = net.export()
	netlink.eval(netlink.guarded(
		'var b=document.getElementById("rv-box");b.value=' .. netlink.js_string(text)
		.. ';b.focus();b.select();return "ok"'))
	M.note("copied to the box below — press Ctrl+C (" .. #text .. " bytes)")
end

-- Peer to peer, signalled by the same box everything else goes through. The
-- handshake is two blobs carried by a human: this side makes one, the other
-- side answers it, and after that nothing is ever pasted again.
local awaiting = nil   -- "answer" while the host waits for the reply blob

local function show(text)
	netlink.eval(netlink.guarded(
		'var b=document.getElementById("rv-box");if(b){b.value='
		.. netlink.js_string(text) .. ';b.focus();b.select();}return "ok"'))
end

-- ICE gathering takes a second or two, so the blob is collected across frames
-- rather than waited for: blocking the game to wait on a network round trip is
-- exactly what the rest of this file avoids.
local pending_role = nil

local function pump_handshake()
	if not pending_role then return end
	local blob, err = netlink.rtc_blob()
	if blob == false then
		pending_role = nil
		M.note("peer-to-peer failed: " .. tostring(err))
		return
	end
	if not blob then return end
	local kind = pending_role == "host" and "offer" or "answer"
	pending_role = nil
	show(net.wrap_sdp(kind, blob))
	if kind == "offer" then
		awaiting = "answer"
		M.note("Ctrl+C and send this to your opponent, then paste their reply here. "
			.. "They do not need the game — it travels with the connection.")
	else
		net.link(netlink.rtc())
		M.note("Ctrl+C and send this back. You are connected once they paste it.")
	end
end

HANDLERS["p2p"] = function()
	if not invitable() then
		M.note("Load a two-player game first — the invite carries the game with it.")
		return
	end
	if not netlink.rtc_start("host") then M.note("this browser has no WebRTC"); return end
	pending_role, awaiting = "host", nil
	M.note("building an invite…")
end

HANDLERS["paste"] = function()
	local text = netlink.eval_long('(window.__ravel.pasted||"")')
	if not text or text == "" then M.note("nothing pasted"); return end
	local kind = net.kind_of(text)

	if kind == "offer" then
		if not netlink.rtc_start("guest", net.unwrap_sdp(text)) then
			M.note("this browser has no WebRTC")
		else
			pending_role = "guest"
			M.note("answering…")
		end
	elseif kind == "answer" then
		if awaiting ~= "answer" then M.note("no invite of ours is waiting for an answer"); return end
		awaiting = nil
		if netlink.rtc_finish(net.unwrap_sdp(text)) then
			net.link(netlink.rtc())
			net.publish(true)
			M.note("connected.")
		else
			M.note("that answer was refused")
		end
	elseif kind == "invite" then
		M.note(net.accept(text) and "started the same game." or "that invite is not valid")
	else
		local ok, err = net.import(text)
		M.note(ok and "applied their state." or ("rejected: " .. tostring(err)))
	end
	last_status = nil
end

-- Called once a frame. The empty case is a single round trip that measured at
-- 6 microseconds, so polling every frame costs nothing worth optimising.
function M.update()
	if not up then return end
	pump_handshake()
	for _ = 1, 8 do
		local cmd = netlink.call("__rvc")
		if not cmd or cmd == "" then break end
		local name, rest = cmd:match("^(%S+)%s*(.*)$")
		local fn = name and HANDLERS[name]
		if fn then pcall(fn, rest) end
		last_status = nil
	end
	M.refresh(false)
end

return M
