local const = require"lacord.const"
local setm = setmetatable
local req = require
local err = error
local getm = getmetatable

local _ENV = {}

--luacheck: ignore 111

local jo_mt
local ja_mt

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

    ja_mt = cjson.array_mt

    ja_mt.__lacord_content_type = "application/json"
    ja_mt.__lacord_payload = _ENV.encode

    function with_empty_as_object(data)
        return cjson_obj_encoder.encode(data)
    end
else
    local dkjson = req"dkjson"
    encode = dkjson.encode
    decode = dkjson.decode
    null = dkjson.null
    jo_mt = {__jsontype = "object", __lacord_content_type = "application/json", __lacord_payload = _ENV.encode}
    ja_mt = {__jsontype = "array", __lacord_content_type = "application/json", __lacord_payload = _ENV.encode}
    function jarray(t, ...) return setm(... and {t, ...} or t, jo_mt) end
    function jobject(x) return setm(x, ja_mt) end
    empty_array = setm({}, {__tojson = function() return "[]" end})

    function with_empty_as_object(_)
        return err("dkjson does not support switching empty tables to objects, please use json.jobject and then json.encode.")
    end
end

function content_type(obj)
    local mt = getm(obj)

    if mt == jo_mt or mt == ja_mt then return obj, mt end

    if mt and mt.__lacord_content_type then
        return obj, mt
    elseif mt then
        mt.__lacord_content_type = "application/json"
        mt.__lacord_payload = _ENV.encode
        return obj, mt
    else
        local newmt = { __lacord_content_type = "application/json", __lacord_payload = _ENV.encode}
        setm(obj, newmt)
        return obj, newmt
    end
end

return _ENV