local iiter = ipairs
local setm  = setmetatable

local cli    = require"lacord.cli"
local logger = require"lacord.util.logger"
local util   = require"lacord.util"

local LACORD_DEBUG      = cli.debug
local LACORD_DEPRECATED = cli.deprecated
local LACORD_UNSTABLE   = cli.unstable

local a_form              = util.form
local compute_attachments = util.compute_attachments
local is_form             = util.is_form
local merge               = util.merge

--luacheck: ignore 111 631

--- Request a specific resource.
-- Function name is the routepath in snake_case
-- Please see the [discord api documentation](https://discordapp.com/developers/docs/reference) for requesting specific routes.
-- @function route_path
-- @tab state The api state.
-- @param ... Parameters to the request
-- @return @{api.request}
-- @usage
--  api.get_channel(state, id)

return function(api)

local default = {bot = true}
local authorization = setm({map = {bot = {}, webhook = {}, client_credentials = {}, bearer = {}, none={}}}, {__index = function() return default end})

local function auth(name, ...)
    authorization[name] = {}

    for _ , v in iiter{...} do
        authorization[name][v] = true
        authorization.map[v][name] = true
    end
end


local empty_route = {}
function api:get_current_application_information()
    return self:request( 'get_current_application_information', 'GET', '/oauth2/applications/@me', empty_route)
end

function api:get_current_authorization_information()
    return self:request('get_current_authorization_information', 'GET', '/oauth2/@me', empty_route)
end

auth('get_current_application_information', 'bot', 'bearer', 'client_credentials')
auth('get_current_authorization_information', 'bot', 'bearer', 'client_credentials')

function api:get_gateway_bot()
    return self:request('get_gateway_bot', 'GET', '/gateway/bot', empty_route)
end

function api:get_guild_audit_log(guild_id)
    return self:request('get_guild_audit_log', 'GET', '/guilds/:guild_id/audit-logs', {guild_id = guild_id})
end

function api:get_channel(channel_id)
    return self:request('get_channel', 'GET', '/channels/:channel_id', {channel_id = channel_id})
end

function api:modify_channel(channel_id, payload)
    return self:request('modify_channel', 'PATCH', '/channels/:channel_id', {channel_id = channel_id}, payload)
end

function api:delete_channel(channel_id)
    return self:request('delete_channel', 'DELETE', '/channels/:channel_id', {channel_id = channel_id})
end

function api:get_channel_messages(channel_id, query)
    return self:request('get_channel_messages', 'GET', '/channels/:channel_id/messages',
        {channel_id = channel_id},
        nil, query)
end

function api:get_channel_message(channel_id, message_id)
    return self:request('get_channel_message', 'GET', '/channels/:channel_id/messages/:message_id',
        {channel_id = channel_id, message_id = message_id})
end

function api:create_message(channel_id, payload, files)
    if files then
        merge(payload, compute_attachments(files), _ENV.attachments_resolution)
    end
    return self:request('create_message', 'POST', '/channels/:channel_id/messages', {
        channel_id = channel_id
    }, payload, nil, files)
end

function api:crosspost_message(channel_id, message_id)
    return self:request('crosspost_message', 'POST', '/channels/:channel_id/messages/:message_id/crosspost',
        {channel_id = channel_id, message_id = message_id})
end

function api:create_reaction(channel_id, message_id, emoji)
    return self:request('create_reaction', 'PUT', '/channels/:channel_id/messages/:message_id/reactions/:emoji/@me',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_own_reaction(channel_id, message_id, emoji)
    return self:request('delete_own_reaction', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji/@me',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_user_reaction(channel_id, message_id, emoji, user_id)
    return self:request('delete_user_reaction', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji/:user_id',
    {channel_id = channel_id, message_id = message_id, emoji = emoji, user_id = user_id})
end

function api:get_reactions(channel_id, message_id, emoji)
    return self:request('get_reactions', 'GET', '/channels/:channel_id/messages/:message_id/reactions/:emoji',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:delete_all_reactions(channel_id, message_id)
    return self:request('delete_all_reactions', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions',
    {channel_id = channel_id, message_id = message_id})
end

function api:delete_reactions(channel_id, message_id, emoji)
    return self:request('delete_reactions', 'DELETE', '/channels/:channel_id/messages/:message_id/reactions/:emoji',
    {channel_id = channel_id, message_id = message_id, emoji = emoji})
end

function api:edit_message(channel_id, message_id, edits)
    return self:request('edit_message', 'PATCH', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    }, edits)
end

function api:delete_message(channel_id, message_id)
    return self:request('delete_message', 'DELETE', '/channels/:channel_id/messages/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:bulk_delete_messages(channel_id, query)
    return self:request('bulk_delete_messages', 'DELETE', '/channels/:channel_id/messages/bulk-delete', {
        channel_id = channel_id
    }, nil, query)
end

function api:edit_channel_permissions(channel_id, overwrite_id, edits)
    return self:request('edit_channel_permissions', 'PUT', '/channels/:channel_id/permissions/:overwrite_id', {
        channel_id = channel_id, overwrite_id = overwrite_id
    }, edits)
end

function api:delete_channel_permissions(channel_id, overwrite_id)
    return self:request('delete_channel_permissions', 'DELETE', '/channels/:channel_id/permissions/:overwrite_id', {
        channel_id = channel_id, overwrite_id = overwrite_id
    })
end

function api:get_channel_invites(channel_id)
    return self:request('get_channel_invites', 'GET', '/channels/:channel_id/invites', {
        channel_id = channel_id
    })
end

function api:create_channel_invite(channel_id, invite)
    return self:request('create_channel_invite', 'POST', '/channels/:channel_id/invites', {
        channel_id = channel_id
    }, invite)
end

function api:follow_channel(channel_id, follower)
    return self:request('follow_channel', 'POST', '/channels/:channel_id/followers', {
        channel_id = channel_id
    }, follower)
end

function api:trigger_typing_indicator(channel_id)
    return self:request('trigger_typing_indicator', 'POST', '/channels/:channel_id/typing', {
        channel_id = channel_id
    })
end

function api:add_pinned_channel_message(channel_id, message_id)
    return self:request('add_pinned_channel_message', 'PUT', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:get_pinned_messages(channel_id)
    return self:request('get_pinned_messages', 'GET', '/channels/:channel_id/pins', {
        channel_id = channel_id
    })
end

function api:delete_pinned_channel_message(channel_id, message_id)
    return self:request('get_pinned_messages', 'DELETE', '/channels/:channel_id/pins/:message_id', {
        channel_id = channel_id,
        message_id = message_id
    })
end

function api:start_thread_with_message(channel_id, message_id, payload)
    return self:request('start_thread_with_message', 'POST', '/channels/:channel_id/messages/:message_id/threads', {
       channel_id = channel_id,
       message_id = message_id,
    }, payload)
end

function api:start_thread_without_message(channel_id, payload)
    return self:request('start_thread_without_message', 'POST', '/channels/:channel_id/threads', {
       channel_id = channel_id
    }, payload)
end

local HAS_MESSAGE_QUERY = {has_message=true}
local NESTED_QUERY = {use_nested_fields = true, has_message=true}
local GUILD_PUBLIC_THREAD = 11

if LACORD_DEBUG then
    function api:start_thread_in_forum(channel_id, payload, files)
        local nested = payload.message
        if files then
            merge(nested or payload, compute_attachments(files), _ENV.attachments_resolution)
        end
        if payload.type ~= GUILD_PUBLIC_THREAD then
            logger.warn("$api:start_thread_in_forum; can only be used to create public threads; overwriting type in payload.")
            payload.type = GUILD_PUBLIC_THREAD
        end
        return self:request('start_thread_in_forum', 'POST', '/channels/:channel_id/threads', {
            channel_id = channel_id
        }, payload, nested and NESTED_QUERY or HAS_MESSAGE_QUERY, files)
    end
else
    function api:start_thread_in_forum(channel_id, payload, files)
        local nested = payload.message
        if files then
            merge(nested or payload, compute_attachments(files), _ENV.attachments_resolution)
        end
        payload.type = GUILD_PUBLIC_THREAD
        return self:request('start_thread_in_forum', 'POST', '/channels/:channel_id/threads', {
            channel_id = channel_id
        }, payload, nested and NESTED_QUERY or HAS_MESSAGE_QUERY, files)
    end
end

function api:join_thread(channel_id)
    return self:request('join_thread', 'PUT', '/channels/:channel_id/thread-members/@me', {
       channel_id = channel_id
    })
end

function api:add_thread_member(channel_id, user_id)
    return self:request('add_thread_member', 'GET', '/channels/:channel_id/thread-members/:user_id', {
       channel_id = channel_id,
       user_id = user_id
    })
end

function api:leave_thread(channel_id)
    return self:request('leave_thread', 'DELETE', '/channels/:channel_id/thread-members/@me', {
       channel_id = channel_id
    })
end

function api:remove_thread_member(channel_id, user_id)
    return self:request('remove_thread_member', 'DELETE', '/channels/:channel_id/thread-members/:user_id', {
       channel_id = channel_id,
       user_id = user_id
    })
end

function api:get_thread_member(channel_id, user_id)
    return self:request('get_thread_member', 'GET', '/channels/:channel_id/thread-members/:user_id', {
       channel_id = channel_id,
       user_id = user_id
    })
end

function api:list_thread_members(channel_id)
    return self:request('list_thread_members', 'GET', '/channels/:channel_id/thread-members', {
       channel_id = channel_id
    })
end

function api:list_active_guild_threads(guild_id)
    return self:request('list_active_threads', 'GET', '/guilds/:guild_id/threads/active', {
        guild_id = guild_id,
    })
end

if LACORD_DEPRECATED and not LACORD_UNSTABLE then
    function api:list_active_threads(channel_id)
        return self:request('list_active_threads', 'GET', '/channels/:channel_id/threads/active', {
            channel_id = channel_id,
        })
    end
elseif not LACORD_DEPRECATED and not LACORD_UNSTABLE then
    function api:list_active_threads()
        logger.warn("%s cannot $list_active_threads; because it has been disabled. Try $list_active_guild_threads; instead.", self)
        return false, nil, "This endpoint has been disabled by discord."
    end
end


function api:list_public_archived_threads(channel_id,  query)
    return self:request('list_public_archived_threads', 'GET', '/channels/:channel_id/threads/archived/public', {
       channel_id = channel_id
    }, nil,  query)
end

function api:list_private_archived_threads(channel_id,  query)
    return self:request('list_private_archived_threads', 'GET', '/channels/:channel_id/threads/archived/private', {
       channel_id = channel_id
    }, nil,  query)
end

function api:list_joined_private_archived_threads(channel_id, query)
    return self:request('list_joined_private_archived_threads', 'GET', '/channels/:channel_id/users/@me/threads/archived/private', {
       channel_id = channel_id
    }, nil,  query)
end

function api:create_interaction_response(interaction_id, interaction_token, payload, files)
    if files then
        merge(payload.data, compute_attachments(files), _ENV.attachments_resolution)
    end
    return self:request('create_interaction_response', 'POST', '/interactions/:interaction_id/:interaction_token/callback', {
        interaction_id = interaction_id,
       interaction_token = interaction_token
    }, payload, nil, files)
end

function api:get_original_interaction_response(application_id, interaction_token)
    return self:request('get_original_interaction_response', 'GET', '/webhooks/:application_id/:interaction_token/messages/@original', {
       application_id = application_id,
       interaction_token = interaction_token
    })
end

function api:edit_original_interaction_response(application_id, interaction_token, payload, files)
    return self:request('edit_original_interaction_response', 'PATCH', '/webhooks/:application_id/:interaction_token/messages/@original', {
       application_id = application_id,
       interaction_token = interaction_token
    }, payload, nil, files)
end

function api:delete_original_interaction_response(application_id, interaction_token)
    return self:request('delete_original_interaction_response', 'DELETE', '/webhooks/:application_id/:interaction_token/messages/@original', {
       application_id = application_id,
       interaction_token = interaction_token
    })
end

function api:create_followup_message(application_id, interaction_token,  payload, files)
    if files then
        merge(payload, compute_attachments(files), _ENV.attachments_resolution)
    end
    return self:request('create_followup_message', 'POST', '/webhooks/:application_id/:interaction_token', {
       application_id = application_id,
       interaction_token = interaction_token
    }, payload, nil, files)
end

function api:edit_followup_message(application_id, interaction_token, message_id, payload)
    return self:request('edit_followup_message', 'PATCH', '/webhooks/:application_id/:interaction_token/messages/:message_id', {
       application_id = application_id,
       interaction_token = interaction_token,
       message_id = message_id
    }, payload)
end

function api:delete_followup_message(application_id, interaction_token, message_id)
    return self:request('delete_followup_message', 'DELETE', '/webhooks/:application_id/:interaction_token/messages/:message_id', {
       application_id = application_id,
       interaction_token = interaction_token,
       message_id = message_id
    })
end

function api:get_guild_emoji(guild_id, emoji_id)
    return self:request('get_guild_emoji', 'GET', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    })
end

function api:create_guild_emoji(guild_id, emoji)
    return self:request('create_guild_emoji', 'POST', '/guilds/:guild_id/emojis', {
        guild_id = guild_id
    }, emoji)
end

function api:modify_guild_emoji(guild_id, emoji_id, edits)
    return self:request('modify_guild_emoji', 'PATCH', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    }, edits)
end

function api:DELETE_guild_emoji(guild_id, emoji_id)
    return self:request('delete_guild_emoji', 'DELETE', '/guilds/:guild_id/emojis/:emoji_id', {
        guild_id = guild_id,
        emoji_id = emoji_id
    })
end

function api:get_guild(guild_id, with_counts)
    return self:request('get_guild', 'GET', '/guilds/:guild_id', {
        guild_id = guild_id
    }, nil, { with_counts = not not with_counts})
end

function api:get_guild_preview(guild_id)
    return self:request('get_guild_preview', 'GET', '/guilds/:guild_id/preview', {
        guild_id = guild_id
    })
end

function api:create_guild(payload)
    return self:request('create_guild', 'POST', '/guilds', empty_route, payload)
end

function api:modify_guild(guild_id, edits)
    return self:request('modify_guild', 'PATCH', '/guilds/:guild_id', {
        guild_id = guild_id
    }, edits)
end

function api:delete_guild(guild_id)
    return self:request('delete_guild', 'DELETE', '/guilds/:guild_id', {
        guild_id = guild_id
    })
end

function api:create_guild_channel(guild_id, channel)
    return self:request('create_guild_channel', 'POST', '/guilds/:guild_id/channels', {
        guild_id = guild_id
    }, channel)
end

function api:modify_guild_channel_positions(guild_id, pos)
    return self:request('modify_guild_channel_positions', 'PATCH', '/guilds/:guild_id/channels', {
        guild_id = guild_id
    }, pos)
end

function api:get_guild_member(guild_id, user_id)
    return self:request('get_guild_member', 'GET', '/guilds/:guild_id/members/:user_id', {
        guild_id = guild_id,
        user_id = user_id
    })
end

function api:list_guild_members(guild_id, params)
    return self:request('list_guild_members', 'GET', '/guilds/:guild_id/members', {
        guild_id = guild_id
    }, nil, params)
end

function api:search_guild_members(guild_id, query)
    return self:request('search_guild_members', 'GET', '/guilds/:guild_id/members/search', {
       guild_id = guild_id
    }, nil, query)
end

function api:add_guild_member(guild_id, user_id, payload)
    return self:request('add_guild_member', 'PUT', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id,
    }, payload)
end

function api:modify_guild_member(guild_id, user_id, payload)
    return self:request('modify_guild_member', 'PATCH', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:modify_current_member(guild_id,  payload)
    return self:request('modify_current_member', 'PATCH', '/guilds/:guild_id/members/@me', {
       guild_id = guild_id,
    }, payload)
end

function api:modify_current_user_nick(guild_id,  payload)
    return self:request('modify_current_user_nick', 'PATCH', '/guilds/:guild_id/members/@me/nick', {
       guild_id = guild_id,

    }, payload)
end


function api:add_guild_member_role(guild_id, user_id, role_id)
    return self:request('add_guild_member_role', 'PUT', '/guilds/:guild_id/members/:user_id/roles/:role_id', {
       guild_id = guild_id,
       user_id = user_id,
       role_id = role_id
    })
end

function api:remove_guild_member_role(guild_id, user_id, role_id )
    return self:request('remove_guild_member_role', 'DELETE', '/guilds/:guild_id/members/:user_id/roles/:role_id', {
       guild_id = guild_id,
       user_id = user_id,
       role_id = role_id
    })
end

function api:remove_guild_member(guild_id, user_id )
    return self:request('remove_guild_member', 'DELETE', '/guilds/:guild_id/members/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, nil)
end

function api:get_guild_bans(guild_id)
    return self:request('get_guild_bans', 'GET', '/guilds/:guild_id/bans', {
       guild_id = guild_id,
    })
end

function api:get_guild_ban(guild_id, user_id)
    return self:request('get_guild_ban', 'GET', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    })
end

function api:create_guild_ban(guild_id, user_id, payload)
    return self:request('create_guild_ban', 'POST', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:remove_guild_ban(guild_id, user_id)
    return self:request('remove_guild_ban', 'DELETE', '/guilds/:guild_id/bans/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    })
end

function api:get_guild_roles(guild_id)
    return self:request('get_guild_roles', 'GET', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    })
end

function api:create_guild_role(guild_id,  payload)
    return self:request('create_guild_role', 'POST', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    }, payload)
end

function api:modify_guild_role_positions(guild_id,  payload)
    return self:request('modify_guild_role_positions', 'PATH', '/guilds/:guild_id/roles', {
       guild_id = guild_id,

    }, payload)
end

function api:modify_guild_role(guild_id, role_id, payload)
    return self:request('modify_guild_role', 'PATCH', '/guilds/:guild_id/roles/:role_id', {
       guild_id = guild_id,
       role_id = role_id
    }, payload)
end

function api:delete_guild_role(guild_id, role_id)
    return self:request('delete_guild_role', 'DELETE', '/guilds/:guild_id/roles/:role_id', {
       guild_id = guild_id,
       role_id = role_id
    })
end

function api:get_guild_prune_count(guild_id,  query)
    return self:request('get_guild_prune_count', 'GET', '/guilds/:guild_id/prune', {
       guild_id = guild_id,

    }, nil,  query)
end

function api:begin_guild_prune(guild_id,  payload)
    return self:request('begin_guild_prune', 'POST', '/guilds/:guild_id/prune', {
       guild_id = guild_id,

    }, payload)
end

function api:get_guild_voice_regions(guild_id)
    return self:request('get_guild_voice_regions', 'GET', '/guilds/:guild_id/regions', {
       guild_id = guild_id,

    })
end

function api:get_guild_invites(guild_id)
    return self:request('get_guild_invites', 'GET', '/guilds/:guild_id/invites', {
       guild_id = guild_id,

    })
end

function api:get_guild_integrations(guild_id)
    return self:request('get_guild_integrations', 'GET', '/guilds/:guild_id/integrations', {
       guild_id = guild_id,

    })
end

function api:delete_guild_integration(guild_id, integration_id)
    return self:request('delete_guild_integration', 'DELETE', '/guilds/:guild_id/integrations/:integration_id', {
       guild_id = guild_id,
       integration_id = integration_id
    })
end

function api:get_guild_widget_settings(guild_id)
    return self:request('get_guild_widget_settings', 'GET', '/guilds/:guild_id/widget', {
       guild_id = guild_id,
    })
end

function api:modify_guild_widget(guild_id,  payload)
    return self:request('modify_guild_widget', 'PATCH', '/guilds/:guild_id/widget', {
       guild_id = guild_id,

    }, payload)
end

function api:get_guild_widget(guild_id)
    return self:request('get_guild_widget', 'GET', '/guilds/:guild_id/widget.json', {
       guild_id = guild_id,

    })
end

function api:get_guild_vanity_url(guild_id,  query)
    return self:request('get_guild_vanity_url', 'GET', '/guilds/:guild_id/vanity-url', {
       guild_id = guild_id,

    }, nil,  query)
end

function api:get_guild_widget_image(guild_id,  query)
    return self:request('get_guild_widget_image', 'GET', '/guilds/:guild_id/widget.png', {
       guild_id = guild_id,

    }, nil, query)
end

function api:get_guild_welcome_screen(guild_id)
    return self:request('get_guild_welcome_screen', 'GET', '/guilds/:guild_id/welcome-screen', {
       guild_id = guild_id,

    })
end

function api:modify_guild_welcome_screen(guild_id,  payload)
    return self:request('modify_guild_welcome_screen', 'PATCH', '/guilds/:guild_id/welcome-screen', {
       guild_id = guild_id,

    }, payload)
end

function api:update_current_user_voice_state(guild_id,  payload)
    return self:request('update_current_user_voice_state', 'PATCH', '/guilds/:guild_id/voice-states/@me', {
       guild_id = guild_id,

    }, payload)
end

function api:update_user_voice_state(guild_id, user_id, payload)
    return self:request('update_user_voice_state', 'PATCH', '/guilds/:guild_id/voice-states/:user_id', {
       guild_id = guild_id,
       user_id = user_id
    }, payload)
end

function api:get_invite(invite_code,  query)
    return self:request('get_invite', 'GET', '/invites/:invite_code', {
       invite_code = invite_code,

    }, nil,  query)
end

function api:delete_invite(invite_code)
    return self:request('delete_invite', 'DELETE', '/invites/:invite_code', {
       invite_code = invite_code,

    })
end

function api:get_current_user()
    return self:request('get_current_user', 'GET', '/users/@me', empty_route)
end

function api:get_user(user_id)
    return self:request('get_user', 'GET', '/users/:user_id', {
        user_id = user_id,
    })
end

function api:modify_current_user(payload)
    return self:request('modify_current_user', 'PATCH', '/users/@me', empty_route, payload)
end

function api:get_current_user_guilds()
    return self:request('get_current_user_guilds', 'GET', '/users/@me/guilds', empty_route)
end

function api:leave_guild(guild_id)
    return self:request('leave_guild', 'GET', '/users/@me/guilds/:guild_id', {
       guild_id = guild_id,

    })
end

function api:create_dm(payload)
    return self:request('create_dm', 'POST', '/users/@me/channels', empty_route, payload)
end

function api:get_user_connections()
    return self:request('get_user_connections', 'GET', '/users/@me/connections', empty_route)
end

function api:create_webhook(channel_id,  payload)
    return self:request('create_webhook', 'POST', '/channels/:channel_id/webhooks', {
       channel_id = channel_id,

    }, payload)
end

function api:get_channel_webhooks(channel_id)
    return self:request('get_channel_webhooks', 'GET', '/channels/:channel_id/webhooks', {
       channel_id = channel_id,

    })
end

function api:get_guild_webhooks(guild_id)
    return self:request('get_guild_webhooks', 'GET', '/guilds/:guild_id/webhooks', {
       guild_id = guild_id,

    })
end

function api:get_webhook(webhook_id)
    return self:request('get_webhook', 'GET', '/webhooks/:webhook_id', {
       webhook_id = webhook_id,

    })
end

auth('get_webhook_with_token', 'webhook')

function api:get_webhook_with_token(webhook_id, webhook_token)
    return self:request('get_webhook_with_token', 'GET', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    })
end

function api:modify_webhook(webhook_id,  payload)
    return self:request('modify_webhook', 'POST', '/webhooks/:webhook_id', {
       webhook_id = webhook_id,

    }, payload)
end

auth('modify_webhook_with_token', 'webhook')

function api:modify_webhook_with_token(webhook_id, webhook_token, payload)
    return self:request('modify_webhook_with_token', 'POST', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token,
    }, payload)
end

function api:delete_webhook(webhook_id)
    return self:request('delete_webhook', 'DELETE', '/webhooks/:webhook_id', {
       webhook_id = webhook_id,

    })
end

auth('delete_webhook_with_token', 'webhook')

function api:delete_webhook_with_token(webhook_id, webhook_token)
    return self:request('delete_webhook_with_token', ' DELETE', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    })
