--- Discord REST API
-- @module api

local cqueues = require"cqueues"
local errno = require"cqueues.errno"
local newreq = require"http.request"
local reason = require"http.h1_reason_phrases"
local httputil = require "http.util"
local zlib = require"http.zlib"
local base64 = require"basexx".to_base64
local constants = require"lacord.const"
local mutex = require"lacord.util.mutex".new
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local auditable = require"lacord.util.audit-log-methods"
local inspect = require"inspect"
local cli = require"lacord.cli"
local LACORD_DEBUG = cli.debug
local LACORD_UNSTABLE = cli.unstable
local LACORD_DEPRECATED = cli.deprecated

local sleep = cqueues.sleep
local monotime = cqueues.monotime
local content_typed = util.content_typed
local inflate = zlib.inflate
local JSON = util.content_types.JSON
local a_form = util.form
local is_form = util.is_form
local tostring = tostring
local remove = table.remove
local time = os.time
local insert, concat = table.insert, table.concat
local unpack = table.unpack
local next, tonumber = next, tonumber
local setm = setmetatable
local max = math.max
local min = math.min
local xpcall = xpcall
local traceback = debug.traceback
local type = type
local ipairs, pairs = ipairs, pairs
local ver = concat({util.version_major, util.version_minor, util.version_release}, ".")
local set = rawset
local err = error
local openf = io.open

local encode = require"lacord.util.json".encode
local decode = require"lacord.util.json".decode

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
local USER_AGENT = ("DiscordBot (%s, %s) lua-version:\"%s\""):format(constants.homepage,constants.version, ver )
_ENV.USER_AGENT = USER_AGENT

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

local function mutexindexer(self, k)
    self[k] = mutex(k)
    return self[k]
end

local mutexc_t = {__mode = "v"}
local unlimi_t = {__index = mutexindexer}

local function mutex_cache(token)
    local ch = caches[token]
    if not ch then
        local unlim = setm({}, unlimi_t)
        ch = setm({}, mutexc_t)
        set(caches, token, ch)
        set(caches, token .. ".unlimited", unlim)
        ch.unlimited = unlim
    end
    return ch
end

local add_a_file do
    if LACORD_UNSTABLE then
        -- unstable feature: new multiple attachments form fields
        -- FUTURE: v10
        function add_a_file(ret, inner_ct, f, i)
            local name = util.file_name(f)
            local fstr, resolved_ct = content_typed(f)
            insert(ret, BOUNDARY2)
            insert(ret, ("Content-Disposition:form-data;name=\"files[%i]\";filename=%q"):format(i and i-1 or 0, name))
            insert(ret, ("Content-Type:%s\r\n"):format(resolved_ct or inner_ct))
            insert(ret, fstr)
        end
    else
        function add_a_file(ret, inner_ct, f, i)
            local name = util.file_name(f)
            local fstr, resolved_ct = content_typed(f)
            insert(ret, BOUNDARY2)
            if i then
                insert(ret, ("Content-Disposition:form-data;name=\"file%i\";filename=%q"):format(i, name))
            else
                insert(ret, ("Content-Disposition:form-data;name=\"file\";filename=%q"):format(name))
            end
            insert(ret, ("Content-Type:%s\r\n"):format(resolved_ct or inner_ct))
            insert(ret, fstr)
        end
    end
end



local function attachContent(payload, files, ct, inner_ct)
    local ret
    if ct ~= "form" then
        if payload ~= '{}' then
            ret = {
                BOUNDARY2,
                "Content-Disposition:form-data;name=\"payload_json\"",
                ("Content-Type:%s\r\n"):format(ct),
                payload,
            }
        else
            logger.debug("Not adding empty payload.")
            ret = {}
        end
    else
        ret = {}
        for k, v in pairs(payload) do
            insert(ret, BOUNDARY2)
            insert(ret, ("Content-Disposition:form-data;name=%q\r\n"):format(k))
            insert(ret, tostring(v))
        end
    end
    if #files == 1 then
        add_a_file(ret, inner_ct, files[1])
    else
        for i, v in ipairs(files) do
            add_a_file(ret, inner_ct, v, i)
        end
    end
    insert(ret, BOUNDARY3)
    return concat(ret, "\r\n")
end

local function attachFiles (payload, files, ct)
    return attachContent(payload, files, ct, util.content_types.BYTES)
end

local function attachTextFiles(payload, files, ct)
    return attachContent(payload, files, ct, util.content_types.TEXT)
end

local function handle_payload(req, method, name, payload, files, asText)
    if with_payload[method] then
        local content_type
        payload,content_type = content_typed(payload, name)
        if not content_type then
            payload = payload and encode(payload) or '{}'
            content_type = JSON
        end
        if files and next(files) then
            payload = (asText and attachTextFiles or attachFiles)(payload, files, content_type)
            req.headers:append('content-type', MULTIPART)
        else
            req.headers:append('content-type', content_type)
        end
        if LACORD_DEBUG then
            local file = openf("test/payload", "wb")
            file:write(payload)
            file:close()
        end
        req:set_body(payload)
    end
end

local function resolve_endpoint(ep, rp)
    return ep:gsub(":([a-z_]+)", rp)
end

local function resolve_majors(rp)
    local mp = {}
    if rp.channel_id then
        insert(mp, 'c')
        insert(mp, rp.channel_id)
    end
    if rp.guild_id then
        insert(mp, 'g')
        insert(mp, rp.guild_id)
    end
    if rp.webhook_id then
        insert(mp, 'w')
        insert(mp, rp.webhook_id)
        insert(mp, rp.webhook_token)
    end
    if rp.interaction_token then
        insert(mp, 'i')
        insert(mp, rp.interaction_token)
    end
    return (not mp[1]) and '' or concat(mp, ".")
end

