local cqueues = require"cqueues"
local errno = require"cqueues.errno"
local newreq = require"http.request"
local reason = require"http.h1_reason_phrases"
local httputil = require "http.util"
local zlib = require"http.zlib"
local constants = require"lacord.const"
local util = require"lacord.util"
local logger = require"lacord.util.logger"
local api = require"lacord.api"

local LACORD_UNSTABLE = require"lacord.cli".unstable

local inflate = zlib.inflate
local JSON = util.content_types.JSON
local BYTES = util.content_types.BYTES
local a_blob_of = util.a_blob_of
local rand = util.rand
local to_n = tonumber
local setm = setmetatable
local type = type
local to_s = tostring
local to_int = math.tointeger
local iter = pairs

local getlocal = debug and debug.getlocal
local pick     = select

local decode = require"lacord.util.json".decode

local _ENV = {}

local URL = constants.api.cdn_endpoint
local USER_AGENT = api.USER_AGENT


--luacheck: ignore 111 631

local img_exts = {
    jpeg = ".jpg",
    jpg = ".jpg",
    png = ".png",
    webp = ".webp",
    gif = ".gif",
}

local sticker_exts = {
    png = ".png",
    lottie = ".json"
}

sticker_exts[1] = ".png"
sticker_exts[2] = ".png"
sticker_exts[3] = ".json"

local cdn_endpoints = {
    attachment = "/attachments/:channel_id/:attachment_id/:file_name:img_ext",
    custom_emoji = "/emojis/:emoji_id:img_ext",
    guild_icon = "/icons/:guild_id/:guild_icon:img_ext",
    guild_splash = "/splashes/:guild_id/:guild_splash:img_ext",
    guild_discovery_splash = "/discovery-splashes/:guild_id/:guild_discovery_splash:img_ext",
    guild_banner = "/banners/:guild_id/:guild_banner:img_ext",
    default_user_avatar = "/embed/avatars/:user_discriminator:img_ext",
    user_avatar = "/avatars/:user_id/:user_avatar:img_ext",
    application_icon = "/app-icons/:application_id/:icon:img_ext",
    application_cover = "/app-icons/:application_id/:cover_image:img_ext",
    application_asset = "/app-assets/:application_id/:asset_id:img_ext",
    achievement_icon = "/app-assets/:application_id/achievements/:achievement_id/icons/:icon:img_ext",
    sticker_pack_banner = "/app-assets/710982414301790216/store/:sticker_pack_banner_asset_id:img_ext",
    team_icon = "/team-icons/:team_id/:team_icon:img_ext",
    sticker = "/stickers/:sticker_id:sticker_ext",
    role_icon = "role-icons/:role_id/:role_icon:img_ext",
    scheduled_guild_event_cover = "guild-events/:scheduled_event_id/:scheduled_event_cover_image:img_ext"
}

if LACORD_UNSTABLE then
    cdn_endpoints.ephemeral_attachment = "/ephemeral-attachments/:channel_id/:attachment_id/:file_name:img_ext"
end

local cdn = {__name = "lacord.cdn"}

cdn.__index = cdn

function new(options)
    return setm({
        http_version = options and options.http_version or 1.1,
        accept_encoding = options and options.accept_encoding and "gzip, deflate, x-gzip" or nil,
        api_timeout = options and options.api_timeout or nil
    }, cdn)
end

local function resolve_parameters(ep, p)
    return (ep:gsub(":([a-z_]+)", p))
end

function cdn:request(name, url, file_name)
    local req = newreq.new_from_uri(httputil.encodeURI(url))
    req.version = self.http_version

    req.headers:upsert(":method", 'GET')
    req.headers:upsert("user-agent", USER_AGENT)

    if self.accept_encoding then
        req.headers:append("accept-encoding", self.accept_encoding)
    end

    return self:push(name, req, 0, file_name)
end

function cdn:push(name, req, retries, file_name)
    local headers , stream , eno = req:go(self.api_timeout or 10)

    if not headers and retries < constants.api.max_retries then
        local rsec = rand(1, 2)
        logger.warn("%s failed to %s because %q (%s, %q) retrying after %.3fsec",
            self, name, to_s(stream), eno and errno[eno] or "?", eno and errno.strerror(eno) or "??", rsec
        )
        cqueues.sleep(rsec)
        return self:push(name, req, retries+1, file_name)
    elseif not headers and retries >= constants.api.max_retries then
        return nil, errno.strerror(eno)
    end

    local code, rawcode,stat

    stat = headers:get":status"
    rawcode, code = stat, to_n(stat)

    local raw = stream:get_body_as_string()

    if headers:get"content-encoding" == "gzip"
    or headers:get"content-encoding" == "deflate"
    or headers:get"content-encoding" == "x-gzip" then
        raw = inflate()(raw, true)
    end
    if code < 300 then
        return a_blob_of(headers:get"content-type" or BYTES, raw, file_name)
    else
        local data = headers:get"content-type" == JSON and decode(raw) or raw
        local extra
        if type(data) == "table" then
            local msg
            if data.code and data.message then
                msg = ('HTTP Error %i : %s'):format(data.code, data.message)
            else
                msg = 'HTTP Error'
            end
            extra = data.errors
            data = msg
        end
        logger.error("(%i, %q) : %s", code, reason[rawcode], name)
        return nil, data, extra
    end
