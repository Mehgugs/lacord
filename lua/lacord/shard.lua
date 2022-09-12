--- The gateway websocket connection container.
-- @module shard

local cqueues = require"cqueues"
local cond = require"cqueues.condition"
local promise = require"cqueues.promise"
local errno = require"cqueues.errno"
local websocket = require"http.websocket"
local zlib = require"http.zlib"
local httputil = require"http.util"
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local constants = require"lacord.const"
local mutex = require"lacord.util.mutex".new
local session_limiter = require"lacord.util.session-limit".new
local intents = require"lacord.util.intents"
local uripattern = require"lpeg_patterns.uri".absolute_uri
local USER_AGENT = require"lacord.api".USER_AGENT
local LACORD_DEPRECATED = require"lacord.cli".deprecated
local LACORD_UNSTABLE   = require"lacord.cli".unstable

local setmetatable = setmetatable
local pairs = pairs
local poll = cqueues.poll
local sleep = cqueues.sleep
local insert, concat = table.insert, table.concat
local type = type
local traceback = debug.traceback
local xpcall = xpcall
local dict_to_query = httputil.dict_to_query
local query_pairs = httputil.query_args
local tostring = tostring
local min, max = math.min, math.max
local random   = math.random
local monotime = cqueues.monotime
local the_platform = util.platform


local encode = require"lacord.util.json".encode
local decode = require"lacord.util.json".decode
local null = require"lacord.util.json".null

local _ENV = {}

local shard = {__name = "lacord.shard"}

shard.__index = shard

function shard:__tostring() return "lacord.shard: "..self.options.id end


local ZLIB_SUFFIX = '\x00\x00\xff\xff'
local GATEWAY_DELAY = constants.gateway.delay
local IDENTIFY_DELAY = constants.gateway.identify_delay

local GATEWAY_NUM, GATEWAY_PER, GATEWAY_ALLOWANCE if LACORD_UNSTABLE then
    GATEWAY_NUM, GATEWAY_PER = constants.gateway.ratelimit[1], constants.gateway.ratelimit[2]
    GATEWAY_ALLOWANCE = constants.gateway.allowance
end

local _ops = {
  DISPATCH              = 0
, HEARTBEAT             = 1
, IDENTIFY              = 2
, STATUS_UPDATE         = 3
, VOICE_STATE_UPDATE    = 4
, VOICE_SERVER_PING     = 5
, RESUME                = 6
, RECONNECT             = 7
, REQUEST_GUILD_MEMBERS = 8
, INVALID_SESSION       = 9
, HELLO                 = 10
, HEARTBEAT_ACK         = 11
}

local ops = {} for k, v in pairs(_ops) do ops[k] = v ops[v] = k end

_ENV.ops = ops

local function load_options(into, o)
    for k, v in pairs(o) do
        into[k] = v
    end
    return into
end

local messages, send, send_heartbeat, read_message, resume, identify, reconnect, push, push_sync

--- Construct a new shard object using the given options and identify mutex.
-- @tab options Options to pass to the shard please see `options`.
-- @mutex session_limit The session_limit used to synchronize identify between multiple shards.
-- @treturn tab The shard object.
function new(options, session_limit)
    if not (options.token and options.token:sub(1,4) == "Bot ") then
        return logger.fatal("Please supply a bot token")
    end
    local state = setmetatable({options = load_options({intents = intents.normal}, options)}, shard)
    if LACORD_UNSTABLE then
        state.shard_mutex = session_limiter(GATEWAY_NUM - GATEWAY_ALLOWANCE)
        state.heartbeat_mutex = session_limiter(GATEWAY_ALLOWANCE)
    else
        state.shard_mutex = mutex() --+
    end
    state.stop_heart = cond.new()
    state.is_ready = promise.new()
    state.ready_failed = false
    state.session_limit = session_limit
    state.beats = 0
    state.backoff = 1
    logger.info("Initialized %s with TOKEN-%d", state, util.hash(state.options.token))
    if not (state.options.compress or state.options.transport_compression) then
        state.options.transport_compression = true
    end
    state.url_options = {
        v = tostring(constants.gateway.version),
        encoding = constants.gateway.encoding,
        compress = state.options.transport_compression and constants.gateway.compress or nil
    }
    state.loop = state.options.loop
    state.emitter = state.options.output

    if state.options.sync then
        state.push = push_sync
    else
        state.push = push
    end
    return state
