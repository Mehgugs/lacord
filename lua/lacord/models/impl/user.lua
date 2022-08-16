local setm  = setmetatable

local context   = require"lacord.models.context"
local mtostring = require"lacord.util.models".tostring
local methodify = require"lacord.util.models".methodify
local mod       = require"lacord.models.user"
local fetch_usr = mod.fetch

local getapi   = context.api
local getctx   = context.get
local request  = context.request
local store    = context.store
local create   = context.create
local property = context.property

local user_mt = {
    __tostring = mtostring,
    __lacord_model_id = function(obj) return obj.id end,
    __lacord_model = 'user',
    __lacord_model_mention = function(obj) return "<@" .. obj.id .. ">" end,
    __lacord_model_defer = {
        send = '__lacord_channel'
    }
}

--- Wrap a lua table in a metatable which designates it a user.
local function as_user(tbl)
    return setm(tbl, user_mt)
end

local user_id_mt = {
    __lacord_model_id = function(obj) return obj[1] end,
    __lacord_model = 'user',
    __lacord_model_partial = true,
    __lacord_user = fetch_usr,
}

local function as_id(str)
    return setm({str}, user_id_mt)
end

function user_mt:__lacord_channel()
    local the_id = self.id
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

methodify(user_mt, mod, 'tag')

return {
    from = as_user,
    as_id = as_id,

    mt = user_mt,
    id_wrapper = user_id_mt,
}