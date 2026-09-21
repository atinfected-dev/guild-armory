--[[----------------------------------------------------------------------------
    LootCouncil/PlusOne — wie oft jemand schon etwas bekommen hat.

    Kein UI. Liefert dem Council eine Zahl, die beim Abwaegen hilft: Wer heute
    schon zwei Gegenstaende bekommen hat, steht anders da als jemand, der seit
    vier Wochen leer ausgeht.

    DIE ENTSCHEIDUNG, DIE DEN ZAEHLER EHRLICH HAELT:

      ER WIRD NICHT GEFUEHRT, SONDERN GERECHNET.

      Die naheliegende Umsetzung waere ein gespeicherter Zaehler, der bei
      jeder Vergabe um eins steigt. Der laeuft frueher oder spaeter von der
      Historie weg: eine Korrektur, ein verpasstes Ereignis, ein Import — und
      ab da behauptet die Zahl etwas, das in der Loot-Historie nicht steht.
      Und niemand merkt es, weil die Zahl ja "gepflegt" wird.

      Hier wird sie stattdessen bei jedem Abruf aus den Vergaben gerechnet.
      Sie KANN der Historie nicht widersprechen, weil sie nichts anderes ist
      als die Historie, gezaehlt.

      Was sich von Hand aendern laesst, ist ein getrennter AUSGLEICH — eine
      Zahl neben der gerechneten, mit Grund und Journaleintrag. Damit bleibt
      sichtbar, was gemessen und was entschieden wurde.

    WAS GEZAEHLT WIRD:

      Nur BESTAETIGTE Vergaben. Eine Vergabe ohne Bestaetigungsart ist eine
      Absicht, kein Erhalt (Abschnitt 4.3) — sie in einen Fairnesszaehler zu
      nehmen hiesse, jemanden fuer etwas zu belasten, das er vielleicht nie
      bekommen hat.

      Handbestaetigungen zaehlen mit, werden aber GETRENNT ausgewiesen. Eine
      Zahl, die Messungen und Behauptungen zusammenwirft, sieht genauer aus,
      als die Daten sind.

    WEM GEZAEHLT WIRD:

      Dem SPIELER, nicht dem Charakter. Sonst holt man sich den naechsten
      Gegenstand mit dem Twink.
------------------------------------------------------------------------------]]

local _, GA = ...

local PlusOne = {}
GA.Modules.PlusOne = PlusOne

local Util = GA.Core.Util
local Debug = GA.Core.Debug

local Schema = GA.Data.Schema
local Status = Schema.LootStatus

--- Ab welcher Qualitaet mitgezaehlt wird. Ein gruenes Ersatzteil ist kein
--- Ereignis, das jemanden hinten anstellen sollte.
local MIN_QUALITY = 4

local function store()
    local db = GA.Core.Database.account
    db.plusOneOffsets = db.plusOneOffsets or {}
    return db.plusOneOffsets
end

-- ================================================================== Rechnen --

--- Zaehlt eine Vergabe mit?
--- @return boolean zaehlt, boolean nurBehauptet
local function counts(award, since, minQuality)
    -- Eine Probevergabe (/ga test) darf niemanden hinten anstellen.
    if award.test then return false end

    if award.status ~= Status.RECEIVED and award.status ~= Status.EQUIPPED then
        return false
    end
    -- Ohne Bestaetigungsart gibt es keinen Erhalt. Die Statusmaschine laesst
    -- das gar nicht zu; die Pruefung steht hier trotzdem, weil ein
    -- importierter oder abgeglichener Datensatz aus einer aelteren Fassung
    -- kommen kann.
    if not award.confirmation then return false end
    if (award.quality or 0) < (minQuality or MIN_QUALITY) then return false end
    if since and (award.confirmedTs or award.ts or 0) < since then return false end

    return true, award.confirmation == "MANUAL"
end

