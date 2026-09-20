--[[----------------------------------------------------------------------------
    LootCouncil/Rolls — Wuerfeln als Verteilweg.

    Kein UI. Oeffnet ein Wurffenster zu einem Gegenstand, sammelt die
    Systemmeldungen des Servers ein und stellt sie sortiert bereit.

    WOZU IN EINEM COUNCIL-ADDON:

      Auch Gilden mit Council wuerfeln — um Zweitausruestung, um Abfall, um
      alles, wofuer eine Abstimmung zu viel Aufwand waere. Das passiert heute
      im Chat, und wer den Ueberblick behalten will, liest dreissig Zeilen
      rueckwaerts. Ein Wurf, den niemand mitgeschrieben hat, ist am naechsten
      Tag nicht mehr nachvollziehbar.

    DIE EINE EIGENSCHAFT, AUF DER DAS BERUHT:

      DER WURF KOMMT VOM SERVER.

      CHAT_MSG_SYSTEM traegt Name, Ergebnis und Spanne so, wie der Server sie
      geschickt hat. Kein Addon kann das faelschen — es ist dieselbe
      Eigenschaft wie beim Absendernamen einer Addon-Nachricht (siehe
      Communication/Sync). Wuerfeln ist deshalb ueberhaupt erst ein
      brauchbarer Verteilweg.

      Was der Server NICHT garantiert: dass jemand mit der richtigen Spanne
      wuerfelt. /roll 1-50 sieht in derselben Zeile aus wie /roll 1-100.
      Deshalb wird die Spanne mitgelesen und geprueft, statt nur die Zahl zu
      nehmen (Regel 3 unten).

    VIER REGELN, DIE DAS FENSTER DURCHSETZT:

      1. Nur waehrend das Fenster offen ist. Ein Wurf von vorhin zaehlt nicht.
      2. Nur aus der eigenen Gruppe. Wer nicht dabei ist, wuerfelt nicht mit.
      3. Nur mit der angekuendigten Spanne. Ein 1-50-Wurf ist mit einem
         1-100-Wurf nicht vergleichbar — er wird erfasst und als ungueltig
         gekennzeichnet, nicht stillschweigend gewertet.
      4. Der ERSTE Wurf zaehlt. Ein zweiter wird vermerkt, nicht ersetzt.
         Sonst wuerfelt man, bis es passt.

    WAS DAS ADDON NICHT TUT:

      Bei Gleichstand keinen Gewinner bestimmen. Es sagt, dass es einen
      Gleichstand gibt — wie damit umzugehen ist, entscheidet der Raid, und
      ein stillschweigend gewaehlter Erster waere eine Entscheidung, die
      niemand getroffen hat.
------------------------------------------------------------------------------]]

local _, GA = ...

local Rolls = {}
GA.Modules.Rolls = Rolls

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Standardspanne und Standarddauer.
local DEFAULT_MIN, DEFAULT_MAX = 1, 100
local DEFAULT_SECONDS = 30

--- Wie viele abgeschlossene Wurfrunden aufgehoben werden.
local HISTORY_LIMIT = 50

--- Die laufende Runde, oder nil.
Rolls.current = nil

-- ================================================================== Oeffnen --

--- @param options table|nil { itemID, itemName, itemLink, awardId, min, max, seconds, note }
--- @return boolean ok, string|table grund oder die Runde
function Rolls:Open(options)
    options = options or {}
    if self.current then return false, "running" end
    if not Compat.IsInGroup() then return false, "nogroup" end

    local min = tonumber(options.min) or DEFAULT_MIN
    local max = tonumber(options.max) or DEFAULT_MAX
    if min >= max then return false, "range" end

    local seconds = tonumber(options.seconds) or DEFAULT_SECONDS

    self.current = {
        id = Util.NewId("r"),
        startedTs = Util.Now(),
        endsTs = Util.Now() + seconds,
        seconds = seconds,
        min = min,
        max = max,
        itemID = options.itemID,
        itemName = options.itemName,
        itemLink = options.itemLink,
        awardId = options.awardId,
        note = options.note,
        openedBy = Compat.GetPlayerIdentity().name,
        rolls = {},       -- [normalisierterName] = Eintrag
        extra = {},       -- Zweitwuerfe und ungueltige Spannen, in Reihenfolge
    }

    GA.Core.Callbacks:Fire("ROLLS_CHANGED")
    Compat.After(seconds, function()
        -- Nur schliessen, wenn es noch DIESE Runde ist: Wer zwischendurch
        -- von Hand geschlossen und neu geoeffnet hat, soll die neue behalten.
        if Rolls.current and Rolls.current.endsTs <= Util.Now() then
            Rolls:Close("Zeit abgelaufen")
        end
    end)

    Debug:Print("council", "Wurfrunde offen: %s (%d-%d, %ds)",
        tostring(options.itemName or options.itemID or "?"), min, max, seconds)
    return true, self.current
end

--- Sagt der Gruppe Bescheid. Ohne Ansage wuerfelt niemand.
function Rolls:Announce()
    local round = self.current
    if not round then return false end

    local channel = Compat.IsInRaid() and "RAID" or "PARTY"
    local what = round.itemLink or round.itemName or ("Gegenstand " .. tostring(round.itemID))
    Compat.SendChatMessage(
        string.format(GA.L.ROLL_ANNOUNCE, what, round.min, round.max, round.seconds), channel)
    if round.note and round.note ~= "" then
        Compat.SendChatMessage(round.note, channel)
    end
    return true
