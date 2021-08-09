## lacord.util.json

This module re-exports the json encode and decode functions so that the library used may be configured.

#### *string (application/json)* `encode(x)`

Encodes the lua object `x` as a json object.

#### *application/json* `decode(x)`

Decodes a json string into a content_typed object.

#### *application/json* `null`

A value representing the json `null` value.

#### *application/json* `empty_array`

A value representing an empty json array.

#### *application/json* `jarray(...)`

Packs `...` into a json array object.