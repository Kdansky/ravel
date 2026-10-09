// The browser's second engine: botpeer.lua on wasmoon (Lua 5.4 in wasm) in a Web
// Worker, playing the engine's seats while the page's one thread goes on
// drawing. love.js is built without threads, which is the whole reason this is
// not a love.thread (see netlink.engine, the page's end).
//
// It hears the page over a BroadcastChannel in a room of the page's choosing,
// named in this script's URL — the page's end is netlink.browser, unchanged.
// The engine's own files are fetched as they are required, from the same
// directory game.love is packed from (nginx.conf, /engine/src/).
importScripts("/engine/wasmoon.js");

const room = decodeURIComponent(location.hash.slice(1));
const inbox = [];
const channel = new BroadcastChannel("ravel:" + room);
channel.onmessage = (e) => { if (typeof e.data === "string") inbox.push(e.data); };

// Synchronous, because `require` is: a worker may block, a page may not.
function fetchText(path) {
	const x = new XMLHttpRequest();
	x.open("GET", "/engine/src/" + path, false);
	x.send();
	return x.status === 200 ? x.responseText : undefined;
}

// The headless shim's filesystem (headless.lua), over the server. A game the
// page shares is written here and kept for as long as the worker lives.
const BOOT = `
unpack = unpack or table.unpack
local written = {}
local function read(path) return written[path] or fetch_text(path) end
love = {
	filesystem = {
		read = read,
		write = function(path, data) written[path] = data return true end,
		getInfo = function(path) if read(path) then return { type = "file" } end end,
		createDirectory = function() return true end,
		remove = function(path) written[path] = nil return true end,
	},
	graphics = { getDimensions = function() return 960, 540 end },
}
table.insert(package.searchers, 2, function(name)
	local src = fetch_text(name:gsub("%.", "/") .. ".lua")
	if not src then return "\\n\\tno " .. name .. ".lua on the server" end
	return assert(load(src, "@" .. name .. ".lua"))
end)
math.randomseed(os.time())
local peer = require("botpeer")
peer.start({ name = "screen", send = wire_send, recv = wire_recv })
function engine_step() return peer.step() end
`;

(async () => {
	const lua = await new wasmoon.LuaFactory("/engine/glue.wasm").createEngine();
	lua.global.set("fetch_text", fetchText);
	lua.global.set("wire_send", (text) => channel.postMessage(text));
	lua.global.set("wire_recv", () => inbox.shift());
	await lua.doString(BOOT);
	const step = lua.global.get("engine_step");
	// Straight back after a move, since the next seat up may be the engine's too.
	const tick = () => setTimeout(tick, step() ? 0 : 20);
	tick();
	// Thrown outside the promise, so it reaches the page's onerror and the seats go back to it.
})().catch((e) => setTimeout(() => { throw e; }));
