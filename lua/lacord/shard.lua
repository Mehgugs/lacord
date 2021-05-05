--- The gateway websocket connection container.
-- @module shard

local cqueues = require"cqueues"
local cond = require"cqueues.condition"
local promise = require"cqueues.promise"
local errno = require"cqueues.errno"
local websocket = require"lacord.websocket"
local zlib = require"http.zlib"
local httputil = require"http.util"
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local constants = require"lacord.const"
local mutex = require"lacord.util.mutex".new
local intents = require"lacord.util.intents"
local USER_AGENT = require"lacord.api".USER_AGENT


local setmetatable = setmetatable
local pairs = pairs
local poll = cqueues.poll
local identify_delay = constants.gateway.identify_delay
local sleep = cqueues.sleep
local insert, concat = table.insert, table.concat
local type = type
local traceback = debug.traceback
local xpcall = xpcall
local toquery = httputil.dict_to_query
local tostring = tostring
local min, max = math.min, math.max
local monotime = cqueues.monotime

local encode = require"dkjson".encode
local decode = require"dkjson".decode
local null = require"dkjson".null

local _ENV = {}

local shard = {__name = "lacord.shard"}

shard.__index = shard

function shard:__tostring() return "lacord.shard: "..self.options.id end


local ZLIB_SUFFIX = '\x00\x00\xff\xff'
local GATEWAY_DELAY = constants.gateway.delay
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

local messages, send, read_message, resume, identify, reconnect

--- Construct a new shard object using the given options and identify mutex.
-- @tab options Options to pass to the shard please see `options`.
-- @mutex idmutex The mutex used to synchronize identify between multiple shards.
-- @treturn tab The shard object.
function init(options, idmutex)
    if not (options.token and options.token:sub(1,4) == "Bot ") then
        return logger.fatal("Please supply a bot token")
    end
    local state = setmetatable({options = load_options({intents = intents.normal}, options)}, shard)

    state.shard_mutex = mutex() --+
    state.identify_mutex = idmutex
    state.stop_heart = cond.new()
    state.identify_wait = cond.new()
    state.is_ready = promise.new()
    state.beats = 0
    state.backoff = 1
    logger.info("Initialized %s with TOKEN-%x", state, util.hash(state.options.token))
    if not (state.options.compress or state.options.transport_compression) then
        state.options.transport_compression = true
    end
    state.url_options = toquery({
        v = tostring(constants.gateway.version),
        encoding = constants.gateway.encoding,
        compress = state.options.transport_compression and constants.gateway.compress or nil
    })
    state.loop = state.options.loop
    state.emitter = state.options.output
    return state
end

--- Connects a shard to discord.
-- This can be called in method form `s:connect()`.
-- This function is asynchronous and should be run inside a continuation queue. (usually state.loop)
-- @tab state The shard object.
function shard:connect()
    -- step 1: get a gateway url.
    local final_url
    if type(self.options.gateway) == 'function' then
        logger.info("%s is regenerating gateway url.", self)
        final_url = self.options.gateway(self) .. '?' .. self.url_options
    else
        final_url = self.options.gateway .. '?' .. self.url_options
    end

    -- step 2: connect
    logger.info("%s is connecting to $white;%s", self, final_url)
    self.socket = websocket.new_from_uri(final_url)
    logger.info("Using user-agent: $white;%s", USER_AGENT)
    self.socket.request.headers:upsert("user-agent", USER_AGENT)

    local success, str, err = self.socket:connect(3)

    if not success then
        logger.error("%s had an error while connecting (%s - %q, %q)", self, errno[err], errno.strerror(err), str or "")
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
    while state.connected do
        logger.warn("Outgoing heart beating")
        state.beats = state.beats + 1
        send(state, hb, state._seq or null, true)
        local r1,r2 = poll(state.stop_heart, interval)
        if r1 == state.stop_heart or r2 == state.stop_heart then
            logger.warn("%s heart was stopped via signal", state)
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
    if code ~= 1012 and code < 4000 then self.session_id = nil end
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
    return state, success, err
end

