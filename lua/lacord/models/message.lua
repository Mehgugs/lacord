local err   = error
local getm  = getmetatable
local iter  = pairs
local iiter = ipairs
local to_s  = tostring
local typ   = type

local constants   = require"lacord.const"
local encodeURI   = require"http.util".encodeURIComponent
local endswith    = require"lacord.util".endswith
local map_bang    = require"lacord.util".map_bang
local new_promise = require"cqueues.promise".new
local prefix      = require"lacord.util".prefix

local context = require"lacord.models.context"
local methods = require"lacord.models.methods"
local numbers = require"lacord.models.magic-numbers"


local channel = require"lacord.models.channel"

local getapi  = context.api
local create  = context.create
local request = context.request

local model_id = methods.model_id
local resolve  = methods.resolve

local link_endpoint = constants.api.base_endpoint .. "/channels"

local SUPPRESS_EMBEDS = numbers.message_flags.SUPPRESS_EMBEDS
local TIMEOUTS = constants.models.timeouts

--luacheck: ignore 111

local function is_emoji(emoji)
    local mt = getm(emoji)
    return typ(emoji) == "string" or (mt and mt.__lacord_emoji)
end

local _ENV = {}

function fetch(c, m)
    return channel.message(c, m)
end

local function edit_by_id_inner(c, m, edit, files)
    local api = getapi()

    local success, data, e = api:edit_message(c, m, edit, files)

    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function edit(m, ...)
    local msg = resolve(m, 'message')

    return edit_by_id_inner(msg.channel_id, msg.id, ...)
end

function edit_by_id(c, m, ...)
    c = model_id(c, 'message')
    m = model_id(m, 'message')

    return edit_by_id_inner(c, m, ...)
end


function react_by_id(c, m, reaction)
    c = model_id(c, 'channel')
    m = model_id(m, 'message')
    reaction = to_s(reaction)

    local api = getapi()

    local success, s, e = api:create_reaction(c, m, encodeURI(reaction))

    if success then
        return s
    else
        return nil, e
    end
end

function unreact_by_id(c, m, reaction)
    c = model_id(c, 'channel')
    m = model_id(m, 'message')
    reaction = to_s(reaction)

    local api = getapi()

    local success, s, e = api:delete_own_reaction(c, m, encodeURI(reaction))

    if success then
        return s
    else
        return nil, e
    end
end

function remove_reaction_by_id(c, m, reaction, u)
    c = model_id(c, 'channel')
    m = model_id(m, 'message')
    u = model_id(u, 'user')
    reaction = to_s(reaction)

    local api = getapi()

    local success, s, e = api:delete_user_reaction(c, m, encodeURI(reaction), u)

    if success then
        return s
    else
        return nil, e
    end
end

local function swap(a, b, f)
    return f(b, a)
end

function reacting_users_by_id(c, m, reaction)
    c = model_id(c, 'channel')
    m = model_id(m, 'message')
    reaction = to_s(reaction)

    local api = getapi()

    local success, users, e = api:get_reactions(c, m, encodeURI(reaction))

    if success then
        return map_bang(swap, users, 'user', create)
    else
        return nil, e
    end
end

local function remove_single_reaction_by_id(c, m, reaction, errr)
    local success, s, e = getapi():delete_reactions(c, m, reaction)
    if success then
        return s
    else
        return errr(e)
    end
end

local function soft_err(e) return nil, e end

function remove_reactions_by_id(c, m, reactions)
    c = model_id(c, 'channel')
    m = model_id(m, 'message')
    if not reactions then
        local api = getapi()
        local success, s, e = api:delete_all_reactions(c, m)

        if success then
            return s
        else
            return nil, e
        end
    elseif is_emoji(reactions) then
        return remove_single_reaction_by_id(c, m, encodeURI(to_s(reactions)), soft_err)
    elseif typ(reactions) == "table" then
        if #reactions == 1 then
            return remove_single_reaction_by_id(c, m, encodeURI(to_s(reactions[1])), soft_err)
        else
            local promises = {}
            for i , reaction in iiter(reactions) do
                promises[i] = new_promise(remove_single_reaction_by_id, c, m, encodeURI(to_s(reaction)), err)
            end
            local timeo = TIMEOUTS.remove_reactions
            if timeo then
                for i, p in iiter(promises) do
                    if p:wait(timeo) then
                        promises[i] = p:status() == "fulfilled"
                    end
                end
            else
                for i, p in iiter(promises) do
                    if p:wait() then
                        promises[i] = p:status() == "fulfilled"
                    end
                end
            end
            return promises
        end
    end
end

function remove_embeds_by_id(c, m, flgs)
    return _ENV.edit_by_id(c, m, {
        flags = flgs | SUPPRESS_EMBEDS
    })
end

function show_embeds_by_id(c, m, flgs)
    return _ENV.edit_by_id(c, m, {
        flags = flgs & ~SUPPRESS_EMBEDS
    })
end

function remove_embeds(m)
    m = resolve(m, 'message')
    return _ENV.remove_embeds_by_id(m.channel_id, m.id, m.flags or 0)
end

function show_embeds(m)
    m = resolve(m, 'message')
    return _ENV.show_embeds_by_id(m.channel_id, m.id, m.flags or 0)
end

function pin_by_id(c, m)
    local api = getapi()

    local success, data, e = api:add_pinned_channel_message(c, m)

    if success then
        return data
    else
        return nil, e
    end
end

function unpin_by_id(c, m)
    local api = getapi()

    local success, data, e = api:delete_pinned_channel_message(c, m)

    if success then
        return data
    else
        return nil, e
    end
end

local new = {}
for name, definition in iter(_ENV) do
    if endswith(name, '_by_id') then
        local pfx = prefix(name, '_by_id')
        if not _ENV[pfx] then
            new[pfx] = function(m, ...)
                m = resolve(m, 'message')
                return definition(m.channel_id, m.id, ...)
            end
        end
    end
end

for k , v in iter(new) do _ENV[k] = v end

function link(m)
    m = resolve(m, 'message')
    local container = m.guild_id

    if not container then
        local c = channel.fetch(m.channel_id)
        if c and c.type == 1 then container = "@me" end
    end
    if container then
        return link_endpoint.."/"..container.."/"..m.channel_id.."/"..m.id
    else
        return link_endpoint.."/"..m.channel_id.."/"..m.id
    end
end

function _ENV.channel(m)
    m = resolve(m, 'message')
    return request('channel', m.channel_id)
end

function _ENV.guild(m)
    m = resolve(m, 'message')
    if m.guild_id then
        return request('guild', m.guild_id)
    end
end

_ENV.send = methods.send

return _ENV