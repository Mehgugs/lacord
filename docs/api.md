## lacord.api

This module is used to connect to discord's restful api over http.
All api methods must be called inside a cqueues managed coroutine.

#### Ratelimits

The api client will automatically handle ratelimits for you. 429s may still be encountered and will be handled as well.


#### *string* `USER_AGENT`

The lacord user-agent used by all clients.

#### *string* `URL`

The api url used by the client.

### *api*

This type has methods for interacting with the discord rest api.

#### *api* `init(options)`

This initializes the api client.

- *{string, string}* `options.client_credentials`
    Set this field to to use Basic authentication for the client credentials grant. It should be a sequence of
    your id and client secret.
- *string* `options.token`
    Set this field to use either a Bearer or Bot token for authentication. Mutually exclusive with `client_credentials`.
- *boolean* `options.track_ratelimits`
    Set this flag to track ratelimit information. This will be available in the `.rates` field of the client.
- *number (seconds)* `options.route_delay`
    Set this field to set a lower bound on the delay calculated when making requests. This is used to make the requests have more even availability but will reduce the throughput of the client.
- *number (seconds)* `options.api_timeout`
    Set this field to control the request timeout.
- *number (http version)* `options.api_http_version`
    Set this field to control the http version used
    by the request client.
- *boolean* `options.accept_encoding`
    Set this flag to control whether the client should
    accept compressed data from discord.

#### *boolean, applicaion/json|true, string, table* `api:method_name(...)`

All requests you can make via this client are methods of the form:
`api:<discord name snake cased>`. For example "Create message" would be
found at `api:create_message`. Consult discord's official documentation for a list of available api methods. All these methods return: a success
boolean;  response data decoded as json; an error message if success was false; and a table of errors if discord sent that in the error response.
All of these functions accept arguments in the following way: first the route parameters as strings in the order they appear in the uri; then the payload if the route accepts a body; then the query if the route accepts a query; and finally a list of content typed objects to attach as files in a multipart request.
Note that some endpoints may accept a query without a payload, in which case the arguments will look like: `route-parameters..., query`.
In the case of `204` the second return value will simply be true. This client will only attempt to retry these requests on timeout, or if a ratelimit is hit. In the latter case the client will wait an appropriate amount of time before continuing to make the request.


##### NOTE

The ["Guild scheduled events"](https://discord.com/developers/docs/resources/guild-scheduled-event) methods break the naming convention used by lacord: "List scheduled events for guild" would be found at `list_scheduled_guild_events`, and "Get Guild scheduled events" at `get_scheduled_guild_events`. This was done to improve readability because the names are rather long.

#### *api.capture* `api:capture()`

This function will create a capture object which can be used to safely sequence multiple requests together.

```lua
-- somewhere in a cqueues coroutine...
 local api = require"lacord.api"
 local discord_api = api.init{blah}
 local R = discord_api
   :capture()
   :get_gateway_bot()
   :get_current_application_information()
if R.success then -- ALL methods succeeded
   local results_list = R.result
   local A, B, C = R:results()
else
   local why = R.error
   local partial = R.result
   -- There may be partial results collected before the error, you can use this to debug.
   R:some_method() -- If there's been a failure, calls like this are noop'd.
end
```

#### *api.webhook* `webhook_init(webhook_token)`

Create a client suitable for executing webhooks.
The only methods this client has access to are
the webhook methods, and you will still need to provide the id as the first parameter of those
methods, but the token will be inserted into the argument list for you internally.

```lua
local hook = api.webhook_init(webhook_token)

hook:execute_webhook(webhook_id, {
    content = line,
    username = username,
})
```

#### *string* `with_reason(text)`

Adds a new contextual audit log reason to the currently running cqueues coroutine.
When requests are made in this coroutine which accept an audit log reason they
will pull a reason from the thread's reason if one is available:

```lua
-- somewhere in a cqueues coroutine...
local api = require"lacord.api"
local discord_api = api.init{blah}
api.with_reason "I'm doing this because I can!"
discord_api:create_guild_ban(...) -- this will have the reason defined above.
```