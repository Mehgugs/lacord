local iiter = ipairs
local setm  = setmetatable

local run_methods = require"lacord.util".run_methods


return function (component, fields, f, ignore)

    function component:id(id)
        self._custom_id = id
        return self
    end

    function component:upsert_id(id)
        if not self._custom_id then
            self._custom_id = id
        end
        return self
    end

    function component:run(field, ...)
        if type(self[field]) == 'function' then
            return self[field](self, ...)
        end
        return self[field]
    end

    if not ignore then
        function component:disable()
            self._disabled = true
            return self
        end


        function component:enable()
            self._disabled = nil
            return self
        end
    end

    function component:clone(tt)
        local t = {}
        for key in iiter(fields) do
            t[key] = self[key]
        end
        t._custom_id = self._custom_id
        t._disabled  = self._disabled
        t._name      = self._name

        local new = setm(t, component)
        if tt then run_methods(new, tt) end
        return f and f(new, self) or new
    end
end