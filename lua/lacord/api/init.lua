--- Discord REST API
-- @module api
local corunning = coroutine.running
local err       = error
local max       = math.max
local pairs     = pairs
local setm      = setmetatable
local tonumber  = tonumber
local tostring  = tostring
local next      = next
local traceback = debug.traceback
local type      = type
local xpcall    = xpcall

local concat = table.concat
local insert = table.insert
local remove = table.remove
local unpack = table.unpack

local base64      = require"basexx".to_base64
local cli         = require"lacord.cli"
local constants   = require"lacord.const"
local cqueues     = require"cqueues"
local decode      = require"lacord.util.json".decode
local errno       = require"cqueues.errno"
local httputil    = require"http.util"
local inspect     = require"inspect"
local logger      = require"lacord.util.logger"
local newreq      = require"http.request"
local methods     = require"lacord.api.methods"
local add_payload = require"lacord.api.payload"
local ratelimit   = require"lacord.api.ratelimiting"
local webhooks    = require"lacord.api.webhooks"
local reason      = require"http.h1_reason_phrases"
local util        = require"lacord.util"
local zlib        = require"http.zlib"

local inflate      = zlib.inflate
local JSON         = util.content_types.JSON
local LACORD_DEBUG = cli.debug
local sleep        = cqueues.sleep
local ver          = concat({util.version_major, util.version_minor, util.version_release}, ".")

local initialize_ratelimit_properties = ratelimit.initialize_ratelimit_properties
local get_bucket                      = ratelimit.get_bucket
local handle_delay                    = ratelimit.handle_delay




local _ENV = {}

--luacheck: ignore 111 631

local api = {__name = "lacord.api"}
api.__index = api
api.__lacord_is_api = true


local URL = constants.api.endpoint
local USER_AGENT = ("DiscordBot (%s, %s) lua-version:\"%s\""):format(constants.homepage,constants.version, ver )

--- Convert a route into a real url by substituting route :parameters for their values.
local function resolve_endpoint(ep, rp)
    return ep:gsub(":([a-z_]+)", rp)
end

--- Select the major parameters present in a set of route parameters.
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

    if type(options) == 'string' then
        options = {token = options}
    end

    if options.client_credentials then
        auth = "Basic " .. base64(("%s:%s"):format(options.client_credentials[1], options.client_credentials[2]))
        state.auth_kind = "client_credentials"
    elseif options.token and options.token:sub(1,4) == "Bot " then
        auth = options.token
        state.auth_kind = "bot"
    elseif options.token and options.token:sub(1,7) == "Bearer " then
        auth = options.token
        state.auth_kind = "bearer"
    elseif options.webhook then
        state.auth_kind = "webhook"
    else
        return logger.fatal("Please supply a token, client credentials, or webhook! It must start with $white;'Bot|Bearer '$error;.")
    end

    state.token = auth

    initialize_ratelimit_properties(state, options)

    state.api_timeout = tonumber(options.api_timeout)
    state.api_http_version = 1.1

    if LACORD_DEBUG then state.expect_100_timeout = options.expect_100_timeout end
    if not not options.accept_encoding then
        state.accept_encoding = "gzip, deflate, x-gzip"
        logger.debug("%s is using $accept-encoding: %q;", state, state.accept_encoding)
    end
    logger.debug("Initialized %s with TOKEN-%x", state, state.token and util.hash(state.token) or 0)

    if options.checks == false then
        api:remove_checks()
    else
        api:enable_checks()
    end

    return state
end

local function mapquery(Q)
    local out = {}
    for i, v in pairs(Q) do out[i] = tostring(v) end
    return out
end

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

local push2

local function make_request(self, name, method, endpoint, route_parameters, payload, query, files)
    local resolved_ep = resolve_endpoint(endpoint, route_parameters)
    local url = URL .. resolved_ep

    if query and next(query) then
        url = ("%s?%s"):format(url, httputil.dict_to_query(mapquery(query)))
    end

    local req = newreq.new_from_uri(httputil.encodeURI(url))
    req.version = self.api_http_version

    req.headers:upsert(":method", method)
    req.headers:upsert("user-agent", USER_AGENT)
    if self.token then req.headers:append("authorization", self.token) end

    if self.accept_encoding then
        req.headers:append("accept-encoding", self.accept_encoding)
    end

    local co = corunning() if not co then logger.fatal("lacord.api: called an api method outside of a cqueues controller.") end

    local reasons = reason_thrs[co]
    if reasons and reasons[1] then
        req.headers:append("x-audit-log-reason", tostring(remove(reasons)))
    end

    add_payload(req, method, payload, files)

    -- Ratelimiting --

    local major_params = resolve_majors(route_parameters)
    local from_routex, first_time, bucket

    if not self.bucket_names[name] then
        self.routex[name]:lock()
        from_routex = true
        if not self.bucket_names[name] then
            first_time = true
            logger.debug("This request is being made without ratelimit information: %s", name)
            goto request
        end
    end

    bucket = get_bucket(self, self.bucket_names[name], major_params)
    bucket:enter()

    ::request::
    local success, data, erro, delay, extra = xpcall(push2, traceback, self, name, req, 0)

    if not success then
        logger.error("api.push failed %q", tostring(data))
        handle_delay(self, nil, name, major_params, bucket, first_time, from_routex)
        return nil
    end

    handle_delay(self, delay, name, major_params, bucket, first_time, from_routex)

    return not erro, data, erro, extra
