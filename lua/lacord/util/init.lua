local random = math.random
local popen = io.popen
local assert = assert
local error = error
local getm = getmetatable
local setm = setmetatable
local vstring = _VERSION
local to_n = tonumber
local to_s = tostring
local set = rawset
local typ = type
local encodeURIComponent = require"http.util".encodeURIComponent
local dict_to_query = require"http.util".dict_to_query
local _platform = require"lacord.util.archp".os

local _ENV = {}

-- luacheck: ignore 111

--- Computes the FNV-1a 32bit hash of the given string.
-- @str str The input string.
-- @treturn integer The hash.
function hash(str)
    local hash = 2166136261
    for i = 1, #str do
        hash = hash ~ str:byte(i)
        hash = (hash * 16777619) & 0xffffffff
    end
    return hash
end

--- Produces a random double between `A` and `B`.
function rand(A, B)
    return random() * (A - B) + A
end

--- The operating system platform.
-- @within Constants
-- @string platform
platform = _platform

do
    local vmj, vmn = vstring:match('Lua (%d)%.(%d)')

    _ENV.version_major = to_n(vmj)
    _ENV.version_minor = to_n(vmn)
    _ENV.version = _ENV.version_major + _ENV.version_minor / 10
end

--- Tests whether a string starts with a given prefix.
-- @str s The string to check.
-- @str prefix The prefix.
-- @treturn bool True if s starts with the prefix.
function startswith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

--- Returns the suffix of `pre` in `s`.
-- @str s The string to check.
-- @str pre The prefix.
-- @treturn string The suffix of `pre` in `s` or `s` if `s` does not start with `pre`.
function suffix(s, pre)
    local len = #pre
    return s:sub(1, len) == pre and s:sub(len + 1) or s
end

--- Tests whether a string ends with a given suffix.
-- @str s The string to check.
-- @str suffix The suffix.
-- @treturn bool True if s starts with the suffix.
function endswith(s, suffix)
    return s:sub(-#suffix) == suffix
end

--- Returns the prefix of `suf` in `s`.
-- @str s The string to check.
-- @str suf The suffix.
-- @treturn string The prefix of `suf` in `s` or `s` if `s` does not end with `suf`.
function prefix(s, suf)
  local len = #suf
  return s:sub(-len) == suf and s:sub(1, -len -1) or s
end

--- Resolve a prospective payload w.r.t lacord content types.
--  Users can check the 2nd return value to see if any processing was done.
function content_typed(payload, ...)
    local mt = getm(payload)
    if mt and mt.__lacord_content_type then
        return mt.__lacord_payload(payload, ...),mt.__lacord_content_type
    else
        return payload
    end
end

--- Some common content types.
_ENV.content_types = {
    JSON = "application/json",
    TEXT = "text/plain; charset=UTF-8",
    URLENCODED = "application/x-www-form-urlencoded",
    BYTES = "application/octet-stream",
}

local txt = {
    __lacord_content_type = _ENV.content_types.TEXT,
    __lacord_payload = function(x) return x[1] end,
    __tostring = function(x) return x[1] end,
}

function plaintext(str) return setm({str}, txt) end

local urlencoded_t = {__lacord_content_type = "application/x-www-form-urlencoded"}

function urlencoded_t:__lacord_payload()
    return encodeURIComponent(dict_to_query(self))
end

function urlencoded(t) return setm(t or {}, urlencoded_t) end

return _ENV