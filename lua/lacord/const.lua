
local _ENV = {}
version = "1629838555"
homepage = "https://github.com/Mehgugs/lacord"
time_unit = "seconds"
discord_epoch = 1420070400
gateway_delay = .5
identify_delay = 5
api_version = 9

api = {
    base_endpoint = "https://discord.com/api"
   ,cdn_endpoint = "https://cdn.discordapp.com"
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

use_cjson = true

supported_cli_options = {
    debug = "flag",
    unstable = "flag",
    ['unstable-features'] = "unstable",
    deprecated = "flag",
    client_id = "value",
    client_secret = "value",
    token = "value",
    ['client-id'] = "client_id",
    ['client-secret'] = "client_secret",
}

supported_environment_varibles = {
    LACORD_DEBUG = "debug",
    LACORD_UNSTABLE = "unstable",
    LACORD_DEPRECATED = "deprecated",
    LACORD_ID = "client_id",
    LACORD_SECRET = "client_secret",
    LACORD_TOKEN = "token"
}

return _ENV