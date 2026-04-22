VERSION = "v1.35.10"
ENGINE = nil
DEBUG = false
army1 = "Army1"
army2 = "Army2"

require("common.constants")
require("common.utils")
require("engine.core")
require("engine.conditions")
require("engine.input")
require("engine.ui")
require("rulesets.lionheart.callbacks")
require("rulesets.lionheart.phases")
require("rulesets.lionheart.persistence")

colorArmy1 = COLOR.NOARMY
colorArmy2 = COLOR.NOARMY
        


-- ============================================================
-- FUNZIONE: onLoad()
-- ============================================================
    function onLoad(save_state)

        clear()
        lionheart_initPhases()

        if save_state and save_state ~= "" then
            ripristinaStato(save_state)
        end

        engine_init()

        if save_state and save_state ~= "" then
            Wait.time(function()
                ripristinaColoriPlayers()
                updateCenterPanel()
            end, 1)
        end
    end
-- ============================================================
-- FUNZIONE: onSave()
-- ============================================================
    function onSave()     
        return lionheart_onSave()
    end
-- ============================================================
-- FUNZIONE: onChat()
-- ============================================================
    function onChat(message, player)
        return engine_handleChat(message, player)
    end