local setm  = setmetatable
local to_s  = tostring
local type  = type

local min = math.min
local max = math.max

local insert = table.insert

local numbers        = require"lacord.models.magic-numbers"
local map            = require"lacord.util".map
local model_id       = require"lacord.models.methods".model_id
local run_methods    = require"lacord.util".run_methods
local common_methods = require"lacord.ui.common"

local types = numbers.component_type


local _ENV = {}


local select = {__name = "lacord.ui.select-menu"}
      select.__index = select


function new(t)
    local self = setm({_selections = {}, _n = 0}, select)
    if t then run_methods(self, t) end
    return self
end


function select:placeholder(str)
    self._placeholder = str
    return self
end


function select:min(n)
    self._min = min(max(n, 0), 25)
    return self
end


function select:max(n)
    self._max = min(max(n, 1), 25)
    return self
end


local selection = {__name = "lacord.ui.selection"}
      selection.__index = selection


function select:selection(t)
    if self._n < 25 then
        local sel = setm({}, selection)
        if t then run_methods(sel, t) end
        self._n = self._n + 1
        insert(self._selections, sel)
        return sel
    end
end


function selection:label(l)
    self._label = l
    return self
end


function selection:value(v)
    self._value = to_s(v)
    return self
end


function selection:description(s)
    self._description = s
    return self
end


function selection:emoji(name, id, animated)
    self._emoji = {
        name = name,
        id = model_id(id, 'emoji'),
        animated = not not animated
    }
    return self
end


function selection:default(v)
    self._default = not not v
    return self
end


function selection:payload(...)
    return {
        label = self:run('_label', ...),
        value = self:run('_value', ...),
        description = self:run('_description', ...),
        emoji = self:run('_emoji', ...),
        default = self:run('_default', ...)
    }
end

common_methods(select, {'_placeholder', '_min', '_max'},
    function(new, old)
        for i = 1, #old._selections do
            local olds = old._selections[i]
            local news = new:selection{
                label = olds._label,
                value = olds._value,
                description = olds._description,
                default = olds._default,
            }
            if olds._emoji then
                if type(olds._emoji) == 'function' then
                    news:emoji(olds._emoji)
                else
                    news:emoji(
                        olds._emoji.name,
                        olds._emoji.id,
                        olds._emoji.animated)
                end
            end
        end
        return new
    end)


selection.run = select.run


function select:__lacord_ui(...)
    return {
        type = types.SELECT_MENU,
        custom_id = self:run('_custom_id', ...),
        placeholder = self:run('_placeholder', ...),
        min_values = self:run('_min', ...),
        max_values = self:run('_max', ...),
        disabled   = self:run('_disabled', ...),
        options = map(selection.payload, self._selections, ...)
    }
end

return _ENV

