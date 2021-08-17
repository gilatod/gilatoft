local object = require("gilatod.auxiliary.object")
local tokenizer = require("gilatod.gilatoft.compiler.tokenizer")
local compiler = require("gilatod.gilatoft.compiler")

local compile = compiler.compile

local exps1 = compile(
    "Esa ipi saecid conam pola li'limelifa. Pju'flahehat palagn necat lata gahegaf."
    -- 哪个-主格 那些-宾格 燃烧（动态无终持续体，宾格）-场景
    -- 旅行（动态有终持续体，主格）-经历者
    -- 寻找（动态有终持续体，经验貌）-第三人称主动态
    -- 幽暗地发光（静态无终持续体，宾格）-述名不定式”
)
print(object.show(exps1))

local source = "pju'flahehat palagn necat lata ga'hegaf."
local exps2 = compile(source)
--print(object.show(tokenizer.read(source)))
--print(object.show(exps2))

-- print(object.show(text))
-- print(object.show(parser.parse(text)))