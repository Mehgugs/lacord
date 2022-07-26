
local _ENV = {}
version = "1637789515"
homepage = "https://github.com/Mehgugs/lacord"
time_unit = "seconds"
discord_epoch = 1420070400
gateway_delay = .5
identify_delay = 5
api_version = 10

api = {
    base_endpoint = "https://discord.com/api"
   ,cdn_endpoint = "https://cdn.discordapp.com"
   ,version = api_version
   ,max_retries = 6
}

gateway = {
    delay = .5
   ,identify_delay = 5
   ,ratelimit = {120, 60}
   ,allowance = 2
   ,version = api_version
   ,encoding = "json"
   ,compress = "zlib-stream"
}

api.endpoint = ("%s/v%s"):format(api.base_endpoint, api.version)

default_avatars = 5

json_provider = "cjson"

supported_cli_options = {
    debug = "flag",
    unstable = "flag",
    deprecated = "flag",
    client_id = "value",
    client_secret = "value",
    token = "value",
    log_file = "value",
    log_mode = {"0","3","8"},
    accept = "flag",
    ['unstable-features'] = "unstable",
    ['client-id'] = "client_id",
    ['client-secret'] = "client_secret",
    ['log-file'] = "log_file",
    ['log-mode'] = "log_mode",
    ['accept-everything'] = "accept",
    ['quiet'] = "flag",
    ['quieter'] = "quiet",
    ['file'] = "value",
    --shorthand
    d = "debug",
    u = "unstable",
    D = "deprecated",
    i = "client_id",
    s = "client_secret",
    t = "token",
    l = "log_file",
    L = "log_mode",
    a = "accept",
    q = "quiet",
    f = "file"
}

supported_environment_variables = {
    LACORD_DEBUG = "debug",
    LACORD_UNSTABLE = "unstable",
    LACORD_DEPRECATED = "deprecated",
    LACORD_ID = "client_id",
    LACORD_SECRET = "client_secret",
    LACORD_TOKEN = "token",
    LACORD_LOG_MODE = "log_mode",
    LACORD_LOG_FILE = "log_file",
    LACORD_QUIET = "quiet"
}

return _ENV