## changelog

Here changes from versions `1590965828` onward are listed.

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