end

if LACORD_DEPRECATED then _ENV.init = _ENV.new end

local function build_url(self, url_in) --TODO
    local parts = uripattern:match(url_in)
    local out = {parts.scheme, "://", parts.host}

    if parts.port then
        insert(out, ":")
        insert(out, parts.port)
    end

    insert(out, parts.path)

    local query = {}

    if parts.query and parts.query ~= "" then
        for k ,v in query_pairs(parts.query) do
            query[k] = v
        end
    end

    for k , v in pairs(self.url_options) do
        query[k] = v
    end

    insert(out, "?"..dict_to_query(query))

    return concat(out)
end

--- Connects a shard to discord.
-- This can be called in method form `s:connect()`.
-- This function is asynchronous and should be run inside a continuation queue. (usually state.loop)
-- @tab state The shard object.
function shard:connect()
    -- step 1: get a gateway url.
    local final_url
    if self.resume_url then
        final_url = build_url(self, self.resume_url)
        self.connected_to = self.resume_url
    else
        if type(self.options.gateway) == 'function' then
            logger.info("%s is regenerating gateway url.", self)
            local url = self.options.gateway(self)
            final_url = build_url(self, url)
            self.connected_to = url
        else
            final_url = build_url(self, self.options.gateway)
            self.connected_to = self.options.gateway
        end
    end

    -- step 2: connect
    logger.info("%s is connecting to $%s;", self, final_url)
    self.socket = websocket.new_from_uri(final_url)
    logger.info("Using user-agent: %s", USER_AGENT)
    self.socket.request.headers:upsert("user-agent", USER_AGENT)

    local success, str, err = self.socket:connect(3)

    if not success then
        logger.error("%s had an error while connecting ($%s - %q;, %q).", self, errno[err], errno.strerror(err), str or "")
        return self, false
    else
        logger.info("%s has connected.", self)
        self.connected = true
        self.begin = monotime()
        if self.options.transport_compression then
            self.transport_infl = zlib.inflate()
            self.transport_buffer = {}
        end
        -- step 3: start receiving messages.
        self.loop:wrap(messages, self)
        return self, true
    end
end

local function backoff(state)
    state.backoff = min(state.backoff * 2, 60)
end

local function winddown(state)
    state.backoff = max(state.backoff / 2, 1)
end


local hb = ops.HEARTBEAT
local function beat_loop(state, interval)
    sleep(interval * random())
    while state.connected do
        logger.debug("Outgoing heart beating.")
        state.beats = state.beats + 1
        send_heartbeat(state, hb, state._seq or null, true)
        local r1,r2 = poll(state.stop_heart, interval)
        if r1 == state.stop_heart or r2 == state.stop_heart then
            logger.warn("%s heart was stopped via signal.", state)
            break
        end
    end
end

local function stop_heartbeat(state)
    return state.stop_heart:signal(1)
end

local function start_heartbeat(state, interval)
    state.loop:wrap(beat_loop, state, interval)
end

--- Triggers a disconnect.
-- This can be called in method form `s:disconnect()`.
-- This will not stop an automatically connecting shard, please see `shutdown`.
-- @tab state The shard object.
-- @str[opt="requested"] why The disconnect reason.
-- @int[opt=4009] code The disconnect code.
-- @treturn table The shard object.
function shard:disconnect(why, code)
    -- reset our session if we're not requesting a restart.
    code = code or 4009
    if code ~= 1012 and code < 4000 then
        self.session_id = nil
        self.resume_url = nil
    end
    self.socket:close(code, why or 'requested')
    return self
