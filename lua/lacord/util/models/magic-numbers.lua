local iiter = ipairs
local set   = rawset


local function powers_of_two(t)
    local out = {}
    for i , v in iiter(t) do
        local x = 1 << (i-1)
        out[v] = x
        out[x] = v
    end
    return out
end

local function iota(t)
    local out = {}
    for i , v in iiter(t) do
        out[v] = i - 1
        out[i - 1] = v
    end
    return out
end

local function iota1(t)
    local out = {}
    for i , v in iiter(t) do
        out[v] = i
        out[i] = v
    end
    return out
end

local function magic_index(_, k)
    return k
end

return function()
    return
        setmetatable({}, {__index = magic_index}),
        iota,
        powers_of_two,
        iota1
end