local never_reconnect = {
    [4001] = 'You sent an invalid Gateway opcode or an invalid payload for an opcode. Don\'t do that!'
   ,[4002] = 'You sent an invalid payload to us. Don\'t do that!'
   ,[4004] = 'The account token sent with your identify payload is incorrect.'
   ,[4010] = 'You sent us an invalid shard when identifying.'
   ,[4011] =
   'The session would have handled too many guilds - you are required to shard your connection in order to connect.'
   ,[4013] = 'You sent an invalid intent for a Gateway Intent. You may have incorrectly calculated the bitwise value.'
   ,[4014] = 'You sent a disallowed intent for a Gateway Intent. You may have tried to specify an intent that you have not enabled or are not whitelisted for.'

}

local function should_reconnect(state, code)
   if never_reconnect[code] then
       logger.error("%s received irrecoverable error(%d): %q", state, code, never_reconnect[code])
       return false
   end
   if code == 4004 then
       return logger.fatal("Token is invalid, shutting down.")
   end
   return state.do_reconnect or state.options.auto_reconnect
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
    state.connected = false
    stop_heartbeat(state)

    logger.warn('%s has stopped receiving: (%q) (close code %s) %.3fsec elapsed',
        state,
        err or state.socket.got_close_message,
        state.socket.got_close_code,
        cqueues.monotime() - state.begin
    )

    local do_reconnect = should_reconnect(state, state.socket.got_close_code)

    if state.is_ready:status() == 'pending' and not reconnect then
        state.is_ready:set(false)
    end

    state.loop:wrap(state.emitter,state, 'DISCONNECT', {
         code = state.socket.got_close_code
        ,lua_err = lua_err
        ,error = err
    })

    logger.warn("%s %s reconnect.", state,
        ((do_reconnect and state.do_reconnect) or (do_reconnect and state.options.auto_reconnect))
        and "will" or "will not")
    local retry ::retry::
    if do_reconnect and state.do_reconnect then
        state.do_reconnect = nil
        sleep(util.rand(1, 5))
        local _, success = state:connect()
        if not success then
            backoff(state)
            sleep()
            retry = true
            goto retry
        end
    elseif retry or (do_reconnect and state.options.auto_reconnect) then
        repeat
            local time = util.rand(0.9, 1.1) * state.backoff
            backoff(state)
            logger.info("%s will automatically reconnect in %.2fsec", state, time)
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

function shard:READY(_, d, t)
    logger.info("%s is ready.", self)
    self.session_id = d.session_id
    self.loop:wrap(self.emitter,self, t, d)
end

function shard:RESUMED(_, d, t)
    logger.info("%s has resumed.", self)
    self.loop:wrap(self.emitter,self, t, d)
end

function shard:HEARTBEAT()
    send( self, ops.HEARTBEAT, self._seq or null)
end

function shard:INVALID_SESSION(_, d)
    logger.warn("%s has an invalid session, resumable=%q.", self, d and "true" or "false")
    if not d then self.session_id = nil end
    self.loop:wrap(self.emitter, self, 'INVALID_SESSION', d)
    return reconnect(self, not not d)
end

function shard:HEARTBEAT_ACK()
    self.beats = self.beats -1
    if self.beats < 0 then
        logger.warn("%s is missing heartbeat acknowledgement! (deficit=%s)", self, -self.beats)
    end
    winddown(self)
    self.loop:wrap(self.emitter, self, "HEARTBEAT", self.beats)
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
    if t == 'READY' then return self:READY(_, d, t) end
    return self.loop:wrap(self.emitter,self, t, d)
end

local function await_ready(state)
    if state.identify_wait:wait(1.5 * identify_delay) then
        sleep(identify_delay)
    end
    return state.identify_mutex:unlock()
end

function identify(self)
    self.identify_mutex:lock()


    self.loop:wrap(await_ready, self)

    self._seq = nil ---
    self.session_id = nil
    logger.info("%s has intents: %0#x", self, self.options.intents)
    return send(self, ops.IDENTIFY, {
        token = self.options.token,
        properties = {
            ['$os'] = util.platform,
            ['$browser'] = 'lacord',
            ['$device']  = 'lacord',
            ['$referrer'] = '',
            ['$referring_domain'] = '',
        },
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
-- @treturn[1] table The json object response.
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
-- @treturn[1] table The json object response.
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
-- @treturn[1] table The json object response.
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