--[[----------------------------------------------------------------------------
    Armory/GuildHistory — wer kam, wer ging, wer wurde befoerdert.

    Kein UI. Vergleicht das Gildenroster gegen den letzten bekannten Stand und
    schreibt die Unterschiede mit.

    WOZU DAS IN EINEM LOOT-ADDON:

      Bei einer Vergabe ist "seit wann ist der dabei" eine Frage, die im
      Council tatsaechlich gestellt wird. Das Gildenroster beantwortet sie
      nicht — es zeigt nur den Jetzt-Zustand. Wer letzte Woche eingetreten ist,
      sieht darin genauso aus wie jemand seit drei Jahren.

    WAS HIER NICHT PASSIERT — und das ist die wichtigste Regel:

      Ein Eintrittsdatum wird NICHT erfunden. Das Addon kennt nur den Moment,
      in dem es jemanden ZUM ERSTEN MAL im Roster gesehen hat. Bei einer
      frischen Installation ist das fuer alle derselbe Tag, und dann steht
      genau das da: "seit der ersten Erfassung bekannt", nicht "beigetreten am".

      Erst wenn jemand waehrend der Laufzeit NEU auftaucht, ist der Beitritt
      beobachtet — und nur dann wird er als solcher gefuehrt.

    Die Unterscheidung klingt spitzfindig, entscheidet aber, ob eine Zahl in
    einer Lootdiskussion etwas wert ist.
------------------------------------------------------------------------------]]

local _, GA = ...

local GuildHistory = {}
GA.Modules.GuildHistory = GuildHistory

local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Ereignisarten.
GuildHistory.JOINED   = "JOINED"
GuildHistory.LEFT     = "LEFT"
GuildHistory.PROMOTED = "PROMOTED"
GuildHistory.DEMOTED  = "DEMOTED"

--- Obergrenze. Aelteres faellt heraus — mit einem Vermerk, damit niemand
--- glaubt, die Liste sei vollstaendig.
local LIMIT = 1000

--- Ab wann ein Schwund als "vermutlich Lesefehler" gilt. Beide Bedingungen
--- muessen zutreffen: Bei einer Gilde mit vier Leuten sind drei Austritte
--- keine Auffaelligkeit, bei einer mit sechzig schon.
local MASS_SHRINK_MIN = 5
local MASS_SHRINK_SHARE = 0.5

local function store()
    local db = GA.Core.Database.account
    db.guildLog = db.guildLog or {}
    return db.guildLog
end

-- ================================================================== Schreiben

