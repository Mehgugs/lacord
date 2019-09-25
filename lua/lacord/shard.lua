--- The gateway websocket connection container.
-- @module shard

local cqueues = require"cqueues"
local cond = require"cqueues.condition"
local promise = require"cqueues.promise"
local errno = require"cqueues.errno"
local websocket = require"http.websocket"
local zlib = require"http.zlib"
local httputil = require"http.util"
local json = require"cjson"
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local constants = require"lacord.const"
local mutex = require"lacord.util.mutex".new
local USER_AGENT = require"lacord.api".USER_AGENT

local setmetatable = setmetatable
local pairs, ipairs = pairs, ipairs
local poll = cqueues.poll
local encode, decode = json.encode, json.decode
local identify_delay = constants.gateway.identify_delay
local sleep = cqueues.sleep
local insert, concat = table.insert, table.concat
local floor = math.floor
local traceback = debug.traceback
local xpcall = xpcall
local toquery = httputil.dict_to_query
local tostring = tostring
local null = json.null
local min, max = math.min, math.max
local monotime = cqueues.monotime

local _ENV = util.interposable{}

__index = _ENV
__name = "shard"

local ZLIB_SUFFIX = '\x00\x00\xff\xff'
local GATEWAY_DELAY = constants.gateway.delay
local _ops = {
  DISPATCH              = 0  -- ✅
, HEARTBEAT             = 1  -- ✅
, IDENTIFY              = 2  -- ✅
, STATUS_UPDATE         = 3
, VOICE_STATE_UPDATE    = 4
, VOICE_SERVER_PING     = 5
, RESUME                = 6
, RECONNECT             = 7  -- ✅
, REQUEST_GUILD_MEMBERS = 8
, INVALID_SESSION       = 9  -- ✅
, HELLO                 = 10 -- ✅
, HEARTBEAT_ACK         = 11 -- ✅
}

ops = {} for k, v in pairs(_ops) do ops[k] = v ops[v] = k end


local function load_options(into, o)
    for k, v in pairs(o) do
        into[k] = v
    end
    return into
end

function init(options, idmutex)
    if not (options.token and options.token:sub(1,4) == "Bot ") then
        return logger.fatal("Please supply a bot token")
    end
    local state = setmetatable({options = load_options({}, options)}, _ENV)

    state.shard_mutex = mutex() --+
    state.identify_mutex = idmutex
    state.heart_acknowledged  = cond.new()
    state.stop_heart = cond.new()
    state.identify_wait = cond.new()
    state.is_ready = promise.new()
    state.raw_ready = nil
    state.to_load = -1
    state.loaded = 0
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

function connect(state)
    local final_url = ("%s?%s"):format(state.options.gateway, state.url_options)

    logger.info("%s is connecting to $white;%s", state, final_url)
    state.socket = websocket.new_from_uri(final_url) --++
    logger.info("Using user-agent: $white;%s", USER_AGENT)
    state.socket.request.headers:upsert("user-agent", USER_AGENT)

    local success, str, err = state.socket:connect(3)

    if not success then
        logger.error("%s had an error while connecting (%s - %q, %q)", state, errno[err], errno.strerror(err), str or "")
        return state, false
    else
        logger.info("%s has connected.", state)
        state.connected = true --+
        state.begin = monotime()
        state.raw_ready = promise.new()
        if state.options.transport_compression then
            state.transport_infl = zlib.inflate()
            state.transport_buffer = {}
        end

        state.loop:wrap(messages, state)
        return state, true
    end
end

function backoff(state)
    state.backoff = min(state.backoff * 2, 60)
end

function winddown(state)
    state.backoff = max(state.backoff / 2, 1)
end

local function beat_loop(state, interval)
    while state.connected do
        logger.warn("Outgoing heart beating")
        state.beats = state.beats + 1
        send(state, ops.HEARTBEAT, state._seq or json.null, true)
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

function disconnect(state, why, code)
    state.session_id = nil ---
    state.socket:close(code or 1000, why or 'requested')
    return state
end

function read_message(state, message, op)
    if op == "text" then
        return decode(message)
    elseif op == "binary" then
        if state.options.transport_compression then
            insert(state.transport_buffer, message)
            if #message < 4 or message:sub(-4) ~= ZLIB_SUFFIX then
                return nil, true
            end
            local msg =  state.transport_infl(concat(state.transport_buffer))
            state.transport_buffer = {}
            return decode(msg)
        else
            local infl = zlib.inflate()
            return  decode(infl(message, true))
        end
    end
end

function send(state, op, d, identify)
    state.shard_mutex:lock()
    local success, err
    if identify or state.session_id then
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
}

