local concat = table.concat

local object = {}

local control_escapes = {
    ["\a"] = "\\a",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\v"] = "\\v",
    ["\n"] = "\\n",
    ["\r"] = "\\r"
}

local function unescape_string(str, unescape_table)
    return str
        :gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub(".", unescape_table or control_escapes)
end

object.unescape_string = unescape_string

local function format_string(str)
    return "\""..unescape_string(str).."\""
end

local function is_identifier(str)
    return type(str) == "string"
        and str:match("^[_%a][_%a%d]*$")
end

object.show = function(o, initial_indent, indent)
    local t = type(o)
    local str

    if t == "string" then
        str = format_string(o)
    elseif t == "table" then
        local mt = getmetatable(o)
        if type(mt) == "table" and mt.__tostring then
            str = tostring(o)
        end
    else
        str = tostring(o)
    end

    if str then
        if initial_indent then
            initial_indent = tostring(initial_indent)
            return initial_indent..str
        else
            return str
        end
    end
    
    if indent then
        indent = tostring(indent)
    else
        indent = "    "
    end

    local root_obj = o

    -- 1. first entry of the inspected's value is the index.
    -- 2. second entry is the count the table is inspected.
    -- 3. third entry will be marked as true when count > 1 and
    --    the content of the table has been displayed.
    local inspected = {}
    local curr_index = 1

    local function inspect(o)
        if type(o) ~= "table" then
            return
        end

        local entry = inspected[o]
        if entry then
            entry[2] = entry[2] + 1
            if not entry[1] then
                entry[1] = tostring(curr_index)
                curr_index = curr_index + 1
            end
            return
        else
            inspected[o] = {nil, 1}
        end

        for k, v in next, o do
            inspect(k)
            inspect(v)
        end
    end

    inspect(root_obj)

    local buffer = {}
    local formatted_strings = {}

    local function raw_show(o, curr_indent)
        local t = type(o)

        if t == "string" then
            local str = formatted_strings[o]
            if not str then
                str = format_string(o)
                formatted_strings[o] = str
            end
            buffer[#buffer+1] = str
            return
        elseif t == "table" then
            local mt = getmetatable(o)
            if type(mt) == "table" and mt.__tostring then
                buffer[#buffer+1] = tostring(o)
                return
            end
        else
            buffer[#buffer+1] = tostring(o)
            return
        end

        local entry = inspected[o]

        -- inspected more than once
        if entry and entry[2] > 1 then
            buffer[#buffer+1] = "<"
            buffer[#buffer+1] = entry[1] -- index
            buffer[#buffer+1] = ">"

            local is_shown = entry[3]
            if is_shown then return end

            entry[3] = true
            buffer[#buffer+1] = " "
        end

        buffer[#buffer+1] = "{"
        local field_indent = curr_indent..indent

        -- array elements
        local o_len = #o
        for i = 1, o_len do
            local v = o[i]
            raw_show(v, field_indent)
            buffer[#buffer+1] = ", "
        end

        -- map elements
        local has_map_elem = false

        for k, v in next, o do
            if type(k) == "number" and k <= o_len then
                goto skip
            end

            if not has_map_elem then
                has_map_elem = true
                buffer[#buffer+1] = "\n"
            end

            buffer[#buffer+1] = field_indent

            -- format key
            if is_identifier(k) then
                buffer[#buffer+1] = k
            else
                buffer[#buffer+1] = "["
                raw_show(k, field_indent)
                buffer[#buffer+1] = "]"
            end

            buffer[#buffer+1] = " = "

            -- format value
            raw_show(v, field_indent)

            buffer[#buffer+1] = ",\n"
            ::skip::
        end

        if has_map_elem then
            buffer[#buffer] = "\n" -- overwrite last ",\n"
            buffer[#buffer+1] = curr_indent
            buffer[#buffer+1] = "}"
        elseif o_len > 0 then
            buffer[#buffer] = "}" -- overwrite last ", "
        else
            buffer[#buffer+1] = "}"
        end
    end

    if initial_indent then
        buffer[1] = initial_indent
        raw_show(root_obj, initial_indent)
    else
        raw_show(root_obj, "")
    end
    return concat(buffer)
end

object.equal = function(a, b)
    local comparisons = {}

    local function raw_equal(a, b)
        if a == b then
            return true
        end

        local a_type = type(a)
        local b_type = type(b)

        if a_type ~= b_type then
            return false
        end

        if a_type ~= "table" then
            return false
        end

        local compared_objs = comparisons[a]
        if not compared_objs then
            compared_objs = {
                -- false denotes that comparison is in progress
                [b] = false
            }
            comparisons[a] = compared_objs
        elseif compared_objs[b] == false then
            return true
        end

        for k, va in pairs(a) do
            local vb = b[k]
            if vb == nil then
                return false
            end

            if va ~= vb then
                local va_compared_objs = comparisons[va]
                if (not va_compared_objs
                    or not va_compared_objs[vb])
                    and not raw_equal(va, vb) then
                    return false
                end
            end
        end

        compared_objs[b] = true
        return true
    end

    return raw_equal(a, b)
end

object.clone = function(o)
    if type(object) ~= "table" then
        return object
    end

    local obj_copies = {}

    local function raw_copy(object)
        if type(object) ~= "table" then
            return object
        end

        local mt = getmetatable(object)
        if type(mt) ~= "table"
                or type(mt.__newindex) == "string" then
            return object
        end

        local obj_copy = obj_copies[object]
        if obj_copy then
            return obj_copy
        end

        obj_copy = {}
        obj_copies[object] = obj_copy

        for k, v in pairs(object) do
            obj_copy[raw_copy(k)] = raw_copy(v)
        end

        return setmetatable(obj_copy, mt)
    end

    return raw_copy(o)
end

return object