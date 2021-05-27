## changelog

Here changes from versions `1590965828` onward are listed.

### 1619975269 -> 1622157568

- The dependencies list now contains an incompatibility with the rock `lua-cjson`.
  you may need to do a fresh install of `lacord` after removing it if there's an issue.

#### NEW [lacord.util.json](lua/lacord/util/json.lua)

- Added a util module which controls the json encoder / decoder used by lacord.
- This module provides the usual `encode()`, `decode()`, and `null` features.
- Empty tables are configured to be parsed as empty json arrays.
- A set of extra utilities are also provided: `jarray` will construct a new table
  which will always be parsed as a json array; `empty_array` is an opaque table
  that represents an empty json array.

#### [lacord.const](lua/lacord/const.lua)

- Added a flag `use_cjson` which governs what json library `lacord.json` becomes.
- This flag is not intended for end users, and is used to modify the library's behaviour
  should the need arise.

### 1618833413 -> 1619975269

#### [lacord.api](lua/lacord/api.lua)

- Added requests for threads and interactions. This is **not stable**.
- Deprecated `api.static` in favour of a webhook client (it can only use "static" methods as before but ratelimit caches are by webhook token).
- Introduced dkjson as the encoder/decoder, this means lua's empty table `{}` is now treated as `[]` by the json encoder.
- This is **temporary** as cjson needs to have its latest version published. If that is held up I will fork and publish my own rock.

#### [lacord.util](lua/lacord/util/init.lua)

- Added some string helpers.

#### [lacord.util.date]()

- REMOVED module.

#### [lacord.util.plcompat]()

- REMOVED module.

#### [lacord.shard](lua/lacord/shard.lua)

- Introduced dkjson as the encoder/decoder, this means lua's empty table `{}` is now treated as `[]` by the json encoder.
- This is **temporary** as cjson needs to have its latest version published.

- Fixed shards stalling due to a typo in messages.

### 1617477179 -> 1618833413

#### global changes

- The api and shard metatables are now explicit.

#### [lacord.api](lua/lacord/api.lua)

- Added api request methods, these cover everything *except* templates and slash commands right now.
- Added `api.static` which is an instance of an api client with no token.
  This can be used to perform requests which do not require authentication, like executing webhooks.
- Added `api:capture` for sequencing calls.
- You can now attach text files with utf-8 encoding using `api:create_message_with_txt`.
- You can now send other payload types via `api:request`,
    - Objects whose metatable has a `__lacord_content_type` will now be encoded using that
      same metatable's `__lacord_payload` function.
- Bot, bearer, and client credientials are now supported authorization headers.

#### [lacord.const](lua/lacord/const.lua)

- Tweaked cdn links.

#### [lacord.util](lua/lacord/util/init.lua)

- REMOVED `util.interposable`
- REMOVED `util.capturable`


### 1590965828 -> 1617477179

#### global changes

- Moved to version 8 of gateway.
- Removed `lpeglabel` dependancy.
    - This removes `util.string` and `util.relabel`.
    - `lpeglabel` and `lpeg` are not compatible and cause the `lpeg` C library to fail (this is a hard crash).
    - Other dependencies (namely `lpegpatterns` from `http`) use `lpeg` so we are required to use it too.



#### [lacord.api](lua/lacord/api.lua)

- Fixed ratelimiting mostly.
    - Still needs another pass in future.
- REMOVED error parsing for now, it will return in a future release.
- REMOVED *most* api methods for now, they will return in a future release.

#### [lacord.const](lua/lacord/const.lua)

- Moved to `discord.com`.
- Moved to `api_version` `8`.

#### [lacord.util](lua/lacord/util/init.lua)

- REMOVED all lpeg utilities.
- made `util.capturable` more sensible.

#### [lacord.util.plcompat](lua/lacord/util/plcompat.lua)

- License now provided.

#### [lacord.util.date](lua/lacord/util/plcompat.lua)

- License now provided.