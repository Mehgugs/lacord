
local _ENV = {}
version = "1619975269"
homepage = "https://github.com/Mehgugs/lacord"
time_unit = "seconds"
discord_epoch = 1420070400
gateway_delay = .5
identify_delay = 5
api_version = 8

api = {
    base_endpoint = "https://discord.com/api"
   ,avatar_endpoint = "https://cdn.discordapp.com/avatars"
   ,default_avatar_endpoint = "https://cdn.discordapp.com/embed/avatars"
   ,emoji_endpoint = "https://cdn.discordapp.com/emojis"
   ,icon_endpoint = "https://cdn.discordapp.com/icons"
   ,splash_endpoint = "https://cdn.discordapp.com/splashs"
   ,version = api_version
   ,max_retries = 6
}

gateway = {
    delay = .5
   ,identify_delay = 5
   ,version = api_version
   ,encoding = "json"
   ,compress = "zlib-stream"
}

api.endpoint = ("%s/v%s"):format(api.base_endpoint, api.version)

default_avatars = 5


return _ENV