local parser = {}

local function parser_error(state, message)
    local token = state.current_clause[state.token_index]
    if not token then
        error(("[parser] end of text: %s"):format(message), 0)
    end

    local metadata = token[1]
    error(("[parser] %s:%s:%s: %s"):format(
        metadata.location,
        metadata.line,
        metadata.column,
        message), 0)
end

local function next_sentence(state)
    local text = state.text
    local sentence_index = state.sentence_index

    sentence_index = sentence_index + 1
    local sentence = text[sentence_index]

    if sentence == nil then
        return false
    else
        state.current_sentence = sentence
        state.sentence_index = sentence_index
        state.current_clause = sentence[1]
        state.clause_index = 1
        state.token_index = 1
        return true
    end
end

local function next_clause(state)
    local sentence = state.current_sentence
    local clause_index = state.clause_index

    clause_index = clause_index + 1
    local clause = sentence[clause_index]

    if clause == nil then
        return false
    else
        state.current_clause = clause
        state.clause_index = clause_index
        state.token_index = 1
        return true
    end
end

local function is_clause_end(state)
    return state.token_index > #state.current_clause
end

local function read_many(state, reader)
    local list = {}
    while true do
        local result = reader(state)
        if result == nil then
            break
        end

        list[#list+1] = result

        if is_clause_end(state) then
            if not next_clause(state) then
                break
            end
        end
    end
    return #list > 0 and list or nil
end

local function read_many_(state, reader, arg)
    while true do
        if not reader(state, arg) then
            break
        end

        if is_clause_end(state) then
            if not next_clause(state) then
                break
            end
        end
    end
end

local function read_many_in_single_clause(state, reader)
    local list = {}
    while true do
        local result = reader(state)
        if result == nil then
            break
        end

        list[#list+1] = result

        if is_clause_end(state) then
            break
        end
    end
    return #list > 0 and list or nil
end

local function read_many_in_single_clause_(state, reader, arg)
    while true do
        if not reader(state, arg) then
            break
        end
        if is_clause_end(state) then
            break
        end
    end
end

local function require_table(t, k)
    local v = t[k]
    if not v then
        v = {}
        t[k] = v
    end
    return v
end

local read_predicative_phrase
local read_nonpredicative_phrase

local function raw_read_token(state, token, upper_phrase)
    local word = token[2]
    local wt = word.type

    if wt == "verb" then
        if word.subtype == "adverbial" then
            local adverbial = require_table(upper_phrase, "adverbial")
            if word.lexical_aspect[1] == "static" then
                adverbial[#adverbial+1] = token
                state.token_index = state.token_index + 1
            else
                local adv_phrase = read_nonpredicative_phrase(state, "adverbial_phrase")
                adverbial[#adverbial+1] = adv_phrase
            end
        else
            local predicative = require_table(upper_phrase, "predicative")
            predicative[#predicative+1] = token
            state.token_index = state.token_index + 1
        end
    elseif wt == "noun" then
        local case = word.case
        if case == "genitive" then
            local genitive = require_table(upper_phrase, "genitive")
            genitive[#genitive+1] = token
            state.token_index = state.token_index + 1
        else
            local argument = require_table(upper_phrase, case)

            if word.subtype == "adjective" then
                if word.lexical_aspect[1] == "static" then
                    argument[#argument+1] = token
                    state.token_index = state.token_index + 1
                else
                    argument[#argument+1] = read_nonpredicative_phrase(state, "adjective_phrase")
                end
            elseif word.subtype == "gerund" then
                if word.lexical_aspect[1] == "static" then
                    argument[#argument+1] = token
                    state.token_index = state.token_index + 1
                else
                    argument[#argument+1] = read_nonpredicative_phrase(state, "gerund_phrase")
                end
            else
                argument[#argument+1] = token
                state.token_index = state.token_index + 1
            end
        end
    else
        error("invalid word")
    end

    return true
end

local function read_token(state, upper_phrase)
    local token_index = state.token_index
    local token = state.current_clause[token_index]
    if token == nil then
        return nil
    end
    return raw_read_token(state, token, upper_phrase)
end

read_predicative_phrase = function(state)
    local ti = state.token_index
    local phrase = {
        type = "predicative_phrase",
        metadata = state.current_clause[ti][1]
    }
    read_many_(state, read_token, phrase)
    return phrase
end

local function read_nonpredicative_token(state, upper_phrase)
    local token_index = state.token_index
    local token = state.current_clause[token_index]
    if token == nil or token[2].subtype == "predicative" then
        return nil
    end
    return raw_read_token(state, token, upper_phrase)
end

read_nonpredicative_phrase = function(state, type)
    local ti = state.token_index
    local head = state.current_clause[ti]
    local phrase = {
        type = type,
        head = head,
        metadata = head[2]
    }
    state.token_index = ti + 1
    read_many_in_single_clause_(state, read_nonpredicative_token, phrase)
    return phrase
end

local function read_text(state)
    local phrases = {}

    while true do
        phrases[#phrases+1] = read_predicative_phrase(state)
        if not next_sentence(state) then
            break
        end
    end

    return phrases
end

parser.parse = function(text)
    if #text == 0 then
        return {}
    end

    return read_text {
        text = text,
        current_sentence = text[1],
        sentence_index = 1,
        current_clause = text[1][1],
        clause_index = 1,
        token_index = 1,
        stack = {}
    }
end

return parser