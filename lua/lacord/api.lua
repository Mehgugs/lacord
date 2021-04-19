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
local _VERSION = _VERSION
local decode = json.decode
local set = rawset

local _ENV = {}

local api = {__name = "lacord.api"}
api.__index = api


--- The api URL the client uses connect.
-- @string URL
-- @within Constants
local URL = constants.api.endpoint
_ENV.URL = URL

--- The user-agent used to connect with. (mandated by discord)
-- @string USER_AGENT
-- @within Constants
local USER_AGENT = ("DiscordBot (%s, %s) lua-version:\"%s\""):format(constants.homepage,constants.version, _VERSION )
_ENV.USER_AGENT = USER_AGENT

local GLOBAL_LOCK = mutex()

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
    local state = setmetatable({}, api)
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
function api.request(state,
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
    -- resolved ep is the endpoint with its :route_params substituted
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

    if with_payload[method] then
        local mt = getmetatable(payload)
        local content_type
        if mt and mt.__lacord_content_type then -- this can be implemented in order to send user-defined objects to discord in multi part uploads
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

local request = api.request

local empty_route = {}
function api:get_current_application_information()
    return request(self, 'get_current_application_information', 'GET', '/oauth2/applications/@me', empty_route)
end

function api:get_gateway_bot()
    return request(self, 'get_gateway_bot', 'GET', '/gateway/bot', empty_route)
end

function api:get_guild_audit_log(guild_id)
    return request(self, 'get_guild_audit_log', 'GET', '/guilds/:guild_id/audit-logs', {guild_id = guild_id})
end

function api:get_channel(channel_id)
    return request(self, 'get_channel', 'GET', '/channels/:channel_id', {channel_id = channel_id})
end

function api:modify_channel(channel_id, payload)
    return request(self, 'modify_channel', 'PATCH', '/channels/:channel_id', {channel_id = channel_id}, payload)
end

function api:delete_channel(channel_id)
    return request(self, 'delete_channel', 'DELETE', '/channels/:channel_id', {channel_id = channel_id})
end

function api:get_channel_messages(channel_id, query)
    return request(self, 'get_channel_messages', 'GET', '/channels/:channel_id/messages',
        {channel_id = channel_id},
        nil, query)
end

function api:get_channel_message(channel_id, message_id)
    return request(self, 'get_channel_message', 'GET', '/channels/:channel_id/messages/:message_id',
        {channel_id = channel_id, message_id = message_id})
end

function api:create_message(channel_id, payload, files)
    return request(self, 'create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files)
end

function api:create_message_with_txt(channel_id, payload, files)
    return request(self, 'create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files, true)
end

function api:crosspost_message(channel_id, message_id)
    return request(self, 'crosspost_message', 'POST', '/channels/:channel_id/messages/:message_id/crosspost',
        {channel_id = channel_id, message_id = message_id})
end

function api:create_reaction(channel_id, message_id, emoji)
    return request(self, 'create_reaction', 'PUT', '/channels/:channel_id/messages/:message_id/reactions/:emoji/@me',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_own_reaction(channel_id, message_id, emoji)
    return request(self, 'delete_own_reaction', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji/@me',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_user_reaction(channel_id, message_id, emoji, user_id)
    return request(self, 'delete_user_reaction', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji/:user_id',
    {channel_id = channel_id, message_id = message_id, emoji = emoji, user_id = user_id})
end

function api:get_reactions(channel_id, message_id, emoji)
    return request(self, 'get_reactions', 'GET', '/channels/:channel_id/messages/:message_id/reactions/:emoji',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_all_reactions(channel_id, message_id)
    return request(self, 'delete_all_reactions', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions',
    {channel_id = channel_id, message_id = message_id})
end

function api:delete_reactions(channel_id, message_id, emoji)
    return request(self, 'delete_reactions', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:edit_message(channel_id, message_id, edits)
    return request(self, 'edit_message', 'PATCH', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    }, edits)
end

function api:delete_message(channel_id, message_id)
    return request(self, 'delete_message', 'DELETE', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:bulk_delete_messages(channel_id, query)
    return request(self, 'bulk_delete_messages', 'DELETE', '/channels/:channel_id/messages/bulk-delete', {
        channel_id = channel_id
    }, nil, query)
end

function api:edit_channel_permissions(channel_id, overwrite_id, edits)
    return request(self, 'edit_channel_permissions', 'PUT', '/channels/:channel_id/permissions/:overwrite_id', {
        channel_id = channel_id, overwrite_id = overwrite_id
    }, edits)
end

function api:delete_channel_permissions(channel_id, overwrite_id)
    return request(self, 'delete_channel_permissions', 'DELETE', '/channels/:channel_id/permissions/:overwrite_id', {
        channel_id = channel_id, overwrite_id = overwrite_id
    })
end

function api:get_channel_invites(channel_id)
    return request(self, 'get_channel_invites', 'GET', '/channels/:channel_id/invites', {
        channel_id = channel_id
    })
end

function api:create_channel_invite(channel_id, invite)
    return request(self, 'create_channel_invite', 'POST', '/channels/:channel_id/invites', {
        channel_id = channel_id
    }, invite)
end

function api:follow_channel(channel_id, follower)
    return request(self, 'follow_channel', 'POST', '/channels/:channel_id/followers', {
        channel_id = channel_id
    }, follower)
end

function api:trigger_typing_indicator(channel_id)
    return request(self, 'trigger_typing_indicator', 'POST', '/channels/:channel_id/typing', {
        channel_id = channel_id
    })
end

function api:add_pinned_channel_message(channel_id, message_id)
    return request(self, 'add_pinned_channel_message', 'PUT', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:get_pinned_messages(channel_id)
    return request(self, 'get_pinned_messages', 'GET', '/channels/:channel_id/pins', {
        channel_id = channel_id
    })
end

function api:delete_pinned_channel_message(channel_id, message_id)
    return request(self, 'get_pinned_messages', 'DELETE', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:get_guild_emoji(guild_id, emoji_id)
    return request(self, 'get_guild_emoji', 'GET', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    })
end

function api:create_guild_emoji(guild_id, emoji)
    return request(self, 'create_guild_emoji', 'POST', '/guilds/:guild_id/emojis/', {
        guild_id = guild_id
    }, emoji)
end

function api:modify_guild_emoji(guild_id, emoji_id, edits)
    return request(self, 'modify_guild_emoji', 'PATCH', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    }, edits)
end

function api:DELETE_guild_emoji(guild_id, emoji_id)
    return request(self, 'delete_guild_emoji', 'DELETE', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    })
end

function api:get_guild(guild_id, with_counts)
    return request(self, 'get_guild', 'GET', '/guilds/:guild_id/', {
        guild_id = guild_id
    }, nil, { with_counts = not not with_counts})
end

function api:get_guild_preview(guild_id)
    return request(self, 'get_guild_preview', 'GET', '/guilds/:guild_id/preview', {
        guild_id = guild_id
    })
end

function api:modify_guild(guild_id, edits)
    return request(self, 'modify_guild', 'PATCH', '/guilds/:guild_id/', {
        guild_id = guild_id
    }, edits)
end

function api:delete_guild(guild_id)
    return request(self, 'delete_guild', 'DELETE', '/guilds/:guild_id/', {
        guild_id = guild_id
    })
end

function api:create_guild_channel(guild_id, channel)
    return request(self, 'create_guild_channel', 'POST', '/guilds/:guild_id/channels', {
        guild_id = guild_id
    }, channel)
end

function api:modify_guild_channel_positions(guild_id, pos)
    return request(self, 'modify_guild_channel_positions', 'PATCH', '/guilds/:guild_id/channels', {
        guild_id = guild_id
    }, pos)
end

function api:get_guild_member(guild_id, user_id)
    return request(self, 'get_guild_member', 'GET', '/guilds/:guild_id/members/:user_id', {
        guild_id = guild_id,
        user_id = user_id
    })
end

function api:list_guild_members(guild_id, params)
    return request(self, 'list_guild_members', 'GET', '/guilds/:guild_id/members', {
        guild_id = guild_id
    }, nil, params)
end

function api:search_guild_members(guild_id, query)
    return request(self, 'search_guild_members', 'GET', '/guilds/:guild_id/members/search', {
       guild_id = guild_id
    }, nil, query)
end

function api:add_guild_member(guild_id, user_id, payload)
    return request(self, 'add_guild_member', 'PUT', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id,
    }, payload)
end

function api:modify_guild_member(guild_id, user_id, payload)
    return request(self, 'modify_guild_member', 'PATCH', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:modify_current_user_nick(guild_id,  payload)
    return request(self, 'modify_current_user_nick', 'PATCH', '/guilds/:guild_id/members/@me/nick', {
       guild_id = guild_id,

    }, payload)
end

function api:add_guild_member_role(guild_id, user_id, role_id)
    return request(self, 'add_guild_member_role', 'PUT', '/guilds/:guild_id/members/:user_id/roles/:role_id', {
       guild_id = guild_id,
       user_id = user_id,
       role_id = role_id
    })
end

function api:remove_guild_member_role(guild_id, user_id, role_id )
    return request(self, 'remove_guild_member_role', 'DELETE', '/guilds/:guild_id/members/:user_id/roles/:role_id', {
       guild_id = guild_id,
       user_id = user_id,
       role_id = role_id
    })
end

function api:remove_guild_member(guild_id, user_id )
    return request(self, 'remove_guild_member', 'DELETE', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, nil)
end

function api:get_guild_bans(guild_id)
    return request(self, 'get_guild_bans', 'GET', '/guilds/:guild_id/bans', {
       guild_id = guild_id,
    })
end

function api:get_guild_ban(guild_id, user_id)
    return request(self, 'get_guild_ban', 'GET', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    })
end

function api:create_guild_ban(guild_id, user_id, payload)
    return request(self, 'create_guild_ban', 'POST', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:remove_guild_ban(guild_id, user_id)
    return request(self, 'remove_guild_ban', 'DELETE', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    })
end

function api:get_guild_roles(guild_id)
    return request(self, 'get_guild_roles', 'GET', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    })
end

function api:create_guild_role(guild_id,  payload)
    return request(self, 'create_guild_role', 'POST', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    }, payload)
end

function api:modify_guild_role_positions(guild_id,  payload)
    return request(self, 'modify_guild_role_positions', 'PATH', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    }, payload)
end

function api:modify_guild_role(guild_id, role_id, payload)
    return request(self, 'modify_guild_role', 'PATCH', '/guilds/:guild_id/roles/:role_id', {
       guild_id = guild_id,
       role_id = role_id
    }, payload)
end

function api:delete_guild_role(guild_id, role_id)
    return request(self, 'delete_guild_role', 'DELETE', '/guilds/:guild_id/roles/:role_id', {
       guild_id = guild_id,
       role_id = role_id
    })
end

function api:get_guild_prune_count(guild_id,  query)
    return request(self, 'get_guild_prune_count', 'GET', '/guilds/:guild_id/prune', {
       guild_id = guild_id,

    }, nil,  query)
end

function api:begin_guild_prune(guild_id,  payload)
    return request(self, 'begin_guild_prune', 'POST', '/guilds/:guild_id/prune', {
       guild_id = guild_id,

    }, payload)
end

function api:get_guild_voice_regions(guild_id)
    return request(self, 'get_guild_voice_regions', 'GET', '/guilds/:guild_id/regions', {
       guild_id = guild_id,

    })
end

function api:get_guild_invites(guild_id)
    return request(self, 'get_guild_invites', 'GET', '/guilds/:guild_id/invites', {
       guild_id = guild_id,

    })
end

function api:get_guild_integrations(guild_id)
    return request(self, 'get_guild_integrations', 'GET', '/guilds/:guild_id/integrations', {
       guild_id = guild_id,

    })
end

function api:delete_guild_integration(guild_id, integration_id)
    return request(self, 'delete_guild_integration', 'DELETE', '/guilds/:guild_id/integrations/:integration_id', {
       guild_id = guild_id,
       integration_id = integration_id
    })
end

function api:get_guild_widget_settings(guild_id)
    return request(self, 'get_guild_widget_settings', 'GET', '/guilds/:guild_id/widget', {
       guild_id = guild_id,
    })
end

function api:modify_guild_widget(guild_id,  payload)
    return request(self, 'modify_guild_widget', 'PATCH', '/guilds/:guild_id/widget', {
       guild_id = guild_id,

    }, payload)
end

function api:get_guild_widget(guild_id)
    return request(self, 'get_guild_widget', 'GET', '/guilds/:guild_id/widget.json', {
       guild_id = guild_id,

    })
end

function api:get_guild_vanity_url(guild_id,  query)
    return request(self, 'get_guild_vanity_url', 'GET', '/guilds/:guild_id/vanity-url', {
       guild_id = guild_id,

    }, nil,  query)
end

function api:get_guild_widget_image(guild_id,  query)
    return request(self, 'get_guild_widget_image', 'GET', '/guilds/:guild_id/widget.png', {
       guild_id = guild_id,

    }, nil, query)
end

function api:get_guild_welcome_screen(guild_id)
    return request(self, 'get_guild_welcome_screen', 'GET', '/guilds/:guild_id/welcome-screen', {
       guild_id = guild_id,

    })
end

function api:modify_guild_welcome_screen(guild_id,  payload)
    return request(self, 'modify_guild_welcome_screen', 'PATCH', '/guilds/:guild_id/welcome-screen', {
       guild_id = guild_id,

    }, payload)
end

function api:update_current_user_voice_state(guild_id,  payload)
    return request(self, 'update_current_user_voice_state', 'PATCH', '/guilds/:guild_id/voice-states/@me', {
       guild_id = guild_id,

    }, payload)
end

function api:update_user_voice_state(guild_id, user_id, payload)
    return request(self, 'update_user_voice_state', 'PATCH', '/guilds/:guild_id/voice-states/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

-- safe method chaining --

local cpmt = {}

local function results(self)
    return unpack(self.result)
end

local function failure(self)
    return self
end

function cpmt:__index(k)
  if self.success then
    local function method(this, ...)
      local s, v, e = api[k](this[1], ...)
      this.success = s
      insert(this.result, v)
      this.error = e or this.error
      return this
    end
    self[k] = method
    return method
  else
    return failure
  end
end

--- Creates a method chain.
-- @treturn table The capture object.
-- @usage
--  local api = require"lacord.api"
--  local discord_api = api.init{blah}
--  local R = discord_api
--    :capture()
--    :get_gateway_bot()
--    :get_current_application_information()
--  if R.success then -- ALL methods succeeded
--    local results_list = R.result
--    local A, B, C = R:results()
--  else
--    local why = R.error
--    local partial = R.result -- There may be partial results collected before the error, you can use this to debug.
--    R:some_method() -- If there's been a faiure, calls like this are noop'd.
--  end
function api:capture()
  return setmetatable({self, success = true, result = {}, results = results, error = false}, cpmt)
end

return _ENV