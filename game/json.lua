local json = {}

local function decode_error(str, idx, msg)
  error(string.format("json decode error at position %d: %s", idx, msg .. " near '" .. str:sub(idx, idx + 20) .. "'"))
end

local function skip_whitespace(str, idx)
  while true do
    local c = str:sub(idx, idx)
    if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
      return idx
    end
    idx = idx + 1
  end
end

local parse_value

local function parse_string(str, idx)
  idx = idx + 1
  local result = {}

  while true do
    local c = str:sub(idx, idx)
    if c == "" then
      decode_error(str, idx, "unterminated string")
    elseif c == '"' then
      return table.concat(result), idx + 1
    elseif c == "\\" then
      local esc = str:sub(idx + 1, idx + 1)
      if esc == '"' or esc == "\\" or esc == "/" then
        result[#result + 1] = esc
        idx = idx + 2
      elseif esc == "b" then
        result[#result + 1] = "\b"
        idx = idx + 2
      elseif esc == "f" then
        result[#result + 1] = "\f"
        idx = idx + 2
      elseif esc == "n" then
        result[#result + 1] = "\n"
        idx = idx + 2
      elseif esc == "r" then
        result[#result + 1] = "\r"
        idx = idx + 2
      elseif esc == "t" then
        result[#result + 1] = "\t"
        idx = idx + 2
      elseif esc == "u" then
        local hex = str:sub(idx + 2, idx + 5)
        if not hex:match("^%x%x%x%x$") then
          decode_error(str, idx, "invalid unicode escape")
        end
        local code = tonumber(hex, 16)
        if code < 128 then
          result[#result + 1] = string.char(code)
        elseif code < 2048 then
          result[#result + 1] = string.char(
            192 + math.floor(code / 64),
            128 + (code % 64)
          )
        else
          result[#result + 1] = string.char(
            224 + math.floor(code / 4096),
            128 + (math.floor(code / 64) % 64),
            128 + (code % 64)
          )
        end
        idx = idx + 6
      else
        decode_error(str, idx, "invalid escape character")
      end
    else
      result[#result + 1] = c
      idx = idx + 1
    end
  end
end

local function parse_number(str, idx)
  local num = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", idx)
  if not num then
    decode_error(str, idx, "invalid number")
  end
  local value = tonumber(num)
  if not value then
    decode_error(str, idx, "invalid number")
  end
  return value, idx + #num
end

local function parse_literal(str, idx, literal, value)
  if str:sub(idx, idx + #literal - 1) ~= literal then
    decode_error(str, idx, "invalid literal")
  end
  return value, idx + #literal
end

local function parse_array(str, idx)
  idx = idx + 1
  local result = {}
  idx = skip_whitespace(str, idx)

  if str:sub(idx, idx) == "]" then
    return result, idx + 1
  end

  while true do
    local value
    value, idx = parse_value(str, idx)
    result[#result + 1] = value
    idx = skip_whitespace(str, idx)

    local c = str:sub(idx, idx)
    if c == "]" then
      return result, idx + 1
    elseif c ~= "," then
      decode_error(str, idx, "expected ',' or ']'")
    end
    idx = skip_whitespace(str, idx + 1)
  end
end

local function parse_object(str, idx)
  idx = idx + 1
  local result = {}
  idx = skip_whitespace(str, idx)

  if str:sub(idx, idx) == "}" then
    return result, idx + 1
  end

  while true do
    if str:sub(idx, idx) ~= '"' then
      decode_error(str, idx, "expected string key")
    end

    local key, value
    key, idx = parse_string(str, idx)
    idx = skip_whitespace(str, idx)

    if str:sub(idx, idx) ~= ":" then
      decode_error(str, idx, "expected ':'")
    end

    idx = skip_whitespace(str, idx + 1)
    value, idx = parse_value(str, idx)
    result[key] = value
    idx = skip_whitespace(str, idx)

    local c = str:sub(idx, idx)
    if c == "}" then
      return result, idx + 1
    elseif c ~= "," then
      decode_error(str, idx, "expected ',' or '}'")
    end
    idx = skip_whitespace(str, idx + 1)
  end
end

parse_value = function(str, idx)
  idx = skip_whitespace(str, idx)
  local c = str:sub(idx, idx)

  if c == '"' then
    return parse_string(str, idx)
  elseif c == "{" then
    return parse_object(str, idx)
  elseif c == "[" then
    return parse_array(str, idx)
  elseif c == "-" or c:match("%d") then
    return parse_number(str, idx)
  elseif c == "t" then
    return parse_literal(str, idx, "true", true)
  elseif c == "f" then
    return parse_literal(str, idx, "false", false)
  elseif c == "n" then
    return parse_literal(str, idx, "null", nil)
  end

  decode_error(str, idx, "unexpected character")
end

function json.decode(str)
  if type(str) ~= "string" then
    error("json.decode expects a string")
  end

  local value, idx = parse_value(str, 1)
  idx = skip_whitespace(str, idx)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return value
end

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r",
  ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f",
}

local function encode_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

-- Tables with only sequential numeric keys encode as arrays (empty tables too).
local function is_array(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

-- Sorting map keys makes the output canonical, which is load-bearing well
-- beyond readable diffs: net.lua hashes this text to decide whether two
-- machines hold the same game, so "same table" has to mean "same bytes".
-- Comparing tostring alone is not a total order — a numeric 1 and a string "1"
-- tie, and a tie makes table.sort's result depend on input order in 5.1 and
-- raise "invalid order function" in 5.4 — so type breaks it first.
local function key_before(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  if ta == "number" then return a < b end
  return tostring(a) < tostring(b)
end

-- Map keys are sorted so output is deterministic (stable diffs, testable dumps).
-- With `indent` set, output is pretty-printed at that nesting depth.
local function encode_value(v, indent)
  local t = type(v)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "number" then
    return string.format("%.14g", v)
  elseif t == "string" then
    return encode_string(v)
  elseif t == "table" then
    local pad, pad_in, nl, sp = "", "", "", ""
    if indent then
      pad    = string.rep("  ", indent)
      pad_in = string.rep("  ", indent + 1)
      nl     = "\n"
      sp     = " "
    end
    local inner = indent and indent + 1
    local parts = {}
    if is_array(v) then
      if #v == 0 then return "[]" end
      -- A list of plain values goes on one line, however long, because that is
      -- how every game file in the repo is written and a dump is meant to be
      -- pasted back into one: ["white", "piece"] is one fact, not two. A list
      -- holding tables is structure and keeps a line each — which leaves a
      -- coordinate pair looking exactly like a coordinate pair.
      if indent then
        local flat, plain = {}, true
        for _, x in ipairs(v) do
          if type(x) == "table" then plain = false break end
          flat[#flat + 1] = encode_value(x, nil)
        end
        if plain then return "[" .. table.concat(flat, ", ") .. "]" end
      end
      for _, x in ipairs(v) do
        parts[#parts + 1] = pad_in .. encode_value(x, inner)
      end
      return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, key_before)
    for _, k in ipairs(keys) do
      parts[#parts + 1] = pad_in .. encode_string(tostring(k)) .. ":" .. sp .. encode_value(v[k], inner)
    end
    return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. pad .. "}"
  end
  error("json.encode: cannot encode " .. t)
end

function json.encode(value, pretty)
  return encode_value(value, pretty and 0 or nil)
end

return json
