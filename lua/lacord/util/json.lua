local const = require"lacord.const"
local setm = setmetatable
local req = require
local err = error
local getm = getmetatable

local REG = debug.getregistry()

local _ENV = {}

--luacheck: ignore 111

local virtual_filenames = setm({}, {__mode = "k"})
local virtual_descriptions = setm({}, {__mode = "k"})

local function virtualname(self) return virtual_filenames[self] end
local function set_virtualname(self, value) virtual_filenames[self] = value end

local function virtualdescription(self) return virtual_descriptions[self] end
local function set_virtualdescription(self, value) virtual_descriptions[self] = value end

local function initialize_metatables(ja_mt, jo_mt, enc)
    ja_mt.__lacord_content_type = "application/json"
    ja_mt.__lacord_payload = enc
    ja_mt.__lacord_file_name = virtualname
    ja_mt.__lacord_set_file_name = set_virtualname
    ja_mt.__lacord_file_description = virtualdescription
    ja_mt.__lacord_set_file_description = set_virtualdescription

    jo_mt.__lacord_content_type = "application/json"
    jo_mt.__lacord_payload = enc
    jo_mt.__lacord_file_name = virtualname
    jo_mt.__lacord_set_file_name = set_virtualname
    jo_mt.__lacord_file_description = virtualdescription
    jo_mt.__lacord_set_file_description = set_virtualdescription
end

local jo_mt
local ja_mt


if const.json_provider == "cjson" then
    local cjson = req"cjson".new()
    cjson.encode_empty_table_as_object(false)
    cjson.decode_array_with_array_mt(true)

    local cjson_obj_encoder = req"cjson".new()
    cjson_obj_encoder.decode_array_with_array_mt(true)
    cjson_obj_encoder.encode_empty_table_as_object(true)

    encode = cjson.encode
    decode = cjson.decode
    null = cjson.null


    ja_mt = cjson.array_mt
    jo_mt = {}

    function jarray(t, ...) return setm(... and {t, ...} or t, cjson.array_mt) end
    function jobject(x)
        return x
    end

    initialize_metatables(ja_mt, jo_mt, encode)


    empty_array = cjson.empty_array

    function with_empty_as_object(v)
        return cjson_obj_encoder.encode(v)
    end
elseif const.json_provider == "rapidjson" then
    local rapidjson = req"rapidjson"

    local empty_table_as_array = {empty_table_as_array = true}

    function encode(v)
        return rapidjson.encode(v, empty_table_as_array)
    end

    decode = rapidjson.decode

    null = rapidjson.null


    ja_mt = REG['json.array']
    jo_mt = REG['json.object']

    function jarray(t, ...) return setm(... and {t, ...} or t, ja_mt) end
    function jobject(x) return setm(x, jo_mt) end

    initialize_metatables(ja_mt, jo_mt, encode)


    empty_array = setm({}, ja_mt)

    function with_empty_as_object(v)
        return rapidjson.encode(v)
    end
elseif const.json_provider == "dkjson" then
    local dkjson = req"dkjson"

    encode = dkjson.encode
    decode = dkjson.decode
    null = dkjson.null


    jo_mt = {__jsontype = "object"}
    ja_mt = {__jsontype = "array"}

    function jarray(t, ...) return setm(... and {t, ...} or t, ja_mt) end
    function jobject(x) return setm(x, jo_mt) end

    initialize_metatables(ja_mt, jo_mt, encode)


    empty_array = setm({}, {__tojson = function() return "[]" end})

    function with_empty_as_object(_)
        return err("dkjson does not support switching empty tables to objects, please use json.jobject and then json.encode.")
    end
end

local newmt = {
    __lacord_content_type = "application/json",
    __lacord_payload = _ENV.encode,
    __lacord_file_name = virtualname,
    __lacord_set_file_name = set_virtualname,
    __lacord_file_description = virtualdescription,
    __lacord_set_file_description = set_virtualdescription,

}

function content_type(obj)
    local mt = getm(obj)

    if mt == jo_mt or mt == ja_mt then return obj, mt end

    if mt and mt.__lacord_content_type then
        return obj, mt
    elseif mt then
        mt.__lacord_content_type = "application/json"
        mt.__lacord_payload = _ENV.encode
        mt.__lacord_file_name = virtualname
        mt.__lacord_set_file_name = set_virtualname
        mt.__lacord_file_description = virtualdescription
        mt.__lacord_set_file_description = set_virtualdescription
        return obj, mt
    else
        setm(obj, newmt)
        return obj, newmt
    end
end

return _ENV