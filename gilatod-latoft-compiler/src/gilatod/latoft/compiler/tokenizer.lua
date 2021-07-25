local byte = string.byte
local char = string.char
local sub = string.sub
local gsub = string.gsub
local lower = string.lower
local unpack = table.unpack
local concat = table.concat

local tokenizer = {}

local BYTE_COMMA        = byte(",")
local BYTE_FULL_STOP    = byte(".")
local BYTE_LIST_START   = byte("[")
local BYTE_LIST_END     = byte("]")
local BYTE_STRING_START = byte("\"")
local BYTE_STRING_END   = byte("\"")

local RESERVED_CHARACTERS = {
    [BYTE_COMMA]        = true,
    [BYTE_FULL_STOP]    = true,
    [BYTE_LIST_START]   = true,
    [BYTE_LIST_END]     = true,
    [BYTE_STRING_START] = true,
    [BYTE_STRING_END]   = true,
    [0]                 = true
}

local BYTE_ESCAPE = byte("\\")

local RAW_ESCAPE_TABLE = {
    a = "\a", b = "\b", f = "\f", n = "\n",
    r = "\r", t = "\t", v = "\v",
    ["\\"] = "\\", ["0"] = "\0", [" "] = " ",
    ["\""] = "\"",
    ["["] = "[", ["]"] = "]"
}

local RAW_UNESCAPE_TABLE = {}
for k, v in pairs(RAW_ESCAPE_TABLE) do
    RAW_UNESCAPE_TABLE[v] = "\\"..k
end

local ESCAPE_TABLE = {}
for k, v in pairs(RAW_ESCAPE_TABLE) do
    ESCAPE_TABLE[byte(k)] = byte(v)
end

local BYTE_SPACE = byte(" ")
local BYTE_TAB   = byte("\t")
local BYTE_LF    = byte("\n")

local WHITE_CHARACTERS = {
    [BYTE_SPACE] = true,
    [BYTE_TAB]   = true,
    [BYTE_LF]    = true
}

local BYTE_A = byte("a")
local BYTE_O = byte("o")
local BYTE_U = byte("u")
local BYTE_E = byte("e")
local BYTE_I = byte("i")

local VOWELS = {
    [BYTE_A] = true,
    [BYTE_O] = true,
    [BYTE_U] = true,
    [BYTE_E] = true,
    [BYTE_I] = true
}

local BYTE_ACCENT_MARK = byte("'")
local BYTE_PROPER_NOUN_MARK = byte("'")

local PRONOUNS = {
    -- personal pronouns

    ["va"]  = {"1s", "nominative"},
    ["iva"] = {"1p", "nominative"},
    ["na"]  = {"2s", "nominative"},
    ["ina"] = {"2p", "nominative"},
    ["la"]  = {"3s", "nominative"},
    ["ila"] = {"3p", "nominative"},

    -- demonstrative pronouns

    ["ta"]  = {"this", "nominative"},
    ["ita"] = {"these", "nominative"},
    ["pa"]  = {"that", "nominative"},
    ["ipa"] = {"those", "nominative"},

    -- declarative pronouns

    ["sa"]  = {"any", "nominative"},
    ["ga"]  = {"all", "nominative"},
    ["ma"]  = {"each", "nominative"},

    -- assertive pronouns

    ["asa"]  = {"assert any", "nominative"},
    ["aga"]  = {"assert all", "nominative"},
    ["ama"]  = {"assert each", "nominative"},

    -- interrogative pronouns

    ["esa"]  = {"query any", "nominative"},
    ["ega"]  = {"query all", "nominative"},
    ["ema"]  = {"query each", "nominative"}
}

