local tokenizer = require("gilatod.latoft.compiler.tokenizer")
local parser = require("gilatod.latoft.compiler.parser")
local assembler = require("gilatod.latoft.compiler.assembler")

local io_open = io.open
local io_read = io.read

local read = tokenizer.read
local parse = parser.parse
local build = assembler.build

local compiler = {
    tokenizer = tokenizer,
    parser = parser,
    assembler = assembler
}

local function compile(source, location)
    local text = read(source, location)
    local phrases = parse(text)
    return build(phrases), phrases
end

compiler.compile = compile

compiler.compile_from = function(path)
    local file = assert(io_open(path,'r'), "cannot open file")
    local source = io_read("*a")
    file:close()
    return compile(source, path)
end

return compiler