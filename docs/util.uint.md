## lacord.util.uint

This module provides functions for handling and manipulating discord snowflake IDs. In this module "encoded uint64" simply means that a uint64 value is being stored in a `lua_Integer` which is an int64.

#### *integer (snowflake)* `touint(s)`

Converts a number or string into an encoded uint64.

- *string|number* `s`


#### *integer (seconds)* `timestamp(s)`

Computes the UNIX timestamp of a given snowflake.

- *string|number (snowflake)* `s`

#### *integer (snowflake)* `fromtime(s)`

Creates an artificial snowflake from a given UNIX timestamp.

- *integer (seconds)* `s`

#### *table* `decompose(s)`

Gets the timestamp, worker ID, process ID and increment from a snowflake. These are set as fields in the returned table at `timestamp`, `worker`, `pid` and `increment` respectively.

- *string|number (snowflake)* `s`


#### *integer (snowflake)* `synthesize(s, worker, pid, incr)`

Creates an artifical snowflake from the given timestamp, worker and pid.

- *integer (seconds)* `s`
    The timestamp.
- *integer* `worker`
    The worker ID.
- *integer* `pid`
    The process ID.
- *integer* `incr`
    The increment. An internal incremented value is used if one is not provided.

#### *boolean* `snowflake_sort(i, j)`

A table sorter that will sort by the `id` field of the elements as snowflakes.


#### *boolean* `id_sort(i, j)`

A table sorter that will sort the elements as snowflake ids.