local function should_reconnect(state, code)
   if never_reconnect[code] then
       logger.error("Shard-%s received irrecoverable error(%d): %q", state.options.id, code, never_reconnect[code])
       return false
   end
   if code == 4004 then
       return logger.fatal("Token is invalid, shutting down.")
   end
   return state.reconnect or state.options.auto_reconnect
end

function messages(state)
    local rec_timeout = state.options.receive_timeout or 60
    local err
    repeat
        local success, message, op, code = xpcall(state.socket.receive, traceback, state.socket, rec_timeout)
        if success and message ~= nil then
            local payload, cont = read_message(state, message, op)
            if cont then goto continue end
            if payload then
                local dop = ops[payload.op]
                if _ENV[dop] then
                    _ENV[dop](state, payload.op, payload.d, payload.t, payload.s)
                end
            else
                disconnect(state, 4000, 'could not decode payload')
            break end
        elseif success and message == nil then
            err = op
        elseif not success then
            err = message
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

    local reconnect = should_reconnect(state, state.socket.got_close_code)

    if state.is_ready:status() == 'pending' and not reconnect then
        state.is_ready:set(false)
    end

    logger.warn("%s %s reconnect.", state, reconnect and "will" or "will not")
    local retry ::retry::
    if reconnect and state.reconnect then
        state.reconnect = nil
        sleep(util.rand(1, 5))
        local _, success = connect(state)
        if not success then
            backoff(state)
            sleep()
            retry = true
            goto retry
        end
    elseif retry or (reconnect and state.options.auto_reconnect) then
        repeat
            local time = util.rand(0.9, 1.1) * state.backoff
            backoff(state)
            logger.info("%s will automatically reconnect in %.2fsec", state, time)
            sleep(time)
            local _, success = connect(state)
        until success or not state.options.auto_reconnect
    end
end

function HELLO(state, _, d)
    logger.info("discord said hello to %s.", state)
    start_heartbeat(state, d.heartbeat_interval/1e3)

    if state.session_id then
        return resume(state)
    else
        return identify(state)
    end
end

function HEARTBEAT(state)
    send(state, ops.HEARTBEAT, state._seq or json.null)
end

function INVALID_SESSION(state, _, d)
    logger.warn("%s has an invalid session, resumable=%q.", state, d and "true" or "false")
    if not d then state.session_id = nil end
    return reconnect(state, not not d)
end

function HEARTBEAT_ACK(state)
    state.beats = state.beats -1
    if state.beats < 0 then
        logger.warn("%s is missing heartbeat acknowledgement! (deficit=%s)", state, -state.beats)
    end
    winddown(state)
    state.emitter(state, "HEARTBEAT", state.beats)
    return state
end

function RECONNECT(state)
    logger.warn("Shard-%s has received a reconnect request.", state)
    return reconnect(state)
end

function reconnect(state, resumable)
    stop_heartbeat(state)
    state.reconnect = true
    if resumable == nil then resumable = true end
    state.socket:close(resumable and 4000 or 1000)
    return state
end

function DISPATCH(state, _, d, t, s)
    state._seq = s --+
    return state.emitter(state, t, d)
end

local function await_ready(state)
    if state.identify_wait:wait(1.5 * identify_delay) then
        sleep(identify_delay)
    end
    return state.identify_mutex:unlock()
end

function identify(state)
    state.identify_mutex:lock()


    state.loop:wrap(await_ready, state)

    state._seq = nil ---
    state.session_id = nil

    return send(state, ops.IDENTIFY, {
        token = state.options.token,
        properties = {
            ['$os'] = util.platform,
            ['$browser'] = 'lacord',
            ['$device']  = 'lacord',
            ['$referrer'] = '',
            ['$referring_domain'] = '',
        },
        compress = state.options.compress,
        large_threshold = state.options.large_threshold,
        shard = {state.options.id, state.options.total_shard_count},
        presence = state.options.presence
    }, true)
end

function resume(state)
    return send(state, ops.RESUME, {
        token = state.options.token,
        session_id = state.session_id,
        seq = state._seq
    })
end

function request_guild_members(state, id)
    return send(state, ops.REQUEST_GUILD_MEMBERS, {
        guild_id = id,
        query = '',
        limit = 0,
    })
end

function update_status(state, presence)
    return send(state, STATUS_UPDATE, presence)
end

function update_voice(state, guild_id, channel_id, self_mute, self_deaf)
    return send(state, VOICE_STATE_UPDATE, {
        guild_id = util.uint.tostring(guild_id),
        channel_id = channel_id and util.uint.tostring(channel_id) or null,
        self_mute = self_mute or false,
        self_deaf = self_deaf or false,
    })
end

return _ENV