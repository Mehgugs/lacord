local lpeg = require"lpeglabel"
local random = math.random
local popen = io.popen
local ipairs, select = ipairs, select
local insert, unpack = table.insert, table.unpack
local setmetatable = setmetatable
local P, Cc, V, Cs, C, Ct = lpeg.P, lpeg.Cc, lpeg.V, lpeg.Cs, lpeg.C, lpeg.Ct
local _ENV = {}

--- Implements the iterposable interface for the given module.
-- This adds a single function `interpose` with the same behaviour as cqueues `interpose`.
-- @tab _ENV The module.
-- @treturn table The module, with a new method `interpose`.
-- @usage
--  local util = require"lacord.util" -- lacord modules are all interposable.
--  do
--    local old = util.interpose('hash', function(str)
--      if str == '' then return error("Contrived example error!")
--      else return old(str)
--      end
--    end)
--  end
function interposable(_ENV)
  function interpose(name, func)
      local old = _ENV[name]
      _ENV[name] = func
      return old
  end
  return _ENV
end

interposable(_ENV)

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

--- lpeg utilities

function exactly(n, p)
  local patt = P(p)
  local out = patt
  for _ = 1, n-1 do
      out = out * patt
  end
  return out
end

local function truth() return true end

function check(p) return  (P(p)/truth) + Cc(false) end

function sepby(s, p) p = P(p) return p * (s * p)^0 end
function endby(s, p) p = P(p) return (p * s)^1 end
function between(b, s) s = P(s) return  b * ((s * b)^1) end
function anywhere (p)
  return P { p + 1 * V(1) }
end

function zipWith(f, ...) local p = f((...))
  for _, q in ipairs{select(2, ...)} do
      p = p * f(q)
  end
  return p
end

function combine(t)
  local a = P(t[1])
  for i = 2, #t do
      a = a * t[i]
  end
  return a
end

function lazy(expr, cont)
  return P{cont + expr * lpeg.V(1)}
end

--- end of lpeg utilities

local function _platform()
  local f = popen('uname')
  local res = f:read()
  if res == 'Darwin' then res = 'OSX' end
  f:close()
  return res
end

--- The operating system platform.
-- @within Constants
-- @string platform
platform = _platform()

local function results(self)
  return unpack(self.result)
end

local function failure(self)
  return self
end

--- Implements the capturable interface for the given module.
-- Makes a module's methods capturable, which makes chaining of multiple failable methods easy.
-- @see capture
-- @tab _ENV The module to make capturable.
-- @treturn table _ENV with a new method `capture`
function capturable(_ENV)
  local cpmt = {}

  function cpmt:__index(k)
    if self.success then
      local function method(self, ...)
        local s, v, e = _ENV[k](self[1], ...)
        self.success = s
        insert(self.result, v)
        self.error = e or self.error
        return self
      end
      self[k] = method
      return method
    else
      return failure
    end
  end
  --- Creates a method chain.
  -- @tab s The module, call capture using method call syntax.
  -- @bool success The success state.
  -- @param value The value state.
  -- @param err The error state, usually a string by convention.
  -- @treturn table The capture object.
  -- @usage
  --  local api = require"lacord.api"
  --  local util = require"lacord.util"
  --  util.capturable(api)
  --
  --  local R = discord_api
  --    :capture(discord_api:get_gateway_bot())
  --    :get_current_application_information()
  --  if R.success then -- ALL methods succeeded
  --    local results_list = R.result
  --    local A, B, C = R:results()
  --  else
  --    local why = R.error
  --    local partial = R.result -- There may be partial results collected before the error, you can use this to debug.
  --    R:some_method() -- If there's been a faiure, calls like this are noop'd.
  --  end
  function capture(s, success, value, err)
    return setmetatable({s, success = success, result = {value}, error = err, results = results}, cpmt)
  end
end

return _ENV