end

auth('execute_webhook', 'webhook')

local WAIT = {wait = true}
local NOWAIT = {wait = false}

function api:execute_webhook(webhook_id, webhook_token, payload, wait, files)
    if files then
        merge(payload, compute_attachments(files), _ENV.attachments_resolution)
    end
    return self:request('execute_webhook', 'POST', '/webhooks/:webhook_id/:webhook_token', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    }, payload, wait and WAIT or (wait == false) and NOWAIT or nil, files)
end

auth('execute_slack_compatible_webhook', 'webhook')

function api:execute_slack_compatible_webhook(webhook_id, webhook_token, payload, query)
    return self:request('execute_slack_compatible_webhook', 'POST', '/webhooks/:webhook_id/:webhook_token/slack', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    }, payload, query)
end

auth('execute_github_compatible_webhook', 'webhook')

function api:execute_github_compatible_webhook(webhook_id, webhook_token, payload, query)
    return self:request('execute_github_compatible_webhook', 'POST', '/webhooks/:webhook_id/:webhook_token/github', {
       webhook_id = webhook_id,
       webhook_token = webhook_token
    }, payload, query)
end

auth('edit_webhook_message', 'webhook')

function api:edit_webhook_message(webhook_id, webhook_token, message_id, payload)
    return self:request('edit_webhook_message', 'PATCH', '/webhooks/:webhook_id/:webhook_token/messages/:message_id', {
       webhook_id = webhook_id,
       webhook_token = webhook_token,
       message_id = message_id
    }, payload)
