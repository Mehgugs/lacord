-- luacheck: ignore 111 113

local _ENV, iota, powers_of_two, iota1, iotaN, boundary = require"lacord.util.models.magic-numbers"()

channel_type = iota{
    TEXT,
    DM,
    VOICE,
    GROUP_DM,
    CATEGORY,
    NEWS,
    NEWS_THREAD,
    PUBLIC_THREAD,
    PRIVATE_THREAD,
    STAGE_VOICE,
    DIRECTORY,
    FORUM,
}


message_flag = powers_of_two{
    CROSSPOSTED,
    IS_CROSSPOST,
    SUPPRESS_EMBEDS,
    SOURCE_MESSAGE_DELETED,
    URGENT,
    HAS_THREAD,
    EPHEMERAL,
    LOADING,
    MENTIONS_FAILED,
}

permission = powers_of_two{
    CREATE_INSTANT_INVITE,
    KICK_MEMBERS,
    BAN_MEMBERS,
    ADMINISTRATOR,
    MANAGE_CHANNELS,
    MANAGE_GUILD,
    ADD_REACTIONS,
    VIEW_AUDIT_LOG,
    PRIORITY_SPEAKER,
    STREAM,
    VIEW_CHANNEL,
    SEND_MESSAGES,
    SEND_TTS_MESSAGES,
    MANAGE_MESSAGES,
    EMBED_LINKS,
    ATTACH_FILES,
    READ_MESSAGE_HISTORY,
    MENTION_EVERYONE,
    USE_EXTERNAL_EMOJIS,
    VIEW_GUILD_INSIGHTS,
    CONNECT,
    SPEAK,
    MUTE_MEMBERS,
    DEAFEN_MEMBERS,
    MOVE_MEMBERS,
    USE_VAD,
    CHANGE_NICKNAME,
    MANAGE_NICKNAMES,
    MANAGE_ROLES,
    MANAGE_WEBHOOKS,
    MANAGE_EMOJIS_AND_STICKERS,
    USE_APPLICATION_COMMANDS,
    REQUEST_TO_SPEAK,
    MANAGE_EVENTS,
    MANAGE_THREADS,
    CREATE_PUBLIC_THREADS,
    CREATE_PRIVATE_THREADS,
    USE_EXTERNAL_STICKERS,
    SEND_MESSAGES_IN_THREADS,
    USE_EMBEDDED_ACTIVITIES,
    MODERATE_MEMBERS,
}

interaction_type = iota1{
    PING,
    COMMAND,
    COMPONENT,
    AUTOCOMPLETE,
    MODAL_RESPONSE,
}

interaction_response = iotaN{
    PONG = 1,
    MESSAGE = 4,
    LOADING,
    ACKNOWLEDGE,
    UPDATE_MESSAGE,
    AUTOCOMPLETE_RESULT,
    CREATE_MODAL
}

command_type = iota1{
    boundary(APP_COMMAND, CHAT),
    USER_CONTEXT,
    boundary(CONTEXT_COMMAND, MESSAGE_CONTEXT),
}

command_option_type = iota1{
    SUB_COMMAND,
    boundary(SUB_COMMANDS, SUB_COMMAND_GROUP),
    STRING,
    INTEGER,
    BOOLEAN,
    USER,
    CHANNEL,
    ROLE,
    MENTIONABLE,
    NUMBER,
    ATTACHMENT,
}

component_type = iota1{
    ACTION_ROW,
    BUTTON,
    SELECT_MENU,
    TEXT_BOX
}

button_style = iota1{
    PRIMARY,
    SECONDARY,
    SUCCESS,
    boundary(INTERACTIVE, DANGER),
    LINK,
}

textbox_style = iota1{
    SHORT,
    PARAGRAPH
}

return _ENV

