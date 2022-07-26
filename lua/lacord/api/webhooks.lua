local iter = pairs
local setm = setmetatable

local prefix = require"lacord.util".prefix


return function(module, api, auth)
    local webhook_client = {}
    webhook_client.__index = webhook_client

    for method in iter(auth.map.webhook) do
        local fn = api[method]
        webhook_client[prefix(method, '_with_token')] = function(self, ...)
            self = self[1]
            return fn(self, self.webhook_id, self.webhook_token, ...)
        end
    end

    for method in iter(auth.map.none) do
        local fn = api[method]
        webhook_client[method] = function(self, ...) self = self[1] return fn(self, ...) end
    end

    webhook_client.request = api.request

    function module.new_webhook(id, token, options)
        options = options or {}
        options.webhook = {id, token}
        local client = module.new(options)
        return setm({client}, webhook_client)
    end
end