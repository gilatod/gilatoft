local max = math.max

local assembler = {}

local function assembler_error(metadata, message)
    error(("[assembler] %s:%s:%s: %s"):format(
        metadata.location,
        metadata.line,
        metadata.column,
        message), 0)
end

local PRONOUN_MAP = {
    -- personal pronouns

    ["v."]  = {"#1", "any"},
    ["iv."] = {"#1", "all"},
    ["n."]  = {"#2", "any"},
    ["in."] = {"#2", "all"},
    ["l."]  = {"#3", "any"},
    ["il."] = {"#3", "all"},

    -- demonstrative pronouns

    ["t."]  = {"#t", "any"},
    ["it."] = {"#t", "all"},
    ["p."]  = {"#p", "any"},
    ["ip."] = {"#p", "all"},

    -- declarative pronouns

    ["s."] = {nil, "any"},
    ["g."] = {nil, "all"},
    ["m."] = {nil, "each"},

    -- assertive pronouns

    ["as."] = {nil, "assert_any"},
    ["ag."] = {nil, "assert_all"},
    ["am."] = {nil, "assert_each"},

    -- interrogative pronouns

    ["es."] = {nil, "query_any"},
    ["eg."] = {nil, "query_all"},
    ["em."] = {nil, "query_each"}
}

local PERSON_MAP = {
    "#1", "#2", "#3"
}

local COMMAND_TYPES = {
    -- 1: declarative
    ["realize"] = 1,
    ["any"] = 1,
    ["all"] = 1,
    ["each"] = 1,

    -- 2: assertive
    ["assert_any"] = 2,
    ["assert_all"] = 2,
    ["assert_each"] = 2,

    -- 3: interrogative
    ["query_any"] = 3,
    ["query_all"] = 3,
    ["query_each"] = 3
}

local ROLE_MAP = {
    ["agent"] = ":a",
    ["patient"] = ":p",
    ["experiencer"] = ":e",
    ["scene"] = ":s",
    ["measure"] = ":m",
    ["outcome"] = ":o",
    ["depletion"] = ":d"
}

local build_adjective_phrase
local build_gerund_phrase
local build_adverbial_phrase

local function build_simple_constraint(state, word)
    local adverb_type = word.detail[2]
    if adverb_type == "adjunct" then
        return word.stem
    else -- determinator
        return {word.stem, {virtual = true}}
    end
end

local function build_constraints(state, adverbial)
    if not adverbial then return nil end

    local c = {}

    for i = 1, #adverbial do
        local comp = adverbial[i]
        local comp_t = comp.type
        if comp_t == "adverbial_phrase" then
            c[#c+1] = build_adverbial_phrase(state, comp)
        else
            c[#c+1] = build_simple_constraint(state, comp[2])
        end
    end

    return c
end

local function build_argument(state, argument)
    if not argument then return nil end

    local cmd = "realize"
    local exp = {0}

    for i = 1, #argument do
        local comp = argument[i]
        local comp_t = comp.type

        if comp_t == "adjective_phrase" then
            exp[#exp+1] = build_adjective_phrase(state, comp)
        elseif comp_t == "gerund_phrase" then
            exp[#exp+1] = build_gerund_phrase(state, comp)
        else
            local noun = comp[2]
            if noun.subtype == "pronoun" then
                local root = noun.root
                local entry = PRONOUN_MAP[root]
                if not entry then
                    local meta = comp[1]
                    assembler_error(meta, "unrecognized pronoun '"..noun.raw.."'")
                end
                local tag = entry[1]
                if tag then exp[#exp+1] = tag end
                cmd = entry[2]
            else
                local detail = noun.detail
                if detail and detail[1] == "role" then
                    exp[#exp+1] = noun.root..ROLE_MAP[detail[2]]
                else
                    exp[#exp+1] = noun.stem
                end
            end
        end
    end

    exp[1] = cmd
    return exp
end

local function raw_build_nonpredicative_phrase(state, phrase, head)
    local nominative = build_argument(state, phrase.nominative)
    local arguments = {
        n = nominative,
        a = build_argument(state, phrase.accusative),
        d = build_argument(state, phrase.dative),
        g = build_argument(state, phrase.genitive),
        o = build_argument(state, phrase.oblique)
    }

    if nominative then
        nominative[#nominative+1] = "#3"
    end

    if not next(arguments) then
        arguments = nil
    end

    return {head.root, arguments,
        build_constraints(state, phrase.adverbial)}
end

build_adjective_phrase = function(state, phrase)
    return raw_build_nonpredicative_phrase(
        state, phrase, phrase.head[2])
end

build_adverbial_phrase = function(state, phrase)
    local head = phrase.head[2]
    local exp = raw_build_nonpredicative_phrase(
        state, phrase, head)

    local adverb_type = head.detail[2]
    if adverb_type == "determinator" then
        local arguments = exp[2]
        arguments.virtual = true
    end

    return exp
end

local function raw_build_predicative_phrase(state, phrase, center)
    local cmd = "declare"

    local n = build_argument(state, phrase.nominative)
    local a = build_argument(state, phrase.accusative)
    local d = build_argument(state, phrase.dative)
    local g = build_argument(state, phrase.genitive)
    local o = build_argument(state, phrase.oblique)

    local person = PERSON_MAP[center.detail[3]]
    if n then
        n[#n+1] = person
    else
        n = {"any", person}
    end

    local cmd_t = 0
    if n then cmd_t = max(cmd_t, COMMAND_TYPES[n[1]]) end
    if a then cmd_t = max(cmd_t, COMMAND_TYPES[a[1]]) end
    if d then cmd_t = max(cmd_t, COMMAND_TYPES[d[1]]) end
    if g then cmd_t = max(cmd_t, COMMAND_TYPES[g[1]]) end
    if o then cmd_t = max(cmd_t, COMMAND_TYPES[o[1]]) end

    if cmd_t == 2 then
        cmd = "assert"
    elseif cmd_t == 3 then
        cmd = "query"
    end

    local arguments
    if cmd_t ~= 0 then
        arguments = {n = n, a = a, d = d, g = g, o = o} 
    end

    if center.type then
        center = center.root
    else
        for i = 1, #center do
            local pred = center[i]
            center[i] = pred.root
        end
    end

    return {cmd, center, arguments,
        build_constraints(state, phrase.adverbial)}
end

build_gerund_phrase = function(state, phrase)
    return {"quote",
        raw_build_predicative_phrase(state, phrase, phrase.head[2])}
end

local function build_predicative_phrase(state, phrase)
    local predicative = phrase.predicative
    if #predicative > 1 then
        local center = {}
        for i = 1, #predicative do
            center[#center+1] = predicative[i][2]
        end
        return raw_build_predicative_phrase(state, phrase, center)
    else
        return raw_build_predicative_phrase(state, phrase, predicative[1][2])
    end
end

assembler.build = function(phrases)
    local state = {}
    local exp = {0}

    for i = 1, #phrases do
        local phrase = phrases[i]
        state.outermost_phrase = phrase
        if phrase.type ~= "predicative_phrase" then
            assembler_error(phrase.metadata, "outermost phrase must be predicative")
        end
        exp[i+1] = build_predicative_phrase(state, phrase)
    end

    if #exp == 2 then
        return exp[2]
    else
        exp[1] = "seq"
    end
    return exp
end

return assembler