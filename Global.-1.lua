-- ============================================================
--   LIONHEART BOT - Tabletop Simulator
-- ============================================================
VERSION = "v1.35.07"
DEBUG   = false  -- false = controlli player attivi

-- TAG_1 = function() return (ARMY[1].tag or "ARMY1") end
-- TAG_2 = function() return (ARMY[2].tag or "ARMY2") end

-- VISUALIZZAZIONE_FERITE       = "tint"
-- COLORE_UNITA_BERSAGLIO_TIRO  = {0.4, 0.8, 1}
-- POSIZIONAMENTO_SU_TAVOLO = false
-- ------------------------------------------------------------
-- COORDINATE TAVOLO NERO
-- ------------------------------------------------------------
-- TAVOLO_Y  = 3.35
-- TAVOLO_LX = 90
-- TAVOLO_LZ = 68

-- ------------------------------------------------------------
-- COORDINATE VERDE
-- ------------------------------------------------------------
-- VERDE_Y       = 2.36
-- VERDE_Y_LINEE = 3.36
-- VERDE_LX      = 50
-- VERDE_LZ      = 32.23
-- DEPLOY_CM     = 8

-- ------------------------------------------------------------
-- STRUTTURA ESERCITI
-- ------------------------------------------------------------
ARMY = {
[1] = { player=nil, tag=nil, nome=nil, nome_display=nil, color=nil, pannello_guid=nil },
[2] = { player=nil, tag=nil, nome=nil, nome_display=nil, color=nil, pannello_guid=nil }
}

linee_settori    = false
pronto_red       = false
pronto_green     = false
Army1DeployDone  = false
Army2DeployDone  = false
segnalini_guids  = {}

FASI = {}
DATI_UNITA = {}
ARMI_TIRO = {}

fase_corrente        = 0
iniziativa_tag       = (ARMY[1].tag or "ARMY1")
iniziativa_scelta    = false
mano_tag             = nil
mano_passata         = false
unita_fired          = {}
animazioneTiroAttiva = false

wounds_data      = {}
target_acquisito = nil
esercito_1       = {}
esercito_2       = {}
turno_corrente   = 0
linee_croce      = false
linee_deploy     = false
linee_rettangolo = false
templates = nil

-- ------------------------------------------------------------
-- VARIABILI URL DI CONFIGURAZIONE JSON
-- ------------------------------------------------------------
MAIN_URL = "https://raw.githubusercontent.com/maxm4004/Tabletop-Simulator-Lua/refs/heads/main/Json/main.json"
REGOLAMENTO_URL = ""
CONFIG_URL      = ""
ARMY1_URL       = ""
ARMY2_URL       = ""
ELEMENTI_SCENARIO_URL = ""
GROUNDS_URL = ""
TEMPLATE_URL = ""
-- =========================================================================================================================
--                                                 PREPARAZIONE ESERCITI INIZIO
-- =========================================================================================================================
-- ============================================================
-- FUNZIONI letturaJsonFileConfiguration()
-- ============================================================
function letturaJsonFileConfiguration(callback)

    printToAll("1. letturaJsonFileConfiguration")

    WebRequest.get(MAIN_URL, function(req)
        if req.is_error then
            printToAll("[CONFIG] Errore main.json: " .. req.error, {r=1,g=0.3,b=0.3})
            callback()  -- chiama comunque il callback per non bloccare il flusso
            return
        end
        local ok, url = pcall(JSON.decode, req.text)
        if ok and type(url) == "table" then
            if url.REGOLAMENTO_URL      then REGOLAMENTO_URL      = url.REGOLAMENTO_URL      end
            if url.CONFIG_URL           then CONFIG_URL            = url.CONFIG_URL            end
            if url.ARMY1_URL            then ARMY1_URL             = url.ARMY1_URL             end
            if url.ARMY2_URL            then ARMY2_URL             = url.ARMY2_URL             end
            if url.ELEMENTI_SCENARIO_URL then ELEMENTI_SCENARIO_URL = url.ELEMENTI_SCENARIO_URL end
            if url.GROUNDS_URL          then GROUNDS_URL           = url.GROUNDS_URL           end
            if url.TEMPLATE_URL          then TEMPLATE_URL           = url.TEMPLATE_URL        end

            printToAll("[CONFIG] main.json caricato", {r=0.4,g=0.9,b=0.4})
        else
            printToAll("[CONFIG] Errore parsing main.json — uso valori di default", {r=1,g=0.6,b=0})
        end
        callback()
    end)
end
-- ============================================================
-- FUNZIONE: caricaConfigurazione(callback)
-- ============================================================
function caricaConfigurazione(callback)
    
    printToAll("2. caricaConfigurazione")
    
    local caricati = 0
    local totale   = 2
    local ok

    local function controlla()
        caricati = caricati + 1
        if caricati >= totale then callback() end
    end

    WebRequest.get(REGOLAMENTO_URL, function(req)
        if req.is_error then
            printToAll("[CONFIG] Errore regolamento: " .. req.error, {r=1,g=0.3,b=0.3})
        else
            local ok, dati = pcall(JSON.decode, req.text)
            if ok and type(dati) == "table" then
                if dati.fasi then
                    FASI = {}
                    for _, f in ipairs(dati.fasi) do
                        table.insert(FASI, { nome=f.nome, desc=f.desc, turno_tts=f.turno_tts })
                    end
                end
                if dati.dati_unita then
                    DATI_UNITA = {}
                    for tipo, d in pairs(dati.dati_unita) do
                        DATI_UNITA[tipo] = { basi=d.basi, fpb=d.fpb, dado_tiro_div=d.dado_tiro_div }
                    end
                end
                if dati.armi_tiro then
                    ARMI_TIRO = {}
                    for arma, d in pairs(dati.armi_tiro) do
                        ARMI_TIRO[arma] = { gittata=d.gittata, valore_visualizzato=d.valore_visualizzato, angolo=d.angolo }
                    end
                end
                printToAll("[CONFIG] Regolamento caricato", {r=0.4,g=0.9,b=0.4})
            else
                printToAll("[CONFIG] Errore parsing regolamento — uso valori di default", {r=1,g=0.6,b=0})
            end
        end
        controlla()
    end)

    WebRequest.get(CONFIG_URL, function(req)
        if req.is_error then
            printToAll("[CONFIG] Errore config: " .. req.error, {r=1,g=0.3,b=0.3})
        else
            local ok, dati = pcall(JSON.decode, req.text)
            if ok and type(dati) == "table" then
                if dati.visualizzazione_ferite  then VISUALIZZAZIONE_FERITE      = dati.visualizzazione_ferite   end
                if dati.colore_bersaglio_tiro    then COLORE_UNITA_BERSAGLIO_TIRO = dati.colore_bersaglio_tiro    end
                if dati.posizionamento_su_tavolo then POSIZIONAMENTO_SU_TAVOLO = dati.posizionamento_su_tavolo    end
                if dati.deploy_cm                then DEPLOY_CM                   = dati.deploy_cm                end
                if dati.army1_url                then ARMY1_URL                   = dati.army1_url                end
                if dati.army2_url                then ARMY2_URL                   = dati.army2_url                end
                if dati.verde then
                    VERDE_Y       = dati.verde.y
                    VERDE_Y_LINEE = dati.verde.y_linee
                    VERDE_LX      = dati.verde.lx
                    VERDE_LZ      = dati.verde.lz
                end
                if dati.tavolo then
                    TAVOLO_Y  = dati.tavolo.y
                    TAVOLO_LX = dati.tavolo.lx
                    TAVOLO_LZ = dati.tavolo.lz
                end
                printToAll("[CONFIG] Config caricata", {r=0.4,g=0.9,b=0.4})
            else
                printToAll("[CONFIG] Errore parsing config — uso valori di default", {r=1,g=0.6,b=0})
            end
        end
        controlla()
    end)

    WebRequest.get(TEMPLATE_URL, function(req)
        if req.is_error then
            printToAll("[CONFIG] Errore template: " .. req.error, {r=1,g=0.3,b=0.3})
            return
        end
        
        ok, templates = pcall(JSON.decode, req.text)
        if not ok or not template then printToAll("[CARICA] Errore parsing JSON",{r=1,g=0.3,b=0.3}); return end
    end)
end
-- ============================================================
-- FUNZIONE: caricaEsercito(url, slot, player)
-- ============================================================
function caricaEsercito(url, slot, player)

    printToAll("3. caricaEsercito")

    printToAll("[CARICA] Download JSON esercito "..slot.."...",{r=0.8,g=0.8,b=0.8})
    local player_name  = player and player.steam_name or "---"
    local player_color = player and player.color or "---"
    WebRequest.get(url, function(request)

        if request.is_error then printToAll("[CARICA] Errore: "..request.error,{r=1,g=0.3,b=0.3}); return end
        local ok, dati = pcall(JSON.decode, request.text)
        if not ok or not dati then printToAll("[CARICA] Errore parsing JSON",{r=1,g=0.3,b=0.3}); return end
        local s = tonumber(slot)

        ARMY[s].tag=dati.tag; 
        ARMY[s].nome=dati.nome; 
        ARMY[s].nome_display=dati.nome_display
        ARMY[s].player=player_name; 
        ARMY[s].color=player_color

        updateCenterPanel()
        local contatori={}; local army_tag="Army"..slot
        printToAll("[CARICA] Esercito: "..dati.nome.." | Tag: "..army_tag,{r=0.4,g=0.9,b=0.4})
        for _, unita in ipairs(dati.unita) do generaUnitaFromJson(unita, army_tag, contatori, slot) end
        printToAll("[CARICA] Completato",{r=0.4,g=0.9,b=0.4})
        if tonumber(slot) == 1 then Army1DeployDone = true end
        if tonumber(slot) == 2 then Army2DeployDone = true end
    end)
