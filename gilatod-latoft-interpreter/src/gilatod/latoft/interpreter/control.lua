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

local function map_iter(state, index)
    local inner_iterator = state[1]
    local inner_state = state[2]
    local mapper = state[3]

    local value
    index, value = inner_iterator(inner_state, index)
    return index, mapper(value)
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