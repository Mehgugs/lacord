## lacord.util.intents

This module provides a thin convenience layer around the intents values used by discord.
See the [intents documentation](https://discord.com/developers/docs/topics/gateway#gateway-intents) for more detailed information.

#### *integer (intent)* `intent_name`

For every individual intent there exists a field in the module with its value. "GUILD_MEMBERS" would be found at `guild_members`.

### Extra values

#### *integer (intent)* `everything`

This intent contains all other intents.

#### *integer (intent)* `message`

This intent contains all message related intents.

#### *integer (intent)* `guild`

This intent contains all guild related intents.

#### *integer (intent)* `direct`

This intent contains all direct message related intents.

## Defaults

#### *integer (intent)* `normal`

This intent contains everything except presences and voice states, because those usually clog up shards are not needed by most bots.

#### *integer (intent)* `unprivileged`

This intent contains everything except privilaged gateway intents.