--- Creates a new api state for connecting to discord.
-- @tab options The options table. Must contain a `token` field with the api token to use.
-- @treturn api The api state object.
function new(options)
    local state = setm({}, api)
    local auth
    if options.client_credentials then
        auth = "Basic " .. base64(("%s:%s"):format(options.client_credentials[1], options.client_credentials[2]))
        state.auth_kind = "client_credentials"
    elseif options.token and options.token:sub(1,4) == "Bot " then
        auth = options.token
        state.auth_kind = "bot"
    elseif options.token and options.token:sub(1,7) == "Bearer " then
        auth = options.token
        state.auth_kind = "bearer"
    else
        return logger.fatal("Please supply a token! It must start with $white;'Bot|Bearer '$error;.")
    end
    state.token = auth
    state.routex = mutex_cache(auth)
    state.global_deadline = 0
    state.globaltex = mutex()
    state.rates = {}
    state.track_rates = options.track_ratelimits
    state.route_delay = options.route_delay and min(options.route_delay, 0) or 1
    state.api_timeout = tonumber(options.api_timeout)
    state.api_http_version = options.http_version or 1.1
    if LACORD_DEBUG then state.expect_100_timeout = options.expect_100_timeout end
    if not not options.accept_encoding then
        state.accept_encoding = "gzip, deflate, x-gzip"
        logger.debug("%s is using $white;accept-encoding: %q", state, state.accept_encoding)
    end
    logger.debug("Initialized %s with TOKEN-%x", state, util.hash(state.token))
    return state
end

if LACORD_DEPRECATED then _ENV.init = _ENV.new end

local static_methods = {}

local function static(name) static_methods[name] = true end

local function mapquery(Q)
    local out = {}
    for i, v in pairs(Q) do out[i] = tostring(v) end
    return out
end

_ENV.mapquery = mapquery

local function get_routex(ratelimits, key, unlimited)
    local item = ratelimits[key]
    -- the key has been mapped to another route
    if type(item) == 'string' then return get_routex(ratelimits, item, unlimited)
    elseif item then return item, key
    -- there was no value found and we're unlimited so return the default rate limit.
    elseif not item and unlimited then
        ratelimits[key] = ratelimits.unlimited[unlimited]
        return ratelimits[key], key
    else
        local new = mutex()
        ratelimits[key] = new
        return new, key, true
    end
end

local function check_global(state)
    local global_remaining = state.global_deadline - monotime()
    if global_remaining > 0 then sleep(global_remaining) end
end

local function modify_global(state, newtime)
    state.globaltex:lock()
    if state.global_deadline < newtime then
        state.global_deadline = newtime
        state.globaltex:unlock_at(newtime)
    else
        state.globaltex:unlock()
    end
end

local push

local reason_thrs = setm({}, {__mode = "k"})
local pre_pushes = setm({}, {__mode = "k"})

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
    local reqthr = cqueues.running()
    if not reqthr then
        return logger.fatal("Please call REST methods asynchronously.")
    end

    local resolved_ep = resolve_endpoint(endpoint, route_parameters)
    local url = URL .. resolved_ep

    if query and next(query) then
        url = ("%s?%s"):format(url, httputil.dict_to_query(mapquery(query)))
    end

    local req = newreq.new_from_uri(httputil.encodeURI(url))
    req.version = state.api_http_version

    logger.debug("HTTP/$white;%s", req.version)

    req.headers:upsert(":method", method)
    req.headers:upsert("user-agent", USER_AGENT)
    if state.token then req.headers:append("authorization", state.token) end

    if state.accept_encoding then
        req.headers:append("accept-encoding", state.accept_encoding)
    end

    local reasons = reason_thrs[reqthr]
    if reasons and reasons[1] and auditable[name] then
        req.headers:append("x-audit-log-reason", tostring(remove(reasons)))
    end

    handle_payload(req, method, name, payload, files, asText)

    local major_params = resolve_majors(route_parameters)
    local initial, bucket = get_routex(state.routex,  major_params .. name, major_params)

    if LACORD_DEBUG and pre_pushes[reqthr] then
        pre_pushes[reqthr] = nil
        return req
    end

    initial:lock()

    check_global(state)

    if LACORD_DEBUG then
        logger.debug("$debug_highlight;Headers:")
        for hname, value, never_index in req.headers:each() do
            logger.debug("  $white;%s$debug; = $white;%s", hname, never_index and "<never_index>" or value)
        end
    end

    local success, data, erro, delay, extra = xpcall(push, traceback, state, name, req, major_params, 0)

    if not success then
        return logger.fatal("api.push failed %q", tostring(data))
    end

    local final,_,fresh = get_routex(state.routex, bucket)
    if delay > 0 then
        if final ~= initial then
            -- we joined a limit
            -- apply a delay to the old one, and if the new limit was freshly created
            -- (i.e it's not in use elsewhere) aquire it now and apply the delay
            -- If the limit is stale then we could be in the middle of a lock - unlock
            -- in that case we need to tell whoever is busy with this limit to wait a bit
            -- longer.
            initial:unlock_after(delay)
            if fresh then
                final:lock()
                final:unlock_after(delay)
            else
                if final.inuse then
                    final:set_hangover(delay)
                else
                    final:lock()
                    final:unlock_after(delay)
                end
            end
        else
            final:unlock_after(delay)
        end
    else
        initial:unlock()
    end

    return not erro, data, erro, extra
end

function push(state, name, req, major_params, retries)
    local delay = state.route_delay -- seconds
    local ID = major_params .. name
    local headers , stream , eno = req:go(state.api_timeout or 60)

    if not headers and retries < constants.api.max_retries then
        local rsec = util.rand(1, 2)
        logger.warn("%s failed to %s because %q (%s, %q) retrying after %.3fsec",
            state, ID, tostring(stream), eno and errno[eno] or "?", eno and errno.strerror(eno) or "??", rsec
        )
        cqueues.sleep(rsec)
        check_global(state)
        return push(state, name, req,major_params, retries+1)
    elseif not headers and retries >= constants.api.max_retries then
        return nil, errno.strerror(eno), delay
    end

    local code, rawcode,stat

    stat = headers:get":status"
    rawcode, code = stat, tonumber(stat)

    local date = headers:get"date"
    local remaining =  headers:get"x-ratelimit-remaining"
    local reset = headers:get"x-ratelimit-reset"
    local reset_after = headers:get"x-ratelimit-reset-after"
    reset = reset and tonumber(reset)
    if remaining == '0' and reset then
        reset_after = tonumber(reset_after)
        delay = max(delay, reset_after)
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
            }
        end
        if state.routex[ID] ~= bucket then
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
        if code == 204 then return true, nil, delay
        else return data, nil, delay
        end
    else
        local extra
        if state.raw then
            data = headers:get"content-type" == JSON and decode(raw) or raw
        end
        if type(data) == 'table' then
            local retry;
            if code == 429 then
                delay = data.retry_after
                if data.global or headers:get"x-ratelimit-global" then
                    modify_global(monotime() + delay)
                end
                retry = retries < 5
            elseif code == 502 then
                delay = delay + util.rand(0 , 2)
                retry = retries < 5
                if headers:get"x-ratelimit-global" then
                    modify_global(monotime() + delay)
                end
            end

            if retry then
                logger.warn("(%i, %q) :  retrying after %fsec : %s", code, reason[rawcode], delay, ID)
                cqueues.sleep(delay)
                return push(state, name, req, major_params, retries+1)
            end

            local msg
            if data.code and data.message then
                msg = ('HTTP Error %i : %s'):format(data.code, data.message)
            else
                msg = 'HTTP Error'
            end
            --TODO: handle data.errors again
            extra = data.errors
            if LACORD_DEBUG then
                logger.debug("$white;%s", msg)
                logger.debug("$white;data.errors$debug; = ")
                logger.printf(inspect(data.errors))
            end
            data = msg
        else
            if headers:get"x-ratelimit-global" then
                modify_global(monotime() + delay)
            end
        end
        logger.error("(%i, %q) : %s", code, reason[rawcode], ID)
        return nil, data, delay, extra
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
function api:get_current_application_information()
    return self:request( 'get_current_application_information', 'GET', '/oauth2/applications/@me', empty_route)