function GuildHistory:Add(kind, member, detail)
    local log = store()

    log[#log + 1] = {
        ts = Util.Now(),
        kind = kind,
        name = Util.ShortName(member.name or "?"),
        fullName = member.fullName or member.name,
        class = member.class,
        rank = member.rankName,
        detail = detail,
    }

    while #log > LIMIT do
        table.remove(log, 1)
        GA.Core.Database.account.guildLogTruncated = true
    end

    GA.Core.Callbacks:Fire("GUILD_HISTORY", kind)
    return log[#log]
end

--- Vergleicht den neuen Rosterstand gegen den letzten und schreibt die
--- Unterschiede mit.
---
--- @param members table  [key] = Eintrag, wie Armory/Guild ihn fuehrt
--- @param firstRun boolean  true beim allerersten Durchlauf
--- @return number anzahl neuer Eintraege
function GuildHistory:Diff(members, firstRun)
    local db = GA.Core.Database.account
    local previous = db.guildSeen or {}
    local current = {}

    -- Erst sammeln, dann schreiben. Wer waehrend des Sammelns schon Eintraege
    -- anlegt, kann nicht mehr entscheiden, die ganze Lesung zu verwerfen.
    local joined, ranked, left = {}, {}, {}
    local previousCount = 0
    for _ in pairs(previous) do previousCount = previousCount + 1 end

    for key, member in pairs(members) do
        current[key] = { rankIndex = member.rankIndex, rankName = member.rankName,
                         name = member.name, class = member.class }

        local before = previous[key]
        if not before then
            -- BEIM ERSTEN DURCHLAUF ist das kein Beitritt, sondern der
            -- Anfangsbestand. Alles andere waere erfunden.
            if not firstRun then joined[#joined + 1] = member end
        elseif before.rankIndex ~= member.rankIndex and member.rankIndex then
            ranked[#ranked + 1] = { member = member, before = before }
        end
    end

    if not firstRun then
        for key, before in pairs(previous) do
            if not current[key] then left[#left + 1] = { key = key, before = before } end
        end
    end

    -- EIN MASSENSCHWUND IST WAHRSCHEINLICHER EIN LESEFEHLER ALS EINE
    -- GILDENSPALTUNG.
    --
    -- Verschwindet auf einen Schlag ein Grossteil des Rosters, gibt es zwei
    -- Erklaerungen: Es sind wirklich alle ausgetreten, oder der Client hat
    -- gerade ein Teilroster geliefert. Von hier aus ist das nicht zu
    -- unterscheiden — also wird es NICHT entschieden, sondern abgewartet.
    --
    -- Ein Teilroster ist im naechsten GUILD_ROSTER_UPDATE wieder vollstaendig;
    -- ein echter Austritt ist es nicht. Wer beim zweiten Mal immer noch fehlt,
    -- ist weg. Das kostet eine Rosteraktualisierung Verzoegerung und spart
    -- zwanzig erfundene Austritte.
    local massShrink = #left > MASS_SHRINK_MIN
        and #left > previousCount * MASS_SHRINK_SHARE

    if massShrink then
        local pending = db.guildShrinkPending or {}
        local stillPending, confirmed = {}, 0
        for _, entry in ipairs(left) do
            stillPending[entry.key] = true
            if pending[entry.key] then confirmed = confirmed + 1 end
        end

        if confirmed == 0 then
            -- Erste Lesung. Nichts behaupten, nichts loeschen, nur merken.
            db.guildShrinkPending = stillPending
            Debug:Warn("Roster um %d von %d geschrumpft — wird erst bei der " ..
                       "naechsten Aktualisierung als Austritt gewertet.",
                       #left, previousCount)
            return 0
        end
    end
    db.guildShrinkPending = nil

    local added = 0
    for _, member in ipairs(joined) do
        self:Add(self.JOINED, member)
        added = added + 1
    end
    for _, entry in ipairs(ranked) do
        -- Kleinerer Index = hoeherer Rang.
        local kind = (entry.member.rankIndex < (entry.before.rankIndex or 99))
            and self.PROMOTED or self.DEMOTED
        self:Add(kind, entry.member, entry.before.rankName)
        added = added + 1
    end
    -- Wer nicht mehr da ist, hat die Gilde verlassen (oder wurde entfernt —
    -- das laesst sich von aussen nicht unterscheiden, und deshalb heisst der
    -- Eintrag "nicht mehr im Roster" und nicht "gekuendigt").
    for _, entry in ipairs(left) do
        self:Add(self.LEFT, { name = entry.before.name, class = entry.before.class,
                              rankName = entry.before.rankName })
        added = added + 1
    end

    db.guildSeen = current
    if firstRun then db.guildSeenSince = Util.Now() end

    if added > 0 then
        Debug:Print("guild", "Rosteraenderungen: %d", added)
    end
    return added
end

-- ================================================================== Lesen ----

--- @param filter table|nil { kind, name, since }
function GuildHistory:List(filter)
    filter = filter or {}
    local out = {}

    for index = #store(), 1, -1 do
        local entry = store()[index]
        local keep = true
        if filter.kind and entry.kind ~= filter.kind then keep = false end
        if filter.since and (entry.ts or 0) < filter.since then keep = false end
        if filter.name and not string.find(string.lower(entry.name or ""),
            string.lower(filter.name), 1, true) then keep = false end
        if keep then out[#out + 1] = entry end
    end
    return out
end

--- Wie lange ist dieser Charakter bekannt — und ist das ein beobachteter
--- Beitritt oder nur der Anfangsbestand?
--- @return number|nil zeitstempel, boolean beobachtet
function GuildHistory:KnownSince(name)
    if not name then return nil, false end
    local wanted = Util.ShortName(name)

    -- Ein beobachteter Beitritt ist die bessere Antwort — und zwar der
    -- JUENGSTE. Wer ausgetreten und wiedergekommen ist, ist seit dem zweiten
    -- Eintritt dabei; der erste beantwortet die Frage, die im Council
    -- gestellt wird ("seit wann ist der dabei"), nachweislich falsch.
    -- Deshalb rueckwaerts durch die Liste.
    local log = store()
    for index = #log, 1, -1 do
        local entry = log[index]
        if entry.kind == self.JOINED and entry.name == wanted then
            return entry.ts, true
        end
    end

    -- Sonst: seit wann das Addon die Gilde ueberhaupt kennt. Das ist KEIN
    -- Beitrittsdatum, und die Oberflaeche beschriftet es auch nicht so.
    return GA.Core.Database.account.guildSeenSince, false
end

function GuildHistory:Stats()
    local counts = { JOINED = 0, LEFT = 0, PROMOTED = 0, DEMOTED = 0 }
    for _, entry in ipairs(store()) do
        counts[entry.kind] = (counts[entry.kind] or 0) + 1
    end
    counts.total = #store()
    counts.since = GA.Core.Database.account.guildSeenSince
    counts.truncated = GA.Core.Database.account.guildLogTruncated and true or false
    return counts
end

-- ================================================================== Start ------

function GuildHistory:OnEnable()
    GA.Core.Callbacks:On("GUILD_UPDATED", function(partial)
        local members = GA.Core.Database.account.guild.members
        if not members or next(members) == nil then return end

        -- Armory/Guild hat gemessen, dass es weniger lesen konnte als die
        -- Gilde Mitglieder hat. Aus einem halben Roster laesst sich keine
        -- Veraenderung ableiten — auch keine Beitritte, denn wer fehlt,
        -- fehlt nur in dieser Lesung.
        if partial then return end

        local firstRun = GA.Core.Database.account.guildSeen == nil
        GuildHistory:Diff(members, firstRun)
    end, "GuildHistory")
end