end

auth('delete_webhook_message', 'webhook')

function api:delete_webhook_message(webhook_id, webhook_token, message_id)
    return self:request('delete_webhook_message', 'DELETE', '/webhooks/:webhook_id/:webhook_token/messages/:message_id', {
        webhook_id = webhook_id,
        webhook_token = webhook_token,
        message_id = message_id
     })
end

function api:list_voice_regions()
    return self:request('list_voice_regions', 'GET', '/voice/regions',empty_route)
end

function api:get_global_application_commands(application_id)
    return self:request('get_global_application_commands', 'GET', '/applications/:application_id/commands', {
       application_id = application_id
    })
end

function api:create_global_application_command(application_id,  payload)
    return self:request('create_global_application_command', 'POST', '/applications/:application_id/commands', {
       application_id = application_id
    }, payload)
end

function api:get_global_application_command(application_id, command_id)
    return self:request('get_global_application_command', 'GET', '/applications/:application_id/commands/:command_id', {
       application_id = application_id,
       command_id = command_id
    })
end

function api:edit_global_application_command(application_id, command_id, payload)
    return self:request('edit_global_application_command', 'PATCH', '/applications/:application_id/commands/:command_id', {
       application_id = application_id,
       command_id = command_id
    }, payload)
end

function api:delete_global_application_command(application_id, command_id)
    return self:request('delete_global_application_command', 'DELETE', '/applications/:application_id/commands/:command_id', {
       application_id = application_id,
       command_id = command_id
    })
