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

All keys may also be set by environment variable by uppercasing the key and prepending `LACORD_`.
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