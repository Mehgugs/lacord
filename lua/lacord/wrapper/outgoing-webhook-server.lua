local cli = require"lacord.cli"

if not pcall(require, "luatweetnacl") then
    require"lacord.util.logger".fatal(
        "You do not have $luatweetnacl; installed. \z
         This is a necessary dependency for using the slash command webserver, \z
         but due to issues provisioning the module on all cqueues compatible systems \z
         it has been removed from the rockspec. Please run $luarocks install luatweetnacl; \z
         to install the module.")
end

if cli.unstable then return require"lacord.outgoing-webhook-server-2"
else return require"lacord.outgoing-webhook-server-1"
end