end

function api:bulk_overwrite_global_application_commands(application_id, payload)
    return self:request('bulk_overwrite_global_application_commands', 'PUT', '/applications/:application_id/commands', {
       application_id = application_id
    }, payload)
end

function api:create_guild_application_command(application_id, guild_id, payload)
    return self:request('create_guild_application_command', 'POST', '/applications/:application_id/guilds/:guild_id/commands', {
       application_id = application_id,
       guild_id = guild_id
    }, payload)
end

function api:get_guild_application_command(application_id, guild_id, command_id)
    return self:request('get_guild_application_command', 'GET', '/applications/:application_id/guilds/:guild_id/commands/:command_id', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    })
end

function api:edit_guild_application_command(application_id, guild_id, command_id, payload)
    return self:request('edit_guild_application_command', 'PATCH', '/applications/:application_id/guilds/:guild_id/commands/:command_id', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    }, payload)
end

function api:delete_guild_application_command(application_id, guild_id, command_id)
    return self:request('delete_guild_application_command', 'DELETE', '/applications/:application_id/guilds/:guild_id/commands/:command_id', {
        application_id = application_id,
        guild_id = guild_id,
        command_id = command_id
    })
end

function api:get_guild_application_commands(application_id, guild_id)
    return self:request('get_guild_application_commands', 'GET', '/applications/:application_id/guilds/:guild_id/commands', {
       application_id = application_id,
       guild_id = guild_id
    })
