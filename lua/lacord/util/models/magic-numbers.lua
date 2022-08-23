local iter  = pairs
local iiter = ipairs
local getm  = getmetatable
local set   = rawset
local setm  = setmetatable

local bound = {}
local enum  = {__name = "lacord.models.enum"}

local function check_bound(v, out)
    if getm(v) == bound then
        out.__boundary = out.__boundary or {}
        out.__boundary[v[2]] = v[1]
        return v[1]
    else return v
    end
end

local function resolve_bound(t)
    if t.__boundary then
        for name, field in iter(t.__boundary) do
            t[name] = t[field] + .5
        end
        t.__boundary = nil
    end
    return setm(t, enum)
end

local function powers_of_two(t)
    local out = {}
    for i , v in iiter(t) do
        v = check_bound(v, out)
        out[v] = 1 << (i-1)
    end
    return resolve_bound(out)
end

local function iota(t)
    local out = {}
    for i , v in iiter(t) do
        v = check_bound(v, out)
        out[v] = i - 1
    end
    return resolve_bound(out)
end

local function iota1(t)
    local out = {}
    for i , v in iiter(t) do
        v = check_bound(v, out)
        out[v] = i
    end
    return resolve_bound(out)
end

local function boundary(name, field)
    return setm({field, name}, bound)
end

local function magic_index(_, k)
    return k
end

local function magic_newindex(t, k, v)
    set(t, k, v)
    set(t, k..'s', v)
    if getm(v) == enum then
        local out = {} for k_ , v_ in iter(v) do
            if k_ == '__boundary' then goto continue end
            out[v_] = k_
            ::continue::
        end
        set(t, k..'_names', out)
    end
end

return function()
    return
        setmetatable({}, {__index = magic_index, __newindex = magic_newindex}),
        iota,
        powers_of_two,
        iota1,
        boundary
end
