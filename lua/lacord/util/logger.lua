local insert, unpack = table.insert, table.unpack
local f = string.format
local date, exit = os.date, os.exit
local tonumber = tonumber
local _stdout, _stderr = io.stdout, io.stderr
local err = error

local LACORD_DEBUG = os.getenv"LACORD_DEBUG"

local _ENV = {}

--luacheck: ignore 111

stdout = _stdout
stderr = _stderr

local _mode = 0

--- An optional lua file object to write output to, must be opened in a write mode.
fd = nil

local function parseHex(c)
    if c:sub(1,1) == '#' then c = c:sub(2) end
    if c:sub(1,2) == '0x' then c = c:sub(3) end
    local len = #c
    if not (len == 3 or len == 6) then
        c = len > 6 and c:sub(1,6) or c .. ("0"):rep(6 - len)
    elseif len == 3 then
        c = c:gsub("(.)", "%1%1")
    end
    local out = {}
    for i = 1,6,2 do
        insert(out, tonumber(c:sub(i,i+1), 16))
    end
    return unpack(out, 1, 3)
end

local function color_code_to_seq(body)
    local r,g,b = body:match("(%d+),(%d+),(%d+)")
    if r and g and b then
        return ('\27[0m\27[38;2;%s;%s;%sm'):format(r,g,b)
    else
        r,g,b = parseHex(body)
        return r and g and b and ('\27[0m\27[38;2;%s;%s;%sm'):format(r,g,b) or ''
    end
end

local function highlight_code_to_seq(body)
    local body1, body2 = body:match("highlight:([^:]+):([^:]+)")
    local rb,gb,bb = parseHex(body1)
    local rf,gf,bf = parseHex(body2)
    return rb and gb and bb and rf and gf and bf and ('\27[0m\27[48;2;%s;%s;%sm\27[38;2;%s;%s;%sm'):format(rb,gb,bb,rf,gf,bf) or ''
end

local colors = {}

colors[0] = {
    info  = ""
    ,warn  = ""
    ,error = ""
    ,white = ""
    ,debug = ""
    ,info_highlight  = ""
    ,warn_highlight  = ""
    ,error_highlight = ""
    ,debug_highlight = ""
}

colors[24] = {
    info  = color_code_to_seq"#1a6"
   ,warn  = color_code_to_seq"#ef5"
   ,error = color_code_to_seq"#f14"
   ,white = color_code_to_seq"#fff"
   ,debug = color_code_to_seq"#0ff"
   ,info_highlight  = highlight_code_to_seq"highlight:#1a6:#000"
   ,warn_highlight  = highlight_code_to_seq"highlight:#ef5:#000"
   ,error_highlight = highlight_code_to_seq"highlight:#f14:#000"
   ,debug_highlight = highlight_code_to_seq"highlight:#0ff:#000"
}

colors[3] = {
     info  = "\27[0m\27[32m"
    ,warn  = "\27[0m\27[33m"
    ,error = "\27[0m\27[31m"
    ,white = "\27[0m\27[1;37m"
    ,debug = "\27[0m\27[1;36m"
    ,info_highlight  = "\27[0m\27[1;92m"
    ,warn_highlight  = "\27[0m\27[1;93m"
    ,error_highlight = "\27[0m\27[1;91m"
    ,debug_highlight = "\27[0m\27[1;96m"
}

colors[8] = {
     info  = "\27[0m\27[38;5;36m"
    ,warn  = "\27[0m\27[38;5;220m"
    ,error = "\27[0m\27[38;5;196m"
    ,white = "\27[0m\27[38;5;231m"
    ,info_highlight  = "\27[0m\27[38;5;48m"
    ,warn_highlight  = "\27[0m\27[38;5;11m"
    ,error_highlight = "\27[0m\27[38;5;9m"
    ,debug = "\27[0m\27[38;5;105m"
    ,debug_highlight = "\27[0m\27[38;5;123m"
}

local function paint(str)
    return str:gsub("($([^;]+);)", function(_, body)
        if body == 'reset' then
            return '\27[0m'
        elseif colors[_mode][body] then
            return colors[_mode][body]
        elseif _mode == 24 and body:sub(1,9) == "highlight" then
            return highlight_code_to_seq(body)
        elseif _mode == 24 then
            return color_code_to_seq(body)
        end
    end)
end

_ENV.paint = paint

local function writef(ifd,...)
    local raw = f(...)
    local str,n = paint(raw)
    if _ENV.fd then
        _ENV.fd:write(raw:gsub("$[^;]+;", ""), "\n")
    end
    if ifd then
        ifd:write(str, n > 0 and "\27[0m\n" or "\n")
    end
end

--- Logs to stdout, and the output file if set, using the INF info channel.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
function info(...)
    return writef(_ENV.stdout, "$info_highlight; %s INF $info; %s", date"!%c", f(...))
end

if LACORD_DEBUG then
    function _ENV.debug(...)
        return writef(_ENV.stdout, "$debug_highlight; %s DBG $debug; %s", date"!%c", f(...))
    end
else
    function _ENV.debug()
    end
end


--- Logs to stdout, and the output file if set, using the WRN warning channel.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
function warn(...)
    return writef(_ENV.stdout, "$warn_highlight; %s WRN $warn; %s", date"!%c", f(...))
end

--- Logs to stderr, and the output file if set, using the ERR error channel.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
function error(...)
    return writef(_ENV.stderr, "$error_highlight; %s ERR $error; %s", date"!%c", f(...))
end

--- Logs an error using `logger.error` and then throws a lua error with the same message.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
function throw(...)
    error(...)
    return err(f(...), 2)
end

--- Logs an error using `logger.error` and then exits with a non-zero exit code.
-- @string str A format string.
-- @param[opt] ... Values passed into `string.format`.
function fatal(...)
    error(...)
    error"Fatal error: quitting!"
    return exit(1, true)
end

--- Similar to lua's assert but uses logger.throw when an assertion fails.
function _ENV.assert(v, ...)
    if v then return v
    else return _ENV.throw(...)
    end
end

function ferror(...) return err(f(...), 2) end

--- Logs to stdout, and the output file if set.
-- @string str A format string.
-- @param[opt] ... Values passed into `string.format`.
function printf(...) return writef(_ENV.stdout, ...) end

local modes = {
    [0] = true,
    [3] = true,
    [8] = true,
    [24] = true
}

--- Change color mode for writing to stdout.
-- You can use:
-- - `3` for `3/4 bit color`
-- - `8` for `8 bit color`
-- - `24` for `24 bit true color`.
-- Setting it to `0` disables coloured output.
-- @tparam number m The mode.
function mode(m)
    m = m or 0
    _mode = modes[m] and m or 0
    return _mode
end

return _ENV