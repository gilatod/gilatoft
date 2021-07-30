local control = require("gilatod.latoft.interpreter.control")

local unpack = table.unpack

local pure = control.pure
local delay = control.delay
local keys = control.keys
local map = control.map
local iterate = control.iterate

local EMPTY_TABLE = {}
local MAIN_ARGUMENTS = {"n", "a", "d", "g", "o"}
local MAIN_ARGUMENTS_COUNT = #MAIN_ARGUMENTS

local environment = setmetatable({}, {
    __call = function(self, scope, store)
        local instance = {
            max_slot_size = 2048,
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

local entity_mt = {
    __tostring = function(e)
        return e.name or "entity: "..e
    end
}

local function check_argument(env, argument, decl_argument)
    local head = decl_argument[1]

    if head == "realize" or head == "each" then
        local constraints = {select(2, unpack(decl_argument))}
        for _, entity in iterate(env:evaluate(argument)) do
            if not env:check_constraints(entity, constraints) then
                local mt = getmetatable(entity)
                if not mt or not mt.__latoft_optional then
                    return false
                end
            end
        end
    else
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

local function check_arguments(env, arguments, decl_arguments)
    if not arguments then return true end
    decl_arguments = decl_arguments or EMPTY_TABLE

    local i = 0
    local key, argument

    while true do
        ::continue::
        i = i + 1
        if i > MAIN_ARGUMENTS_COUNT then break end

        key = MAIN_ARGUMENTS[i]
        argument = arguments[key]
        if not argument then goto continue end

        local decl_argument = decl_arguments[key]
        if not decl_argument
            or not check_argument(env, argument, decl_argument) then
            return false
        end
    end

    return true
end

local function raw_record_store(env, queue, entity, declaration)
    local max_slot_size = env.max_slot_size

    local front = queue.front
    local rear = (queue.rear + 1) % max_slot_size
    queue[rear] = {entity, declaration}
    queue.rear = rear
    
    if rear == front then
        front = (front + 1) % max_slot_size
    elseif front == 0 then
        front = 1
    end

    queue.front = front
    queue.rear = rear
end

local function record_store(env, entity, predicate, declaration)
    local store = env.store
    local queue = store[predicate]
    if not queue then
        queue = {front = 0, rear = 0}
        store[predicate] = queue
    end
    raw_record_store(env, queue, entity, declaration)
end

local function multi_record_store(env, entities, predicate, declaration)
    local store = env.store
    local queue = store[predicate]
    if not queue then
        queue = {front = 0, rear = 0}
        store[predicate] = queue
    end
    for entity in iterate(entities) do
        raw_record_store(env, queue, entity, declaration)
    end
end

local function match_store(env, entity, predicate, arguments, constraints)
    local queue = env.store[predicate]
    if not queue then return nil end

    local max_slot_size = env.max_slot_size
    for i = queue.rear, queue.front, -1 do
        if i == 0 then
            i = max_slot_size
        end

        local entry = queue[i]
        local target_entity = entry[1]
        local declaration = entry[2]

        if entity == target_entity
            and check_arguments(env, arguments, declaration[2])
            and env:check_constraints(declaration, declaration[3])
            and env:check_constraints(declaration, constraints) then
            -- reinforce memory
            raw_record_store(env, queue, target_entity, declaration)
            return declaration
        end
    end
end

local EXIST_DECLARATION = {"j.t."}
local OTHER_DECLARATION = {"#3"}

local function make_exist(env, entity, target)
    record_store(env, entity, "j.t.", EXIST_DECLARATION)
    record_store(env, entity, "#3", OTHER_DECLARATION)
end

local function make_exist_categorized(env, entity, target, ...)
    -- TODO: improve this
    record_store(env, entity, "j.t.",
        {"j.t.", {d = {"realize", ...}}})
    record_store(env, entity, "#3", OTHER_DECLARATION)
end

function environment:create_entity(constraints)
    local entity = setmetatable({}, entity_mt)
    if constraints then
        self:apply_constraints(entity, constraints)
        local c = constraints[1]
        entity.name = type(c) == "string" and c or c[1]
    end
    make_exist(self, entity)
    return entity
end

function environment:apply_constraint(entity, constraint)
    if type(constraint) == "table" then
        local predicate = constraint[1]
        local arguments = constraint[2] or EMPTY_TABLE
        local subconstraints = constraint[3]

        if not arguments.virtual then
            local nominative = arguments.n
            if nominative then
                multi_record_store(
                    self, self:evaluate(nominative), predicate, constraint)
            else
                record_store(self, entity, predicate, constraint)
            end
            if subconstraints then
                self:apply_constraints(constraint, subconstraints)
            end
        end
    else
        record_store(self, entity, constraint, {constraint})
    end

    make_exist_categorized(self, constraint, "#constraint")
end

function environment:apply_constraints(entity, constraints)
    for i = 1, #constraints do
        self:apply_constraint(entity, constraints[i])
    end
end

local function do_check_constraint(env, entity, predicate, arguments, constraints)
    local result = match_store(
        env, entity, predicate, arguments, constraints)
    if result then return result end

    local entry = env.declarations[predicate]
    if not entry then return nil end

    local result_entity

    if arguments then
        for declaration in pairs(entry) do
            local decl_arguments = declaration[2]
            if decl_arguments and decl_arguments.n then
                for _, decl_entity in iterate(env:evaluate(decl_arguments.n)) do
                    if entity == decl_entity
                        and check_arguments(env, arguments, decl_arguments)
                        and env:check_constraints(declaration, declaration[3])
                        and env:check_constraints(declaration, constraints) then
                        result = declaration
                        result_entity = decl_entity
                        goto finish
                    end
                end
            end
        end
    else
        for declaration in pairs(entry) do
            local decl_arguments = declaration[2]
            if decl_arguments and decl_arguments.n then
                local success
                for _, decl_entity in iterate(env:evaluate(decl_arguments.n)) do
                    if entity == decl_entity
                        and env:check_constraints(declaration, declaration[3])
                        and env:check_constraints(declaration, constraints) then
                        result = declaration
                        result_entity = decl_entity
                        goto finish
                    end
                end
            end
        end
    end

    ::finish::
    if not result then return nil end

    record_store(env, result_entity, predicate, declaration)
    return result
end

function environment:check_constraint(entity, constraint)
    if type(constraint) == "string" then
        return do_check_constraint(self, entity, constraint)
    end

    local predicate = constraint[1]
    local arguments = constraint[2]
    local subconstraints = constraint[3]

    if arguments and arguments.n then
        return self:assert(predicate, arguments, subconstraints)
    end

    if type(predicate) == "table" then
        local t = {}
        for i = 1, #predicate do
            if not do_check_constraint(
                self, entity, predicate[i], arguments, subconstraints) then
                t[#t+1] = declaration
            end
        end
        return unpack(t)
    else
        return do_check_constraint(
            self, entity, predicate, arguments, subconstraints)
    end
end

function environment:check_constraints(entity, constraints)
    if not constraints then return true end
    for i = 1, #constraints do
        if not self:check_constraint(entity, constraints[i]) then
            return false
        end
    end
    return true
end

local function make_entity_iterator(handler)
    return function(state, index)
        local env = state[1]
        local constraints = state[2]
        local queues = state[3]

        local curr_queue_index
        local curr_entry_index
        local found_entities

        if index then
            curr_queue_index = index[1]
            curr_entry_index = index[2]
            found_entities = index[3]
        else
            curr_queue_index = 1
            curr_entry_index = queues[1][1].rear
            found_entities = {}
        end

        local pair = queues[curr_queue_index]
        local curr_queue = pair[1]
        local curr_constraint = pair[2]

        local max_slot_size = env.max_slot_size

        while true do
            for i = curr_entry_index, curr_queue.front, -1 do
                if i == 0 then i = max_slot_size end
                entity = curr_queue[i][1]
                if not found_entities[entity] then
                    found_entities[entity] = true
                    if handler(env, entity, curr_constraint, constraints) then
                        return {curr_queue_index, i, found_entities}, entity
                    end
                end
            end

            if curr_queue_index >= #queues then
                return nil
            end

            curr_queue_index = curr_queue_index + 1
            pair = queues[curr_queue_index]
            curr_queue = pair[1]
            curr_constraint = pair[2]
            curr_entry_index = curr_queue.rear
        end
    end
end

local select_iter = make_entity_iterator(function(env, entity, curr_constraint, constraints)
    for i = 1, #constraints do
        local constraint = constraints[i]
        if curr_constraint ~= constraint 
            and not env:check_constraint(entity, constraints[i]) then
            return false
        end
    end
    return true
end)

local function wrap_entity_selector(env, iterator, constraints)
    local store = env.store
    local queues = {}

    for i = 1, #constraints do
        local constraint = constraints[i]
        local predicate =
            type(constraint) == "string"
            and constraint or constraint[1]

        local queue = store[predicate]
        if queue and queue.front ~= 0 then
            queues[#queues+1] = {queue, constraint}
        end
    end
    return #queues ~= 0
        and delay(iterator, {env, constraints, queues})
        or nil
end

function environment:select(...)
    local constraints = {...}
    if #constraints == 0 then
        constraints[1] = "#3"
    end
    return wrap_entity_selector(self, select_iter, constraints)
end

local function realize_iter(state, index)
    if index == true then
        return nil
    end

    local new_index, value = select_iter(state, index)
    if new_index then return new_index, value end
    if index then return nil end

    return true, state[1]:create_entity(state[2])
end

function environment:realize(...)
    local constraints = {...}
    return wrap_entity_selector(self, realize_iter, constraints)
        or pure(self:create_entity(constraints))
end

function environment:declare(predicate, arguments, constraints)
    local declarations = self.declarations
    local declaration = setmetatable({
        predicate, arguments, constraints,
        name = "declaration: "..predicate
    }, entity_mt)

    local entry = declarations[predicate]
    if not entry then
        entry = {}
        declarations[predicate] = entry
    end
    entry[declaration] = true
    
    make_exist_categorized(self, declaration, "#declaration")

    if constraints then
        self:apply_constraints(declaration, constraints)
    end

    if arguments and arguments.n then
        if constraints then
            for i = 1, #constraints do
                local constraint = constraints[i]
                local arguments = constraint[2]
                if arguments and arguments.virtual
                    and not self:check_constraint(declaration, constraint) then
                    goto skip
                end
            end
        end
        for _, entity in iterate(self:evaluate(arguments.n)) do
            record_store(self, entity, predicate, declaration)
        end
    end

    ::skip::
    return declaration
end

function environment:undeclare_all(predicate)
    local store = self.store
    if store[predicate] then
        store[predicate] = nil
    end

    local declarations = self.declarations
    if declarations[predicate] then
        declarations[predicate] =  nil
    end
end

function environment:assert(predicate, arguments, constraints)
    local entry = self.declarations[predicate]
    if not entry then return nil end

    local success, res = pcall(function()
        if constraints then
            for declaration in pairs(entry) do
                if check_arguments(self, arguments, declaration[2])
                    and self:check_constraints(declaration, declaration[3])
                    and self:check_constraints(declaration, constraints) then
                    return declaration
                end
            end
        else
            for declaration in pairs(entry) do
                if check_arguments(self, arguments, declaration[2])
                    and self:check_constraints(declaration, declaration[3]) then
                    return declaration
                end
            end
        end
    end)

    return success and res
end

local function clear(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function query_iter(state, index)
    local env = state[1]
    local entry = state[2]
    local arguments = state[3]
    local constraints = state[4]

    local curr_declaration
    local curr_collection
    local curr_entity

    if index then
        curr_declaration = index[1]
        curr_collection = index[2]
        curr_entity = index[3]
    else
        curr_collection = {}
        local collections = env.collections
        collections[#collections+1] = curr_collection
    end

    if curr_entity then
        curr_entity = next(curr_collection, curr_entity)
        if curr_entity then
            return {curr_declaration, curr_collection, curr_entity}, curr_entity
        else
            clear(curr_collection)
        end
    end

    while true do
        curr_declaration = next(entry, curr_declaration)
        if not curr_declaration then
            break
        end
        if check_arguments(env, arguments, curr_declaration[2])
            and env:check_constraints(curr_declaration, curr_declaration[3])
            and env:check_constraints(curr_declaration, constraints) then
            curr_entity = next(curr_collection)
            return {curr_declaration, curr_collection, curr_entity}, curr_entity
        end
    end

    local collections = env.collections
    collections[#collections] = nil
end

function environment:query(predicate, arguments, constraints)
    local entry = self.declarations[predicate]
    if not entry then return nil end
    return delay(query_iter, {self, entry, arguments, constraints})
end

local collector_mt = {
    __latoft_optional = true,
    __eq = function(e1, e2)
        if e1.value == e2 then
            e1.collection[e2] = true
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