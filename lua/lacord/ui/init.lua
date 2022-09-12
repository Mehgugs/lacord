local getm   = getmetatable
local iter   = pairs
local iiter  = ipairs
local set    = rawset
local setm   = setmetatable
local type   = type

local running_coro = coroutine.running

local insert = table.insert

local dflt_env = _ENV

local cqueues     = require"cqueues"
local context     = require"lacord.models.context"
local interaction = require"lacord.models.interaction"
local numbers     = require"lacord.models.magic-numbers"
local resolve     = require"lacord.models.methods".resolve
local run_methods = require"lacord.util".run_methods

local button  = require"lacord.ui.button"
local selects = require"lacord.ui.select-menu"
local textbox = require"lacord.ui.text-box"

local monotime = cqueues.monotime
local running  = cqueues.running
local sleep    = cqueues.sleep

local types = numbers.component_type


local _ENV = {}


local interface = {__name = "lacord.ui"}
      interface.__index = interface


function new(t)
    local self = setm({_rows = {}, _actions = {}}, interface)

    if t then run_methods(self, t) end

    return self
end


local function interface_cid(self, instance)
    return (instance._id .. "." ..(self._name or ("%p"):format(self):sub(2))):sub(1, 100)
end

function interface:add(item, ...)
    if getm(item).__lacord_ui then ::top::
        if not self._current_row then
            local len = #self._rows
            if len < 5 then
                self._current_row = #self._rows + 1
                insert(self._rows, { item:upsert_id(interface_cid) })
            end
        else
            if #self._rows[self._current_row] < 25 then
                insert(self._rows[self._current_row], item:upsert_id(interface_cid))
            else
                self._current_row = nil
                goto top
            end
        end
    end
    if ... then return self:add(...) end
    return self
end


function interface:id(i) self._id = i return self end


function interface:add_row(...)
    local len = #self._rows
    if len < 5 then
        self._current_row = #self._rows + 1
        insert(self._rows, {})
        if ... then
            return self:add(...)
        end
    end
end


function interface:using_row(i, ...)
    local len = #self._rows
    if len < i then
        return self:add_row(...)
    else
        self._current_row = i
        if ... then
            return self:add(...)
        end
    end
end


function interface:add_action(name, fn)
    self._actions[name] = fn
end


local function interface_timeout(id, age) ::top::
    sleep(age - monotime())
    local ui = context.property('ui', id)
    age = ui and ui._age
    if ui and age > monotime() then
        goto top
    end

    ui = context.property('ui', id, context.DEL) or ui

    if ui._interface._actions.timeout then
        _ENV.in_environment(ui)
        ui._interface._actions.timeout(ui)
    end
end


local instance = {__name = "lacord.ui.live"}
      instance.__index = instance


function instance:__tostring()
    return ("%s: %s"):format(getm(self).__name, self._id)
end


function instance:restore(I)
    return interaction.send(I, {components = self._components})
end


function instance:store(K, V)
    self._state[K] = V
end


function instance:close(I)
    if I then I:clear() end
    return context.property('ui', self._id, context.DEL)
end

instance.stop = instance.close


function interface:new_state()
    local out = { }
    for k, v in iter(self._initial_state) do
        out[k] = v
    end
    return out
end


function interface:instance(payload, timeout, target_id, ...)
    local this = {
        _age = timeout or self._age or false,
        _interface = self,
        _actions={},
        _state=self:new_state(),
        _id = "",
        _target = type(target_id) ~= 'function' and target_id,
        _filter = type(target_id) == 'function' and target_id,
    }

    local id = self._id or ("%p"):format(this):sub(2)
    this._id = id

    setm(this, instance)
    if payload then
        local components = {}
        for i = 1, #self._rows do
            local row = self._rows[i]
            local row_out = {}
            for j = 1, #row do
                local json = getm(row[j]).__lacord_ui(row[j], this, ...)
                if self._actions[row[j]._name] then
                    this._actions[json.custom_id]
                        = row[j]._name
                end
                row_out[j] = json
            end
            components[i] = {type = types.ACTION_ROW, components = row_out}
        end

        self._components = components

        if payload.data then
            payload.data.components = components
        else
            payload.components = components
        end
    end

    context.property('ui', id, this)

    if this._age then
        running():wrap(interface_timeout, this._id, this._age)
    end

    return this
end


function interface:attach(I, timeout, msg, files, ephemeral)
    local payload = (type(msg) == 'string' and {content = msg}) or msg or {}

    if self._actions.init then
        local out = self._actions.init(timeout, payload, files, ephemeral)
        if out then
            timeout   = out.timeout or timeout
            payload   = out.payload or payload
            files     = out.files or files
            ephemeral = out.ephemeral or ephemeral
        end
    end

    local target = resolve(I, 'user')
    self:instance(payload, timeout, target.id, I, target)

    return interaction[ephemeral and 'whisper' or 'reply'](I, payload, files)
