
local error  = error
local iiter  = ipairs
local iter   = pairs
local getm   = getmetatable
local setm   = setmetatable
local set    = rawset
local to_n   = tonumber
local to_s   = tostring
local typ    = type
local warn   = warn or function()end

local random = math.random

local getenv = os.getenv

local pkgloaded= package.loaded
local preload  = package.preload

local char     = string.char

local insert = table.insert
local concat = table.concat
local move   = table.move
local pak    = table.pack
local unpak  = table.unpack

local _VERSION = _VERSION

local archp_loaded, archp = pcall(require, "lacord.util.archp")
local dict_to_query = require"http.util".dict_to_query
local expected_args = require"lacord.const".supported_cli_options
local expected_env = require"lacord.const".supported_environment_variables
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
if archp_loaded then
    platform = archp.os

    _ENV.version_major = to_n(archp.lua.major)
    _ENV.version_minor = to_n(archp.lua.minor)
    _ENV.version_release = to_n(archp.lua.release_num)
    _ENV.version = _ENV.version_major + _ENV.version_minor / 10
else
    platform = "generic"
    local mj, mi = _VERSION:match("Lua (%d)%.(%d)")
    _ENV.version_major = to_n(mj)
    _ENV.version_minor = to_n(mi)
    _ENV.version_release = -1
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

function _ENV.set(...)
    local out = pak(...)
    for _ , k in iiter(out) do
        out[k] = true
    end
    return out
end

function map(f, t, ...)
    local out = {}
    for i = 1, #t do
        out[i] = f(t[i], ...)
    end
    return out
end

function map_bang(f, t, ...)
    for i = 1, #t do
        t[i] = f(t[i], ...)
    end

    return t
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
    __lacord_file_description = function(self) return self.description end,
    __lacord_set_file_description = function(self, value) self.description = value end,
}

function plaintext(str, name) return setm({str, name = name}, txt) end


local bin = {
    __lacord_content_type = _ENV.content_types.BYTES,
    __lacord_payload = function(x) return x[1] end,
    __tostring = function(x) return x[1] end,
    __lacord_file_name = function(x) return x.name end,
    __lacord_set_file_name = function(self, value) self.name = value end,
    __lacord_file_description = function(self) return self.description end,
    __lacord_set_file_description = function(self, value) self.description = value end,
}

function binary(str, name) return setm({str, name = name}, bin) end


local virtual_filenames = setm({}, {__mode = "k"})
local virtual_descriptions = setm({}, {__mode = "k"})

local urlencoded_t = {__lacord_content_type = "application/x-www-form-urlencoded"}

function urlencoded_t:__lacord_payload()
    return dict_to_query(self)
end

function urlencoded_t:__lacord_file_name()
    return virtual_filenames[self]
end

function urlencoded_t:__lacord_set_file_name(value)
    virtual_filenames[self] = value
end

function urlencoded_t:__lacord_file_description()
    return virtual_descriptions[self]
end

function urlencoded_t:__lacord_set_file_description(value)
    virtual_descriptions[self] = value
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
    __lacord_file_description = function(self) return self.description end,
    __lacord_set_file_description = function(self, value) self.description = value end,
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
    __lacord_file_description = function(self) return self.description end,
    __lacord_set_file_description = function(self, value) self.description = value end,
}

function json_string(data, name)
    return setm({data, name = name}, json_str)
end


function file_name(cted)
    local mt = getm(cted)
    local curname = mt and mt.__lacord_file_name and mt.__lacord_file_name(cted) or ""

    local base,ext = curname:match"^(.+)(%..+)"
    if not ext then
        if curname:sub(1,1) == "." then
            base = ""
            ext = curname
        else
            base = curname
            local ct = _ENV.the_content_type(cted)
            local lookup = ct and ct:match"^[^;]+"
            if ct and mime.exts[lookup] then
                ext = mime.exts[lookup]
            else
                ext = ""
            end
        end
    end
    return base .. ext, base, ext
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
            __lacord_file_description = function(self) return self.description end,
            __lacord_set_file_description = function(self, value) self.description = value end,
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
    local _, curname, curext = _ENV.file_name(blob)
    if not curname or curname == "" then curname = name or "" end

    local base,ext = curname:match"^(.+)(%..+)"

    if not ext then
        if curname:sub(1,1) == "." then
            base = ""
            ext = curname
        elseif curext then
            base = curname
            ext = curext
        else
            base = curname
            local ct = _ENV.the_content_type(blob)
            local lookup = ct:match"^[^;]+"
            if mime.exts[lookup] then
                ext = mime.exts[lookup]
            else
                ext = ""
            end
        end
    end
    return base .. ext, (_ENV.content_typed(blob))
