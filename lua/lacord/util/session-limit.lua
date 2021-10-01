local cond = require"cqueues.condition"
local me = require"cqueues".running
local sleep = require"cqueues".sleep
local setm = setmetatable
local err = error

local _ENV = {}

--luacheck: ignore 111

local session_limit = {__name = "lacord.session-limit"}

session_limit.__index = session_limit

function new(availability)
    return setm({
        v = availability,
        cv = cond.new(false),
    }, session_limit)
end

function session_limit:exit()
    self.v = self.v + 1
    self.cv:signal(1)
end

function session_limit:enter()
    while self.v <= 0 do self.cv:wait() end
    self.v = self.v - 1
end

local waiter = function(s, sc) sleep(sc) s:exit() end
function session_limit:exit_after(secs)
    me():wrap(waiter, self, secs)
end

return _ENV
