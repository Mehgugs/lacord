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
local lpeg = require"lpeglabel"
local re = require"lacord.util.relabel"
local constants = require"lacord.const"
local mutex = require"lacord.util.mutex".new
local Date = require"lacord.util.date".Date
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local startswith = require"lacord.util.string".startswith
local inflate = zlib.inflate
local JSON = "application/json"
local tostring = tostring
local difftime = os.difftime
local time = os.time
local insert, concat = table.insert, table.concat
local next, tonumber = next, tonumber
local setmetatable = setmetatable
local max = math.max
local modf = math.modf
local xpcall = xpcall
local traceback = debug.traceback
local type = type
local ipairs, pairs = ipairs, pairs
local _VERSION = _VERSION
local decode = json.decode

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

local BOUNDARY1 = "lacord" .. ("%x"):format(util.hash(tostring(time())))
local BOUNDARY2 = "--" .. BOUNDARY1
local BOUNDARY3 = BOUNDARY2 .. "--"

local MULTIPART = ("multipart/form-data;boundary=%s"):format(BOUNDARY1)

local with_payload = {
    PUT = true,
    PATCH = true,
    POST = true,
}

local function mutex_cache()
    return setmetatable({},
    {
        __mode = "v",
        __index = function (self, k)
            self[k] = mutex(k)
            return self[k]
        end
    })
end


local next_key = re.compile[[
    key <- ident / numeral / quoted
        ident <- (iprefix isuffix*) -> "%s.%s"
            iprefix <- [a-zA-Z_-]
            isuffix <- iprefix / %d
        numeral <- %d+ -> "%s[%d]"
        quoted <- .+ -> "%s[%q]"
]]

local function parseErrors(ret, errors, key)
    for k, v in pairs(errors) do
        if k == '_errors' then
            for _, err in ipairs(v) do
                insert(ret, ('%s in %s : %q'):format(err.code, key or 'payload', err.message))
            end
        else
            if key then
                parseErrors(ret, v, next_key:match(k):format(key, k))
            else
                parseErrors(ret, v, k)
            end
        end
    end
    return concat(ret, '\n\t')
end

local check_anywhere = function(p) return util.anywhere(util.check(p)) end
local digits = lpeg.digit^1
local message_endpoint = util.check("/channels" * digits * "/messages/" * digits * -1)
local major_params = lpeg.P"channels" + "guilds" + "webhooks"
local is_major_route = check_anywhere((lpeg.P"channels" + "guilds" + "webhooks") * "/" * digits * -1)
local ends_in_id = check_anywhere("/" * digits * -1)
local trailing_id = util.anywhere(lpeg.C(util.lazy(1,"/")) * digits * -1)

local get_major_params = lpeg.Ct(util.anywhere(major_params * "/" * lpeg.C(digits))^0)
    /function(t) return #t > 0 and concat(t, "-") or nil end


local function route_of(endpoint, method)
    if endpoint:find('reactions', 1, true) then
        return endpoint:match('.*/reactions')
    elseif method == "DELETE" and message_endpoint:match(endpoint) then
        return 'MESSAGE_DELETE-'..trailing_id:match(endpoint)
    elseif endpoint:sub(1,9) == "/invites/" then
        return "/invites/"
    elseif is_major_route:match(endpoint) then
        return endpoint
    elseif ends_in_id:match(endpoint) then
        return trailing_id:match(endpoint)
    else
        return endpoint
    end
end

local function attachFiles(payload, files)
    local ret = {
        BOUNDARY2,
        "Content-Disposition:form-data;name=\"payload_json\"",
        "Content-Type:application/json\r\n",
        payload,
    }
    for i, v in ipairs(files) do
        insert(ret, BOUNDARY2)
        insert(ret, ("Content-Disposition:form-data;name=\"file%i\";filename=%q"):format(i, v[1]))
        insert(ret, "Content-Type:application/octet-stream\r\n")
        insert(ret, v[2])
    end
    insert(ret, BOUNDARY3)
    return concat(ret, "\r\n")
end

local precisions = {
     second = true
    ,millisecond = true
}