end
-- ============================================================
-- FUNZIONE: generaUnita(unita, tag, contatori, slot)
-- ============================================================
function generaUnita(unita, tag, contatori, slot)

    printToAll("4. generaUnita")

    contatori[unita.tipo]=(contatori[unita.tipo] or 0) + 1
    local unita_num=contatori[unita.tipo]; local offsetZ=45.00
    
    for _, base in ipairs(unita.basi) do
        print(base.guid or unita.guid)
        local template=getByName(base.model or unita.model or unita.tipo)
        if template then
            
            local nickname=unita.tipo.."_"..unita_num.."."..base.seq
            if unita.modificatore then nickname=nickname.."_"..unita.modificatore end
            if base.arma          then nickname=nickname.."_"..base.arma          end

            local posTarget={x=base.posizione.x, y=1.70, z=base.posizione.z+(tag=="Army1" and (offsetZ*-1) or offsetZ)}
            local rotTarget={x=0, y=slot=="1" and 0 or 180, z=0}
            local clone=template.clone({position=posTarget, rotation=rotTarget, snap_to_grid=false})
            clone.setLock(true)
            Wait.frames(function()
                if clone==nil then return end
                clone.setName(nickname); clone.addTag(tag)
                clone.setDescription(unita.nome_display)
                clone.setPosition(posTarget); clone.setRotation(rotTarget)
                local nemico_color=slot=="1" and ARMY[2].color or ARMY[1].color
                if nemico_color and nemico_color~="---" and not DEBUG then clone.setInvisibleTo({nemico_color}) end
                clone.auto_raise=true
                if base.ferite and base.ferite>0 then
                    wounds_data[nickname]=base.ferite
                    local d=DATI_UNITA[unita.tipo]; local fpb=d and d.fpb or 3
                    aggiornaTintaBase(clone, base.ferite, fpb)
                end
                Wait.time(function() if clone~=nil then clone.setLock(false); clone.auto_raise=true end end, 1.0)
            end, 10)
        end
    end
end
-- ============================================================
-- FUNZIONE: generaUnita(unita, tag, contatori, slot)
-- ============================================================
function generaUnitaFromJson(unita, tag, contatori, slot)

    contatori[unita.tipo] = (contatori[unita.tipo] or 0) + 1
    local unita_num = contatori[unita.tipo]
    local offsetZ = 45.00

    for _, base in ipairs(unita.basi) do

        -- Recupera i dati tecnici dal database JSON
        local templateData = getByNameFromJson(base.model or unita.model or unita.tipo)
        if templateData then
            -- Costruzione Nickname dinamico
            local nickname = unita.tipo .. "_" .. unita_num .. "." .. base.seq
            if unita.modificatore then nickname = nickname .. "_" .. unita.modificatore end
            if base.arma then nickname = nickname .. "_" .. base.arma end
            local posTarget = {x=base.posizione.x, y=1.70, z=base.posizione.z+(tag=="Army1" and (offsetZ*-1) or offsetZ)}
            local rotTarget = {x=0, y=(slot=="1" and 0 or 180), z=0}

            -- Prepariamo i parametri per lo spawn
            local spawn_params = {
                name = "Custom_Model",
                nickname = nickname,
                description = unita.nome_display or "",
                Transform = {
                    posX = posTarget.x, posY = posTarget.y, posZ = posTarget.z,
                    rotX = rotTarget.x, rotY = rotTarget.y, rotZ = rotTarget.z,
                    scaleX = 1, scaleY = 1, scaleZ = 1
                },
                CustomMesh = templateData.customMesh
            }

            -- Eseguiamo lo spawn
            spawnObjectJSON({
                json = JSON.encode(spawn_params),
                callback_function = function(obj)
                    if obj == nil then return end
                    obj.setCustomObject(spawn_params.CustomMesh)
                    obj.reload()
                    obj.setLock(true)
                    obj.addTag(tag)
                   -- Gestione Invisibilità
                    local nemico_color = (slot=="1" and ARMY[2].color or ARMY[1].color)
                    if nemico_color and nemico_color ~= "---" and not DEBUG then 
                        obj.setInvisibleTo({nemico_color}) 
                    end
                    
                    obj.auto_raise = true

                    -- Gestione Ferite e Tinta
                    if base.ferite and base.ferite > 0 then
                        wounds_data[nickname] = base.ferite
                        local d = DATI_UNITA[unita.tipo]
                        local fpb = d and d.fpb or 3
                        aggiornaTintaBase(obj, base.ferite, fpb)
                    end

                    -- Sblocco fisico post-caricamento
                    Wait.time(function() if obj ~= nil then obj.setLock(false) end end, 1.0)
                end
            })
        end
    end
end

