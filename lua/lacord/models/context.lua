local getm = getmetatable
local setm = setmetatable
local err  = error
local to_s = tostring

local running = require"cqueues".running

local _ENV = {}

local cache = setm({}, {__mode = 'k'})

function attach(loop, ctx)
    cache[loop] = ctx
    return ctx
end

local function get()
    local loop = running()
    return cache[loop], loop
end

local function getfrom(loop)
    return cache[loop]
end

_ENV.get = get
_ENV.getfrom = getfrom

-- function checkset(ctx)
--     local ctx_, loop = get()
--     if ctx_ ~= ctx then
--         cache[loop] = ctx
--     end
--     return ctx, loop
-- end

function api(ctx, loop)
    loop = loop or running()
    ctx = ctx or cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")

    local mt = getm(ctx)
    if mt and mt.__lacord_model_context then
        local handle = mt.__lacord_model_context(ctx)
        local hmt = getm(handle)
        if hmt and hmt.__lacord_is_api then return handle end
    end
    return err("lacord.models.context: ctx for " ..to_s(loop).." did not satisfy __lacord_model_context or __lacord_is_api.")
end

function create(ctx_or_type, type_or_data, data_, ...)
    local mt = getm(ctx_or_type)
    local type, data, ctx
    local onlydots

    if not (mt and mt.__lacord_model_context) then
        local loop = running()
        type = ctx_or_type
        data = type_or_data
        ctx = cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")
        mt = getm(ctx)
    else
        type = type_or_data
        data = data_
        onlydots = true
    end

    if mt.__lacord_model_context_create then
        if onlydots then
            return mt.__lacord_model_context_create(ctx, type, data, ...)
        else
            return mt.__lacord_model_context_create(ctx, type, data, data_, ...)
        end
    end
end

function request(ctx, ...) -- table, primary_id
    local loop = running()
    local mt = getm(ctx)
    local old

    if not (mt and mt.__lacord_model_context) then
        old = ctx
        ctx = cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")
        mt = getm(ctx)
    end

    if mt and mt.__lacord_model_context_request then
        if old then
            return mt.__lacord_model_context_request(ctx, old, ...)
        else
            return mt.__lacord_model_context_request(ctx, ...)
        end
    else
        return nil
    end
end

function store(ctx, ...)
    local loop = running()
    local mt = getm(ctx)
    local old

    if mt.__lacord_is_api then return nil end

    if not (mt and mt.__lacord_model_context) then
        old = ctx
        ctx = cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")
        mt = getm(ctx)
    end

    if mt and mt.__lacord_model_context_store then
        if old then
            return mt.__lacord_model_context_store(ctx, old, ...)
        else
            return mt.__lacord_model_context_store(ctx, ...)
        end
    else
        return nil
    end
end

function property(ctx, ...) -- secondary_table, secondary_id, value
    local loop = running()
    local mt = getm(ctx)
    local old

    if mt.__lacord_is_api then return nil end

    if not (mt and mt.__lacord_model_context) then
        old = ctx
        ctx = cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")
        mt = getm(ctx)
    end

    if mt and mt.__lacord_model_context_prop then
        if old then
            return mt.__lacord_model_context_prop(ctx, old, ...)
        else
            return mt.__lacord_model_context_prop(ctx, ...)
        end
    else
        return nil
    end
end

function upsert(ctx, ...) -- secondary_table, secondary_id, value
    local loop = running()
    local mt = getm(ctx)
    local old

    if mt.__lacord_is_api then return nil end

    if not (mt and mt.__lacord_model_context) then
        old = ctx
        ctx = cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")
        mt = getm(ctx)
    end

    if mt and mt.__lacord_model_context_upsert then
        if old then
            return mt.__lacord_model_context_upsert(ctx, old, ...)
        else
            return mt.__lacord_model_context_upsert(ctx, ...)
        end
    else
        return nil
    end
end

local property_clear = {}

_ENV.DEL = property_clear

local upserters = { }

function upserters.TABLE() return { } end
function upserters.COUNT() return 0 end
function upserters.VALUE(k) return function() return k end end

_ENV.upserters = upserters

function unstore(ctx, ...)
    local loop = running()
    local mt = getm(ctx)
    local old

    if mt.__lacord_is_api then return nil end

    if not (mt and mt.__lacord_model_context) then
        old = ctx
        ctx = cache[loop] or err("lacord.models.context: no model ctx available for "..to_s(loop)..".")
        mt = getm(ctx)
    end

    if mt and mt.__lacord_model_context_unstore then
        if old then
            return mt.__lacord_model_context_unstore(ctx, old, ...)
        else
            return mt.__lacord_model_context_unstore(ctx, ...)
        end
    else
        return nil
    end
end

local simple_mt = {}

function simple_mt:__lacord_model_context()
    return self[1]
end

function simple_mt:__lacord_model_context_create(type, data)
    local ctor = self[2][type]
    if ctor then
        local obj = ctor(data)
        simple_mt.__lacord_model_context_store(self, obj, type)
        return obj
    else
        return data
    end
end

function simple_mt:__lacord_model_context_request(table, primary_id)
    local mcache = self[table]
    if mcache then
        return primary_id and mcache[primary_id]
    end
end

function simple_mt:__lacord_model_context_store(object, table)
    local mcache = self[table]
    if mcache then
        mcache[object.id] = object
        return object.id
    end
end

function simple_mt:__lacord_model_context_unstore(table, primary_id)
    local mcache = self[table]
    if mcache then
        local obj = mcache[primary_id]
        mcache[primary_id] = nil
        return obj
    end
end

function simple_mt:__lacord_model_context_prop(table, k, v)
    local pcache = self.props[table]
    if pcache then
        if v ~= nil then
            goto set
        else
            if k == "*" or k == nil then return pcache else return pcache[k] end
        end
    elseif (not pcache) and v ~= nil then
        if k == '*' then
            self.props[table] = v
            return
        else
            pcache = {}
            self.props[table] = pcache
            goto set
        end
    else
        return nil
    end

    ::set::
    if v == property_clear then v = nil end
    if k == "*" then
        if v then
            self.props[table] = v
        end
        return pcache
    else
        local old = pcache[k]
        pcache[k] = v
        return old
    end
end

function simple_mt:__lacord_model_context_upsert(table, k, default)
    local pcache = self.props[table]
    if k == nil or k == "*" then err("lacord.models.context: Cannot upsert using key=*", 2) end
    if pcache then
        if pcache[k] then
            return pcache[k]
        else
            local new = default()
            pcache[k] = new
            return new
        end
    elseif not pcache then
        local new = default()
        pcache = {[k] = new}
        self.props[table] = pcache
        return new
    end
end

function simple_context(api, ctors)
    return setm({api, ctors; channel = {}, guild = {}, props = {}}, simple_mt)
end

return _ENV