end

function api:bulk_overwrite_guild_application_commands(application_id, guild_id, payload)
    return self:request('bulk_overwrite_guild_application_commands', 'PUT', '/applications/:application_id/guilds/:guild_id/commands', {
       application_id = application_id,
       guild_id = guild_id
    }, payload)
end

function api:get_guild_application_command_permissions(application_id, guild_id)
    return self:request('get_guild_application_command_permissions', 'GET', '/applications/:application_id/guilds/:guild_id/commands/permissions', {
       application_id = application_id,
       guild_id = guild_id
    })
end

function api:get_application_command_permissions(application_id, guild_id, command_id)
    return self:request('get_application_command_permissions', 'GET', '/applications/:application_id/guilds/:guild_id/commands/:command_id/permissions', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    })
end

function api:edit_application_command_permissions(application_id, guild_id, command_id, payload)
    return self:request('edit_application_command_permissions', 'PUT', '/applications/:application_id/guilds/:guild_id/commands/:command_id/permissions', {
       application_id = application_id,
       guild_id = guild_id,
       command_id = command_id
    }, payload)
end

if LACORD_DEPRECATED and not LACORD_UNSTABLE then
    function api:batch_edit_application_command_permissions(application_id, guild_id, payload)
        return self:request('batch_edit_application_command_permissions', 'PUT', '/applications/:application_id/guilds/:guild_id/commands/permissions', {
        application_id = application_id,
        guild_id = guild_id
        }, payload)
    end
