local err   = error
local getm  = getmetatable
local iter  = pairs
local iiter = ipairs
local setm  = setmetatable
local to_s  = tostring
local type  = type

local insert = table.insert
local unpack = table.unpack

local encode   = require"lacord.util.json".encode
local map      = require"lacord.util".map
local map_bang = require"lacord.util".map_bang
local f_iter   = require"lacord.util".selected_pairs
local numbers  = require"lacord.models.magic-numbers"

local types             = numbers.command_type
local option_types      = numbers.command_option_type
local option_type_names = numbers.command_option_type_names
local channel_types      = numbers.channel_type
local channel_type_names = numbers.channel_type_names

local _ENV = {}


local command = {__lacord_content_type = "application/json", __name = "lacord.command"}
      command.__index = command

local option = {__name = "lacord.option"}
      option.__index = option


local value_option = function(x) return x > option_types.SUB_COMMANDS end

local function try_localize(thing, info)
    local mt = getm(thing)
    if mt.__lacord_localize then
        return mt:__lacord_localize(thing, info)
    else
        return to_s(thing)
    end
end

local function to_channeltype(x) local xstr = to_s(x)
    if channel_types[xstr] then return channel_types[xstr]
    elseif channel_type_names[x] then return x
    end
end

local function run_methods(self, ctor, flat)
    for k , v in iter(ctor) do
        if flat and flat[k] then
            self[k](self, unpack(v))
        else
            self[k](self, v)
        end
    end
end


function slash(t)
    local self = setm({_type = types.CHAT}, command)
    if t then run_methods(self, t) end
    return self
end


function command:name(name)
    self._name = name
    return self
end


function command:description(name)
    self._description = name
    return self
end

local flatmethods = {
    choice = true,
    filter = true
}
function command:_option(_type, name, description)
    if self._type ~= types.CHAT then return self end
    if not self._options then self._options = {} end

    if option_types[_type] then _type = option_types[_type]
    elseif not option_type_names[_type] then
        warn("lacord.command: Unknown command type "..to_s(_type))
    end

    local opt = setm({_type = _type}, option)
    insert(self._options, opt)

    local mtn = getm(name)

    if type(name) == 'table' and not (mtn and mtn.__lacord_localize) then
        run_methods(opt, name, flatmethods)
    else
        opt._name = name
        opt._description = description
    end

    return opt
end


function command:permissions(bits)
    self._permissions = to_s(bits)
    return self
end


function command:accept_dms(value)
    self._accept_dms = not not value
    return self
end


local function command_payload(self, was_sub)
    local typ = was_sub or self._type

    local info = {
        options = self._options and #self._options
    }

    local name, localized = try_localize(self._name, info)
    local out = {
        name = name,
        name_localizations = localized,
        type = typ,
        default_member_permissions = self._permissions,
    }

    if self._accept_dms then
        out.dm_permission = self._accept_dms
    end

    if was_sub or typ < types.APP_COMMAND then
        local desc, localized2 = try_localize(self._description, info)
        out.description = desc
        out.description_localizations = localized2
        out.options = self._options and map(option.payload, self._options) or nil
    elseif typ < types.CONTEXT_COMMAND then
        out.description = ""
    end

    return out
end

command.__lacord_payload = function(self) return encode(command_payload(self)) end


for name, value in f_iter(value_option,option_types) do
    command[name:lower()] = function(self, ...)
        return command._option(self, value, ...)
    end
end

function option:name(name) self._name = name return self end
function option:description(name) self._description = name return self end


function option:choice(display_name, value, ...)
    self._choices = self._choices or {}
    local name, localized = try_localize(display_name, {value = value})

    insert(self._choices, {
        name = name,
        name_localizations = localized,
        value = value
    })

    if ... then return self:choice(...)
    else return self
    end
end

function option:filter(...)
    self._channel_types = map_bang(to_channeltype, {...})
    return self
end

function option:optional() self._required = false return self end

function option:required() self._required = true return self end

function option:payload()
    local typ = self._type
    local info = {
        choices = self._choices and #self._choices or 0,
        min_value = self._min,
        max_value = self._max,
        min_length = self._min,
        max_length = self._max,
    }
    local name, localized = try_localize(self._name, info)
    local desc, localized2 = try_localize(self._description, info)

    local payload = {
        type = typ,
        name = name,
        name_localizations = localized,
        description = desc,
        description_localizations = localized2,
        channel_types = self._channel_types,
        choices = self._choices,
        min_value = self._min,
        max_value = self._max,
        min_length = self._min,
        max_length = self._max,
        autocomplete = (not self._choices) and self._autocomplete
    }

    if self._required ~= nil then payload.required = self._required end

    return payload
end


local groupcommand = {__name = "lacord.command.group", __lacord_content_type = "application/json"}
      groupcommand.__index = groupcommand

function group(t)
    local self = setm({_type = types.CHAT, _commands = {}}, groupcommand)
    if t then run_methods(self, t) end
    return self
end

function groupcommand:add(C)
    if (getm(C) == command and C._type == types.CHAT) or getm(C) == groupcommand then
        insert(self._commands, C)
    else
        return err("lacord.command: Only chat commands – or groups – can be members of a command group.")
    end
    return self
end


for _, name in iiter{'name', 'description', 'permissions', 'accept_dms'} do
    groupcommand[name] = command[name]
end

local group_payload
local function sub_payload(cmd)
    if getm(cmd) == command then
        return command_payload(cmd, option_types.SUB_COMMAND)
    else
        return group_payload(cmd, option_types.SUB_COMMAND_GROUP)
    end
end

function group_payload(self, typ)
    local info = {
        options = self._options and #self._options
    }
    local name, localized = try_localize(self._name, info)
    local desc, localized2 = try_localize(self._description, info)
    local out = {
        name = name,
        name_localizations = localized,
        description = desc,
        description_localizations = localized2,
        type = typ or self._type,
        default_member_permissions = self._permissions,
    }

    if self._accept_dms then
        out.dm_permission = self._accept_dms
    end

    out.options = map(sub_payload, self._commands)

    return out
end

groupcommand.__lacord_payload = function(self) return encode(group_payload(self)) end


function context(t)
    local self = setm({}, command)
    if t then run_methods(self, t) end
    return self
end

function command:target(target)
    self._type = target == 'user' and types.USER_CONTEXT or types.MESSAGE_CONTEXT
    return self
end


return _ENV