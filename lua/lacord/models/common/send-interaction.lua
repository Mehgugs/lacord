local responses = require"lacord.models.magic-numbers".interaction_response

local function send_inner(self, api, msg, files)
    if not self._state then
        local success, data, e = api:create_interaction_response(self.id, self.token, {
            type = responses.MESSAGE,
            data = msg
        }, files)
        if success and data then
            self._state = 'message'
            --self._empty = (not msg.content or files)
            return true
        else
            return nil, e
        end
    elseif self._state == 'message' then
        if self._ephemeral and msg then msg.flags = (msg.flags or 0) | 64 end

        local success, data, e = api:create_followup_message(self.application_id, self.token, msg, files)
        if success then return data else return nil, e end
    elseif self._state == 'loading' then
        if self._ephemeral and msg then
            msg.flags = (msg.flags or 0) | 64
        end
        local success, data, e = api:edit_original_interaction_response(self.application_id, self.token, msg, files)
        if success then
            self._state = 'message'
            --self._empty = (not msg.content or files)
            return data
        else return nil, e
        end
    end
end

return send_inner