--- Unsigned integer encoding and utilities.
-- @module util.uint

local ult, mtoint, mntype, max_int = math.ult, math.tointeger, math.type, math.maxinteger
local setmetatable = setmetatable
local tonumber = tonumber
local type = type
local time = os.time
local lpeg = require"lpeglabel":locale()
local constants = require"lacord.const"

local _ENV = setmetatable({}, {__call = function(self,s) return self.touint(s) end})

local function by10(n, i) i = i or 1
    for _ = 1, i do n = (n << 4) - (n << 2) - (n << 1) end
    return n
end


local function to_integer_worker(s) -- string -> uint64
    local n = 0
    local l = #s
    for i = l -1,0, -1  do
        n = n + by10(tonumber(s:sub(i+1,i+1)), l-i-1)
    end
    return n
end

local two_63 = 2^63
local two_64 = 2^64

local function float_to_uint(f)
    if f > max_int then
        return mtoint(((f + two_63) % two_64) - two_63)
    else
        return mtoint(f)
    end
end

local function lnum_to_uint(l)
    if mntype(l) == 'integer' then
        return l
    else
        return float_to_uint(l)
    end
end

local numeral = lpeg.digit^1 * -1

--- Converts a number or string into an encoded uint64.
-- @tparam number|string s
-- @treturn[1] integer The encoded uint64.
-- @treturn[2] nil
function touint(s)
    if type(s) == 'number' then return lnum_to_uint(s)
    elseif type(s) == 'string' and numeral:match(s) then
        return to_integer_worker(s)
    end
end

--- uint64 tostring
-- @int i An encoded uint64.
function tostring(i) return ("%u"):format(i) end

local function udiv (n, d)
    if d < 0 then
      if ult(n, d) then return 0
      else return 1
      end
    end
    local q = ((n >> 1) // d) << 1
    local r = n - q * d
    if not ult(r, d) then q = q + 1 end
    return q
end

do
    local fnv_basis = touint"14695981039346656037"
    local fnv_prime = 1099511628211
    --- Computes the FNV-1a 64bit hash of the given string.
    -- @str str The input string.
    -- @treturn integer The hash.
    function hash(str)
        local hash = fnv_basis
        for i = 1, #str do
        hash = hash ~ str:byte(i)
        hash = (hash * fnv_prime)
        end
        return hash
    end
end

local epoch = constants.discord_epoch * 1000

--- Computes the UNIX timestamp of a given uint64, using discord's bitfield format.
-- @tparam string|number s The snowflake.
-- @treturn integer The timestamp.
function timestamp(s)
    return udiv((touint(s) >> 22) + epoch , 1000)
end

--- Creates an artificial snowflake from a given UNIX timestamp.
-- @tparam[opt=current time] integer s The timestamp.
-- @treturn integer The resulting snowflake.
function fromtime(s)
    s = by10(s or time(), 3)
    return (s - epoch) << 22
end

--- Gets the timestamp, worker ID, process ID and increment from a snowflake.
-- @tparam number|string s The snowflake.
-- @treturn table
function decompose(s)
    s = touint(s)
    return {
         timestamp = timestamp(s)
        ,worker = (s & 0x3E0000) >> 17
        ,pid = (s & 0x1F000) >> 12
        ,increment = s & 0xFFF
    }
end

local inc = -1

--- Creates an artifical snowflake from the given timestamp, worker and pid.
-- @int s The timestamp.
-- @int worker The worker ID.
-- @int pid The process ID.
-- @int[opt] incr The increment. An internal incremented value is used if one is not provided.
-- @treturn integer The snowflake.
function synthesize(s, worker, pid, incr)
    inc = (inc + 1) & 0xFFF
    incr = (incr or inc) &  0xFFF
    worker = ((worker or 0) & 63) << 17
    pid = ((pid or 0) & 63) << 12
    return fromtime(s) | worker | pid | incr
end

---sort two snowflake objects.
function snowflake_sort(i,j) return ult(touint(i.id) , touint(j.id)) end

---sort two snowflake ids.
function id_sort(i,j) return ult(touint(i) , touint(j)) end

return _ENV