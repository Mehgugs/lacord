--- Unsigned integer encoding and utilities.

local setm = setmetatable
local to_n = tonumber
local to_s = tostring
local typ  = type

local band   = bit.band
local bnot   = bit.bnot
local bor    = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift

local time = os.time

local ffi       = require"ffi"
local constants = require"lacord.const"

local cast = ffi.cast
local ctype = ffi.istype


local M = setm({}, {__call = function(self,s) return self.touint(s) end})

local max_int = bnot(0)

local uint64_t = ffi.typeof'uint64_t'

local function to_integer_worker(s) -- string -> uint64
    local n = 0ULL
    local l = #s
    local place = 1LL
    for i = l -1,0, -1  do
        n = n + to_n(s:sub(i+1,i+1)) * place
        place = place * 10ULL
    end
    return n
end

local two_63 = 2^63
local two_64 = 2^64

local function lnum_to_uint(f)
    if f > max_int then
        return cast(uint64_t, ((f + two_63) % two_64) - two_63)
    else
        return cast(uint64_t, f)
    end
end

local function numeral(str)
    local s, e = str:find('%d+', 1)
    return s == 1 and e == #str
end

--- Converts a number or string into an encoded uint64.
-- @tparam number|string s
-- @treturn[1] integer The encoded uint64.
-- @treturn[2] nil
function M.touint(s)
    local the_type = typ(s)
    if the_type == 'number' then return lnum_to_uint(s)
    elseif the_type == 'string' and numeral(s) then
        return to_integer_worker(s)
    elseif the_type == 'cdata' and ctype(uint64_t, s) then
        return s
    elseif the_type == 'cdata' and ctype('int64_t', s) then
        return s < 0 and cast(uint64_t, -s) or cast(uint64_t, s)
    end
end

M.tostring = to_s

local epoch = cast(uint64_t, constants.discord_epoch) * 1000ULL

--- Computes the UNIX timestamp of a given uint64, using discord's bitfield format.
-- @tparam string|number s The snowflake.
-- @treturn integer The timestamp.
function M.timestamp(s)
    return (rshift(M.touint(s) , 22) + epoch) / 1000ULL
end

--- Creates an artificial snowflake from a given UNIX timestamp.
-- @tparam[opt=current time] integer s The timestamp.
-- @treturn integer The resulting snowflake.
function M.fromtime(s)
    s = (s or M.touint(time())) * 1000ULL
    return lshift(s - epoch,  22)
end

--- Gets the timestamp, worker ID, process ID and increment from a snowflake.
-- @tparam number|string s The snowflake.
-- @treturn table
function M.decompose(s)
    s = M.touint(s)
    return {
         timestamp = M.timestamp(s)
        ,worker = rshift(band(s , 0x3E0000), 17)
        ,pid = rshift(band(s , 0x1F000) , 12)
        ,increment = band(s , 0xFFF)
    }
end

local inc = -1LL

--- Creates an artifical snowflake from the given timestamp, worker and pid.
-- @int s The timestamp.
-- @int worker The worker ID.
-- @int pid The process ID.
-- @int[opt] incr The increment. An internal incremented value is used if one is not provided.
-- @treturn integer The snowflake.
function M.synthesize(s, worker, pid, incr)
    inc = band((inc + 1) , 0xFFF)
    incr = band((incr or inc) ,  0xFFF)
    worker = lshift(band((worker or 0) , 63) , 17)
    pid = lshift(band((pid or 0) , 63) , 12)
    return bor(M.fromtime(s) , worker , pid , incr)
end

---sort two snowflake objects.
function M.snowflake_sort(i,j) return M.touint(i.id) < M.touint(j.id) end

---sort two snowflake ids.
function M.id_sort(i,j) return M.touint(i) < M.touint(j) end

return M