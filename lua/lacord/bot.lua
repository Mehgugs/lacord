local iter = pairs
local setm = setmetatable
local type = type

local max = math.max

local api     = require"lacord.api"
local context = require"lacord.models.context"
local cqs     = require"cqueues"
local intents = require"lacord.util.intents"
local logger  = require"lacord.util.logger"
local setup   = require"lacord.models.impl"
local shard   = require"lacord.shard"
local signal  = require"cqueues.signal"

local new_sessionlimit = require"lacord.util.session-limit".new

local TABLE = context.upserters.TABLE

local function guild_property(type, guild_id, obj_id)
    local set = context.upsert('guild->'..type, guild_id, TABLE)
    set[obj_id] = true
    context.property(type..'->guild', obj_id, guild_id)
end


--local _ENV = {}

local bot_t = {__name = "lacord.gateway-bot"}

bot_t.__index = bot_t

function new(token, options)
    if type(options) == 'function' then options = {output = options}
    elseif not options then options = {}
    end

    if options.api then options.api.token = token end
    local discord = api.new(options.api or token)

    return setm({
        api = discord,
        shards = {},
        options = options
    }, bot_t)
end

local function handlesignals(self)
    signal.block(signal.SIGINT, signal.SIGTERM)
    local sig = signal.listen(signal.SIGTERM, signal.SIGINT)
    local int = sig:wait()
    local reason = signal.strsignal(int)
    logger.info("%s received (%d, %q); shutting down.", self, int, reason)
    for _, s in pairs(self.shards) do
        s:shutdown()
    end

    local me = cqs.running()

    logger.info("There are %d cqueues objects still processing.", me:count())

    me:wrap(self.options.output, 'SIGNAL', int)

    signal.unblock(signal.SIGINT, signal.SIGTERM)
end

local function get_gateway(req, self)
    if not self.options.gateway then
        return req:get_gateway_bot()
    end
end

local function runner(self)
    local R = self.api:capture()
        :get_current_application_information()
        :continue(get_gateway, self)

    if R.success then
        self.app = R.result[1]
        local gateway = R.result[2] or self.options.gateway
        local sessionlimit = new_sessionlimit(gateway.session_start_limit.max_concurrency)

        for i = 0, gateway.shards -1 do
            local s = shard.new({
                token = self.api.token
                ,id = i
                ,gateway = gateway.url
                ,compress = false
                ,transport_compression = true
                ,total_shard_count = gateway.shards
                ,large_threshold = 100
                ,auto_reconnect = true
                ,loop = self.loop
                ,output = self:output()
                ,intents = self.options.intents or intents.unprivileged
                ,sync = true
            }, sessionlimit)
            self.shards[i] = s
            s:connect()
        end

        self.gateway = gateway
        self.gateway.session_limiter = sessionlimit

        if self.options.handle_signals then
            self.loop:wrap(handlesignals, self)
        end

    else
        logger.error(R.error)
    end
end

function bot_t:run(loop)
    loop = loop or cqs.new()
    self.loop = loop

    local _ctx
    if self.options.context then
        _ctx = context.attach(loop, self.options.context(self))
    else
        _ctx = setup(self.api, loop)
    end

    context.property(_ctx, 'bot', '*', self)

    loop:wrap(runner, self)

    return assert(loop:loop())
end

function bot_t.me()
    return context.property('me', '*')
end

local events = { }

function events.SHARD_READY(d)
    local glds = d.guilds
    for  i = 1, #glds do
        context.create('guild', glds[i])
    end
    d.user = context.create('user', d.user)
    context.property('me', '*', d.user)
    return d
end

local function populate_channels(d)
    local chls, thds = d.channels, d.threads
    local lenc, lent = #chls, #thds
    local bigger = max(lenc, lent)
    local smaller = bigger == lenc and lent or lenc

    for i = 1, smaller do
        local c = context.create('channel', chls[i])
        local t = context.create('channel', thds[i])
        guild_property('channel', d.id, c.id)
        guild_property('channel', d.id, t.id)
    end

    local left = bigger == lenc and chls or thds
    for i = smaller + 1, bigger do
        local c = context.create('channel', left[i])
        guild_property('channel', d.id, c.id)
    end
end

local function populate_others(d)
    local chls, thds = d.roles, d.emojis
    local lenc, lent = #chls, #thds
    local bigger = max(lenc, lent)
    local smaller = bigger == lenc and lent or lenc

    for i = 1, smaller do
        local c = context.create('role', chls[i])
        local t = context.create('emoji', thds[i])
        guild_property('role', d.id, c.id)
        guild_property('emoji', d.id, t.id)
    end

    local left = bigger == lenc and chls or thds
    local typ = left == chls and 'role' or 'emoji'
    for i = smaller + 1, bigger do
        local c = context.create(typ, left[i])
        guild_property(typ, d.id, c.id)
    end
end

