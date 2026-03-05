-- ============================================================
-- LIONHEART BOT - Tabletop Simulator
-- Versione 1.28.02 - Struttura ARMY[1/2], pannelli player
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
--   !deploy      -> mostra separè e linee di schieramento sul verde
--   !deploy off  -> rimuove separè e linee di schieramento
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
VERDE_LX      = 48
VERDE_LZ      = 32.23
DEPLOY_CM     = 8    -- 10 cm in unita TTS

-- GUID delle Scripting Zone di deploy
ZONA_1_GUID = "ed72ac"
ZONA_2_GUID = "fe1daa"

-- Struttura eserciti
ARMY = {
    [1] = { player = nil, tag = nil, nome = nil, color = nil, pannello_guid = nil },
    [2] = { player = nil, tag = nil, nome = nil, color = nil, pannello_guid = nil }
}

-- Posizioni pannelli informativi
PANNELLO_POS = {
    [1] = {x=-60.92, y=1.66, z=-41.71},
    [2] = {x= 60.92, y=1.66, z= 41.71}
}

-- Posizioni spawn eserciti
-- Base URL repository JSON
GITHUB_BASE_URL = "https://raw.githubusercontent.com/maxm4004/Tabletop-Simulator-Lua/refs/heads/main/ArmyJson/"

ARMY1_URL = GITHUB_BASE_URL .. "francesi.json"
ARMY2_URL = GITHUB_BASE_URL .. "inglesi.json"

SPAWN_POS = {
    [1] = {x=0, y=2.36, z=-43.60},
    [2] = {x=0, y=2.36, z= 43.60}
}

-- ------------------------------------------------------------
-- MONITOR FASE
-- Pannello nero fisso con 2 testi 3DText (nord e sud)
-- Pannello: pos {-0.01, 56.12, 0.00} rot {0,90,0} scale {2.5,26.82,47.14}
-- ------------------------------------------------------------
MONITOR_X      = -0.01
MONITOR_Y      = 66
MONITOR_Z      = 0
MONITOR_OFFSET = 1.5   -- distanza testo dal pannello

monitor_visibile = true
monitor_guids    = {}
monitor_schermo_guid = nil

function onScriptingButtonDown(index, player_color)
    if index == 1 then
        toggleMonitor()
    end
end

function toggleMonitor()
    monitor_visibile = not monitor_visibile
    local colore = monitor_visibile and {r=1, g=0.85, b=0.3} or {r=0, g=0, b=0}
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == "MONITOR_NORD" or obj.getName() == "MONITOR_SUD" then
            obj.TextTool.setFontColor(colore)
        end
    end
    printToAll("[MONITOR] " .. (monitor_visibile and "Visibile" or "Nascosto"), {r=0.6,g=0.6,b=0.6})
end

-- Sequenza fasi
FASI = {
    {nome="INIZIATIVA",  desc="Lancia 1D6 — chi vince sceglie se muovere primo o secondo"},
    {nome="MOVIMENTO",   desc="Prima le cariche, poi le manovre"},
    {nome="TIRO",        desc="Simultaneo — tira sempre al nemico piu vicino"},
    {nome="MISCHIA",     desc="Combatti le mischie derivanti dalle cariche"},
}
fase_corrente  = 1
iniziativa_tag = (ARMY[1].tag or "ARMY1")