elseif not LACORD_DEPRECATED and not LACORD_UNSTABLE then
    function api.batch_edit_application_command_permissions(state)
        logger.warn("%s cannot $batch_edit_application_command_permissions; because it has been disabled.\n See <https://discord.com/developers/docs/interactions/application-commands#permissions>.", state)
        return false, nil, "This endpoint has been disabled by discord."
    end
end

function api:get_token(data)
    return self:request('get_token', 'POST', '/oauth2/token', empty_route, data)
end

function api:get_sticker(sticker_id)
    return self:request('get_sticker', 'GET', '/stickers/:sticker_id', {
       sticker_id = sticker_id
    })
end

function api:list_nitro_sticker_packs()
    return self:request('list_nitro_sticker_packs', 'GET', '/sticker-packs', empty_route)
end

function api:list_guild_stickers(guild_id)
    return self:request('list_guild_stickers', 'GET', '/guilds/:guild_id/stickers', {
       guild_id = guild_id
    })
end

function api:get_guild_sticker(guild_id, sticker_id)
    return self:request('get_guild_sticker', 'GET', '/guilds/:guild_id/stickers/:sticker_id', {
       guild_id = guild_id,
       sticker_id = sticker_id
    })
end

function api:create_guild_sticker(guild_id,  payload, img)
    if not is_form(payload) then
        payload = a_form(payload)
    end
    return self:request('create_guild_sticker', 'POST', '/guilds/:guild_id/stickers', {
       guild_id = guild_id
    }, payload, nil, {img})
