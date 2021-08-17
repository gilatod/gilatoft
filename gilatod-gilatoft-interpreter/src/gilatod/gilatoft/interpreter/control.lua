local control = {}

local TAG_PURE = {}
local TAG_DELAY  = {}
local TAG_THROW  = {}

control.pure = function(value)
    return {TAG_PURE, value}
end

control.delay = function(iterator, state)
    return {TAG_DELAY, iterator, state}
end

control.throw = function(message)
    return {TAG_THROW, message}
end

control.is_throw = function(ctl)
    return ctl[1] == TAG_THROW
end

local function keys_iter(state, index)
    local key = next(state, index)
    return key, key
end

control.keys = function(t)
    return {TAG_DELAY, keys_iter, t}
end

local function map_iter(state, index)
    local inner_iter = state[1]
    local inner_state = state[2]
    local mapper = state[3]

    local value
    index, value = inner_iter(inner_state, index)
    if index ~= nil then
        return index, mapper(value)
    end
end

control.map = function(ctl, mapper)
    if ctl == nil then return nil end
    local head = ctl[1]
    if head == TAG_PURE then
        return {TAG_PURE, mapper(ctl[2])}
    elseif head == TAG_DELAY then
        local iterator = ctl[2]
        local state = ctl[3]
        return {TAG_DELAY, map_iter, {iterator, state, mapper}}
    else
        return ctl
    end
end

local function unique_iter(state, index)
    local inner_iter = state[1]
    local inner_state = state[2]

    local last_value
    local found_values

    if index then
        last_index = index[1]
        found_values = index[2]
    else
        found_values = {}
    end

    local value
    while true do
        ::next::
        last_index, value = inner_iter(inner_state, last_index)

        if not last_index then
            return nil
        elseif found_values[value] then
            goto next
        end

        found_values[value] = true
        return {last_index, found_values}, value
    end
end

control.unique = function(ctl)
    if ctl == nil then return nil end
    local head = ctl[1]
    if head == TAG_PURE then
        return ctl
    elseif head == TAG_DELAY then
        local iterator = ctl[2]
        local state = ctl[3]
        return {TAG_DELAY, unique_iter, {iterator, state}}
    else
        return ctl
    end
end

local function join_iter(state, index)
    local ctl_index
    local ctl_inner_index

    if index then
        ctl_index = index[1]
        ctl_inner_index = index[2]
    else
        ctl_index = 0
    end

    local ctl

    if ctl_inner_index then
        ctl = state[ctl_index]
        local value
        ctl_inner_index, value = ctl[2](ctl[3], ctl_inner_index)
        if ctl_inner_index then
            return {ctl_index, ctl_inner_index}, value
        end
    end

    local head
    while true do
        ::next::
        ctl_index = ctl_index + 1
        if ctl_index > #state then
            return nil
        end

        ctl = state[ctl_index]
        head = ctl[1]

        if head == TAG_PURE then
            return {ctl_index}, ctl[2]
        elseif head == TAG_DELAY then
            local iterator = ctl[2]
            local state = ctl[3]

            local value
            ctl_inner_index, value = iterator(state)
            if not ctl_inner_index then
                goto next
            end
            return {ctl_index, ctl_inner_index}, value
        else
            return {ctl_index}, ctl
        end
    end
end

control.join = function(ctls)
    return {TAG_DELAY, join_iter, ctls}
end

control.first = function(ctl)
    if ctl == nil then
        return {TAG_THROW, "empty value"}
    end
    local head = ctl[1]
    if head == TAG_DELAY then
        local _, value = ctl[2](ctl[3])
        return value
            and {TAG_PURE, value}
            or {TAG_THROW, "empty value"}
    else
        return ctl
    end
end

control.group = function(ctl)
    if ctl == nil then return nil end
    local head = ctl[1]
    if head == TAG_PURE then
        return {TAG_PURE, {ctl[2]}}
    elseif head == TAG_DELAY then
        local g = {}
        for k, v in ctl[2], ctl[3] do
            g[k] = v
        end
        return {TAG_PURE, g}
    else
        return ctl
    end
end

local function empty_iter(state, index)
    return nil
end

local function pure_iter(state, index)
    if index ~= true then
        return true, state
    end
end

control.iterate = function(ctl)
    if ctl == nil then return empty_iter end
    local head = ctl[1]
    if head == TAG_PURE then
        return pure_iter, ctl[2]
    elseif head == TAG_DELAY then
        return ctl[2], ctl[3]
    elseif head == TAG_THROW then
        error(ctl[2])
    else
        error("invalid control")
    end
end

return control