local setm  = setmetatable
local type  = type

local numbers        = require"lacord.models.magic-numbers"
local model_id       = require"lacord.models.methods".model_id
local run_methods    = require"lacord.util".run_methods
local common_methods = require"lacord.ui.common"

local types = numbers.component_type
local styles = numbers.button_style
local style_names = numbers.button_style_names

local _ENV = {}


local button = {__name = "lacord.ui.button"}
      button.__index = button


function new(t)
    local self = setm({_style = styles.SECONDARY}, button)
    if t then run_methods(self, t) end
    return self
end


function button:style(s)
    if type(s) == 'function' then
        self._style = s
    else
        if self._style == styles.LINK then return self end
        s = style_names[s] and s or styles[s]
        if s < styles.INTERACTIVE then
            self._style = s
        end
    end
    return self
end


function button:label(l)
    self._label = l
    return self
end


function button:emoji(name, id, animated)
    if type(name) == 'function' then
        self._emoji = name
    else
        self._emoji = {
            name = name,
            id = id and model_id(id, 'emoji'),
            animated = (not not animated) or nil
        }
    end
    return self
end


function button:__lacord_ui(...)
    return {
        type = types.BUTTON,
        custom_id = self:run('_custom_id', ...),
        style = self:run('_style', ...),
        label = self:run('_label', ...),
        emoji = self:run('_emoji', ...),
        disabled = self:run('_disabled', ...),
        url = self:run('_url', ...)
    }
end


common_methods(button, {'_style', '_label', '_emoji'})


function hyperlink(url, t)
    local self = setm({_url = url, _style = styles.LINK}, button)

    if t then run_methods(self, t) end

    return self
end


return _ENV