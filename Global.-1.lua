-- ============================================================
-- LIONHEART BOT - Tabletop Simulator
VERSION = "v1.31.02"
DEBUG   = false  -- false = controlli player attivi
-- Comandi chat:
--   !inizia      -> scansiona il tavolo
--   !turno       -> avvia/avanza sequenza di gioco
--   !fase        -> conferma fine fase e passa alla successiva
--   !wounds N    -> registra N ferite sulla base selezionata
--   !reset       -> azzera ferite sulla base selezionata
--   !visual      -> mostra nome oggetto selezionato
--   !pos         -> mostra posizione oggetto selezionato
--   !stato       -> mostra stato battaglia
--   !croce       -> mostra croce di riferimento sul tavolo
--   !croce off   -> rimuove croce
--   !deploy      -> carica eserciti e scansiona
--   !linee       -> mostra linee di schieramento
--   !linee off   -> rimuove linee di schieramento
-- ============================================================

-- ------------------------------------------------------------
-- CONFIGURAZIONE PRE-PARTITA
-- ------------------------------------------------------------
-- (ARMY[1].tag or "ARMY1")/(ARMY[2].tag or "ARMY2") sono alias per compatibilita
TAG_1 = function() return (ARMY[1].tag or "ARMY1") end
TAG_2 = function() return (ARMY[2].tag or "ARMY2") end

-- Modalita visualizzazione ferite: "highlight" o "tint"
VISUALIZZAZIONE_FERITE = "highlight"

-- ------------------------------------------------------------
-- COORDINATE TAVOLO NERO
-- Centro: X=0, Y=3.34, Z=0
-- Angoli approssimativi: X=±86, Z=±64
-- ------------------------------------------------------------
TAVOLO_Y  = 3.35
TAVOLO_LX = 90
TAVOLO_LZ = 68

-- ------------------------------------------------------------
-- COORDINATE VERDE
-- Centro: X=0, Y=2.34, Z=0
-- Angoli: X=±48, Z=±32.23
-- Scala: 1 cm regolamento = 0.8 unita TTS
-- Deploy: 10 cm = 8 unita TTS dal bordo
-- ------------------------------------------------------------
VERDE_Y       = 2.36
VERDE_Y_LINEE = 3.36  -- altezza linee deploy sopra il verde (Y + 1)
VERDE_LX      = 46
VERDE_LZ      = 32.23
DEPLOY_CM     = 8    -- 10 cm in unita TTS

-- GUID delle Hidden Zone (trovate dinamicamente per nome)
ZONA_1_GUID = nil
ZONA_2_GUID = nil

-- ------------------------------------------------------------
-- FUNZIONE: trovaZona(tag)
-- Trova una Hidden/Scripting Zone per tag
-- ------------------------------------------------------------
function trovaZona(tag)
    for _, obj in ipairs(getAllObjects()) do
        local tags = obj.getTags()
        for _, t in ipairs(tags) do
            if t == tag then return obj.getGUID() end
        end
    end
    printToAll("[ZONA] Non trovata con tag: " .. tag, {r=1,g=0.3,b=0.3})
    return nil
end

-- Struttura eserciti
ARMY = {
    [1] = { player = nil, tag = nil, nome = nil, nome_breve = nil, color = nil, pannello_guid = nil },
    [2] = { player = nil, tag = nil, nome = nil, nome_breve = nil, color = nil, pannello_guid = nil }
}

-- Posizioni pannelli informativi
PANNELLO_POS = {
    [1] = {x=-60.92, y=1.66, z=-41.71},
    [2] = {x= 60.92, y=1.66, z= 41.71}
}

-- Associazione colore -> slot army
ARMY_COLORS = {
    ["Red"]   = 1,  -- Z negativa
    ["Green"] = 2,  -- Z positiva
}

-- Posizioni spawn eserciti
-- Base URL repository JSON
GITHUB_BASE_URL = "https://raw.githubusercontent.com/maxm4004/Tabletop-Simulator-Lua/refs/heads/main/ArmyJson/"

ARMY1_URL = GITHUB_BASE_URL .. "francesi.json"
ARMY2_URL = GITHUB_BASE_URL .. "inglesi.json"

SPAWN_POS = {
    [1] = {x=0, y=2.36, z=-47.00},
    [2] = {x=0, y=2.36, z= 47.00}
}

-- ------------------------------------------------------------
pronto_red       = false   -- Red ha premuto PRONTO
pronto_green     = false   -- Green ha premuto PRONTO
deploy_fatto     = false   -- !deploy è stato eseguito almeno una volta
segnalini_guids  = {}      -- sfere rosse basi fuori zona

-- Sequenza fasi
FASI = {
    {nome="INIZIATIVA", desc="Lanciate entrambi 1D6 — chi vince sceglie se muovere primo o secondo",                                                          turno_tts=false},
    {nome="MOVIMENTO",  desc="Prima muove chi ha l'iniziativa (prima i caricanti poi le altre), poi passa all'avversario",                                    turno_tts=true },
    {nome="TIRO",       desc="Simultaneo — si tira sempre al nemico piu vicino, unita in bosco tirano solo entro 3cm dal bordo",                              turno_tts=false},
    {nome="MISCHIE",    desc="Si combattono le mischie da cariche — testa morale se sotto il 50% delle figure. Esercito che perde >50% unita abbandona.", turno_tts=true },
}
fase_corrente     = 0
iniziativa_tag    = (ARMY[1].tag or "ARMY1")
iniziativa_scelta = false  -- true quando il vincitore ha premuto il suo pulsante
mano_tag          = nil    -- tag di chi sta muovendo ora (fasi con turno_tts)

-- ------------------------------------------------------------
-- TABELLA DATI REGOLAMENTO
-- ------------------------------------------------------------
DATI_UNITA = {
    AI   = { basi=3, fpb=4, dado_tiro_div=3   },
    UI   = { basi=4, fpb=3, dado_tiro_div=3   },
    SK   = { basi=4, fpb=2, dado_tiro_div=4   },
    AC   = { basi=2, fpb=3, dado_tiro_div=nil },
    UC   = { basi=2, fpb=3, dado_tiro_div=nil },
    SKC  = { basi=2, fpb=2, dado_tiro_div=nil },
    CinC = { basi=1, fpb=0, dado_tiro_div=nil },
}

-- Codici armi da tiro
ARMI_TIRO = {
    ARC  = { gittata=30 },
    ARCL = { gittata=35 },
    BAL  = { gittata=35 },
    FROM = { gittata=20 },
    GIAV = { gittata=10 },
    HAN  = { gittata=10 },
}

-- Tabella interna ferite per base
wounds_data = {}

-- ------------------------------------------------------------
-- STRUTTURE DATI GLOBALI
-- ------------------------------------------------------------
esercito_1     = {}
esercito_2     = {}
turno_corrente = 0

-- Stato linee attive
linee_croce  = false
linee_deploy      = false
linee_rettangolo  = false

-- ------------------------------------------------------------
-- FUNZIONE: aggiungiMenuBase(obj)
-- Aggiunge voci menu contestuale alle basi
-- ------------------------------------------------------------
function aggiungiMenuBase(obj)
    local tipo = string.match(obj.getName(), "^([A-Za-z]+)")
    if not tipo or not DATI_UNITA[tipo] then return end

    obj.addContextMenuItem("Metti in colonna", function(player)
        mettInColonnaOggetto(obj, player)
    end)

    obj.addContextMenuItem("Allinea al fronte", function(player)
        allineaAlFronte(player, obj)
    end)
end

-- ------------------------------------------------------------
-- FUNZIONE: onObjectSpawn(obj)
-- ------------------------------------------------------------
function onObjectSpawn(obj)
    Wait.frames(function()
        aggiungiMenuBase(obj)
    end, 30)
end