end

function custom_emoji_url(emoji_id, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.custom_emoji,
            {emoji_id = emoji_id, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return base .. "?size" .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!"))
    else
        return httputil.encodeURI(base)
    end
end

function guild_icon_url(guild_id, guild_icon, ext, size)
   local base = URL ..
        resolve_parameters(cdn_endpoints.guild_icon,
            { guild_id = guild_id, guild_icon = guild_icon, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
       return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
       return httputil.encodeURI(base)
    end
end

function guild_splash_url(guild_id, guild_splash, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.guild_splash,
            { guild_id = guild_id, guild_splash = guild_splash, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function guild_discovery_splash_url(guild_id, guild_discovery_splash, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.guild_discovery_splash,
            { guild_id = guild_id, guild_discovery_splash = guild_discovery_splash, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function guild_banner_url(guild_id, guild_banner, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.guild_banner,
            { guild_id = guild_id, guild_banner = guild_banner, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function default_user_avatar_url(user_discriminator, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.default_user_avatar,
            { user_discriminator = user_discriminator, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function user_avatar_url(user_id, user_avatar, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.user_avatar,
            { user_id = user_id, user_avatar = user_avatar, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function application_icon_url(application_id, icon, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.application_icon,
            { application_id = application_id, icon = icon, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function application_cover_url(application_id, cover_image, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.application_cover,
            { application_id = application_id, cover_image = cover_image, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function application_asset_url(application_id, asset_id, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.applicaion_asset,
            { application_id = application_id, asset_id = asset_id, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function achievement_icon_url(application_id, achievement_id, icon, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.achievement_icon,
            { application_id = application_id, achievement_id = achievement_id, icon = icon, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function sticker_pack_banner_url(sticker_pack_banner_asset_id, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.sticker_pack_banner,
            { sticker_pack_banner_asset_id = sticker_pack_banner_asset_id, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function team_icon_url(team_id, team_icon, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.team_icon,
            { team_id = team_id, team_icon = team_icon, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function sticker_url(sticker_id, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.sticker,
            { sticker_id = sticker_id, sticker_ext = logger.assert(sticker_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function attachment_url(channel_id, attachment_id, file_name, ext, size)
    ext = img_exts[ext] or ext or '' if ext ~= "" and ext:byte() ~= 46 then ext = "." .. ext end
    local base = URL ..
        resolve_parameters(cdn_endpoints.attachment,
            { channel_id = channel_id, attachment_id = attachment_id, file_name = file_name, img_ext = img_exts[ext] or ext})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function role_icon_url(role_id, role_icon, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.role_icon,
            { role_id = role_id, role_icon = role_icon, img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

function scheduled_guild_event_cover_url(scheduled_event_id, scheduled_event_cover_image, ext, size)
    local base = URL ..
        resolve_parameters(cdn_endpoints.scheduled_guild_event_cover,
            { scheduled_event_id = scheduled_event_id, scheduled_event_cover_image = scheduled_event_cover_image,
                img_ext = logger.assert(img_exts[ext], "Image extension %s not supported!", ext)})
    if size then
        return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
    else
        return httputil.encodeURI(base)
    end
end

if LACORD_UNSTABLE then
    function ephemeral_attachment_url(channel_id, attachment_id, file_name, ext, size)
        ext = img_exts[ext] or ext or '' if ext ~= "" and ext:byte() ~= 46 then ext = "." .. ext end
        local base = URL ..
            resolve_parameters(cdn_endpoints.attachment,
                { channel_id = channel_id, attachment_id = attachment_id, file_name = file_name, img_ext = ext})
        if size then
            return httputil.encodeURI(base .. '?size' .. to_s(logger.assert(to_int(size), "Must provide an integer size which is a power of 2!")))
        else
            return httputil.encodeURI(base)
        end
    end
end

for k in iter(cdn_endpoints) do
    local the_url = _ENV[k .. "_url"]
    if not the_url then logger.fatal("cdn[get_%s] has no url function.", k) end
    local has_file
    local the_method
    if getlocal then
        for i = 1, 5 do
            local param_name = getlocal(the_url, i)
            if param_name == 'file_name' then has_file = i
            elseif param_name == nil then break
            end
        end
    end

    if has_file then
        function the_method(self, ...)
            return self:request(k, the_url(...), (pick(has_file, ...)))
        end
    else
        function the_method(self, ...)
            return self:request(k, the_url(...))
        end
    end
    cdn['get_'..k] = the_method
end

function cdn:fetch(...)
    return self:request("generic-file-request", ...)
end

return _ENV