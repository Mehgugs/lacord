local err  = error
local getm = getmetatable
local to_s = tostring

local upper = string.upper

local set = require"lacord.util".set

local resolve  = require"lacord.models.methods".resolve
local model_id = require"lacord.models.methods".model_id

local _ENV = {}

function methodify(metatable, methods, exclude, ...)
    local props = exclude and set(exclude, ...)
    if props then
        function metatable:__index(key)
            if props[key] then
                return methods[key](self)
            else
                return methods[key]
            end
        end
    else
        metatable.__index = methods
    end
end


function tostring(self)
    local mt = getm(self)
    local header = (mt.__lacord_model or 'model'):gsub("^.", upper, 1)

    if mt.__lacord_model_mention then
        header = header .. " " .. mt.__lacord_model_mention(self)
    elseif mt.__lacord_model_id then
        header = header .. " <" .. mt.__lacord_model_id(self) .. ">"
    end
    return header
end

function model_selectors(name, mt)
    local function the_model(obj)
        if getm(obj) == mt then return obj end
        return resolve(obj, name) or err("Object " .. to_s(obj) .. " does not implement the " .. name .. " protocol!")
    end

    local function the_id(obj)
        if getm(obj) == mt then return obj.id end
        return model_id(obj, name)
    end

    return the_model, the_id
end

return _ENV
