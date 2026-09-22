--[[----------------------------------------------------------------------------
    Raids/CombatLog — die Aufzeichnung beim Betreten eines Raids einschalten.

    Kein UI. Wird von Raids/Attendance angestossen, das ohnehin weiss, ob man
    gerade in einer Schlachtzugsinstanz steht.

    ===========================================================================
    STANDARD AUS, UND DAS BLEIBT SO
    ===========================================================================

    Was hier eingeschaltet wird, legt eine DATEI auf der Festplatte an —
    mehrere Megabyte je Abend, mit den Namen und Kennungen aller Anwesenden.
    Auch derer, die nicht in der Gilde sind und nie gefragt wurden.

    Ein Addon, das so etwas ungefragt tut, hat seine Befugnis ueberschritten.
    Deshalb:

      Die Einstellung ist AUS, bis jemand sie einschaltet.
      Ist sie aus, wird LoggingCombat NIE aufgerufen — auch nicht lesend.
      Wer sie einschaltet, bekommt in den Einstellungen gesagt, was entsteht.

    ===========================================================================
    WAS WIR EINGESCHALTET HABEN, SCHALTEN WIR AUS — MEHR NICHT
    ===========================================================================

    Lief die Aufzeichnung schon, als wir den Raid betraten, dann hat sie
    jemand anders gestartet — ein anderes Addon oder der Spieler selbst mit
    /combatlog. Die ruehren wir beim Verlassen NICHT an.

    Ohne diese Unterscheidung wuerde das Addon eine laufende Aufzeichnung
    beenden, die jemand fuer etwas anderes braucht, und der merkt es erst,
    wenn die Datei fehlt.

    ===========================================================================
    WOFUER DAS GANZE
    ===========================================================================

    Die Datei kann das Addon nicht lesen — Addons lesen keine Dateien. Sie
    ist fuer das Begleitprogramm und die Webapp: Dort stecken Wipes, Tode,
    Todesursachen und Bosskills drin, also alles, was der Client dem Addon
    verweigert (COMBAT_LOG_EVENT_UNFILTERED feuert auf Forever nicht,
    gemessen 18.09.2026).
------------------------------------------------------------------------------]]

local _, GA = ...

local CombatLog = {}
GA.Modules.CombatLog = CombatLog

local Compat = GA.Core.Compat
local Debug = GA.Core.Debug

--- Haben WIR sie eingeschaltet? Entscheidet, ob wir sie beenden duerfen.
CombatLog.ours = false

--- Einmal melden, nicht bei jedem Betreten.
local warned = false

local function wanted()
    return GA.Core.Config:Get("autoCombatLog") and true or false
end

--- Kann dieser Client es ueberhaupt?
--- @return boolean|nil  nil = noch nicht gefragt (Einstellung aus)
function CombatLog:Available()
    if not wanted() then return nil end
    return Compat.IsCombatLogging() ~= nil
end

--- Wendet die Regel an.
---
--- @param inRaid boolean  stehe ich in einer Schlachtzugsinstanz?
--- @return string  was getan wurde: "aus" | "an" | "beendet" | "fremd" | "nichts"
function CombatLog:Apply(inRaid)
    -- EINSTELLUNG AUS HEISST: GAR NICHTS ANFASSEN. Nicht einmal nachsehen,
    -- ob sie laeuft — das waere zwar harmlos, aber die Zusage lautet "wir
    -- fassen es nicht an", und die soll im Code genauso dastehen.
    if not wanted() then
        self.ours = false
        return "aus"
    end

    local running = Compat.IsCombatLogging()
    if running == nil then
        if not warned then
            warned = true
            Debug:Info("%s", GA.L.COMBATLOG_UNAVAILABLE)
        end
        return "nichts"
    end

    if inRaid then
        if running then
            -- Lief schon. Entweder von uns (dann bleibt ours true) oder von
            -- jemand anderem — in dem Fall merken wir uns das NICHT als
            -- unsere und lassen sie beim Verlassen in Ruhe.
            return self.ours and "an" or "fremd"
        end

        local after = Compat.SetCombatLogging(true)
        if after ~= true then
            if not warned then
                warned = true
                Debug:Info("%s", GA.L.COMBATLOG_FAILED)
            end
            return "nichts"
        end

        self.ours = true
        Debug:Print("core", "Combat Log eingeschaltet")
        return "an"
    end

    -- Draussen. Nur beenden, was wir angefangen haben.
    if running and self.ours then
        Compat.SetCombatLogging(false)
        self.ours = false
        Debug:Print("core", "Combat Log beendet")
        return "beendet"
    end

    return running and "fremd" or "nichts"
end
