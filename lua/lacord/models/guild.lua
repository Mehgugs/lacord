local err  = error
local iter = pairs

local insert = table.insert

local context   = require"lacord.models.context"
local methods   = require"lacord.models.methods"
local map_bang  = require"lacord.util".map_bang
local map       = require"lacord.util".map

local fetch_chl = require"lacord.models.channel".fetch

local getapi  = context.api
local getctx  = context.get
local create  = context.create
local request = context.request
local property = context.property
local upsert   = context.upsert
local TABLE    = context.upserters.TABLE

local model_id = methods.model_id

--luacheck: ignore 111

local _ENV = {}

local function guild_property(type, guild_id, obj_id)
    local set = upsert('guild->'..type, guild_id, TABLE)
    set[obj_id] = true
end

function fetch(g)
    g = model_id(g, 'guild')
    local gld = request('guild', g)
    if not gld then
        local api = getapi()
        local success, data, e = api:get_guild(g)
        if success then
            gld = create('guild', data)
        else
            return err(
                "lacord.models.guild: Unable to resolve guild id to guild."
                .."\n "..e
            )
        end
    end
    return gld or err"lacord.models.guild: Unable to resolve guild id to guild."
end

local function swap3(a, b, c, f)
    return f(c, b, a)
end

local function build_channels(data, ctx, g)
    data.guild_id = g
    local chl = create(ctx, 'channel', data)
    guild_property('channel', g, chl.id)
    return chl
end

function channels(g)
    g = model_id(g, 'guild')
    local ctx = getctx()

    local cached = property(ctx, 'guild->channel', g)

    if cached then
        local out = { }
        for k in iter(cached) do
            insert(out, fetch_chl(k))
        end
        return out
    else
        local api = getapi(ctx)
        local success, data, e = api:get_guild_channels(g)
        if success then
            local res = map_bang(build_channels, data, ctx, g)
            return res
        else
            return nil, e
        end

    end
end

function new_channel(g, payload)
    g = model_id(g, 'guild')
    local ctx = getctx()
    local api = getapi(ctx)
    local success, data, e = api:create_guild_channel(g, payload)

    if success then
        data.guild_id = g
        local chl = create(ctx, 'channel', data)

        guild_property('channel', g, chl.id)

        return chl
    else
        return nil, e
    end
end

function active_threads(g)
    g = model_id(g, 'guild')
    local ctx = getctx()
    local api = getapi(ctx)
    local success, data, e = api:list_active_guild_threads(g)
    if success then
        local chls = map(swap3, data[1], 'channel', ctx, create)
        return chls, data[2]
    else
        return nil, e
    end
end

function membership(g, u)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')

    local api = getapi()
    local success, data, e = api:get_guild_member(g, u)

    if success then
        return data
    else
        return nil, e
    end
end

function list_members(g, limit, after)
    g = model_id(g, 'guild')

    local api = getapi()
    local success, data, e = api:list_guild_members(g, {limit = limit, after = after})

    if success then
        return data
    else
        return nil, e
    end
end

function search_members(g, limit, after)
    g = model_id(g, 'guild')

    local api = getapi()
    local success, data, e = api:search_guild_members(g, {limit = limit, after = after})

    if success then
        return data
    else
        return nil, e
    end
end

function edit_membership(g, u, payload)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')

    local api = getapi()
    local success, data, e = api:modify_guild_member(g, u, payload)

    if success then
        return data
    else
        return nil, e
    end
end

function edit_my_membership(g, payload)
    g = model_id(g, 'guild')

    local api = getapi()
    local success, data, e = api:modify_current_member(g, payload)

    if success then
        return data
    else
        return nil, e
    end
end

function add_role_to(g, u, r)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')
    r = model_id(r, 'role')

    local api = getapi()
    local success, data, e = api:add_guild_member_role(g, u, r)

    if success then
        return data
    else
        return nil, e
    end
end

function remove_roles_from(g, u, r)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')
    r = model_id(r, 'role')

    local api = getapi()
    local success, data, e = api:remove_guild_member_role(g, u, r)

    if success then
        return data
    else
        return nil, e
    end
end

function kick(g, u)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')

    local api = getapi()
    local success, data, e = api:remove_guild_member(g, u)

    if success then
        return data
    else
        return nil, e
    end
end

function banlist(g, limit, before, after)
    g = model_id(g, 'guild')

    local api = getapi()
    local success, data, e = api:get_guild_bans(g, {limit = limit, before = before, after = after})

    if success then
        return data
    else
        return nil, e
    end
end

function get_ban(g, b)
    g = model_id(g, 'guild')
    b = model_id(b, 'ban')

    local api = getapi()
    local success, data, e = api:get_guild_ban(g, b)

    if success then
        return data
    else
        return nil, e
    end
end

function ban(g, u, days)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')

    local api = getapi()
    local success, data, e = api:create_guild_ban(g, u, days and {delete_message_days = days})

    if success then
        return data
    else
        return nil, e
    end
end

function unban(g, u)
    g = model_id(g, 'guild')
    u = model_id(u, 'user')

    local api = getapi()
    local success, data, e = api:remove_guild_ban(g, u)

    if success then
        return data
    else
        return nil, e
    end
end

function load_roles(g)
    g = model_id(g, 'guild')

    local ctx = getctx()
    local api = getapi(ctx)
    local success, data, e = api:get_guild_roles(g)

    if success then
        local n = #data
        local item
        for i = 1, n do
            item = data[i]
            item.guild_id = g
            data[i] = create(ctx, 'role', item)
            guild_property('role', g, item.id)
        end
        return data
    else
        return nil, e
    end
end

function new_role(g, payload)
    g = model_id(g, 'guild')

    local ctx = getctx()
    local api = getapi(ctx)
    local success, data, e = api:create_guild_role(g, payload)

    if success then
        data.guild_id = g
        local rol = create(ctx, 'role', data)
        guild_property('role', g, rol.id)
        return rol
    else
        return nil, e
    end
end

function iterate(g, type)
    return iter, upsert('guild->'..type, g, TABLE)
end



return _ENV






