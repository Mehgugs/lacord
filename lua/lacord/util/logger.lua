local f = string.format
local date, exit = os.date, os.exit
local _stdout, _stderr = io.stdout, io.stderr
local openf = io.open
local to_n = tonumber
local err = error

local cli = require"lacord.cli"
local LACORD_DEBUG = cli.debug
local LACORD_LOG_MODE = cli.log_mode
local LACORD_LOG_FILE = cli.log_file

local M = {}

M.stdout = _stdout
M.stderr = _stderr

local _mode = 0

--- An optional lua file object to write output to, must be opened in a write mode.

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

local function quick_highlight(c, body, last, level)
    if level and c[level .. '_highlight'] then return c[level .. '_highlight'] .. body .. last
    else return c.white .. body .. last
    end
end

local highlighters = { }
local function paint(str, level)
    if not highlighters[level] then
        local function highlighter(body)
            return quick_highlight(colors[_mode], body, "\27[0m", level)
        end
        highlighters[level] = highlighter
        return str:gsub("$([^;]+);", highlighter)
    else
        return str:gsub("$([^;]+);", highlighters[level])
    end
end

local function unpaint(str) return (str:gsub("$([^;]+);", "%1")) end

local function check_fd(s, msg, code)
    if not s then
        M.fd = nil
        M.warn("removed $logger.fd; because $(%q, %#x);.", msg , code)
        return false
    end
    return true
end

local fmts = { }

local function writef(ifd, level, content)
    local timestamp = date"!%c"
    if M.fd then
        if check_fd(M.fd:write(timestamp, " ")) then
            if level then
                if not check_fd(M.fd:write(fmts[level], " ")) then goto finished end
            end
            check_fd(M.fd:write(content, "\n"))
            ::finished::
        end
    end
    if ifd then
        local str = paint(content, level)
        ifd:write(
            colors[_mode][level or 'white'],
            timestamp, " "
        )
        if level then ifd:write(colors[_mode][level .. "_highlight"], fmts[level], " ")
        else ifd:write("LOG", " ") end
        ifd:write(
            "\27[0m", str, "\27[0m\n"
        )
    end
end



--- Logs to stdout, and the output file if set, using the INF info channel.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
fmts.info = "INF"
function M.info(...)
    return writef(M.stdout, 'info', f(...))
end

fmts.debug = "DBG"

if LACORD_DEBUG then
    function M.debug(...)
        return writef(M.stdout, 'debug', f(...))
    end
else
    function M.debug()
    end
end


--- Logs to stdout, and the output file if set, using the WRN warning channel.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
fmts.warn = "WRN"
function M.warn(...)
    return writef(M.stdout, 'warn', f(...))
end

--- Logs to stderr, and the output file if set, using the ERR error channel.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
fmts.error = "ERR"
function M.error(...)
    return writef(M.stderr, 'error', f(...))
end

--- Logs an error using `logger.error` and then throws a lua error with the same message.
-- @string str A format string
-- @param[opt] ... Values passed into `string.format`.
function M.throw(...)
    local content = f(...)
    writef(M.stderr, 'error', content)
    return err(unpaint(content), 2)
end

--- Logs an error using `logger.error` and then exits with a non-zero exit code.
-- @string str A format string.
-- @param[opt] ... Values passed into `string.format`.
function M.fatal(...)
    error(...)
    error"Fatal error: quitting!"
    return exit(1, true)
end

--- Similar to lua's assert but uses logger.throw when an assertion fails.
function M.assert(v, ...)
    if v then return v
    else return M.throw(...)
    end
end

function M.ferror(...) return err(f(...), 2) end

--- Logs to stdout, and the output file if set.
-- @string str A format string.
-- @param[opt] ... Values passed into `string.format`.
function M.printf(...) return writef(M.stdout, nil, f(...)) end

local modes = {
    [0] = true,
    [3] = true,
    [8] = true
}

--- Change color mode for writing to stdout.
-- You can use:
-- - `3` for `3/4 bit color`
-- - `8` for `8 bit color`
-- - `24` for `24 bit true color`.
-- Setting it to `0` disables coloured output.
-- @tparam number m The mode.
function M.mode(m)
    m = m or 0
    _mode = modes[m] and m or 0
    return _mode
end

if LACORD_LOG_FILE then
    M.fd = openf(LACORD_LOG_FILE, "a")
end

if LACORD_LOG_MODE then
    M.mode(to_n(LACORD_LOG_MODE))
end

return M