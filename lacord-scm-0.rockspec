package = 'lacord'
version = 'scm-0'

source = {
    url = "git://github.com/Mehgugs/lacord.git"
}

description = {
    summary = 'A low level, lightweight discord API shard library.'
    ,homepage = "https://github.com/Mehgugs/lacord"
    ,license = 'MIT'
    ,maintainer = 'Magicks <m4gicks@gmail.com>'
    ,detailed = ""
}

dependencies = {
     'lua >= 5.3'
    ,'cqueues'
    ,'http'
    ,'lua-zlib'
    ,'lpeglabel >= 1.0'
    ,'lua-cjson == 2.1.0-1'
}

build = {
     type = "builtin"
    ,modules = {}
}