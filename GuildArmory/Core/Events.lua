--[[----------------------------------------------------------------------------
    Events — EIN Frame fuer alle Spielereignisse.

    Warum genau einer: Jeder registrierte Frame kostet bei jedem Ereignis einen
    eigenen Aufruf. Bei COMBAT_LOG_EVENT_UNFILTERED im 40er-Raid ist das der
    Unterschied zwischen unauffaellig und spuerbar. Module melden sich hier an und
    nicht beim Spiel.

    Aussen sichtbar:
        Events:Register("GROUP_ROSTER_UPDATE", handler, owner)
        Events:Unregister("GROUP_ROSTER_UPDATE", owner)

    Ein Ereignis wird beim Spiel erst registriert, wenn der erste Empfaenger da ist,
    und wieder abgemeldet, wenn der letzte geht (Vorgabe: "Events nur registrieren,
    wenn benoetigt").
------------------------------------------------------------------------------]]

local _, GA = ...

local Events = {}
GA.Core.Events = Events

local frame = CreateFrame("Frame", "GuildArmoryEventFrame")
local handlers = {}

--- Ereignisse, die dieser Client nicht kennt. Wird fuer die Diagnose gemerkt.
Events.unsupported = {}

local function dispatch(_, event, ...)
    local list = handlers[event]
    if not list then return end

    for index = 1, #list do
        local ok, err = pcall(list[index].handler, event, ...)
        if not ok then
            GA.Core.Debug:Warn("Fehler im Handler fuer %s: %s", event, tostring(err))
        end
    end
end

frame:SetScript("OnEvent", dispatch)

function Events:Register(event, handler, owner)
    local list = handlers[event]

    if not list then
        -- Ein dem Client unbekannter Eventname wirft beim Registrieren. Da die
        -- Zielplattform noch nicht feststeht, darf das nicht das Addon abbrechen.
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            self.unsupported[event] = true
            GA.Core.Debug:Print("core", "Event nicht verfuegbar: %s", event)
            return false
        end
        list = {}
        handlers[event] = list
    end

    list[#list + 1] = { handler = handler, owner = owner }
    return true
end

function Events:Unregister(event, owner)
    local list = handlers[event]
    if not list then return end

    for index = #list, 1, -1 do
        if list[index].owner == owner then
            table.remove(list, index)
        end
    end

    if #list == 0 then
        handlers[event] = nil
        pcall(frame.UnregisterEvent, frame, event)
    end
end

function Events:IsSupported(event)
    return not self.unsupported[event]
end

-- --------------------------------------------------------------- Startlauf ---

--- Reihenfolge beim Laden:
---   ADDON_LOADED (eigenes Addon) -> Datenbank steht
---   PLAYER_LOGIN                 -> UI und Module duerfen starten
local bootstrap = CreateFrame("Frame")

-- Spiegelung beim Abmelden. Eigener Rahmen statt eines Aufrufs in
-- Core/Export: Der Export darf ausfallen, die Spiegelung nicht — sie ist
-- das Einzige, was die Daten auf diesem Client ueberhaupt ueberleben laesst
-- (siehe Database/Database.lua, pickSource).
local mirror = CreateFrame("Frame")
mirror:RegisterEvent("PLAYER_LOGOUT")
mirror:SetScript("OnEvent", function()
    if GA.Core.Database and GA.Core.Database.Mirror then
        GA.Core.Database:Mirror()
    end
end)

bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")

bootstrap:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == GA.name then
        -- WAS DER CLIENT GELIEFERT HAT — gemessen VOR Initialize.
        --
        -- Die Reihenfolge ist hier nicht nebensaechlich: Danach hat
        -- ApplyDefaults die Tabellen laengst angelegt, und jede Messung
        -- meldet nur noch die eigene Arbeit zurueck. Genau daran ist die
        -- erste Fassung dieser Sonde gescheitert (20.09.2026) — sie zeigte
        -- immer "geladen" und hat damit tagelang in die Irre gefuehrt.
        GA.storagePre = {
            account = type(_G.GuildArmoryDB) == "table",
            character = type(_G.GuildArmoryCharDB) == "table",
        }

        GA.Core.Database:Initialize()
        GA.Core.Debug:Print("core", "Datenbank geladen, Schema %s, Quelle %s",
            tostring(GA.Core.Database.account.schemaVersion),
            tostring(GA.Core.Database.storage.source))
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")

        -- EINMALIGER HINWEIS, wenn der Client nichts geliefert hat.
        --
        -- Gemessen am 20.09.2026 auf dem Forever-Beta: SavedVariables werden
        -- korrekt geschrieben, aber nie eingelesen — weder kontoweit noch
        -- pro Charakter, und bei einem zweiten Addon genauso. Ohne diesen
        -- Hinweis traegt jemand einen Abend lang Vergaben ein und findet sie
        -- am naechsten Tag nicht wieder, ohne je zu erfahren, warum.
        --
        -- Beim allerersten Start ist die Meldung ebenfalls richtig: Dann gibt
        -- es tatsaechlich nichts zu laden. Sie behauptet deshalb keinen
        -- Fehler, sondern nennt nur den Zustand.
        if GA.Core.Database.storage and GA.Core.Database.storage.nothingLoaded then
            print("|cffe5cc80Guild Armory:|r " .. GA.L.STORAGE_EMPTY)
        end

        -- Reihenfolge: Sprache -> Messung der Faehigkeiten -> Bootstrap-Admin
        -- -> Module. Die Messung braucht einen eingeloggten Charakter.
        GA.Core.Locale:Apply()
        GA.Core.Compat.Measure()
        GA.Core.Database:EnsureBootstrapAdmin(UnitGUID("player"))
        -- Die Nachrichtenschicht vor den Modulen: Module haengen sich beim
        -- Starten an Nachrichtentypen, und dafuer muss Comm schon stehen.
        if GA.Core.Comm then GA.Core.Comm:OnEnable() end
        if GA.Core.Export then GA.Core.Export:OnEnable() end
        -- Die Sonde haengt unter GA.Core, nicht unter GA.Modules: Die
        -- Schleife weiter unten wuerde sie nicht finden.
        if GA.Core.Probe then GA.Core.Probe:OnEnable() end

        -- Module zuerst: Sie fuellen den Zustand, den die Views danach anzeigen.
        for name, module in pairs(GA.Modules) do
            if type(module.OnEnable) == "function" then
                local ok, err = pcall(module.OnEnable, module)
                if not ok then
                    GA.Core.Debug:Warn("Modul %s konnte nicht starten: %s", name, tostring(err))
                end
            end
        end

        GA.Core.Callbacks:Fire("ADDON_READY")
        GA.Core.Debug:Print("core", "Bereit. Version %s", GA.version)
    end
end)

