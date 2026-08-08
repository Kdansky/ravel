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
	d.innerHTML =
		'<h4 style="cursor:pointer" id="rv-t">▾ Ravel · net</h4><div class="body">' +
		'<div><button id="rv-link">Link tabs</button>' +
		'<button id="rv-off">Off</button></div>' +
		'<input id="rv-room" value="ravel" spellcheck="false">' +
		'<div id="rv-seats"></div>' +
		'<div><button id="rv-copy">Copy state</button>' +
		'<button id="rv-load">Paste &amp; apply</button></div>' +
		'<textarea id="rv-box" rows="3" spellcheck="false" ' +
		'placeholder="paste an opponent&apos;s state here"></textarea>' +
		'<div class="s" id="rv-status">offline</div>' +
		'<div class="s" id="rv-msg" style="color:#c8a45e"></div></div>';
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
	document.getElementById("rv-off").onclick   = function () { push("unlink"); };
	document.getElementById("rv-copy").onclick  = function () { push("copy"); };
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
		M.refresh(true)
	end
	return up
end

function M.available()
	return up
end

-- One short line of truth, refreshed only when it changes: every eval is a
-- round trip, and the status is read far more often than it moves.
local function status_text()
	local bits = { net.status() }
	if net.seat then bits[#bits + 1] = "you are " .. net.seat end
	local seats = net.seats()
	if #seats > 1 then bits[#bits + 1] = "turn: " .. tostring(require("zones").active_seat()) end
	bits[#bits + 1] = "state " .. net.fingerprint()
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
end

local HANDLERS = {}

HANDLERS["link"] = function(room)
	local t, err = netlink.browser(room ~= "" and room or "ravel")
	if not t then M.note("could not link: " .. tostring(err)); return end
	net.link(t)
	-- Announce ourselves, so a tab that links second is not invisible until it
	-- moves. Whoever is behind will ask for a full state on its own.
	net.publish(true)
end

HANDLERS["unlink"] = function() net.unlink() end

HANDLERS["seat"] = function(name)
	net.seat = (name ~= "" and name) or nil
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

HANDLERS["paste"] = function()
	local text = netlink.eval_long('(window.__ravel.pasted||"")')
	if not text or text == "" then M.note("nothing pasted"); return end
	local ok, err = net.import(text)
	M.note(ok and "applied their state." or ("rejected: " .. tostring(err)))
	last_status = nil
end

-- Called once a frame. The empty case is a single round trip that measured at
-- 6 microseconds, so polling every frame costs nothing worth optimising.
function M.update()
	if not up then return end
	for _ = 1, 8 do
		local cmd = netlink.eval(netlink.guarded(
			'var c=(window.__ravel||{}).cmds;return (c&&c.length)?String(c.shift()):""'))
		if not cmd or cmd == "" then break end
		local name, rest = cmd:match("^(%S+)%s*(.*)$")
		local fn = name and HANDLERS[name]
		if fn then pcall(fn, rest) end
		last_status = nil
	end
	M.refresh(false)
end

return M
