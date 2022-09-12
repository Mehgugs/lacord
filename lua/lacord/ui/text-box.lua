local setm  = setmetatable

local numbers        = require"lacord.models.magic-numbers"
local run_methods    = require"lacord.util".run_methods
local common_methods = require"lacord.ui.common"

local types = numbers.component_type
local styles = numbers.textbox_style
local style_names = numbers.textbox_style_names


local _ENV = {}


local textbox = {__name = "lacord.ui.text-box"}

function new(t)
    local self = setm({}, textbox)
    if t then run_methods(self, t) end
    return self
end


function textbox:style(s) s = style_names[s] and s or styles[s]
    self._style = s
    return self
end


function textbox:label(l)
    self._label = l
    return self
end


function textbox:min(n)
    self._min = n
    return self
end


function textbox:max(n)
    self._max = n
    return self
end


function textbox:required(v)
    self._required = not not v
    return self
end


function textbox:value(v)
    self._value = v
    return self
end


function textbox:placeholder(v)
    self._placeholder = v
    return self
end


function textbox:__lacord_ui(...)
    return {
        type = types.TEXT_BOX,
        custom_id = self:run('_custom_id', ...),
        style = self:run('_style', ...),
        label = self:run('_label', ...),
        min_length = self:run('_min', ...),
        max_length = self:run('_max', ...),
        required = self:run('_required', ...),
        value = self:run('_value', ...),
        placeholder = self:run('_placeholder', ...)
    }
end


function textbox:__lacord_ui_name(name)
    self._name = name
    return self
end

common_methods(textbox, {'_style', '_label', '_min', '_max', '_required', '_value', '_placeholder'}, nil, true)


return _ENV