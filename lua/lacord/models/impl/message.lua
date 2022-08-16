local setm = setmetatable

local context   = require"lacord.models.context"
local mtostring = require"lacord.util.models".tostring
local methodify = require"lacord.util.models".methodify
local mod       = require"lacord.models.message"

local getapi  = context.api
local getctx  = context.get
local create  = context.create
local request = context.request
local unstore = context.unstore

local _ENV = {}

local message_mt = {
    __lacord_model_id = function(obj) return obj.id end,
    __lacord_model = 'message',
    __tostring = mtostring,
}

local function as_channel(tbl)
    return setm(tbl, message_mt)
end

--- Operations on messages ---

function message_mt:__lacord_model_send(api, msg, files)
    if not msg.message_reference then
        msg.message_reference = {
            message_id = self.id,
            channel_id = self.channel_id,
            fail_if_not_exists = false,
        }
        if self.guild_id then msg.message_reference.guild_id = self.guild_id end
    end
    local success, data, e = api:create_message(self.channel_id, msg, files)
    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function message_mt:__lacord_model_delete(api)
    local success, data, e = api:delete_message(self.channel_id, self.id)
    if success and data then
        unstore('message', self.id)
        return true
    else
        return nil, e
    end
end

function message_mt:__lacord_model_update(api, edit, files)
    local success, data, e = api:edit_message(self.channel_id, self.id, edit, files)

    if success then
        return create('message', data)
    else
        return nil, e
    end
end

function message_mt:__lacord_channel()
    local ctx, loop = getctx()

    local chl = request(ctx, 'channel', self.channel_id)

    if not chl then
        local api = getapi(ctx, loop)
        local success, data, e = api:get_channel(self.channel_id)
        if success then
            chl = create('channel', data)
        else
            return nil, e
        end
    end

    return chl
end

function message_mt:__lacord_guild()
    if not self.guild_id then return nil
    else
        local ctx, loop = getctx()

        local gld = request(ctx, 'guild', self.guild_id)

        if not gld then
            local api = getapi(ctx, loop)
            local success, data, e = api:get_guild(self.guild_id)
            if success then
                gld = create('guild', data)
            else
                return nil, e
            end
        end

        return gld
    end
end

function message_mt:__lacord_user()
    if not (self.author and self.author.id) then return nil
    else
        local usr = request('user', self.author.id)
        if not usr then
            local api = getapi()
            local success, data, e = api:get_user(self.author.id)
            if success then
                usr = create('user', data)
            else
                return nil, e
            end
        end
        return usr
    end
end

methodify(message_mt, mod, 'link', 'channel', 'guild')

return {
    from = as_channel,
    mt = message_mt,
}