end

function api:get_current_authorization_information()
    return self:request('get_current_authorization_information', 'GET', '/oauth2/@me', empty_route)
end

function api:get_gateway_bot()
    return self:request('get_gateway_bot', 'GET', '/gateway/bot', empty_route)
end

function api:get_guild_audit_log(guild_id)
    return self:request('get_guild_audit_log', 'GET', '/guilds/:guild_id/audit-logs', {guild_id = guild_id})
end

function api:get_channel(channel_id)
    return self:request('get_channel', 'GET', '/channels/:channel_id', {channel_id = channel_id})
end

function api:modify_channel(channel_id, payload)
    return self:request('modify_channel', 'PATCH', '/channels/:channel_id', {channel_id = channel_id}, payload)
end

function api:delete_channel(channel_id)
    return self:request('delete_channel', 'DELETE', '/channels/:channel_id', {channel_id = channel_id})
end

function api:get_channel_messages(channel_id, query)
    return self:request('get_channel_messages', 'GET', '/channels/:channel_id/messages',
        {channel_id = channel_id},
        nil, query)
end

function api:get_channel_message(channel_id, message_id)
    return self:request('get_channel_message', 'GET', '/channels/:channel_id/messages/:message_id',
        {channel_id = channel_id, message_id = message_id})
end

