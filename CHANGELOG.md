## changelog

Here changes from versions `1590965828` onward are listed.

### 1629838555 -> 1637789515

#### [Documentation](docs)

- Documentation for `lacord.cli` was added.
- Documentation for `lacord.util.session-limit` was added.
- Wording was tweaked in `api.md`.

#### NEW lacord.cli

This new module has been introduced to facilitate command line configuration.
Most users will interact with it via the `-l` module like so:
`$ lua -lacord myscript.lua --unstable --deprecated --token XXXXX`

Please refer to [the associated documentation](docs/cli.md) for usage information.

The new `--unstable` flag added in this release will now control the usage of bleeding edge parts of
the discord api. Setting this flag may cause discord to return errors or unexpected data.

The new `--deprecated` flag added in this release will now be used to control availability of
some deprecated features. Everything made available by this flag **will be removed in the next major version**.

In `1637789515` the following features were marked as deprecated:

- function `lacord.api.init` (was renamed)
- function `lacord.shard.init` (was renamed)

#### [lacord.api](lua/lacord/api.lua)

- `api.init(options)` was renamed to `api.new`.
- Providing lacord with the `--unstable` flag will change how attachments are sent, following the new?
  guidelines. This will be enforced at some unspecified point in the future, and this soft change has
  been marked as unstable as it may change considerably on discord's whim. This does not impact lacord's API.
- Added a missing method, `modify_current_member`.
- Fixed the `get_token` method.
- Added support for guild scheduled events.
- Fixed some endpoint formatting issues.
- `edit_original_interaction_response` now accepts files.

#### [lacord.shard](lua/lacord/shard.lua)
- Add a session limit object to implement the `max_concurrency`
  rules mandated by discord. This object is automatically used
  by shards to orchestrate them.
- !!`shard.new` now takes a session-limit object as its second argument.
- !!`shard:send` now returns a boolean.
- `shard.init(options, session_limit)` was renamed to `new`.

#### [lacord.util](lua/lacord/util/init.lua)

- Added command line processing functions.
- Fixed `util.urlencoded_t` being incorrectly serialized.


#### NEW [lacord.util.session-limit](lua/lacord/util/session-limit.lua)

Added a new module for shard session limiting. Please see the [associated documentation](docs/util.session-limit.md) for more information.


### 1627995481.88199 -> 1629838555

#### NEW [Documentation](docs)

Markdown documentation was added in between releases, this now covers the public
facing areas of the project. There may be methods that have been left out of the
documentation: this is intentional.

#### [lacord.api](lua/lacord/api.lua)

- Added a missing method, `get_guild_application_commands`.
- Fixed an incorrect HTTP verb in the `edit_original_interaction_response` request.
- Added payload debugging.

#### [lacord.cdn](lua/lacord/cdn.lua)

- Fixed sticker image extensions not being added to the sticker url.
- One can now use the format type as the value of `ext` for stickers.

#### [lacord.util](lua/lacord/util/init.lua)

- Fixed some content-typed objects not producing filenames correctly.

#### [lacord.util.json](lua/lacord/util/json.lua)

- Changed `content_type` to re-use metatables if
  the argument does not have a metatable.



### [Hotfix release] 1627995481 -> 1627995481.88199

#### [lacord.api](lua/lacord/api.lua)

- Fix a ratelimiting unlock I wasn't 100% on.
- Add webhook token to the major parameters.
- Support sending files through interactions.

### 1622157568 -> 1627995481

- The dependencies list now contains `luatweetnacl` and `inspect`.
- Removed the crude websocket patch.

#### NEW [lacord.util.archp](src/archp.c)

- Added a util module for platform fingerprinting, this is now what `util.platform` is initialized from.

#### NEW [lacord.cdn](lua/lacord/cdn.lua)

- Added a CDN client for obtaining urls and resources from the discord CDN.
- This module provides a client at `cdn.new{options...}`.
- This module provides `cdn.resouce_url(parameters..., ext, size)` see discord's reference section
  of the documentation for a list of cdn resources.

#### [lacord.const](lua/lacord/const.lua)

- Removed cdn URLS. see [lacord.cdn](lua/lacord/cdn.lua).
- Using api version 9.

#### NEW [lacord.outgoing-webhook-server](lua/lacord/outgoing-webhook-server.lua)

- Added a new module for hosting an outgoing webhook for slash commands.
- This module provides `outgoing_webhook_server.new(options, crtpath, keypath)`.
  This returns a cqueues server object suitable for accepting slash commands.
  Refer to the [README](README.md#slash-commands).



#### [lacord.util](lua/lacord/util/init.lua)

- Added support for content typed file objects.
  These are lightweight containers which associate a content type with data.
  These file containers are used to send files to discord in attachments.
- Improved `util.platform`.
- Added `util.version` for detecting lua version more easily.
- Added `util.a_blob_of` for constructing content typed containers for raw data with
  an associated mime type.
- Added `util.blob_for_file` for preparing a content typed file for serializing as a file with name.
- Added `util.content_typed` to resolve an object with respect to content type tags.
  This returns `payload, cotnent_type` and is suitable for serialization or sending if the content type is present, if not content type is returned then it may have ignored incompatible objects.
- Added `util.the_content_type` to get the content type of a content typed object.
- Added `util.plaintext` `util.binary` `util.urlencoded` `util.png` `util.json_string`
  as common content type constructors.
- Added `util.form` for marking POST bodies as form data, this is only respected when attaching files.

#### [lacord.api](lua/lacord/api.lua)

- Added global ratelimit support. (needs testing)
- Removed `api.static`
- Added sticker methods.
- Added stage instance methods.
- Added misc. methods like GET `oauth2/token`
- Added contextual audit log reasons:
  ```lua
    api.with_reason "The reason I'm doing the action"
    api_client:auditloggable(...)
  ```
- Added / fixed thread methods.
- Added some more api client options mostly for debugging.
- Changed how file uploads are structured:
  - Pass in an array of content typed files instead of `{name, data}` pairs.
  - Set file names with `util.set_file_name(content_typed)`.


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