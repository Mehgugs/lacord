--- Discord REST API
-- Dependencies:
-- @module api

local cqueues = require"cqueues"
local errno = require"cqueues.errno"
local newreq = require"http.request"
local reason = require"http.h1_reason_phrases"
local httputil = require "http.util"
local zlib = require"http.zlib"
local json = require"cjson"
local base64 = require"basexx".to_base64
local constants = require"lacord.const"
local mutex = require"lacord.util.mutex".new
local Date = require"lacord.util.date".Date
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local inflate = zlib.inflate
local JSON = "application/json"
local tostring = tostring
local difftime = os.difftime
local time = os.time
local insert, concat = table.insert, table.concat
local next, tonumber = next, tonumber
local setmetatable = setmetatable
local max = math.max
local min = math.min
local modf = math.modf
local xpcall = xpcall
local traceback = debug.traceback
local type = type
local ipairs, pairs = ipairs, pairs
local ulen = utf8.len
local _VERSION = _VERSION
local decode = json.decode
local set = rawset

local _ENV = util.interposable{}

__index = _ENV
__name = "lacord.api"

--- The api URL the client uses connect.
-- @string URL
-- @within Constants
URL = constants.api.endpoint

--- The user-agent used to connect with. (mandated by discord)
-- @string USER_AGENT
-- @within Constants
USER_AGENT = ("DiscordBot (%s, %s) lua-version:\"%s\""):format(constants.homepage,constants.version, _VERSION )


GLOBAL_LOCK = mutex()

local BOUNDARY1 = "lacord" .. ("%x"):format(util.hash(tostring(time())))
local BOUNDARY2 = "--" .. BOUNDARY1
local BOUNDARY3 = BOUNDARY2 .. "--"

local MULTIPART = ("multipart/form-data;boundary=%s"):format(BOUNDARY1)

local with_payload = {
    PUT = true,
    PATCH = true,
    POST = true,
}

local caches = {}

local function mutex_cache(token)
    return caches[token] or set(caches, token, setmetatable({},
    {
        __mode = "v",
        __index = function (self, k)
            self[k] = mutex(k)
            return self[k]
        end
    }))[token]
end

local function attachContent(payload, files, ct, inner_ct)
    local ret = {
        BOUNDARY2,
        "Content-Disposition:form-data;name=\"payload_json\"",
        ("Content-Type:%s\r\n"):format(ct),
        payload,
    }
    for i, v in ipairs(files) do
        insert(ret, BOUNDARY2)
        insert(ret, ("Content-Disposition:form-data;name=\"file%i\";filename=%q"):format(i, v[1]))
        insert(ret, ("Content-Type:%s\r\n"):format(inner_ct))
        insert(ret, v[2])
    end
    insert(ret, BOUNDARY3)
    return concat(ret, "\r\n")
end

local function attachFiles (payload, files, ct)
    return attachContent(payload, files, ct, "application/octet-stream")
end

local function attachTextFiles(payload, files, ct)
    return attachContent(payload, files, ct, "text/plain")
end

local function resolve_endpoint(ep, rp)
    return ep:gsub(":([a-z_]+)", rp)
end

local function resolve_majors(ep, rp)
    local mp = {}
    if ep:find('/channels/', 1, true) then
        insert(mp, rp.channel_id)
    end
    if ep:find('/guilds/', 1, true) then
        insert(mp, rp.guild_id)
    end
    if ep:find('/webhooks/', 1, true) then
        insert(mp, rp.webhook_id)
        insert(mp, rp.webhook_token)
    end
    return #mp == 0 and '' or concat(mp, ".")
end

--- Creates a new api state for connecting to discord.
-- @tab options The options table. Must contain a `token` field with the api token to use.
-- @treturn api The api state object.
function init(options)
    local state = setmetatable({}, _ENV)
    local auth
    if options.client_credentials then
        auth = "Basic " .. base64(("%s:%s"):format(options.client_credentials[1], options.client_credentials[2]))
    elseif options.token and options.token:sub(1,4) == "Bot " or options.token:sub(1,7) == "Bearer " then
        auth = options.token
    else
        return logger.fatal("Please supply a token! It must start with $white;'Bot|Bearer '$error;.")
    end
    state.token = auth
    state.routex = mutex_cache(auth)
    state.global_lock = GLOBAL_LOCK
    state.rates = {}
    state.track_rates = options.track_ratelimits
    state.use_legacy = options.legacy_ratelimits
    state.route_delay = options.route_delay and min(options.route_delay, 0) or 1
    state.http_version = options.http_version
    state.api_timeout = tonumber(options.api_timeout)
    state.loud = not options.quiet
    if not not options.accept_encoding then
        state.accept_encoding = "gzip, deflate, x-gzip"
        if state.loud then
            logger.info("%s is using $white;accept-encoding: %q", state, state.accept_encoding)
        end
    end

    if state.loud then
        logger.info("Initialized %s with TOKEN-%x", state, util.hash(state.token))
    end
    return state