function api:create_message(channel_id, payload, files)
    return self:request('create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files)
end

function api:create_message_with_txt(channel_id, payload, files)
    return self:request('create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files, true)
end

function api:crosspost_message(channel_id, message_id)
    return self:request('crosspost_message', 'POST', '/channels/:channel_id/messages/:message_id/crosspost',
        {channel_id = channel_id, message_id = message_id})
end

function api:create_reaction(channel_id, message_id, emoji)
    return self:request('create_reaction', 'PUT', '/channels/:channel_id/messages/:message_id/reactions/:emoji/@me',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_own_reaction(channel_id, message_id, emoji)
    return self:request('delete_own_reaction', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji/@me',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_user_reaction(channel_id, message_id, emoji, user_id)
    return self:request('delete_user_reaction', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji/:user_id',
    {channel_id = channel_id, message_id = message_id, emoji = emoji, user_id = user_id})
end

function api:get_reactions(channel_id, message_id, emoji)
    return self:request('get_reactions', 'GET', '/channels/:channel_id/messages/:message_id/reactions/:emoji',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_all_reactions(channel_id, message_id)
    return self:request('delete_all_reactions', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions',
    {channel_id = channel_id, message_id = message_id})
end

function api:delete_reactions(channel_id, message_id, emoji)
    return self:request('delete_reactions', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:edit_message(channel_id, message_id, edits)
    return self:request('edit_message', 'PATCH', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    }, edits)
end

function api:delete_message(channel_id, message_id)
    return self:request('delete_message', 'DELETE', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:bulk_delete_messages(channel_id, query)
    return self:request('bulk_delete_messages', 'DELETE', '/channels/:channel_id/messages/bulk-delete', {
        channel_id = channel_id
    }, nil, query)
end

function api:edit_channel_permissions(channel_id, overwrite_id, edits)
    return self:request('edit_channel_permissions', 'PUT', '/channels/:channel_id/permissions/:overwrite_id', {
        channel_id = channel_id, overwrite_id = overwrite_id
    }, edits)
end

function api:delete_channel_permissions(channel_id, overwrite_id)
    return self:request('delete_channel_permissions', 'DELETE', '/channels/:channel_id/permissions/:overwrite_id', {
        channel_id = channel_id, overwrite_id = overwrite_id
    })
end

function api:get_channel_invites(channel_id)
    return self:request('get_channel_invites', 'GET', '/channels/:channel_id/invites', {
        channel_id = channel_id
    })
end

function api:create_channel_invite(channel_id, invite)
    return self:request('create_channel_invite', 'POST', '/channels/:channel_id/invites', {
        channel_id = channel_id
    }, invite)
end

function api:follow_channel(channel_id, follower)
    return self:request('follow_channel', 'POST', '/channels/:channel_id/followers', {
        channel_id = channel_id
    }, follower)
end

function api:trigger_typing_indicator(channel_id)
    return self:request('trigger_typing_indicator', 'POST', '/channels/:channel_id/typing', {
        channel_id = channel_id
    })
end

function api:add_pinned_channel_message(channel_id, message_id)
    return self:request('add_pinned_channel_message', 'PUT', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:get_pinned_messages(channel_id)
    return self:request('get_pinned_messages', 'GET', '/channels/:channel_id/pins', {
        channel_id = channel_id
    })
end

function api:delete_pinned_channel_message(channel_id, message_id)
    return self:request('get_pinned_messages', 'DELETE', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:start_thread_with_message(channel_id, message_id, payload)
    return self:request('start_thread_with_message', 'POST', '/channels/:channel_id/messages/:message_id/threads', {
       channel_id = channel_id,
       message_id = message_id,
    }, payload)
end

function api:start_thread_without_message(channel_id, payload)
    return self:request('start_thread_without_message', 'POST', '/channels/:channel_id/threads', {
       channel_id = channel_id
    }, payload)
end

function api:join_thread(channel_id)
    return self:request('join_thread', 'PUT', '/channels/:channel_id/thread-members/@me', {
       channel_id = channel_id
    })
end

function api:add_thread_member(channel_id, user_id)
    return self:request('add_thread_member', 'GET', '/channels/:channel_id/thread-members/:user_id', {
       channel_id = channel_id,
       user_id = user_id
    })
end

function api:leave_thread(channel_id)
    return self:request('leave_thread', 'DELETE', '/channels/:channel_id/thread-members/@me', {
       channel_id = channel_id
    })
end

function api:remove_thread_member(channel_id,user_id)
    return self:request('remove_thread_member', 'DELETE', '/channels/:channel_id/thread-members/:user_id', {
       channel_id = channel_id,
       user_id = user_id
    })
end

function api:list_thread_members(channel_id)
    return self:request('list_thread_members', 'GET', '/channels/:channel_id/thread-members', {
       channel_id = channel_id
    })
end

function api:list_active_threads(channel_id)
    return self:request('list_active_threads', 'GET', '/channels/:channel_id/threads/active', {
       channel_id = channel_id,
    })
end

function api:list_public_archived_threads(channel_id,  query)
    return self:request('list_public_archived_threads', 'GET', '/channels/:channel_id/threads/archived/public', {
       channel_id = channel_id
    }, nil,  query)
end

function api:list_private_archived_threads(channel_id,  query)
    return self:request('list_private_archived_threads', 'GET', '/channels/:channel_id/threads/archived/private', {
       channel_id = channel_id
    }, nil,  query)
end

function api:list_joined_private_archived_threads(channel_id, query)
    return self:request('list_joined_private_archived_threads', 'GET', '/channels/:channel_id/users/@me/threads/archived/private', {
       channel_id = channel_id
    }, nil,  query)
end

function api:create_interaction_response(interaction_id, interaction_token, payload, files)
    return self:request('create_interaction_response', 'POST', '/interactions/:interaction_id/:interaction_token/callback', {
        interaction_id = interaction_id,
       interaction_token = interaction_token
    }, payload, nil, files)
end

function api:create_interaction_response_with_txt(application_id, interaction_token, payload, files)
    return self:request('create_interaction_response', 'POST', '/interactions/:application_id/:interaction_token/callback', {
       application_id = application_id,
       interaction_token = interaction_token
    }, payload, nil, files, true)
end

function api:get_original_interaction_response(application_id, interaction_token)
    return self:request('get_original_interaction_response', 'GET', '/webhooks/:application_id/:interaction_token/messages/@original', {
       application_id = application_id,
       interaction_token = interaction_token
    })
end

function api:edit_original_interaction_response(application_id, interaction_token, payload)
    return self:request('edit_original_interaction_response', 'PATCH', '/webhooks/:application_id/:interaction_token/messages/@original', {
       application_id = application_id,
       interaction_token = interaction_token
    }, payload)
end

function api:delete_original_interaction_response(application_id, interaction_token)
    return self:request('delete_original_interaction_response', 'DELETE', '/webhooks/:application_id/:interaction_token/messages/@original', {
       application_id = application_id,
       interaction_token = interaction_token
    })
end

function api:create_followup_message(application_id, interaction_token,  payload, files)
    return self:request('create_followup_message', 'POST', '/webhooks/:application_id/:interaction_token', {
       application_id = application_id,
       interaction_token = interaction_token
    }, payload, nil, files)
end

function api:edit_followup_message(application_id, interaction_token, message_id, payload)
    return self:request('edit_followup_message', 'PATCH', '/webhooks/:application_id/:interaction_token/messages/:message_id', {
       application_id = application_id,
       interaction_token = interaction_token,
       message_id = message_id
    }, payload)
end

function api:delete_followup_message(application_id, interaction_token, message_id)
    return self:request('delete_followup_message', 'DELETE', '/webhooks/:application_id/:interaction_token/messages/:message_id', {
       application_id = application_id,
       interaction_token = interaction_token,
       message_id = message_id
    })
end

function api:get_guild_emoji(guild_id, emoji_id)
    return self:request('get_guild_emoji', 'GET', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    })
end

function api:create_guild_emoji(guild_id, emoji)
    return self:request('create_guild_emoji', 'POST', '/guilds/:guild_id/emojis', {
        guild_id = guild_id
    }, emoji)
end

function api:modify_guild_emoji(guild_id, emoji_id, edits)
    return self:request('modify_guild_emoji', 'PATCH', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    }, edits)
end

function api:DELETE_guild_emoji(guild_id, emoji_id)
    return self:request('delete_guild_emoji', 'DELETE', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    })
end

function api:get_guild(guild_id, with_counts)
    return self:request('get_guild', 'GET', '/guilds/:guild_id', {
        guild_id = guild_id
    }, nil, { with_counts = not not with_counts})
end

function api:get_guild_preview(guild_id)
    return self:request('get_guild_preview', 'GET', '/guilds/:guild_id/preview', {
        guild_id = guild_id
    })
end

function api:create_guild(payload)
    return self:request('create_guild', 'POST', '/guilds', empty_route, payload)
end

function api:modify_guild(guild_id, edits)
    return self:request('modify_guild', 'PATCH', '/guilds/:guild_id', {
        guild_id = guild_id
    }, edits)
end

function api:delete_guild(guild_id)
    return self:request('delete_guild', 'DELETE', '/guilds/:guild_id', {
        guild_id = guild_id
    })
end

function api:create_guild_channel(guild_id, channel)
    return self:request('create_guild_channel', 'POST', '/guilds/:guild_id/channels', {
        guild_id = guild_id
    }, channel)
end

function api:modify_guild_channel_positions(guild_id, pos)
    return self:request('modify_guild_channel_positions', 'PATCH', '/guilds/:guild_id/channels', {
        guild_id = guild_id
    }, pos)
end

function api:get_guild_member(guild_id, user_id)
    return self:request('get_guild_member', 'GET', '/guilds/:guild_id/members/:user_id', {
        guild_id = guild_id,
        user_id = user_id
    })
end

function api:list_guild_members(guild_id, params)
    return self:request('list_guild_members', 'GET', '/guilds/:guild_id/members', {
        guild_id = guild_id
    }, nil, params)
end

function api:search_guild_members(guild_id, query)
    return self:request('search_guild_members', 'GET', '/guilds/:guild_id/members/search', {
       guild_id = guild_id
    }, nil, query)
end

function api:add_guild_member(guild_id, user_id, payload)
    return self:request('add_guild_member', 'PUT', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id,
    }, payload)
end

function api:modify_guild_member(guild_id, user_id, payload)
    return self:request('modify_guild_member', 'PATCH', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:modify_current_member(guild_id,  payload)
    return self:request('modify_current_member', 'PATCH', '/guilds/:guild_id/members/@me', {
       guild_id = guild_id,
    }, payload)
end

function api:modify_current_user_nick(guild_id,  payload)
    return self:request('modify_current_user_nick', 'PATCH', '/guilds/:guild_id/members/@me/nick', {
       guild_id = guild_id,

    }, payload)
end


function api:add_guild_member_role(guild_id, user_id, role_id)
    return self:request('add_guild_member_role', 'PUT', '/guilds/:guild_id/members/:user_id/roles/:role_id', {
       guild_id = guild_id,
       user_id = user_id,
       role_id = role_id
    })
end

function api:remove_guild_member_role(guild_id, user_id, role_id )
    return self:request('remove_guild_member_role', 'DELETE', '/guilds/:guild_id/members/:user_id/roles/:role_id', {
       guild_id = guild_id,
       user_id = user_id,
       role_id = role_id
    })
end

function api:remove_guild_member(guild_id, user_id )
    return self:request('remove_guild_member', 'DELETE', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, nil)
end

function api:get_guild_bans(guild_id)
    return self:request('get_guild_bans', 'GET', '/guilds/:guild_id/bans', {
       guild_id = guild_id,
    })
end

function api:get_guild_ban(guild_id, user_id)
    return self:request('get_guild_ban', 'GET', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    })
end

function api:create_guild_ban(guild_id, user_id, payload)
    return self:request('create_guild_ban', 'POST', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:remove_guild_ban(guild_id, user_id)
    return self:request('remove_guild_ban', 'DELETE', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    })
end

function api:get_guild_roles(guild_id)
    return self:request('get_guild_roles', 'GET', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    })
end

function api:create_guild_role(guild_id,  payload)
    return self:request('create_guild_role', 'POST', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    }, payload)
end

function api:modify_guild_role_positions(guild_id,  payload)
    return self:request('modify_guild_role_positions', 'PATH', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    }, payload)
end

function api:modify_guild_role(guild_id, role_id, payload)
    return self:request('modify_guild_role', 'PATCH', '/guilds/:guild_id/roles/:role_id', {
       guild_id = guild_id,
       role_id = role_id
    }, payload)
end

function api:delete_guild_role(guild_id, role_id)
    return self:request('delete_guild_role', 'DELETE', '/guilds/:guild_id/roles/:role_id', {
       guild_id = guild_id,
       role_id = role_id
    })
end

function api:get_guild_prune_count(guild_id,  query)
    return self:request('get_guild_prune_count', 'GET', '/guilds/:guild_id/prune', {
       guild_id = guild_id,

    }, nil,  query)
end

function api:begin_guild_prune(guild_id,  payload)
    return self:request('begin_guild_prune', 'POST', '/guilds/:guild_id/prune', {
       guild_id = guild_id,

    }, payload)
end

function api:get_guild_voice_regions(guild_id)
    return self:request('get_guild_voice_regions', 'GET', '/guilds/:guild_id/regions', {
       guild_id = guild_id,

    })
end

function api:get_guild_invites(guild_id)
    return self:request('get_guild_invites', 'GET', '/guilds/:guild_id/invites', {
       guild_id = guild_id,

    })
end

function api:get_guild_integrations(guild_id)
    return self:request('get_guild_integrations', 'GET', '/guilds/:guild_id/integrations', {
       guild_id = guild_id,

    })
end

function api:delete_guild_integration(guild_id, integration_id)
    return self:request('delete_guild_integration', 'DELETE', '/guilds/:guild_id/integrations/:integration_id', {
       guild_id = guild_id,
       integration_id = integration_id
    })
end

function api:get_guild_widget_settings(guild_id)
    return self:request('get_guild_widget_settings', 'GET', '/guilds/:guild_id/widget', {
       guild_id = guild_id,
    })
end

function api:modify_guild_widget(guild_id,  payload)
    return self:request('modify_guild_widget', 'PATCH', '/guilds/:guild_id/widget', {
       guild_id = guild_id,

    }, payload)
end

function api:get_guild_widget(guild_id)
    return self:request('get_guild_widget', 'GET', '/guilds/:guild_id/widget.json', {
       guild_id = guild_id,

    })
end

function api:get_guild_vanity_url(guild_id,  query)
    return self:request('get_guild_vanity_url', 'GET', '/guilds/:guild_id/vanity-url', {
       guild_id = guild_id,

    }, nil,  query)
end

function api:get_guild_widget_image(guild_id,  query)
    return self:request('get_guild_widget_image', 'GET', '/guilds/:guild_id/widget.png', {
       guild_id = guild_id,

    }, nil, query)
end

function api:get_guild_welcome_screen(guild_id)
    return self:request('get_guild_welcome_screen', 'GET', '/guilds/:guild_id/welcome-screen', {
       guild_id = guild_id,

    })
end

function api:modify_guild_welcome_screen(guild_id,  payload)
    return self:request('modify_guild_welcome_screen', 'PATCH', '/guilds/:guild_id/welcome-screen', {
       guild_id = guild_id,

    }, payload)
end

function api:update_current_user_voice_state(guild_id,  payload)
    return self:request('update_current_user_voice_state', 'PATCH', '/guilds/:guild_id/voice-states/@me', {
       guild_id = guild_id,

    }, payload)
end

function api:update_user_voice_state(guild_id, user_id, payload)
    return self:request('update_user_voice_state', 'PATCH', '/guilds/:guild_id/voice-states/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:get_invite(invite_code,  query)
    return self:request('get_invite', 'GET', '/invites/:invite_code', {
       invite_code = invite_code,

    }, nil,  query)
end

function api:delete_invite(invite_code)
    return self:request('delete_invite', 'DELETE', '/invites/:invite_code', {
       invite_code = invite_code,

    })
end

function api:get_current_user()
    return self:request('get_current_user', 'GET', '/users/@me', empty_route)
end

function api:get_user(user_id)
    return self:request('get_user', 'GET', '/users/:user_id', {
        user_id = user_id,
    })
end

function api:modify_current_user(payload)
    return self:request('modify_current_user', 'PATCH', '/users/@me', empty_route, payload)
end

function api:get_current_user_guilds()
    return self:request('get_current_user_guilds', 'GET', '/users/@me/guilds', empty_route)
end

function api:leave_guild(guild_id)
    return self:request('leave_guild', 'GET', '/users/@me/guilds/:guild_id', {
       guild_id = guild_id,

    })
end

function api:create_dm(payload)
    return self:request('create_dm', 'POST', '/users/@me/channels', empty_route, payload)
end

function api:get_user_connections()
    return self:request('get_user_connections', 'GET', '/users/@me/connections', empty_route)
end

function api:create_webhook(channel_id,  payload)
    return self:request('create_webhook', 'POST', '/channels/:channel_id/webhooks', {
       channel_id = channel_id,

    }, payload)
end

function api:get_channel_webhooks(channel_id)
    return self:request('get_channel_webhooks', 'GET', '/channels/:channel_id/webhooks', {
       channel_id = channel_id,

    })
end

function api:get_guild_webhooks(guild_id)
    return self:request('get_guild_webhooks', 'GET', '/guilds/:guild_id/webhooks', {
       guild_id = guild_id,

    })
end

function api:get_webhook(webhook_id)
    return self:request('get_webhook', 'GET', '/webhooks/:webhook_id', {
       webhook_id = webhook_id,

    })
end

static'get_webhook_with_token'

function api:get_webhook_with_token(webhook_id, webhook_token)
    return self:request('get_webhook_with_token', 'GET', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    })
end

function api:modify_webhook(webhook_id,  payload)
    return self:request('modify_webhook', 'POST', '/webhooks/:webhook_id', {
       webhook_id = webhook_id,

    }, payload)
end

static'modify_webhook_with_token'

function api:modify_webhook_with_token(webhook_id, webhook_token, payload)
    return self:request('modify_webhook_with_token', 'POST', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token,
    }, payload)
