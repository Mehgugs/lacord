local cli_options = require"lacord.util".cli_options

local climt = {__name = "lacord.cli"}

function climt.__call(_,...)
    return cli_options(...)
end

package.preload['lacord._.cli_metatable'] = function() return climt end

return setmetatable({}, climt)