end

--- This will terminate the shard's connection, clearing any reconnection flags and then disconnecting.
-- This can be called in method form `s:shutdown()`.
-- @tab state The shard object.
-- @param[opt] ... Arguments to `disconnect`.
-- @treturn table The shard object.
function shard:shutdown(...)
    self.options.auto_reconnect = nil
    self.do_reconnect = nil
    return self:disconnect(...)
end

function shard:restart(why)
    logger.info("%s is requesting a restart.", self)
    return self:disconnect(why)
end

-- note: the () around decode is a lua-ism to adjust the returns to 1 value, so that they dont trip `cont' checking.
function read_message(state, message, op)
    if op == "text" then
        return (decode(message))
    elseif op == "binary" then
        if state.options.transport_compression then
            insert(state.transport_buffer, message)
            if #message < 4 or message:sub(-4) ~= ZLIB_SUFFIX then
                return nil, true
            end
            local msg =  state.transport_infl(concat(state.transport_buffer))
            state.transport_buffer = {}
            return (decode(msg))
        else
            local infl = zlib.inflate()
            return  (decode(infl(message, true)))
        end
    end
end

if LACORD_UNSTABLE then
    function send(state, op, d, ident)
        state.shard_mutex:enter()
        local success, err
        if ident or state.session_id then
            if state.connected then
                success, err = state.socket:send(encode {op = op, d = d}, 0x1, state.options.rec_timeout or 60)
            else
                success, err = false, 'Not connected to gateway'
            end
        else
            success, err = false, 'Invalid session'
        end
        state.shard_mutex:exit_after(GATEWAY_PER)
        return success, err
    end
    function send_heartbeat(state, op, d, ident)
        state.heartbeat_mutex:enter()
        local success, err
        if ident or state.session_id then
            if state.connected then
                success, err = state.socket:send(encode {op = op, d = d}, 0x1, state.options.rec_timeout or 60)
            else
                success, err = false, 'Not connected to gateway'
            end
        else
            success, err = false, 'Invalid session'
        end
        state.heartbeat_mutex:exit_after(GATEWAY_PER)
        return success, err
    end
else
    function send(state, op, d, ident)
        state.shard_mutex:lock()
        local success, err
        if ident or state.session_id then
            if state.connected then
                success, err = state.socket:send(encode {op = op, d = d}, 0x1, state.options.rec_timeout or 60)
            else
                success, err = false, 'Not connected to gateway'
            end
        else
            success, err = false, 'Invalid session'
        end
        state.shard_mutex:unlock_after(GATEWAY_DELAY)
        return success, err
    end
    send_heartbeat = send
end

local never_reconnect = {
    [4010] = 'You sent us an invalid shard when identifying.'
   ,[4011] =
   'The session would have handled too many guilds - you are required to shard your connection in order to connect.'
   ,[4012] = 'You sent an invalid version for the gateway.'
   ,[4013] = 'You sent an invalid intent for a Gateway Intent. You may have incorrectly calculated the bitwise value.'
   ,[4014] = 'You sent a disallowed intent for a Gateway Intent. You may have tried to specify an intent that you have not enabled or are not whitelisted for.'

}

local function should_reconnect(state, code)
   if never_reconnect[code] then
       logger.error("%s received irrecoverable error ($%d;, %q).", state, code, never_reconnect[code])
       return false
   end
   if code == 4004 then
       return logger.fatal("Token is invalid, shutting down.")
   end
   return state.do_reconnect or state.options.auto_reconnect
end

function push(self, ...)
    self.loop:wrap(self.emitter, self, ...)
end

function push_sync(self, ...)
    self:emitter(...)
end

function messages(state)
    local rec_timeout = state.options.receive_timeout or 60
    local err, lua_err
    repeat
        local success, message, op, code = xpcall(state.socket.receive, traceback, state.socket, rec_timeout)
        if success and message ~= nil then
            local payload, cont = read_message(state, message, op)
            if cont then goto continue end
            if payload then
                local dop = ops[payload.op]
                if shard[dop] then
                    shard[dop](state, payload.op, payload.d, payload.t, payload.s)
                end
            else
                state:disconnect(4000, 'could not decode payload')
            break end
        elseif success and message == nil then
            err = op
            lua_err = false
        elseif not success then
            err = message
            lua_err = true
        end
        ::continue::
    until state.socket.got_close_code or message == nil or not success
    --disconnect handling

    -- we need to do both of these things to ensure the heartbeat is stopped in a timely manner.
    state.connected = false
    stop_heartbeat(state)

    logger.warn('%s has stopped receiving: (%q) ($close code %s;) %.3f sec elapsed',
        state,
        err or state.socket.got_close_message,
        state.socket.got_close_code,
        cqueues.monotime() - state.begin
    )

    -- Based on the close code / state.do_reconnect flag
    local decided = should_reconnect(state, state.socket.got_close_code)

    -- If we never kept the ready promise (i.e we never got READY)
    -- we should break it if we're not planning to reconnect.
    -- If we are **not** reconnecting we need to exit the session limit.
    if state.is_ready:status() == 'pending' then
        if not decided then
            state.is_ready:set(false)
            if state.session_limit then
                state.session_limit:exit_after(IDENTIFY_DELAY)
            end
        else
            state.ready_failed = true
        end
    end

    state:push('DISCONNECT', {
         code = state.socket.got_close_code
        ,lua_err = lua_err
        ,error = err
        ,reconnect = decided
        ,ready = state.is_ready:status()
    })

    logger.warn("%s $%s; reconnect.", state, decided and "will" or "will not")

    local retry ::retry::
    -- even though decided can be assigned the value of
    -- do_reconnect we need to explicitly check it
    -- like this to avoid errors with state being clobbered.
    if decided and state.do_reconnect then
        state.do_reconnect = nil
        sleep(util.rand(1, 5))
        local _, success = state:connect()
        if not success then
            backoff(state)
            sleep()
            retry = true
            goto retry
        end
    elseif retry or (decided and state.options.auto_reconnect) then
        repeat
            local time = util.rand(0.9, 1.1) * state.backoff
            backoff(state)
            logger.info("%s will automatically reconnect in $%.2f; sec", state, time)
            sleep(time)
            local _, success = state:connect()
        until success or not state.options.auto_reconnect
    end
end

function shard:HELLO(_, d)
    logger.info("discord said hello to %s.", self)
    start_heartbeat(self, d.heartbeat_interval/1e3)
    if self.session_id then
        return resume(self)
    else
        return identify(self)
    end
end

function shard:READY(_, d)
    logger.info("%s is ready.", self)
    self.session_id = d.session_id
    self.resume_url = d.resume_url
    self:push('SHARD_READY', d)
    self.is_ready:set(true, d)
    if self.session_limit then
        self.session_limit:exit_after(IDENTIFY_DELAY)
    end
end

function shard:RESUMED(_, d)
    logger.info("%s has resumed.", self)
    self:push('SHARD_RESUMED', d)
end


local function and_then(time, f, ...)
    sleep(time)
    return f(...)
end


function shard:INVALID_SESSION(_, d)
    logger.warn("%s has an invalid session, ($resumable=%s;).", self, d and "true" or "false")
    local resumeurl = self.resume_url

    if not d then
        self.session_id = nil
        self.resume_url = nil
    end
    self:push('INVALID_SESSION', d)

    if d then
        if self.connected_to ~= resumeurl then
            logger.debug('%s has a resume_url=%s; reconnecting to it.', self, resumeurl)
            return reconnect(self)
        else
            logger.debug('%s is connected to its resume_url; resuming diretly.', self)
            return resume(self)
        end
    else
        if self.connected_to == resumeurl then
            logger.debug('%s is connected to its resume_url; dropping back to main gateway.', self)
            return reconnect(self)
        else
            return self.loop:wrap(and_then, math.random()*4 + 1, identify, self)
        end
    end
end

function shard:HEARTBEAT_ACK()
    self.beats = self.beats -1
    if self.beats < 0 then
        logger.warn("%s is missing heartbeat acknowledgement! ($deficit=%s;)", self, -self.beats)
    end
    winddown(self)
    self:push("HEARTBEAT", self.beats)
    return self
end

function shard:RECONNECT()
    logger.warn("%s has received a reconnect request from discord.", self)
    return reconnect(self)
end

function reconnect(state)
    stop_heartbeat(state)
    state.do_reconnect = true
    state.socket:close(4009)
    return state
end

function shard:DISPATCH(_, d, t, s)
    self._seq = s --+
    if t == 'READY' then return self:READY(_, d, t)
    elseif t == 'RESUMED' then return self:RESUMED(_,d, t)
    end
    return self:push(t, d)
end

local IDENTIFY_PROPERTIES = {
    os      = the_platform,
    browser = "lacord",
    device  = "lacord",
}

function identify(self)
    -- If we were ready in the past and are being asked to identify
    -- again we need to create a new promise to keep when we receive READY
    if self.is_ready:status() ~= "pending" then
        self.is_ready = promise.new()
    end

    -- If we failed to ready up, then we're already "entered" into the
    -- session limit. So we should only :enter() in the case where ready_failed is false.
    if not self.ready_failed and self.session_limit then
        self.session_limit:enter()
    end
    self.ready_failed = false

    self._seq = nil ---
    self.session_id = nil
    self.resume_url = nil
    logger.info("%s has intents: %0#x", self, self.options.intents)
    send(self, ops.IDENTIFY, {
        token = self.options.token,
        properties = IDENTIFY_PROPERTIES,
        compress = self.options.compress,
        large_threshold = self.options.large_threshold,
        shard = {self.options.id, self.options.total_shard_count},
        presence = self.options.presence,
        intents = self.options.intents
    }, true)
end

function resume(self)
    return send(self, ops.RESUME, {
        token = self.options.token,
        session_id = self.session_id,
        seq = self._seq
    })
end

--- Sends a REQUEST_GUILD_MEMBERS request.
-- @tab state The shard object.
-- @int id The guild id.
-- @treturn[1] bool true If the message was sent successfully.
-- @treturn[2] bool false If the message was not sent successfully.
-- @return[2]  An error describing what went wrong.
function shard:request_guild_members(id)
    return send(self, ops.REQUEST_GUILD_MEMBERS, {
        guild_id = id,
        query = '',
        limit = 0,
    })
end

--- Sends a STATUS_UPDATE request.
-- @tab state The shard object.
-- @tab presence The new presence for the bot. Please see the discord documentation.
-- @treturn[1] bool true If the message was sent successfully.
-- @treturn[2] bool false If the message was not sent successfully.
-- @return[2]  An error describing what went wrong.
function shard:update_status(presence)
    return send(self, ops.STATUS_UPDATE, presence)
end

--- Sends a VOICE_STATE_UPDATE request.
-- @tab state The shard object.
-- @int guild_id The guild id of the guild the voice channel is in.
-- @int channel_id The voice channel id.
-- @bool self_mute Whether the bot is muted.
-- @bool self_deaf Whether the bot is deafened.
-- @treturn[1] bool true If the message was sent successfully.
-- @treturn[2] bool false If the message was not sent successfully.
-- @return[2]  An error describing what went wrong.
function shard:update_voice(guild_id, channel_id, self_mute, self_deaf)
    return send(self, ops.VOICE_STATE_UPDATE, {
        guild_id = guild_id,
        channel_id = channel_id and channel_id or null,
        self_mute = self_mute or false,
        self_deaf = self_deaf or false,
    })
end

return _ENV