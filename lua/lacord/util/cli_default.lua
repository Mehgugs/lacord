local iiter  = ipairs
local iter   = pairs
local loads  = load
local setm   = setmetatable
local to_n   = tonumber
local try    = pcall
local typ    = type
local warn   = warn or function()end

local openf  = io.open

local getenv = os.getenv

local pkgloaded= package.loaded

local char     = string.char

local move   = table.move
local pak    = table.pack
local unpak  = table.unpack

local expected_args = require"lacord.const".supported_cli_options
local expected_env = require"lacord.const".supported_environment_variables

local climt = {__name = "lacord.cli"}

local positives = {
    yes = true,
    no = false,
    y = true,
    n = false,
    on = true,
    off = false,
    ['true'] = true,
    [true] = true,
    [false] = false,
    ['false'] = false,
    ['1'] = true,
    ['0'] = false,
    [1] = true,
    [0] = false,
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

local function cli_options_from_table(tbl)
    local out = {}
    local expecting = false
    local key

    for _ , item in iiter(tbl) do
        if expecting == 1 then
            expecting = false
            for _ , option in iiter(expected_args[key]) do
                if option == item then
                    out[key] = item
                    goto continue
                end
            end
            warn("lacord.util.commandline_args: Unrecognized option passed to --"..key)
        elseif expecting then
            out[key] = item
            expecting = false
        else
            key, expecting = commandline_item(out, item)
        end
        ::continue::
    end

    for k, v in iter(tbl) do
        if not to_n(k) then
            k, expecting = commandline_item(out, k)
            if not k then goto continue end

            if expecting == 1 then
                out[k] = enum_environment_variable(expected_args[k], v)
            elseif expecting then
                out[k] = value_environment_variable(v)
            else
                out[k] = boolean_environment_variable(v)
            end
            ::continue::
        end
    end
    return out
end


local file_env_mt = {}

function file_env_mt.__index(_, k)
    return k
end

function file_env_mt.__newindex() end

local file_env = setm({}, file_env_mt)


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
            if key == "file" then
                local file = openf(item, "r")
                if file then
                    local content = file:read"a"
                    file:close()
                    if not content then goto file_fail end

                    local success, loader, t = try(loads, "return "..content, "lacord.cli.options", "t", file_env)
                    if not success then goto file_fail end

                    success,t = try(loader)

                    if not success then goto file_fail end
                    list[i] = nil
                    move(list, i+1, list.n, 1)
                    return cli_options_from_table(t), list
                end
                ::file_fail::
                warn("lacord.util.commandline_args: Error loading arguments from file "..item)
                expecting = false
                list[i] = nil
            else
                out[key] = item
                expecting = false
                list[i] = nil
           end
        else -- if this is a new key
            if f == 45 and s == 45 then -- if at least a `-` is found
                list[i] = nil
                key, expecting = commandline_item(out, char(item:byte(3, -1))) -- cut off the -- prefix
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

local function cli_options(...)
    local flags, remaining = commandline_args(...)

    for envname, flagname in iter(expected_env) do
        local value, was_set = read_environment_variable(expected_args, flagname, getenv(envname))
        if was_set then flags[flagname] = flags[flagname] or value end
    end


    pkgloaded['lacord.cli'] = setm(flags, climt)

    return remaining, flags
end



function climt.__call(_,...)
    return cli_options(...)
end

return setmetatable({}, climt)