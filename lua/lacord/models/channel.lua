local err   = error
local to_s  = tostring
local typ   = type

local context   = require"lacord.models.context"
local methods   = require"lacord.models.methods"
local map_bang  = require"lacord.util".map_bang
local map       = require"lacord.util".map
local numbers   = require"lacord.models.magic-numbers"
local null      = require"lacord.util.json".null

local getapi   = context.api
local create   = context.create
local request  = context.request
local property = context.property

local modify   = methods.update
local model_id = methods.model_id
local resolve  = methods.resolve

local GUILD_PRIVATE_THREAD, GUILD_PUBLIC_THREAD = numbers.PRIVATE_THREAD, numbers.PUBLIC_THREAD

--luacheck: ignore 111

local _ENV = {}

function fetch(c)
    c = model_id(c, 'channel')
    local chl = request('channel', c)
    if not chl then
        local api = getapi()
        local success, data, e = api:get_channel(c)
        if success then
            chl = create('channel', data)
        else
            return err(
                "lacord.models.channel: Unable to resolve channel id to channel."
                .."\n "..e
            )
        end
    end
    return chl or err"lacord.models.channel: Unable to resolve channel id to channel."
end


function edit(c, changes)
    c = model_id(c, 'channel')

    local api = getapi()
    local success, data, e = api:modify_channel(c, changes)

    if success then
        local chl = create('channel', data)
        if chl.recipient_id then
            property('dms', chl.recipient_id, chl.id)
        end
        return chl
    else
        return nil, e
    end
end

function message(c, id)
    c = model_id(c, 'channel')
    id = model_id(id, 'message')

    local api = getapi()
    local success, data, e = api:get_message(c, id)
    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function first_message(c)
    c = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:get_channel_messages(c, {after = c, limit = 1})
    if success and data[1] then
        return create('message', data[1])
    elseif success and not data[1] then
        return false, "Channel has no messages."
    else
        return nil, e
    end
end

function last_message(c)
    c = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:get_channel_messages(c, {limit = 1})
    if success and data[1] then
        return create('message', data[1])
    elseif success and not data[1] then
        return false, "Channel has no messages."
    else
        return nil, e
    end
end

local function swap(a, b, f)
    return f(b, a)
end

function messages(c, query)
    c = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:get_channel_messages(c, query)
    if success and data[1] then
        return map_bang(swap, data, 'message', create)
    elseif success and not data[1] then
        return false, "Channel has no messages."
    else
        return nil, e
    end
end

function pinned_messages(c)
    c = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:get_pinned_messages(c)

    if success then
        return data
    else
        return nil, e
    end
end

function broadcast_typing(c)
    c = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:trigger_typing_indicator(c)

    if success and data then return true
    else return nil, e
    end
end

function rename(c, new_name)
    new_name = to_s(new_name)
    return modify(c, {name = new_name})
end

function change_category(c, new_parent)
    local id = new_parent and model_id(new_parent, 'channel') or null
    return modify(c, {parent_id = id})
end

function change_topic(c, the_topic)
    return modify(c, {topic = the_topic or null})
end

function enable_slowmode(c, rl_per_user)
    return modify(c, {
        rate_limit_per_user = rl_per_user or null,
    })
end

function disable_slowmode(c)
    return modify(c, {rate_limit_per_user = null})
end

function enable_NSFW(c)
    return modify(c, {nsfw = true})
end

function disable_NSFW(c)
    return modify(c, {nsfw = false})
end

enable_SFW = disable_NSFW

function fetch_invites(c)
    local the_id = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:get_channel_invites(the_id)

    if success then return data
    else return nil, e
    end
end

function create_invite(c, payload)
    c = model_id(c, 'channel')
    local api = getapi()
    local success, data, e = api:create_channel_invite(c, payload)

    if success then return data
    else return nil, e
    end
end

function check_overwrite(c, user_role)
    c = model_id(c, 'channel')
    local id, kind = model_id(user_role, 'user', 'role')

    if c.permission_overwrites[id] then
        return c.permission_overwrites[id]
    else
        return {
            id = id,
            type = kind,
            allow = 0,
            deny  = 0
        }
    end
end

function update_overwrite(c, ow)
    c = model_id(c, 'channel')

    if ow.id and ow.type and ow.allow and ow.deny then
        local api = getapi()
        local success, data, e = api:edit_channel_permissions(c.id, ow.id, {
            type = ow.type,
            id = ow.id,
            allow = ow.allow,
            deny = ow.deny
        })
        if success and data then
            return ow
        else return nil, e
        end
    else
        return nil, "Overwrite object invalid"
    end
end

