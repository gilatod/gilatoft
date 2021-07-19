local control = require("gilatod.latoft.interpreter.control")

local unpack = table.unpack

local pure = control.pure
local delay = control.delay
local keys = control.keys
local map = control.map
local iterate = control.iterate

local EMPTY_TABLE = {}

local environment = setmetatable({}, {
    __call = function(self, scope, store)
        local instance = {
            entities = {},
            scope = scope or {},
            store = store or {},
            declarations = {},
            collections = {}
        }
        return setmetatable(instance, self)
    end
})
environment.__index = environment

function environment:get_scope()
    return self.scope
end

function environment:evaluate(value)
    local head = value[1]
    local func = self.scope[head]
    if not func then
        error("invalid function: "..tostring(head))
    end
    return func(self, value)
end

function environment:apply_entity(entity, constraints)
    local declare = self.declare

    local ref_args_mt = {}
    local ref_args = setmetatable(
        {n = {"id", entity}}, ref_args_mt)

    for i = 1, #constraints do
        local constraint = constraints[i]
        if type(constraint) == "table" then
            local predicate = constraint[1]
            ref_args_mt.__index = constraint[2]
            local decl_constraints = constraint[3]
            declare(self, predicate, ref_args, decl_constraints)
        else
            declare(self, constraint, ref_args)
        end
    end
end

local entity_mt = {
    __tostring = function(e)
        return e.name or "entity: "..e
    end
}

function environment:create_entity(constraints)
    local entity = setmetatable({}, entity_mt)
    self.entities[entity] = true
    if constraints then
        self:apply_entity(entity, constraints)
        local c = constraints[1]
        entity.name = type(c) == "string" and c or c[1]
    end
    return entity
end

local function check_arguments(env, decl_arguments, arguments)
    for key, argument in pairs(arguments) do
        local decl_argument = decl_arguments[key]
        if not decl_argument then return false end

        local iterator, state = iterate(env:evaluate(decl_argument))
        for _, entity in iterate(env:evaluate(argument)) do
            local success
            for _, decl_entity in iterator, state do
                if entity == decl_entity then
                    success = true
                    break
                end
            end
            if not success then
                local mt = getmetatable(entity)
                if not mt or not mt.__latoft_optional then
                    return false
                end
            end
        end
    end

    return true
end

local function do_match(env, entity, predicate, arguments)
    local entry = env.declarations[predicate]
    if not entry then return nil end

    local store = env.store
    local slot = store[predicate]

    if slot then
        local decl = slot[entity]
        if decl then
            local decl_constraints = decl[3]
            if not decl_constraints
                or env:check_constraints(decl, decl_constraints) then
                return decl
            end
            slot[entity] = nil
        end
    end

    local result

    if arguments then
        for declaration in pairs(entry) do
            local decl_arguments = declaration[2]
            local nominative = decl_arguments.n
            if nominative then
                for _, decl_entity in iterate(env:evaluate(nominative)) do
                    if decl_entity == entity and check_arguments(env, decl_arguments, arguments) then
                        local decl_constraints = declaration[3]
                        if not decl_constraints
                            or env:check_constraints(declaration, decl_constraints) then
                            result = declaration
                            goto finish
                        end
                    end
                end
            end
        end
    else
        for declaration in pairs(entry) do
            local decl_arguments = declaration[2]
            local nominative = decl_arguments.n
            if nominative then
                local success
                for _, decl_entity in iterate(env:evaluate(nominative)) do
                    if decl_entity == entity then
                        local decl_constraints = declaration[3]
                        if not decl_constraints
                            or env:check_constraints(declaration, decl_constraints) then
                            result = declaration
                            goto finish
                        end
                    end
                end
            end
        end
    end

    ::finish::

    if not result then return nil end

    if not slot then
        slot = {}
        self.store[predicate] = slot
    end

    slot[entity] = result
    return result
end

