local iter = pairs
local setm = setmetatable
local type = type

local max = math.max

local api            = require"lacord.api"
local command        = require"lacord.command"
local cond           = require"cqueues.condition"
local context        = require"lacord.models.context"
local cqs            = require"cqueues"
local intents        = require"lacord.util.intents"
local logger         = require"lacord.util.logger"
local numbers        = require"lacord.models.magic-numbers"
local setup          = require"lacord.models.impl"
local interaction    = require"lacord.models.interaction"
local shard          = require"lacord.shard"
local signal         = require"cqueues.signal"
local in_environment = require"lacord.ui".in_environment

local itypes = numbers.interaction_type

local new_sessionlimit = require"lacord.util.session-limit".new

local TABLE = context.upserters.TABLE

local function guild_property(type, guild_id, obj_id)
    local set = context.upsert('guild->'..type, guild_id, TABLE)
    set[obj_id] = true
end


--local _ENV = {}

local bot = {__name = "lacord.gateway-bot"}

bot.__index = bot

local interaction_filter
function new(token, options)
    if type(options) == 'function' then options = {output = options}
    elseif not options then options = {}
    end

    if options.api then options.api.token = token end
    local discord = api.new(options.api or token)


    return setm({
        api = discord,
        shards = {},
        options = options,
        global_handlers = {},
    }, bot)
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
        if self.options.commands then
            command.deploy(self.app.id, self.options.commands.global, self.options.commands.guilds)
        else
            command.load(self.app.id)
        end
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

        context.property('shards-alive', '*', gateway.shards)

        self.gateway = gateway
        self.gateway.session_limiter = sessionlimit

        if self.options.handle_signals then
            self.loop:wrap(handlesignals, self)
        end

    else
        logger.error(R.error)
    end
end


local function executor(loop, ref)
    while not (loop:empty() or ref.value)  do
        if cqs.poll(loop, ref.cv) == loop then
            local success, why = loop:step(0.0)
            if not success then
                logger.error(why)
                break
            end
        end
    end
end

function bot:run(loop)
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

    local outer = cqs.new()
    local cancel = {cv = cond.new()}

    context.property(_ctx, 'cancellation-cv', '*', cancel)

    outer:wrap(executor, loop, cancel)

    return assert(outer:loop())
end

function bot.me()
    return context.property'me'
end

local events = { }

_ENV.event_handlers = events

function events.DISCONNECT(d)
    if not d.reconnect then
        local count = context.property'shards-alive'
        context.property('shards-alive', '*', count - 1)
        if (count - 1) == 0 then
            local ref = context.property'cancellation-cv'
            ref.value = true
            ref.cv:signal()
        end
    end
end

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
    local guild_id = d.id
    local lenc, lent = #chls, #thds
    local bigger = max(lenc, lent)
    local smaller = bigger == lenc and lent or lenc

    for i = 1, smaller do
        chls[i].guild_id = guild_id
        thds[i].guild_id = guild_id
        local c = context.create('channel', chls[i])
        local t = context.create('channel', thds[i])
        guild_property('channel', guild_id, c.id)
        guild_property('channel', guild_id, t.id)
    end

    local left = bigger == lenc and chls or thds
    for i = smaller + 1, bigger do
        left[i].guild_id = guild_id
        local c = context.create('channel', left[i])
        guild_property('channel', guild_id, c.id)
    end
end

local function populate_others(d)
    local chls, thds = d.roles, d.emojis
    local guild_id = d.id
    local lenc, lent = #chls, #thds
    local bigger = max(lenc, lent)
    local smaller = bigger == lenc and lent or lenc

    for i = 1, smaller do
        chls[i].guild_id = guild_id
        thds[i].guild_id = guild_id
        local c = context.create('role', chls[i])
        local t = context.create('emoji', thds[i])
        guild_property('role', d.id, c.id)
        guild_property('emoji', d.id, t.id)
    end

    local left = bigger == lenc and chls or thds
    local typ = left == chls and 'role' or 'emoji'
    for i = smaller + 1, bigger do
        left[i].guild_id = guild_id
        local c = context.create(typ, left[i])
        guild_property(typ, d.id, c.id)
    end
end

function events.GUILD_CREATE(d, handlers)
    if d.unavailable then
        return context.create('guild', d, 'create'), 'outage'
    end
    local old = context.request('guild', d.id)
    d._status = 'connected'
    populate_channels(d)
    populate_others(d)

    if handlers and not context.property('guild->command', d.id) then
        cqs.running():wrap(command.load, context.property('application', 'id'), d.id)
    end

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
    context.property(ctx, 'guild->command', d.id, context.DEL)
    for type in iter(guild_entities) do
        context.property(ctx, 'guild->'..type, d.id, context.DEL)
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
        emojis[i].guild_id = guild_id
        local t = context.create('emoji', emojis[i])
        local ID = t.id


        emojis[i] = t
        set[ID] = true
        old[ID] = nil
    end

    for k in pairs(old) do
        context.unstore(ctx, 'emoji', k)
    end

    return d