end


function push2(state, name, req, retries)
    local delay_s = state.route_delay or 0 -- seconds
    state.global:enter()
    local headers , stream , eno = req:go(state.api_timeout or 60)

    if not headers and retries < constants.api.max_retries then
        local rsec = util.rand(1, 2)
        logger.warn("%s failed to %s because %q (%s, %q) retrying after %.3fsec",
            state, name, tostring(stream), eno and errno[eno] or "?", eno and errno.strerror(eno) or "??", rsec
        )
        cqueues.sleep(rsec)
        return push2(state, name, req, retries+1)
    elseif not headers and retries >= constants.api.max_retries then
        return nil, errno.strerror(eno), nil
    end

    local code, rawcode,stat

    stat = headers:get":status"
    rawcode, code = stat, tonumber(stat)

    local reset_after = headers:get"x-ratelimit-reset-after"
    local delay_limit = tonumber(headers:get"x-ratelimit-limit" or nil)

    if reset_after then
        reset_after = tonumber(reset_after)
        delay_s = max(delay_s, reset_after)
    end

    local delay_id = headers:get"x-ratelimit-bucket"

    local raw = stream:get_body_as_string()

    if headers:get"content-encoding" == "gzip"
    or headers:get"content-encoding" == "deflate"
    or headers:get"content-encoding" == "x-gzip" then
        raw = inflate()(raw, true)
    end

    local data = state.raw and raw or headers:get"content-type" == JSON and decode(raw) or raw
    if code < 300 then
        state.global:exit_after(1.0)
        if code == 204 then return true, nil, {delay_s, delay_id, delay_limit}
        else return data, nil, {delay_s, delay_id, delay_limit}
        end
    else
        local extra
        if state.raw then
            data = headers:get"content-type" == JSON and decode(raw) or raw
        end
        if type(data) == 'table' then
            local retry;
            local retry_after = data.retry_after or headers:get"retry-after"
            if code == 429 then

                if data.global or headers:get"x-ratelimit-global" then
                    state.global:exit_after(retry_after or 1.0)
                else
                    delay_s = retry_after
                    state.global:exit_after(1.0)
                end
                retry = retries < 5
            else
                state.global:exit_after(retry_after or 1.0)
            end

            if retry then
                local scope = headers:get"x-ratelimit-scope"
                logger.warn("($%i;, %q%s) :  retrying after $%f; sec : %s",
                    code, reason[rawcode], scope and (", scope: "..scope) or "", delay_s, name)

                sleep(delay_s)
                return push2(state, name, req, retries+1)
            end

            local msg
            if data.code and data.message then
                msg = ('HTTP Error $%i; : %s'):format(data.code, data.message)
            else
                msg = 'HTTP Error'
            end
            --TODO: handle data.errors again
            extra = data.errors
            if LACORD_DEBUG then
                logger.debug("%s", msg)
                logger.debug("$data.errors;\n" .. inspect(data.errors))
            end
            data = msg
        else
            state.global:exit_after(1.0)
        end
        local scope = headers:get"x-ratelimit-scope"
        logger.error("($%i;, %q%s) : %s",
            code, reason[rawcode], scope and (", scope: "..scope) or "", name)
        return nil, data, {delay_s, delay_id, delay_limit}, extra
    end
end

local authorization = methods(api)

local function checked_request(self, name, ...)
    if authorization[name][self.auth_kind] then
        return make_request(self, name, ...)
    else
        return nil, "You cannot use this method with your current authorization."
    end
end

function api:remove_checks()
    self.request = make_request
end

function api:enable_checks()
    self.request = checked_request
end



-- safe method chaining --

local cpmt = {}

local function results(self)
    return unpack(self.result)
end

local function failure(self)
    return self
end

local function continue(self, func, a)
    if self.success then
        local r

        if a then r = func(self, a, unpack(self.result))
        else r = func(self, unpack(self.result))
        end

        if r and r ~= self then
            insert(self.result, r)
        end
        return self
    else
        return self
    end
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
  return setm({self, success = true, result = {}, results = results, error = false, continue = continue}, cpmt)
end

--- Webhook initialization

webhooks(_ENV, api, authorization)


--- Thread local x-auditlog-reason & request debugging.

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


--- QoL helpers

local INVITE_URL = URL .. "/oauth2/authorize"

function invite_url(id, permissions, bot_only)
    return INVITE_URL .. "?" .. httputil.dict_to_query(mapquery{
        client_id = id,
        scope = bot_only and 'bot' or 'bot applications.commands',
        permissions = permissions,
    })
end

_ENV.mapquery = mapquery
_ENV.USER_AGENT = USER_AGENT
_ENV.URL = URL

return _ENV