--- Creates a new api state for connecting to discord.
-- @tab options The options table. Must contain a `token` field with the api token to use.
-- @treturn api The api state object.
function init(options)
    local state = setmetatable({}, _ENV)
    if not (options.token and options.token:sub(1,4) == "Bot ") then
        return logger.fatal("Please supply a bot token! It must start with $white;'Bot '$error;.")
    end
    state.token = options.token
    state.routex = mutex_cache()
    state.global_lock = mutex()
    state.precision = "second"
    if not not options.accept_encoding then
        state.accept_encoding = "gzip, deflate, gzip-x"
        logger.info("%s is using $white;accept-encoding: %q", state, state.accept_encoding)
    end
    if precisions[options.precision] then
        state.precision = options.precision
    end
    logger.info("Initialized %s with TOKEN-%x", state, util.hash(state.token))
    return state
end

local function mapquery(Q)
    local out = {}
    for i, v in ipairs(Q) do out[i] = tostring(v) end
    return out
end

local function get_routex(routes, key)
    local item = routes[key]
    if type(item) == 'string' then return get_routex(routes, item)
    else return item
    end
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
function request(state, method, endpoint, payload, query, files)
    if not cqueues.running() then
        return logger.fatal("Please call REST methods asynchronously.")
    end
    local url = URL .. endpoint
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
    if state.precision then
        req.headers:append("x-ratelimit-precision", state.precision)
    end
    if with_payload[method] then
        payload = payload and json.encode(payload) or '{}'
        if files and next(files) then
            payload = attachFiles(payload, files)
            req.headers:append('content-type', MULTIPART)
        else
            req.headers:append('content-type', JSON)
        end
        req.headers:append("content-length", #payload)
        req:set_body(payload)
    end

    local route = route_of(endpoint, method)

    get_routex(state.routex, route):lock()

    local success, data, err, delay = xpcall(push, traceback, state, req, method, route, 0)
    if not success then
        return logger.fatal("api.push failed %q", tostring(data))
    end

    get_routex(state.routex, route):unlock_after(delay)

    return not err, data, err
end

function push(state, req, method,route, retries)
    local delay = 1 -- seconds
    local global = false -- whether the delay incurred is on the global limit

    local headers , stream , eno = req:go(60)

    if not headers and retries < constants.api.max_retries then
        local rsec = util.rand(1, 2)
        logger.warn("%s failed to %s:%s because %q (%s, %q) retrying after %.3fsec",
            state, method,route, tostring(stream), errno[eno], errno.strerror(eno), rsec
        )
        cqueues.sleep(rsec)
        return push(state, req, method,route, retries+1)
    elseif not headers and retries >= constants.api.max_retries then
        return nil, errno.strerror(eno), delay, global
    end
    local code, rawcode,stat

    stat = headers:get":status"
    rawcode, code = stat, tonumber(stat)

    local date = headers:get"date"
    local remaining =  headers:get"x-ratelimit-remaining"
    local reset = headers:get"x-ratelimit-reset"
    reset = reset and tonumber(reset)

    if remaining == '0' and reset then
        local secs, rest = modf(reset)
        local dt = difftime(secs, Date.parseHeader(date))
        delay = max(dt+rest, delay)
    end

    local route_id = headers:get"x-ratelimit-bucket"
    if route_id and not startswith(route, "MESSAGE_DELETE") then
        local major_key = get_major_params:match(route)
        local bucket = (major_key and major_key .. '-' or '') .. route_id
        if state.routex[route] ~= bucket then
            logger.info("%s grouping route $white;%q$info; into bucket $white;%s[%s]$info;.", state, route, route_id, bucket)
            local routex = state.routex[bucket]
            routex.inuse = true
            state.routex[route].handoff = routex.pollfd
            state.routex[route] = bucket
        end
    end

    local raw = stream:get_body_as_string()

    if headers:get"content-encoding" == "gzip"
    or headers:get"content-encoding" == "deflate"
    or headers:get"content-encoding" == "gzip-x" then
        raw = inflate()(raw, true)
    end

    local data = headers:get"content-type" == JSON and decode(raw) or raw
    if code < 300 then
        return data, nil, delay, global
    else
        if type(data) == 'table' then
            local retry;
            if code == 429 then
                delay = data.retry_after / 1000
                global = data.global
                retry = retries < 5
            elseif code == 502 then
                delay = delay + util.rand(0 , 2)
                retry = retries < 5
            end

            if retry then
                logger.warn("(%i, %q) :  retrying after %fsec : %s%s", code, reason[rawcode], delay, method, route)
                cqueues.sleep(delay)
                return push(state, req, method,route, retries+1)
            end

            local msg
            if data.code and data.message then
                msg = ('HTTP Error %i : %s'):format(data.code, data.message)
            else
                msg = 'HTTP Error'
            end
            if data.errors then
                msg = parseErrors({msg}, data.errors)
            end

            data = msg
        end
        logger.error("(%i, %q) : %s%s", code, reason[rawcode], method, route)
        return nil, data, delay, global
    end
end

local endpoints = {
    APPLICATION_ENTITLEMENT         = "/applications/%u/entitlements/%u",
    APPLICATION_ENTITLEMENTS        = "/applications/%u/entitlements",
    APPLICATION_ENTITLEMENT_        = "/applications/%u/entitlements/%u/",
    APPLICATION_ENTITLEMENT_CONSUME = "/applications/%u/entitlements/%u/consume",
    APPLICATION_SKUS                = "/applications/%u/skus",
    CHANNEL                         = "/channels/%u",
    CHANNEL_INVITES                 = "/channels/%u/invites",
    CHANNEL_MESSAGE                 = "/channels/%u/messages/%u",
    CHANNEL_MESSAGES                = "/channels/%u/messages",
    CHANNEL_MESSAGES_BULK_DELETE    = "/channels/%u/messages/bulk-delete",
    CHANNEL_MESSAGE_REACTION        = "/channels/%u/messages/%u/reactions/%s",
    CHANNEL_MESSAGE_REACTIONS       = "/channels/%u/messages/%u/reactions",
    CHANNEL_MESSAGE_REACTION_ME     = "/channels/%u/messages/%u/reactions/%s/@me",
    CHANNEL_MESSAGE_REACTION_USER   = "/channels/%u/messages/%u/reactions/%u",
    CHANNEL_PERMISSION              = "/channels/%u/permissions/%u",
    CHANNEL_PIN                     = "/channels/%u/pins/%u",
    CHANNEL_PINS                    = "/channels/%u/pins",
    CHANNEL_RECIPIENT               = "/channels/%u/recipients/%u",
    CHANNEL_TYPING                  = "/channels/%u/typing",
    CHANNEL_WEBHOOKS                = "/channels/%u/webhooks",
    GATEWAY                         = "/gateway",
    GATEWAY_BOT                     = "/gateway/bot",
    GUILD                           = "/guilds/%u",
    GUILDS                          = "/guilds",
    GUILD_AUDIT_LOGS                = "/guilds/%u/audit-logs",
    GUILD_BAN                       = "/guilds/%u/bans/%u",
    GUILD_BANS                      = "/guilds/%u/bans",
    GUILD_CHANNELS                  = "/guilds/%u/channels",
    GUILD_EMBED                     = "/guilds/%u/embed",
    GUILD_EMOJI                     = "/guilds/%u/emojis/%u",
    GUILD_EMOJIS                    = "/guilds/%u/emojis",
    GUILD_INTEGRATION               = "/guilds/%u/integrations/%u",
    GUILD_INTEGRATIONS              = "/guilds/%u/integrations",
    GUILD_INTEGRATION_SYNC          = "/guilds/%u/integrations/%u/sync",
    GUILD_INVITES                   = "/guilds/%u/invites",
    GUILD_MEMBER                    = "/guilds/%u/members/%u",
    GUILD_MEMBERS                   = "/guilds/%u/members",
    GUILD_MEMBERS_ME_NICK           = "/guilds/%u/members/@me/nick",
    GUILD_MEMBER_ROLE               = "/guilds/%u/members/%u/roles/%u",
    GUILD_PRUNE                     = "/guilds/%u/prune",
    GUILD_REGIONS                   = "/guilds/%u/regions",
    GUILD_ROLE                      = "/guilds/%u/roles/%u",
    GUILD_ROLES                     = "/guilds/%u/roles",
    GUILD_VANITY_URL                = "/guilds/%u/vanity-url",
    GUILD_WEBHOOKS                  = "/guilds/%u/webhooks",
    GUILD_WIDGET_PNG                = "/guilds/%u/widget.png",
    INVITE                          = "/invites/%s",
    OAUTH2_APPLICATIONS_ME          = "/oauth2/applications/@me",
    STORE_SKU_DISCOUNT_             = "/store/skus/%u/discounts/%u/",
    USER                            = "/users/%u",
    USERS_ME                        = "/users/@me",
    USERS_ME_CHANNELS               = "/users/@me/channels",
    USERS_ME_CONNECTIONS            = "/users/@me/connections",
    USERS_ME_GUILD                  = "/users/@me/guilds/%u",
    USERS_ME_GUILDS                 = "/users/@me/guilds",
    VOICE_REGIONS                   = "/voice/regions",
    WEBHOOK                         = "/webhooks/%u",
    WEBHOOK_TOKEN                   = "/webhooks/%u/%s",
    WEBHOOK_TOKEN_GITHUB            = "/webhooks/%u/%s/github",
    WEBHOOK_TOKEN_SLACK             = "/webhooks/%u/%s/slack",
}

--- Request a specific resource.
-- Function name is the routepath in snake_case
-- Please see the [discord api documentation](https://discordapp.com/developers/docs/reference) for requesting specific routes.
-- @function route_path
-- @tab state The api state.
-- @param ... Parameters to the request
-- @return @{api.request}
-- @usage
--  api.get_channel(state, id)

function get_entitlements(state, application_id)
    local endpoint = endpoints.APPLICATION_ENTITLEMENTS:format(application_id)
    return request(state, "GET", endpoint)
end

function get_entitlement(state, application_id, entitlement_id)
    local endpoint = endpoints.APPLICATION_ENTITLEMENT:format(application_id, entitlement_id)
    return request(state, "GET", endpoint)
end

function get_sKUs(state, application_id)
    local endpoint = endpoints.APPLICATION_SKUS:format(application_id)
    return request(state, "GET", endpoint)
end

function consume_sKU(state, application_id, entitlement_id, payload)
    local endpoint = endpoints.APPLICATION_ENTITLEMENT_CONSUME:format(application_id, entitlement_id)
    return request(state, "POST", endpoint, payload)
end

function delete_test_entitlement(state, application_id, entitlement_id)
    local endpoint = endpoints.APPLICATION_ENTITLEMENT_:format(application_id, entitlement_id)
    return request(state, "DELETE", endpoint)
end

function create_purchase_discount(state, sku_id, user_id, payload)
    local endpoint = endpoints.STORE_SKU_DISCOUNT_:format(sku_id, user_id)
    return request(state, "PUT", endpoint, payload)
end

function delete_purchase_discount(state, sku_id, user_id)
    local endpoint = endpoints.STORE_SKU_DISCOUNT_:format(sku_id, user_id)
    return request(state, "DELETE", endpoint)
end

function get_guild_audit_log(state, guild_id)
    local endpoint = endpoints.GUILD_AUDIT_LOGS:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_channel(state, channel_id)
    local endpoint = endpoints.CHANNEL:format(channel_id)
    return request(state, "GET", endpoint)
end

function modify_channel(state, channel_id, payload)
    local endpoint = endpoints.CHANNEL:format(channel_id)
    return request(state, "PATCH", endpoint, payload)
end

function delete_channel(state, channel_id)
    local endpoint = endpoints.CHANNEL:format(channel_id)
    return request(state, "DELETE", endpoint)
end

function get_channel_messages(state, channel_id)
    local endpoint = endpoints.CHANNEL_MESSAGES:format(channel_id)
    return request(state, "GET", endpoint)
end

function get_channel_message(state, channel_id, message_id)
    local endpoint = endpoints.CHANNEL_MESSAGE:format(channel_id, message_id)
    return request(state, "GET", endpoint)
end

function create_message(state, channel_id, payload)
    local endpoint = endpoints.CHANNEL_MESSAGES:format(channel_id)
    return request(state, "POST", endpoint, payload)
end

function create_reaction(state, channel_id, message_id, emoji, payload)
    local endpoint = endpoints.CHANNEL_MESSAGE_REACTION_ME:format(channel_id, message_id, emoji)
    return request(state, "PUT", endpoint, payload)
end

function delete_own_reaction(state, channel_id, message_id, emoji)
    local endpoint = endpoints.CHANNEL_MESSAGE_REACTION_ME:format(channel_id, message_id, emoji)
    return request(state, "DELETE", endpoint)
end

function delete_user_reaction(state, channel_id, message_id, emoji, user_id)
    local endpoint = endpoints.CHANNEL_MESSAGE_REACTION_USER:format(channel_id, message_id, emoji, user_id)
    return request(state, "DELETE", endpoint)
end

function get_reactions(state, channel_id, message_id, emoji)
    local endpoint = endpoints.CHANNEL_MESSAGE_REACTION:format(channel_id, message_id, emoji)
    return request(state, "GET", endpoint)
end

function delete_all_reactions(state, channel_id, message_id)
    local endpoint = endpoints.CHANNEL_MESSAGE_REACTIONS:format(channel_id, message_id)
    return request(state, "DELETE", endpoint)
end

function edit_message(state, channel_id, message_id, payload)
    local endpoint = endpoints.CHANNEL_MESSAGE:format(channel_id, message_id)
    return request(state, "PATCH", endpoint, payload)
end

function delete_message(state, channel_id, message_id)
    local endpoint = endpoints.CHANNEL_MESSAGE:format(channel_id, message_id)
    return request(state, "DELETE", endpoint)
end

function bulk_delete_messages(state, channel_id, payload)
    local endpoint = endpoints.CHANNEL_MESSAGES_BULK_DELETE:format(channel_id)
    return request(state, "POST", endpoint, payload)
end

function edit_channel_permissions(state, channel_id, overwrite_id, payload)
    local endpoint = endpoints.CHANNEL_PERMISSION:format(channel_id, overwrite_id)
    return request(state, "PUT", endpoint, payload)
end

function get_channel_invites(state, channel_id)
    local endpoint = endpoints.CHANNEL_INVITES:format(channel_id)
    return request(state, "GET", endpoint)
end

function create_channel_invite(state, channel_id, payload)
    local endpoint = endpoints.CHANNEL_INVITES:format(channel_id)
    return request(state, "POST", endpoint, payload)
end

function delete_channel_permission(state, channel_id, overwrite_id)
    local endpoint = endpoints.CHANNEL_PERMISSION:format(channel_id, overwrite_id)
    return request(state, "DELETE", endpoint)
end

function trigger_typing_indicator(state, channel_id, payload)
    local endpoint = endpoints.CHANNEL_TYPING:format(channel_id)
    return request(state, "POST", endpoint, payload)
end

function get_pinned_messages(state, channel_id)
    local endpoint = endpoints.CHANNEL_PINS:format(channel_id)
    return request(state, "GET", endpoint)
end

function add_pinned_channel_message(state, channel_id, message_id, payload)
    local endpoint = endpoints.CHANNEL_PIN:format(channel_id, message_id)
    return request(state, "PUT", endpoint, payload)
end

function delete_pinned_channel_message(state, channel_id, message_id)
    local endpoint = endpoints.CHANNEL_PIN:format(channel_id, message_id)
    return request(state, "DELETE", endpoint)
end

function group_dM_add_recipient(state, channel_id, user_id, payload)
    local endpoint = endpoints.CHANNEL_RECIPIENT:format(channel_id, user_id)
    return request(state, "PUT", endpoint, payload)
end

function group_dM_remove_recipient(state, channel_id, user_id)
    local endpoint = endpoints.CHANNEL_RECIPIENT:format(channel_id, user_id)
    return request(state, "DELETE", endpoint)
end

function list_guild_emojis(state, guild_id)
    local endpoint = endpoints.GUILD_EMOJIS:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_guild_emoji(state, guild_id, emoji_id)
    local endpoint = endpoints.GUILD_EMOJI:format(guild_id, emoji_id)
    return request(state, "GET", endpoint)
end

function create_guild_emoji(state, guild_id, payload)
    local endpoint = endpoints.GUILD_EMOJIS:format(guild_id)
    return request(state, "POST", endpoint, payload)
end

function modify_guild_emoji(state, guild_id, emoji_id, payload)
    local endpoint = endpoints.GUILD_EMOJI:format(guild_id, emoji_id)
    return request(state, "PATCH", endpoint, payload)
end

function delete_guild_emoji(state, guild_id, emoji_id)
    local endpoint = endpoints.GUILD_EMOJI:format(guild_id, emoji_id)
    return request(state, "DELETE", endpoint)
end

function create_guild(state, payload)
    local endpoint = endpoints.GUILDS
    return request(state, "POST", endpoint, payload)
end

function get_guild(state, guild_id)
    local endpoint = endpoints.GUILD:format(guild_id)
    return request(state, "GET", endpoint)
end

function modify_guild(state, guild_id, payload)
    local endpoint = endpoints.GUILD:format(guild_id)
    return request(state, "PATCH", endpoint, payload)
end

function delete_guild(state, guild_id)
    local endpoint = endpoints.GUILD:format(guild_id)
    return request(state, "DELETE", endpoint)
end

function get_guild_channels(state, guild_id)
    local endpoint = endpoints.GUILD_CHANNELS:format(guild_id)
    return request(state, "GET", endpoint)
end

function create_guild_channel(state, guild_id, payload)
    local endpoint = endpoints.GUILD_CHANNELS:format(guild_id)
    return request(state, "POST", endpoint, payload)
end

function modify_guild_channel_positions(state, guild_id, payload)
    local endpoint = endpoints.GUILD_CHANNELS:format(guild_id)
    return request(state, "PATCH", endpoint, payload)
end

function get_guild_member(state, guild_id, user_id)
    local endpoint = endpoints.GUILD_MEMBER:format(guild_id, user_id)
    return request(state, "GET", endpoint)
end

function list_guild_members(state, guild_id)
    local endpoint = endpoints.GUILD_MEMBERS:format(guild_id)
    return request(state, "GET", endpoint)
end

function add_guild_member(state, guild_id, user_id, payload)
    local endpoint = endpoints.GUILD_MEMBER:format(guild_id, user_id)
    return request(state, "PUT", endpoint, payload)
end

function modify_guild_member(state, guild_id, user_id, payload)
    local endpoint = endpoints.GUILD_MEMBER:format(guild_id, user_id)
    return request(state, "PATCH", endpoint, payload)
end

function modify_current_user_nick(state, guild_id, payload)
    local endpoint = endpoints.GUILD_MEMBERS_ME_NICK:format(guild_id)
    return request(state, "PATCH", endpoint, payload)
end

function add_guild_member_role(state, guild_id, user_id, role_id, payload)
    local endpoint = endpoints.GUILD_MEMBER_ROLE:format(guild_id, user_id, role_id)
    return request(state, "PUT", endpoint, payload)
end

function remove_guild_member_role(state, guild_id, user_id, role_id)
    local endpoint = endpoints.GUILD_MEMBER_ROLE:format(guild_id, user_id, role_id)
    return request(state, "DELETE", endpoint)
end

function remove_guild_member(state, guild_id, user_id)
    local endpoint = endpoints.GUILD_MEMBER:format(guild_id, user_id)
    return request(state, "DELETE", endpoint)
end

function get_guild_bans(state, guild_id)
    local endpoint = endpoints.GUILD_BANS:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_guild_ban(state, guild_id, user_id)
    local endpoint = endpoints.GUILD_BAN:format(guild_id, user_id)
    return request(state, "GET", endpoint)
end

function create_guild_ban(state, guild_id, user_id, payload)
    local endpoint = endpoints.GUILD_BAN:format(guild_id, user_id)
    return request(state, "PUT", endpoint, payload)
end

function remove_guild_ban(state, guild_id, user_id)
    local endpoint = endpoints.GUILD_BAN:format(guild_id, user_id)
    return request(state, "DELETE", endpoint)
end

function get_guild_roles(state, guild_id)
    local endpoint = endpoints.GUILD_ROLES:format(guild_id)
    return request(state, "GET", endpoint)
end

function create_guild_role(state, guild_id, payload)
    local endpoint = endpoints.GUILD_ROLES:format(guild_id)
    return request(state, "POST", endpoint, payload)
end

function modify_guild_role_positions(state, guild_id, payload)
    local endpoint = endpoints.GUILD_ROLES:format(guild_id)
    return request(state, "PATCH", endpoint, payload)
end

function modify_guild_role(state, guild_id, role_id, payload)
    local endpoint = endpoints.GUILD_ROLE:format(guild_id, role_id)
    return request(state, "PATCH", endpoint, payload)
end

function delete_guild_role(state, guild_id, role_id)
    local endpoint = endpoints.GUILD_ROLE:format(guild_id, role_id)
    return request(state, "DELETE", endpoint)
end

function get_guild_prune_count(state, guild_id)
    local endpoint = endpoints.GUILD_PRUNE:format(guild_id)
    return request(state, "GET", endpoint)
end

function begin_guild_prune(state, guild_id, payload)
    local endpoint = endpoints.GUILD_PRUNE:format(guild_id)
    return request(state, "POST", endpoint, payload)
end

function get_guild_voice_regions(state, guild_id)
    local endpoint = endpoints.GUILD_REGIONS:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_guild_invites(state, guild_id)
    local endpoint = endpoints.GUILD_INVITES:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_guild_integrations(state, guild_id)
    local endpoint = endpoints.GUILD_INTEGRATIONS:format(guild_id)
    return request(state, "GET", endpoint)
end

function create_guild_integration(state, guild_id, payload)
    local endpoint = endpoints.GUILD_INTEGRATIONS:format(guild_id)
    return request(state, "POST", endpoint, payload)
end

function modify_guild_integration(state, guild_id, integration_id, payload)
    local endpoint = endpoints.GUILD_INTEGRATION:format(guild_id, integration_id)
    return request(state, "PATCH", endpoint, payload)
end

function delete_guild_integration(state, guild_id, integration_id)
    local endpoint = endpoints.GUILD_INTEGRATION:format(guild_id, integration_id)
    return request(state, "DELETE", endpoint)
end

function sync_guild_integration(state, guild_id, integration_id, payload)
    local endpoint = endpoints.GUILD_INTEGRATION_SYNC:format(guild_id, integration_id)
    return request(state, "POST", endpoint, payload)
end

function get_guild_embed(state, guild_id)
    local endpoint = endpoints.GUILD_EMBED:format(guild_id)
    return request(state, "GET", endpoint)
end

function modify_guild_embed(state, guild_id, payload)
    local endpoint = endpoints.GUILD_EMBED:format(guild_id)
    return request(state, "PATCH", endpoint, payload)
end

function get_guild_vanity_uRL(state, guild_id)
    local endpoint = endpoints.GUILD_VANITY_URL:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_guild_widget_image(state, guild_id)
    local endpoint = endpoints.GUILD_WIDGET_PNG:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_invite(state, invite_code)
    local endpoint = endpoints.INVITE:format(invite_code)
    return request(state, "GET", endpoint)
end

function delete_invite(state, invite_code)
    local endpoint = endpoints.INVITE:format(invite_code)
    return request(state, "DELETE", endpoint)
end

function get_current_user(state)
    local endpoint = endpoints.USERS_ME
    return request(state, "GET", endpoint)
end

function get_user(state, user_id)
    local endpoint = endpoints.USER:format(user_id)
    return request(state, "GET", endpoint)
end

function modify_current_user(state, payload)
    local endpoint = endpoints.USERS_ME
    return request(state, "PATCH", endpoint, payload)
end

function get_current_user_guilds(state)
    local endpoint = endpoints.USERS_ME_GUILDS
    return request(state, "GET", endpoint)
end

function leave_guild(state, guild_id)
    local endpoint = endpoints.USERS_ME_GUILD:format(guild_id)
    return request(state, "DELETE", endpoint)
end

function get_user_dMs(state)
    local endpoint = endpoints.USERS_ME_CHANNELS
    return request(state, "GET", endpoint)
end

function create_dM(state, payload)
    local endpoint = endpoints.USERS_ME_CHANNELS
    return request(state, "POST", endpoint, payload)
end

function create_group_dM(state, payload)
    local endpoint = endpoints.USERS_ME_CHANNELS
    return request(state, "POST", endpoint, payload)
end

function get_user_connections(state)
    local endpoint = endpoints.USERS_ME_CONNECTIONS
    return request(state, "GET", endpoint)
end

function list_voice_regions(state)
    local endpoint = endpoints.VOICE_REGIONS
    return request(state, "GET", endpoint)
end

function create_webhook(state, channel_id, payload)
    local endpoint = endpoints.CHANNEL_WEBHOOKS:format(channel_id)
    return request(state, "POST", endpoint, payload)
end

function get_channel_webhooks(state, channel_id)
    local endpoint = endpoints.CHANNEL_WEBHOOKS:format(channel_id)
    return request(state, "GET", endpoint)
end

function get_guild_webhooks(state, guild_id)
    local endpoint = endpoints.GUILD_WEBHOOKS:format(guild_id)
    return request(state, "GET", endpoint)
end

function get_webhook(state, webhook_id)
    local endpoint = endpoints.WEBHOOK:format(webhook_id)
    return request(state, "GET", endpoint)
end

function get_webhook_with_token(state, webhook_id, webhook_token)
    local endpoint = endpoints.WEBHOOK_TOKEN:format(webhook_id, webhook_token)
    return request(state, "GET", endpoint)
end

function modify_webhook(state, webhook_id, payload)
    local endpoint = endpoints.WEBHOOK:format(webhook_id)
    return request(state, "PATCH", endpoint, payload)
end

function modify_webhook_with_token(state, webhook_id, webhook_token, payload)
    local endpoint = endpoints.WEBHOOK_TOKEN:format(webhook_id, webhook_token)
    return request(state, "PATCH", endpoint, payload)
end

function delete_webhook(state, webhook_id)
    local endpoint = endpoints.WEBHOOK:format(webhook_id)
    return request(state, "DELETE", endpoint)
end

function delete_webhook_with_token(state, webhook_id, webhook_token)
    local endpoint = endpoints.WEBHOOK_TOKEN:format(webhook_id, webhook_token)
    return request(state, "DELETE", endpoint)
end

function execute_webhook(state, webhook_id, webhook_token, payload)
    local endpoint = endpoints.WEBHOOK_TOKEN:format(webhook_id, webhook_token)
    return request(state, "POST", endpoint, payload)
end

function execute_slack_compatible_webhook(state, webhook_id, webhook_token, payload)
    local endpoint = endpoints.WEBHOOK_TOKEN_SLACK:format(webhook_id, webhook_token)
    return request(state, "POST", endpoint, payload)
end

function execute_gitHub_compatible_webhook(state, webhook_id, webhook_token, payload)
    local endpoint = endpoints.WEBHOOK_TOKEN_GITHUB:format(webhook_id, webhook_token)
    return request(state, "POST", endpoint, payload)
end

function get_gateway(state)
    local endpoint = endpoints.GATEWAY
    return request(state, "GET", endpoint)
end

function get_gateway_bot(state)
    local endpoint = endpoints.GATEWAY_BOT
    return request(state, "GET", endpoint)
end

function get_current_application_information(state)
    local endpoint = endpoints.OAUTH2_APPLICATIONS_ME
    return request(state, "GET", endpoint)
end

return _ENV