end

function api:modify_guild_sticker(guild_id, sticker_id, payload)
    return self:request('modify_guild_sticker', 'PATCH', '/guilds/:guild_id/stickers/:sticker_id', {
       guild_id = guild_id,
       sticker_id = sticker_id
    }, payload)
end

function api:delete_guild_sticker(guild_id, sticker_id)
    return self:request('delete_guild_sticker', 'DELETE', '/guilds/:guild_id/stickers/:sticker_id', {
       guild_id = guild_id,
       sticker_id = sticker_id
    })
end

function api:create_stage_instance(payload)
    return self:request('create_stage_instance', 'POST', '/stage-instances', empty_route, payload)
end

function api:get_stage_instance(channel_id)
    return self:request('get_stage_instance', 'GET', '/stage-instances/:channel_id', {
       channel_id = channel_id
    })
end

function api:modify_stage_instance(channel_id, payload)
    return self:request('modify_stage_instance', 'PATCH', '/stage-instances/:channel_id', {
       channel_id = channel_id
    }, payload)
end

function api:delete_stage_instance(channel_id)
    return self:request('delete_stage_instance', 'DELETE', '/stage-instances/:channel_id', {
       channel_id = channel_id
    })
end

function api:get_guild_template(template_code)
    return self:request('get_guild_template', 'GET', '/guilds/templates/:template_code', {
       template_code = template_code
    })
