--- Adapted from https://gist.github.com/daurnimator/192dc5b210718dd129cfc1e5986df97b
local cqueues = require "cqueues"
local cc = require "cqueues.condition"
local ce = require "cqueues.errno"
local new_headers = require "http.headers".new
local server = require "http.server"
local http_util = require "http.util"
local zlib = require "http.zlib"
local http_tls = require "http.tls"
local openssl_ssl = require "openssl.ssl"
local openssl_ctx = require "openssl.ssl.context"
local Pkey = require "openssl.pkey"
local Crt = require "openssl.x509"
local Chain = require"openssl.x509.chain"

local const = require"lacord.const"
local logger = require"lacord.util.logger"
local nacl = require"luatweetnacl"
local json = require"lacord.util.json"
local util = require"lacord.util"

local asserts = assert
local errors = error
local try = pcall
local setm = setmetatable
local to_s = tostring
local to_n = tonumber
local typ = type
local insert = table.insert
local traceback = debug.traceback
local openf = io.open
local date = os.date
local fmt = string.format
local char = string.char
local unpak = table.unpack
local content_typed = util.content_typed
local default_server = "lacord " .. const.version
local iiter = ipairs

--luacheck: ignore 111
local _ENV = {}

local function alpn_select(ssl, protos, version)
	for _, proto in iiter(protos) do
		if proto == "h2" and (version == nil or version == 2) then
			-- HTTP2 only allows >= TLSv1.2
			-- allow override via version
			if ssl:getVersion() >= openssl_ssl.TLS1_2_VERSION or version == 2 then
				return proto
			end
		elseif (proto == "http/1.1" and (version == nil or version == 1.1))
			or (proto == "http/1.0" and (version == nil or version == 1.0)) then
			return proto
		end
	end
	return nil
end

local function decode_hex(str)
    local bytes = {}
    for i = 1, #str, 2 do
        insert(bytes, to_n(str:sub(i, i + 1), 16))
    end
    return char(unpak(bytes))
end

local function decode_fullchain(crtfile)
	local crtf  = asserts(openf(crtfile, "r"))
	local crttxt = crtf:read"a"
	local crts, pos = {}, 1
	repeat
		local st, ed = crttxt:find("-----BEGIN CERTIFICATE-----", pos, true)
		if st then
			local st2, ed2 = crttxt:find("-----END CERTIFICATE-----", ed + 1, true)
			if st2 then
				insert(crts, crttxt:sub(st, ed2))
				pos = ed2+1
			end
		end
	until st == nil
	crtf:close()
	local chain = Chain.new()
	local primary = asserts(Crt.new(crts[1]))
	for i = 2, #crts do
		local crt = asserts(Crt.new(crts[i]))
		chain:add(crt)
	end
	return primary,chain
end

local function new_ctx(version, crtpath, keypath)
	local ctx = http_tls.new_server_context()
	if http_tls.has_alpn then
		ctx:setAlpnSelect(alpn_select, version)
	end
	if version == 2 then
		ctx:setOptions(openssl_ctx.OP_NO_TLSv1 + openssl_ctx.OP_NO_TLSv1_1)
	end
	local keyfile = asserts(openf(keypath, "r"))
	local primary,crt = decode_fullchain(crtpath)
	asserts(ctx:setPrivateKey(Pkey.new(keyfile:read"a")))
	asserts(ctx:setCertificate(primary))
	asserts(ctx:setCertificateChain(crt))
	keyfile:close()
	return ctx
end

local function check_compressed(headers, raw)
    if headers:get"content-encoding" == "gzip"
    or headers:get"content-encoding" == "deflate"
    or headers:get"content-encoding" == "x-gzip" then
        return zlib.inflate()(raw, true)
    end
    return raw
end

local PING_ACK = json.content_type{
    type = 1
}

local response_methods = {}
local response_mt = {
	__index = response_methods;
	__name = nil;
}

local function new_response(request_headers, stream)
	local headers = new_headers();
	-- Give some defaults
	headers:append(":status", "503")
	headers:append("server", default_server)
	headers:append("date", http_util.imf_date())
    local _, peer = stream:peername()
	return setm({
		request_headers = request_headers;
		stream = stream,
		-- Record peername upfront, as the client might disconnect before request is completed
		peername = peer,
        path = request_headers:get":path",
        method = request_headers:get":method",
		headers = headers,
		body = nil,
	}, response_mt)
end

function response_methods:combined_log()
	-- Log in "Combined Log Format"
	-- https://httpd.apache.org/docs/2.2/logs.html#combined
	return fmt('%s - - [%s] "%s %s HTTP/%g" %s %d "%s" "%s"',
		self.peername or "-",
		date("%d/%b/%Y:%H:%M:%S %z"),
		self.request_headers:get(":method") or "",
		self.request_headers:get(":path") or "",
		self.stream.connection.version,
		self.headers:get(":status") or "",
		self.stream.stats_sent,
		self.request_headers:get("referer") or "-",
		self.request_headers:get("user-agent") or "-")
end