end

-- ================================================================== Empfang --

local function inGroup(name)
    local wanted = Util.NormalizeName(name)
    for index = 1, Compat.GetNumGroupMembers() do
        local identity = Compat.GetUnitIdentity(Compat.GetGroupUnit(index))
        if identity.name and Util.NormalizeName(identity.name) == wanted then
            return true, identity
        end
    end
    return false
end

--- Eine Systemzeile. Liefert den Eintrag, wenn sie ein gewerteter Wurf war.
--- @return table|nil eintrag, string|nil grund der Ablehnung
function Rolls:OnSystemMessage(message)
    local round = self.current
    if not round then return nil, "closed" end

    local name, roll, min, max = Compat.ParseRoll(message)
    if not name or not roll then return nil, "nomatch" end

    -- Regel 1: Nur im offenen Fenster.
    if Util.Now() > round.endsTs then return nil, "late" end

    -- Regel 2: Nur aus der Gruppe.
    local isMember, identity = inGroup(name)
    if not isMember then return nil, "outside" end

    local key = Util.NormalizeName(name)
    local entry = {
        name = Util.ShortName(name),
        guid = identity and identity.guid,
        class = identity and identity.class,
        roll = roll,
        min = min,
        max = max,
        ts = Util.Now(),
    }

    -- Regel 3: Nur mit der angekuendigten Spanne. Erfasst, aber nicht gewertet
    -- — sonst waere ein 1-50-Wurf ein schlechter 1-100-Wurf, und das ist er
    -- nicht: Er ist gar keiner.
    if min ~= round.min or max ~= round.max then
        entry.invalid = "range"
        round.extra[#round.extra + 1] = entry
        GA.Core.Callbacks:Fire("ROLLS_CHANGED")
        return nil, "range"
    end

    -- Regel 4: Der erste Wurf zaehlt.
    if round.rolls[key] then
        entry.invalid = "second"
        round.extra[#round.extra + 1] = entry
        GA.Core.Callbacks:Fire("ROLLS_CHANGED")
        return nil, "second"
    end

    round.rolls[key] = entry
    GA.Core.Callbacks:Fire("ROLLS_CHANGED")
    return entry
end

-- ================================================================== Ergebnis -

--- Die gewerteten Wuerfe, hoechster zuerst.
--- @param round table|nil  Standard: die laufende Runde
function Rolls:Results(round)
    round = round or self.current
    if not round then return {} end

    local list = {}
    for _, entry in pairs(round.rolls) do list[#list + 1] = entry end

    -- Bei gleichem Wurf der frueheren zuerst — das ist KEINE Entscheidung
    -- ueber den Gewinner, nur eine stabile Reihenfolge fuer die Anzeige.
    table.sort(list, function(a, b)
        if a.roll ~= b.roll then return a.roll > b.roll end
        return (a.ts or 0) < (b.ts or 0)
    end)
    return list
end

--- Gibt es einen eindeutigen Hoechsten?
--- @return table|nil gewinner, table gleichstand
function Rolls:Winner(round)
    local list = self:Results(round)
    if #list == 0 then return nil, {} end

    local best = list[1].roll
    local tied = {}
    for _, entry in ipairs(list) do
        if entry.roll == best then tied[#tied + 1] = entry end
    end

    -- Bei Gleichstand wird NICHT gewaehlt. Der Raid entscheidet, wie es
    -- weitergeht; ein stillschweigend gewaehlter Erster waere eine
    -- Entscheidung, die niemand getroffen hat.
    if #tied > 1 then return nil, tied end
    return list[1], {}
end

--- Wer aus der Gruppe hat nicht gewuerfelt?
function Rolls:Missing(round)
    round = round or self.current
    if not round then return {} end

    local out = {}
    for index = 1, Compat.GetNumGroupMembers() do
        local identity = Compat.GetUnitIdentity(Compat.GetGroupUnit(index))
        local key = identity.name and Util.NormalizeName(identity.name)
        if key and not round.rolls[key] then
            out[#out + 1] = { name = Util.ShortName(identity.name), class = identity.class }
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

-- ================================================================== Schliessen

function Rolls:Close(reason)
    local round = self.current
    if not round then return false end

    round.closedTs = Util.Now()
    round.closedReason = reason
    round.result = self:Results(round)

    local db = GA.Core.Database.account
    db.rollLog = db.rollLog or {}
    db.rollLog[#db.rollLog + 1] = {
        id = round.id,
        ts = round.startedTs,
        itemID = round.itemID,
        itemName = round.itemName,
        min = round.min,
        max = round.max,
        openedBy = round.openedBy,
        reason = reason,
        rolls = round.result,
        extra = round.extra,
    }
    while #db.rollLog > HISTORY_LIMIT do table.remove(db.rollLog, 1) end

    self.current = nil
    GA.Core.Callbacks:Fire("ROLLS_CHANGED")
    Debug:Print("council", "Wurfrunde beendet (%s), %d Wuerfe",
        tostring(reason), #round.result)
    return true, round
end

function Rolls:History(limit)
    local log = (GA.Core.Database.account.rollLog) or {}
    local out = {}
    for index = #log, math.max(1, #log - (limit or 20) + 1), -1 do
        out[#out + 1] = log[index]
    end
    return out
end

-- ================================================================== Start ------

function Rolls:OnEnable()
    GA.Core.Events:Register("CHAT_MSG_SYSTEM", function(_, message)
        Rolls:OnSystemMessage(message)
    end, "Rolls")
end
