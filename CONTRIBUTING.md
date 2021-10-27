### Contribution Guidelines

#### Documentation Guidelines

When editing the documentation please make sure you follow the style outlined.
If you want to add a markdown file that is not directly mapped to a file in the code,
please open an issue first: the generating script for HTML has some options
regarding their location.

- Name files the way the lua module will be named with a lowercase `.md` extension.
- Page titles must use h2 / `##`.
- There should be an initial paragraph describing the module.
- Please include context information in parentheses after broad types:
    ```md
    *string* not this!
    *string (uri)* this!
    ```
- The format for exported object documentation is:
    ```md
    #### *type* `name`
    <!-->Blank line here<!-->
    Description of the export.
    ```
- The format for exported function documentation is:
    ```md
    #### *return type* `functionname(argument, ...)`
    <!-->Blank line here<!-->
    Description of function.
    - *argument type* `argument`
        Optional description.
    <!-->One bullet for each argument<!-->
    ```
    Please make sure vararg parameters `...` are documented with a bullets too.

- You may inline documentation for tables in function arguments/members of exported tables:
    ```md
    *string (plaintext message)* `options.content`
    ```

- For exported types (realized in code as metatables with a constructor)
  document them using a h3 / `###` as follows:
    ```md
    ### *metatable*
    <!-->Blank line here<!-->
    Description of the type.

    #### *metatable* `constructor(argument, ...)`
    ...
    <!-->This should be the function that constructs the values with the metatable set.<!-->

    #### *return type* `metatable:method(argument, ...)`
    ...
    <!-->Methods are functions reachable from `metatable.__index`.<!-->
    ```

#### Code guidelines

- All modules must use `local _ENV = {}`, this is to restrict globals.
- **ALL** globals used must be localized at the top of the file.
- Standard library methods must be localized individually, do not localize the whole module.
- No tabs, use 4 spaces.
- Use `_ENV` as the returned module table (as appropriate).
- Use free variables in function declaration statements to export to `_ENV`.
- **ALL** metatables must have a `__name`.
- **ALL** `__name` fields must be scoped to lacord: `lacord.module.component`.
- Do not use `_ENV` as a metatable.
- Attach LDoc compatible comments if you wish to provide comments for functions.
- Complex code / scattered code paths must have a documentation trail to explain. (See shard.lua's session limit explainers)
- Please use `logger.throw` / `logger.fatal` to trigger a lua error.
- If an object can/should be serialized to a file or sent over the internet,
  implement the content typed protocol for that object.

#### Git Guidelines

- PRs will be squashed, so please keep that in mind.
- Always use long form commit messages.
- Always make sure they have a descriptive summary line.
- Always describe the changes you have made in a file, for each file changed.
- Try to keep commits minimal, consider amending locally instead of pushing multiple commits.
- Try to keep lines in your commit message body ~70 characters maximum.
- Don't put emojis in summary messages.
- When you fork please create a feature branch for a PR, do not use master.

##### Priority contributions

- Bug fixes.
- Improvements to existing code.
- Coverage for discord api methods.
- Documentation translations (open issue first).

This list is not exhaustive, this is just some of the things I would be primarily interested in receiving PRs for.

##### What not to contribute

- Clients (see [lacord-client](https://github.com/Mehgugs/lacord-client)).
- Please check the above repo to see if either already provides what you want to add, or would
  be a better destination for your contribution.
- Revisions to the rockspec (please open an issue and I will commit those if necessary).
- Voice support.
- Lua\[jit\] version compatibility.
- CI.
- All contributions to the `site` branch will be rejected, that branch is managed by a script.
- Config files.
- Coverage / Luacheck configuration.
- .gitattribute changes.

This list is not exhaustive.