function crosspost(c, m_id)
    c = model_id(c, 'channel')
    m_id = model_id(m_id, 'message')
    local api = getapi()
    local success, data, e = api:crosspost_message(c, m_id)
    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function delete_messages(c, input)
    c = model_id(c, 'channel')

    local messages = resolve(input, 'message')

    messages = messages and {messages.id} or map(model_id, input, 'message')

    local api = getapi()

    if #messages == 1 then
        local success, data , e = api:delete_message(c, messages[1])
        return success and data or nil, e
    else
        local success, data , e = api:bulk_delete_messages(c, messages)
        return success and data or nil, e
    end
end

function delete_overwrite(c, user_role)
    c = model_id(c, 'channel')
    local id = model_id(user_role, 'user', 'role')
    local api = getapi()

    local success, data, e = api:delete_channel_permission(c, id)
    return success and data or nil, e
end

function pin(c, id)
    c = model_id(c, 'channel')
    id = model_id(id, 'message')

    local api = getapi()
    local success, data, e = api:pin_message(c, id)
    return success and data or nil, e
end

function unpin(c, id)
    c = model_id(c, 'channel')
    id = model_id(id, 'message')

    local api = getapi()
    local success, data, e = api:unpin_message(c, id)
    return success and data or nil, e
end

function message_to_thread(c, id, name, auto_archive_duration, rl_per_user)
    c = model_id(c, 'channel')
    id = model_id(id, 'message')

    local api = getapi()

    local success, data, e = api:start_thread_with_message(c, id, {
        name = name,
        auto_archive_duration = auto_archive_duration,
        rate_limit_per_user = rl_per_user
    })

    if success then
        return create('channel', data)
    else
        return nil, e
    end
end


function private_thread(c, name, auto_archive_duration, rl_per_user, invitable)
    c = model_id(c, 'channel')

    local api = getapi()

    local success, data, e = api:start_thread_without_message(c, {
        name = name,
        auto_archive_duration = auto_archive_duration,
        rate_limit_per_user = rl_per_user,
        invitable = invitable,
        type = GUILD_PRIVATE_THREAD
    })

    if success then
        return create('channel', data)
    else
        return nil, e
    end
end

--- Open a new thread in a channel (defaults to a public thread)
function thread(c, name, auto_archive_duration, rl_per_user, type)
    c = model_id(c, 'channel')

    local api = getapi()

    local success, data, e = api:start_thread_without_message(c, {
        name = name,
        auto_archive_duration = auto_archive_duration,
        rate_limit_per_user = rl_per_user,
        type = type or GUILD_PUBLIC_THREAD
    })

    if success then
        return create('channel', data)
    else
        return nil, e
    end
end

function forum_post(c, name, auto_archive_duration, rl_per_user, msg, files)
    c = model_id(c, 'channel')

    local api = getapi()

    local success, data, e = api:start_thread_in_forum(c, {
        name = name,
        auto_archive_duration = auto_archive_duration,
        rate_limit_per_user = rl_per_user,
        type = type or GUILD_PUBLIC_THREAD,
        message = msg
    }, files)

    if success then
        return create('channel', data)
    else
        return nil, e
    end
end

function join(c)
    c = model_id(c, 'channel')

    local api = getapi()
    local success, data, e = api:join_thread(c)
    return success and data or nil, e
end

function leave(c)
    c = model_id(c, 'channel')

    local api = getapi()
    local success, data, e = api:leave_thread(c)
    return success and data or nil, e
end

function add_to_thread(c, id)
    c = model_id(c, 'channel')
    id = model_id(id, 'user')

    local api = getapi()
    local success, data, e = api:add_thread_member(c, id)
    return success and data or nil, e
end

function remove_from_thread(c, id)
    c = model_id(c, 'channel')
    id = model_id(id, 'user')

    local api = getapi()
    local success, data, e = api:remove_thread_member(c, id)
    return success and data or nil, e
end

function membership_of(c, id)
    c = model_id(c, 'channel')
    id = model_id(id, 'user')

    local api = getapi()
    local success, data, e = api:get_thread_member(c, id)
    if success then
        return data
    else
        return nil, e
    end
end

function membership(c)
    c = model_id(c, 'channel')

    local api = getapi()
    local success, data, e = api:list_thread_members(c)
    if success then
        return data
    else
        return nil, e
    end
end

function _ENV.send(c, msg, files)
    c = model_id(c, 'channel')
    local api = getapi()
    if typ(msg) == 'string' then msg = {content = msg} end

    local success, data, e = api:create_message(c, msg, files)
    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function _ENV.guild(c)
    c = resolve(c, 'channel')
    if c.guild_id then
        return request('guild', c.guild_id)
    end
end

return _ENV