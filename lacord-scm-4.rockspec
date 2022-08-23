package = 'lacord'
version = 'scm-3'

source = {
    url = "git+https://github.com/Mehgugs/lacord.git"
}

local details =
[[lacord is a small discord library providing low level clients for the discord rest and gateway API.
  Check out https://github.com/Mehgugs/lacord-client for a higher level wrapper over this project.]]

description = {
    summary = 'A low level, lightweight discord API library.'
    ,homepage = "https://github.com/Mehgugs/lacord"
    ,license = 'MIT'
    ,maintainer = 'Magicks <m4gicks@gmail.com>'
    ,detailed = details
}

dependencies = {
     'lua >= 5.3'
    ,'cqueues'
    ,'http'
    ,'lua-zlib'
    ,'lua-cjson-219'
    ,'inspect'
}

build = {
     type = "builtin"
    ,modules = {
        ["lacord.util.archp"] = "src/archp.c",
        ["lacord.cli"] = "lua/lacord/util/cli_default.lua",
        ["acord"] = "lua/lacord/util/cli_auto.lua",
        ["lacord.ext.shs"] = "ext/shs/shs.lua",
        ["lacord.outgoing-webhook-server"] = "lua/lacord/wrapper/outgoing-webhook-server.lua",

        ["internationalize"] = "ext/internationalize/internationalize/init.lua",
        ["internationalize.interpolation"] = "ext/internationalize/internationalize/interpolation.lua",
        ["internationalize.plural"] = "ext/internationalize/internationalize/plural.lua"
    }
}