--- A minimal mutex implementation.
-- @module util.mutex

local cqueues = require"cqueues"
local sleep = cqueues.sleep
local me = cqueues.running
local cond = require"cqueues.condition"
local setmetatable = setmetatable

local _ENV = {}

local mutex = {}

mutex.__index = mutex
mutex.__name  = 'lacord.mutex'

--- Locks the mutex.
-- @tparam mutex self
-- @tparam[opt] number timeout an optional timeout to wait.
function mutex:lock(timeout)
    if self.inuse then
        self.inuse = self.pollfd:wait(timeout)
    else
        self.inuse = true
    end
end

--- Unlocks the mutex.
-- @tparam mutex self
function mutex:unlock()
    if self.inuse then
        self.inuse = false
        self.pollfd:signal(1)
    end
end

local function unlockAfter(self, time)
    sleep(time)
    self:unlock()
end

--- Unlocks the mutex after the specified time in seconds.
-- @tparam mutex self
-- @tparam number time The time to unlock after, in seconds.
function mutex:unlock_after(time)
    me():wrap(unlockAfter, self, time)
end

local function defered(self)
    sleep()
    self:unlock()
end

--- Unlocks the mutex on the next schedule.
-- @tparam mutex self
function mutex:defer_unlock()
    me():wrap(defered, self)
end

--- Creates a new mutex
-- @treturn mutex
function new()
    return setmetatable({
         pollfd = cond.new()
        ,inuse= false
    }, _ENV)
end

--- Mutex Object.
-- @table mutex
-- @within Objects
-- @bool inuse
-- @field cond The condition variable.

return _ENV