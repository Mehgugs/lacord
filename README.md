## lacord

lacord is a small discord library providing low level clients for the discord rest and gateway API.
All data is given to the user as raw JSON.

Documentation is sparsely provided in the form of LDoc comments which can be processed into a document using LDoc.

### The Future

Currently the low level interfaces for slash commands are being implemented.

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

local discord = api.webhook_init(webhook_token)

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
            local success = discord:execute_webhook(webhook_id, {
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

## Installation

This project depends on [`lua-http`](https://github.com/daurnimator/lua-http) and thus [`cqueues`](https://25thandclement.com/~william/projects/cqueues.html). This means that you must
be able to install `cqueues` on your platform.

You can consult the respective projects for
detailed instructions but as a general guide the following tools/libraries should be installed and available on your system:

- m4
- awk
- zlib-dev
- libssl-dev (or equiv.)[¹](#note1)

Once you have the pre-requisites in order you can install this library with luarocks:

- Directly `luarocks install lacord`
- Via this repository
    - `git clone https://github.com/Mehgugs/lacord.git && cd lacord`
    - *optionally checkout a specific commit*
    - `luarocks make`

NB. In these example I have shown installs to the global rocktree, this may need `sudo` permission on your system.
Luarocks can install and build modules to a local rocktree with some simple configuration.

## Slash Commands

This library provides support for slash commands naturally over the gateway and
also provides a https server module under `lacord.outoing-webhook-server` for interfacing
with discord over outgoing webhook. When using this method there are a collection of things to keep in mind:

- You must use TLS. By default this module accepts two file paths after the server options table.
  The first one should be your full certificate chain in pem format and the second should be your private key in pem format.
  Should you wish to do more advanced TLS configuration, you can attach a ctx object to the options under `.ctx`.

- The first argument, the options table, is passed to `http.server.listen`. So please refer to the http library docs
  for a full list of network options. Some fields, such as `tls` will be filled in for you.
  In addition to the `http` library's fields, the following are expected:
    - The string field `route` is the path component of the URL you configure your application to use.
      In the URL `https://example.com/interactions` this would be `/interactions`.
    - The function field `interact` is called when a discord interaction event is received by the webhook.
      The first argument is the json object payload discord sent, the next argument is the https response object.
      Return a valid json object from the function to send it to discord; if you do not it will respond with 500.
      Any error in this function is caught and will respond with 503, logging the message internally.
    - The function field `fallthrough` receives a response object, and is called with any other request (i.e requests to paths other than the `route`).
    - The string field `public_key` is your applications public key, necessary for signature verification.

Here is a minimal example of configuration:

```lua
local server = require"lacord.outgoing-webhook-server"

local function interact(event, resp)
    if event.data.command == "hello" then
        return {
            type = 4,
            data = {
                content = "Hello, world!"
            }
        }
    else
        resp:set_code_and_reply(404, "Command not found.", "text/plain; charset=UTF-8")
    end
end

local loop = server.new({
    public_key = os.getenv"PUBLIC_KEY",
    fallthrough = function(resp) resp:set_code_and_reply(404, "Page not found.", "text/plain; charset=UTF-8") end,
    interact = interact,
    host = "localhost",
    port = 8888,
    route = "/interactions"
}, "fullchain.pem", "key.pem")


assert(loop:loop())
```

The `loop` object has `.cq` field which can be used to `:wrap` asynchronous code.

## Notes

#### Note 1
I would recommend manually installing openssl with a version in the current stable series.
At the time of writing this is the **1.1.1** series.