end

local function mapquery(Q)
    local out = {}
    for i, v in pairs(Q) do out[i] = tostring(v) end
    return out
end

local function get_routex(ratelimits, key)
    local item = ratelimits[key]
    if type(item) == 'string' then return get_routex(ratelimits, item)
    else return item, key
    end
end

local function resolve_global_unlocks(global, bucket, initial)
    global.pollfd:wait() -- we must wait for the global limit to expire before potentially resuming a request
    if initial ~= bucket then
        initial:unlock()
    end
    return bucket:unlock() -- now we can call unlock
end

local push

--- The api state object.
-- @table api
-- @see api.init
-- @within Objects
-- @string token The bot token
-- @string id The RID for this api state.

--- Makes a request to discord.
-- @tab state The api state.
-- @string method The HTTP method to use.
-- @string endpoint The endpoint to connect to.
-- @tab[opt={}] payload An optional payload for PUT/PATCH/POST requests.
-- @tab[opt={}] query An optional table to convert into a url query string, appended to the URL.
-- @tab[opt=nil] files An optional table of files to upload in a multi-part formdata request.
-- @treturn boolean Whether the request succeeded.
-- @treturn table The decoded JSON data returned by discord.
-- @return An error if the request did not succeed.
function request(state,
    name, -- function name
    method, -- http method
    endpoint, -- uninterpolated endpoint
    route_parameters, -- a table of route parameters
    payload, -- a json payload
    query, -- a query string
    files, -- a list of files
    asText -- should it be text files or binary?
)
    if not cqueues.running() then
        return logger.fatal("Please call REST methods asynchronously.")
    end
    local resolved_ep = resolve_endpoint(endpoint, route_parameters)
    local url = URL .. resolved_ep
    if query and next(query) then
        url = ("%s?%s"):format(url, httputil.dict_to_query(mapquery(query)))
    end
    url = httputil.encodeURI(url)
    local req = newreq.new_from_uri(url)
    req.headers:upsert(":method", method)
    req.headers:upsert("user-agent", USER_AGENT)
    req.headers:append("authorization", state.token)
    if state.accept_encoding then
        req.headers:append("accept-encoding", state.accept_encoding)
    end
    if state.http_version then
        req.version = state.http_version
    end
    if with_payload[method] then
        local mt = getmetatable(payload)
        local content_type
        if mt and mt.__lacord_content_type then
            payload = mt.__lacord_payload(payload)
            content_type = mt.__lacord_content_type
        else
            payload = payload and json.encode(payload) or '{}'
            content_type = JSON
        end
        if files and next(files) then
            payload = (asText and attachTextFiles or attachFiles)(payload, files, content_type)
            req.headers:append('content-type', MULTIPART)
        else
            req.headers:append('content-type', content_type)
        end
        req.headers:append("content-length", #payload)
        req:set_body(payload)
    end

    local major_params = resolve_majors(endpoint, route_parameters)
    if state.global_lock.inuse then state.global_lock.polldfd:wait() end

    local initial, bucket = get_routex(state.routex, method .. major_params .. name)

    initial:lock()

    local success, data, err, delay, global = xpcall(push, traceback, state, name, req, method, major_params, 0)
    if not success then
        return logger.fatal("api.push failed %q", tostring(data))
    end

    local final = get_routex(state.routex, bucket)
    if global then
        state.global_lock:unlock_after(delay)
        cqueues.running():wrap(resolve_global_unlocks, state.global_lock, final, initial)
    else
        if final ~= initial then
           initial:unlock_after(delay)
        end
        final:unlock_after(delay)
        state.global_lock:unlock()
    end

    return not err, data, err
end

function push(state, name, req, method, major_params, retries)
    local delay = state.route_delay -- seconds
    local global = false -- whether the delay incurred is on the global limit
    local ID = method..major_params .. name
    local headers , stream , eno = req:go(state.api_timeout or 60)

    if not headers and retries < constants.api.max_retries then
        local rsec = util.rand(1, 2)
        logger.warn("%s failed to %s because %q (%s, %q) retrying after %.3fsec",
            state, ID, tostring(stream), errno[eno], errno.strerror(eno), rsec
        )
        cqueues.sleep(rsec)
        return push(state, name, req, method,major_params, retries+1)
    elseif not headers and retries >= constants.api.max_retries then
        return nil, errno.strerror(eno), delay, global
    end
    local code, rawcode,stat

    stat = headers:get":status"
    rawcode, code = stat, tonumber(stat)

    local date = headers:get"date"
    local remaining =  headers:get"x-ratelimit-remaining"
    local reset = headers:get"x-ratelimit-reset"
    local reset_after = headers:get"x-ratelimit-reset-after"
    reset = reset and tonumber(reset)
    local drift
    if remaining == '0' and reset then
        reset_after = tonumber(reset_after)
        if state.use_legacy then
            local secs, rest = modf(reset)
            local dt = difftime(secs, Date.parseHeader(date))
            drift = reset_after - dt
            delay = max(dt+rest, delay)
        else
            delay = max(delay, reset_after)
        end
    end

    local route_id = headers:get"x-ratelimit-bucket"
    if route_id then
        local bucket = major_params == "" and route_id or major_params .. "." .. route_id
        if state.track_rates then
            state.rates[name] = {
                date = date
                ,bucket = bucket
                ,last_used_by = ID
                ,reset = reset
                ,remaining = remaining
                ,reset_after = headers:get"x-ratelimit-reset-after"
                ,limit = headers:get"x-ratelimit-limit"
                ,drift = drift or state.rates[name] and state.rates[name].drift
            }
        end
        if state.routex[ID] ~= bucket then
            logger.info("%s grouping route $white;%q$info; into bucket $white;%s$info;.",
                state,
                ID,
                route_id)
            local routex = state.routex[bucket]
            routex.inuse = true
            state.routex[ID] = bucket
        end
    end

    local raw = stream:get_body_as_string()

    if headers:get"content-encoding" == "gzip"
    or headers:get"content-encoding" == "deflate"
    or headers:get"content-encoding" == "x-gzip" then
        raw = inflate()(raw, true)
    end

    local data = state.raw and raw or headers:get"content-type" == JSON and decode(raw) or raw
    if code < 300 then
        if code == 204 then return true, nil, delay, global
        else return data, nil, delay, global
        end
    else
        if state.raw then
            data = headers:get"content-type" == JSON and decode(raw) or raw
        end
        if type(data) == 'table' then
            local retry;
            if code == 429 then
                delay = data.retry_after
                global = data.global
                retry = retries < 5
            elseif code == 502 then
                delay = delay + util.rand(0 , 2)
                retry = retries < 5
                global = headers:get"x-ratelimit-global"
            end

            if retry then
                logger.warn("(%i, %q) :  retrying after %fsec : %s", code, reason[rawcode], delay, ID)
                if global then state.global_lock:unlock_after(delay) end
                cqueues.sleep(delay)
                return push(state, name, req, method, major_params, retries+1)
            end

            local msg
            if data.code and data.message then
                msg = ('HTTP Error %i : %s'):format(data.code, data.message)
            else
                msg = 'HTTP Error'
            end
            --TODO: handle data.errors again
            data = msg
        else
            global = headers:get"x-ratelimit-global"
        end
        logger.error("(%i, %q) : %s", code, reason[rawcode], ID)
        return nil, data, delay, global
    end
end

--- Request a specific resource.
-- Function name is the routepath in snake_case
-- Please see the [discord api documentation](https://discordapp.com/developers/docs/reference) for requesting specific routes.
-- @function route_path
-- @tab state The api state.
-- @param ... Parameters to the request
-- @return @{api.request}
-- @usage
--  api.get_channel(state, id)

local empty_route = {}
function get_current_application_information(state)
    return request(state, 'get_current_application_information', 'GET', '/oauth2/applications/@me', empty_route)
end

function get_gateway_bot(state)
    return request(state, 'get_gateway_bot', 'GET', '/gateway/bot', empty_route)
end

function create_message(state, channel_id, payload, files)
    return request(state, 'create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files)
end

function create_message_with_txt(state, channel_id, payload, files)
    return request(state, 'create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files, true)
end

function delete_message(state, channel_id, message_id)
    return request(state, 'delete_message', 'DELETE', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function get_pinned_messages(state, channel_id)
    return request(state, 'get_pinned_messages', 'GET', '/channels/:channel_id/pins', {
        channel_id = channel_id
    })
end

function delete_pinned_channel_message(state, channel_id, message_id)
    return request(state, 'get_pinned_messages', 'DELETE', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

return _ENV