end

function api:delete_webhook(webhook_id)
    return self:request('delete_webhook', 'DELETE', '/webhooks/:webhook_id', {
       webhook_id = webhook_id,

    })
end

static'delete_webhook_with_token'

function api:delete_webhook_with_token(webhook_id, webhook_token)
    return self:request('delete_webhook_with_token', ' DELETE', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    })
end

static'execute_webhook'

function api:execute_webhook(webhook_id, webhook_token, payload, query, files)
    return self:request('execute_webhook', 'POST', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    }, payload, query, files)
end

static'execute_slack_compatible_webhook'

function api:execute_slack_compatible_webhook(webhook_id, webhook_token, payload, query)
    return self:request('execute_slack_compatible_webhook', 'POST', '/webhooks/:webhook_id/:webhook_token/slack', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    }, payload, query)
end

static'execute_github_compatible_webhook'

function api:execute_github_compatible_webhook(webhook_id, webhook_token, payload, query)
    return self:request('execute_github_compatible_webhook', 'POST', '/webhooks/:webhook_id/:webhook_token/github', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    }, payload, query)
end

static'edit_webhook_message'

function api:edit_webhook_message(webhook_id, webhook_token, message_id, payload)
    return self:request('edit_webhook_message', 'PATCH', '/webhooks/:webhook_id/:webhook_token/messages/:message_id', {
       webhook_id = webhook_id,
       webhook_token = webhook_token,
       message_id = message_id
    }, payload)