end


function interface:attach_filter(I, timeout, filter, msg, files, ephemeral)
    local payload = (type(msg) == 'string' and {content = msg}) or msg or {}

    if self._actions.init then
        local out = self._actions.init(timeout, payload, files, ephemeral)
        timeout   = out.timeout or timeout
        payload   = out.payload or payload
        files     = out.files or files
        ephemeral = out.ephemeral or ephemeral
    end

    local target = resolve(I, 'user')
    self:instance(payload, timeout, filter, I, target)

    return interaction[ephemeral and 'whisper' or 'reply'](I, payload, files)
end


function interface:attach_quietly(I, timeout, msg, files)
    return self:attach(I, timeout, msg, files, true)
end


function interface:attach_filter_quietly(I, timeout, msg, files)
    return self:attach_filter(I, timeout, msg, files, true)
end


local INTERFACE = {}
local INSTANCE = {}
local KEEP = {}


local ctors = {
    button = button.new,
    select = selects.new,
    textbox = textbox.new
}


local env2 = {__name = "lacord.ui.state"}

function env2:__index(K)
    return self[INSTANCE][running_coro()][K] or dflt_env[K]
end

function env2:__newindex(K, V)
    self[INSTANCE][running_coro()][K] = V
end


local view_helpers = {}

function view_helpers.row(self, _,_, ccomps) return function(i)
    if i then
        self[INTERFACE]:using_row(i)
    else
        self[INTERFACE]:add_row()
    end
    return ccomps
end end

function view_helpers.using(self, get_stack, set_stack) return function(i)
    local stack = get_stack()
    if stack then
        for _,comp in iiter(stack) do
            comp._name = i
            self[INTERFACE]:add(comp)
        end
        set_stack(nil)
    end
end end


local function view_ctor(interface_id)
    local env = {__name = "lacord.ui.environment"}
    local stack
    local function set_stack(s) stack = s end
    local function get_stack() return stack end
    local comps, ccomps = {}, {}

    for name, ctor in iter(ctors) do
        local function the_ctor(t)
            if stack then insert(stack, ctor(t))
            else
                stack = {ctor(t)}
            end
        end
        comps[name] = the_ctor
        ccomps[name] = function(self, t)
            if stack then
                for _,comp in iiter(stack) do
                    self[INTERFACE]:add(comp)
                end
                stack = nil
            end
            stack = {ctor(t)}
        end
    end


    function env:__newindex(key, value)
        if type(value) == 'function' then
            if stack then
                self[INTERFACE]:add_action(key, value)
                if key ~= 'init' then
                    local last
                    for _,comp in iiter(stack) do
                        comp._name = key
                        last = comp
                        self[INTERFACE]:add(comp)
                    end
                    set(self, key, last)
                    stack = nil
                end
            else
                self[INTERFACE]:add_action(key, value)
            end
        else
            local mt = getm(value)
            if mt and mt.__lacord_state_wrap then
                value = value[1]
                self[KEEP][key] = true
            end
            set(self, key, value)
        end
    end


    function env:__index(k)
        if k == 'interface' then
            local out = self[INTERFACE]
            self[INTERFACE] = nil

            local keep = self[KEEP]
            self[KEEP] = nil

            local copy = {}
            for k_ , v in iter(self) do
                self[k_] = nil
                local mt = getm(v)
                if mt and mt.__lacord_ui and not keep[k_] then goto continue end
                copy[k_] = v
                ::continue::
            end

            out._initial_state = copy

            self[INSTANCE] = setm({}, {__mode = 'k'})

            out._environment = self

            setm(self, env2)

            return out
        elseif view_helpers[k] then
            return view_helpers[k](self, get_stack, set_stack, ccomps)
        else
            return self[INTERFACE]._actions[k] or comps[k] or dflt_env[k]
        end
    end


    local out = setm({[KEEP] = {}}, env)

    out[INTERFACE] = new{id = interface_id}

    return out
end


local viewf = {ignore_t = {__lacord_state_wrap = true}}

function viewf:__call(...) return view_ctor(...) end

function viewf.ignore(v)
    return setm({v}, viewf.ignore_t)
end

_ENV.view = setm(viewf, viewf)


function in_environment(inst)
    if inst._interface._environment then
        inst._interface._environment[INSTANCE][running_coro()] = inst._state
    end
end

return _ENV