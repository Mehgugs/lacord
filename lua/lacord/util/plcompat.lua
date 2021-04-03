--- Compatability modules for penlight based dependencies.
-- @module util.plcompat

--[[
    Copyright (C) 2009-2016 Steve Donovan, David Manura.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT
SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.
]]

local error = error
local getmetatable, setmetatable = getmetatable, setmetatable
local pairs = pairs
local rawget, rawset = rawget, rawset
local tostring = tostring
local type = type

local _ENV = {}

-- class interface from pl.class --

local function call_ctor (c,obj,...)
    -- nice alias for the base class ctor
    local base = rawget(c,'_base')
    if base then
        local parent_ctor = rawget(base,'_init')
        while not parent_ctor do
            base = rawget(base,'_base')
            if not base then break end
            parent_ctor = rawget(base,'_init')
        end
        if parent_ctor then
            rawset(obj,'super',function(obj,...)
                call_ctor(base,obj,...)
            end)
        end
    end
    local res = c._init(obj,...)
    rawset(obj,'super',nil)
    return res
end

local function is_a(self,klass)
    if klass == nil then
        -- no class provided, so return the class this instance is derived from
        return getmetatable(self)
    end
    local m = getmetatable(self)
    if not m then return false end --*can't be an object!
    while m do
        if m == klass then return true end
        m = rawget(m,'_base')
    end
    return false
end

local function class_of(klass,obj)
    if type(klass) ~= 'table' or not rawget(klass,'is_a') then return false end
    return klass.is_a(obj,klass)
end

local function cast (klass, obj)
    return setmetatable(obj,klass)
end

local function _class_tostring (obj)
    local mt = obj._class
    local name = rawget(mt,'_name')
    setmetatable(obj,nil)
    local str = tostring(obj)
    setmetatable(obj,mt)
    if name then str = name ..str:gsub('table','') end
    return str
end

local function tupdate(td,ts,dont_override)
    for k,v in pairs(ts) do
        if not dont_override or td[k] == nil then
            td[k] = v
        end
    end
end

local function _class(base,c_arg,c)
    -- the class `c` will be the metatable for all its objects,
    -- and they will look up their methods in it.
    local mt = {}   -- a metatable for the class to support __call and _handler
    -- can define class by passing it a plain table of methods
    local plain = type(base) == 'table' and not getmetatable(base)
    if plain then
        c = base
        base = c._base
    else
        c = c or {}
    end

    if type(base) == 'table' then
        -- our new class is a shallow copy of the base class!
        -- but be careful not to wipe out any methods we have been given at this point!
        tupdate(c,base,plain)
        c._base = base
        -- inherit the 'not found' handler, if present
        if rawget(c,'_handler') then mt.__index = c._handler end
    elseif base ~= nil then
        error("must derive from a table type",3)
    end

    c.__index = c
    setmetatable(c,mt)
    if not plain then
        c._init = nil
    end

    if base and rawget(base,'_class_init') then
        base._class_init(c,c_arg)
    end

    -- expose a ctor which can be called by <classname>(<args>)
    mt.__call = function(class_tbl,...)
        local obj
        if rawget(c,'_create') then obj = c._create(...) end
        if not obj then obj = {} end
        setmetatable(obj,c)

        if rawget(c,'_init') then -- explicit constructor
            local res = call_ctor(c,obj,...)
            if res then -- _if_ a ctor returns a value, it becomes the object...
                obj = res
                setmetatable(obj,c)
            end
        elseif base and rawget(base,'_init') then -- default constructor
            -- make sure that any stuff from the base class is initialized!
            call_ctor(base,obj,...)
        end

        if base and rawget(base,'_post_init') then
            base._post_init(obj)
        end

        return obj
    end
    -- Call Class.catch to set a handler for methods/properties not found in the class!
    c.catch = function(self, handler)
        if type(self) == "function" then
            -- called using . instead of :
            handler = self
        end
        c._handler = handler
        mt.__index = handler
    end
    c.is_a = is_a
    c.class_of = class_of
    c.cast = cast
    c._class = c

    if not rawget(c,'__tostring') then
        c.__tostring = _class_tostring
    end

    return c
end

class = setmetatable({}, {__call = function(_, ...)
    return _class(...)
end})

class.properties = class()

function class.properties._class_init(klass)
    klass.__index = function(t,key)
        -- normal class lookup!
        local v = klass[key]
        if v then return v end
        -- is it a getter?
        v = rawget(klass,'get_'..key)
        if v then
            return v(t)
        end
        -- is it a field?
        return rawget(t,'_'..key)
    end
    klass.__newindex = function (t,key,value)
        -- if there's a setter, use that, otherwise directly set table
        local p = 'set_'..key
        local setter = klass[p]
        if setter then
            setter(t,value)
        else
            rawset(t,key,value)
        end
    end
end

-- assertion functions from pl.utils --

function assert_arg (n,val,tp,verify,msg,lev)
    if type(val) ~= tp then
        error(("argument %d expected a '%s', got a '%s'"):format(n,tp,type(val)),lev or 2)
    end
    if verify and not verify(val) then
        error(("argument %d: '%s' %s"):format(n,val,msg),lev or 2)
    end
    return val
end

function assert_string (n, val)
    return assert_arg(n,val,'string',nil,nil,3)
end

return _ENV