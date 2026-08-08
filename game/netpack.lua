-- Turning a table into a string somebody can paste into a chat window, and
-- back. Two layers, both hand-rolled in portable Lua for the same reason: the
-- wire format has to be **identical on every host**. A CLI player must be able
-- to paste a string a browser player produced, and love.data — which has both
-- deflate and base64 — does not exist under the headless shim. A format that
-- only half the clients can read is not a format.
--
--   compress/decompress   LZSS, because a state is mostly repeated key names
--   encode/decode         base64, because the result has to survive a chat
--                         client, a JS string literal and a copy/paste

local M = {}

---------------------------------------------------------------- base64

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, 64 do B64R[B64:sub(i, i)] = i - 1 end

function M.encode(s)
	local out, n = {}, 0
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local v = a * 65536 + (b or 0) * 256 + (c or 0)
		local e1, e2 = math.floor(v / 262144) % 64, math.floor(v / 4096) % 64
		local e3, e4 = math.floor(v / 64) % 64, v % 64
		n = n + 1
		out[n] = B64:sub(e1 + 1, e1 + 1) .. B64:sub(e2 + 1, e2 + 1)
			.. (b and B64:sub(e3 + 1, e3 + 1) or "=")
			.. (c and B64:sub(e4 + 1, e4 + 1) or "=")
	end
	return table.concat(out)
end

function M.decode(s)
	s = s:gsub("[^A-Za-z0-9+/=]", "")   -- chat clients wrap lines; drop the damage
	local out, n = {}, 0
	for i = 1, #s, 4 do
		local d1, d2 = B64R[s:sub(i, i)], B64R[s:sub(i + 1, i + 1)]
		if not (d1 and d2) then return nil end
		local d3, d4 = B64R[s:sub(i + 2, i + 2)], B64R[s:sub(i + 3, i + 3)]
		local v = d1 * 262144 + d2 * 4096 + (d3 or 0) * 64 + (d4 or 0)
		n = n + 1
		out[n] = string.char(math.floor(v / 65536) % 256)
			.. (d3 and string.char(math.floor(v / 256) % 256) or "")
			.. (d4 and string.char(v % 256) or "")
	end
	return table.concat(out)
end

---------------------------------------------------------------- LZSS
--
-- Deliberately not deflate. A Lua deflate with its Huffman stage is several
-- hundred lines and a week of nobody trusting it; LZSS is the half that does
-- almost all the work on this particular payload, because a game state is the
-- same twenty key names over and over and every one of them is a long match.
--
-- Format: one flag byte, then eight tokens, low bit first.
--   flag bit 0 → a literal byte
--   flag bit 1 → two bytes: 12-bit distance back, 4-bit (length - 3),
--                so 3..18 bytes copied from up to 4096 back
-- A trailing partial group is fine: the decoder stops at the end of input.

local WINDOW, MINM, MAXM = 4096, 3, 18
local PROBES = 48   -- how far down a hash chain to look; past this it stops paying

function M.compress(s)
	local n = #s
	if n == 0 then return "" end
	local out, on = {}, 0
	local head, prev = {}, {}      -- 3-byte key → latest position, and its chain
	local group, gn, flags = {}, 0, 0
	local byte, sub, char = string.byte, string.sub, string.char

	local function flush()
		if gn == 0 then return end
		on = on + 1
		out[on] = char(flags) .. table.concat(group, "", 1, gn)
		group, gn, flags = {}, 0, 0
	end

	local i = 1
	while i <= n do
		local best_len, best_dist = 0, 0
		if i + MINM - 1 <= n then
			local key = sub(s, i, i + MINM - 1)
			local p   = head[key]
			local probes = 0
			while p and probes < PROBES do
				local dist = i - p
				if dist > WINDOW then break end
				-- Extend only past what we already have; anything shorter is
				-- not worth the comparison.
				if byte(s, p + best_len) == byte(s, i + best_len) then
					local len = 0
					while len < MAXM and i + len <= n and byte(s, p + len) == byte(s, i + len) do
						len = len + 1
					end
					if len > best_len then
						best_len, best_dist = len, dist
						if len == MAXM then break end
					end
				end
				p = prev[p]
				probes = probes + 1
			end
		end

		local step
		if best_len >= MINM then
			local code = (best_dist - 1) * 16 + (best_len - MINM)
			gn = gn + 1
			group[gn] = char(math.floor(code / 256), code % 256)
			flags = flags + 2 ^ (gn - 1)
			step = best_len
		else
			gn = gn + 1
			group[gn] = sub(s, i, i)
			step = 1
		end

		-- Index every position we pass over, including the ones inside a match:
		-- a later match can start anywhere.
		for k = i, i + step - 1 do
			if k + MINM - 1 <= n then
				local key = sub(s, k, k + MINM - 1)
				prev[k], head[key] = head[key], k
			end
		end
		i = i + step
		if gn == 8 then flush() end
	end
	flush()
	return table.concat(out)
end

function M.decompress(s)
	local n = #s
	local out, on = {}, 0
	local i = 1
	local byte, sub, char = string.byte, string.sub, string.char
	while i <= n do
		local flags = byte(s, i)
		if not flags then break end
		i = i + 1
		for bit = 0, 7 do
			if i > n then break end
			if math.floor(flags / 2 ^ bit) % 2 == 1 then
				local hi, lo = byte(s, i), byte(s, i + 1)
				if not lo then return nil end
				i = i + 2
				local code = hi * 256 + lo
				local dist, len = math.floor(code / 16) + 1, code % 16 + MINM
				-- Overlapping copies are legal and load-bearing (that is how a
				-- run of one repeated byte is encoded), so this copies a byte at
				-- a time from the output built so far rather than in one slice.
				local start = on - dist + 1
				if start < 1 then return nil end
				for k = 0, len - 1 do
					on = on + 1
					out[on] = out[start + k]
				end
			else
				on = on + 1
				out[on] = sub(s, i, i)
				i = i + 1
			end
		end
	end
	return table.concat(out)
end

return M
