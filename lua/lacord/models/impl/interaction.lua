local setm = setmetatable
local to_n = tonumber

local insert = table.insert

local context   = require"lacord.models.context"
local mtostring = require"lacord.util.models".tostring
local methodify = require"lacord.util.models".methodify
local mod       = require"lacord.models.interaction"
local numbers   = require"lacord.models.magic-numbers"
local send_int  = require"lacord.models.common.send-interaction"


local store    = context.store
local unstore  = context.unstore
local create   = context.create
local property = context.property
local DEL      = context.DEL

local types     = numbers.interaction_type


local _ENV = {}

local interaction_mt = {
    __lacord_model_id = function(obj) return obj.id end,
    __lacord_model = 'interaction',
    __lacord_model_mention = function(obj) return "<#" .. obj.id .. ">" end,
    __tostring = mtostring,
}

local function as_interaction(self)
    -- normalize and hydrate --
    if self.type == types.COMMAND then
        local opts = { }
        local options = self.data.options
        if self.data.options then
            for i = 1, #options do
                local opt = options[i]
                opts[opt.name] = opt.value
                insert(opts, opt.value)
            end
        end
        self.options = opts
    end

    if self.member then
        self.member.user = create('user', self.member.user)
    else
        self.user = create('user', self.user)
    end

    if self.message then
        self.message = create('message', self.message)
    end

    self.app_permissions = to_n(self.app_permissions)

    return setm(self, interaction_mt)
end

--- Operations on channels ---

function interaction_mt:__lacord_model_send(...)
    return send_int(self, ...)
end

function interaction_mt:__lacord_channel()
    return mod.channel(self)
end

function interaction_mt:__lacord_guild()
    return mod.guild(self)
end

function interaction_mt:__lacord_user()
    if self.member then
        return self.member.user
    else return self.user
    end
end

methodify(interaction_mt, mod,
    'channel', 'guild', 'state',
    'custom_id',
    'command', 'command_id', 'command_name', 'subcommand', 'root', 'group', 'command_type', 'args', 'target')

return {
    from = as_interaction,

    mt = interaction_mt,
}