end

static'delete_webhook_message'

function api:delete_webhook_message(webhook_id, webhook_token, message_id)
    return self:request('delete_webhook_message', 'DELETE', '/webhooks/:webhook_id/:webhook_token/messages/:message_id', {
        webhook_id = webhook_id,
        webhook_token = webhook_token,
        message_id = message_id
     })
end

function api:list_voice_regions()
    return self:request('list_voice_regions', 'GET', '/voice/regions',empty_route)
end

function api:get_global_application_commands(application_id)
    return self:request('get_global_application_commands', 'GET', '/applications/:application_id/commands', {
       application_id = application_id
    })
end

function api:create_global_application_command(application_id,  payload)
    return self:request('create_global_application_command', 'POST', '/applications/:application_id/commands', {
       application_id = application_id
    }, payload)
end

function api:get_global_application_command(application_id, command_id)
    return self:request('get_global_application_command', 'GET', '/applications/:application_id/commands/:command_id', {
       application_id = application_id,
       command_id = command_id
    })
end

function api:edit_global_application_command(application_id, command_id, payload)
    return self:request('edit_global_application_command', 'PATCH', '/applications/:application_id/commands/:command_id', {
       application_id = application_id,
       command_id = command_id
    }, payload)
end

function api:delete_global_application_command(application_id, command_id)
    return self:request('delete_global_application_command', 'DELETE', '/applications/:application_id/commands/:command_id', {
       application_id = application_id,
       command_id = command_id
    })
