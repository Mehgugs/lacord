## lacord

lacord is a small discord library providing low level clients for the discord rest and gateway API.
All data is given to the user as raw JSON.

Documentation is sparsely provided in the form of LDoc comments which can be processed into a document using LDoc.

## Contributing

Please do not contribute higher level facilities, you should make a library using this for its low level operations instead.

### The Future

This library will remain mostly static. I plan to trim back the `lacord.util.*` a bit to make it smaller.

## Example

```lua
local cqs = require"cqueues"
local api = require"lacord.api"
local shard = require"lacord.shard"
local logger = require"lacord.util.logger"
local util = require"lacord.util"
local mutex = require"lacord.util.mutex"

logger.mode(8) -- nice colours!
util.capturable(api) -- makes running a series of api requests that depend on each other easier

-- good error handling
local old_wrap do
    local traceback = debug.traceback
    old_wrap = cqs.interpose('wrap', function(self, ...)
        return old_wrap(self, function(fn, ...)
            local s, e = xpcall(fn, traceback, ...)
            if not s then
                logger.error(e)
            end
        end, ...)
    end)
end

local discord_api = api.init{
     token = "Bot "..os.getenv"TOKEN"
    ,precision = "millisecond"
    ,accept_encoding = true
}

local loop = cqs.new() -- continuation queue for our shard + api.
local output -- dispatch function
loop:wrap(function()
    local R = discord_api
        :capture(discord_api:get_gateway_bot())
        :get_current_application_information()

    if R.success then
        local gateway, app = R:results()
        output = output(app)
        local limit = gateway.session_start_limit
        if limit then
            logger.info("TOKEN-%s has used %d/%d sessions.",
                util.hash(discord_api.token),
                limit.total - limit.remaining,
                limit.total)
        else
            util.fatal("Failed to retrieve valid information from GET /gateway/bot $white;%s$error;", write(data))
        end
        if limit.remaining > 0 then
            local s = shard.init({
                token = discord_api.token
               ,id = 0
               ,gateway = gateway.url
               ,compress = false
               ,transport_compression = true
               ,total_shard_count = 1
               ,large_threshold = 100
               ,auto_reconnect = true
               ,loop = cqs.running()
               ,output = output
           }, mutex.new())
           s:connect()
        end
    else
        logger.error(R.error)
    end
end)

function output(app)
    return function(_, event, data)
        logger.info("received %s", event)
        if event == 'MESSAGE_CREATE' and data.content == "!ping" then
            for i = 1, 10 do
                discord_api:create_message(data.channel_id, {content = "pong!"..i})
            end
        end
    end
end

loop:loop()
```
