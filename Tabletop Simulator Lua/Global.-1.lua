require("common.constants")
require("common.utils")
require("engine.core")
require("engine.conditions")
require("engine.input")
require("engine.ui")
require("rulesets.lionheart.callbacks")
require("rulesets.lionheart.phases")

function onLoad()
    lionheart_initPhases()
    engine_init()
end