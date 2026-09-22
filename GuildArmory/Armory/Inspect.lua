--[[----------------------------------------------------------------------------
    Armory/Inspect — Ausruestung fremder Charaktere per Inspect erfassen.

    Kein UI. Fordert ein Inspect an (NotifyInspect), wartet auf INSPECT_READY
    und liest dann dieselben 19 Plaetze wie beim eigenen Charakter — ueber
    Equipment:ReadEquipment(unit), damit beide Wege identisch rechnen.

    REGELN (Vorgabe Abschnitt 4):
      - Jeder so erfasste Stand traegt source = "inspect" und einen Zeitstempel.
        Die Armory zeigt ihn NIE als aktuell an, sondern mit Alter und Quelle.
      - Nur die eigene Anfrage wird ausgewertet. Oeffnet der Spieler selbst das
        Blizzard-Inspect-Fenster, feuert INSPECT_READY ebenfalls — das wird
        nicht angefasst, sonst wuerde ClearInspectPlayer Blizzards Fenster leeren.
      - Eine Anfrage zur Zeit. Der Server drosselt Inspects; ein zweiter
        NotifyInspect verwirft den ersten.

    Gemessen 19.09.2026: NotifyInspect, CanInspect, ClearInspectPlayer,
    C_Traits.GenerateInspectImportString existieren. Ob letzteres in Forever
    einen String liefert, zeigt der erste echte Inspect — bis dahin bleibt
    character.loadout bei Fremden leer, nicht "?".
------------------------------------------------------------------------------]]

local _, GA = ...

local Inspect = {}
GA.Modules.Inspect = Inspect

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

local TIMEOUT = 8   -- Sekunden ohne INSPECT_READY, dann gilt die Anfrage als verloren

local pending = nil   -- { unit, guid, name, ts }

-- ================================================================== Anfrage ---

--- Kann `unit` gerade inspiziert werden? Liefert den Grund, wenn nicht —
--- als Schluessel fuer L["INSPECT_REASON_" .. reason].
function Inspect:CanRequest(unit)
    if pending then return false, "busy" end
    return Compat.CanInspectUnit(unit)
end

--- Fordert ein Inspect an. Ergebnis kommt asynchron als EQUIPMENT_UPDATED(guid)
--- oder INSPECT_FAILED(name).
--- @return boolean angefordert, string|nil reason
function Inspect:Request(unit)
    local can, reason = self:CanRequest(unit)
    if not can then return false, reason end

    local identity = Compat.GetUnitIdentity(unit)
    if not identity.guid then return false, "notarget" end

    local request = { unit = unit, guid = identity.guid, name = identity.name, ts = Util.Now() }
    if not Compat.RequestInspect(unit) then return false, "range" end
    pending = request

    Debug:Print("inspect", "Angefordert: %s (%s)", tostring(identity.name), unit)
    GA.Core.Callbacks:Fire("INSPECT_REQUESTED", identity.name)

    Compat.After(TIMEOUT, function()
        if pending == request then
            pending = nil
            Debug:Print("inspect", "Keine Antwort fuer %s", tostring(request.name))
            GA.Core.Callbacks:Fire("INSPECT_FAILED", request.name)
        end
    end)
    return true
end

-- ================================================================== Antwort ---

function Inspect:OnReady(guid)
    if not pending then return end
    -- Auch hier kein blosses "~=": Der Wert kommt aus dem Ereignis und kann
    -- verschleiert sein (siehe Compat.SameGUID).
    if guid and not Compat.SameGUID(guid, pending.guid) then return end

    local request = pending
    local unit = request.unit

    -- Das Ziel kann inzwischen gewechselt haben: Nur lesen, wenn die Einheit
    -- noch derselbe Charakter ist.
    --
    -- Compat.SameGUID statt "~=": Ein Vergleich mit einem verschleierten Wert
    -- wirft (gemessen 21.09.2026 in LOOT_READY, dieselbe Bauart). Laesst er
    -- sich nicht durchfuehren, gilt die Einheit als NICHT dieselbe — dann
    -- bricht der Inspect ab, statt fremde Ausruestung unter dem falschen
    -- Namen zu speichern.
    local ok, unitGuid = pcall(_G.UnitGUID, unit)
    if not UnitExists(unit) or not ok or not Compat.SameGUID(unitGuid, request.guid) then
        pending = nil
        Compat.ClearInspect()
        GA.Core.Callbacks:Fire("INSPECT_FAILED", request.name)
        return
    end

    local identity = Compat.GetUnitIdentity(unit)
    local db = GA.Core.Database
    local character = db:GetCharacter(request.guid, identity)

    local equipment, incomplete = GA.Modules.Equipment:ReadEquipment(unit)
    local average, count = Compat.ComputeItemLevel(unit)

    character.equipment = equipment
    character.equipmentTs = Util.Now()
    character.source = "inspect"
    character.itemLevel = { value = average, count = count, ts = Util.Now() }
    character.specID = Compat.GetSpecializationID(unit) or character.specID
    if identity.guildName then
        character.guildName = identity.guildName
        character.guildRank = identity.guildRank
        character.guildRankIndex = identity.guildRankIndex
    end

    local loadout = Compat.GetInspectLoadoutString(unit)
    if loadout then character.loadout = { value = loadout, ts = Util.Now(), source = "inspect" } end

    GA.Modules.Equipment:Snapshot(character, equipment, average)

    pending = nil
    Compat.ClearInspect()

    Debug:Print("inspect", "Erfasst: %s, %d Plaetze, Itemlevel %s%s", tostring(identity.name),
        count, tostring(average), incomplete and " (unvollstaendig)" or "")
    db:Journal("INSPECT", "self", nil, { guid = request.guid, name = identity.name, itemLevel = average })

    GA.Core.Callbacks:Fire("EQUIPMENT_UPDATED", request.guid)
    GA.Core.Callbacks:Fire("INSPECT_DONE", identity.name)
end

function Inspect:IsPending() return pending ~= nil end

-- ================================================================== Start ------

function Inspect:OnEnable()
    local Events = GA.Core.Events

    Events:Register("INSPECT_READY", function(_, guid)
        Inspect:OnReady(guid)
    end, "Inspect")

    -- Die Armory-Ansicht schaltet ihren Inspect-Knopf nach dem Ziel.
    Events:Register("PLAYER_TARGET_CHANGED", function()
        GA.Core.Callbacks:Fire("TARGET_CHANGED")
    end, "Inspect")
end
