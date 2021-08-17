local interpreter = require("gilatod.gilatoft.interpreter")

local itp = interpreter()
itp:run {"declare", "is",
    {n = {"realize", "a", "b"}},
    {{"being", {o = {"realize", "c"}}}}
}
itp:run {"assert", "is",
    {n = {"any", "a", "b"}},
    {{"being", {o = {"realize", "c"}}}}
}