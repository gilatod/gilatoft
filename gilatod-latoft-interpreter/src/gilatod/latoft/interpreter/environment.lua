local control = require("gilatod.latoft.interpreter.control")

local pure = control.pure
local delay = control.delay
local map = control.map
local iterate = control.iterate

local EMPTY_TABLE = {}

local environment = setmetatable({}, {
    __call = function(self, scope, store)
        local instance = {
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
            declare(self, predicate, ref_args)
        else
            declare(self, constraint, ref_args)
        end
    end
end

function environment:create_entity(constraints)
    local entity = {}
    self:apply_entity(entity, constraints)
    return entity
end

function environment:find_declaration(nominative, predicate)
    local store = self.store
    local slot = store[predicate]
    if not slot then return nil end
    return slot.entities[nominative]
end

local function check_arguments(env, decl_arguments, arguments)
    for key, argument in pairs(arguments) do
        local decl_argument = decl_arguments[key]
        if not decl_argument then return false end

        local iterator, state = iterate(env:evaluate(decl_argument))
        for _, entity in iterate(env:evaluate(argument)) do
            local success
            for _, decl_entity in iterator, state do
                if decl_entity == entity then
                    success = true
                    break
                end
            end
            if not success then
                return false
            end
        end
    end
    return true
end

local function check_complex_constraint(env, entity, predicate, arguments)
    if arguments then
        local entry = env.declarations[predicate]
        if not entry then return false end

        for declaration in pairs(entry) do
            local decl_arguments = declaration[2]
            local nominative = decl_arguments.n
            if nominative then
                local success
                for _, decl_entity in iterate(env:evaluate(nominative)) do
                    if decl_entity == entity then
                        success = true
                        break
                    end
                end
                if success and check_arguments(env, decl_arguments, arguments) then
                    return true
                end
            end
        end
    else
        local slot = env.store[predicate]
        return slot and slot[entity]
    end
end

local function check_constraint(env, entity, constraint)
    if type(constraint) == "string" then
        local slot = env.store[constraint]
        return slot and slot.entities[entity]
    end

    local predicate = constraint[1]
    local arguments = constraint[2]

    if type(predicate) == "table" then
        for i = 1, #predicate do
            if not check_complex_constraint(env, entity, predicate[i], arguments) then
                return false
            end
        end
        return true
    else
        return check_complex_constraint(env, entity, predicate, arguments)
    end
end

local function select_iter(state, entity)
    local env = state[1]
    local constraints = state[2]
    local entities = state[3]
    local excluded_index = state[4]

    local initial = entity

    while true do
        ::next::
        entity = next(entities, entity)
        if not entity then break end

        for i = 1, #constraints do
            if i ~= excluded_index
                and not check_constraint(env, entity, constraints[i]) then
                goto next
            end
        end

        return entity, entity
    end
end

function environment:select(...)
    local constraints = {...}
    local count = #constraints
    if count == 0 then return nil end

    local store = self.store

    local min_slot
    local excluded_index

    for i = 1, count do
        local constraint = constraints[i]
        local predicate =
            type(constraint) == "string"
            and constraint or constraint[1]

        local slot = store[predicate]
        if not slot or not next(slot.entities) then
            return nil
        end

        if not min_slot or min_slot.count > slot.count then
            min_slot = slot
            excluded_index = i
        end
    end

    return delay(select_iter,
        {self, constraints, min_slot.entities, excluded_index})
end


local function realize_iter(state, entity)
    if state[0] then
        state[0] = nil
        return nil
    end

    local env = state[1]
    local constraints = state[2]
    local entities = state[3]
    local excluded_index = state[4]

    local initial = entity

    while true do
        ::next::
        entity = next(entities, entity)
        if not entity then break end

        for i = 1, #constraints do
            if i ~= excluded_index
                and not check_constraint(env, entity, constraints[i]) then
                goto next
            end
        end

        return entity, entity
    end

    if not initial then
        state[0] = true
        entity = env:create_entity(constraints)
        return entity, entity
    end
end

function environment:realize(...)
    local constraints = {...}
    local count = #constraints
    if count == 0 then return pure({}) end

    local store = self.store

    local min_slot
    local excluded_index

    for i = 1, count do
        local constraint = constraints[i]
        local predicate =
            type(constraint) == "string"
            and constraint or constraint[1]

        local slot = store[predicate]
        if not slot or not next(slot.entities) then
            return pure(self:create_entity(constraints))
        end

        if not min_slot or min_slot.count > slot.count then
            min_slot = slot
            excluded_index = i
        end
    end

    return delay(realize_iter,
        {self, constraints, min_slot.entities, excluded_index})
end

function environment:declare(predicate, arguments, constraints)
    local declarations = self.declarations
    local declaration = {predicate, arguments or EMPTY_TABLE, constraints}

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
                slot = {count = 0, entities = {}}
                store[predicate] = slot
            end
            local entities = slot.entities
            for _, entity in iterate(self:evaluate(nominative)) do
                if not entities[entity] then
                    slot.count = slot.count + 1
                end
                entities[entity] = declaration
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

    if constraints then
        for declaration in pairs(entry) do
            if check_arguments(self, declaration[2], arguments) then
                local success = true
                for i = 1, #constraints do
                    if not check_constraint(self, declaration, constraints[i]) then
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
end

function environment:query(predicate, arguments, constraints)
    local collections = self.collections
    local collection = {}
    collections[#collections+1] = collection

    local res = self:assert(predicate, arguments, constraints)
    collections[#collections] = nil

    if res then return next, collection end
end

function environment:collect(ctl)
    local collections = self.collections
    return map(ctl, function(value)
        local c = collections[#collections]
        c[#c+1] = value
        return value
    end)
end

return environment