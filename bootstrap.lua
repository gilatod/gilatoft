local packages = {
    "gilatod-thirdparty",
    "gilatod-auxiliary",
    "gilatod-latoft-compiler",
    "gilatod-latoft-interpreter"
}

for _, pkg in pairs(packages) do
    package.path = package.path
        ..(";%s/src/?.lua;%s/src/?/init.lua"):format(pkg, pkg)
end

local function do_tests()
    local function test(pkg)
        local prev_path = package.path
        package.path = prev_path..(";%s/test/?.lua;%s/test/?/init.lua"):format(pkg, pkg)
        dofile(pkg.."/test/init.lua")
        package.path = prev_path
    end

    test("gilatod-latoft-compiler")
    test("gilatod-latoft-interpreter")
end

local object = require("gilatod.auxiliary.object")
local compiler = require("gilatod.latoft.compiler")
local interpreter = require("gilatod.latoft.interpreter")

local interpreter = interpreter()

local function run(source)
    local assembly, phrases = compiler.compile(source)
    print(object.show(assembly))
    return interpreter:run(assembly)
end

local function show_result(iterator, state)
    for _, res in iterator, state do
        print(res)
    end
end

run("letam lata.")
-- 存在(静态无终持续体,主格)-经历者 存在(动态无终持续体,经验貌)-第三人称单数
-- 存在之物存在。

run("Ae'a jata letam.")
-- 亚夜-主格 是(动态无终持续体,经验貌)-第三人称单数 存在(静态无终持续体,主格)-经历者
-- 亚夜是存在之物。

show_result(run("Esa lata."))
-- 单数判断代词-主格 亚夜-主格 存在(动态无终持续体,经验貌)-第三人称单数
-- 亚夜是否存在？