end

function file_description(cted)
    local mt = getm(cted)
    local desc = mt and mt.__lacord_file_description and mt.__lacord_file_description(cted)
    return desc or "", not not desc
end

function set_file_description(cted, name)
    local mt = getm(cted)
    return mt and mt.__lacord_set_file_description and mt.__lacord_set_file_description(cted, name)
end

function compute_attachments(files)
    local att = { }
    for i, file in iiter(files) do
        local d, was_set = _ENV.file_description(file)
        if was_set then
            insert(att, {
                id = i -1,
                description = d
            })
        end
    end
    return {attachments = att}
end

local function merget(t, other, conflict)
    for k , v in iter(other) do
        local old = t[k]
        if old and conflict then t[k] = conflict(old, v)
        elseif old and typ(old) == "table" and typ(v) == "table" then
            merget(old, v, conflict)
        else t[k] = v
        end
    end
end

_ENV.merge = merget

local positives = {
    yes = true,
    no = false,
    y = true,
    n = false,
    on = true,
    off = false,
    ['true'] = true,
    ['false'] = false,
    ['1'] = true,
    ['0'] = false,
    [0] = false,
    true,
}

local function boolean_environment_variable(value)
    if value ~= nil then
        if typ(value) == "string" then value = value:lower() end
        local flag = positives[value]
        return flag, flag ~= nil
    end
    return nil, false
end

local function value_environment_variable(value)
    return value, value ~= nil
end

local function enum_environment_variable(enum, value)
    if value ~= nil then
        if typ(value) == "string" then value = value:lower() end

        for _, v in iiter(enum) do
            if v == value then return v, true end
        end
    end
    return nil, false
end

local function read_environment_variable(cfg, flagname, ...)
    if typ(cfg[flagname]) == "table" then return enum_environment_variable(cfg[flagname], ...)
    elseif cfg[flagname] == "flag" then return boolean_environment_variable(...)
    else return value_environment_variable(...)
    end
end

local function commandline_item(out, rest)
    local eval = false ::evaluate::
    local key, expecting
    if expected_args[rest] == "flag" then
        out[rest] = true
    elseif expected_args[rest] == "value" then
        key = rest
        expecting = true
    elseif typ(expected_args[rest]) == "table" then
        key = rest
        expecting = 1
    elseif expected_args[expected_args[rest]] and not eval then
        rest = expected_args[rest]
        eval = true
        goto evaluate
    elseif out.accept then
        key = rest
        expecting = true
    end
    return key, expecting
end

local function commandline_args(...)
    local list = pak(...)
    local out = {}
    local expecting = false
    local key
    for i = 1, list.n do
        local item = list[i]
        local f,s = item:byte(1, 2) -- check for double `-`
        if expecting == 1 then
            expecting = false
            list[i] = nil
            for _ , option in iiter(expected_args[key]) do
                if option == item then
                    out[key] = item
                    goto continue
                end
            end
            warn("lacord.util.commandline_args: Unrecognized option passed to --"..key)
        elseif expecting then
           -- if we're expecting an argument then set the current argument as the value
           out[key] = item
           expecting = false
           list[i] = nil
        else -- if this is a new key
            if f == 45 and s == 45 then -- if at least a `-` is found
                list[i] = nil
                                                     -- cut off the -- prefix
                key, expecting = commandline_item(out, char(item:byte(3, -1)))
            elseif f == 45 then
                list[i] = nil
                local chrs = {item:byte(2, -1)}
                for j, c in iiter(chrs) do
                    key, expecting = commandline_item(out, char(c))
                    if expecting then
                        if j ~= #chrs then warn("lacord.util.commandline_args: shorthands which both admit an argument were used, dropping: ".. char(unpak(chrs, j+1))) end
                        break
                    end
                end
            else
                move(list, i, list.n, 1)
                return out, list
            end
        end
        ::continue::
    end
    return out, list
end

function cli_options(...)
    local flags, remaining = commandline_args(...)

    for envname, flagname in iter(expected_env) do
        local value, was_set = read_environment_variable(expected_args, flagname, getenv(envname))
        if was_set then flags[flagname] = flags[flagname] or value end
    end

    pkgloaded['lacord.cli'] = setm(flags, preload['lacord._.cli_metatable'])

    return remaining, flags
end

return _ENV