local control = require("gilatod.latoft.interpreter.control")
local environment = require("gilatod.latoft.interpreter.environment")

local unpack = table.unpack

local is_throw = control.is_throw
local pure = control.pure
local delay = control.delay
local throw = control.throw
local first = control.first
local group = control.group

local evaluate = environment.evaluate
local declare = environment.declare
local env_assert = environment.assert
local query = environment.query
local realize = environment.realize
local env_select = environment.select
local collect = environment.collect

local core = {}

-- control flow

core.seq = function(env, exp)
    local len = #exp
    for i = 2, len - 1 do
        local ctl = evaluate(env, exp[i])
        if is_throw(ctl) then
            return ctl
        end
    end
    return evaluate(env, exp[len])
end

core.quote = function(env, exp)
    return pure(exp[2])
end

-- predicate

core.declare = function(env, exp)
    local predicate = exp[2]
    local arguments = exp[3]
    local constraints = exp[4]

    if type(predicate) == "table" then
        for i = 1, #predicate do
            declare(env, predicate[i], arguments, constraints)
        end
    else
        declare(env, predicate, arguments, constraints)
    end
end

core.assert = function(env, exp)
    local predicate = exp[2]
    local arguments = exp[3]
    local constraints = exp[4]

    if type(predicate) == "table" then
        for i = 1, #predicate do
            if not env_assert(env, predicate[i], arguments, constraints) then
                return pure(false)
            end
        end
    else
        if not env_assert(env, predicate, arguments, constraints) then
            return pure(false)
        end
    end

    return pure(true)
end

local function multi_iter(state, index)
    index = index or {1}
    local entry_index = index[1]

    while true do
        local entry = state[entry_index]
        local sub_iterator = entry[1]
        local sub_state = entry[2]
        local key = index[2]

        local value
        key, value = sub_iterator(sub_state, key)

        if key then
            return {entry_index, key}, value
        elseif entry_index == #state then
            return nil
        end

        entry_index = entry_index + 1
    end
end

core.query = function(env, exp)
    local predicate = exp[2]
    local arguments = exp[3]
    local constraints = exp[4]

    if type(predicate) == "table" then
        local state = {}
        for i = 1, #predicate do
            state[#state+1] = {query(env, predicate[i], arguments, constraints)}
        end
        return delay(multi_iter, state)
    else
        local iterator, state = query(env, predicate, arguments, constraints)
        if iterator then
            return delay(iterator, state)
        end
    end
end

-- argument

core.realize = function(env, exp)
    return realize(env, select(2, unpack(exp)))
end

local function each(env, exp)
    return env_select(env, select(2, unpack(exp)))
end

core.any = function(env, exp)
    return first(each(env, exp))
end

core.all = function(env, exp)
    return group(each(env, exp))
end

core.each = each

core.assert_any = core.any
core.assert_all = core.all
core.assert_each = core.each

core.query_any = function(env, exp)
    return collect(env, first(each(env, exp)))
end

core.query_all = function(env, exp)
    return collect(env, group(each(env, exp)))
end

core.query_each = function(env, exp)
    return collect(env, each(env, exp))
end

return core