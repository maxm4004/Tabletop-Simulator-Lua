VERSION = "WARFORGE - v1.36.01"
ACTIVE_RULESET = "LIONHEART"
--ACTIVE_RULESET = "DEFAULT"
SAVE_STATE = nil
DEBUG = false
army1 = "Army1"
army2 = "Army2"

require("common.constants")
require("common.utils")

require("engine.dispatcher")
require("engine.boot")
require("engine.core")
require("engine.buttonbar.loader") 
require("engine.tools.dice") 
require("engine.ui")
require("engine.input")
require("engine.conditions")
require("engine.renderers")
require("engine.measure")

require("rulesets.loader")
-- ============================================================
-- FUNZIONE: onLoad()
-- ============================================================
function onLoad(save_state)
    if DEBUG then print("onLoad") end
    warforge_boot(ACTIVE_RULESET, save_state)
end
-- ============================================================
-- FUNZIONE: onSave()
-- ============================================================
function onSave()
    if callHandler then
        return callHandler("onSave")
    end
    return ""
end
-- ============================================================
-- FUNZIONE: onChat()
-- ============================================================
    function onChat(message, player)
        return engine_handleChat(message, player)
    end