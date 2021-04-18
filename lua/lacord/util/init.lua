local random = math.random
local popen = io.popen
local assert = assert
local error = error

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

return _ENV