local function conjugate_pronouns(pronouns)
    local conjugated = {}
    for pron, desc in pairs(pronouns) do
        local stem = pron:sub(1, #pron - 1)
        conjugated[stem.."i"] = {desc[1], "accusative"}
        conjugated[stem.."o"] = {desc[1], "dative"}
        conjugated[stem.."u"] = {desc[1], "genitive"}
        conjugated[stem.."e"] = {desc[1], "oblique"}
    end

    for art, desc in pairs(conjugated) do
        pronouns[art] = desc
    end
end

conjugate_pronouns(PRONOUNS)

local LEXICAL_ASPECT_MARKS = {
    ["a"]  = {"dynamic", "atelic", "durative"},
    ["ae"] = {"dynamic", "atelic", "punctual"},
    ["o"]  = {"dynamic", "telic", "durative"},
    ["oe"] = {"dynamic", "telic", "punctual"},
    ["e"]  = {"static", "atelic", "durative"},
    ["ei"] = {"static", "atelic", "punctual"},
    ["i"]  = {"static", "telic", "durative"},
    ["ie"] = {"static", "telic", "punctual"}
}

local GRAMMATICAL_ASPECT_MARKS = {
    ["a"]  = "empirical",
    ["i"]  = "initial",
    ["o"]  = "progressive",
    ["u"]  = "perfective",
    ["e"]  = "continuous"
}

local LEXICAL_PREFIXES = {
    ["a"]    = "accomplished",
    ["ju"]   = "defective",
    ["bi"]   = "negative",
    ["ga"]   = "opposite",
    ["si"]   = "analogous",
    ["zu"]   = "posterior",
    ["gi"]   = "transcendental",
    ["cu"]   = "reflexive",
    ["cuta"] = "voluntary",
    ["pa"]   = "mutual",
    ["di"]   = "half",
    ["en"]   = "singular",
    ["mo"]   = "dual",
    ["sta"]  = "trial",
    ["mu"]   = "plural",
    ["na"]   = "repeat",
    ["ho"]   = "common",
    ["o"]    = "greator",
    ["li"]   = "smaller",
    ["so"]   = "orignal",
    ["lu"]   = "convergent",
    ["ca"]   = "separative",
    ["fla"]  = "transfering",
    ["la"]   = "forward",
    ["ce"]   = "backward",
    ["pju"]  = "before",
    ["si"]   = "optional",
    ["se"]   = "parrallel",
    ["me"]   = "condition",
    ["hi"]   = "reason",
    ["va"]   = "result",
    ["su"]   = "purpose",
    ["de"]   = "theme",
    ["vi"]   = "synonym"
}

local GRAMMATICAL_POSTFIXES = {
    ["n"]   = {"predicative", "active", 1},
    ["s"]   = {"predicative", "active", 2},
    ["sai"] = {"predicative", "active", 2, "honorific"},
    [0]     = {"predicative", "active", 3},
    ["vai"] = {"predicative", "active", 3, "honorific"},

    ["ni"] = {"predicative", "passive", 1},
    ["si"] = {"predicative", "passive", 2},
    ["vi"] = {"predicative", "passive", 3},

    ["nu"] = {"predicative", "employment", 1},
    ["su"] = {"predicative", "employment", 2},
    ["vu"] = {"predicative", "employment", 3},

    -- adjunct adverb

    ["f"]  = {"adverbial", "adjunct", "active"},
    ["fi"] = {"adverbial", "adjunct", "passive"},
    ["fu"] = {"adverbial", "adjunct", "employment"},

    -- determinator adverb

    ["t"]  = {"adverbial", "determinator", "active"},
    ["ti"] = {"adverbial", "determinator", "passive"},
    ["tu"] = {"adverbial", "determinator", "employment"}
}

local CASE_MARKS = {
    ["a"]  = "nominative",
    ["i"]  = "accusative",
    ["o"]  = "dative",
    ["u"]  = "genitive",
    ["e"]  = "oblique"
}

local NOUN_POSTFIXES = {
    -- infinitive verb

    ["ns"]  = {"adjective", "active"},
    ["nsi"] = {"adjective", "passive"},
    ["nsu"] = {"adjective", "employment"},

    -- gerund

    ["gn"]   = {"gerund", "active"},
    ["gni"]  = {"gerund", "passive"},
    ["gnu"] = {"gerund", "employment"},

    -- semantic role

    ["nt"] = {"role", "agent"},
    ["l"]  = {"role", "patient"},
    ["m"]  = {"role", "experiencer"},
    ["d"]  = {"role", "scene"},
    ["ft"] = {"role", "measure"},
    ["vz"] = {"role", "outcome"},
    ["g"]  = {"role", "depletion"}
}

local POSTFIXES = {}
for k, v in pairs(GRAMMATICAL_POSTFIXES) do POSTFIXES[k] = v end
for k, v in pairs(NOUN_POSTFIXES) do POSTFIXES[k] = v end

local function tokenizer_error(state, message)
    error(("[tokenizer] %s:%s:%s: %s"):format(
        state.location,
        state.line,
        state.column,
        message), 0)
end

local function read_byte(state, source)
    local index = state.index
    local cb = byte(source, index)
    if cb == nil then return nil end

    if cb == BYTE_LF then
        state.line = state.line + 1
        state.column = 1
    else
        state.column = state.column + 1
    end

    state.index = index + 1
    return cb
end

local function try_byte(state, source, cb)
    local sb = byte(source, state.index)
    if sb ~= cb then
        return nil
    else
        return read_byte(state, source)
    end
end

local function close_with_byte(state, source, cb)
    local sb = byte(source, state.index)
    if sb == nil then
        tokenizer_error(state, ("end of source ('%s' expected)")
            :format(char(cb)))
    elseif sb ~= cb then
        return nil
    else
        return read_byte(state, source)
    end
end

local function skip_white(state, source)
    while true do
        local cb = byte(source, state.index)
        if cb == nil or not WHITE_CHARACTERS[cb] then
            return
        end
        read_byte(state, source)
    end
end

local function parse_numeric_escape(state, source)
    local cb1 = byte(source, index)
    local cb2 = byte(source, index + 1)
    local cb3 = byte(source, index + 2)

    error("TODO")
end

local function read_character_byte(state, source)
    local cb = read_byte(state, source)
    if cb == nil then return nil end

    if cb == BYTE_ESCAPE then
        local escape_head = read_byte(state, source)
        if escape_head == nil then
            tokenizer_error(state, "end of source (escape character expected)")
        end
        return ESCAPE_TABLE[escape_head]
            or parse_numeric_escape(state, source)
    end

    return cb
end

local function read_string(state, source)
    if not try_byte(state, source, BYTE_STRING_START) then
        return nil
    end

    local cs = {}
    while true do
        if close_with_byte(state, source, BYTE_STRING_END) then
            break
        end
        cs[#cs+1] = read_character_byte(state, source)
    end
    return char(unpack(cs))
end

local function read_list(state, source, element_reader)
    if not try_byte(state, source, BYTE_LIST_START) then
        return nil
    end

    local es = {}
    while true do
        if close_with_byte(state, source, BYTE_LIST_END) then
            break
        end
        es[#es+1] = element_reader(state, source)
    end
    return es
end

local function read_letters(state, source)
    local cs = {}

    while true do
        local cb = byte(source, state.index)
        if cb == nil or WHITE_CHARACTERS[cb] or RESERVED_CHARACTERS[cb] then
            break
        end
        cs[#cs+1] = cb
        read_byte(state, source)
    end

    return #cs > 0 and char(unpack(cs))
end

local function calculate_stem_consonant_cluster_count(str)
    local count = 0
    local i = #str
    local cb

    while i > 0 do
        cb = byte(str, i)
        if cb == BYTE_ACCENT_MARK then
            break
        elseif not VOWELS[cb] then
            count = count + 1
            while true do
                i = i - 1
                if i <= 0 then break end
                cb = byte(str, i)
                if VOWELS[cb] then break end
            end
        end
        i = i - 1
    end

    return count
end

local function get_postfix(state, str)
    local candidate
    local candidate_type
    local candidate_desc

    local acc = ""
    local prev_cb
    local cb
    local desc

    if calculate_stem_consonant_cluster_count(str) <= 2 then
        return nil
    end

    for i = #str, 1, -1 do
        cb = byte(str, i)
        acc = char(cb)..acc

        desc = POSTFIXES[acc]
        if desc then
            candidate = acc
            candidate_desc = desc
        end
    end

    return candidate, candidate_desc
end

local function deconstruct_stem(state, stem)
    local root_lhs = ""
    local root_rhs = ""
    local mark_lhs = ""
    local mark_rhs = ""

    local cb
    local i = #stem

    if not VOWELS[byte(stem, i)] then
        tokenizer_error(state, "invalid stem: "..stem)
    end

    while i > 0 do
        cb = byte(stem, i)
        if not VOWELS[cb] then break end
        mark_rhs = char(cb)..mark_rhs
        i = i - 1
    end

    if #mark_rhs == 0 then
        return nil, 2
    end

    while i > 0 do
        cb = byte(stem, i)
        if VOWELS[cb] then break end
        root_rhs = char(cb)..root_rhs
        i = i - 1
    end

    if #root_rhs == 0 then
        tokenizer_error(state, "invalid word root")
    end

    while i > 0 do
        cb = byte(stem, i)
        if not VOWELS[cb] then break end
        mark_lhs = char(cb)..mark_lhs
        i = i - 1
    end

    if #mark_lhs == 0 then
        return nil, 1
    end

    while i > 0 do
        cb = byte(stem, i)
        if VOWELS[cb] then break end
        root_lhs = char(cb)..root_lhs
        i = i - 1
    end

    if #root_lhs == 0 then
        tokenizer_error(state, "invalid word root")
    end

    return sub(stem, 1, i)..root_lhs.."."..root_rhs..".",
        mark_lhs, mark_rhs
end

local function read_token(state, source)
    local metadata = {
        location = state.location,
        index = state.index,
        line = state.line,
        column = state.column
    }

    local raw = read_letters(state, source)
    if not raw then return nil end

    local word_cache = state.word_cache
    local cache = word_cache[raw]
    if cache then
        return {metadata, cache}
    end

    local w = {}
    local token = {metadata, w}

    if byte(raw, #raw-1) == BYTE_PROPER_NOUN_MARK then
        local case = CASE_MARKS[char(byte(raw, #raw))]
        w.type = "noun"
        w.subtype = "proper"
        w.raw = raw
        w.stem = sub(raw, 1, #raw - 2)
        w.case = case
        word_cache[raw] = w
        return token
    end

    raw = lower(raw)
    w.raw = raw
    word_cache[raw] = w

    local pron_desc = PRONOUNS[raw]
    if pron_desc then
        w.type = "noun"
        w.subtype = "pronoun"
        w.case = pron_desc[2]
        w.detail = pron_desc
        w.root = sub(raw, 1, #raw-1).."."
        return token
    end

    local num = tonumber(raw)
    if num then
        w.type = "noun"
        w.subtype = "number"
        w.number = num
        return token
    end

    local postfix, desc = get_postfix(state, raw)
    if postfix then
        raw = sub(raw, 1, #raw - #postfix)
        w.stem = raw
        w.subtype = desc[1]
        w.detail = desc

        if NOUN_POSTFIXES[postfix] then
            w.type = "noun"
        else
            w.type = "verb"
        end
    else
        w.type = "verb"
        w.stem = raw

        local desc = GRAMMATICAL_POSTFIXES[0]
        w.subtype = desc[1]
        w.detail = desc
    end

    if w.type == "verb" then
        local root, la, ga = deconstruct_stem(state, raw)
        if root == nil then
            tokenizer_error(state, la == 1
                and "lexical aspect mark required"
                or "grammatical aspect mark required")
        end

        local la_desc = LEXICAL_ASPECT_MARKS[la]
        local ga_desc = GRAMMATICAL_ASPECT_MARKS[ga]

        if not la_desc then
            tokenizer_error(state, "invalid lexical aspect mark: "..la)
        elseif not ga_desc then
            tokenizer_error(state, "invalid grammatical aspect mark: "..ga)
        end

        w.root = root
        w.lexical_aspect = la_desc
        w.grammatical_aspect = ga_desc
    elseif w.type == "noun" then
        local root, la, cs = deconstruct_stem(state, raw)
        if root == nil then
            tokenizer_error(state, la == 1
                and "lexical aspect mark required"
                or "case mark required")
        end

        local la_desc = LEXICAL_ASPECT_MARKS[la]
        local cs_desc = CASE_MARKS[cs]

        if not la_desc then
            tokenizer_error(state, "invalid lexical aspect mark: "..la)
        elseif not cs_desc then
            tokenizer_error(state, "invalid case mark: "..cs)
        end

        w.root = root
        w.lexical_aspect = la_desc
        w.case = cs_desc
    end

    return token
end

local function read_sentence(state, source)
    local clause = {}
    local sentence = {
        type = "sentence",
        clause
    }

    while true do
        skip_white(state, source)

        if close_with_byte(state, source, BYTE_FULL_STOP) then
            break
        elseif close_with_byte(state, source, BYTE_COMMA) then
            if #clause ~= 0 then
                clause = {}
                sentence[#sentence+1] = clause
            end
        else
            clause[#clause+1] =
                read_token(state, source)
                or read_string(state, source)
                or read_list(state, source, read_sentence)
                or tokenizer_error(state,
                    "unrecorgnized character"..byte(source, state.index))
        end
    end

    if #sentence == 1 and #clause == 0 then
        return nil
    end

    return sentence
end

local function read_text(state, source)
    local text = {
        type = "text"
    }
    
    while true do
        skip_white(state, source)
        if state.index > #source then
            break
        end
        text[#text+1] = read_sentence(state, source)
    end

    return text
end

tokenizer.read = function(source, location)
    return read_text({
        index = 1,
        line = 1,
        column = 1,
        location = location or "[source]",
        word_cache = {}
    }, source)
end

return tokenizer