function events.GUILD_CREATE(d)
    if d.unavailable then
        return context.create('guild', d, 'create'), 'outage'
    end
    local old = context.request('guild', d.id)
    d._status = 'connected'
    populate_channels(d)
    populate_others(d)
    if old and old.unavailable then
        return context.create('guild', d, 'create'), 'connected'
    else
        return context.create('guild', d, 'create'), 'joined'
    end
end

function events.GUILD_UPDATE(d)
    return context.create('guild', d, 'update', true)
end

local guild_entities = {
    channel = true,
    role = true,
    emoji = true,
}

function events.GUILD_DELETE(d)
    if d.unavailable then
        d._status = 'disconnected'
        return context.create('guild', d, 'create'), 'outage'
    end
    return context.unstore('guild', d.id), 'left', '_GUILD_CLEANUP'
end

function events._GUILD_CLEANUP(d)
    local ctx = context.get()
    for type in iter(guild_entities) do
        local old = context.property(ctx, 'guild->'..type, d.id, context.DEL)
        for obj_id in iter(old) do
            context.property(ctx, type..'->guild', obj_id, context.DEL)
            context.unstore(ctx, type, obj_id)
        end
    end
end

function events.GUILD_BAN_ADD(d)
    d.user = context.create('user', d.user)
    return d
end

function events.GUILD_BAN_REMOVE(d)
    d.user = context.create('user', d.user)
    return d
end

function events.GUILD_EMOJIS_UPDATE(d)
    local emojis = d.emojis
    local guild_id = d.guild_id
    local set = {}
    local ctx = context.get()

    local old = context.property(ctx, 'guild->emoji', guild_id, set)

    for i = 1, #emojis do
        local t = context.create('emoji', emojis[i])
        local ID = t.id

        context.property(ctx, 'emoji->guild', ID, guild_id)
        emojis[i] = t
        set[ID] = true
        old[ID] = nil
    end

    for k in pairs(old) do
        context.unstore(ctx, 'emoji', k)
        context.property(ctx, 'emoji->guild', k, context.DEL)
    end

    return d
end

function events.GUILD_ROLE_CREATE(d)
    guild_property('role', d.guild_id, d.role.id)
    d.role = context.create('role', d, 'create')
    return d
end

function events.GUILD_ROLE_UPDATE(d)
    d.role = context.create('role', d, 'update')
    return d
end

function events.GUILD_ROLE_DELETE(d)
    context.property('guild->role', d.guild_id)[d.id] = nil
    context.property('role->guild', d.role_id, context.DEL)
    d.role = context.unstore('role', d.role_id)
    return d
end

--- Channels ---

function events.CHANNEL_CREATE(d)
    if d.guild_id then
        guild_property('channel', d.guild_id, d.id)
    end
    return context.create('channel', d, 'create')
end

function events.CHANNEL_UPDATE(d)
    return context.create('channel', d, 'update')
end

function events.CHANNEL_DELETE(d)
    local chl = context.unstore('channel', d.id)
    if chl.guild_id then
        context.property('guild->channel', d.guild_id)[d.id] = nil
        context.property('channel->guild', d.id, context.DEL)
    end
    return chl
end

function events.THREAD_CREATE(d)
    local state = d.newly_created and 'create' or 'joined'; d.newly_created = nil
    return context.create('channel', d, 'create'), state
end

function events.THREAD_UPDATE(d)
    return context.create('channel', d, 'update')
end

function events.THREAD_DELETE(d)
    if d.guild_id then
        context.property('guild->channel', d.guild_id)[d.id] = nil
        context.property('channel->guild', d.id, context.DEL)
    end
    return context.unstore('channel', d.id)
end

function events.THREAD_LIST_SYNC(d)
    local len = #d.threads
    local ctx = context.get()
    for i = 1, len do
        d.threads[i] = context.create(ctx, 'channel', d, 'create')
    end
    return d
end

--- Messages ---

function events.MESSAGE_CREATE(d)
    return context.create('message', d, 'create')
end

function events.MESSAGE_UPDATE(d)
    return context.create('message', d, 'update')
end

--- Misc. ---

function events.USER_UPDATE(d)
    local out = context.create('user', d, 'update')
    if d.id == context.property('me', 'id') then
        context.property('me', '*', out)
    end
    return out
end

--- End ---

local function follow_with(outputf, followup, d, ...)
    outputf(...)
    events[followup](d)
end

function bot_t:output()
    local outputf = self.options.output
    return function(the_shard, the_event, d)
        if events[the_event] then
            local d_, state, followup = events[the_event](d)
            if followup then
                the_shard.loop:wrap(follow_with, outputf, followup, d, the_event, d_, state, the_shard)
            else
                the_shard.loop:wrap(outputf, the_event, d_, state, the_shard)
            end
        else
            the_shard.loop:wrap(outputf, the_event, d, nil, the_shard)
        end
    end
end

return _ENV