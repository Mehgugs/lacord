## lacord

lacord is a small discord library providing low level clients for the discord rest and gateway API.
All data is given to the user as raw JSON.

Documentation is sparsely provided in the form of LDoc comments which can be processed into a document using LDoc.

## Contributing

Please do not contribute higher level facilities, you should make a library using this for its low level operations instead.

### The Future

This library will remain mostly static. I plan to trim back the `lacord.util.*` a bit to make it smaller.

## Example

This example sends lines inputed at the terminal to discord over a supplied webhook.

For examples using the gateway see my other project [lacord-client](https://github.com/Mehgugs/lacord-client).

```lua
local api = require"lacord.api"
local cqs = require"cqueues"
local errno = require"cqueues.errno"
local thread = require"cqueues.thread"
local logger = require"lacord.util.logger"
local webhook = os.getenv"WEBHOOK"

local webhook_id, webhook_token = webhook:match"^(.+):(.+)$"

local loop = cqs.new()

local function starts(s, prefix)
    return s:sub(1, #prefix) == prefix
end

local function suffix(s, pre)
    local len = #pre
    return s:sub(1, len) == pre and s:sub(len + 1) or s
end

local thr, con = thread.start(function(con)
    print"Write messages to send over the webhook here!"
    for input in io.stdin:lines() do
        if input == ":quit" then break end
        con:write(input, "\n")
    end
end)

loop:wrap(function()
    local username = "lacord webhook example"
    for line in con:lines() do
        if starts(line, ":") then
            if starts(line, ":username ") then
                username = suffix(line, ":username ")
            end
        else
            local success = api.static:execute_webhook(webhook_id, webhook_token, {
                content = line,
                username = username,
            })
            if not success then io.stdin:write":quit" break end
        end
    end

    local ok, why = thr:join()

    if not ok then logger.error("error in reader thread (%s, %q)", why, errno.strerror(why)) end
end)

assert(loop:loop())
```
