local running = require"cqueues".running

local context = require"lacord.models.context"
local ctors   = require"lacord.models.impl.constructors"

return function(api, loop)
    local ctx = context.simple_context(api, ctors)
    loop = loop or running()
    if loop then
        context.attach(loop, ctx)
    end
    return ctx
end