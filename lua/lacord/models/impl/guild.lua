local setm  = setmetatable

local methodify = require"lacord.util.models".methodify
local mod       = require"lacord.models.guild"
local mtostring = require"lacord.util.models".tostring
local context   = require"lacord.models.context"

local create  = context.create

local fetch_gld = mod.fetch

local THROW_OUT = require"lacord.const".models.remove_unused_keys

local guild_mt = {
    __lacord_model_id = function(obj) return obj.id end,
    __lacord_model = 'guild',
    __tostring = mtostring,
}

local as_guild if THROW_OUT then
    function as_guild(tbl, _)

        if not tbl.unavailable then
            tbl.roles = nil
            tbl.emojis = nil
            tbl.members = nil
            tbl.voice_states = nil
            tbl.presences = nil
            tbl.channels = nil
            tbl.threads = nil
        end

        return setm(tbl, guild_mt)
    end
else
    function as_guild(tbl)
        return setm(tbl, guild_mt)
    end
end



local guild_id_wrapper = {
    __lacord_model_id = function(obj) return obj[1] end,
    __lacord_model = 'guild',
    __lacord_model_partial = true,
    __lacord_guild = function(obj) return fetch_gld(obj[1]) end,
}

local function as_id(str)
    return setm({str}, guild_id_wrapper)
end

function guild_mt:__lacord_model_update(api, edit)
    local success, data, e = api:modify_guild(self.id, edit)

    if success then
        return create('guild', data, false, true)
    else
        return nil, e
    end
end

methodify(guild_mt, mod)

return {
    from = as_guild,
    as_id = as_id,

    mt = guild_mt,
    id_wrapper = guild_id_wrapper,
}