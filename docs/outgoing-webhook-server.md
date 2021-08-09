## lacord.outgoing-webhook-server

This module contains a low level https server for hosting an outgoing webhook for receiving discord interactions.

### *server*

This type is a http server configured for use as an outgoing webhook.

#### *server* `new(options, crtfile, keyfile)`

Constructs a new https server.
Providing TLS configuration (either by filepaths or context object) is optional,
but by default a warning is printed because discord will not accept plain `http`.
The callback `options.interact` can return a json object, and this will be set as
the interaction response. You can also use the [reponse object](#response_object) to set the body manually.

- *string* `options.public_key`
    Your applications public key, used for signature verification.
- *function* `options.interact`
    The callback to handle interactions from discord. This is called with the interaction payload and a [reponse object](#response_object).
- *function* `options.fallthrough`
    The callback to handle requests that are not on the route discord is configured to use.
- *string* `options.route`
    The path discord will send interactions to, defaults to `/`.
- *function* `options.onerror`
    The lua-http error handler, defaults to [`logger.error`](util.logger.html#error)
- *openssl.ssl.context* `options.ctx`
    An openssl context for TLS. Mutually exclusive with `crtfile`.
- *boolean* `options.ikwid`
    Set this flag to silence the warning message printing when TLS is not configured.
- *string (filepath)* `crtfile`
    The path to your certificate chain file.
- *string (filepath)* `keyfile`
    The path to your private key file.

### *response_object*

This type has methods for setting the server response to an interaction.

#### *headers* `response_object.request_headers`

The request headers.

#### *headers* `response_object.headers`

The response headers.

#### *string* `response_object.peername`

The address and port at the other end of the connection.

#### *string (http verb)* `response_object.method`

The http verb.

#### *string* `response_object.path`

The path.


#### *string* `response_object:set_body(body)`

Sets the body to the specified content typed object.

- *content_typed|string* `body`
    A content typed object will be resolved and the content-type header set along with the body, a string will set the body to that raw value.


#### *nothing* `response_object:set_503()`

Sets the status code to 503 and attaches a suitable body.

#### *nothing* `response_object:set_500()`

Sets the status code to 500 and attaches a suitable body.

#### *nothing* `response_object:set_401()`

Sets the status code to 401 and attaches a suitable body.

#### *nothing* `response_object:set_ok()`

Sets the status code to 204.

#### *nothing* `response_object:set_ok_and_reply(body, content_type)`

Sets the status code to 200 and attaches the given body.

- *content_typed|string* `body`
    A content typed object will be resolved and the content-type header set along with the body, a string will set the body to that raw value.
- *string (content_type)* `content_type`
    This will force the content-type set to be this argument if it is provided.

#### *nothing* `response_object:set_code_and_reply(code, body, content_type)`

Sets the status code to the given code and attaches the given body.

- *number (http status code)* `code`
- *content_typed|string* `body`
    A content typed object will be resolved and the content-type header set along with the body, a string will set the body to that raw value.
- *string (content_type)* `content_type`
    This will force the content-type set to be this argument if it is provided.

