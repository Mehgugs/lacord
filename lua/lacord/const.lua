
local _ENV = {}
version = "1617477179"
homepage = "https://github.com/Mehgugs/lacord"
time_unit = "seconds"
discord_epoch = 1420070400
gateway_delay = .5
identify_delay = 5
api_version = 8

api = {
    base_endpoint = "https://discord.com/api"
   ,avatar_endpoint = "https://cdn.discordapp.com/avatars/%u/%s.%s"
   ,default_avatar_endpoint = "https://cdn.discordapp.com/embed/avatars/%s.png"
   ,emoji_endpoint = "https://cdn.discordapp.com/emojis/%s.%s"
   ,icon_endpoint = "https://cdn.discordapp.com/icons/%s/%s.png"
   ,splash_endpoint = "https://cdn.discordapp.com/splashs/%s/%s.png"
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