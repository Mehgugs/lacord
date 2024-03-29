## lacord.cli

This module is used to set/get feature flags from the command line.

### Setting configuration values from the commandline

You may provide configuration from the commandline to lacord, this can be loaded
using [`module()`](#module). The presence of a flag on the commandline is enough to
enable it, but for convenience an assortment of values are also supported.
To set a flag simply append it as a commandline argument with the appropriate hypen prefix:
`lua main.lua --debug`. To use and load this configuration, call this module inside your `main.lua`
-- or equivalent entrypoint script -- and pass the vararg argument for the main chunk to the call like so:
```lua
require"lacord.cli"(...)
```

#### *boolean|string* `option`

Indexing this module will look up the key in the configuration.

Currently the only recognized keys are:

- *boolean* `debug`
    This field will enable debug logs. This is passed to the commandline as `--debug`
- *boolean* `unstable`
    This field will enable unstable features. These are features of the library that
    are partially supported or discord has said should not be considered available
    for widespread use. Things may become gated behind this flag on discord's whim
    so please read the changelogs to see which features are behind this flag.
    This is passed to the commandline as `--unstable-features`.
- *boolean* `deprecated`
    This field will enable deprecated features. These are features of the library that
    will be removed at a specified point in time. This is passed to the commandline as `--deprecated`.
- *string* `log_file`
    This field will open a file in write mode and pass it to the logger to write into. This is passed to the commandline as `--log-file PATH`
- *one of "0", "3", "8"* `log_mode`
    This field will set the logger's colour mode. This is passed to the commandline as
    `--log-mode n`
- *boolean* `accept`
    This field will instruct the cli parser to admit arbitrary parameters. Currently only
    values are supported. This enables a user defined parameters to be captured in the cli module table. This **does not** affect the environment variables read.
    This is passed to the commandline as `--accept-everything`, but the shorthand mnemonic `-a` may be preferable.

Additionally the following keys are loaded by this module **but are never used by lacord internally**.
You must manually use them yourself where appropriate.

- *string* `client_id`
    This field corresponds to the application's client id. This is passed to the commandline as `--client-id XXXXX`.

- *string* `client_secret`
    This field corresponds to the application's client secret. This is passed to the commandline as `--client-secret XXXXX`.

- *string* `token`
    This field corresponds to the application's bot token. This is passed to the commandline as `--token XXXXX`.


All keys may also be set by environment variables by uppercasing the key and prepending `LACORD_`.
For example, the `debug` key can be configured by the `LACORD_DEBUG` environment variable.

In the case that an environment variable has been set **and** a commandline flag provided,
this module will set the key if **either of them were positive**.

#### *table (argv)* `module()`

Calling the module like a function will load the function arguments as commandline arguments,
and also resolve environment variables that are set. This returns the argv array.
If the arguments do not match the scheme, argument resolving stops. The returned table contains
all unprocessed arguments.

Example with arguments as literals so you can see how it works:

```lua
    local arguments  = require"lacord.cli"('--debug', '--unstable-features', 'foo')
    -- In this example the cli module now has the parameters `debug` and `unstable` set.
    -- `arguments` contains remaining commandline arguments that were not processed which in this case is 'foo'.
```

### Shorthand parameters

You may also specify parameters using a single `-`, in which case each character of the parameter is
expanded to the corresponding long form and they are all set. You cannot use two different value flags in the same `-` string, because there will only be one value available for them to be assigned. In this scenario the module will set the first flag and stop expanding characters.

Example invocation:
```
$ lua -lacord main.lua -dDuL 8
```

This would set `debug`, `deprecated`, `unstable` and set the `log_mode` to `8`.

Characters and their corresponding key in cli:

|Character|Field          |
|---------|---------------|
|`d      `|`debug        `|
|`D      `|`deprecated   `|
|`u      `|`unstable     `|
|`a      `|`accept       `|
|`l      `|`log_file     `|
|`L      `|`log_mode     `|
|`i      `|`client_id    `|
|`s      `|`client_secret`|
|`t      `|`token        `|

### Automatically loading flags in lua standalone

The virtual module `acord` is designed to be loaded by the lua standalone interpreter option `l` (i.e `lua -lacord ...`).
This module will read from `_G.arg` -- and also read environment variables -- and populate the cli table with options.

On lua versions >= 5.4 this will emit lua warnings if there are malformed parameters.

Example invocation:

```bash
$ LACORD_TOKEN=XXXXXXXXXXXXXXXXXXXXXXXXXXXX lua -lacord main.lua --unstable-features
```

main.lua:
```lua
....
local discord_api = api.init{
    token = "Bot "..require"lacord.cli".token
}
....
```