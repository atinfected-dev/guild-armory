--[[----------------------------------------------------------------------------
    Raids/History — was aus den hochgeladenen Logs bekannt ist.

    Kein UI. Liest Data/RaidHistory.lua (erzeugt aus Warcraft Logs) und
    beantwortet daraus Fragen ueber einen Spieler.

    ===========================================================================
    ZWEI QUELLEN FUER DIESELBE FRAGE — UND WARUM NICHT ADDIERT WIRD
    ===========================================================================

    "Wie viele Raidabende war ich dabei?" lässt sich jetzt zweimal
    beantworten:

      Raids/Attendance  was DIESER Client gesehen hat. Beginnt mit der
                        Installation, ist aber selbst gemessen.
      Raids/History     was hochgeladen wurde. Reicht weiter zurueck, fehlt
                        aber fuer jeden Abend, den niemand hochgeladen hat.

    Beide beschreiben dieselben Abende und ueberschneiden sich. ADDIEREN
    WAERE FALSCH: Ein Abend, der gemessen UND hochgeladen wurde, zaehlte
    doppelt.

    Genommen wird deshalb der GROESSERE der beiden Werte. Das ist keine
    Bequemlichkeit, sondern das einzig Richtige: Beide Zahlen sind
    Untergrenzen der Wahrheit, und die groessere Untergrenze ist die bessere.
    Eine echte Vereinigung braeuchte einen Abgleich Abend fuer Abend — und
    die Zeitstempel der beiden Quellen stammen aus verschiedenen Uhren.

    ===========================================================================
    WAS DARAUS FOLGT FUER DEN BELEG
    ===========================================================================

    Ein Erfolg, der nur wegen dieser Daten aufgeht, ist BEOBACHTET und nicht
    gemessen. Das Addon hat den Abend nicht gesehen; es glaubt einem
    Hochladenden und Warcraft Logs. Der Unterschied steht in der Ansicht, und
    er gehoert dorthin.
------------------------------------------------------------------------------]]

local _, GA = ...

local History = {}
GA.Modules.History = History

local Util = GA.Core.Util

local function data()
    return GA.Data.RaidHistory or { nights = {}, firstKills = {} }
end

--- Gibt es ueberhaupt etwas?
function History:Available()
    local store = data()
    return #(store.nights or {}) > 0
end

function History:Stand()
    local store = data()
    return { generated = store.generated or 0, reports = store.reports or 0,
             nights = #(store.nights or {}) }
end

--- Alle Charakternamen eines Spielers, kurz und kleingeschrieben.
---
--- Kleingeschrieben, weil Warcraft Logs und der Client sich bei der
--- Schreibweise nicht immer einig sind. Gekuerzt, weil im Log kein Realm
--- steht — und im Addon manchmal schon.
local function namesOf(profile)
    local wanted = {}
    if not profile then return wanted end

    for _, character in ipairs(GA.Modules.Players:CharactersOf(profile)) do
        local name = character.name and Util.ShortName(character.name)
        if name and name ~= "" then wanted[string.lower(name)] = true end
    end
    return wanted
end

--- Was die Logs ueber diesen Spieler wissen.
---
--- @param profile table  Spielerprofil, nicht ein einzelner Charakter
--- @return table { nights, minutes, kills, wipes }
function History:StatsFor(profile)
    local wanted = namesOf(profile)
    local stats = { nights = 0, minutes = 0, kills = 0, wipes = 0 }

    for _, night in ipairs(data().nights or {}) do
        local hier = nil
        for _, entry in ipairs(night.players or {}) do
            -- Der Eintrag ist eine Liste: { Name, Minuten, Kills }. Kurz,
            -- weil davon tausende in der Datei stehen.
            local name = entry[1]
            if name and wanted[string.lower(name)] then hier = entry break end
        end

        if hier then
            -- EIN ABEND, NICHT EIN CHARAKTER. Wer mit Main und Twink im
            -- selben Log steht, war trotzdem einen Abend dabei.
            stats.nights = stats.nights + 1
            stats.minutes = stats.minutes + (tonumber(hier[2]) or 0)
            stats.kills = stats.kills + (tonumber(hier[3]) or 0)
            -- Wipes gehoeren dem Abend, nicht dem Spieler: Wer da war, war
            -- bei ihnen dabei.
            stats.wipes = stats.wipes + (tonumber(night.wipes) or 0)
        end
    end

    return stats
end

--- Der erste bekannte Kill eines Bosses, oder nil.
--- @return number|nil zeitpunkt, string|nil name
function History:FirstKill(encounterID)
    for _, entry in ipairs(data().firstKills or {}) do
        if entry[1] == encounterID then return entry[3], entry[2] end
    end
    return nil
end

--- Wie viele verschiedene Bosse hat die Gilde nachweislich gelegt?
function History:BossesDowned()
    return #(data().firstKills or {})
end