function environment:match(entity, constraint)
    if type(constraint) == "string" then
        return do_match(self, entity, constraint)
    end

    local predicate = constraint[1]
    local arguments = constraint[2]

    if type(predicate) == "table" then
        local t = {}
        for i = 1, #predicate do
            if not do_match(self, entity, predicate[i], arguments) then
                t[#t+1] = declaration
            end
        end
        return unpack(t)
    else
        return do_match(self, entity, predicate, arguments)
    end
end

function environment:check_constraints(entity, constraints)
    for i = 1, #constraints do
        if not self:match(entity, constraints[i]) then
            return false
        end
    end
    return true
end

local function select_iter(state, index)
    local env = state[1]
    local constraints = state[2]
    local slots = state[3]

    local curr_index
    local entity
    local found_entities

    if index then
        curr_index = index[1]
        entity = index[2]
        found_entities = index[3]
    else
        curr_index = 1
        found_entities = {}
    end

    local curr_slot = slots[curr_index]

    while true do
        ::next::
        entity = next(curr_slot, entity)

        if not entity then
            if curr_index >= #slots then
                return nil
            end
            curr_index = curr_index + 1
            curr_slot = slots[curr_index]
            goto next
        end

        if found_entities[entity] then
            goto next
        end
        found_entities[entity] = true

        for i = 1, #constraints do
            if not env:match(entity, constraints[i]) then
                goto next
            end
        end

        return {curr_index, entity, found_entities}, entity
    end
end

local function wrap_entity_selector(env, iterator, constraints)
    local store = env.store
    local slots = {}

    for i = 1, #constraints do
        local constraint = constraints[i]
        local predicate =
            type(constraint) == "string"
            and constraint or constraint[1]

        local slot = store[predicate]
        if slot and next(slot) then
            slots[#slots+1] = slot
        end
    end

    if #slots == 0 then
        return nil
    end
    return delay(iterator, {env, constraints, slots})
end

function environment:select(...)
    local constraints = {...}
    if #constraints == 0 then
        return keys(self.entities)
    end
    return wrap_entity_selector(self, select_iter, constraints)
end

local function realize_iter(state, index)
    if index == true then
        return nil
    end

    local new_index, entity = select_iter(state, index)

    if not new_index then
        if not index then
            entity = state[1]:create_entity(state[2])
            return true, entity
        end
        return nil
    end

    return new_index, entity
end

function environment:realize(...)
    local constraints = {...}
    if #constraints == 0 then
        return pure(self:create_entity())
    end
    return wrap_entity_selector(self, realize_iter, constraints)
        or pure(self:create_entity(constraints))
end

function environment:declare(predicate, arguments, constraints)
    local declarations = self.declarations
    local declaration = {predicate, arguments or EMPTY_TABLE, constraints}
    self.entities[declaration] = true

    local entry = declarations[predicate]
    if not entry then
        entry = {}
        declarations[predicate] = entry
    end
    entry[declaration] = true

    if arguments then
        local nominative = arguments.n
        if nominative then
            local store = self.store
            local slot = store[predicate]
            if not slot then
                slot = {}
                store[predicate] = slot
            end
            for _, entity in iterate(self:evaluate(nominative)) do
                slot[entity] = declaration
            end
        end
    end

    if constraints then
        self:apply_entity(declaration, constraints)
    end
end

function environment:assert(predicate, arguments, constraints)
    local entry = self.declarations[predicate]
    if not entry then return false end
    if not arguments then return true end

    local success, res = pcall(function()
        if constraints then
            for declaration in pairs(entry) do
                if check_arguments(self, declaration[2], arguments) then
                    local success = true
                    for i = 1, #constraints do
                        if not self:match(declaration, constraints[i]) then
                            success = false
                            break
                        end
                    end
                    if success then
                        return true
                    end
                end
            end
        else
            for declaration in pairs(entry) do
                if check_arguments(self, declaration[2], arguments) then
                    return true
                end
            end
        end
        return false
    end)

    return success and res
end

local function clear(t)
    for i = 1, #t do
        t[i] = nil
    end
end

function environment:query(predicate, arguments, constraints)
    local entry = self.declarations[predicate]
    if not entry or not arguments then return nil end

    local collections = self.collections
    local collection = {}
    collections[#collections+1] = collection

    local result = {}

    if constraints then
        for declaration in pairs(entry) do
            if check_arguments(self, declaration[2], arguments)
                and self:check_constraints(declaration, declaration[3])
                and self:check_constraints(declaration, constraints) then
                for i = 1, #collection do
                    result[#result+1] = collection[i]
                end
            end
            clear(collection)
        end
    else
        for declaration in pairs(entry) do
            if check_arguments(self, declaration[2], arguments)
                and (not declaration[3]
                    or self:check_constraints(declaration, declaration[3])) then
                for i = 1, #collection do
                    result[#result+1] = collection[i]
                end
            end
            clear(collection)
        end
    end

    collections[#collections] = nil
    return next, result
end

local collector_mt = {
    __latoft_optional = true,
    __eq = function(o1, o2)
        if o1.value == o2 then
            local c = o1.collection
            c[#c+1] = o2
            return true
        end
        return false
    end
}

function environment:collect(ctl)
    local collections = self.collections
    local collection = collections[#collections]
    return map(ctl, function(value)
        return setmetatable({
            value = value,
            collection = collection
        }, collector_mt)
    end)
end

return environment