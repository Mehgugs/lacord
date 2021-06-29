local const = require"lacord.const"
local setm = setmetatable
local req = require

local _ENV = {}

--luacheck: ignore 111

if const.use_cjson then
    local cjson = req"cjson".new()
    cjson.encode_empty_table_as_object(false)
    cjson.decode_array_with_array_mt(true)

    encode = cjson.encode
    decode = cjson.decode
    null = cjson.null
    function jarray(t, ...) return setm(... and {t, ...} or t, cjson.array_mt) end
    function jobject(x) return x end
    empty_array = cjson.empty_array
else
    local dkjson = req"dkjson"
    encode = dkjson.encode
    decode = dkjson.decode
    null = dkjson.null
    function jarray(t, ...) return setm(... and {t, ...} or t, {__jsontype = "array"}) end
    function jobject(x) return setm(x, {__jsontype = "object"}) end
    empty_array = setm({}, {__tojson = function() return "[]" end})
end

return _ENV