-- ------------------------------------------------------------
-- TABELLA DATI REGOLAMENTO
-- ------------------------------------------------------------
DATI_UNITA = {
    AI  = { basi=3, fpb=4, dado_tiro_div=3   },
    UI  = { basi=4, fpb=3, dado_tiro_div=3   },
    SK  = { basi=4, fpb=2, dado_tiro_div=4   },
    AC  = { basi=2, fpb=3, dado_tiro_div=nil },
    UC  = { basi=2, fpb=3, dado_tiro_div=nil },
    SKC = { basi=2, fpb=2, dado_tiro_div=nil },
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
    local tipo = string.match(obj.getName(), "^([A-Z]+)")
    if not tipo or not DATI_UNITA[tipo] then return end

    obj.addContextMenuItem("Metti in colonna", function(player)
        mettInColonnaOggetto(obj, player)
    end)
end

-- ------------------------------------------------------------
-- FUNZIONE: onObjectSpawn(obj)
-- ------------------------------------------------------------
function onObjectSpawn(obj)
    Wait.frames(function()
        aggiungiMenuBase(obj)
    end, 5)
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
-- Spawna i due pannelli informativi sul tavolo
-- ------------------------------------------------------------
function spawnaPannelli()
    for slot = 1, 2 do
        -- Cerca pannello esistente per nome
        local existing = nil
        for _, obj in ipairs(getAllObjects()) do
            if obj.getName() == "PANNELLO_ARMY" .. slot then
                existing = obj
                break
            end
        end
        if existing then
            ARMY[slot].pannello_guid = existing.getGUID()
        else
            local pos = PANNELLO_POS[slot]
            local rot = slot == 1 and {x=90,y=0,z=0} or {x=90,y=180,z=0}
            local s = slot
            spawnObject({
                type = "3DText",
                position = pos,
                rotation = rot,
                scale = {x=100, y=100, z=100},
                callback_function = function(obj)
                    obj.setName("PANNELLO_ARMY" .. s)
                    obj.setColorTint({r=0.5,g=0.5,b=0.5})
                    obj.TextTool.setValue("ARMY " .. s .. "\nIn attesa...")
                    ARMY[s].pannello_guid = obj.getGUID()
                end
            })
        end
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaPannello(slot)
-- Aggiorna il testo del pannello per Army 1 o 2
-- ------------------------------------------------------------
function aggiornaPannello(slot)
    local a = ARMY[slot]
    local guid = a.pannello_guid
    if not guid then return end
    local obj = getObjectFromGUID(guid)
    if not obj then return end

    local player = a.player or "---"
    local tag    = a.tag    or "---"
    local nome   = a.nome   or "---"
    local color  = a.color  or "---"
    local testo  = "ARMY " .. slot .. "\n"
                .. "Player: " .. player .. "\n"
                .. "Colore: " .. color .. "\n"
                .. "Tag:    " .. tag .. "\n"
                .. "Esercito: " .. nome
    obj.TextTool.setValue(testo)
    obj.setColorTint({r=1, g=0.85, b=0.3})
end

-- ------------------------------------------------------------
function onLoad()
    log("[LIONHEART] Script caricato v1.28.02")
    log("[LIONHEART]   !caricaArmy1 URL -> carica esercito 1 da JSON")
    log("[LIONHEART]   !caricaArmy2 URL -> carica esercito 2 da JSON")
    log("[LIONHEART]   !reveal      -> rivela entrambi gli eserciti")
    log("[LIONHEART]   !inizia      -> scansiona il tavolo")
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
    log("[LIONHEART]   !deploy      -> linee di schieramento sul verde")
    log("[LIONHEART]   !deploy off  -> rimuove linee di schieramento")
    log("[LIONHEART]   Tasto 1      -> mostra/nasconde monitor fase")

    -- Spawna pannelli informativi
    spawnaPannelli()

    -- Rettangoli spawn sempre visibili
    linee_rettangolo = true
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
    if message == "!caricaArmy1" then
        local url = leggiUrlDaNotebook("Army1")
        if url then
            caricaEsercito(url, "1", player)
        else
            printToAll("[LIONHEART] Notebook 'Army1' non trovato o vuoto", {r=1,g=0.3,b=0.3})
        end
        return false
    end

    if message == "!caricaArmy2" then
        local url = leggiUrlDaNotebook("Army2")
        if url then
            caricaEsercito(url, "2", player)
        else
            printToAll("[LIONHEART] Notebook 'Army2' non trovato o vuoto", {r=1,g=0.3,b=0.3})
        end
        return false
    end

    if message == "!reveal" then
        reveal()
        return false
    end

    if message == "!inizia" then
        scanTavolo()
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

    if message == "!deploy" then
        spawnaDeploy()
        return false
    end

    if message == "!deploy off" then
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

        -- Separè centrale (bianco)
        table.insert(linee, {
            points    = {{x=-VERDE_LX, y=y, z=0}, {x=VERDE_LX, y=y, z=0}},
            color     = {r=1, g=1, b=1},
            thickness = 0.25,
        })

        -- Linea deploy (ARMY[1].tag or "ARMY1") (rosso) — bordo nord
        local z1 = -(VERDE_LZ - DEPLOY_CM)
        table.insert(linee, {
            points    = {{x=-VERDE_LX, y=y, z=z1}, {x=VERDE_LX, y=y, z=z1}},
            color     = {r=0.9, g=0.2, b=0.2},
            thickness = 0.25,
        })

        -- Linea deploy (ARMY[2].tag or "ARMY2") (blu) — bordo sud
        local z2 = (VERDE_LZ - DEPLOY_CM)
        table.insert(linee, {
            points    = {{x=-VERDE_LX, y=y, z=z2}, {x=VERDE_LX, y=y, z=z2}},
            color     = {r=0.2, g=0.4, b=0.9},
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
        printToAll("[LIONHEART] Oggetto non valido: " .. nickname .. " — fai !inizia prima", {r=1,g=0.3,b=0.3})
        return nil
    end
    return nickname
end

-- ------------------------------------------------------------
-- FUNZIONE: parsaNome(nickname)
-- Formato nuovo: AC1, AC1_S, UI7_BAL, UI15_I_ARCL
-- tipo = parte alfabetica iniziale, seq = numero dopo il tipo
-- ------------------------------------------------------------
function parsaNome(nickname)
    -- Estrai tipo (lettere iniziali) e seq (numero subito dopo)
    local tipo, seq_str = string.match(nickname, "^([A-Z]+)(%d+)")
    if not tipo or not seq_str then return nil end
    if not DATI_UNITA[tipo] then return nil end

    local valore   = 0
    local lancieri = false
    local arma     = nil

    -- Analizza i modificatori dopo il seq
    local resto = string.sub(nickname, #tipo + #seq_str + 1)
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
        unita_num = tonumber(seq_str),
        base_num  = 1,
        valore    = valore,
        lancieri  = lancieri,
        arma      = arma,
        fpb       = d.fpb,
        basi_max  = d.basi,
    }
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
-- FUNZIONE: reveal()
-- Svuota le Hidden Zone — le basi diventano visibili a tutti
-- ------------------------------------------------------------
function reveal()
    local count = 0
    for _, zona_guid in ipairs({ZONA_1_GUID, ZONA_2_GUID}) do
        local zona = getObjectFromGUID(zona_guid)
        if zona then
            local oggetti = zona.getObjects()
            for _, obj in ipairs(oggetti) do
                -- Sposta leggermente l'oggetto fuori dalla zona
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
            ARMY[1].player = player_name
            ARMY[1].color = player_color
            aggiornaPannello(1)
        else
            ARMY[2].tag = dati.tag
            ARMY[2].nome = dati.nome
            ARMY[2].player = player_name
            ARMY[2].color = player_color
            aggiornaPannello(2)
        end

        local zona_guid = slot == "1" and ZONA_1_GUID or ZONA_2_GUID
        local contatori = {}  -- contatore progressivo per tipo unita

        printToAll("[CARICA] Esercito: " .. dati.nome .. " | Tag: " .. dati.tag, {r=0.4,g=0.9,b=0.4})

        for _, unita in ipairs(dati.unita) do
            generaUnita(unita, dati.tag, zona_guid, contatori, slot)
        end

        printToAll("[CARICA] Completato — digita !inizia per scansionare", {r=0.4,g=0.9,b=0.4})
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

    -- Reset pannelli
    ARMY[1] = { player=nil, tag=nil, nome=nil, color=nil, pannello_guid=ARMY[1].pannello_guid }
    ARMY[2] = { player=nil, tag=nil, nome=nil, color=nil, pannello_guid=ARMY[2].pannello_guid }
    for slot = 1, 2 do
        local obj = ARMY[slot].pannello_guid and getObjectFromGUID(ARMY[slot].pannello_guid)
        if obj then obj.TextTool.setValue("ARMY " .. slot .. "\nIn attesa...") end
    end

    local gruppi_1  = {}
    local gruppi_2  = {}
    local gia_visti = {}

    for _, obj in ipairs(getAllObjects()) do
        local tags    = obj.getTags()
        local fazione = nil
        for _, tag in ipairs(tags) do
            if tag == (ARMY[1].tag or "ARMY1") then fazione = "1" end
            if tag == (ARMY[2].tag or "ARMY2") then fazione = "2" end
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

    printToAll("=== LIONHEART BOT v1.28.02 ===", {r=0.8,g=0.6,b=0.1})
    printToAll((ARMY[1].tag or "ARMY1") .. ": " .. #esercito_1 .. " unita", {r=0.9,g=0.2,b=0.2})
    printToAll((ARMY[2].tag or "ARMY2") .. ": " .. #esercito_2 .. " unita", {r=0.2,g=0.4,b=0.9})

    printToAll("--- " .. (ARMY[1].tag or "ARMY1") .. " ---", {r=0.9,g=0.2,b=0.2})
    for _, u in ipairs(esercito_1) do
        local info = u.nome_display .. " | Basi: " .. #u.basi .. "/" .. u.basi_max .. " | Val: " .. u.valore
        if u.lancieri then info = info .. " [LANC]" end
        if u.arma     then info = info .. " [" .. u.arma .. "]" end
        printToAll(info, {r=0.9,g=0.2,b=0.2})
    end

    printToAll("--- " .. (ARMY[2].tag or "ARMY2") .. " ---", {r=0.2,g=0.4,b=0.9})
    for _, u in ipairs(esercito_2) do
        local info = u.nome_display .. " | Basi: " .. #u.basi .. "/" .. u.basi_max .. " | Val: " .. u.valore
        if u.lancieri then info = info .. " [LANC]" end
        if u.arma     then info = info .. " [" .. u.arma .. "]" end
        printToAll(info, {r=0.2,g=0.4,b=0.9})
    end

    printToAll("=== PRONTO ===", {r=0.4,g=0.9,b=0.4})

    -- Resetta monitor se attivo
    turno_corrente = 0
    fase_corrente  = 1
    iniziativa_tag = (ARMY[1].tag or "ARMY1")
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == "MONITOR_NORD" or obj.getName() == "MONITOR_SUD" then
            obj.setValue("IN ATTESA\n\nDigita !turno\nper iniziare")
            obj.TextTool.setFontColor({r=1, g=0.85, b=0.3})
        end
    end
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
-- FUNZIONE: testoPannello()
-- ------------------------------------------------------------
function testoPannello()
    local fase = FASI[fase_corrente]
    return "TURNO " .. turno_corrente
        .. "\n\nFASE: " .. fase.nome
        .. "\n\n-> " .. iniziativa_tag
        .. "\n\n" .. fase.desc
end

-- ------------------------------------------------------------
-- FUNZIONE: aggiornaMonitor()
-- Aggiorna il testo su entrambi i lati del monitor
-- ------------------------------------------------------------
function aggiornaMonitor()
    local testo = testoPannello()
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == "MONITOR_NORD" or obj.getName() == "MONITOR_SUD" then
            obj.setValue(testo)
            obj.TextTool.setFontColor({r=1, g=0.85, b=0.3})
        end
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: spawnaMonitor()
-- ------------------------------------------------------------
function spawnaMonitor()
    -- Rimuovi monitor esistenti cercando per nome
    for _, obj in ipairs(getAllObjects()) do
        if obj.getName() == "MONITOR_NORD" or obj.getName() == "MONITOR_SUD" then
            obj.destruct()
        end
    end
    monitor_guids = {}

    local testo = testoPannello()

    -- Testo lato nord
    spawnObject({
        type     = "3DText",
        position = {x=MONITOR_X, y=MONITOR_Y, z=MONITOR_Z - MONITOR_OFFSET},
        rotation = {x=0, y=0, z=0},
        scale    = {x=20, y=20, z=20},
        callback_function = function(obj)
            obj.setName("MONITOR_NORD")
            obj.setValue(testo)
            obj.TextTool.setFontSize(120)
            obj.TextTool.setFontColor({r=1, g=0.85, b=0.3})
            obj.setLock(true)
            table.insert(monitor_guids, obj.getGUID())
        end
    })

    -- Testo lato sud
    spawnObject({
        type     = "3DText",
        position = {x=MONITOR_X, y=MONITOR_Y, z=MONITOR_Z + MONITOR_OFFSET},
        rotation = {x=0, y=180, z=0},
        scale    = {x=20, y=20, z=20},
        callback_function = function(obj)
            obj.setName("MONITOR_SUD")
            obj.setValue(testo)
            obj.TextTool.setFontSize(120)
            obj.TextTool.setFontColor({r=1, g=0.85, b=0.3})
            obj.setLock(true)
            table.insert(monitor_guids, obj.getGUID())
        end
    })

    printToAll("[MONITOR] Attivo", {r=0.4,g=0.9,b=0.4})
end

-- ------------------------------------------------------------
-- FUNZIONE: avviaTurno()
-- ------------------------------------------------------------
function avviaTurno()
    turno_corrente = turno_corrente + 1
    fase_corrente  = 1

    -- Iniziativa
    local d1 = math.random(1, 6)
    local d2 = math.random(1, 6)
    while d1 == d2 do
        d1 = math.random(1, 6)
        d2 = math.random(1, 6)
    end

    iniziativa_tag = d1 > d2 and (ARMY[1].tag or "ARMY1") or (ARMY[2].tag or "ARMY2")

    printToAll("=== TURNO " .. turno_corrente .. " ===", {r=0.8,g=0.6,b=0.1})
    printToAll("INIZIATIVA: " .. (ARMY[1].tag or "ARMY1") .. " tira " .. d1 .. " | " .. (ARMY[2].tag or "ARMY2") .. " tira " .. d2, {r=0.8,g=0.8,b=0.8})
    printToAll("-> " .. iniziativa_tag .. " ha l'iniziativa", {r=0.4,g=0.9,b=0.4})
    printToAll("Digita !fase per avanzare", {r=0.6,g=0.6,b=0.6})

    if #monitor_guids == 0 then
        spawnaMonitor()
    else
        aggiornaMonitor()
    end
end

-- ------------------------------------------------------------
-- FUNZIONE: avanzaFase()
-- ------------------------------------------------------------
function avanzaFase()
    if turno_corrente == 0 then
        printToAll("[LIONHEART] Digita prima !turno!", {r=1,g=0.3,b=0.3})
        return
    end

    fase_corrente = fase_corrente + 1

    if fase_corrente > #FASI then
        printToAll("=== FINE TURNO " .. turno_corrente .. " — digita !turno per il prossimo ===",
                   {r=0.4,g=0.9,b=0.4})
        fase_corrente = #FASI
        return
    end

    local fase = FASI[fase_corrente]
    printToAll("FASE " .. fase_corrente .. ": " .. fase.nome .. " — " .. fase.desc,
               {r=0.8,g=0.6,b=0.1})
    printToAll("-> " .. iniziativa_tag .. " agisce per primo | !fase quando pronto",
               {r=0.6,g=0.6,b=0.6})

    aggiornaMonitor()
end