end

function events.GUILD_ROLE_CREATE(d)
    guild_property('role', d.guild_id, d.role.id)
    d.role.guild_id = d.guild_id
    d.role = context.create('role', d.role, 'create')
    return d
end

function events.GUILD_ROLE_UPDATE(d)
    d.role.guild_id = d.guild_id
    d.role = context.create('role', d.role, 'update')
    return d
end

function events.GUILD_ROLE_DELETE(d)
    context.property('guild->role', d.guild_id)[d.id] = nil
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
    --local old = context.request('channel', d.id)
    --if old and old.guild_id then d.guild_id = old.guild_id end
    return context.create('channel', d, 'update')
end

function events.CHANNEL_DELETE(d)
    local chl = context.unstore('channel', d.id)
    if chl.guild_id then
        context.property('guild->channel', d.guild_id)[d.id] = nil
    end
    return chl
end

function events.THREAD_CREATE(d)
    local state = d.newly_created and 'create' or 'joined'; d.newly_created = nil
    return context.create('channel', d, 'create'), state
end

function events.THREAD_UPDATE(d)
    --local old = context.request('channel', d.id)
    --if old and old.guild_id then d.guild_id = old.guild_id end
    return context.create('channel', d, 'update')
end

function events.THREAD_DELETE(d)
    if d.guild_id then
        context.property('guild->channel', d.guild_id)[d.id] = nil
    end
    return context.unstore('channel', d.id)
end

function events.THREAD_LIST_SYNC(d)
    local len = #d.threads
    local ctx = context.get()
    local guild_id = d.guild_id
    for i = 1, len do
        d.threads[i].guild_id = guild_id
        d.threads[i] = context.create(ctx, 'channel', d.threads[i], 'create')
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

function events.INTERACTION_CREATE(d)
    return context.create('interaction', d, 'create')
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

function bot:output()
    local outputf = self.options.output
    local filters = self.options.filters
    local has_handlers = not not self.guild_handlers
    return function(the_shard, the_event, d)
        if events[the_event] then
            local d_, state, followup = events[the_event](d, has_handlers)
            if followup then
                the_shard.loop:wrap(follow_with, outputf, followup, d, the_event, d_, state, the_shard)
            else
                if filters and filters[the_event] then
                    local filter = filters[the_event]
                    local cb, A = filter(self, d_)
                    if cb then
                        the_shard.loop:wrap(cb, d_, state, the_shard, A)
                    else
                        the_shard.loop:wrap(outputf, the_event, d_, state, the_shard)
                    end
                else
                    the_shard.loop:wrap(outputf, the_event, d_, state, the_shard)
                end
            end
        else
            the_shard.loop:wrap(outputf, the_event, d, nil, the_shard)
        end
    end
end


local function find_handler(self, d, hnd)
    local name = d.command_name
    if hnd[name] then return hnd[name]
    elseif self.options.command_fallback then
        local root = d.root
        local group = d.group and (d.root.." "..d.group)
        if group and hnd[group] then
            return hnd[group]
        else return hnd[root]
        end
    end
end


local function run_instance(I, _, _, inst)
    local action = inst._actions[I.data.custom_id]
    if action then
        in_environment(inst)
        inst._interface._actions[action](inst, I, interaction.values(I))
    elseif inst.interface._callback then
        in_environment(inst)
        inst._interface._callback(inst, I, interaction.values(I))
    end
end

local function ignore(I)
    return interaction.ack(I)
end

function interaction_filter(self, d)
    if d.type == itypes.COMMAND then
        if d.data.guild_id then
            if self.guild_handlers and self.guild_handlers[d.data.guild_id] then
                return find_handler(self, d, self.guild_handlers[d.data.guild_id])
            end
        else
            return find_handler(self, d, self.global_handlers)
        end
    elseif d.type == itypes.COMPONENT then
        local instance_id do
            local start = d.data.custom_id:find('.', 1, true)
            instance_id = d.data.custom_id:sub(1, start - 1)
        end

        local inst = context.property('ui', instance_id)

        if inst then
            if inst._target and ((d.member and d.member.user or d.user).id ~= inst._target) then
                return ignore, d
            elseif inst._filter and (not inst._filter(d)) then
                return ignore, d
            end
            return run_instance, inst
        end
    end
end

--- handle("name", fn)
--- handle("name", guild_id, fn)
function bot:handle(name, fn, extra)
    self.options.filters = self.options.filters or {}

    self.options.filters.INTERACTION_CREATE
    = self.options.filters.INTERACTION_CREATE or interaction_filter

    if extra then
        self.guild_handlers  = self.guild_handlers or {}
        self.guild_handlers[fn] = self.global_handlers[fn] or {}
        self.global_handlers[fn][name] = extra
    else
        self.global_handlers[name] = fn
    end
end

return _ENV