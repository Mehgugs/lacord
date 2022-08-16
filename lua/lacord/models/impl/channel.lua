local iter = pairs
local setm = setmetatable

local context   = require"lacord.models.context"
local mtostring = require"lacord.util.models".tostring
local methodify = require"lacord.util.models".methodify
local mod       = require"lacord.models.channel"
local fetch_chl = mod.fetch

local store    = context.store
local unstore  = context.unstore
local create   = context.create
local property = context.property
local DEL      = context.DEL

local _ENV = {}

local channel_mt = {
    __lacord_model_id = function(obj) return obj.id end,
    __lacord_model = 'channel',
    __lacord_model_mention = function(obj) return "<#" .. obj.id .. ">" end,
    __tostring = mtostring,
}

local function as_channel(tbl)
    return setm(tbl, channel_mt)
end

local channel_id_wrapper = {
    __lacord_model_id = function(obj) return obj[1] end,
    __lacord_model = 'channel',
    __lacord_model_partial = true,
    __lacord_channel = function(obj) return fetch_chl(obj[1]) end
}

local function as_id(str)
    return setm({str}, channel_id_wrapper)
end

--- Operations on channels ---

function channel_mt:__lacord_model_send(api, msg, files)
    local success, data, e = api:create_message(self.id, msg, files)
    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function channel_id_wrapper:__lacord_model_send(api, msg, files)
    local success, data, e = api:create_message(self[1], msg, files)
    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function channel_mt:__lacord_model_delete(api)
    local success, data, e = api:delete_channel(self.id)
    if success and data then
        unstore('channel', self.id)
        if self.recipient_id then
            property('dms', self.recipient_id, DEL)
        end
        return true
    else
        return nil, e
    end
end

function channel_id_wrapper:__lacord_model_delete(api)
    local success, data, e = api:delete_channel(self[1])
    if success and data then
        unstore('channel', self[1])
        local dms = property('dms', "*")
        local rem
        for k , v in iter(dms) do
            if v == self[1] then
                rem = k break
            end
        end
        if rem then property('dms', rem, DEL) end
        return true
    else
        return nil, e
    end
end

function channel_mt:__lacord_model_update(api, edit)
    local success, data, e = api:modify_channel(self.id, edit)

    if success then
        local chl = create('channel', data)
        return chl
    else
        return nil, e
    end
end

methodify(channel_mt, mod, 'guild')

return {
    from = as_channel,
    as_id = as_id,

    mt = channel_mt,
    id_wrapper = channel_id_wrapper,
}