local next     = next
local tostring = tostring

local openf = io.open
local time  = os.time

local concat = table.concat
local insert = table.insert

local cli     = require"lacord.cli"
local cqueues = require"cqueues"
local encode  = require"lacord.util.json".encode
local logger  = require"lacord.util.logger"
local util    = require"lacord.util"


local content_typed = util.content_typed
local file_name     = util.file_name
local JSON          = util.content_types.JSON
local LACORD_DEBUG  = cli.debug
local monotime      = cqueues.monotime

local BOUNDARY1 = "lacord" .. ("%x"):format(util.hash(tostring(time())))
local BOUNDARY2 = "--" .. BOUNDARY1
local BOUNDARY3 = BOUNDARY2 .. "--"

local MULTIPART = ("multipart/form-data;boundary=%s"):format(BOUNDARY1)

local with_payload = {
    PUT = true,
    PATCH = true,
    POST = true,
}


local function add_a_file(ret, default_ct, f, i)
    local name = file_name(f)
    local fstr, resolved_ct = content_typed(f)
    insert(ret, BOUNDARY2)
    insert(ret, ("Content-Disposition:form-data;name=\"files[%i]\";filename=%q"):format(i and i-1 or 0, name))
    insert(ret, ("Content-Type:%s\r\n"):format(resolved_ct or default_ct))
    insert(ret, fstr)
end


local empty_file_array = { }

local function attach(payload, files, ct, default_ct)
    local ret
    if ct ~= "form" then
        if payload ~= '{}' then
            ret = {
                BOUNDARY2,
                "Content-Disposition:form-data;name=\"payload_json\"",
                ("Content-Type:%s\r\n"):format(ct),
                payload,
            }
        else
            logger.debug("Not adding empty payload.")
            ret = {}
        end
    else
        ret = {}
        for k, v in pairs(payload) do
            insert(ret, BOUNDARY2)
            local v_, vct = content_typed(v)
            if vct then
                insert(ret, ("Content-Disposition:form-data;name=%q"):format(k))
                insert(ret, ("Content-Type:%s\r\n"):format(vct))
            else
                insert(ret, ("Content-Disposition:form-data;name=%q\r\n"):format(k))
            end
            insert(ret, v_ or tostring(v))
        end
    end
    if #files == 1 then
        add_a_file(ret, default_ct, files[1])
    else
        for i, v in ipairs(files) do
            add_a_file(ret, default_ct, v, i)
        end
    end
    insert(ret, BOUNDARY3)
    return concat(ret, "\r\n")
end

local function attach_files(payload, files, ct)
    return attach(payload, files, ct, util.content_types.BYTES)
end

return function(req, method, name, payload, files)
    if with_payload[method] then
        local content_type
        payload,content_type = content_typed(payload, name)
        if not content_type then
            payload = payload and encode(payload) or '{}'
            content_type = JSON
        end
        if files and next(files) or content_type == "form" then
            payload = attach_files(payload, files or empty_file_array, content_type)
            req.headers:append('content-type', MULTIPART)
        else
            req.headers:append('content-type', content_type)
        end
        if LACORD_DEBUG then
            local file = openf("test/payload" .. util.hash(tostring(monotime())), "wb")
            file:write(payload)
            file:close()
        end
        req:set_body(payload)
    end
end