local err   = error
local getm  = getmetatable
local iter  = pairs
local iiter = ipairs
local setm  = setmetatable
local to_s  = tostring

local insert = table.insert
local unpack = table.unpack

local context  = require"lacord.models.context"
local encode   = require"lacord.util.json".encode
local guild    = require"lacord.models.guild"
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
    if mt and mt.__lacord_localize then
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


local unpack_command = {}
function slash(t)
    local self = setm({_type = types.CHAT}, command)
    if t then run_methods(self, t, unpack_command) end
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
function command:_option(_type, t)
    if self._type ~= types.CHAT then return self end
    if not self._options then self._options = {} end

    if option_types[_type] then _type = option_types[_type]
    elseif not option_type_names[_type] then
        warn("lacord.command: Unknown command type "..to_s(_type))
    end

    local opt = setm({_type = _type}, option)
    insert(self._options, opt)

    run_methods(opt, t, flatmethods)

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
        dm_permission = not not self._accept_dms
    }


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
    local method = name:lower()
    command[method] = function(self, ...)
        return command._option(self, value, ...)
    end
    command[method.."s"] = function(self, ...)
        local payloads = {...}
        for i = 1, #payloads do
            command._option(self, value, payloads[i])
        end
    end
    unpack_command[method.."s"] = true
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


local unpack_group = {add = true}
function group(t)
    local self = setm({_type = types.CHAT, _commands = {}}, groupcommand)
    if t then run_methods(self, t, unpack_group) end
    return self
end


function groupcommand:add(C, ...)
    if (getm(C) == command and C._type == types.CHAT) or getm(C) == groupcommand then
        insert(self._commands, C)
    else
        return err("lacord.command: Only chat commands – or groups – can be members of a command group.")
    end

    if ... then
        return self:add(...)
    else
        return self
    end
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


function _ENV.context(t)
    local self = setm({}, command)
    if t then run_methods(self, t) end
    return self
end


function command:target(target)
    self._type = target == 'user' and types.USER_CONTEXT or types.MESSAGE_CONTEXT
    return self
end


function _ENV.type(c)
    local mt = getm(c)
    return mt == command and 'command' or mt == groupcommand and 'group' or nil
end


--- Converts a command into a JSON table
local function resolve_list(c)
    local mt = getm(c)
    if mt == command then return command_payload(c)
    elseif mt == groupcommand then return group_payload(c)
    end
end


local function deploy_guilds(req, guilds, appid)
    for id, commands in iter(guilds) do
        req:bulk_overwrite_guild_application_commands(appid, id, map(resolve_list, commands))
    end
end


local function load_commands(list)
    for i = 1, #list do
        local cmd = list[i]
        if cmd.guild_id then
            guild.set_guild_property('command', cmd.guild_id, cmd.id)
        else
            context.property('global-command', cmd.name, cmd.id)
        end
        context.store('command', cmd)
        cmd._full_names = _ENV.full_names(cmd)
        if cmd._full_names.children then cmd._group = true end
    end
end


local function deployer(api, load_commands_, global_commands, guild_commands, appid)
    appid = appid

    local R = api:capture():bulk_overwrite_global_application_commands(
        appid,
        map(resolve_list, global_commands)
    )

    if guild_commands then R:continue(deploy_guilds, guild_commands, appid) end

    if R.success then

        load_commands_(R.result[1], global_commands)

        for i = 2, #R.result do
            local list = R.result[i]
            load_commands_(list, guild_commands[list[1].guild_id])
        end

        return true
    else return nil, R.error
    end
end


local function loader(api, load_commands_, guild_id, appid)
    appid =  appid

    if guild_id then
        local success, list, e = api:get_guild_application_commands(appid, guild_id)
        if success then
            load_commands_(list)
            return true
        else
            return nil, e
        end
    else
        local success, list, e = api:get_global_application_commands(appid)
        if success then
            load_commands_(list)
            return true
        else
            return nil, e
        end
    end
end


function deploy(appid, gbl, gld)
    return deployer(context.api(), load_commands, gbl, gld, appid)
end


function load(appid, guild_id)
    return loader(context.api(), load_commands, guild_id, appid)
end

_ENV.standalone = {}

function standalone.deploy(api, appid, gbl, gld)
    local out = {global = {}, guild = {}}
    local function load_commands_(list)
        for i = 1, #list do
            local cmd = list[i]
            cmd._full_names = _ENV.full_names(cmd)
            if cmd._full_names.children then cmd._group = true end
            if cmd.guild_id then
                out.guild[cmd.guild_id] = out.guild[cmd.guild_id] or {}
                out.guild[cmd.guild_id][cmd.id] = cmd
            else
                out.global[cmd.id] = cmd
            end
        end
    end
    if deployer(api, load_commands_, gbl, gld, appid) then
        return out
    end
end

function standalone.load(api, appid, guild_id, out)
    out = out or {global = {}, guild = {}}
    local function load_commands_(list)
        for i = 1, #list do
            local cmd = list[i]
            cmd._full_names = _ENV.full_names(cmd)
            if cmd._full_names.children then cmd._group = true end
            if cmd.guild_id then
                out.guild[cmd.guild_id] = out.guild[cmd.guild_id] or {}
                out.guild[cmd.guild_id][cmd.id] = cmd
            else
                out.global[cmd.id] = cmd
            end
        end
    end
    if loader(api, load_commands_, guild_id, appid) then
        return out
    end
end


function full_name(i)
    local cmd = i.data
    if not cmd.options then return cmd.name, cmd.name
    else
        local ot = cmd.options[1].type
        if ot == option_types.SUB_COMMAND then
            local leaf = cmd.options[1].name
            return cmd.name .. " " .. leaf, leaf
        elseif ot == option_types.SUB_COMMAND_GROUP then
            local branch = cmd.name.." "..cmd.options[1].name
            local leaf = cmd.options[1].options[1].name
            return branch.." "..leaf, leaf, branch
        end
    end
end


local function full_names2(id, out, cmd, parent, exit)
    local names = {id = id, name = cmd.name, parent = parent and parent.id}

    if parent then
        parent.children = parent.children or {}
        parent.children[id] = cmd.name
    end

    out[id] = names

    if not cmd.options or exit then
        return out
    else
        for i = 1, #cmd.options do
            local o = cmd.options[i]
            if o.type == option_types.SUB_COMMAND then
                id = id + 1
                full_names2(id, out, o, names, true)
            elseif o.type == option_types.SUB_COMMAND_GROUP then
                id = id + 1
                full_names2(id, out, o, names)
            end
        end
        return out
    end
end

function full_names(cmd)
    local mt = getm(cmd)
    if mt == command then
        return {{name = cmd._name}}
    elseif mt == groupcommand then
        cmd = group_payload(cmd)
    end

    return full_names2(1, {}, cmd)
end

_ENV.full_names = full_names


return _ENV