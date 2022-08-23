local i18n = require"internationalize"
local locales = require"lacord.util.locales"

local translator = {__name = "lacord.translator"}

function translator:__index(k)
    if translator[k] then return translator[k]
    elseif self.instance[k] then
        local function method(this, ...)
            return this.instance[k](this.instance, ...)
        end
        self[k] = method
        return method
    end
end

function translator:__call(str)
    return setmetatable({str}, self)
end

function translator:add(t)
    for k, v in pairs(t) do
        self.ctx[k] = v
    end
end

local function __lacord_localize(T, locale_str, info)
    local ctx = {}

    for k ,v in pairs(T.ctx) do
        ctx[k] = v
    end
    for k ,v in pairs(info) do
        ctx[k] = v
    end

    local out = T:translations_from(locale_str[1], ctx, locales)

    local default = T.instance.locale
    local rest, primary, set = {}

    for _ , result in ipairs(out) do
        local loc, value, used = result[1], result[2], result[3]

        if loc == default or used == default then
            primary = value
        elseif value ~= primary then
            rest[loc] = value
            set = true
        end
    end

    return primary, set and rest or nil
end

local function new(default_locale)
    local instance = i18n(default_locale)

    return setmetatable({instance = instance, ctx = {}, __lacord_localize = __lacord_localize}, translator)
end

return {
    new = new
}