-- ============================================================
-- FUNZIONE: scanTavolo()
-- ============================================================
function scanTavolo()

    printToAll("5. scanTavolo")

    esercito_1={}; esercito_2={}; wounds_data={}
    local gruppi_1={}; local gruppi_2={}; local gia_visti={}
    for _, obj in ipairs(getAllObjects()) do
        local fazione=nil
        for _, tag in ipairs(obj.getTags()) do
            if tag=="Army1" then fazione="1" end
            if tag=="Army2" then fazione="2" end
        end
        if fazione then
            local nickname=obj.getName()
            if nickname~="" and not gia_visti[nickname] then
                local dati=parsaNome(nickname)
                if dati then
                    gia_visti[nickname]=true
                    local chiave=dati.tipo.."_"..dati.unita_num
                    local gruppi=fazione=="1" and gruppi_1 or gruppi_2
                    local d=DATI_UNITA[dati.tipo]
                    if not gruppi[chiave] then
                        gruppi[chiave]={tipo=dati.tipo,unita_num=dati.unita_num,valore=dati.valore,arma=dati.arma,fpb=d.fpb,basi_max=d.basi,fazione=fazione,basi={}}
                    end
                    table.insert(gruppi[chiave].basi,{nickname=nickname,guid=obj.getGUID()})
                    wounds_data[nickname]=0; obj.highlightOff(); obj.setDescription(""); aggiornaTagInjured(obj,0)
                end
            end
        end
    end
    local function gruppiToLista(gruppi, tag)
        local lista={}
        for _, unita in pairs(gruppi) do
            unita.nome_display=tag.."_"..unita.tipo.."_"..unita.unita_num
            table.insert(lista,unita)
        end
        table.sort(lista, function(a,b) if a.tipo~=b.tipo then return a.tipo<b.tipo end return a.unita_num<b.unita_num end)
        return lista
    end
    esercito_1=gruppiToLista(gruppi_1,(ARMY[1].tag or "ARMY1"))
    esercito_2=gruppiToLista(gruppi_2,(ARMY[2].tag or "ARMY2"))
    printToAll("=== LIONHEART BOT "..VERSION.." ===",{r=0.8,g=0.6,b=0.1})
    printToAll((ARMY[1].tag or "ARMY1")..": "..#esercito_1.." unita",{r=0.9,g=0.2,b=0.2})
    printToAll((ARMY[2].tag or "ARMY2")..": "..#esercito_2.." unita",{r=0.2,g=0.4,b=0.9})
    for _, u in ipairs(esercito_1) do
        local info=u.nome_display.." | Basi: "..#u.basi.."/"..u.basi_max
        if u.valore==1 then info=info.." | Superiore" elseif u.valore==-1 then info=info.." | Inferiore" end
        if u.arma then info=info.." ["..u.arma.."]" end
        printToAll(info,{r=0.9,g=0.2,b=0.2})
    end
    for _, u in ipairs(esercito_2) do
        local info=u.nome_display.." | Basi: "..#u.basi.."/"..u.basi_max
        if u.valore==1 then info=info.." | Superiore" elseif u.valore==-1 then info=info.." | Inferiore" end
        if u.arma then info=info.." ["..u.arma.."]" end
        printToAll(info,{r=0.2,g=0.4,b=0.9})
    end
    printToAll("=== PRONTO ===",{r=0.4,g=0.9,b=0.4})
    aggiornaPannello(1); aggiornaPannello(2)
    turno_corrente=0; fase_corrente=0; iniziativa_tag=(ARMY[1].tag or "ARMY1")
    aggiornaBanner()
end
-- =========================================================================================================================
--                                                 PREPARAZIONE ESERCITI FINE
-- =========================================================================================================================

-- =========================================================================================================================
--                                                        SISTEMA INIZIO
-- =========================================================================================================================
-- ============================================================
-- FUNZIONE: onSave()
-- ============================================================
function onSave()
    local stato = {
        turno_corrente    = turno_corrente,
        fase_corrente     = fase_corrente,
        iniziativa_tag    = iniziativa_tag,
        iniziativa_scelta = iniziativa_scelta,
        mano_tag          = mano_tag,
        mano_passata      = mano_passata,
        Army1DeployDone   = Army1DeployDone,
        Army2DeployDone   = Army2DeployDone,
        pronto_red        = pronto_red,
        pronto_green      = pronto_green,
        wounds_data       = wounds_data,
        army1 = {
            tag=ARMY[1].tag, nome=ARMY[1].nome, nome_display=ARMY[1].nome_display,
            player=ARMY[1].player, color=ARMY[1].color,
        },
        army2 = {
            tag=ARMY[2].tag, nome=ARMY[2].nome, nome_display=ARMY[2].nome_display,
            player=ARMY[2].player, color=ARMY[2].color,
        },
        esercito_1 = esercito_1,
        esercito_2 = esercito_2,
    }
    return JSON.encode(stato)
end
-- ============================================================
-- FUNZIONE: ripristinaStato(save_state)
-- ============================================================
function ripristinaStato(save_state)
    if not save_state or save_state == "" then return false end
    local ok, stato = pcall(JSON.decode, save_state)
    if not ok or not stato then return false end

    turno_corrente    = stato.turno_corrente    or 0
    fase_corrente     = stato.fase_corrente     or 0
    iniziativa_tag    = stato.iniziativa_tag    or (ARMY[1].tag or "ARMY1")
    iniziativa_scelta = stato.iniziativa_scelta or false
    mano_tag          = stato.mano_tag          or nil
    mano_passata      = stato.mano_passata      or false
    Army1DeployDone   = stato.Army1DeployDone   or false
    Army2DeployDone   = stato.Army2DeployDone   or false
    pronto_red        = stato.pronto_red        or false
    pronto_green      = stato.pronto_green      or false
    wounds_data       = stato.wounds_data       or {}

    if stato.army1 then
        ARMY[1].tag=stato.army1.tag; ARMY[1].nome=stato.army1.nome
        ARMY[1].nome_display=stato.army1.nome_display
        ARMY[1].player=stato.army1.player; ARMY[1].color=stato.army1.color
    end
    if stato.army2 then
        ARMY[2].tag=stato.army2.tag; ARMY[2].nome=stato.army2.nome
        ARMY[2].nome_display=stato.army2.nome_display
        ARMY[2].player=stato.army2.player; ARMY[2].color=stato.army2.color
    end

    esercito_1 = stato.esercito_1 or {}
    esercito_2 = stato.esercito_2 or {}

    for nickname, wounds in pairs(wounds_data) do
        if wounds > 0 then
            local obj = trovaOggettoPerNome(nickname)
            if obj then
                local dati = parsaNome(nickname)
                if dati and DATI_UNITA[dati.tipo] then
                    aggiornaTintaBase(obj, wounds, DATI_UNITA[dati.tipo].fpb)
                end
            end
        end
    end

    return true
end
-- ============================================================
-- FUNZIONE: onLoad(save_state)
-- ============================================================
-- function onLoad(save_state)
--     print("[LIONHEART] Script caricato " .. VERSION)
--     groundSettings()
--     linee_rettangolo = true
--     linee_deploy     = false

--     letturaJsonFileConfiguration(function()
--         caricaConfigurazione(function()
--             Wait.frames(function()
--                 local ripristinato = ripristinaStato(save_state)
--                 if ripristinato and turno_corrente > 0 then
--                     printToAll("[LIONHEART] Partita ripristinata — Turno " .. turno_corrente
--                         .. " | Fase " .. (FASI[fase_corrente] and FASI[fase_corrente].nome or "---"),
--                         {r=0.4,g=0.9,b=0.4})
--                 end
--                 updateCenterPanel()
--                 aggiornaLinee()
--             end, 10)
--         end)
--     end)
-- end
-- ============================================================
-- FUNZIONE: onChat()
-- ============================================================
function onChat(message, player)
    if not message then return end
    message = message:gsub("^%s+", ""):gsub("%s+$", "")
    if not message or message == "" then return end
    if message == "!restart" then restart() end
    if message == "!turno"   then avviaTurno()  return false end
    if message == "!fase"    then avanzaFase()  return false end
    if message == "!stato"   then mostraStato() return false end
    if message == "!clear"   then clear() end

    if message == "!visual" then
        local sel = player.getSelectedObjects()
        if not sel or #sel == 0 then
            printToAll("[VISUAL] Nessun oggetto selezionato", {r=1,g=0.3,b=0.3})
        else
            for _, obj in ipairs(sel) do
                print(obj.getName())
                visual(obj, player)
            end
        end
        return false
    end

end
-- =========================================================================================================================
--                                                           SISTEMA FINE
-- =========================================================================================================================
-- =========================================================================================================================
--                                                           FASI INIZIO
-- =========================================================================================================================
-- ============================================================
-- FUNZIONE: verificaPronti
-- ============================================================
function verificaPronti()

    print("verificaPronti")

    if pronto_red and pronto_green then
        printToAll("Entrambi pronti — verifico il deploy...", {r=0.9,g=0.8,b=0.1})
        if POSIZIONAMENTO_SU_TAVOLO then
            local ok, err = pcall(verificaDeploy)
            if not ok then
                printToAll("[ERRORE verificaDeploy] " .. tostring(err), {r=1,g=0,b=0})
                pronto_red=false; pronto_green=false; aggiornaBanner(); return
            end
            if not err then
                printToAll("Correggi il posizionamento e premi di nuovo PRONTO!", {r=1,g=0.3,b=0.3})
                pronto_red=false; pronto_green=false; aggiornaBanner(); return
            end
        end
        pronto_red=false; pronto_green=false
        Wait.frames(function() avviaTurno() end, 60)
    end
end
-- ============================================================
-- FUNZIONE: onBtnProntoRed
-- ============================================================
function onBtnProntoRed(player, value, id)

    print("onBtnProntoRed")

    if not DEBUG then
        if player == nil or player.color ~= "Red" then return end
    end
    pronto_red = not pronto_red
    printToAll(pronto_red and "[R] Red: PRONTO!" or "[R] Red: non piu pronto.", {r=1,g=0.4,b=0.4})
    updateCenterPanel()
    verificaPronti()
end
-- ============================================================
-- FUNZIONE: onBtnProntoGreen
-- ============================================================
function onBtnProntoGreen(player, value, id)

    print("onBtnProntoGreen")

    if not DEBUG then
        local color = (player ~= nil) and (type(player) == "string" and player or player.color) or "Green"
        if color ~= "Green" then return end
    end
    pronto_green = not pronto_green
    printToAll(pronto_green and "[G] Green: PRONTO!" or "[G] Green: non piu pronto.", {r=0.4,g=1,b=0.4})
    updateCenterPanel()
    verificaPronti()
end
-- ============================================================
-- FUNZIONE: onBtnAvanzaFase
-- ============================================================
function onBtnAvanzaFase(player, value, id)
    print("onBtnAvanzaFase")
    if fase_corrente >= #FASI then avviaTurno() else avanzaFase() end
end
-- ============================================================
-- FUNZIONE: onBtnIniziativa1
-- ============================================================
function onBtnIniziativa1(player, value, id)
    print("onBtnIniziativa1")
    iniziativa_tag    = ARMY[1].tag or "ARMY1"
    iniziativa_scelta = true
    printToAll("Iniziativa: " .. (ARMY[1].nome_display or iniziativa_tag), {r=1,g=0.8,b=0.2})
    aggiornaPannello(1); aggiornaPannello(2)
    avanzaFase()
end
-- ============================================================
-- FUNZIONE: onBtnIniziativa2
-- ============================================================
function onBtnIniziativa2(player, value, id)
    print("onBtnIniziativa2")
    iniziativa_tag    = ARMY[2].tag or "ARMY2"
    iniziativa_scelta = true
    printToAll("Iniziativa: " .. (ARMY[2].nome_display or iniziativa_tag), {r=1,g=0.8,b=0.2})
    aggiornaPannello(1); aggiornaPannello(2)
    avanzaFase()
end
-- ============================================================
-- FUNZIONE: onBtnPassaMano
-- ============================================================
function onBtnPassaMano(player, value, id)
    print("onBtnPassaMano")
    if not mano_passata then
        mano_passata = true
        local altro_tag = nil
        for slot = 1, 2 do
            if ARMY[slot].tag ~= mano_tag then altro_tag = ARMY[slot].tag end
        end
        mano_tag = altro_tag
        local nb = mano_tag
        for slot = 1, 2 do
            if ARMY[slot].tag == mano_tag then nb = ARMY[slot].nome_display or mano_tag end
        end
        printToAll("-> Ora muove: " .. (nb or "---"), {r=0.4,g=0.9,b=0.4})
        aggiornaBanner()
    else
        mano_tag     = nil
        mano_passata = false
        printToAll("-> Movimento completato.", {r=0.4,g=0.9,b=0.4})
        avanzaFase()
    end
end
-- ============================================================
-- FUNZIONE: aggiornaPannello(slot)
-- ============================================================
function aggiornaPannello(slot)
    -- local a      = ARMY[slot]
    -- local prefix = "pan" .. slot .. "_"
    -- local esercito     = slot == 1 and esercito_1 or esercito_2
    -- local unita_attive = 0
    -- for _, u in ipairs(esercito) do
    --     if #u.basi > 0 then unita_attive = unita_attive + 1 end
    -- end
    -- local unita_str = (#esercito > 0) and (unita_attive .. "/" .. #esercito) or "---"
    -- local fase_str
    -- if fase_corrente == 0 then
    --     fase_str = turno_corrente == 0 and "DEPLOY" or "INIZIATIVA"
    -- else
    --     fase_str = FASI[fase_corrente] and FASI[fase_corrente].nome or "---"
    -- end
    -- local col_map = {
    --     Red="rgba(1,0.2,0.2,1)", Green="rgba(0.2,0.9,0.2,1)", Blue="rgba(0.2,0.4,1,1)",
    --     Orange="rgba(1,0.6,0,1)", Teal="rgba(0,0.8,0.8,1)", Purple="rgba(0.7,0.2,1,1)",
    --     Pink="rgba(1,0.4,0.7,1)", Yellow="rgba(1,1,0,1)", White="rgba(1,1,1,1)", Grey="rgba(0.6,0.6,0.6,1)",
    -- }
    -- local col_str = col_map[a.color or ""] or "rgba(1,0.85,0.3,1)"
    -- UI.setAttribute(prefix.."title",  "color", col_str)
    -- UI.setAttribute(prefix.."player", "text", "Player: "   .. (a.player or "---"))
    -- UI.setAttribute(prefix.."color",  "text", "Colore: "   .. (a.color  or "---"))
    -- UI.setAttribute(prefix.."army",   "text", "Esercito: " .. (a.nome   or "---"))
    -- UI.setAttribute(prefix.."unita",  "text", "Unita: "    .. unita_str)
    -- UI.setAttribute(prefix.."fase",   "text", "Fase: "     .. fase_str)
end
-- ============================================================
-- FUNZIONE: onDeployArmy1
-- ============================================================
function onDeployArmy1(player, value, id)

    if player and player.color and player.color ~= "Red" then
        printToColor("[LIONHEART] Only ".. army1 .. " can use it to deploy", "Green")
        return
    end
    
    caricaEsercito(ARMY1_URL, "1", player)

end
-- ============================================================
-- FUNZIONE: onDeployArmy2
-- ============================================================
function onDeployArmy2(player, value, id)

     if player and player.color and player.color ~= "Green" then
        printToColor("[LIONHEART] Only ".. army2 .. " can use it to deploy", "Red")
        return
    end
    
    caricaEsercito(ARMY2_URL, "2", player)
end
-- =========================================================================================================================
--                                                            FASI FINE
-- =========================================================================================================================
-- ============================================================
-- FUNZIONE: aggiornaLinee()
-- ============================================================
function aggiornaLinee()
   
    local linee = {}

    if linee_croce then
        table.insert(linee, { points={{x=-TAVOLO_LX,y=TAVOLO_Y,z=0},{x=TAVOLO_LX,y=TAVOLO_Y,z=0}}, color={r=0.8,g=0.8,b=0.8}, thickness=0.3 })
        table.insert(linee, { points={{x=0,y=TAVOLO_Y,z=-TAVOLO_LZ},{x=0,y=TAVOLO_Y,z=TAVOLO_LZ}}, color={r=0.8,g=0.8,b=0.8}, thickness=0.3 })
    end
    if linee_deploy then
        local y  = VERDE_Y_LINEE
        table.insert(linee, { points={{x=-VERDE_LX,y=y,z=-(VERDE_LZ-DEPLOY_CM)},{x=VERDE_LX,y=y,z=-(VERDE_LZ-DEPLOY_CM)}}, color={r=0.9,g=0.2,b=0.2}, thickness=0.25 })
        table.insert(linee, { points={{x=-VERDE_LX,y=y,z=(VERDE_LZ-DEPLOY_CM)}, {x=VERDE_LX,y=y,z=(VERDE_LZ-DEPLOY_CM)}},  color={r=0.2,g=0.8,b=0.2}, thickness=0.25 })
    end
    if linee_rettangolo then
        local y = 1.70
        table.insert(linee, { points={{x=-46.18,y=y,z=-37.55},{x=46.18,y=y,z=-37.55},{x=46.18,y=y,z=-62.38},{x=-46.18,y=y,z=-62.38},{x=-46.18,y=y,z=-37.55}}, color={r=1,g=0,b=0}, thickness=0.3 })
        table.insert(linee, { points={{x=-46.18,y=y,z=37.55}, {x=46.18,y=y,z=37.55}, {x=46.18,y=y,z=62.38}, {x=-46.18,y=y,z=62.38}, {x=-46.18,y=y,z=37.55}},  color={r=0,g=1,b=0}, thickness=0.3 })
    end
    if linee_settori then
        local cols=6; local rows=5
        local sx=(VERDE_LX*2)/cols; local sz=(VERDE_LZ*2)/rows; local y=3.5
        for c=0,cols do local x=-VERDE_LX+c*sx; table.insert(linee,{points={{x,y,-VERDE_LZ},{x,y,VERDE_LZ}},color={r=0.2,g=0.8,b=0.8},thickness=0.1}) end
        for r=0,rows do local z=-VERDE_LZ+r*sz; table.insert(linee,{points={{-VERDE_LX,y,z},{VERDE_LX,y,z}},color={r=0.2,g=0.8,b=0.8},thickness=0.1}) end
    end
    Global.setVectorLines(linee)
end
-- ============================================================
-- FUNZIONE: groundSettings()
-- ============================================================
function groundSettings()
    local g = getByName("Ground")
    if not g then return end
    g.setPosition({x=0,y=0.5,z=0}); g.setScale({x=5.86,y=4.05,z=3.95}); g.setRotation({x=0,y=0,z=0})
end
-- ============================================================
-- FUNZIONE: parsaNome(nickname)
-- ============================================================
function parsaNome(nickname)
    local tipo, unita_str, seq_str = string.match(nickname, "^([A-Za-z]+)_(%d+)%.(%d+)")
    if not tipo or not unita_str or not seq_str then return nil end
    if not DATI_UNITA[tipo] then return nil end
    local valore=0; local arma=nil
    local resto = string.sub(nickname, #tipo+#unita_str+#seq_str+3)
    for mod in string.gmatch(resto, "[^_]+") do
        if mod == "S" then valore=1 end
        if mod == "I" then valore=-1 end
        if ARMI_TIRO[mod] then arma=mod end
    end
    local d = DATI_UNITA[tipo]
    return { tipo=tipo, seq=tonumber(seq_str), unita_num=tonumber(unita_str), base_num=1, valore=valore, arma=arma, fpb=d.fpb, basi_max=d.basi }
end

-- ============================================================
-- FUNZIONE: verificaDeploy()
-- ============================================================
function verificaDeploy()

    printToAll("verificaDeploy")

    local X_MAX=45.54; local Z_NEAR=25.67; local Z_FAR=32.88
    
    for _, guid in ipairs(segnalini_guids) do local o=getObjectFromGUID(guid); if o then o.destruct() end end
    segnalini_guids={}
    local errori={[1]={fuori={},sbagliata={}}, [2]={fuori={},sbagliata={}}}
    local basi_errate={}
    local prefissi_template={}
    for slot=1,2 do local tag=ARMY[slot].tag; if tag then prefissi_template[tag.."_"]=true end end

    for _, obj in ipairs(getAllObjects()) do
        local nome=obj.getName(); local is_template=false
        for pfx,_ in pairs(prefissi_template) do if string.sub(nome,1,#pfx)==pfx then is_template=true break end end
        if not is_template and parsaNome(nome) then
            local army_tag=nil
            for _,t in ipairs(obj.getTags()) do if t=="Army1" or t=="Army2" then army_tag=t break end end
            if army_tag then
                local slot=tonumber(string.match(army_tag,"%d")); local pos=obj.getPosition()
                local z_abs=math.abs(pos.z); local x_abs=math.abs(pos.x)
                local z_ok=z_abs>=Z_NEAR and z_abs<=Z_FAR; local x_ok=x_abs<=X_MAX
                local z_sign_ok=(slot==1 and pos.z<0) or (slot==2 and pos.z>0)
                if not z_ok or not x_ok then table.insert(errori[slot].fuori,nome); table.insert(basi_errate,{obj=obj,pos=pos})
                elseif not z_sign_ok then table.insert(errori[slot].sbagliata,nome); table.insert(basi_errate,{obj=obj,pos=pos}) end
            end
        end
    end
    for _,b in ipairs(basi_errate) do if b and b.obj then b.obj.highlightOn({r=1,g=0.1,b=0.1},15) end end
    local totale=0
    for slot=1,2 do
        local e=errori[slot]; local n=#e.fuori+#e.sbagliata; totale=totale+n
        if n>0 then
            local nb=(ARMY[slot] and ARMY[slot].nome_display) or ("Army"..slot)
            printToAll("── Army "..slot.." ("..nb..") ──",{r=1,g=0.8,b=0.2})
            for _,nn in ipairs(e.fuori)    do printToAll("  Fuori zona: "..nn,    {r=1,g=0.7,b=0.3}) end
            for _,nn in ipairs(e.sbagliata) do printToAll("  Zona sbagliata: "..nn,{r=1,g=0.4,b=0.4}) end
        end
    end
    local basi_trovate=(function() local c=0; for _,obj in ipairs(getAllObjects()) do for _,t in ipairs(obj.getTags()) do if t=="Army1" or t=="Army2" then c=c+1 break end end end return c end)()
    if basi_trovate==0 then printToAll("[DEPLOY] Nessuna base trovata!",{r=1,g=0.3,b=0.3}); return false end
    if totale==0 then printToAll("[DEPLOY] OK — tutte le basi nelle zone corrette!",{r=0.4,g=0.9,b=0.4}); return true end
    return false
end

-- ============================================================
-- FUNZIONE: getByName()
-- ============================================================
function getByName(name)
    for _,obj in ipairs(getAllObjects()) do if obj.getName()==name then return obj end end
    return nil
end
-- ============================================================
-- FUNZIONE: getByNameFromJson()
-- ============================================================
function getByNameFromJson(name)

        for _, army in ipairs(templates.Army) do
            for _, template in ipairs(army.modelli) do
                if template.nickname == name then
                    return template
                end
            end    
        end
    print("ERRORE: Modello non trovato nel database JSON: " .. tostring(name))
    return nil
end
-- ============================================================
-- FUNZIONE: getByGuid(guid)
-- ============================================================
function getByGuid(guid)
    if not guid then return nil end
    return getObjectFromGUID(guid)
end
-- ============================================================
-- FUNZIONE: clear()
-- ============================================================
function clear() for i=0,120 do print("") end end
-- =========================================================================================================================
--                                                            CHAT INIZIO
-- =========================================================================================================================
-- ============================================================
-- FUNZIONE: restart()
-- ============================================================
    function restart()

        for _, obj in ipairs(getAllObjects()) do
            for _, tag in ipairs(obj.getTags()) do
                if tag == "Army1" or tag == "Army2" then
                    if parsaNome(obj.getName()) then
                        obj.destruct()
                    end
                    break
                end
            end
        end

        ARMY[1] = {player=nil, tag=nil, nome=nil, color=nil, pannello_guid=nil}
        ARMY[2] = {player=nil, tag=nil, nome=nil, color=nil, pannello_guid=nil}

        esercito_1 = {}
        esercito_2 = {}
        wounds_data = {}

        turno_corrente = 0
        fase_corrente = 0

        Army1DeployDone = false
        Army2DeployDone = false
        pronto_red = false
        pronto_green = false
        iniziativa_scelta = false
        mano_tag = nil
        mano_passata = false

        for _, guid in ipairs(segnalini_guids) do
            local o = getObjectFromGUID(guid)
            if o then
                o.destruct()
            end
        end

        segnalini_guids = {}
        Turns.enable = false
        linee_deploy = false



        if ENGINE then
            ENGINE.phase = "SITTING"
            ENGINE.state = {
                Army1Click = false,
                Army2Click = false
            }
        end

        colorArmy1 = "Grey"
        colorArmy2 = "Grey"

        UI.setAttribute("army1", "color", "Grey")
        UI.setAttribute("army2", "color", "Grey")

        UI.setAttribute("BTN_ARMY1", "active", "true")
        UI.setAttribute("BTN_ARMY2", "active", "true")
        UI.setAttribute("BTN_SINGLE", "active", "true")

        UI.setAttribute("panelBtnUp", "active", "true")
        UI.setAttribute("panelBtnDown", "active", "true")
        UI.setAttribute("panelBtnUp", "offsetXY", "0 318")
        UI.setAttribute("panelBtnDown", "offsetXY", "0 266")

        for _, p in pairs(Player.getPlayers()) do
            if p.color == "Red" or p.color == "Green" or p.color == "White" then
                p.changeColor("Grey")
            end
        end

        updateCenterPanel()
        aggiornaLinee()
        clear()

        printToAll("[RESET] Partita azzerata — pronto per nuovo setup", {r=0.9, g=0.5, b=0.1})
    end
-- ============================================================
-- FUNZIONE: impostaTurnoTTS()
-- ============================================================

function impostaTurnoTTS(fase) --DA CHAT
    Turns.enable=false
    if not fase.turno_tts then mano_tag=nil; mano_passata=false; return end
    mano_tag=iniziativa_tag; mano_passata=false
    local nb=mano_tag
    for slot=1,2 do if ARMY[slot].tag==mano_tag then nb=ARMY[slot].nome_display or mano_tag end end
    printToAll("-> "..nb.." muove per primo",{r=0.4,g=0.9,b=0.4})
end
-- ============================================================
-- FUNZIONE: avviaTurno()
-- ============================================================
function avviaTurno() --DA CHAT
    turno_corrente=turno_corrente+1; fase_corrente=1; iniziativa_scelta=false
    Turns.enable=false; linee_deploy=false; aggiornaLinee()
    for _,obj in ipairs(getAllObjects()) do
        for _,t in ipairs(obj.getTags()) do if t=="Army1" or t=="Army2" then obj.setInvisibleTo({}); break end end
    end
    printToAll("=== TURNO "..turno_corrente.." === INIZIATIVA",{r=0.8,g=0.6,b=0.1})
    printToAll("Lanciate entrambi 1D6 — chi vince sceglie se muovere primo o secondo.",{r=0.8,g=0.6,b=0.1})
    aggiornaBanner(); aggiornaPannello(1); aggiornaPannello(2)
end
-- ============================================================
-- FUNZIONE: avanzaFase()
-- ============================================================
function avanzaFase() --DA CHAT
    if turno_corrente==0 then printToAll("[LIONHEART] Digita prima !turno!",{r=1,g=0.3,b=0.3}); return end
    if fase_corrente==1 and not iniziativa_scelta then printToAll("[LIONHEART] Prima dichiara chi ha l'iniziativa!",{r=1,g=0.3,b=0.3}); return end
    fase_corrente=fase_corrente+1
    if fase_corrente>#FASI then Turns.enable=false; fase_corrente=#FASI; aggiornaBanner(); return end
    local fase=FASI[fase_corrente]
    local nb_ini=iniziativa_tag
    for slot=1,2 do if ARMY[slot].tag==iniziativa_tag then nb_ini=ARMY[slot].nome_display or iniziativa_tag end end
    printToAll("── FASE "..fase_corrente..": "..fase.nome.." ──",{r=0.8,g=0.6,b=0.1})
    printToAll(fase.desc,{r=0.8,g=0.8,b=0.8})
    if fase.turno_tts then printToAll("-> "..nb_ini.." agisce per primo",{r=0.4,g=0.9,b=0.4}) end
    printToAll("!fase quando la fase e' completata",{r=0.6,g=0.6,b=0.6})
    impostaTurnoTTS(fase); aggiornaBanner(); aggiornaPannello(1); aggiornaPannello(2)
end
-- ============================================================
-- FUNZIONE: mostraStato()
-- ============================================================
function mostraStato() --DA CHAT

    printToAll("=== STATO BATTAGLIA - TURNO "..turno_corrente.." ===",{r=0.8,g=0.8,b=0.8})
    local function stampa(lista,tag,colore)
        printToAll("-- "..tag.." --",colore)
        for _,u in ipairs(lista) do
            local fpb=DATI_UNITA[u.tipo].fpb; local fig_max=u.basi_max*fpb
            printToAll(u.nome_display.." | Basi: "..basiPresentiUnita(u).."/"..u.basi_max.." | Figure: "..figureTotaliUnita(u).."/"..fig_max,colore)
        end
    end
    stampa(esercito_1,(ARMY[1].tag or "ARMY1"),{r=0.9,g=0.2,b=0.2})
    stampa(esercito_2,(ARMY[2].tag or "ARMY2"),{r=0.2,g=0.4,b=0.9})
end

function basiPresentiUnita(unita)
    local count=0
    for _,base in ipairs(unita.basi) do if trovaOggettoPerNome(base.nickname) then count=count+1 end end
    return count
end
-- =========================================================================================================================
--                                                            CHAT FINE
-- =========================================================================================================================
-- =========================================================================================================================
--                                                       FUNZIONI FERITE INIZIO
-- =========================================================================================================================
-- ============================================================
-- FUNZIONE: registraWounds
-- ============================================================
function registraWounds(nome_base, n_ferite)
    local unita,base,fazione=trovaBase(nome_base)
    if not unita then printToAll("[LIONHEART] Base non trovata: "..nome_base,{r=1,g=0.3,b=0.3}); return end
    local obj=trovaOggettoPerNome(nome_base)
    if not obj then printToAll("[LIONHEART] Oggetto non trovato: "..nome_base,{r=1,g=0.3,b=0.3}); return end
    local fpb=DATI_UNITA[unita.tipo].fpb
    local wounds_totali=math.min((wounds_data[nome_base] or 0)+n_ferite, fpb)
    wounds_data[nome_base]=wounds_totali
    aggiornaTintaBase(obj,wounds_totali,fpb)
    if wounds_totali>=fpb then
        printToAll("RIMUOVI BASE: "..nome_base.." ("..wounds_totali.."/"..fpb.." ferite)",{r=1,g=0.3,b=0.3})
    else
        printToAll("[WOUNDS] "..nome_base..": "..wounds_totali.."/"..fpb.." ferite",{r=1,g=0.7,b=0.2})
    end
    verificaMorale(unita,fazione)
end
-- ============================================================
-- FUNZIONE: trovaBase
-- ============================================================
function trovaBase(nome_base)
    local function cerca(lista)
        if not lista then return nil,nil end
        for _,unita in ipairs(lista) do for _,base in ipairs(unita.basi) do if base.nickname==nome_base then return unita,base end end end
        return nil,nil
    end
    local unita,base=cerca(esercito_1); if unita then return unita,base,"1" end
    unita,base=cerca(esercito_2); if unita then return unita,base,"2" end
    return nil,nil,nil
end
-- ============================================================
-- FUNZIONE: trovaOggettoPerNome
-- ============================================================
function trovaOggettoPerNome(nickname)
    for _, obj in ipairs(getAllObjects()) do if obj.getName()==nickname then return obj end end
    return nil
end
-- ============================================================
-- FUNZIONE: aggiornaTintaBase
-- ============================================================
function aggiornaTintaBase(obj, wounds, fpb)
    if wounds<1 then
        if VISUALIZZAZIONE_FERITE=="highlight" then obj.highlightOff() else obj.setColorTint({r=1,g=1,b=1}) end
        aggiornaTagInjured(obj,0); return
    end
    local colore
    if wounds==1 then colore={r=1,g=0.75,b=0.39}
    elseif wounds==2 then colore={r=1,g=0.55,b=0}
    else colore={r=0.71,g=0.33,b=0} end
    if VISUALIZZAZIONE_FERITE=="highlight" then obj.highlightOn(colore) else obj.setColorTint(colore) end
    aggiornaTagInjured(obj,wounds)
    obj.setDescription("Ferite: "..wounds.."/"..fpb)
end
-- ============================================================
-- FUNZIONE: aggiornaTagInjured
-- ============================================================
function aggiornaTagInjured(obj, wounds)
    obj.removeTag("injured1"); obj.removeTag("injured2"); obj.removeTag("injured3")
    if wounds==1 then obj.addTag("injured1")
    elseif wounds==2 then obj.addTag("injured2")
    elseif wounds>=3 then obj.addTag("injured3") end
end
-- ============================================================
-- FUNZIONE: verificaMorale
-- ============================================================
function verificaMorale(unita, fazione)
    local figure_att=figureTotaliUnita(unita)
    local fpb=DATI_UNITA[unita.tipo].fpb
    local figure_max=unita.basi_max*fpb
    local soglia=math.floor(figure_max/2)
    if figure_att<=soglia and figure_att>0 then
        local colore=fazione=="1" and {r=0.9,g=0.2,b=0.2} or {r=0.2,g=0.4,b=0.9}
        printToAll("MORALE: "..unita.nome_display.." sotto 50% ("..figure_att.."/"..figure_max..")"
            .." | D6 necessario 4+ (mod: "..(unita.valore>=0 and "+" or "")..unita.valore..")", colore)
    end
end
-- ============================================================
-- FUNZIONE: figureTotaliUnita
-- ============================================================
function figureTotaliUnita(unita)
    local figure=0; local fpb=DATI_UNITA[unita.tipo].fpb
    for _,base in ipairs(unita.basi) do
        if trovaOggettoPerNome(base.nickname) then
            figure=figure+(fpb-math.min(wounds_data[base.nickname] or 0, fpb))
        end
    end
    return figure
end
-- =========================================================================================================================
--                                                       FUNZIONI FERITE FINE
-- =========================================================================================================================
-- ============================================================
-- FUNZIONE: visual()
-- ============================================================
function visual(obj, player)

    local customData = obj.getCustomObject()
        
    if customData and customData.mesh ~= nil then
        local dataTable = {
            Name = "Custom_Model",
            Nickname = obj.getName(),
            CustomMesh = {
                MeshURL = customData.mesh,
                DiffuseURL = customData.diffuse,
                ColliderURL = customData.collider,
                Material = customData.material,
                Type = customData.type
            }
        }

        if not dataTable then 
            print("nil")
             return 
        end

        -- USARE setClipboardText invece di copyString
        local jsonString = JSON.encode(dataTable) 
        print(jsonString)

        end
        return false
end
-- ================================================================================================================================================
--                                                              REFACTORING FASI
-- ================================================================================================================================================

ACTION = {
    ARMY1_CLICK = "ARMY1_CLICK",
    ARMY2_CLICK = "ARMY2_CLICK",
    CONFIRM     = "CONFIRM"
}

COND = {
    BOTH_PLAYERS_SELECTED = "both_players_selected",
    CONFIRM_READY         = "confirm_ready",
    CONFIRM_IMMEDIATE     = "confirm_immediate",
    AUTO_ADVANCE          = "auto_advance"
}

COLOR = {
    ARMY1 = "Red",
    ARMY2 = "Green",
    NOARMY = "Grey"    
}

BUTTONS = {
    BTN_ARMY1 = "BTN_ARMY1",
    BTN_ARMY2 = "BTN_ARMY2",
    BTN_SINGLE = "BTN_SINGLE"
}

-- ============================================================
-- FUNZIONE: onLoad()
-- ============================================================
function onLoad()

    linee_rettangolo = true
    linee_deploy     = false

    local phases_json = [[
    {
        "SITTING": {
            "title": "PHASE: SITTING",
            "desc": "Select both players",
            "allowedActions": ["ARMY1_CLICK", "ARMY2_CLICK"],
            "render": "2BtnClick",
            "buttons": {
                "BTN_ARMY1": {
                    "action": "ARMY1_CLICK",
                    "label": "Select Red",
                    "textColor": "White",
                    "callback": "sitting_btn_army"
                },
                "BTN_ARMY2": {
                    "action": "ARMY2_CLICK",
                    "label": "Select Green",
                    "textColor": "White",
                    "callback": "sitting_btn_army"
                }
            },
            "transitions": [
                {
                    "to": "DEPLOY",
                    "conditions": ["both_players_selected"]
                }
            ]
        },

        "DEPLOY": {
            "title": "PHASE: DEPLOY",
            "desc": "Deploy your units behind the spawning line",
            "allowedActions": ["ARMY1_CLICK", "ARMY2_CLICK", "CONFIRM"],
            "render": "3BtnClick",
            "buttons": {
                "BTN_ARMY1": {
                    "action": "ARMY1_CLICK",
                    "label": "Army 1 Ready",
                    "textColor": "White",
                    "callback": "deploy_btn_army1"
                },
                "BTN_ARMY2": {
                    "action": "ARMY2_CLICK",
                    "label": "Army 2 Ready",
                    "textColor": "White",
                    "callback": "deploy_btn_army2"
                },
                "BTN_SINGLE": {
                    "action": "CONFIRM",
                    "label": "Confirm Deploy",
                    "textColor": "Black",
                    "callback": "deploy_btn_single"
                }
            },
            "transitions": [
                {
                    "to": "INITIATIVE",
                    "conditions": ["both_players_selected", "confirm_ready"]
                }
            ]
        },

        "INITIATIVE": {
            "title": "PHASE: INITIATIVE",
            "desc": "The dice are rolled and the winner decides who moves first.",
            "allowedActions": ["ARMY1_CLICK", "ARMY2_CLICK", "CONFIRM"],
            "render": "3BtnClick",
            "buttons": {
                "BTN_ARMY1": {
                    "action": "ARMY1_CLICK",
                    "label": "Army 1 Starts",
                    "textColor": "White",
                    "callback": "initiative_btn_army1"
                },
                "BTN_ARMY2": {
                    "action": "ARMY2_CLICK",
                    "label": "Army 2 Starts",
                    "textColor": "White",
                    "callback": "initiative_btn_army2"
                },
                "BTN_SINGLE": {
                    "action": "CONFIRM",
                    "label": "Confirm Initiative",
                    "textColor": "Black",
                    "callback": "initiative_btn_single"
                }
            },
            "transitions": [
                {
                    "to": "MOVE",
                    "conditions": ["both_players_selected", "confirm_ready"]
                }
            ]
        },

        "MOVE": {
            "title": "PHASE: MOVE",
            "desc": "Move your army",
            "allowedActions": ["ARMY1_CLICK", "ARMY2_CLICK", "CONFIRM"],
            "render": "3BtnClick",
            "buttons": {
                "BTN_ARMY1": {
                    "action": "ARMY1_CLICK",
                    "label": "Army 1 Done",
                    "textColor": "White",
                    "callback": "move_btn_army1"
                },
                "BTN_ARMY2": {
                    "action": "ARMY2_CLICK",
                    "label": "Army 2 Done",
                    "textColor": "White",
                    "callback": "move_btn_army2"
                },
                "BTN_SINGLE": {
                    "action": "CONFIRM",
                    "label": "Confirm Move",
                    "textColor": "Black",
                    "callback": "move_btn_single"
                }
            },
            "transitions": [
                {
                    "to": "SHOOT",
                    "conditions": ["both_players_selected", "confirm_ready"]
                }
            ]
        },

        "SHOOT": {
            "title": "PHASE: SHOOT",
            "desc": "Open fire on targets",
            "allowedActions": ["ARMY1_CLICK", "ARMY2_CLICK", "CONFIRM"],
            "render": "3BtnClick",
            "buttons": {
                "BTN_ARMY1": {
                    "action": "ARMY1_CLICK",
                    "label": "Army 1 Done",
                    "textColor": "White",
                    "callback": "shoot_btn_army1"
                },
                "BTN_ARMY2": {
                    "action": "ARMY2_CLICK",
                    "label": "Army 2 Done",
                    "textColor": "White",
                    "callback": "shoot_btn_army2"
                },
                "BTN_SINGLE": {
                    "action": "CONFIRM",
                    "label": "Confirm Shoot",
                    "textColor": "Black",
                    "callback": "shoot_btn_single"
                }
            },
            "transitions": [
                {
                    "to": "ATTACK",
                    "conditions": ["both_players_selected", "confirm_ready"]
                }
            ]
        },

        "ATTACK": {
            "title": "PHASE: ATTACK",
            "desc": "Resolve combat",
            "allowedActions": ["ARMY1_CLICK", "ARMY2_CLICK", "CONFIRM"],
            "render": "3BtnClick",
            "buttons": {
                "BTN_ARMY1": {
                    "action": "ARMY1_CLICK",
                    "label": "Army 1 Done",
                    "textColor": "White",
                    "callback": "attack_btn_army1"
                },
                "BTN_ARMY2": {
                    "action": "ARMY2_CLICK",
                    "label": "Army 2 Done",
                    "textColor": "White",
                    "callback": "attack_btn_army2"
                },
                "BTN_SINGLE": {
                    "action": "CONFIRM",
                    "label": "Confirm Attack",
                    "textColor": "Black",
                    "callback": "attack_btn_single"
                }
            },
            "transitions": [
                {
                    "to": "MORALE",
                    "conditions": ["both_players_selected", "confirm_ready"]
                }
            ]
        },

        "MORALE": {
            "title": "PHASE: MORALE",
            "desc": "Test morale",
            "allowedActions": ["CONFIRM"],
            "turnStart": true,
            "render": "1BtnClick",
            "buttons": {
                "BTN_SINGLE": {
                    "action": "CONFIRM",
                    "label": "Next Turn",
                    "textColor": "Black",
                    "callback": "morale_btn_single"
                }
            },
            "transitions": [
                {
                    "to": "INITIATIVE",
                    "conditions": ["confirm_immediate"]
                }
            ]
        }
    }
    ]]

    local decoded = JSON.decode(phases_json)
    if not decoded then
        error("JSON decode FALLITO")
    end

    local phasesData = decoded[1] or decoded

    ENGINE = {
        phase = "SITTING",
        turn = 1,
        state = {
            Army1Click = false,
            Army2Click = false,
            ConfirmClick = false
        },
        phases = phasesData
    }

    engine_validatePhases()

    UI.setAttribute("BTN_ARMY1", "active", "true")
    UI.setAttribute("BTN_ARMY2", "active", "true")
    UI.setAttribute("BTN_SINGLE", "active", "true")
    fadeOut("WELCOME TO LIONHEART")
 
    clear()
    allPlayersGrey();
    updateCenterPanel()
    aggiornaLinee()

end

-- ============================================================
-- FUNZIONE: engine_validatePhases()
-- ============================================================
function engine_validatePhases()

    if not ENGINE.phases then
        error("ENGINE.phases NIL")
    end

    for phaseName, phaseData in pairs(ENGINE.phases) do

        if not phaseData.allowedActions then
            error("Manca allowedActions in fase: "..phaseName)
        end

        if not phaseData.transitions then
            error("Manca transitions in fase: "..phaseName)
        end

        if not phaseData.render then
            error("Manca render in fase: "..phaseName)
        end

        if phaseData.buttons then
            for slot, btn in pairs(phaseData.buttons) do
                if type(btn) ~= "table" then
                    error("Button malformato in fase: "..phaseName.." slot: "..slot)
                end

                if btn.action and type(btn.action) ~= "string" then
                    error("Button action non valida in fase: "..phaseName.." slot: "..slot)
                end

                if btn.label and type(btn.label) ~= "string" then
                    error("Button label non valida in fase: "..phaseName.." slot: "..slot)
                end

                if btn.textColor and type(btn.textColor) ~= "string" then
                    error("Button textColor non valida in fase: "..phaseName.." slot: "..slot)
                end

                if btn.callback and type(btn.callback) ~= "string" then
                    error("Button callback non valida in fase: "..phaseName.." slot: "..slot)
                end
            end
        end

        for i = 1, #phaseData.transitions do
            local t = phaseData.transitions[i]

            if not t.to then
                error("Transizione senza 'to' in fase: "..phaseName)
            end

            if not ENGINE.phases[t.to] then
                error("Transizione verso fase inesistente: "..t.to.." (da "..phaseName..")")
            end

            if not t.conditions then
                error("Transizione senza conditions in fase: "..phaseName)
            end
        end
    end
end

-- ==============================================================================================================
--                                                          ENGINE CORE
-- ==============================================================================================================
-- ============================================================
-- FUNZIONE: engine_handleButton()
-- ============================================================
    function engine_handleButton(slot, player, value, id)

        if DEBUG then print("engine_handleButton") end

        local phase = ENGINE.phases[ENGINE.phase]
        if not phase or not phase.buttons then return end

        local button = phase.buttons[slot]
        if not button then return end

        local allowed = true

        if button.callback then
            local fn = _G[button.callback]
            if fn then
                local result = fn(player, value, id)
                if result == false then
                    allowed = false
                end
            end
        end

        if not allowed then
            return
        end

        if button.action then
            engine_handleAction({
                type = button.action,
                player = player
            })
        end
    end

-- ============================================================
-- FUNZIONE: engine_handleAction()
-- ============================================================
function engine_handleAction(action)

    if DEBUG then print("engine_handleAction") end

    if not engine_isAllowed(action.type) then
        return
    end

    engine_execute(action)
    engine_transition(action)
    updateCenterPanel()
end

-- ============================================================
-- FUNZIONE: engine_isAllowed()
-- ============================================================
function engine_isAllowed(actionType)

    if DEBUG then print("engine_isAllowed") end

    local phase = ENGINE.phases[ENGINE.phase]
    if not phase then return false end

    for i = 1, #phase.allowedActions do
        if actionType == phase.allowedActions[i] then
            return true
        end
    end

    return false
end

-- ============================================================
-- FUNZIONE: engine_execute()
-- ============================================================
function engine_execute(action)

    if DEBUG then print("engine_execute") end

    if action.type == ACTION.ARMY1_CLICK then
        ENGINE.state.Army1Click = true

    elseif action.type == ACTION.ARMY2_CLICK then
        ENGINE.state.Army2Click = true

    elseif action.type == ACTION.CONFIRM then
        ENGINE.state.ConfirmClick = true
    end
end

-- ============================================================
-- FUNZIONE: engine_transition()
-- ============================================================
function engine_transition(action)

    if DEBUG then print("engine_transition") end

    local phase = ENGINE.phases[ENGINE.phase]
    if not phase then return end

    if action then
        for i = 1, #phase.transitions do
            local t = phase.transitions[i]

            if checkConditions(t.conditions, action) then
                ENGINE.phase = t.to
                engine_resetState()
                break
            end
        end
    end

    local changed = true

    while changed do
        changed = false

        local p = ENGINE.phases[ENGINE.phase]
        if not p then return end

        for i = 1, #p.transitions do
            local t = p.transitions[i]

            if checkConditions(t.conditions, nil) then
                ENGINE.phase = t.to
                engine_resetState()
                changed = true
                break
            end
        end
    end
end
-- ============================================================
-- FUNZIONE: checkConditions()
-- ============================================================
function checkConditions(conditions, action)
    
    if DEBUG then print("checkConditions") end

    if type(conditions) == "string" then
        return checkCondition(conditions, action)
    end

    if not conditions then
        return false
    end

    for i = 1, #conditions do
        if not checkCondition(conditions[i], action) then
            return false
        end
    end

    return true
end

-- ============================================================
-- FUNZIONE: checkCondition()
-- ============================================================
function checkCondition(cond, action)

    if DEBUG then print("checkCondition") end
    
    local phase = ENGINE.phases[ENGINE.phase]

    if cond == COND.BOTH_PLAYERS_SELECTED then
        return ENGINE.state.Army1Click and ENGINE.state.Army2Click
    end

    if cond == COND.CONFIRM_READY then
        return ENGINE.state.ConfirmClick
           and ENGINE.state.Army1Click
           and ENGINE.state.Army2Click
    end

    if cond == COND.CONFIRM_IMMEDIATE then
        if ENGINE.state.ConfirmClick and phase.turnStart then
            ENGINE.turn = ENGINE.turn + 1
        end
        return ENGINE.state.ConfirmClick
    end

    if cond == COND.AUTO_ADVANCE then
        return true
    end

    return false
end

-- ============================================================
-- FUNZIONE: engine_resetState()
-- ============================================================
function engine_resetState()

    if DEBUG then print("engine_resetState") end

    ENGINE.state = {
        Army1Click = false,
        Army2Click = false,
        ConfirmClick = false
    }
end

-- ============================================================
-- CALLBACKS
-- ============================================================
-- ============================================================
-- FUNZIONE: sitting_btn_army()
-- ============================================================
function sitting_btn_army(player, value, id)
    
    local colorPlayer = player.color
    
    if id == BUTTONS.BTN_ARMY1 then          
        if colorArmy1 == COLOR.NOARMY then
            if colorArmy2 == colorPlayer then
                colorArmy2 = COLOR.NOARMY
            end
            player.changeColor(COLOR.ARMY1)
            colorArmy1 = COLOR.ARMY1
            colorPlayer = COLOR.ARMY1
        else 
            if colorPlayer == colorArmy1 then
                fadeOut(army1 .. " already using this color") 
            else
                fadeOut("color " .. army1 .. " already used")  
            end
        end
    end

    if id == BUTTONS.BTN_ARMY2 then 
        if colorArmy2 == COLOR.NOARMY then
            if colorArmy1 == colorPlayer then
                colorArmy1 = COLOR.NOARMY
            end
            player.changeColor(COLOR.ARMY2)
            colorArmy2 = COLOR.ARMY2
            colorPlayer = COLOR.ARMY2
        else 
            if colorPlayer == colorArmy2 then
                fadeOut(army2 .. " already using this color") 
            else
                fadeOut("color " .. army2 .. " already used")  
            end
        end
    end      

    local playerArmy1 = Player[COLOR.ARMY1].seated
    local playerArmy2 = Player[COLOR.ARMY2].seated

    print("playerArmy1: ".. tostring(playerArmy1) .." - " .."playerArmy2: ".. tostring(playerArmy2))

    sitting_btn_army1(nil, playerArmy1, nil)
    
    sitting_btn_army2(nil, playerArmy2, nil)

    return false
 end
-- ============================================================
-- FUNZIONE: sitting_btn_army1()
-- ============================================================
   function sitting_btn_army1(player, value, id)
      return value
   end
-- ============================================================
-- FUNZIONE: sitting_btn_army2()
-- ============================================================
    function sitting_btn_army2(player, value, id)
        return value
    end
-- ============================================================
-- FUNZIONE: sitting_btn_single()
-- ============================================================
function sitting_btn_single(player, value, id)
    print("sitting_btn_single")
    return true
end

-- ============================================================
-- FUNZIONE: deploy_btn_army1()
-- ============================================================
function deploy_btn_army1(player, value, id)
    print("deploy_btn_army1")
    return true
end
-- ============================================================
-- FUNZIONE: deploy_btn_army2()
-- ============================================================
function deploy_btn_army2(player, value, id)
    print("deploy_btn_army2")
    return true
end

-- ============================================================
-- FUNZIONE: deploy_btn_single()
-- ============================================================
function deploy_btn_single(player, value, id)
    print("deploy_btn_single")
    return true
end

-- ============================================================
-- FUNZIONE: initiative_btn_army1()
-- ============================================================
function initiative_btn_army1(player, value, id)
    print("initiative_btn_army1")
    return true
end

-- ============================================================
-- FUNZIONE: initiative_btn_army2()
-- ============================================================
function initiative_btn_army2(player, value, id)
    print("initiative_btn_army2")
    return true
end

-- ============================================================
-- FUNZIONE: initiative_btn_single()
-- ============================================================
function initiative_btn_single(player, value, id)
     print("initiative_btn_single")
     return true
end
-- ============================================================
-- FUNZIONE: move_btn_army1()
-- ============================================================
function move_btn_army1(player, value, id)
    print("move_btn_army1")
    return true
end

-- ============================================================
-- FUNZIONE: move_btn_army2()
-- ============================================================
function move_btn_army2(player, value, id)
    print("move_btn_army2")
    return true
end

-- ============================================================
-- FUNZIONE: move_btn_single()
-- ============================================================
function move_btn_single(player, value, id)
    print("move_btn_single")
    return true
end

-- ============================================================
-- FUNZIONE: shoot_btn_army1()
-- ============================================================
function shoot_btn_army1(player, value, id)
    print("shoot_btn_army1")
    return true
end

-- ============================================================
-- FUNZIONE: shoot_btn_army2()
-- ============================================================
function shoot_btn_army2(player, value, id)
    print("shoot_btn_army2")
    return true
end

-- ============================================================
-- FUNZIONE: shoot_btn_single()
-- ============================================================
function shoot_btn_single(player, value, id)
    print("shoot_btn_single")
    return true
end

-- ============================================================
-- FUNZIONE: attack_btn_army1()
-- ============================================================
function attack_btn_army1(player, value, id)
    print("attack_btn_army1")
    return true
end

-- ============================================================
-- FUNZIONE: attack_btn_army2()
-- ============================================================
function attack_btn_army2(player, value, id)
    print("attack_btn_army2")
    return true
end

-- ============================================================
-- FUNZIONE: attack_btn_single()
-- ============================================================
function attack_btn_single(player, value, id)
    print("attack_btn_single")
    return true
end

-- ============================================================
-- FUNZIONE: morale_btn_single()
-- ============================================================
function morale_btn_single(player, value, id)
    print("morale_btn_single")
    return true
end

-- ============================================================
-- UI WRAPPER
-- ============================================================

-- ============================================================
-- FUNZIONE: onBtnArmy1()
-- ============================================================
function onBtnArmy1(player, value, id)
    engine_handleButton("BTN_ARMY1", player, value, id)
end

-- ============================================================
-- FUNZIONE: onBtnArmy2()
-- ============================================================
function onBtnArmy2(player, value, id)
    engine_handleButton("BTN_ARMY2", player, value, id)
end

-- ============================================================
-- FUNZIONE: onBtnScelta()
-- ============================================================
function onBtnScelta(player, value, id)
    engine_handleButton("BTN_SINGLE", player, value, id)
end

-- ============================================================
-- RENDERERS
-- ============================================================

RENDERERS = {}

-- ============================================================
-- FUNZIONE: RENDERERS.NoBtn()
-- ============================================================
    RENDERERS.NoBtn = function(phase)

        UI.setAttribute("BTN_ARMY1", "active", "false")
        UI.setAttribute("BTN_ARMY2", "active", "false")
        UI.setAttribute("BTN_SINGLE", "active", "false")

        UI.setAttribute("panelBtnUp", "active", "false")
        UI.setAttribute("panelBtnDown", "active", "false")
    end
-- ============================================================
-- FUNZIONE: RENDERERS.NoBtn()
-- ============================================================
    RENDERERS["1BtnClick"] = function(phase)

        UI.setAttribute("panelBtnUp", "active", "false")
        UI.setAttribute("panelBtnDown", "active", "true")
        UI.setAttribute("panelBtnDown", "offsetXY", "0 318")

        UI.setAttribute("BTN_SINGLE", "active", "true")
    end
-- ============================================================
-- FUNZIONE: RENDERERS.NoBtn()
-- ============================================================
    RENDERERS["2BtnClick"] = function(phase)

        UI.setAttribute("panelBtnUp", "active", "true")
        UI.setAttribute("panelBtnDown", "active", "false")
        UI.setAttribute("panelBtnUp", "offsetXY", "0 318")

        -- UI.setAttribute("BTN_ARMY1", "active", "true")
        -- UI.setAttribute("BTN_ARMY2", "active", "true")
    end
-- ============================================================
-- FUNZIONE: RENDERERS.NoBtn()
-- ============================================================
    RENDERERS["3BtnClick"] = function(phase)

        UI.setAttribute("panelBtnUp", "active", "true")
        UI.setAttribute("panelBtnDown", "active", "false")
        UI.setAttribute("panelBtnUp", "offsetXY", "0 318")

        -- UI.setAttribute("BTN_ARMY1", "active", "true")
        -- UI.setAttribute("BTN_ARMY2", "active", "true")

        if ENGINE.state.Army1Click and ENGINE.state.Army2Click then
            UI.setAttribute("panelBtnUp", "active", "false")
            UI.setAttribute("panelBtnDown", "active", "true")
            UI.setAttribute("panelBtnDown", "offsetXY", "0 318")
            UI.setAttribute("BTN_SINGLE", "active", "true")
        end
    end
-- ============================================================
-- FUNZIONE: updateCenterPanel()
-- ============================================================
function updateCenterPanel()

    UI.setAttribute("army1", "color", colorArmy1 or "Grey")
    UI.setAttribute("army2", "color", colorArmy2 or "Grey")

    if not ENGINE or not ENGINE.phase then
        printToAll("ENGINE non inizializzato", "Red")
        return
    end

    local phase = ENGINE.phases[ENGINE.phase]

    if not phase then
        printToAll("Fase non trovata: "..tostring(ENGINE.phase), "Red")
        return
    end

    local buttons = phase.buttons or {}

    local btn1 = buttons.BTN_ARMY1
    local btn2 = buttons.BTN_ARMY2
    local btnS = buttons.BTN_SINGLE

    UI.setAttribute("textFase", "text", phase.title or "")
    UI.setAttribute("textDesc", "text", phase.desc or "")
    UI.setAttribute("textTurn", "text", ENGINE.turn == 0 and "" or " TURN: "..ENGINE.turn)
    
    UI.setAttribute("BTN_ARMY1", "text", btn1 and btn1.label or "")
    UI.setAttribute("BTN_ARMY1", "textColor", btn1 and btn1.textColor)

    UI.setAttribute("BTN_ARMY2", "text", btn2 and btn2.label or "")
    UI.setAttribute("BTN_ARMY2", "textColor", btn2 and btn2.textColor)

    UI.setAttribute("BTN_SINGLE", "text", btnS and btnS.label or "")
    UI.setAttribute("BTN_SINGLE", "textColor", btnS and btnS.textColor)

    -- UI.setAttribute("BTN_ARMY1", "active", "false")
    -- UI.setAttribute("BTN_ARMY2", "active", "false")
    -- UI.setAttribute("BTN_SINGLE", "active", "false")

    UI.setAttribute("panelBtnUp", "active", "true")
    UI.setAttribute("panelBtnDown", "active", "true")
    UI.setAttribute("panelBtnUp", "offsetXY", "0 318")
    UI.setAttribute("panelBtnDown", "offsetXY", "0 266")

    local renderer = RENDERERS[phase.render]

    if renderer then
        renderer(phase)
    else
        printToAll("Renderer non trovato: "..tostring(phase.render), "Red")
    end
end
-- ================================================================================================================================
--                                                           PLAYERS SEATED
-- ================================================================================================================================
army1 = "Army1"
army2 = "Army2"
colorArmy1 = "Grey"
colorArmy2 = "Grey"
numeroPlayerSeated = 0

-- ============================================================
-- FUNZIONE: allPlayersGrey()
-- ============================================================
function allPlayersGrey()
    for _, p in ipairs(Player.getPlayers()) do
        if p then
          p.changeColor("Grey")
        end
    end
end
-- ============================================================
-- FUNZIONE: countSeated()
-- ============================================================
function countSeated()
    numeroPlayerSeated = 0
    for _, p in ipairs(Player.getPlayers()) do
        if p and p.seated then
            if p and p.seated then
                if p.color == "Green" then numeroPlayerSeated=numeroPlayerSeated+1 end
                if p.color == "Red" then numeroPlayerSeated=numeroPlayerSeated+1 end                
            end
        end
    end
    return numeroPlayerSeated
end
-- ============================================================
-- FUNZIONE: isOtherPlayerSeated()
-- ============================================================
function isOtherPlayerSeated(player)


    local function checkPlayer(player)
        if player.color ~= COLOR.NOARMY then 
            return true
        end    
    end    

    for _, p in ipairs(Player.getPlayers()) do
        if p and p.seated then
            if p.steam_name ~= player.steam_name then
                return checkPlayer(p)
            end
        end
    end
    return false
end
-- ============================================================
-- FUNZIONE: isArmy1Seated()
-- ============================================================
function isArmy1Seated()
    for _, p in ipairs(Player.getPlayers()) do
        if p and p.seated then
            if p.color == "Green" then 
                return true
            end
        end
    end
end
-- ============================================================
-- FUNZIONE: isArmy2Seated()
-- ============================================================
function isArmy2Seated()
    for _, p in ipairs(Player.getPlayers()) do
        if p and p.seated then
            if p.color == "Red" then 
                return true
            end
        end
    end
end
-- ============================================================
-- FUNZIONE: onPlayerConnect()
-- ============================================================
function onPlayerConnect(player)
    print(player.steam_name)
    print(player.color)
end
-- ============================================================
-- FUNZIONE: onPlayerDisconnect()
-- ============================================================
function onPlayerDisconnect(player)
    print(player.steam_name)
    print(player.color)
end
-- ============================================================
-- FUNZIONE: onPlayerChangeColor()
-- ============================================================
function onPlayerChangeColor(color)

    if not color then return end
    if color == "Black" or color == "Grey" then 

            if not isArmy1Seated() then
                colorArmy1 = "Grey"
            end

            if not isArmy2Seated() then
                colorArmy2 = "Grey"
            end        
    end

    if color == "Red" then colorArmy1 = color end  
    if color == "Green" then colorArmy2 = color end

    updateCenterPanel()
end
-- ============================================================
-- FUNZIONE: setPlayerRed()
-- ============================================================
function setPlayerRed(player, value, id)

    if Player["Red"].seated then
        player.broadcast("color " .. army1 .. " already used")
    else    
        player.changeColor("Red")
        print(player.steam_name .. " choose ".. army1)
    end
end
-- ============================================================
-- FUNZIONE: setPlayerGreen()
-- ============================================================
function setPlayerGreen(player, value, id)
    
    if Player["Green"].seated then
        player.broadcast("color " .. army2 .. " already used")
    else    
        player.changeColor("Green")
        print(player.steam_name .. " choose ".. army2)
    end
end

function fadeOut(warning)

    local alpha = 1
    

    UI.setAttribute("textWarning", "active", "true")
    UI.setAttribute("textWarning", "text", warning)

    local function step()
        alpha = alpha - 0.05
        if alpha <= 0 then
            UI.setAttribute("textWarning", "active", "false")
            return
        end
     
        UI.setAttribute("textWarning", "color", "rgba(255,215,0," .. alpha .. ")")
        Wait.time(step, 0.2)
    end

    step()
end
