local pairs = pairs
local _ENV = {}

local intents = {
    guilds                   = 0x0001,
    guild_members            = 0x0002,
    guild_bans               = 0x0004,
    guild_emojis             = 0x0008,
    guild_integrations       = 0x0010,
    guild_webhooks           = 0x0020,
    guild_invites            = 0x0040,
    guild_voice_states       = 0x0080,
    guild_presences          = 0x0100,
    guild_messages           = 0x0200,
    guild_message_reactions  = 0x0400,
    guild_message_typing     = 0x0800,
    direct_messages          = 0x1000,
    direct_message_reactions = 0x2000,
    direct_message_typing    = 0x4000,
    message_content          = 0x8000,
}

intents.everything = 0
for _, value in pairs(intents) do
    intents.everything = intents.everything | value
end

intents.message = 0
for name, value in pairs(intents) do
    if name:find'message' then
        intents.message = intents.message | value
    end
end

intents.guild = 0
for name, value in pairs(intents) do
    if name:find'guild' then
        intents.guild = intents.guild | value
    end
end

intents.direct = 0
for name, value in pairs(intents) do
    if name:find'direct' then
        intents.direct = intents.direct | value
    end
end

intents.normal = intents.everything & ~intents.guild_presences & ~intents.guild_voice_states
intents.unprivileged = intents.everything & ~intents.guild_members & ~intents.guild_presences & ~intents.message_content

return intents