function response_methods:set_body(body)
    local contenttype
    body, contenttype = content_typed(body)
    if contenttype then self.headers:upsert("content-type", contenttype) end
	self.body = body
	local length
	if typ(self.body) == "string" then
		length = #body
	end
	if length then
		self.headers:upsert("content-length", fmt("%d", #body))
	end
end

function response_methods:set_503()
	local headers = new_headers()
	headers:append(":status", "503")
	headers:append("server", default_server)
	headers:append("date", http_util.imf_date())
	self.headers = headers
	headers:append("content-type", "text/plain; charset=UTF-8")
	self:set_body"Internal server error."
end

function response_methods:set_401()
    local headers = new_headers()
    headers:append(":status", "401")
    headers:append("server", default_server)
    headers:append("date", http_util.imf_date())
    self.headers = headers
    headers:append("content-type", "text/plain; charset=UTF-8")
    self:set_body"Invalid request signature."
end

function response_methods:set_ok()
    local headers = new_headers()
    headers:append(":status", "201")
    headers:append("server", default_server)
    headers:append("date", http_util.imf_date())
    self.headers = headers
end

function response_methods:set_ok_and_reply(body, content_type)
    local headers = new_headers()
    headers:append(":status", "200")
    headers:append("server", default_server)
    headers:append("date", http_util.imf_date())
    self.headers = headers
    self:set_body(body)
    if content_type then  headers:upsert("content-type", content_type) end
end

function response_methods:set_code_and_reply(code, body, content_type)
    local headers = new_headers()
    headers:append(":status", to_s(code))
    headers:append("server", default_server)
    headers:append("date", http_util.imf_date())
    self.headers = headers
    self:set_body(body)
    if content_type then  headers:upsert("content-type", content_type) end
end

function response_methods:enable_compression()
	if self.headers:has("content-encoding") then
		return false
	end
	local deflater = zlib.deflate()
	local new_body = deflater(self.body, true)
	self.headers:append("content-encoding", "gzip")
	self.body = new_body
	return true
end

local function default_onerror(_, ...)
	logger.error(...)
end

local function server_onerror(_, context, op, err, _)
	local msg = op .. " on " .. to_s(context) .. " failed"
	if err then
		msg = msg .. ": " .. to_s(err)
	end
	logger.error(msg)
end

local function default_log(response)
	logger.error(response:combined_log())
end

function new(options, crtfile, keyfile)
    local pubkey = asserts(options.public_key, "Please provide your application's public key for signature verfication.")
	local interact = asserts(options.interact, "Please provide an event handler to receive interactions from.")
    local nondiscord = asserts(options.fallthrough, "Please provide a fallthrough function for non-discord related web requests.")
    local discordpath = options.route or "/"
	local onerror = options.onerror or default_onerror
	local log = options.log or default_log

	options.tls = true
	pubkey = decode_hex(pubkey)
	if options.version == nil then options.version = 1.1 end
	if crtfile then
		options.ctx = new_ctx(options.version, crtfile, keyfile)
	else
		if not options.ctx then
			logger.fatal("Cannot use a self-signed certificate; it will be rejected by discord.")
		end
	end

	local function onstream(_, stream)
		local req_headers, err, errno = stream:get_headers()
		if req_headers == nil then
			-- connection hit EOF before headers arrived
			stream:shutdown()
			if err ~= ce.EPIPE and errno ~= ce.ECONNRESET then
				onerror("header error: %s", to_s(err))
			end
			return
		end

		local resp = new_response(req_headers, stream)

		local ok,err2
		if resp.path == discordpath and resp.method == "POST" then
			local verified = false
			local raw = check_compressed(req_headers, stream:get_body_as_string())
			local sig, timestamp =
				req_headers:get"x-signature-ed25519",
				req_headers:get"x-signature-timestamp"
			if sig ~= "" and timestamp ~= "" then
				logger.info("using sig timestamp %s - %s", sig, timestamp)
				verified = nacl.sign_open(decode_hex(sig) .. timestamp .. raw, pubkey) ~= nil
			end

			if verified then
				local payload = json.decode(raw)
				if payload.type == 1 then
					ok = true
					resp:set_ok_and_reply(PING_ACK)
				else
					local ok_, res = try(interact, payload, resp)
					if not ok_ then ok, err2 = false, res
					else
						ok = true
						if res then
							resp:set_ok_and_reply(json.encode(res), "application/json")
						elseif not resp.body then -- they didn't set anything
							resp:set_code_and_reply(500, "No response available.", "text/plain; charset=UTF-8")
						end
					end
				end
			else
				ok = true
				resp:set_401()
			end
		else
			ok,err2 = try(nondiscord, resp)
		end

		if stream.state ~= "closed" and stream.state ~= "half closed (local)" then
			if not ok then
				resp:set_503()
			end
			local send_body = resp.body and req_headers:get ":method" ~= "HEAD"
			stream:write_headers(resp.headers, not send_body)
			if send_body then
				stream:write_chunk(resp.body, true)
			end
		end
		stream:shutdown()
		log(resp)
		if not ok then
			onerror("stream error: %s", to_s(err2))
		end
	end

	options.onstream = onstream
	options.onerror  = server_onerror

	local myserver = server.listen(options)

	return myserver
end

return _ENV