end

function api:bulk_overwrite_global_application_commands(application_id, payload)
    return self:request('bulk_overwrite_global_application_commands', 'PUT', '/applications/:application_id/commands', {
       application_id = application_id
    }, payload)
end

function api:create_guild_application_command(application_id, guild_id, payload)
    return self:request('create_guild_application_command', 'POST', '/applications/:application_id/guilds/:guild_id/commands', {
       application_id = application_id,
       guild_id = guild_id
    }, payload)
end

function api:get_guild_application_command(application_id, guild_id, command_id)
    return self:request('get_guild_application_command', 'GET', '/applications/:application_id/guilds/:guild_id/commands/:command_id', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    })
end

function api:edit_guild_application_command(application_id, guild_id, command_id, payload)
    return self:request('edit_guild_application_command', 'PATCH', '/applications/:application_id/guilds/:guild_id/commands/:command_id', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    }, payload)
end

function api:delete_guild_application_command(application_id, guild_id, command_id)
    return self:request('delete_guild_application_command', 'DELETE', '/applications/:application_id/guilds/:guild_id/commands/:command_id', {
        application_id = application_id,
        guild_id = guild_id,
        command_id = command_id
    })
end

function api:get_guild_application_commands(application_id, guild_id)
    return self:request('get_guild_application_commands', 'GET', '/applications/:application_id/guilds/:guild_id/commands', {
       application_id = application_id,
       guild_id = guild_id
    })
end

function api:bulk_overwrite_guild_application_commands(application_id, guild_id, payload)
    return self:request('bulk_overwrite_guild_application_commands', 'PUT', '/applications/:application_id/guilds/:guild_id/commands', {
       application_id = application_id,
       guild_id = guild_id
    }, payload)
end

function api:get_guild_application_command_permissions(application_id, guild_id)
    return self:request('get_guild_application_command_permissions', 'GET', '/applications/:application_id/guilds/:guild_id/commands/permissions', {
       application_id = application_id,
       guild_id = guild_id
    })
end

function api:get_application_command_permissions(application_id, guild_id, command_id)
    return self:request('get_application_command_permissions', 'GET', '/applications/:application_id/guilds/:guild_id/commands/:command_id/permissions', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    })
end

function api:edit_application_command_permissions(application_id, guild_id, command_id, payload)
    return self:request('edit_application_command_permissions', 'PUT', '/applications/:application_id/guilds/:guild_id/commands/:command_id/permissions', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    }, payload)
end

function api:batch_edit_application_command_permissions(application_id, guild_id, payload)
    return self:request('batch_edit_application_command_permissions', 'PUT', '/applications/:application_id/guilds/:guild_id/commands/permissions', {
       application_id = application_id,
       guild_id = guild_id
    }, payload)
end

function api:get_token(data)
    return self:request('get_token', 'POST', '/oauth2/token', empty_route, data)
end

function api:get_sticker(sticker_id)
    return self:request('get_sticker', 'GET', '/stickers/:sticker_id', {
       sticker_id = sticker_id
    })
end

function api:list_nitro_sticker_packs()
    return self:request('list_nitro_sticker_packs', 'GET', '/sticker-packs', empty_route)
end

function api:list_guild_stickers(guild_id)
    return self:request('list_guild_stickers', 'GET', '/guilds/:guild_id/stickers', {
       guild_id = guild_id
    })
end

function api:get_guild_sticker(guild_id, sticker_id)
    return self:request('get_guild_sticker', 'GET', '/guilds/:guild_id/stickers/:sticker_id', {
       guild_id = guild_id,
       sticker_id = sticker_id
    })
end

function api:create_guild_sticker(guild_id,  payload, img)
    if not is_form(payload) then
        payload = a_form(payload)
    end
    return self:request('create_guild_sticker', 'POST', '/guilds/:guild_id/stickers', {
       guild_id = guild_id
    }, payload, nil, {img})
end