-- ------------------------------------------------------------
-- FUNZIONE: mettInColonnaOggetto(obj, player)
-- Versione single-object: mette in colonna l'unità dell'oggetto
-- ------------------------------------------------------------
function mettInColonnaOggetto(obj, player)
    -- Trova tutte le basi della stessa unità (stesso prefisso tipo_num)
    local nome = obj.getName()
    local prefisso = string.match(nome, "^([A-Z]+_%d+)")
    if not prefisso then
        printToAll("[COLONNA] Nickname non valido: " .. nome, {r=1,g=0.3,b=0.3})
        return
    end

    local basi = {}
    for _, o in ipairs(getAllObjects()) do
        if string.match(o.getName(), "^" .. prefisso) then
            table.insert(basi, o)
        end
    end

    -- Ordina per Z
    table.sort(basi, function(a, b)
        return a.getPosition().z > b.getPosition().z
    end)

    local PROFONDITA = {AI=2.4,AC=2.4,UI=2.4,UC=2.4,SKC=2.4,SK=1.6}
    local tipo = string.match(nome, "^([A-Z]+)")
    local passo = PROFONDITA[tipo] or 2.4

    local pos0 = basi[1].getPosition()
    local x = pos0.x
    local y = pos0.y
    local z = pos0.z

    for i, b in ipairs(basi) do
        b.setPosition({x=x, y=y, z=z})
        z = z - passo
    end

    printToAll("[COLONNA] " .. prefisso .. " — " .. #basi .. " basi allineate", {r=0.4,g=0.9,b=0.4})
end


-- ------------------------------------------------------------
-- FUNZIONE: spawnaPannelli()
-- Crea i pannelli informativi come Global UI XML (2D, uguale per tutti)
-- ------------------------------------------------------------
function spawnaPannelli()
    UI.setXmlTable({
        -- Banner centrale scelta colori
        {
            tag = "Panel",
            attributes = {
                id            = "banner_root",
                rectAlignment = "MiddleCenter",
                width         = "420",
                height        = "240",
                color         = "rgba(0,0,0,0.85)",
                offsetXY      = "0 330",
            },
            children = {{
                tag = "VerticalLayout",
                attributes = { padding = "12 12 12 12", spacing = "6" },
                children = {
                    { tag = "Text",   attributes = { id="banner_title", text="SCEGLI IL TUO COLORE", fontSize="18", fontStyle="Bold", color="White", alignment="MiddleCenter" } },
                    { tag = "Text",   attributes = { id="banner_army1", text="Red  ->  Army 1", fontSize="14", color="rgba(1,0.3,0.3,1)", alignment="MiddleCenter" } },
                    { tag = "Text",   attributes = { id="banner_army2", text="Green  ->  Army 2", fontSize="14", color="rgba(0.3,1,0.3,1)", alignment="MiddleCenter" } },
                    { tag = "Text",   attributes = { id="banner_desc",  text="", fontSize="12", color="rgba(0.8,0.8,0.8,1)", alignment="MiddleCenter" } },
                    { tag = "Button", attributes = { id="banner_btn_fase", text="► AVANZA FASE", fontSize="14", fontStyle="Bold",
                        color="rgba(0.2,0.6,0.2,1)", textColor="White",
                        width="180", height="36",
                        onClick="onBtnAvanzaFase",
                        active="false"
                    }},
                    { tag = "Button", attributes = { id="banner_btn_deploy", text="► DEPLOY ESERCITI", fontSize="14", fontStyle="Bold",
                        color="rgba(0.15,0.4,0.8,1)", textColor="White",
                        width="200", height="36",
                        onClick="onBtnDeploy",
                        active="false"
                    }},
                    { tag = "Button", attributes = { id="banner_btn_mano", text="⇒ PASSA LA MANO", fontSize="14", fontStyle="Bold",
                        color="rgba(0.5,0.2,0.7,1)", textColor="White",
                        width="200", height="36",
                        onClick="onBtnPassaMano",
                        active="false"
                    }},
                    { tag = "Panel", attributes = { id="banner_pronti_row", active="false", preferredHeight="40" }, children = {
                        { tag = "HorizontalLayout", attributes = { spacing="12", childAlignment="MiddleCenter" }, children = {
                        { tag = "Button", attributes = { id="banner_btn_pronto_red",   text="[R] PRONTO", fontSize="13", fontStyle="Bold",
                            color="rgba(0.7,0.15,0.15,1)", textColor="White",
                            width="130", height="36",
                            onClick="onBtnProntoRed"
                        }},
                        { tag = "Button", attributes = { id="banner_btn_pronto_green", text="[G] PRONTO", fontSize="13", fontStyle="Bold",
                            color="rgba(0.15,0.6,0.15,1)", textColor="White",
                            width="130", height="36",
                            onClick="onBtnProntoGreen"
                        }},
                    }}}},
                    { tag = "Panel", attributes = { id="banner_ini_row", active="false", preferredHeight="40" }, children = {
                        { tag = "HorizontalLayout", attributes = { spacing="12", childAlignment="MiddleCenter" }, children = {
                        { tag = "Button", attributes = { id="banner_btn_ini1", text="Army 1", fontSize="13", fontStyle="Bold",
                            color="rgba(0.7,0.15,0.15,1)", textColor="White",
                            width="130", height="36",
                            onClick="onBtnIniziativa1"
                        }},
                        { tag = "Button", attributes = { id="banner_btn_ini2", text="Army 2", fontSize="13", fontStyle="Bold",
                            color="rgba(0.15,0.6,0.15,1)", textColor="White",
                            width="130", height="36",
                            onClick="onBtnIniziativa2"
                        }},
                    }}}},
                }
            }}
        },
        -- Pannello Army 1 (sinistra)
        {
            tag = "Panel",
            attributes = {
                id            = "pannello_root",
                rectAlignment = "UpperLeft",
                width         = "300",
                height        = "200",
                color         = "rgba(0,0,0,0.7)",
                offsetXY      = "320 -100",
            },
            children = {{
                tag = "VerticalLayout",
                attributes = { padding = "8 8 8 8", spacing = "4" },
                children = {
                    { tag = "Text", attributes = { id="pan1_title",  text="ARMY 1",       fontSize="16", fontStyle="Bold", color="rgba(1,0.85,0.3,1)" } },
                    { tag = "Text", attributes = { id="pan1_player", text="Player: ---",   fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan1_color",  text="Colore: ---",   fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan1_army",   text="Esercito: ---", fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan1_unita",  text="Unita: ---",    fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan1_fase",   text="Fase: ---",     fontSize="13", color="rgba(0.4,0.9,0.4,1)" } },
                }
            }}
        },
        -- Pannello Army 2 (destra)
        {
            tag = "Panel",
            attributes = {
                id            = "pannello2_root",
                rectAlignment = "UpperRight",
                width         = "300",
                height        = "200",
                color         = "rgba(0,0,0,0.7)",
                offsetXY      = "-320 -100",
            },
            children = {{
                tag = "VerticalLayout",
                attributes = { padding = "8 8 8 8", spacing = "4" },
                children = {
                    { tag = "Text", attributes = { id="pan2_title",  text="ARMY 2",       fontSize="16", fontStyle="Bold", color="rgba(0.3,1,0.3,1)" } },
                    { tag = "Text", attributes = { id="pan2_player", text="Player: ---",   fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan2_color",  text="Colore: ---",   fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan2_army",   text="Esercito: ---", fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan2_unita",  text="Unita: ---",    fontSize="13", color="White" } },
                    { tag = "Text", attributes = { id="pan2_fase",   text="Fase: ---",     fontSize="13", color="rgba(0.4,0.9,0.4,1)" } },
                }
            }}
        },
    })
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaPannello(slot)
-- Aggiorna il testo del pannello UI per Army 1 o 2
-- ------------------------------------------------------------
function aggiornaPannello(slot)
    local a          = ARMY[slot]
    local prefix     = "pan" .. slot .. "_"
    local player     = a.player     or "---"
    local color      = a.color      or "---"
    local nome       = a.nome       or "---"  -- nome completo per pannello

    -- Conta unità attive
    local esercito = slot == 1 and esercito_1 or esercito_2
    local unita_attive = 0
    for _, u in ipairs(esercito) do
        if #u.basi > 0 then unita_attive = unita_attive + 1 end
    end
    local unita_str = (#esercito > 0) and (unita_attive .. "/" .. #esercito) or "---"

    -- Fase corrente da tabella FASI
    local fase_str
    if fase_corrente == 0 then
        fase_str = turno_corrente == 0 and "DEPLOY" or "INIZIATIVA"
    else
        fase_str = FASI[fase_corrente] and FASI[fase_corrente].nome or "---"
    end

    -- Colore titolo dal colore player TTS
    local col_map = {
        Red    = "rgba(1,0.2,0.2,1)",
        Green  = "rgba(0.2,0.9,0.2,1)",
        Blue   = "rgba(0.2,0.4,1,1)",
        Orange = "rgba(1,0.6,0,1)",
        Teal   = "rgba(0,0.8,0.8,1)",
        Purple = "rgba(0.7,0.2,1,1)",
        Pink   = "rgba(1,0.4,0.7,1)",
        Yellow = "rgba(1,1,0,1)",
        White  = "rgba(1,1,1,1)",
        Grey   = "rgba(0.6,0.6,0.6,1)",
    }
    local col_str = col_map[color] or "rgba(1,0.85,0.3,1)"

    UI.setAttribute(prefix .. "title",  "color", col_str)
    UI.setAttribute(prefix .. "player", "text", "Player: " .. player)
    UI.setAttribute(prefix .. "color",  "text", "Colore: " .. color)
    UI.setAttribute(prefix .. "army",   "text", "Esercito: " .. nome)
    UI.setAttribute(prefix .. "unita",  "text", "Unita: " .. unita_str)
    UI.setAttribute(prefix .. "fase",   "text", "Fase: " .. fase_str)
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaBanner()
-- Mostra/nasconde il banner di benvenuto
-- Scompare quando Red e Green sono entrambi seduti
-- ------------------------------------------------------------
function onBtnAvanzaFase(player, value, id)
    if fase_corrente >= #FASI then
        avviaTurno()
    else
        avanzaFase()
    end
end

function onBtnIniziativa1(player, value, id)
    local tag = ARMY[1].tag or "ARMY1"
    local nb  = ARMY[1].nome_breve or tag
    iniziativa_tag    = tag
    iniziativa_scelta = true
    printToAll("[DEBUG] fase prima di avanzaFase: " .. tostring(fase_corrente), {r=1,g=1,b=0})
    printToAll("Iniziativa: " .. nb, {r=1,g=0.8,b=0.2})
    aggiornaPannello(1)
    aggiornaPannello(2)
    avanzaFase()
end

function onBtnIniziativa2(player, value, id)
    local tag = ARMY[2].tag or "ARMY2"
    local nb  = ARMY[2].nome_breve or tag
    iniziativa_tag    = tag
    iniziativa_scelta = true
    printToAll("Iniziativa: " .. nb, {r=1,g=0.8,b=0.2})
    aggiornaPannello(1)
    aggiornaPannello(2)
    avanzaFase()
end

function onBtnPassaMano(player, value, id)
    -- Trova il tag dell'altro esercito
    local altro_tag = nil
    for slot = 1, 2 do
        if ARMY[slot].tag ~= mano_tag then
            altro_tag = ARMY[slot].tag
        end
    end
    if altro_tag then
        mano_tag = altro_tag
        local nb = mano_tag
        for slot = 1, 2 do
            if ARMY[slot].tag == mano_tag then nb = ARMY[slot].nome_breve or mano_tag end
        end
        printToAll("-> Mano passata a: " .. nb, {r=0.4,g=0.9,b=0.4})
        aggiornaBanner()
    else
        -- Entrambi hanno mosso — mostra AVANZA FASE
        mano_tag = nil
        aggiornaBanner()
    end
end

function onBtnDeploy(player, value, id)
    local c = type(player) == "string" and player or (player and player.color) or ""
    if c ~= "Red" and c ~= "Green" then
        if c ~= "" then
            printToColor("[LIONHEART] Solo Red o Green possono fare il deploy.", c, {r=1,g=0.3,b=0.3})
        end
        return
    end
    -- Ricava oggetto Player dal colore
    local p = Player[c]
    if not p then return end
    onChat("!deploy", p)
end

function onBtnProntoRed(player, value, id)
    if player == nil or player.color ~= "Red" then return end
    pronto_red = not pronto_red
    local msg = pronto_red and "[R] Red: PRONTO!" or "[R] Red: non piu pronto."
    printToAll(msg, {r=1,g=0.4,b=0.4})
    aggiornaBanner()
    verificaPronti()
end

function onBtnProntoGreen(player, value, id)
    if player == nil or player.color ~= "Green" then return end
    pronto_green = not pronto_green
    local msg = pronto_green and "[G] Green: PRONTO!" or "[G] Green: non piu pronto."
    printToAll(msg, {r=0.4,g=1,b=0.4})
    aggiornaBanner()
    verificaPronti()
end

function onBtnProntoGreen(player, value, id)
    local color = (player ~= nil) and (type(player) == "string" and player or player.color) or "Green"
    if color ~= "Green" then return end
    pronto_green = not pronto_green
    local msg = pronto_green and "[G] Green: PRONTO!" or "[G] Green: non piu pronto."
    printToAll(msg, {r=0.4,g=1,b=0.4})
    aggiornaBanner()
    verificaPronti()
end

function verificaPronti()
    if pronto_red and pronto_green then
        printToAll("Entrambi pronti — verifico il deploy...", {r=0.9,g=0.8,b=0.1})
        local ok, err = pcall(verificaDeploy)
        if not ok then
            printToAll("[ERRORE verificaDeploy] " .. tostring(err), {r=1,g=0,b=0})
            pronto_red   = false
            pronto_green = false
            aggiornaBanner()
            return
        end
        if not err then
            printToAll("Correggi il posizionamento e premi di nuovo PRONTO!", {r=1,g=0.3,b=0.3})
            pronto_red   = false
            pronto_green = false
            aggiornaBanner()
            return
        end
        pronto_red   = false
        pronto_green = false
        Wait.frames(function()
            avviaTurno()
        end, 60)
    end
end

function aggiornaBanner()
    -- Helper: nascondi tutti i pulsanti
    local function resetBtn()
        UI.setAttribute("banner_btn_fase",        "active", "false")
        UI.setAttribute("banner_btn_turno",       "active", "false")
        UI.setAttribute("banner_btn_deploy",      "active", "false")
        UI.setAttribute("banner_btn_mano",        "active", "false")
        UI.setAttribute("banner_pronti_row",      "active", "false")
        UI.setAttribute("banner_ini_row",         "active", "false")
    end

    UI.setAttribute("banner_root", "active", "true")

    -- STATO 1a: Fase INIZIATIVA (fase_corrente==1) — mostra pulsanti scelta iniziativa
    if fase_corrente == 1 and not iniziativa_scelta then
        resetBtn()
        UI.setAttribute("banner_ini_row", "active", "true")
        local nb1 = ARMY[1].nome_breve or ARMY[1].tag or "Army 1"
        local nb2 = ARMY[2].nome_breve or ARMY[2].tag or "Army 2"
        UI.setAttribute("banner_btn_ini1", "text", nb1)
        UI.setAttribute("banner_btn_ini2", "text", nb2)
        UI.setAttribute("banner_title", "text", "TURNO " .. turno_corrente)
        UI.setAttribute("banner_army1", "text", "Fase: INIZIATIVA")
        UI.setAttribute("banner_army2", "text", "")
        UI.setAttribute("banner_desc",  "text", "Chi ha vinto il dado? Premi il tuo nome.")
        return
    end

    -- STATO 1: Gioco in corso (fase > 0, non INIZIATIVA)
    if fase_corrente > 0 and fase_corrente ~= 1 then
        resetBtn()
        local fase = FASI[fase_corrente]
        local nb_ini = iniziativa_tag
        for slot = 1, 2 do
            if ARMY[slot].tag == iniziativa_tag then
                nb_ini = ARMY[slot].nome_breve or iniziativa_tag
            end
        end
        UI.setAttribute("banner_title", "text", "TURNO " .. turno_corrente)
        UI.setAttribute("banner_army1", "text", "Fase: " .. (fase and fase.nome or "---"))
        UI.setAttribute("banner_army2", "text", "Iniziativa: " .. nb_ini)
        UI.setAttribute("banner_desc",  "text", fase and fase.desc or "")
        -- Fasi con mano: mostra PASSA LA MANO o AVANZA FASE
        if fase and fase.turno_tts and mano_tag ~= nil then
            local nb_mano = mano_tag
            for slot = 1, 2 do
                if ARMY[slot].tag == mano_tag then nb_mano = ARMY[slot].nome_breve or mano_tag end
            end
            UI.setAttribute("banner_btn_mano", "active", "true")
            UI.setAttribute("banner_btn_mano", "text", nb_mano .. " -> PASSA LA MANO")
        else
            local btn_txt = fase_corrente >= #FASI and "► PROSSIMO TURNO" or "► AVANZA FASE"
            UI.setAttribute("banner_btn_fase", "active", "true")
            UI.setAttribute("banner_btn_fase", "text", btn_txt)
        end
        return
    end

    -- STATO 3: Deploy fatto, in attesa PRONTO
    if deploy_fatto then
        resetBtn()
        UI.setAttribute("banner_pronti_row", "active", "true")
        UI.setAttribute("banner_title", "text", "SCHIERA I TUOI ESERCITI")
        local nb1 = ARMY[1] and ARMY[1].nome_breve or "Army 1"
        local nb2 = ARMY[2] and ARMY[2].nome_breve or "Army 2"
        UI.setAttribute("banner_army1", "text", "[R] " .. nb1)
        UI.setAttribute("banner_army2", "text", "[G] " .. nb2)
        UI.setAttribute("banner_desc",  "text", "Quando pronti premi il tuo pulsante PRONTO")
        -- Aggiorna aspetto pulsanti in base allo stato
        if pronto_red then
            UI.setAttribute("banner_btn_pronto_red", "text",  "[R] IN ATTESA...")
            UI.setAttribute("banner_btn_pronto_red", "color", "rgba(0.4,0.4,0.4,1)")
        else
            UI.setAttribute("banner_btn_pronto_red", "text",  "[R] PRONTO")
            UI.setAttribute("banner_btn_pronto_red", "color", "rgba(0.7,0.15,0.15,1)")
        end
        if pronto_green then
            UI.setAttribute("banner_btn_pronto_green", "text",  "[G] IN ATTESA...")
            UI.setAttribute("banner_btn_pronto_green", "color", "rgba(0.4,0.4,0.4,1)")
        else
            UI.setAttribute("banner_btn_pronto_green", "text",  "[G] PRONTO")
            UI.setAttribute("banner_btn_pronto_green", "color", "rgba(0.15,0.6,0.15,1)")
        end
        return
    end

    -- STATO 4: Inizio assoluto — solo pulsante DEPLOY
    resetBtn()
    UI.setAttribute("banner_btn_deploy", "active", "true")
    UI.setAttribute("banner_title", "text", "LIONHEART")
    local nb1 = ARMY[1] and ARMY[1].nome_breve
    local nb2 = ARMY[2] and ARMY[2].nome_breve
    UI.setAttribute("banner_army1", "text", "[R] Red  →  " .. (nb1 and nb1 or "Army 1"))
    UI.setAttribute("banner_army2", "text", "[G] Green  →  " .. (nb2 and nb2 or "Army 2"))
    UI.setAttribute("banner_desc",  "text", "Scegli il tuo colore e avvia il deploy")
end

-- ------------------------------------------------------------
function onPlayerChangeColor(player_color)
    Wait.frames(function() aggiornaBanner() end, 10)
end

-- ------------------------------------------------------------
function onLoad()
    log("[LIONHEART] Script caricato " .. VERSION)
    log("[LIONHEART]   !caricaArmy   -> carica esercito (slot determinato dal colore player)")
    log("[LIONHEART]   !reveal      -> rivela entrambi gli eserciti")
    log("[LIONHEART]   !deploy      -> carica eserciti e scansiona")
    log("[LIONHEART]   !turno       -> avvia turno")
    log("[LIONHEART]   !fase        -> avanza fase")
    log("[LIONHEART]   !wounds N    -> ferite sulla base selezionata")
    log("[LIONHEART]   !reset       -> azzera ferite sulla base selezionata")
    log("[LIONHEART]   !visual      -> mostra nome oggetto selezionato")
    log("[LIONHEART]   !pos         -> mostra posizione oggetto selezionato")
    log("[LIONHEART]   !stato       -> mostra stato battaglia")
    log("[LIONHEART]   !listobj     -> lista tutti gli oggetti con nome")
    log("[LIONHEART]   !croce       -> croce di riferimento sul tavolo")
    log("[LIONHEART]   !croce off   -> rimuove croce")
    log("[LIONHEART]   !linee       -> linee di schieramento sul verde")
    log("[LIONHEART]   !linee off   -> rimuove linee di schieramento")

    -- Posizioni originali Hz (hardcoded)
    HZ_POS = {
        ["Hz1"] = {x=-0.04, y=5.39, z=-27.26},
        ["Hz2"] = {x=-0.16, y=5.39, z= 27.79}
    }

    -- Spawna pannelli informativi
    spawnaPannelli()

    -- Rettangoli spawn sempre visibili, linee deploy no
    linee_rettangolo = true
    linee_deploy     = false
    aggiornaLinee()

    -- Aggiunge menu contestuale a tutti gli oggetti gia presenti
    for _, obj in ipairs(getAllObjects()) do
        aggiungiMenuBase(obj)
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: onChat()
-- ------------------------------------------------------------
function onChat(message, player)
    if not message then return end
    message = message:gsub("^%s+", ""):gsub("%s+$", "")
    if not message or message == "" then return end

    -- !carica1 URL — carica esercito 1 da JSON
    if message == "!caricaArmy" then
        local slot = ARMY_COLORS[player.color]
        if not slot then
            printToAll("[LIONHEART] Colore " .. player.color .. " non associato a nessun esercito", {r=1,g=0.3,b=0.3})
            return false
        end
        local url = leggiUrlDaNotebook("Army" .. slot)
        if url then
            caricaEsercito(url, tostring(slot), player)
        else
            printToAll("[LIONHEART] Notecard 'Army" .. slot .. "' non trovata", {r=1,g=0.3,b=0.3})
        end
        return false
    end

    if string.sub(message, 1, 8) == "!promote" then
        local colore = string.match(message, "%S+%s+(%S+)")
        if colore then
            Player[colore].promote()
            printToAll("[DEBUG] Promosso come " .. colore, {r=1,g=1,b=0})
        else
            printToAll("[DEBUG] Uso: !promote Red", {r=1,g=0.3,b=0.3})
        end
        return false
    end

    if message == "!verificaDeploy" then
        verificaDeploy()
        return false
    end

    if message == "!cercaHz" then
        local trovate = 0
        for _, obj in ipairs(getAllObjects()) do
            local tags = obj.getTags()
            for _, t in ipairs(tags) do
                if t == "Hz1" or t == "Hz2" then
                    printToAll("Hz trovata: nome=[" .. obj.getName() .. "] tag=" .. t .. " guid=" .. obj.getGUID() .. " pos=" .. obj.getPosition().x .. "," .. obj.getPosition().y .. "," .. obj.getPosition().z, {r=0,g=1,b=1})
                    trovate = trovate + 1
                end
            end
        end
        if trovate == 0 then
            printToAll("[Hz] Nessuna zona trovata con tag Hz1 o Hz2", {r=1,g=0.3,b=0.3})
        end
        return false
    end

    if message == "!restart" then
        restart()
        return false
    end

    if message == "!reveal" then
        reveal()
        return false
    end

    if message == "!deploy" then
        -- Verifica che i player siano seduti
        if not DEBUG then
            local red_ok   = Player["Red"]   and Player["Red"].seated
            local green_ok = Player["Green"] and Player["Green"].seated
            if not red_ok or not green_ok then
                printToAll("[INIZIA] Entrambi i player devono essere seduti (Red e Green)", {r=1,g=0.3,b=0.3})
                if not red_ok   then printToAll("  Red non seduto",   {r=1,g=0.3,b=0.3}) end
                if not green_ok then printToAll("  Green non seduto", {r=1,g=0.3,b=0.3}) end
                return false
            end
        end
        -- Carica entrambi gli eserciti poi scansiona
        local url1 = leggiUrlDaNotebook("Army1")
        local url2 = leggiUrlDaNotebook("Army2")
        if not url1 or not url2 then
            printToAll("[INIZIA] Notecard Army1 o Army2 non trovata", {r=1,g=0.3,b=0.3})
            return false
        end
        -- Mostra linee deploy
        linee_deploy = true
        aggiornaLinee()
        caricaEsercito(url1, "1", Player["Red"])
        caricaEsercito(url2, "2", Player["Green"])
        deploy_fatto = true
        aggiornaBanner()
        -- Delay per attendere spawn prima di verificare e scansionare
        Wait.time(function()
            -- verificaDeploy() -- disabilitato per ora
            scanTavolo()
        end, 5)
        return false
    end

    if message == "!rettangolo" then
        linee_rettangolo = true
        aggiornaLinee()
        printToAll("[RETTANGOLO] Zone spawn visibili", {r=1,g=0.8,b=0})
        return false
    end

    if message == "!rettangolo off" then
        linee_rettangolo = false
        aggiornaLinee()
        printToAll("[RETTANGOLO] Zone spawn nascoste", {r=0.8,g=0.8,b=0.8})
        return false
    end

    if message == "!colonna" then
        mettInColonna(player)
        return false
    end

    if message == "!hide" then
        local slot = ARMY_COLORS[player.color]
        if not slot then
            printToAll("[HIDE] Colore " .. player.color .. " non associato a nessun esercito", {r=1,g=0.3,b=0.3})
            return false
        end
        local nemico_color = slot == 1 and ARMY[2].color or ARMY[1].color
        -- fallback: cerca l'altro colore tra Red e Green
        if not nemico_color or nemico_color == "---" then
            nemico_color = slot == 1 and "Green" or "Red"
        end
        local army_tag = "Army" .. slot
        local count = 0
        for _, obj in ipairs(getAllObjects()) do
            for _, t in ipairs(obj.getTags()) do
                if t == army_tag then
                    obj.setInvisibleTo({nemico_color})
                    count = count + 1
                    break
                end
            end
        end
        printToAll("[HIDE] " .. count .. " basi nascoste a " .. nemico_color, {r=0.4,g=0.9,b=0.4})
        return false
    end

    if message == "!show" then
        local slot = ARMY_COLORS[player.color]
        if not slot then
            printToAll("[SHOW] Colore " .. player.color .. " non associato a nessun esercito", {r=1,g=0.3,b=0.3})
            return false
        end
        local army_tag = "Army" .. slot
        local count = 0
        for _, obj in ipairs(getAllObjects()) do
            for _, t in ipairs(obj.getTags()) do
                if t == army_tag then
                    obj.setInvisibleTo({})
                    count = count + 1
                    break
                end
            end
        end
        printToAll("[SHOW] " .. count .. " basi visibili a tutti", {r=0.4,g=0.9,b=0.4})
        return false
    end

    if message == "!turno" then
        avviaTurno()
        return false
    end

    if message == "!fase" then
        avanzaFase()
        return false
    end

    if message == "!stato" then
        mostraStato()
        return false
    end

    if message == "!listobj" then
        for _, obj in ipairs(getAllObjects()) do
            local n = obj.getName()
            if n ~= "" then
                printToAll(n, {r=0.8,g=0.8,b=0.8})
            end
        end
        return false
    end

    if message == "!visual" then
        local sel = player.getSelectedObjects()
        if not sel or #sel == 0 then
            printToAll("[VISUAL] Nessun oggetto selezionato", {r=1,g=0.3,b=0.3})
        else
            for _, obj in ipairs(sel) do
                printToAll("[VISUAL] Nome: " .. obj.getName(), {r=0.4,g=0.9,b=0.4})
            end
        end
        return false
    end

    if message == "!pos" then
        local sel = player.getSelectedObjects()
        if not sel or #sel == 0 then
            printToAll("[POS] Nessun oggetto selezionato", {r=1,g=0.3,b=0.3})
        else
            local pos = sel[1].getPosition()
            printToAll("[POS] X: " .. string.format("%.2f", pos.x)
                       .. " Y: " .. string.format("%.2f", pos.y)
                       .. " Z: " .. string.format("%.2f", pos.z),
                       {r=0.4,g=0.9,b=0.4})
        end
        return false
    end

    if message == "!croce" then
        spawnaCroce()
        return false
    end

    if message == "!croce off" then
        rimuoviCroce()
        return false
    end

    if message == "!linee" then
        spawnaDeploy()
        return false
    end

    if message == "!linee off" then
        rimuoviDeploy()
        return false
    end

    -- !wounds N
    if string.sub(message, 1, 7) == "!wounds" then
        local parti = {}
        for p in string.gmatch(message, "%S+") do
            table.insert(parti, p)
        end
        if #parti == 2 then
            local n = tonumber(parti[2])
            if n and n > 0 then
                local nome_base = getBaseSelezionata(player)
                if nome_base then registraWounds(nome_base, n) end
            else
                printToAll("[LIONHEART] Uso: seleziona base + !wounds NUMERO", {r=1,g=0.3,b=0.3})
            end
        else
            printToAll("[LIONHEART] Uso: seleziona base + !wounds NUMERO", {r=1,g=0.3,b=0.3})
        end
        return false
    end

    -- !reset
    if message == "!reset" then
        local nome_base = getBaseSelezionata(player)
        if nome_base then resetWounds(nome_base) end
        return false
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaLinee()
-- Ridisegna tutte le linee attive in un unico setVectorLines
-- ------------------------------------------------------------
function aggiornaLinee()
    local linee = {}

    -- Croce sul tavolo nero
    if linee_croce then
        table.insert(linee, {
            points    = {{x=-TAVOLO_LX, y=TAVOLO_Y, z=0}, {x=TAVOLO_LX, y=TAVOLO_Y, z=0}},
            color     = {r=0.8, g=0.8, b=0.8},
            thickness = 0.3,
        })
        table.insert(linee, {
            points    = {{x=0, y=TAVOLO_Y, z=-TAVOLO_LZ}, {x=0, y=TAVOLO_Y, z=TAVOLO_LZ}},
            color     = {r=0.8, g=0.8, b=0.8},
            thickness = 0.3,
        })
    end

    -- Linee deploy sul verde
    if linee_deploy then
        local y = VERDE_Y_LINEE

        -- Linea deploy Army1 (rosso) — bordo nord
        local z1 = -(VERDE_LZ - DEPLOY_CM)
        table.insert(linee, {
            points    = {{x=-VERDE_LX, y=y, z=z1}, {x=VERDE_LX, y=y, z=z1}},
            color     = {r=0.9, g=0.2, b=0.2},
            thickness = 0.25,
        })

        -- Linea deploy Army2 (verde) — bordo sud
        local z2 = (VERDE_LZ - DEPLOY_CM)
        table.insert(linee, {
            points    = {{x=-VERDE_LX, y=y, z=z2}, {x=VERDE_LX, y=y, z=z2}},
            color     = {r=0.2, g=0.8, b=0.2},
            thickness = 0.25,
        })
    end

    -- Rettangolo spawn Army1
    if linee_rettangolo then
        local y = 2.69
        local pts1 = {
            {x=-46.18, y=y, z=-37.55}, {x=46.18, y=y, z=-37.55},
            {x=46.18,  y=y, z=-62.38}, {x=-46.18, y=y, z=-62.38},
            {x=-46.18, y=y, z=-37.55}
        }
        table.insert(linee, {points=pts1, color={r=1,g=0.8,b=0}, thickness=0.3})
        -- Rettangolo spawn Army2 (simmetrico)
        local pts2 = {
            {x=-46.18, y=y, z=37.55}, {x=46.18, y=y, z=37.55},
            {x=46.18,  y=y, z=62.38}, {x=-46.18, y=y, z=62.38},
            {x=-46.18, y=y, z=37.55}
        }
        table.insert(linee, {points=pts2, color={r=1,g=0.8,b=0}, thickness=0.3})
    end

    Global.setVectorLines(linee)
end

-- ------------------------------------------------------------
-- FUNZIONE: spawnaCroce()
-- ------------------------------------------------------------
function spawnaCroce()
    linee_croce = true
    aggiornaLinee()
    printToAll("[CROCE] Attiva — bianca sul tavolo", {r=0.8,g=0.8,b=0.8})
end

-- ------------------------------------------------------------
-- FUNZIONE: rimuoviCroce()
-- ------------------------------------------------------------
function rimuoviCroce()
    linee_croce = false
    aggiornaLinee()
    printToAll("[CROCE] Rimossa", {r=0.8,g=0.8,b=0.8})
end

-- ------------------------------------------------------------
-- FUNZIONE: spawnaDeploy()
-- ------------------------------------------------------------
function spawnaDeploy()
    linee_deploy = true
    aggiornaLinee()
    printToAll("[DEPLOY] Linee attive", {r=0.4,g=0.9,b=0.4})
    printToAll("  Rosso = zona deploy Army 1", {r=0.9,g=0.2,b=0.2})
    printToAll("  Blu   = zona deploy Army 2", {r=0.2,g=0.4,b=0.9})
end

-- ------------------------------------------------------------
-- FUNZIONE: rimuoviDeploy()
-- ------------------------------------------------------------
function rimuoviDeploy()
    linee_deploy      = false
linee_rettangolo  = false
    aggiornaLinee()
    printToAll("[DEPLOY] Linee rimosse", {r=0.8,g=0.8,b=0.8})
end

-- ------------------------------------------------------------
-- FUNZIONE: getBaseSelezionata(player)
-- ------------------------------------------------------------
function getBaseSelezionata(player)
    local sel = player.getSelectedObjects()
    if not sel or #sel == 0 then
        printToAll("[LIONHEART] Nessuna base selezionata — usa Ctrl+click", {r=1,g=0.3,b=0.3})
        return nil
    end
    if #sel > 1 then
        printToAll("[LIONHEART] Seleziona una sola base alla volta", {r=1,g=0.3,b=0.3})
        return nil
    end
    local nickname = sel[1].getName()
    if wounds_data[nickname] == nil then
        printToAll("[LIONHEART] Oggetto non valido: " .. nickname .. " — fai !deploy prima", {r=1,g=0.3,b=0.3})
        return nil
    end
    return nickname
end

-- ------------------------------------------------------------
-- FUNZIONE: parsaNome(nickname)
-- Formato: AC_1.1_S, UI_3.19_ARCL, SK_1.23_GIAV
-- tipo = parte alfabetica, unita_num = numero dopo _, seq = numero dopo .
-- ------------------------------------------------------------
function parsaNome(nickname)
    -- Estrai tipo, unita_num, seq
    local tipo, unita_str, seq_str = string.match(nickname, "^([A-Za-z]+)_(%d+)%.(%d+)")
    if not tipo or not unita_str or not seq_str then return nil end
    if not DATI_UNITA[tipo] then return nil end

    local valore   = 0
    local lancieri = false
    local arma     = nil

    -- Analizza i modificatori dopo il seq
    local resto = string.sub(nickname, #tipo + #unita_str + #seq_str + 3) -- +3 per "_", ".", "_"
    for mod in string.gmatch(resto, "[^_]+") do
        if mod == "S"     then valore   = 1    end
        if mod == "I"     then valore   = -1   end
        if mod == "LANC"  then lancieri = true  end
        if ARMI_TIRO[mod] then arma     = mod   end
    end

    local d = DATI_UNITA[tipo]
    return {
        tipo      = tipo,
        seq       = tonumber(seq_str),
        unita_num = tonumber(unita_str),
        base_num  = 1,
        valore    = valore,
        lancieri  = lancieri,
        arma      = arma,
        fpb       = d.fpb,
        basi_max  = d.basi,
    }
end

-- ------------------------------------------------------------
-- FUNZIONE: allineaAlFronte(player, ref_obj)
-- Allinea le basi selezionate alla posizione di ref_obj sul vettore fronte
-- ------------------------------------------------------------
function allineaAlFronte(player, ref_obj)
    local p = type(player) == "string" and Player[player] or player
    local sel = p.getSelectedObjects()
    if not sel or #sel == 0 then
        printToAll("[FRONTE] Seleziona le basi prima", {r=1,g=0.3,b=0.3})
        return
    end

    -- Trova rotazione Y maggioritaria (arrotondata a 5 gradi)
    local conteggio = {}
    for _, obj in ipairs(sel) do
        local y = math.floor(obj.getRotation().y / 5 + 0.5) * 5
        conteggio[y] = (conteggio[y] or 0) + 1
    end
    local rot_maggioritaria = nil
    local max_count = 0
    for y, c in pairs(conteggio) do
        if c > max_count then
            max_count = c
            rot_maggioritaria = y
        end
    end

    -- Allinea rotazione delle basi non conformi
    for _, obj in ipairs(sel) do
        local y = math.floor(obj.getRotation().y / 5 + 0.5) * 5
        if y ~= rot_maggioritaria then
            local rot = obj.getRotation()
            obj.setRotation({x=rot.x, y=rot_maggioritaria, z=rot.z})
            printToAll("[FRONTE] Base " .. obj.getName() .. " ruotata a " .. rot_maggioritaria .. "°", {r=1,g=0.8,b=0})
        end
    end

    -- Calcola vettore fronte dalla rotazione maggioritaria
    local rad = math.rad(rot_maggioritaria)
    local dx  =  math.sin(rad)
    local dz  = -math.cos(rad)

    -- Componente dominante
    local usa_z = math.abs(dz) >= math.abs(dx)

    -- Trova la base di riferimento (più avanzata sull'asse dominante)
    local ref_val = nil
    for _, obj in ipairs(sel) do
        local pos = obj.getPosition()
        local val = usa_z and pos.z or pos.x
        -- Army1 avanza verso Z positivo, Army2 verso Z negativo
        local tags = obj.getTags()
        local is_army2 = false
        for _, t in ipairs(tags) do if t == "Army2" then is_army2 = true end end
        if ref_val == nil then
            ref_val = val
        elseif is_army2 and val < ref_val then
            ref_val = val
        elseif not is_army2 and val > ref_val then
            ref_val = val
        end
    end

    -- Allinea tutte le basi sull'asse dominante
    for _, obj in ipairs(sel) do
        local pos = obj.getPosition()
        if usa_z then
            obj.setPosition({x=pos.x, y=pos.y, z=ref_val})
        else
            obj.setPosition({x=ref_val, y=pos.y, z=pos.z})
        end
    end

    printToAll("[FRONTE] " .. #sel .. " basi allineate al fronte", {r=0.4,g=0.9,b=0.4})
end

-- ------------------------------------------------------------
-- FUNZIONE: mettInColonna(player)
-- Posiziona le basi selezionate in colonna verso Z negativo
-- senza spazi, partendo dalla posizione della prima base
-- ------------------------------------------------------------
function mettInColonna(player)
    local sel = player.getSelectedObjects()
    if not sel or #sel == 0 then
        printToAll("[COLONNA] Seleziona le basi prima", {r=1,g=0.3,b=0.3})
        return
    end

    -- Profondita base per tipo in unita TTS (1 cm = 0.8)
    local PROFONDITA = {
        AI=2.4, AC=2.4, UI=2.4, UC=2.4, SKC=2.4,
        SK=1.6
    }

    -- Ordina per Z crescente (prima base = Z meno negativa)
    table.sort(sel, function(a, b)
        return a.getPosition().z > b.getPosition().z
    end)

    local pos0 = sel[1].getPosition()
    local x = pos0.x
    local y = pos0.y
    local z = pos0.z

    for i, obj in ipairs(sel) do
        -- Ricava il tipo dal nickname (lettere iniziali)
        local tipo = string.match(obj.getName(), "^([A-Z]+)")
        local passo = PROFONDITA[tipo] or 2.4

        obj.setPosition({x=x, y=y, z=z})
        z = z - passo
    end

    printToAll("[COLONNA] " .. #sel .. " basi allineate", {r=0.4,g=0.9,b=0.4})
end

-- ------------------------------------------------------------
-- FUNZIONE: restart()
-- Torna all'inizio — cancella basi, ripristina Hz e pannelli
-- ------------------------------------------------------------
function restart()
    -- Cancella tutte le basi spawnat (non i template)
    local count = 0
    for _, obj in ipairs(getAllObjects()) do
        local tags = obj.getTags()
        for _, tag in ipairs(tags) do
            if tag == "Army1" or tag == "Army2" then
                -- Salta i template (nickname non parsabile = template)
                if parsaNome(obj.getName()) then
                    obj.destruct()
                    count = count + 1
                end
                break
            end
        end
    end

    ARMY[1] = { player=nil, tag=nil, nome=nil, color=nil, pannello_guid=nil }
    ARMY[2] = { player=nil, tag=nil, nome=nil, color=nil, pannello_guid=nil }

    -- Reset pannelli UI
    for slot = 1, 2 do
        local prefix = "pan" .. slot .. "_"
        UI.setAttribute(prefix .. "player", "text", "Player: ---")
        UI.setAttribute(prefix .. "color",  "text", "Colore: ---")
        UI.setAttribute(prefix .. "army",   "text", "Esercito: ---")
        UI.setAttribute(prefix .. "unita",  "text", "Unità: ---")
        UI.setAttribute(prefix .. "fase",   "text", "Fase: ---")
    end

    -- Reset stato partita
    esercito_1   = {}
    esercito_2   = {}
    wounds_data  = {}
    turno_corrente = 0
    fase_corrente  = 0
    deploy_fatto      = false
    pronto_red        = false
    pronto_green      = false
    iniziativa_scelta = false
    mano_tag          = nil
    -- Rimuovi sfere segnalino
    for _, guid in ipairs(segnalini_guids) do
        local o = getObjectFromGUID(guid)
        if o then o.destruct() end
    end
    segnalini_guids = {}
    Turns.enable   = false

    -- Nascondi linee deploy
    linee_deploy = false
    aggiornaLinee()

    aggiornaBanner()
    printToAll("[RESET] Partita azzerata — pronto per nuovo setup", {r=0.9,g=0.5,b=0.1})
end

-- ------------------------------------------------------------
-- FUNZIONE: verificaDeploy()
-- Controlla che le basi siano nelle Scripting Zone corrette
-- Sz1 = Army1, Sz2 = Army2
-- ------------------------------------------------------------
function verificaDeploy()
    local X_MAX  = 45.54
    local Z_NEAR = 25.67
    local Z_FAR  = 32.88

    -- Rimuovi sfere segnalino precedenti
    for _, guid in ipairs(segnalini_guids) do
        local o = getObjectFromGUID(guid)
        if o then o.destruct() end
    end
    segnalini_guids = {}

    local errori = { [1]={fuori={}, sbagliata={}}, [2]={fuori={}, sbagliata={}} }
    local basi_errate = {}  -- {obj, nome} da segnalare con sfera

    -- Prefissi template dinamici dai tag esercito
    local prefissi_template = {}
    for slot = 1, 2 do
        local tag = ARMY[slot].tag
        if tag then prefissi_template[tag .. "_"] = true end
    end
    prefissi_template["FRA_"] = true
    prefissi_template["ENG_"] = true

    for _, obj in ipairs(getAllObjects()) do
        local nome = obj.getName()
        local is_template = false
        for pfx, _ in pairs(prefissi_template) do
            if string.sub(nome, 1, #pfx) == pfx then is_template = true break end
        end
        if not is_template and parsaNome(nome) then
            local army_tag = nil
            for _, t in ipairs(obj.getTags()) do
                if t == "Army1" or t == "Army2" then army_tag = t break end
            end
            if army_tag then
                local slot = tonumber(string.match(army_tag, "%d"))
                local pos  = obj.getPosition()
                local z_abs = math.abs(pos.z)
                local x_abs = math.abs(pos.x)
                local z_ok     = z_abs >= Z_NEAR and z_abs <= Z_FAR
                local x_ok     = x_abs <= X_MAX
                local z_sign_ok = (slot == 1 and pos.z < 0) or (slot == 2 and pos.z > 0)

                if not z_ok or not x_ok then
                    table.insert(errori[slot].fuori, nome)
                    table.insert(basi_errate, {obj=obj, pos=pos})
                elseif not z_sign_ok then
                    table.insert(errori[slot].sbagliata, nome)
                    table.insert(basi_errate, {obj=obj, pos=pos})
                end
            end
        end
    end

    -- Evidenzia basi errate con highlight rosso
    for _, b in ipairs(basi_errate) do
        if b and b.obj then
            b.obj.highlightOn({r=1, g=0.1, b=0.1}, 15)
        end
    end

    local totale = 0
    local basi_trovate = 0
    for slot = 1, 2 do
        local e = errori[slot]
        local n = #e.fuori + #e.sbagliata
        totale = totale + n
        if n > 0 then
            local nome_breve = (ARMY[slot] and ARMY[slot].nome_breve) or ("Army" .. slot)
            printToAll("── Army " .. slot .. " (" .. nome_breve .. ") ──", {r=1,g=0.8,b=0.2})
            if #e.fuori > 0 then
                printToAll("Fuori zona:", {r=1,g=0.5,b=0})
                for _, n in ipairs(e.fuori) do
                    printToAll("  " .. n, {r=1,g=0.7,b=0.3})
                end
            end
            if #e.sbagliata > 0 then
                printToAll("Zona sbagliata:", {r=1,g=0.3,b=0.3})
                for _, n in ipairs(e.sbagliata) do
                    printToAll("  " .. n, {r=1,g=0.4,b=0.4})
                end
            end
        end
    end
    basi_trovate = totale + (function()
        local c = 0
        for _, obj in ipairs(getAllObjects()) do
            for _, t in ipairs(obj.getTags()) do
                if t == "Army1" or t == "Army2" then c = c + 1 break end
            end
        end
        return c
    end)()

    if basi_trovate == 0 then
        printToAll("[DEPLOY] Nessuna base trovata — fai prima !deploy!", {r=1,g=0.3,b=0.3})
        return false
    end

    if totale == 0 then
        printToAll("[DEPLOY] OK — tutte le basi nelle zone corrette!", {r=0.4,g=0.9,b=0.4})
        return true
    end
    return false
end


-- Svuota le Hidden Zone — le basi diventano visibili a tutti
-- ------------------------------------------------------------
function reveal()
    local count = 0
    for _, zona_nome in ipairs({"Hz1", "Hz2"}) do
        local zona_guid = trovaZona(zona_nome)
        local zona = zona_guid and getObjectFromGUID(zona_guid)
        if zona then
            local oggetti = zona.getObjects()
            for _, obj in ipairs(oggetti) do
                local pos = obj.getPosition()
                obj.setPosition({x=pos.x, y=pos.y + 0.5, z=pos.z})
                count = count + 1
            end
        end
    end
    printToAll("[REVEAL] " .. count .. " basi rivelate — buona battaglia!", {r=0.4,g=0.9,b=0.4})
end

-- ------------------------------------------------------------
-- FUNZIONE: leggiUrlDaNotebook(nome)
-- Legge l'URL dalla description di una Notecard con quel nome
-- fallback alle costanti ARMY1_URL / ARMY2_URL
-- ------------------------------------------------------------
function leggiUrlDaNotebook(nome)
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == nome then
            local url = obj.getDescription()
            if url then
                url = url:gsub("^%s+", ""):gsub("%s+$", "")
                if url ~= "" then return url end
            end
        end
    end
    -- Fallback alle costanti
    if nome == "Army1" and ARMY1_URL then return ARMY1_URL end
    if nome == "Army2" and ARMY2_URL then return ARMY2_URL end
    printToAll("[LIONHEART] Notecard '" .. nome .. "' non trovata", {r=1,g=0.3,b=0.3})
    return nil
end

-- ------------------------------------------------------------
-- FUNZIONE: caricaEsercito(url, slot, player)
-- Scarica JSON e genera le basi clonando i template
-- ------------------------------------------------------------
function caricaEsercito(url, slot, player)
    printToAll("[CARICA] Download JSON esercito " .. slot .. "...", {r=0.8,g=0.8,b=0.8})

    local player_name  = player and player.steam_name or "---"
    local player_color = player and player.color or "---"

    WebRequest.get(url, function(request)
        if request.is_error then
            printToAll("[CARICA] Errore download: " .. request.error, {r=1,g=0.3,b=0.3})
            return
        end

        local ok, dati = pcall(JSON.decode, request.text)
        if not ok or not dati then
            printToAll("[CARICA] Errore parsing JSON", {r=1,g=0.3,b=0.3})
            return
        end

        if slot == "1" then
            ARMY[1].tag = dati.tag
            ARMY[1].nome = dati.nome
            ARMY[1].nome_breve = dati["nome-breve"] or dati.tag
            ARMY[1].player = player_name
            ARMY[1].color = player_color
            aggiornaPannello(1)
            aggiornaBanner()
            -- Assegna colore player alla Hidden Zone
            local gz = trovaZona("Hz1")
            if gz then getObjectFromGUID(gz).setValue(player_color) end
        else
            ARMY[2].tag = dati.tag
            ARMY[2].nome = dati.nome
            ARMY[2].nome_breve = dati["nome-breve"] or dati.tag
            ARMY[2].player = player_name
            ARMY[2].color = player_color
            aggiornaPannello(2)
            aggiornaBanner()
            -- Assegna colore player alla Hidden Zone
            local gz = trovaZona("Hz2")
            if gz then getObjectFromGUID(gz).setValue(player_color) end
        end

        local zona_nome = "HiddenZone" .. slot
        local zona_guid = trovaZona(zona_nome)
        local contatori = {}
        local army_tag  = "Army" .. slot  -- Army1 o Army2

        printToAll("[CARICA] Esercito: " .. dati.nome .. " | Tag: " .. army_tag, {r=0.4,g=0.9,b=0.4})

        for _, unita in ipairs(dati.unita) do
            generaUnita(unita, army_tag, zona_guid, contatori, slot)
        end

        printToAll("[CARICA] Completato — digita !deploy per scansionare", {r=0.4,g=0.9,b=0.4})
    end)
end

-- ------------------------------------------------------------
-- FUNZIONE: generaUnita(unita, tag, zona_guid, contatori)
-- Clona il template per ogni base — model: base.model > unita.model > unita.tipo
-- nickname: tipo_unitanum.baseid_mod_arma
-- ------------------------------------------------------------
function generaUnita(unita, tag, zona_guid, contatori, slot)
    -- Incrementa contatore per questo tipo
    contatori[unita.tipo] = (contatori[unita.tipo] or 0) + 1
    local unita_num = contatori[unita.tipo]

    -- Offset spawn (CinC ha posizione assoluta, no offset)
    local offset = (unita.tipo == "CinC") and {x=0,y=0,z=0} or (SPAWN_POS[tonumber(slot)] or {x=0,y=0,z=0})

    printToAll("[CARICA] " .. unita.tipo .. "_" .. unita_num
               .. " (" .. unita.nome_display .. ") x" .. #unita.basi, {r=0.8,g=0.8,b=0.8})

    for _, base in ipairs(unita.basi) do
        -- Determina quale oggetto clonare
        local template_name = base.model or unita.model or unita.tipo
        local template = nil
        for _, obj in ipairs(getAllObjects()) do
            if obj.getName() == template_name then
                template = obj
                break
            end
        end

        if not template then
            printToAll("[CARICA] Template non trovato: " .. template_name, {r=1,g=0.3,b=0.3})
        else
            -- Nickname: tipo_unitanum.seq_mod_arma
            local nickname = unita.tipo .. "_" .. unita_num .. "." .. base.seq
            if unita.modificatore then
                nickname = nickname .. "_" .. unita.modificatore
            end
            if base.arma then
                nickname = nickname .. "_" .. base.arma
            end

            -- Legge rotazione Y dal template
            local template_rot = template.getRotation()

            local clone = template.clone({
                position = {
                    x = base.posizione.x + offset.x,
                    y = base.posizione.y,
                    z = base.posizione.z + offset.z
                },
            })
            clone.setLock(true)

            local b = base
            Wait.frames(function()
                clone.setName(nickname)
                clone.setRotation({x=b.rotazione.x, y=template_rot.y, z=b.rotazione.z})
                clone.setPosition({
                    x = b.posizione.x + offset.x,
                    y = b.posizione.y,
                    z = b.posizione.z + offset.z
                })
                clone.addTag(tag)
                clone.setDescription(unita.nome_display)
                -- Nasconde la base al giocatore nemico durante il deploy
                local nemico_color = slot == "1" and ARMY[2].color or ARMY[1].color
                if nemico_color and nemico_color ~= "---" then
                    clone.setInvisibleTo({nemico_color})
                end
                clone.auto_raise = true
                clone.setLock(false)
                if b.ferite and b.ferite > 0 then
                    wounds_data[nickname] = b.ferite
                    local d = DATI_UNITA[unita.tipo]
                    local fpb = d and d.fpb or 3
                    aggiornaTintaBase(clone, b.ferite, fpb)
                end
            end, 10)
        end
    end
end


-- ------------------------------------------------------------
-- FUNZIONE: scanTavolo()
-- ------------------------------------------------------------
function scanTavolo()
    esercito_1  = {}
    esercito_2  = {}
    wounds_data = {}

    -- Rivela entrambi gli eserciti
    reveal()

    local gruppi_1  = {}
    local gruppi_2  = {}
    local gia_visti = {}

    for _, obj in ipairs(getAllObjects()) do
        local tags    = obj.getTags()
        local fazione = nil
        for _, tag in ipairs(tags) do
            if tag == "Army1" then fazione = "1" end
            if tag == "Army2" then fazione = "2" end
        end
        if fazione then
            local nickname = obj.getName()
            if nickname ~= "" and not gia_visti[nickname] then
                local dati = parsaNome(nickname)
                if dati then
                    gia_visti[nickname] = true
                    local chiave = dati.tipo .. "_" .. dati.unita_num
                    local gruppi = fazione == "1" and gruppi_1 or gruppi_2
                    local d      = DATI_UNITA[dati.tipo]

                    if not gruppi[chiave] then
                        gruppi[chiave] = {
                            tipo      = dati.tipo,
                            unita_num = dati.unita_num,
                            valore    = dati.valore,
                            lancieri  = dati.lancieri,
                            arma      = dati.arma,
                            fpb       = d.fpb,
                            basi_max  = d.basi,
                            fazione   = fazione,
                            basi      = {},
                        }
                    end

                    table.insert(gruppi[chiave].basi, {
                        nickname = nickname,
                        guid     = obj.getGUID(),
                    })

                    wounds_data[nickname] = 0
                    obj.highlightOff()
                    obj.setDescription("")
                    aggiornaTagInjured(obj, 0)
                end
            end
        end
    end

    local function gruppiToLista(gruppi, tag)
        local lista = {}
        for _, unita in pairs(gruppi) do
            unita.nome_display = tag .. "_" .. unita.tipo .. "_" .. unita.unita_num
            table.insert(lista, unita)
        end
        table.sort(lista, function(a,b)
            if a.tipo ~= b.tipo then return a.tipo < b.tipo end
            return a.unita_num < b.unita_num
        end)
        return lista
    end

    esercito_1 = gruppiToLista(gruppi_1, (ARMY[1].tag or "ARMY1"))
    esercito_2 = gruppiToLista(gruppi_2, (ARMY[2].tag or "ARMY2"))

    printToAll("=== LIONHEART BOT " .. VERSION .. " ===", {r=0.8,g=0.6,b=0.1})
    printToAll((ARMY[1].tag or "ARMY1") .. ": " .. #esercito_1 .. " unita", {r=0.9,g=0.2,b=0.2})
    printToAll((ARMY[2].tag or "ARMY2") .. ": " .. #esercito_2 .. " unita", {r=0.2,g=0.4,b=0.9})

    printToAll("--- " .. (ARMY[1].tag or "ARMY1") .. " ---", {r=0.9,g=0.2,b=0.2})
    for _, u in ipairs(esercito_1) do
        local val_str = ""
        if u.valore == 1  then val_str = " | Superiore" end
        if u.valore == -1 then val_str = " | Inferiore" end
        local info = u.nome_display .. " | Basi: " .. #u.basi .. "/" .. u.basi_max .. val_str
        if u.lancieri then info = info .. " [LANC]" end
        if u.arma     then info = info .. " [" .. u.arma .. "]" end
        printToAll(info, {r=0.9,g=0.2,b=0.2})
    end

    printToAll("--- " .. (ARMY[2].tag or "ARMY2") .. " ---", {r=0.2,g=0.4,b=0.9})
    for _, u in ipairs(esercito_2) do
        local val_str = ""
        if u.valore == 1  then val_str = " | Superiore" end
        if u.valore == -1 then val_str = " | Inferiore" end
        local info = u.nome_display .. " | Basi: " .. #u.basi .. "/" .. u.basi_max .. val_str
        if u.lancieri then info = info .. " [LANC]" end
        if u.arma     then info = info .. " [" .. u.arma .. "]" end
        printToAll(info, {r=0.2,g=0.4,b=0.9})
    end

    printToAll("=== PRONTO ===", {r=0.4,g=0.9,b=0.4})

    -- Aggiorna pannelli UI
    aggiornaPannello(1)
    aggiornaPannello(2)

    turno_corrente = 0
    fase_corrente  = 0
    iniziativa_tag = (ARMY[1].tag or "ARMY1")
    aggiornaBanner()
end

-- ------------------------------------------------------------
-- FUNZIONE: trovaOggettoPerNome(nickname)
-- ------------------------------------------------------------
function trovaOggettoPerNome(nickname)
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == nickname then return obj end
    end
    return nil
end

-- ------------------------------------------------------------
-- FUNZIONE: trovaBase(nome_base)
-- ------------------------------------------------------------
function trovaBase(nome_base)
    local function cerca(lista)
        if not lista then return nil, nil end
        for _, unita in ipairs(lista) do
            for _, base in ipairs(unita.basi) do
                if base.nickname == nome_base then
                    return unita, base
                end
            end
        end
        return nil, nil
    end

    local unita, base = cerca(esercito_1)
    if unita then return unita, base, "1" end
    unita, base = cerca(esercito_2)
    if unita then return unita, base, "2" end
    return nil, nil, nil
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaTagInjured(obj, wounds)
-- ------------------------------------------------------------
function aggiornaTagInjured(obj, wounds)
    obj.removeTag("injured1")
    obj.removeTag("injured2")
    obj.removeTag("injured3")
    if wounds == 1 then
        obj.addTag("injured1")
    elseif wounds == 2 then
        obj.addTag("injured2")
    elseif wounds >= 3 then
        obj.addTag("injured3")
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaTintaBase(obj, wounds, fpb)
-- ------------------------------------------------------------
function aggiornaTintaBase(obj, wounds, fpb)
    if wounds < 1 then
        if VISUALIZZAZIONE_FERITE == "highlight" then
            obj.highlightOff()
        else
            obj.setColorTint({r=1, g=1, b=1})
        end
        aggiornaTagInjured(obj, 0)
        return
    end

    local colore
    if wounds == 1 then
        colore = {r=1, g=0.75, b=0.39}
    elseif wounds == 2 then
        colore = {r=1, g=0.55, b=0}
    else
        colore = {r=0.71, g=0.33, b=0}
    end

    if VISUALIZZAZIONE_FERITE == "highlight" then
        obj.highlightOn(colore)
    else
        obj.setColorTint(colore)
    end

    aggiornaTagInjured(obj, wounds)
    obj.setDescription("Ferite: " .. wounds .. "/" .. fpb)
end

-- ------------------------------------------------------------
-- FUNZIONE: registraWounds(nome_base, n_ferite)
-- ------------------------------------------------------------
function registraWounds(nome_base, n_ferite)
    local unita, base, fazione = trovaBase(nome_base)
    if not unita then
        printToAll("[LIONHEART] Base non trovata: " .. nome_base, {r=1,g=0.3,b=0.3})
        return
    end

    local obj = trovaOggettoPerNome(nome_base)
    if not obj then
        printToAll("[LIONHEART] Oggetto non trovato: " .. nome_base, {r=1,g=0.3,b=0.3})
        return
    end

    local fpb              = DATI_UNITA[unita.tipo].fpb
    local wounds_attuali   = wounds_data[nome_base] or 0
    local wounds_totali    = math.min(wounds_attuali + n_ferite, fpb)
    wounds_data[nome_base] = wounds_totali

    aggiornaTintaBase(obj, wounds_totali, fpb)

    if wounds_totali >= fpb then
        printToAll("⚠ RIMUOVI BASE: " .. nome_base
                   .. " (" .. wounds_totali .. "/" .. fpb .. " ferite)",
                   {r=1,g=0.3,b=0.3})
    else
        printToAll("[WOUNDS] " .. nome_base .. ": " .. wounds_totali .. "/" .. fpb .. " ferite",
                   {r=1,g=0.7,b=0.2})
    end

    verificaMorale(unita, fazione)
end

-- ------------------------------------------------------------
-- FUNZIONE: resetWounds(nome_base)
-- ------------------------------------------------------------
function resetWounds(nome_base)
    local unita, base, fazione = trovaBase(nome_base)
    if not unita then
        printToAll("[LIONHEART] Base non trovata: " .. nome_base, {r=1,g=0.3,b=0.3})
        return
    end

    wounds_data[nome_base] = 0

    local obj = trovaOggettoPerNome(nome_base)
    if obj then
        if VISUALIZZAZIONE_FERITE == "highlight" then
            obj.highlightOff()
        else
            obj.setColorTint({r=1, g=1, b=1})
        end
        obj.setDescription("")
        aggiornaTagInjured(obj, 0)
    end

    printToAll("[RESET] " .. nome_base .. " azzerata", {r=0.4,g=0.9,b=0.4})
end

-- ------------------------------------------------------------
-- FUNZIONE: figureTotaliUnita(unita)
-- ------------------------------------------------------------
function figureTotaliUnita(unita)
    local figure = 0
    local fpb    = DATI_UNITA[unita.tipo].fpb
    for _, base in ipairs(unita.basi) do
        if trovaOggettoPerNome(base.nickname) then
            local wounds = wounds_data[base.nickname] or 0
            figure = figure + (fpb - math.min(wounds, fpb))
        end
    end
    return figure
end

-- ------------------------------------------------------------
-- FUNZIONE: basiPresentiUnita(unita)
-- ------------------------------------------------------------
function basiPresentiUnita(unita)
    local count = 0
    for _, base in ipairs(unita.basi) do
        if trovaOggettoPerNome(base.nickname) then count = count + 1 end
    end
    return count
end

-- ------------------------------------------------------------
-- FUNZIONE: verificaMorale(unita, fazione)
-- ------------------------------------------------------------
function verificaMorale(unita, fazione)
    local figure_att = figureTotaliUnita(unita)
    local fpb        = DATI_UNITA[unita.tipo].fpb
    local figure_max = unita.basi_max * fpb
    local soglia     = math.floor(figure_max / 2)
    if figure_att <= soglia and figure_att > 0 then
        local colore = fazione == "1" and {r=0.9,g=0.2,b=0.2} or {r=0.2,g=0.4,b=0.9}
        printToAll("⚠ MORALE: " .. unita.nome_display
                   .. " sotto 50% (" .. figure_att .. "/" .. figure_max .. ")"
                   .. " | D6 necessario 4+ (mod: " .. (unita.valore >= 0 and "+" or "") .. unita.valore .. ")",
                   colore)
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: mostraStato()
-- ------------------------------------------------------------
function mostraStato()
    printToAll("=== STATO BATTAGLIA - TURNO " .. turno_corrente .. " ===", {r=0.8,g=0.8,b=0.8})
    local function stampa(lista, tag, colore)
        printToAll("-- " .. tag .. " --", colore)
        for _, u in ipairs(lista) do
            local fpb     = DATI_UNITA[u.tipo].fpb
            local fig_max = u.basi_max * fpb
            printToAll(u.nome_display
                       .. " | Basi: " .. basiPresentiUnita(u) .. "/" .. u.basi_max
                       .. " | Figure: " .. figureTotaliUnita(u) .. "/" .. fig_max,
                       colore)
        end
    end
    stampa(esercito_1, (ARMY[1].tag or "ARMY1"), {r=0.9,g=0.2,b=0.2})
    stampa(esercito_2, (ARMY[2].tag or "ARMY2"), {r=0.2,g=0.4,b=0.9})
end

-- ------------------------------------------------------------
-- FUNZIONE: getUnitaViva(esercito)
-- ------------------------------------------------------------
function getUnitaViva(esercito)
    local vive = {}
    for _, u in ipairs(esercito) do
        if basiPresentiUnita(u) > 0 then table.insert(vive, u) end
    end
    return vive
end

-- ------------------------------------------------------------
-- FUNZIONE: posizioneUnita(unita)
-- ------------------------------------------------------------
function posizioneUnita(unita)
    local sx, sy, sz, count = 0, 0, 0, 0
    for _, base in ipairs(unita.basi) do
        local obj = trovaOggettoPerNome(base.nickname)
        if obj then
            local pos = obj.getPosition()
            sx = sx + pos.x
            sy = sy + pos.y
            sz = sz + pos.z
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return {x=sx/count, y=sy/count, z=sz/count}
end

-- ------------------------------------------------------------
-- FUNZIONE: distanzaPlanare(posA, posB)
-- ------------------------------------------------------------
function distanzaPlanare(posA, posB)
    local dx = posA.x - posB.x
    local dz = posA.z - posB.z
    return math.sqrt(dx*dx + dz*dz)
end

-- ------------------------------------------------------------
-- FUNZIONE: trovaNemicoVicino(unita, nemici)
-- ------------------------------------------------------------
function trovaNemicoVicino(unita, nemici)
    local nemici_vivi = getUnitaViva(nemici)
    if #nemici_vivi == 0 then return nil, nil end

    local pos_unita = posizioneUnita(unita)
    if not pos_unita then return nil, nil end

    local nemico_vicino   = nil
    local distanza_minima = math.huge

    for _, nemico in ipairs(nemici_vivi) do
        local pos_nemico = posizioneUnita(nemico)
        if pos_nemico then
            local dist = distanzaPlanare(pos_unita, pos_nemico)
            if dist < distanza_minima then
                distanza_minima = dist
                nemico_vicino   = nemico
            end
        end
    end

    return nemico_vicino, distanza_minima
end

-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- FUNZIONE: playerTagToColor(tag)
-- Restituisce il colore TTS dal tag esercito
-- ------------------------------------------------------------
function playerTagToColor(tag)
    for slot = 1, 2 do
        if ARMY[slot].tag == tag then return ARMY[slot].color end
    end
    return nil
end

-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- FUNZIONE: impostaTurnoTTS(fase)
-- ------------------------------------------------------------
function impostaTurnoTTS(fase)
    Turns.enable = false
    if not fase.turno_tts then
        mano_tag = nil
        return
    end
    -- Chi ha iniziativa va per primo
    mano_tag = iniziativa_tag
    local nb = mano_tag
    for slot = 1, 2 do
        if ARMY[slot].tag == mano_tag then nb = ARMY[slot].nome_breve or mano_tag end
    end
    printToAll("-> " .. nb .. " muove per primo", {r=0.4,g=0.9,b=0.4})
end

-- ------------------------------------------------------------
-- FUNZIONE: avviaTurno()
-- ------------------------------------------------------------
function avviaTurno()
    turno_corrente    = turno_corrente + 1
    fase_corrente     = 1
    iniziativa_scelta = false
    Turns.enable      = false
    linee_deploy      = false
    aggiornaLinee()

    -- Rivela tutte le basi a tutti i giocatori
    for _, obj in ipairs(getAllObjects()) do
        for _, t in ipairs(obj.getTags()) do
            if t == "Army1" or t == "Army2" then
                obj.setInvisibleTo({})
                break
            end
        end
    end

    printToAll("=== TURNO " .. turno_corrente .. " === INIZIATIVA", {r=0.8,g=0.6,b=0.1})
    printToAll("Lanciate entrambi 1D6 — chi vince sceglie se muovere primo o secondo.", {r=0.8,g=0.6,b=0.1})

    aggiornaBanner()
    aggiornaPannello(1)
    aggiornaPannello(2)
end

-- ------------------------------------------------------------
-- FUNZIONE: avanzaFase()
-- ------------------------------------------------------------
function avanzaFase()
    if turno_corrente == 0 then
        printToAll("[LIONHEART] Digita prima !turno!", {r=1,g=0.3,b=0.3})
        return
    end

    -- Blocca se siamo in INIZIATIVA e il vincitore non ha ancora scelto
    if fase_corrente == 1 and not iniziativa_scelta then
        printToAll("[LIONHEART] Prima dichiara chi ha l'iniziativa!", {r=1,g=0.3,b=0.3})
        return
    end

    fase_corrente = fase_corrente + 1

    if fase_corrente > #FASI then
        Turns.enable = false
        printToAll("=== FINE TURNO " .. turno_corrente .. " — digita !turno per il prossimo ===", {r=0.4,g=0.9,b=0.4})
        fase_corrente = #FASI
        return
    end

    local fase   = FASI[fase_corrente]
    local nb_ini = iniziativa_tag
    for slot = 1, 2 do
        if ARMY[slot].tag == iniziativa_tag then
            nb_ini = ARMY[slot].nome_breve or iniziativa_tag
        end
    end

    printToAll("── FASE " .. fase_corrente .. ": " .. fase.nome .. " ──", {r=0.8,g=0.6,b=0.1})
    printToAll(fase.desc, {r=0.8,g=0.8,b=0.8})
    if fase.turno_tts then
        printToAll("-> " .. nb_ini .. " agisce per primo", {r=0.4,g=0.9,b=0.4})
    end
    printToAll("!fase quando la fase e' completata", {r=0.6,g=0.6,b=0.6})

    impostaTurnoTTS(fase)
    aggiornaBanner()
    aggiornaPannello(1)
    aggiornaPannello(2)
end