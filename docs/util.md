## lacord.util

This module contains a miscellaneous collection of functions which provide some utility to other lacord modules.


#### *string* `hash(str)`

Computes the FNV-1a 32bit hash of the given string.

- *string* `str`



#### *number* `rand(A, B)`

Produces a random double between `A` and `B`.

- *number* `A`
- *number* `B`


#### *string* `platform`

The operating system platform.


#### *number* `version`

The lua version as a number in `MAJOR.MINOR` form.


#### *number* `version_major`

The major version of the lua version.


#### *number* `version_minor`

The minor version of the lua version.


#### *number* `version_release`

The release/patch version of the lua version.


#### *boolean* `startswith(s, prefix)`

Tests whether the string `s` starts with the string `prefix`.

- *string* `s`
- *string* `prefix`


#### *boolean* `endswith(s, suffix)`

Tests whether the string `s` ends with the string `suffix`.

- *string* `s`
- *string* `suffix`


#### *boolean* `suffix(s, pre)`

Returns the suffix of `pre` in `s`

- *string* `s`
- *string* `pre`


#### *boolean* `prefix(s, pre)`

Returns the prefix of `suf` in `s`

- *string* `s`
- *string* `suf`


### content_typed

The following utilities construct and manipulate objects which represent content typed data. These can be transparently passed to api methods as bodies and will have the correct content type attached to the request. This is also true when sending files in multipart requests.

#### *string, string? (content_type)* `content_typed(payload)`

Resolve a prospective payload with respect to lacord content types. The 2nd argument will be present if a content type was resolved. The processing is occurs when `payload` has a metatable with a `__lacord_content_type` function and a `__lacord_payload` function defined.

- *table (implements \_\_lacord_content_type)* `payload`


#### *string? (content_type)* `the_content_type(payload)`

Resolve a prospective payload with respect to lacord content types. This only returns the content type or nil if one can not be resolved.

- *table (implements \_\_lacord_content_type)* `payload`


#### *table* `content_types`

A table of commonly used content types.

- *string* `JSON`
- *string* `TEXT`
- *string* `URLENCODED`
- *string* `BYTES`
- *string* `PNG`

#### *content_typed* `plaintext(str, name)`

Creates a content typed object containing plaintext.

- *string* `str`
    The plaintext content.
- *string* `name`
    A file name, optional.

#### *content_typed* `binary(str, name)`

Creates a content typed object containing raw bytes.

- *string* `str`
    The content.
- *string* `name`
    A file name, optional.

#### *content_typed* `urlencoded(t)`

Creates a content typed object containing url encoded key-value pairs.

- *table* `t`
    The table of key-value pairs.


#### *content_typed* `png(str, name)`

Creates a content typed object containing png image data.

- *string* `str`
    The png image data.
- *string* `name`
    A file name, optional.

#### *content_typed* `json_string(data, name)`

Creates a content typed object containing encoded json.

- *string* `data`
    The encoded json content.
- *string* `name`
    A file name, optional.

#### *string* `file_name(cted)`

Gets the file name for the associated content typed object.

- *content_typed* `cted`

#### *nothing* `set_file_name(cted, name)`

Sets the file name for the associated content typed object.

- *content_typed* `cted`
- *string* `name`


#### *content_typed* `a_blob_of(content_type, data, name)`

Creates a content typed object containing the specified content type.

- *string (content type)* `content_type`
- *string* `data`
    The data.
- *string* `name`
    A file name, optional.

#### *string, string (file name)* `blob_for_file`

Resolves a content typed object and gets a file name suitable for writing to a file. This function will try to resolve file name extensions with respect to the content type's appropriate extension, if one exists.

- *content_typed* `blob`
- *string* `name`
    A name to use instead of the set name.

