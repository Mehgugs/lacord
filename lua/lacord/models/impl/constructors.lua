local impl = {
    user    = require"lacord.models.impl.user",
    channel  = require"lacord.models.impl.channel",
    guild   = require"lacord.models.impl.guild",
    message = require"lacord.models.impl.message",
    role    = require"lacord.models.impl.role",
}

local ctors = { }

for type, mod in pairs(impl) do
    ctors[type] = mod.from
end

return ctors