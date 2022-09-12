local err   = error
local iter  = pairs
local iiter = ipairs
local to_s  = tostring
local typ   = type

local command  = require"lacord.command"
local context  = require"lacord.models.context"
local copy     = require"lacord.util".copy
local map_bang = require"lacord.util".map_bang
local methods  = require"lacord.models.methods"
local numbers  = require"lacord.models.magic-numbers"
local send_int = require"lacord.models.common.send-interaction"



local getapi   = context.api
local create   = context.create
local request  = context.request
local property = context.property

local modify   = methods.update
local model_id = methods.model_id
local resolve  = methods.resolve

local responses = numbers.interaction_response
local types     = numbers.interaction_type

local _ENV = {}

-- luacheck: ignore 111

--- General interaction functionality ---

function _ENV.channel(i)
    i = resolve(i, 'interaction')
    return i.channel_id and request('channel', i.channel_id)
end


function _ENV.guild(i)
    i = resolve(i, 'interaction')
    return i.guild_id and request('guild', i.guild_id)
end

function _ENV.invoker(i)
    i = resolve(i, 'interaction')
    return i.member and i.member.user or i.user
end

function state(i) i = resolve(i, 'interaction') return i._state end


function _ENV.send(i, msg, files)
    i = resolve(i, 'interaction')
    if typ(msg) == 'string' then msg = {content = msg} end
    return send_int(i, getapi(), msg, files)
end

_ENV.reply = _ENV.send


function _ENV.whisper(i, msg, files)
    i = resolve(i, 'interaction')
    i._ephemeral = true
    if typ(msg) == 'string' then msg = {content = msg, flags = 64}
    elseif not msg then msg = {flags = 64}
    end
    return send_int(i, getapi(), msg, files)
end


local ephemeral_data = {flags = 64}

function defer(i, ephemeral)
    i = resolve(i, 'interaction')
    if not i._state then
        if ephemeral then i._ephemeral = true end
        local api = getapi()
        local success, data, e = api:create_interaction_response(i.id, i.token, {
            type = responses.LOADING,
            data = ephemeral and ephemeral_data or nil,
        })
        if success and data then
            i._state = 'loading'
            return true
        else
            return nil, e
        end
    end
end


--- Component specific methods ---
function ack(i, ephemeral)
    i = resolve(i, 'interaction')
    if not i._state then
        if ephemeral then i._ephemeral = true end
        local api = getapi()
        local success, data, e = api:create_interaction_response(i.id, i.token, {
            type = responses.ACKNOWLEDGE,
            data = ephemeral and ephemeral_data or nil,
        })
        if success and data then
            i._state = 'message'
            return true
        else
            return nil, e
        end
    end
end

_ENV.acknowledge = _ENV.ack


function update_message(i, msg, files)
    i = resolve(i, 'interaction')
    if i.type == types.COMPONENT then
        if typ(msg) == 'string' then msg = {content = msg} end
        local api = getapi()
        if not i._state then
            local success, data, e = api:create_interaction_response(i.id, i.token, {
                type = responses.UPDATE_MESSAGE,
                data = msg,
            }, files)
            if success and data then
                i._state = 'message'
                i._empty = (not msg.content or files)
                return true
            else
                return nil, e
            end
        else
            local success, data, e = api:edit_message(i.message.channel_id, i.message.id, msg, files)
            if success and data then
                return true
            else
                return nil, e
            end
        end
    end
end


function custom_id(i)
    i = resolve(i, 'interaction')
    return i.data.custom_id
end


local function values_(I, i)
    if I.data.values[i] then
        return I.data.values[i].value, values_(I, i + 1)
    end
end

function values(i)
    i = resolve(i, 'interaction')
    if i.data.values then
        return values_(i, 1)
    end
end


function clear(i)
    i = resolve(i, 'interaction')
    if i._empty then
        local api = getapi()
        local success, data, e = api:delete_original_interaction_response(i.application_id, i.token)
        if success and data then
            return true
        else
            return nil, e
        end
    else
        if (i.message.content ~= "") or i.message.attachments[1] or i.message.embeds[1] then
            return _ENV.update_message(i, {components = {}})
        else
            local success, data, e = getapi():delete_message(i.message.channel_id, i.message.id)
            if success and data then
                return true
            else
                return nil, e
            end
        end
    end
end

function delete(i)
    i = resolve(i, 'interaction')
    if i._empty ~= nil then
        local api = getapi()
        local success, data, e = api:delete_original_interaction_response(i.application_id, i.token)
        if success and data then
            return true
        else
            return nil, e
        end
    else
        local success, data, e = getapi():delete_message(i.message.channel_id, i.message.id)
        if success and data then
            return true
        else
            return nil, e
        end
    end
end


local disable_ = function(cmp) cmp.disabled = true end

function disable(i)
    i = resolve(i, 'interaction')
    local components = copy(i.message.components)
    for j , row in iiter(components) do
        components[j] = map_bang(disable_, row)
    end
    return _ENV.update_message(i, {components = components})
end


function replace_components(i, msg, files)
    i = resolve(i, 'interaction')
    if typ(msg) == 'string' then msg = {content = msg} end
    msg.components = {}
    return _ENV.update_message(i, msg, files)
end


--- App command specific methods ---

local function resolve_type(i, ty)
    i = resolve(i, 'interaction')
    if i.type == ty then return i end
end

local function load_name(i)
    i._full_name, i._inner_name, i._middle_name = command.full_name(i)
    return i._full_name
end


function command_name(i)
    if i._full_name then return i._full_name end
    i = resolve_type(i, types.COMMAND)
    if i then return load_name(i) end
end


function subcommand(i)
    if i._inner_name then return i._inner_name end
    i = resolve_type(i, types.COMMAND)
    if i then
        load_name(i)
        return i._inner_name
    end
end


function group(i)
    if i._inner_name then return i._inner_name end
    i = resolve_type(i, types.COMMAND)
    if i then
        load_name(i)
        return i._middle_name
    end
end


function root(i)
    i = resolve_type(i, types.COMMAND)
    if i then
        return i.data.name
    end
end


function command_id(i)
    i = resolve_type(i, types.COMMAND)
    if i then
        return i.data.id
    end
end


function command_type(i)
    i = resolve_type(i, types.COMMAND)
    if i then
        return i.data.type
    end
end


function _ENV.command(i)
    i = resolve_type(i, types.COMMAND)
    if i then
        return context.request('command', i.data.id)
    end
end


function args(i)
    i = resolve_type(i, types.COMMAND)
    if i then
        return i.options
    end
end


local targets = {
    [numbers.command_type.USER_CONTEXT] = 'users',
    [numbers.command_type.MESSAGE_CONTEXT] = 'messages',
}

function target(i)
    i = resolve_type(i, types.COMMAND)
    if i then
        local resolved = targets[i.data.type]
        local obj = resolved and i.data.resolved[resolved][i.data.target_id]
        if obj then
            return create(resolved:sub(1, -2), obj)
        end
    end
end


local function get_resolved(i, type, id)
    i = resolve(i, 'interaction')
    if i.data and i.data.resolved and i.data.resolved[type] then
        local map = i.data.resolved[type]
        if map[id] then return create(type:sub(1, -2), map[id]) end
    end
end


local can_resolve = {
    users = true,
    members = true,
    roles = true,
    channels = true,
    messages = true,
    attachments = true
}

for name in iter(can_resolve) do
    _ENV['resolved_'..name:sub(1, -2)] = function(i, ...)
        return get_resolved(i, name, ...)
    end
end


return _ENV