## changelog

Here changes from versions `1590965828` onward are listed.

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