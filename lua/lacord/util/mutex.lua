--- A minimal mutex implementation.
-- @module util.mutex

local cqueues = require"cqueues"
local sleep = cqueues.sleep
local me = cqueues.running
local cond = require"cqueues.condition"
local setmetatable = setmetatable

local _ENV = {}

__index = _ENV

--- Locks the mutex.
-- @tparam mutex self
-- @tparam[opt] number timeout an optional timeout to wait.
function lock(self, timeout)
    if self.inuse then
        self.inuse = self.pollfd:wait(timeout)
        local handoff = self.handoff
        if handoff then
            handoff:wait()
            self.handoff = nil
        end
    else
        self.inuse = true
    end
end

--- Unlocks the mutex.
-- @tparam mutex self
function unlock(self)
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
function unlock_after(self, time)
    me():wrap(unlockAfter, self, time)
end

local function defered(self)
    sleep()
    self:unlock()
end

--- Unlocks the mutex on the next schedule.
-- @tparam mutex self
function defer_unlock(self)
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
-- All functions which take a mutex as their first argument can be called from the mutex in method form.
-- @table mutex
-- @within Objects
-- @bool inuse
-- @field cond The condition variable.

return _ENV