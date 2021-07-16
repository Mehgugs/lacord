local random = math.random
local popen = io.popen
local assert = assert
local error = error
local getm = getmetatable

local _ENV = {}

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

function shift(n, start1, stop1, start2, stop2)
    return (n - start1) / (stop1 - start1) * (stop2 - start2) + start2
end

function rand(A, B)
    return shift(random(), 0, 1, A, B)
end

local function _platform()
    local f = assert(popen('uname'))
    local res, m = f:read()
    if not res then f:close() return error(m) end

    if res == 'Darwin' then res = 'OSX' end
    return res
end

--- The operating system platform.
-- @within Constants
-- @string platform
platform = _platform()

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

function content_typed(payload)
    local mt = getm(payload)
    if mt and mt.__lacord_content_type then -- this can be implemented in order to send user-defined objects to discord in multi part uploads
        return mt.__lacord_payload(payload),mt.__lacord_content_type
    else
        return payload
    end
end

return _ENV