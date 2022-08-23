local setm  = setmetatable


local context   = require"lacord.models.context"
local mtostring = require"lacord.util.models".tostring

local create  = context.create
local unstore = context.unstore
local upsert  = context.upsert
local TABLE   = context.upserters.TABLE

local role_mt = {
    __lacord_model_id = function(obj) return obj.id end,
    __lacord_model = 'role',
    __tostring = mtostring,
    __lacord_model_mention = function(obj) return "<@&" .. obj.id .. ">" end
}

function role_mt:__lacord_model_update(api, edit)

    local g = self.guild_id

    local success, data, e = api:modify_guild_role(g, self.id, edit)

    if success then
        data.guild_id = g
        local rol = create('role', data)
        return rol
    else
        return nil, e
    end
end

function role_mt:__lacord_model_delete(api)
    local g = self.guild_id
    local success, data, e = api:delete_guild_role(g, self.id)

    if success and data then
        unstore('role', self.id)
        upsert('guild->role', g, TABLE)[self.id] = nil
        return true
    else
        return nil, e
    end
end

local function as_role(tbl) return setm(tbl, role_mt) end

return {
    from = as_role,

    mt = role_mt,
}