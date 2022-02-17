## lacord.shard

This module is used to start a websocket session connected to discord's gateway.

### *shard*

This type has methods for connecting and interaction with the discord gateway.

#### *shard* `init(options, session_limiter)`

Construct a new shard object using the given options and identify mutex.

- *integer* `options.id`
    The ID of the shard.
- *boolean* `options.transport_compression`
    Sets the transport compression gateway option, defaults to true.
- *cqueue* `options.loop`
    Sets the cqueues controller object associated with this shard.
- *function* `options.output`
    Sets the output callback to dispatch events to.
- *string (url)|function* `options.gateway`
    Sets gateway url to connect to. This can be discovered by using `api:get_gateway_bot`. If this is a function it will be called with the shard object and must return the gateway url to use.
- *boolean* `options.auto_reconnect`
    Set this flag to cause the shard to attempt to reconnect after a non-fatal disconnect.
- *number (seconds)* `options.receive_timeout`
    Sets the timeout to use when reading from the websocket.
- *integer (bitfield)* `options.intents`
    Sets the gateway intents to declare when identifying with discord.
- *string* `options.token`
    Sets the token to use when identifying.
- *integer* `options.large_threshold`
    Sets the large threshold value to declare when identifying.
- *integer* `options.total_shard_count`
    The total amount of shards to declare when identiying.
- *application/json* `options.presence`
    An initial presence object to declare when identiying.
- *session limit* `session_limiter`
    A [session limit](util.session-limit.md) object created to handle sequencing the shards.

#### *shard* `shard:connect()`

Connects the shard to discord. This function is asynchronous and should be run inside a cqueues coroutine. (usually from state.loop)

#### *shard* `shard:disconnect(why, code)`

Disconnects the shard. This will not permanently stop an automatically connecting shard, please see [`shard:shutdown`](#shardshutdown).

- *string* `why`
    The disconnect reason, defaults to `"requested"`.
- *integer (websocket close code)* `code`
    Defaults to `4009`


#### *shard* `shard:shutdown(...)`

This will terminate the shard's connection, clearing any reconnection flags and then disconnecting.

- ...
    Arguments to pass to disconnect.

#### *boolean* `shard:request_guild_members(id)`

Sends a REQUEST_GUILD_MEMBERS request. This will return true if the request was successfully sent. If this function fails it will return false followed by an error message.

- *string (snowflake)* `id`
    The guild id to request members from.


#### *boolean, application/json|string* `shard:update_status(presence)`

Sends a STATUS_UPDATE request. This will return true if the request was successfully sent. If this function fails it will return false followed by an error message.

- *application/json* `presence`
    The new presence for the bot. See the [discord documentation](https://discord.com/developers/docs/topics/gateway#update-presence).

#### *boolean, application/json|string* `shard:update_voice(guild_id, channel_id, self_mute, self_deaf)`

Sends a VOICE_STATE_UPDATE request. This will return true if the request was successfully sent. If this function fails it will return false followed by an error message.

- *string (snowflake)* `guild_id`
    The guild id of the guild the voice channel is in.
- *string (snowflake)* `channel_id`
    The voice channel id.
- *boolean* `self_mute`
    Whether the bot is muted.
- *boolean* `self_deaf`
    Whether the bot is deafened.
