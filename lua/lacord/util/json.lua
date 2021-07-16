local const = require"lacord.const"
local setm = setmetatable
local req = require
local err = error

local _ENV = {}

--luacheck: ignore 111

if const.use_cjson then
    local cjson = req"cjson".new()
    cjson.encode_empty_table_as_object(false)
    cjson.decode_array_with_array_mt(true)

    local cjson_obj_encoder = req"cjson".new()
    cjson_obj_encoder.decode_array_with_array_mt(true)
    cjson_obj_encoder.encode_empty_table_as_object(true)

    encode = cjson.encode
    decode = cjson.decode
    null = cjson.null
    function jarray(t, ...) return setm(... and {t, ...} or t, cjson.array_mt) end
    function jobject(x)
        return x
    end
    empty_array = cjson.empty_array

    function with_empty_as_object(data)
        return cjson_obj_encoder.encode(data)
    end
else
    local dkjson = req"dkjson"
    encode = dkjson.encode
    decode = dkjson.decode
    null = dkjson.null
    function jarray(t, ...) return setm(... and {t, ...} or t, {__jsontype = "array"}) end
    function jobject(x) return setm(x, {__jsontype = "object"}) end
    empty_array = setm({}, {__tojson = function() return "[]" end})

    function with_empty_as_object(_)
        return err("dkjson does not support switching empty tables to objects, please use json.jobject and then json.encode.")
    end
end

return _ENV