--- Der Stand aller Spieler.
---
--- @param options table|nil { since, minQuality }
--- @return table [playerId] = { id, name, counted, manual, offset, total, last }
function PlusOne:Compute(options)
    options = options or {}
    local Players = GA.Modules.Players
    local out = {}

    -- Erst alle Profile anlegen, damit auch die auftauchen, die nichts
    -- bekommen haben. Genau die sind fuer das Council interessant.
    for id, profile in pairs(GA.Core.Database.account.players) do
        out[id] = {
            id = id,
            name = Players:DisplayName(profile),
            counted = 0,
            manual = 0,
            offset = 0,
            last = nil,
        }
    end

    for _, award in pairs(GA.Core.Database.account.awards) do
        local ok, manualOnly = counts(award, options.since, options.minQuality)
        if ok then
            local profile = award.recipientGuid and Players:GetProfileFor(award.recipientGuid)
            local entry = profile and out[profile.id]

            -- Ohne Profil laesst sich die Vergabe niemandem zuordnen. Sie
            -- einem Namen zuzuschlagen waere geraten: Zwei Charaktere koennen
            -- denselben Kurznamen tragen, und der Twink waere unsichtbar.
            if entry then
                entry.counted = entry.counted + 1
                if manualOnly then entry.manual = entry.manual + 1 end
                local ts = award.confirmedTs or award.ts
                if ts and (not entry.last or ts > entry.last) then entry.last = ts end
            end
        end
    end

    for id, entry in pairs(out) do
        entry.offset = tonumber(store()[id]) or 0
        entry.total = entry.counted + entry.offset
    end
    return out
end

--- Als Liste, wenigste zuerst — die Reihenfolge, in der das Council schaut.
function PlusOne:List(options)
    local list = {}
    for _, entry in pairs(self:Compute(options)) do list[#list + 1] = entry end

    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total < b.total end
        -- Bei gleichem Stand der, dessen letzter Gegenstand laenger her ist.
        -- Wer noch nie etwas bekommen hat (last = nil), steht ganz vorn.
        local aLast, bLast = a.last or 0, b.last or 0
        if aLast ~= bLast then return aLast < bLast end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

--- Der Stand eines einzelnen Charakters oder Profils.
function PlusOne:For(guid, options)
    local profile = guid and GA.Modules.Players:GetProfileFor(guid)
    if not profile then return nil end
    return self:Compute(options)[profile.id]
end

-- ================================================================== Ausgleich

--- Von Hand nachjustieren.
---
--- Der Ausgleich steht NEBEN der gerechneten Zahl, nicht statt ihr: Sonst
--- waere nicht mehr zu sehen, was gemessen und was entschieden wurde.
--- @return boolean ok, number|string neuerWert oder Grund
function PlusOne:Adjust(playerId, delta, reason, byGuid)
    if not playerId then return false, "noplayer" end
    delta = tonumber(delta)
    if not delta or delta == 0 then return false, "nodelta" end

    local offsets = store()
    local before = tonumber(offsets[playerId]) or 0
    local after = before + delta
    offsets[playerId] = after ~= 0 and after or nil

    GA.Core.Database:Journal("PLUSONE_ADJUST", playerId, before,
        { offset = after, reason = reason }, byGuid)
    GA.Core.Callbacks:Fire("PLUSONE_CHANGED")

    Debug:Print("council", "Plus-Eins-Ausgleich %s: %d -> %d (%s)",
        tostring(playerId), before, after, tostring(reason))
    return true, after
end

--- Alle Ausgleiche zuruecksetzen. Die gerechnete Zahl bleibt, wie sie ist —
--- sie haengt an der Historie und nicht an dieser Tabelle.
function PlusOne:ResetOffsets(byGuid)
    local count = 0
    for id in pairs(store()) do
        store()[id] = nil
        count = count + 1
    end
    if count > 0 then
        GA.Core.Database:Journal("PLUSONE_RESET", nil, count, nil, byGuid)
        GA.Core.Callbacks:Fire("PLUSONE_CHANGED")
    end
    return count
end

-- ================================================================== Start ------

function PlusOne:OnEnable()
    -- Nichts einzuhaengen: Die Zahl wird bei jedem Abruf gerechnet. Ein
    -- Rueckruf auf AWARD_CHANGED waere genau der gefuehrte Zaehler, den
    -- dieses Modul vermeidet.
end
