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
    --print(object.show(assembly))
    return interpreter:run(assembly)
end

local function show_result(iterator, state)
    for _, res in iterator, state do
        print(res)
    end
end

local function decl_1()
    run("Ma letam lata.")
    -- 所有-主格 存在(静态无终持续体,主格)-经历者 存在(动态无终持续体,经验貌)-第三人称单数
    -- 所有存在之物存在。

    run("Ae'a jata letam.")
    -- 亚夜-主格 是(动态无终持续体,经验貌)-第三人称单数 存在(静态无终持续体,主格)-经历者
    -- 亚夜是存在之物。

    run("Sia'a jata letam.")
    -- 西亚-主格 是(动态无终持续体,经验貌)-第三人称单数 存在(静态无终持续体,主格)-经历者
    -- 西亚是存在之物。

    show_result(run("Ema lata."))
    -- 哪些-主格 存在(动态无终持续体,经验貌)-第三人称单数
    -- 哪些事物存在？
end

local function decl_2()
    run("Loemut Ae'a, jata bilatom.")
    -- 如果亚夜死了，（她）就是虚无的。
    show_result(run("Asa Ae'a jata bilatom."))
    -- 亚夜是否是虚无的？
    run("Ae'a loema.")
    -- 亚夜死了。
    show_result(run("Asa Ae'a jata Ae'u bilatom."))
    -- 亚夜是否是虚无的？
end

local function decl_3()
    run("Latot fema'u fenalar, fema'a jata Juri'o.")
    -- 如果一位女孩的女朋友存在，这位女孩就是百合。
    -- 存在(限定) 少女的 女朋友，少女 是 百合
    run("Via'a jata fema'a.")
    -- 未亚是女孩。
    -- 未亚 是 少女
    run("Via'u fenalar lata.")
    -- 未亚的女朋友存在。
    -- 未亚的 女朋友 存在
    show_result(run("Asa Via'a jata Juri'o."))
    -- 未亚是否是百合？
    -- 是否 未亚 是 百合
end

decl_3()