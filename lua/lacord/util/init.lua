local random = math.random
local popen = io.popen
local assert = assert
local error = error
local getm = getmetatable
local setm = setmetatable
local vstring = _VERSION
local to_n = tonumber
local to_s = tostring
local set = rawset
local typ = type
local insert = table.insert
local concat = table.concat
local iiter = ipairs
local iter = pairs
local encodeURIComponent = require"http.util".encodeURIComponent
local dict_to_query = require"http.util".dict_to_query
local _platform = require"lacord.util.archp".os
local mime = require"lacord.util.mime"

local _ENV = {}

-- luacheck: ignore 111

--- Computes the FNV-1a 32bit hash of the given string.
-- @str str The input string.
-- @treturn integer The hash.
function hash(str)
    local hash = 2166136261
    for i = 1, #str do
        hash = hash ~ str:byte(i)
        hash = (hash * 16777619) & 0xffffffff
    end
    return hash
end

--- Produces a random double between `A` and `B`.
function rand(A, B)
    return random() * (A - B) + A
end

--- The operating system platform.
-- @within Constants
-- @string platform
platform = _platform

do
    local vmj, vmn = vstring:match('Lua (%d)%.(%d)')

    _ENV.version_major = to_n(vmj)
    _ENV.version_minor = to_n(vmn)
    _ENV.version = _ENV.version_major + _ENV.version_minor / 10
end

--- Tests whether a string starts with a given prefix.
-- @str s The string to check.
-- @str prefix The prefix.
-- @treturn bool True if s starts with the prefix.
function startswith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

--- Returns the suffix of `pre` in `s`.
-- @str s The string to check.
-- @str pre The prefix.
-- @treturn string The suffix of `pre` in `s` or `s` if `s` does not start with `pre`.
function suffix(s, pre)
    local len = #pre
    return s:sub(1, len) == pre and s:sub(len + 1) or s
end

--- Tests whether a string ends with a given suffix.
-- @str s The string to check.
-- @str suffix The suffix.
-- @treturn bool True if s starts with the suffix.
function endswith(s, suffix)
    return s:sub(-#suffix) == suffix
end

--- Returns the prefix of `suf` in `s`.
-- @str s The string to check.
-- @str suf The suffix.
-- @treturn string The prefix of `suf` in `s` or `s` if `s` does not end with `suf`.
function prefix(s, suf)
  local len = #suf
  return s:sub(-len) == suf and s:sub(1, -len -1) or s
end

--- Resolve a prospective payload w.r.t lacord content types.
--  Users can check the 2nd return value to see if any processing was done.
function content_typed(payload, ...)
    local mt = getm(payload)
    if mt and mt.__lacord_content_type then
        return mt.__lacord_payload(payload, ...),mt.__lacord_content_type
    else
        return payload
    end
end

function the_content_type(payload)
    local mt = getm(payload)
    if mt and mt.__lacord_content_type then
        return mt.__lacord_content_type
    end
end

--- Some common content types.
_ENV.content_types = {
    JSON = "application/json",
    TEXT = "text/plain; charset=UTF-8",
    URLENCODED = "application/x-www-form-urlencoded",
    BYTES = "application/octet-stream",
    PNG = "image/png",
}


local txt = {
    __lacord_content_type = _ENV.content_types.TEXT,
    __lacord_payload = function(x) return x[1] end,
    __tostring = function(x) return x[1] end,
    __lacord_file_name = function(x) return x.name end,
    __lacord_set_file_name = function(self, value) self.name = value end,
}

function plaintext(str, name) return setm({str, name = name}, txt) end


local bin = {
    __lacord_content_type = _ENV.content_types.BYTES,
    __lacord_payload = function(x) return x[1] end,
    __tostring = function(x) return x[1] end,
    __lacord_file_name = function(x) return x.name end,
    __lacord_set_file_name = function(self, value) self.name = value end,
}

function binary(str, name) return setm({str, name = name}, bin) end


local virtual_filenames = setm({}, {__mode = "k"})


local urlencoded_t = {__lacord_content_type = "application/x-www-form-urlencoded"}

function urlencoded_t:__lacord_payload()
    return encodeURIComponent(dict_to_query(self))
end

function urlencoded_t:__lacord_file_name()
    return virtual_filenames[self]
end

function urlencoded_t:__lacord_set_file_name(value)
    virtual_filenames[self] = value
end

function urlencoded(t) return setm(t or {}, urlencoded_t) end


local form_t = {__lacord_content_type = "form"}

function form_t:__lacord_file_name()
    return virtual_filenames[self]
end

function form_t:__lacord_set_file_name(value)
    virtual_filenames[self] = value
end

function form(t)
    return setm(t or {}, form_t)
end

function form_t:__lacord_payload() return self end

function form_t:__newindex(k, v)
    if typ(k) ~= "string" then return error("Cannot set non string keys on a form!") end
    set(self, k, to_s(v))
end

function is_form(f) return getm(f) == form_t end


local png_t = {
    __lacord_content_type = "image/png",
    __lacord_payload = function(self) return self[1] end,
    __tostring = function(self) return self[1] end,
    __lacord_file_name = function(self) return self.name end,
    __lacord_set_file_name = function(self, value) self.name = value end,
}

function png(str, name)
    return setm({str, name = name ..".png"}, png_t)
end


local json_str = {
    __lacord_content_type = _ENV.content_types.JSON,
    __lacord_payload = function(x) return x[1] end,
    __tostring = function(x) return x[1] end,
    __lacord_file_name = function(x) return x.name end,
    __lacord_set_file_name = function(self, value) self.name = value end,
}

function json_string(data, name)
    return setm({data, name = name}, json_str)
end


function file_name(cted)
    local mt = getm(cted)
    return mt and mt.__lacord_file_name and mt.__lacord_file_name(cted) or ""
end

function set_file_name(cted, name)
    local mt = getm(cted)
    return mt and mt.__lacord_set_file_name and mt.__lacord_set_file_name(cted, name)
end

local mime_blob_ts = {}

local function new_mime_blob(content_type)
    if mime_blob_ts[content_type] then return mime_blob_ts[content_type]
    else
        local new = {
            __lacord_content_type = content_type,
            __lacord_payload = function(x) return x[1] end,
            __tostring = function(x) return x[1] end,
            __lacord_file_name = function(x) return x.name end,
            __lacord_set_file_name = function(self, value) self.name = value end,
        }
        mime_blob_ts[content_type] = new
        return new
    end
end

mime_blob_ts[_ENV.content_types.JSON] = json_str
mime_blob_ts[_ENV.content_types.TEXT] = txt
mime_blob_ts[_ENV.content_types.BYTES] = bin
mime_blob_ts[_ENV.content_types.PNG] = png_t

function a_blob_of(content_type, data, name)
    return setm({data, name = name}, new_mime_blob(content_type))
end

function blob_for_file(blob, name)
    local curname = _ENV.file_name(blob)
    if not curname or curname == "" then curname = name or "" end
    local base,ext = curname:match"^(.+)(%..+)"
    if not ext then
        if curname:sub(1,1) == "." then
            base = ""
            ext = curname
        else
            base = curname
            local ct = _ENV.the_content_type(blob)
            if mime.exts[ct] then
                ext = mime.exts[ct]
            else
                ext = ""
            end
        end
    end
    return base .. ext, (_ENV.content_typed(blob))
end


return _ENV