local environment = require("gilatod.gilatoft.interpreter.environment")
local control = require("gilatod.gilatoft.interpreter.control")
local core = require("gilatod.gilatoft.interpreter.scopes.core")

local iterate = control.iterate

local interpreter = setmetatable({}, {
    __call = function(self, env)
        local instance = {
            env = env or
                environment(setmetatable({}, {__index = core}))
        }
        return setmetatable(instance, self)
    end
})
interpreter.__index = interpreter

function interpreter:run(assembly)
    return iterate(self.env:evaluate(assembly))
end

return interpreter