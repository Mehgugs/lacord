## lacord.util.session-limit

This module provides an object to control concurrent shards identifying.

### If you're wanting to run shards across multiple processes/threads please open an issue/ticket.

### *session-limit*

This type is a semaphore-like object which can be used to orchestrate shard connection.
The `:enter()` method is called when you prepare a shard. When the limit is used up
-- and we've started `availability` requests concurrently -- `:enter()` will block until we're allowed to connect. Every call to `:enter()` is met with a call to `:exit()` when the shard receives a `READY` event from discord. Note that the shard implementation will call these methods as appropriate, you need only create this object.

### Example taken from `lacord-client`

In this example `self` is the client (which is a table of shards and other bot related components).
When the client connects we pass its `.session_limit`. This object is initialized with the `max_concurrency` field of `get_gateway_bot`.

```lua

local R = self.api
    :capture()
    :get_current_application_information()
    :get_gateway_bot()

if R.success then

    local gatewayinfo
    self.app, gatewayinfo  = R:results()

    self.session_limit = session_limit.new(gatewayinfo.session_start_limit.max_concurrency)

    for i = 0 , gatewayinfo.shards - 1 do
        local s = shard.init({
            token = self.api.token
            ,id = i
            ,gateway = gatewayinfo.url
            ,compress = false
            ,transport_compression = true
            ,total_shard_count = gatewayinfo.shards
            ,large_threshold = 100
            ,auto_reconnect = true
            ,loop = cqs.running()
            ,output = output,
            intents = self.intents
        }, self.session_limit) -- we pass in the client's session limit.
        self.shards[i] = s
        s:connect()
    end
else....
```

#### *session-limit* `new(availability)`

Constructs *session-limit* object which will allow for up to `availability` concurrent
requests before blocking.
