## lacord.util.logger

This module provides a set of functions for logging to standard output and error stream in a readable format.

#### *file* `fd`

Set this to a lua file object opened in a write mode to also write any output to the file.

#### *integer* `mode(x)`

Sets the colour mode the logger uses.

- *integer* `x`
    The colour mode, valid values are:
    - `0` no colouring.
    - `3` colouring using standard color codes.
    - `8` colouring using 8 bit ansi codes.
    - `24` colouring using 24 bit ansi codes.

#### *nothing* `info(fmt, ...)`

Writes using the info prefix to standard output.

- *string* `fmt`
    A lua format string.
- `...`
    Format values.

#### *nothing* `warn(fmt, ...)`

Writes using the warning prefix to standard output.

- *string* `fmt`
    A lua format string.
- `...`
    Format values.


#### *nothing* `error(fmt, ...)`

Writes using the error prefix to standard error.

- *string* `fmt`
    A lua format string.
- `...`
    Format values.


#### *nothing* `throw(fmt, ...)`

Writes using the error prefix to standard error,
and then raises the message as a lua error.

- *string* `fmt`
    A lua format string.
- `...`
    Format values.


#### *nothing* `fatal(fmt, ...)`

Writes using the error prefix to standard error,
and then terminates the program with a non-zero exit code.

- *string* `fmt`
    A lua format string.
- `...`
    Format values.


#### *anything* `assert(x, ...)`

Similar to lua's assert but uses logger.throw when an assertion fails.

- *string* `x`
    A value to assert is truthy.
- `...`
    Arguments to [`throw`](#throw)

