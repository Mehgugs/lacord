## lacord.cdn

This module is used to get discord CDN urls and fetch CDN resources.

#### *string* `cdn_asset_url(...)`

For each CDN endpoint listed [here][cdn_endpoints] there is
a function in this module for creating a url. For example the "Custom Emoji" url function
is found at `custom_emoji`. As arguments these functions take any parameters present in the documentation's url followed by the extension and size.

```lua
local cdn = require"lacord.cdn"
local the_url = cdn.custom_emoji_url(emoji_id, "png")
```

### *cdn*

This type has methods for retrieving assets from the discord CDN.

#### *cdn* `new(options)`

Constructs a new cdn client.

- *number (http version)* `options.http_version`
    Set this field to control the http version used when making requests.
- *boolean* `options.accept_encoding`
    Set this flag to control whether the client should
    accept compressed data from discord.
- *number (seconds)* `options.api_timeout`
    Set this field to control the request timeout.

#### *content_typed, string, table* `cdn:get_endpoint(...)`

Fetches the an asset from the CDN. Similarly to the url functions, for every CDN endpoint listed [here][cdn_endpoints] there is a cdn client method for fetching
an asset from the endpoint. For example the "Custom Emoji" method would be found at `cdn:get_custom_emoji`. All of these methods accept the same arguments as their associated url function. These functions return a content typed table,
with the inner blob of data located at index 1. Read more about content types [here](util.html#content_typed). If these functions fail the first return will be nil, followed by an error message and an errors table if discord sent one.



[cdn_endpoints]:
https://discord.com/developers/docs/reference#image-formatting-cdn-endpoints