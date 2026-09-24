--[[----------------------------------------------------------------------------
    Debug — Ausgabekanaele.

    Vorgabe aus der Spezifikation: "Debug-Ausgaben muessen im normalen Betrieb
    deaktiviert sein." Umgesetzt ueber Kanaele statt eines einzelnen Schalters —
    sonst ist der Debug-Modus im Raid unbenutzbar laut, sobald das Combat Log
    mitprotokolliert.

        /rb debug              Debug an/aus
        /rb debug roster       Nur den Kanal "roster" umschalten
------------------------------------------------------------------------------]]

local _, GA = ...

local Debug = {}
GA.Core.Debug = Debug

local PREFIX = "|cffe5cc80GA|r "

--- Bekannte Kanaele mit Beschreibung. Unbekannte Kanaele sind stumm.
Debug.channels = {
    core       = "Laden, Datenbank, Migration",
    armory     = "Ausruestungserfassung und Snapshots",
    guild      = "Gildenroster",
    loot       = "Loot-Erkennung, Sessions, Vergaben",
    trade      = "Handelsbestaetigung",
    comm       = "Addon-Nachrichten (gespraechig)",
    ui         = "Ansichten, Neuzeichnen",
    callbacks  = "Fehler in Empfaengern",
    craft      = "Berufe und Rezepte",
    camp       = "Lagerleiste und Aufstellungen",
}

local enabled = {}

function Debug:IsEnabled(channel)
    -- Core\Events registriert Ereignisse bereits beim Laden der Datei, also bevor
    -- ADDON_LOADED die Datenbank aufgebaut hat. Schlaegt dort eine Registrierung
    -- fehl, laeuft der Fehlerpfad durch diese Funktion — ohne diese Pruefung
    -- waere die Diagnose selbst die Fehlerquelle.
    local database = GA.Core.Database
    if not database or not database.char then return false end
    if not database.char.debug then return false end

    if channel == nil then return true end
    -- Ohne ausdrueckliche Auswahl sind alle Kanaele ausser dem lautesten aktiv.
    if next(enabled) == nil then return channel ~= "comm" end
    return enabled[channel] == true
end

function Debug:Print(channel, format, ...)
    if not self:IsEnabled(channel) then return end

    local ok, message = pcall(string.format, format, ...)
    if not ok then message = tostring(format) end

    print(PREFIX .. "|cff6f6753[" .. tostring(channel) .. "]|r " .. message)
end

--- Ausgabe, die auch ohne Debug-Modus erscheint. Fuer echte Fehler.
function Debug:Warn(format, ...)
    local ok, message = pcall(string.format, format, ...)
    if not ok then message = tostring(format) end
    print(PREFIX .. "|cffc8402f" .. message .. "|r")
end

function Debug:Info(format, ...)
    local ok, message = pcall(string.format, format, ...)
    if not ok then message = tostring(format) end
    print(PREFIX .. message)
end

function Debug:ToggleChannel(channel)
    if not self.channels[channel] then
        self:Info("Unbekannter Kanal: %s", tostring(channel))
        return
    end
    enabled[channel] = not enabled[channel] or nil
    self:Info("Kanal %s: %s", channel, enabled[channel] and "an" or "aus")
end

function Debug:Toggle()
    local db = GA.Core.Database.char
    db.debug = not db.debug
    self:Info("Debug-Modus: %s", db.debug and "|cff4caf50an|r" or "aus")
    return db.debug
end

--- Sammelbericht fuer die Fehlersuche.
function Debug:Report()
    local stats = GA.Core.Database:Stats()

    local lines = {
        PREFIX .. "Diagnose",
        string.format("  Version %s, DB-Schema %s", GA.version, tostring(stats.schemaVersion)),
        string.format("  %d Spieler, %d Strategien, %d Raids, %d Pulls",
            stats.players, stats.strategies, stats.raids, stats.pulls),
        "  Client-Faehigkeiten:",
        GA.Core.Compat.Describe(),
        "  Callbacks:",
        GA.Core.Callbacks:Describe(),
    }

    print(table.concat(lines, "\n"))
end
