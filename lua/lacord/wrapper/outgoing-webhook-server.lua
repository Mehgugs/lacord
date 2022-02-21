local cli = require"lacord.cli"

if cli.unstable then return require"lacord.outgoing-webhook-server-2"
else return require"lacord.outgoing-webhook-server-1"
end