end

function api:create_guild_from_guild_template(template_code,  payload)
    return self:request('create_guild_from_guild_template', 'POST', '/guilds/templates/:template_code', {
       template_code = template_code,
    }, payload)
end

function api:get_guild_templates(guild_id)
    return self:request('get_guild_templates', 'GET', '/guilds/:guild_id/templates', {
       guild_id = guild_id
    })
end

function api:create_guild_template(guild_id,  payload)
    return self:request('create_guild_template', 'POST', '/guilds/:guild_id/templates', {
       guild_id = guild_id
    }, payload)
end

function api:sync_guild_template(guild_id, template_code, payload)
    return self:request('sync_guild_template', 'PUT', '/guilds/:guild_id/templates/:template_code', {
       guild_id = guild_id,
       template_code = template_code
    }, payload)
end

function api:modify_guild_template(guild_id, template_code, payload)
    return self:request('modify_guild_template', 'PATCH', '/guilds/:guild_id/templates/:template_code', {
       guild_id = guild_id,
       template_code
    }, payload)
end

function api:delete_guild_template(guild_id, template_code)
    return self:request('delete_guild_template', 'DELETE', '/guilds/:guild_id/templates/:template_code', {
       guild_id = guild_id,
       template_code = template_code
    })
end

function api:list_scheduled_guild_events(guild_id, query)
    return self:request('list_scheduled_guild_events', 'GET', '/guilds/:guild_id/scheduled-events', {
       guild_id = guild_id,
    }, nil,  query)
end

function api:create_scheduled_guild_event(guild_id,  payload)
    return self:request('create_scheduled_guild_event', 'POST', '/guilds/:guild_id/scheduled-events', {
       guild_id = guild_id
    }, payload)
end

function api:get_scheduled_guild_event(guild_id, event_id, query)
    return self:request('get_scheduled_guild_event', 'GET', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    }, nil, query)
end

function api:modify_scheduled_guild_event(guild_id, event_id,  payload)
    return self:request('modify_scheduled_guild_event', 'PATCH', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    }, payload)
end

function api:delete_scheduled_guild_event(guild_id, event_id)
    return self:request('delete_scheduled_guild_event', 'DELETE', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    })
end

function api:get_scheduled_guild_event_users(guild_id, event_id,  query)
    return self:request('get_scheduled_guild_event_users', 'GET', '/guilds/:guild_id/scheduled-events/:guild_scheduled_event_id/users', {
       guild_id = guild_id,
       guild_scheduled_event_id = event_id
    }, nil,  query)
end

function api:list_auto_moderation_rules(guild_id)
    return self:request('list_auto_moderation_rules', 'GET', '/guilds/:guild_id/auto-moderation/rules', {
       guild_id = guild_id,
    })
end

function api:get_auto_moderation_rule(guild_id, rule_id)
    return self:request('get_auto_moderation_rule', 'GET', '/guilds/:guild_id/auto-moderation/rules/:rule_id', {
       guild_id = guild_id,
       rule_id  = rule_id,
    })
end

function api:create_auto_moderation_rule(guild_id, payload)
    return self:request('create_auto_moderation_rule', 'POST', '/guilds/:guild_id/auto-moderation/rules', {
       guild_id = guild_id,
    }, payload)
end

function api:modify_auto_moderation_rule(guild_id, rule_id, payload)
    return self:request('modify_auto_moderation_rule', 'PATCH', '/guilds/:guild_id/auto-moderation/rules/:rule_id', {
       guild_id = guild_id,
       rule_id  = rule_id,
    }, payload)
end

function api:delete_auto_moderation_rule(guild_id,  rule_id)
    return self:request('delete_auto_moderation_rule', 'DELETE', '/guilds/:guild_id/auto-moderation/rules/:rule_id', {
       guild_id = guild_id,
       rule_id  = rule_id,
    })
end

return authorization end