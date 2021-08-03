--- A minimal mutex implementation.
-- @module util.mutex

local cqueues = require"cqueues"
local sleep = cqueues.sleep
local monotime = cqueues.monotime
local me = cqueues.running
local cond = require"cqueues.condition"
local setmetatable = setmetatable
local max = math.max

local _ENV = {}

local mutex = {}

mutex.__index = mutex
mutex.__name  = 'lacord.mutex'

--- Locks the mutex.
-- @tparam mutex self
-- @tparam[opt] number timeout an optional timeout to wait.
function mutex:lock(timeout)
    self:check_hangover()
    if self.inuse then
        self.inuse = self.pollfd:wait(timeout)
        self:check_hangover()
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

local function unlockAt(self, deadline)
    sleep(max(0, deadline - monotime()))
    self:unlock()
end

--- Unlocks the mutex at the specified point in time in seconds.
-- @tparam mutex self
-- @tparam number time The time to unlock at, in seconds.
function mutex:unlock_at(deadline)
    me():wrap(unlockAt, self, deadline)
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

function mutex:set_hangover(delay)
    if self.hangover then
        self.hangover = max(self.hangover, monotime() + delay)
    else
        self.hangover = monotime() + delay
    end
end

function mutex:check_hangover()
    local the_hangover = self.hangover
    if the_hangover and the_hangover > monotime() then
        sleep(the_hangover - monotime())
        if the_hangover ~= self.hangover then return self:check_hangover() end
    end
end

--- Creates a new mutex
-- @treturn mutex
function new()
    return setmetatable({
         pollfd = cond.new()
        ,inuse= false
    }, mutex)
end

--- Mutex Object.
-- @table mutex
-- @within Objects
-- @bool inuse
-- @field cond The condition variable.

return _ENV