local asserts = assert
local iter    = pairs
local to_n    = tonumber
local unpak = unpack

local insert = table.insert

local char = string.char

local const  = require"lacord.const"
local shs    = require"lacord.ext.shs"
local util   = require"lacord.util"
local json   = require"lacord.util.json"

local sign_open = require"luatweetnacl".sign_open

local default_server = "lacord " .. const.version

local decode = json.decode

local content_typed = util.content_typed
local JSON          = util.content_types.JSON
local TEXT          = util.content_types.TEXT

local M = {}

-- decode a hexadecimal string into bytes
local function decode_hex(str)
    local bytes = {}
    for i = 1, #str, 2 do
        insert(bytes, to_n(str:sub(i, i + 1), 16))
    end
    return char(unpak(bytes))
end

local PING_ACK = json.encode{
    type = 1
}

local function generic_handler(R)
    if R.method == "POST" then
        local verified = false
        local raw = R:get_body()

        local sig, timestamp =
                R.request_headers:get"x-signature-ed25519",
                R.request_headers:get"x-signature-timestamp"

        if sig ~= "" and timestamp ~= "" then
            verified = sign_open(decode_hex(sig) .. timestamp .. raw, R.data.key) ~= nil
        end

        if verified then
            local payload = decode(raw)
            if not payload then return R:set_code_and_reply(400, "Payload was not json.")
            else
                if payload.type == 1 then
                    return R:set_ok_and_reply(PING_ACK, JSON)
                else
                    return R.data.inner(R, payload)
                end
            end
        else
            return R:set_401()
        end

    else
        return R:set_code_and_reply(404, "Not found!", TEXT)
    end
end

local mt = {} for k, v in iter(shs.response_mt) do mt[k] = v end

mt.__index = mt

do
    local inner = shs.response_mt.set_body
    function mt:set_body(content)
        local data,ct = content_typed(content)
        if ct then self.headers:upsert('content-type', ct) end
        return inner(data)
    end
end

function M.new(options, ...)
    local data = {key = asserts(options.public_key,
        "Please provide your application's public key for signature verfication.")}

    local routes = options.routes or {}

    local discordpath = options.route or '/'

    data.inner = routes[discordpath] or assert(options.interact,
        "Please provide an event handler to receive interactions from.")

    routes['*'] = routes['*'] or options.fallthrough

    routes[discordpath] = generic_handler


    return shs.new({
        routes = routes,
        host = options.host,
        port = options.port,
        server = options.server or default_server,
        ctx = options.ctx,
        data = data,
        response_mt = mt,
    }, ...)
end

return M