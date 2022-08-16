local err  = error
local getm = getmetatable
local to_s = tostring
local typ  = type

local getapi = require"lacord.models.context".api


local _ENV = {}

function mention(object)
    local mt = getm(object)

    if mt and mt.__lacord_model_mention then
        return mt.__lacord_model_mention(object)
    elseif mt then
        return mt.__lacord_model .. ": " .. mt.__lacord_model_id(object)
    else
        return to_s(object)
    end
end

local function send(object, msg, files, ctx, loop)
    local mt = getm(object)
    if mt then
        local def = mt.__lacord_model_defer
        if mt.__lacord_model_send then
            local api = getapi(ctx, loop)
            if typ(msg) == 'string' then msg = {content = msg} end
            return mt.__lacord_model_send(object, api, msg, files)
        elseif typ(def) == 'string' then
            return send(mt[def](object), msg, files, ctx, loop)
        elseif def and def.send then
            return send(mt[def.send](object), msg, files, ctx, loop)
        end
    end
    return err("Cannot send messages to a "..to_s(object)..".")
end

_ENV.send = send

local function model_id_rec(mt, object, t, ...)
    if mt.__lacord_model == t then
        return mt.__lacord_model_id(object), t
    elseif ... then
        return model_id_rec(mt, object, ...)
    else
        return false, t
    end
end

local function model_id(object, ...)
    local t = typ(object)
    if t == 'string' then
        return object
    elseif  t == 'number'  then
        return ("%u"):format(object)
    end

    local mt = getm(object)
    if ... then
        if mt and mt.__lacord_model then
            local def = mt.__lacord_model_defer
            local tyid, what = model_id_rec(mt, object, ...)
            if tyid then return tyid
            elseif typ(def) == 'string' then
                return model_id(mt[def](object), ...)
            elseif def and def.id then
                return model_id(mt[def.id](object), ...)
            else
                return err("lacord.models: Object "..to_s(object).." was not the right kind of model. Expecting: "..what..".")
            end
        end
    elseif mt and mt.__lacord_model_id then
        return mt.__lacord_model_id(object)
    end
    return err("lacord.models: Object "..to_s(object).." does not implement the model protocol.")
end

_ENV.model_id = model_id

local function update(object, edit, ctx, loop)
    local mt = getm(object)
    if mt then
        local def = mt.__lacord_model_defer
        if mt.__lacord_model_update then
            local api = getapi(ctx, loop)
            return mt.__lacord_model_update(object, api, edit)
        elseif typ(def) == 'string' then
            return update(mt[def](object), edit, ctx, loop)
        elseif def and def.update then
            return update(mt[def.update](object), edit, ctx, loop)
        end
    end
    return err("Cannot update "..to_s(object)..".")
end

local function delete(object, ctx, loop)
    local mt = getm(object)
    if mt and mt.__lacord_model_delete then
        local api = getapi(ctx, loop)
        return mt.__lacord_model_delete(object, api)
    end
    return err("Cannot delete "..to_s(object)..".")
end

local function resolve_rec(object, mt, t, ...)

    if mt.__lacord_model == t and not mt.__lacord_model_partial then
        return object, t
    else
        local creator = '__lacord_'..t
        if mt[creator] then return mt[creator](object), t
        elseif ... then return resolve_rec(object, mt, ...)
        end
    end
end

function resolve(object, ...)
    if ... then
        local mt = getm(object)
        if mt then
            return resolve_rec(object, mt, ...)
        end
    else
        local mt = getm(object)
        return mt and not mt.__lacord_model_partial and mt.__lacord_model and object
    end
end

_ENV.update = update
_ENV.delete = delete

return _ENV