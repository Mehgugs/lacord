
local const = {}
const.version = "1637789515"
const.homepage = "https://github.com/Mehgugs/lacord"
const.time_unit = "seconds"
const.discord_epoch = 1420070400
const.gateway_delay = .5
const.identify_delay = 5
const.api_version = 10

const.api = {
    base_endpoint = "https://discord.com/api"
   ,cdn_endpoint = "https://cdn.discordapp.com"
   ,version = const.api_version
   ,max_retries = 6
}

const.gateway = {
    delay = .5
   ,identify_delay = 5
   ,version = const.api_version
   ,encoding = "json"
   ,compress = "zlib-stream"
}

const.api.endpoint = ("%s/v%s"):format(const.api.base_endpoint, const.api.version)

const.default_avatars = 5

const.use_cjson = true

const.supported_cli_options = {
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
}

const.supported_environment_variables = {
    LACORD_DEBUG = "debug",
    LACORD_UNSTABLE = "unstable",
    LACORD_DEPRECATED = "deprecated",
    LACORD_ID = "client_id",
    LACORD_SECRET = "client_secret",
    LACORD_TOKEN = "token",
    LACORD_LOG_MODE = "log_mode",
    LACORD_LOG_FILE = "log_file"
}

return const