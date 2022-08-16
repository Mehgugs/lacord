local err   = error
local to_n  = tostring

local user_avatar_url         = require"lacord.cdn"  .user_avatar_url
local default_user_avatar_url = require"lacord.cdn"  .default_user_avatar_url
local default_avatars         = require"lacord.const".default_avatars

local context   = require"lacord.models.context"
local methods   = require"lacord.models.methods"
local null      = require"lacord.util.json".null

local getapi   = context.api
local getctx   = context.get
local request  = context.request
local store    = context.store
local create   = context.create
local property = context.property

local send     = methods.send
local resolve  = methods.resolve
local model_id = methods.model_id

--luacheck: ignore 111

local _ENV = {}

function fetch(u)
    u = model_id(u, 'user')
    local usr
    local api = getapi()
    local success, data, e = api:get_user(u)
    if success then
        usr = create('user', data)
    else
        return err(
            "lacord.models.user: Unable to resolve user id to user."
            .."\n "..e
        )
    end
    return usr or err"lacord.models.user: Unable to resolve user id to user."
end

function avatar_url(u, ...)
    u = resolve(u, 'user')
    if u.avatar ~= null then
        return user_avatar_url(u.id, u.avatar, ...)
    else
        return default_user_avatar_url(u.id, to_n(u.discriminator) % default_avatars, ...)
    end
end

local function private_channel(u)
    local the_id = model_id(u, 'user')
    local ctx, loop = getctx()

    local chl_id = property(ctx, 'dms', the_id)

    local chl = chl_id and request(ctx, 'channel', chl_id)

    if not chl then
        local api = getapi(ctx, loop)
        local success, data, e = api:create_dm{recipient_id = the_id}
        if success then
            chl = create('channel', data)
            property(ctx, 'dms', the_id, chl.id)
        else
            return nil, e
        end
    end

    return chl
end

_ENV.private_channel = private_channel

function dm(u, ...)
    return send(private_channel(u), ...)
end

function tag(u)
    u = resolve(u, 'user')
    return u.username .. "#" .. u.discriminator
end

return _ENV