function api:modify_guild_sticker(guild_id, sticker_id, payload)
    return self:request('modify_guild_sticker', 'PATCH', '/guilds/:guild_id/stickers/:sticker_id', {
       guild_id = guild_id,
       sticker_id = sticker_id
    }, payload)
end

function api:delete_guild_sticker(guild_id, sticker_id)
    return self:request('delete_guild_sticker', 'DELETE', '/guilds/:guild_id/stickers/:sticker_id', {
       guild_id = guild_id,
       sticker_id = sticker_id
    })
end

function api:create_stage_instance(payload)
    return self:request('create_stage_instance', 'POST', '/stage-instances', empty_route, payload)
end

function api:get_stage_instance(channel_id)
    return self:request('get_stage_instance', 'GET', '/stage-instances/:channel_id', {
       channel_id = channel_id
    })
end

function api:modify_stage_instance(channel_id, payload)
    return self:request('modify_stage_instance', 'PATCH', '/stage-instances/:channel_id', {
       channel_id = channel_id
    }, payload)
end

function api:delete_stage_instance(channel_id)
    return self:request('delete_stage_instance', 'DELETE', '/stage-instances/:channel_id', {
       channel_id = channel_id
    })
end

function api:get_guild_template(template_code)
    return self:request('get_guild_template', 'GET', '/guilds/templates/:template_code', {
       template_code = template_code
    })
end

function api:create_guild_from_guild_template(template_code,  payload)
    return self:request('create_guild_from_guild_template', 'POST', '/guilds/templates/:template_code', {
       template_code = template_code,
    }, payload)
end

function api:get_guild_templates(guild_id)
    return self:request('get_guild_templates', 'GET', '/guilds/:guild_id/templates', {
       guild_id = guild_id
    })
end

function api:create_guild_template(guild_id,  payload)
    return self:request('create_guild_template', 'POST', '/guilds/:guild_id/templates', {
       guild_id = guild_id
    }, payload)
end

function api:sync_guild_template(guild_id, template_code, payload)
    return self:request('sync_guild_template', 'PUT', '/guilds/:guild_id/templates/:template_code', {
       guild_id = guild_id,
       template_code = template_code
    }, payload)
end

function api:modify_guild_template(guild_id, template_code, payload)
    return self:request('modify_guild_template', 'PATCH', '/guilds/:guild_id/templates/:template_code', {
       guild_id = guild_id,
       template_code
    }, payload)
end

function api:delete_guild_template(guild_id, template_code)
    return self:request('delete_guild_template', 'DELETE', '/guilds/:guild_id/templates/:template_code', {
       guild_id = guild_id,
       template_code = template_code
    })
end

function api:list_scheduled_guild_events(guild_id, query)
    return self:request('list_scheduled_guild_events', 'GET', '/guilds/:guild_id/scheduled-events', {
       guild_id = guild_id,
    }, nil,  query)
end

function api:create_scheduled_guild_event(guild_id,  payload)
    return self:request('create_scheduled_guild_event', 'POST', '/guilds/:guild_id/scheduled-events', {
       guild_id = guild_id
    }, payload)
end

function api:get_scheduled_guild_event(guild_id, event_id)
    return self:request('get_scheduled_guild_event', 'GET', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    })
end

function api:modify_scheduled_guild_event(guild_id, event_id,  payload)
    return self:request('modify_scheduled_guild_event', 'PATCH', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    }, payload)
end

function api:delete_scheduled_guild_event(guild_id, event_id)
    return self:request('delete_scheduled_guild_event', 'DELETE', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    })
end

function api:get_scheduled_guild_event_users(guild_id, event_id,  query)
    return self:request('get_scheduled_guild_event_users', 'GET', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id/users', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    }, nil,  query)
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
  return setm({self, success = true, result = {}, results = results, error = false}, cpmt)
end

local webhookm = {} for k, v in pairs(api) do
    webhookm[k] = v
end

webhookm.__index = webhookm

for k in pairs(static_methods) do
    if util.endswith(k, "_with_token") then
        local raw = webhookm[k]
        local function wrapped(self, id, ...)
            return raw(self, id, self.webhook_token, ...)
        end
        webhookm[util.prefix(k, "_with_token")] = wrapped
    end
end

function webhookm:execute_webhook(id, ...)
    return api.execute_webhook(self, id, self.webhook_token, ...)
end

function webhookm:execute_github_compatible_webhook(id, ...)
    return api.execute_github_compatible_webhook(self, id, self.webhook_token, ...)
end

function webhookm:execute_slack_compatible_webhook(id, ...)
    return api.execute_slack_compatible_webhook(self, id, self.webhook_token, ...)
end

function webhookm:request(name, ...)
    if not static_methods[name] then return logger.throw("requesting %s requires authentication!", name)
    else
        return api.request(self, name, ...)
    end
end

local function webhook_init(webhook_token)
    local webhook_api = setm({}, webhookm)
    webhook_api.routex = mutex_cache(webhook_token)

    webhook_api.rates = {}
    webhook_api.track_rates = false
    webhook_api.route_delay = 1
    webhook_api.api_timeout = 60
    webhook_api.accept_encoding = "gzip, deflate, x-gzip"
    webhook_api.webhook_token = webhook_token

    return webhook_api
end
_ENV.webhook_init = webhook_init

function with_reason(txt)
    local thr = cqueues.running()
    if not thr then err("Cannot add a contextual reason without a cqueues thread (using api methods outside a coroutine?).") end
    reason_thrs[thr] = reason_thrs[thr] or {}
    insert(reason_thrs[thr], 1, txt)
    return txt
end

if LACORD_DEBUG then
    function pre_push()
        local thr = cqueues.running()
        if not thr then err("Cannot grab contextual request object. (using api methods outside a coroutine?).") end
        pre_pushes[thr] = true
    end
end

return _ENV