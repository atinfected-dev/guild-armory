--[[----------------------------------------------------------------------------
    LootCouncil/Rotation — Council-Sitze auf Zeit, reihum.

    Kein UI. Waehlt zu Beginn eines Raidabends N Schlachtzugsmitglieder aus und
    gibt ihnen einen befristeten Sitz im Council.

    WOZU:

      Ein festes Council entscheidet ueber Loot fuer Leute, die nicht
      mitreden. Das ist organisatorisch bequem und sozial teuer. Ein
      rotierender Sitz kostet nichts und aendert die Wahrnehmung: Jeder war
      schon einmal auf der anderen Seite des Tisches.

    DIE EINE ENTSCHEIDUNG, DIE HIER ZAEHLT:

      Ein Sitz auf Zeit wird NICHT in `roles` geschrieben.

      Die naheliegende Umsetzung waere, kurz die Rolle auf COUNCIL zu setzen
      und am Ende des Abends zurueckzusetzen. Das geht so lange gut, bis das
      Zuruecksetzen ausfaellt — Absturz, Verbindungsabbruch, jemand macht
      /reload mitten im Raid, der Lootmeister loggt aus, bevor er aufraeumt.
      Danach sitzt jemand dauerhaft im Council, und niemand weiss, warum.

      Deshalb liegen Sitze in `rotation` mit einem Ablaufzeitpunkt, und
      Database:HasRotationSeat prueft die Uhr. Aufgeraeumt wird trotzdem, aber
      die Berechtigung haengt nicht am Aufraeumen. Wer nicht aufraeumt,
      verliert den Sitz trotzdem.

    FAIRNESS OHNE ZUFALL:

      Gemischt wird mit math.random, aber die Fairness haengt NICHT daran.
      Sie haengt an `rotationSeen`: Wer in diesem Zyklus schon dran war, ist
      aus dem Topf, bis alle einmal dran waren. Selbst wenn math.random auf
      diesem Client unbesaet waere und jedes Mal dieselbe Reihenfolge lieferte,
      bekaeme trotzdem jeder genau einmal je Zyklus einen Sitz — nur die
      Reihenfolge innerhalb des Zyklus waere vorhersagbar.

      Das ist der Unterschied zwischen "zufaellig" und "gerecht", und nur das
      zweite ist hier zugesagt.
------------------------------------------------------------------------------]]

local _, GA = ...

local Rotation = {}
GA.Modules.Rotation = Rotation

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local L = GA.L

--- Obergrenze fuer den Verlauf.
local LOG_LIMIT = 200

local function db()
    return GA.Core.Database.account
end

local function config(key)
    return GA.Core.Config:Get(key)
end

-- ================================================================== Auswahl ---

--- Wer kommt ueberhaupt in Frage?
---
--- Bedingungen, alle messbar:
---   * im Schlachtzug (nicht in der Gilde — wer nicht dabei ist, kann nicht
---     ueber den Loot des Abends mitentscheiden)
---   * nicht man selbst (der Lootmeister sitzt ohnehin drin)
---   * nicht schon dauerhaft im Council oder darueber
---   * Gildenrang innerhalb der Grenze, falls eine gesetzt ist
---
--- @return table liste { guid, name, class }, table grund [name] = warum nicht
function Rotation:Pool()
    local eligible, rejected = {}, {}
    local own = Compat.GetPlayerIdentity().guid
    local maxRank = config("rotationMaxRankIndex")
    local Database = GA.Core.Database

    for index = 1, Compat.GetNumGroupMembers() do
        local identity = Compat.GetUnitIdentity(Compat.GetGroupUnit(index))
        local name = identity.name

        if not identity.guid or not name then
            -- Nicht in Reichweite oder noch nicht geladen. Kein Grund zur
            -- Beschwerde, aber auch kein Kandidat.
        elseif identity.guid == own then
            rejected[name] = "self"
        elseif Database:HasAtLeast(identity.guid, GA.const.ROLE_COUNCIL) then
            -- Auch ein bereits laufender Sitz faellt hierunter: Niemand bekommt
            -- in derselben Rotation zwei.
            rejected[name] = "already"
        elseif maxRank and (identity.guildRankIndex or 99) > maxRank then
            rejected[name] = "rank"
        else
            eligible[#eligible + 1] = {
                guid = identity.guid, name = name, class = identity.class,
                rankIndex = identity.guildRankIndex,
            }
        end
    end

    return eligible, rejected
end

--- Der Topf ohne die, die in diesem Zyklus schon dran waren.
--- Ist er leer, beginnt ein neuer Zyklus — das ist kein Sonderfall, sondern
--- der normale Abschluss einer Runde.
--- @return table topf, boolean zyklusZurueckgesetzt
function Rotation:Fresh()
    local pool = self:Pool()
    local seen = db().rotationSeen or {}

    local unseen = {}
    for _, entry in ipairs(pool) do
        if not seen[entry.guid] then unseen[#unseen + 1] = entry end
    end

    if #unseen > 0 then return unseen, false end
    if #pool == 0 then return {}, false end

    Util.Wipe(db().rotationSeen)
    Debug:Print("council", "Rotationszyklus abgeschlossen — Topf zurueckgesetzt")
    return pool, true
end

--- Fisher-Yates. Mischt an Ort und Stelle.
local function shuffle(list)
    for index = #list, 2, -1 do
        local other = math.random(index)
        list[index], list[other] = list[other], list[index]
    end
    return list
end

-- ================================================================== Sitze -----

--- Laeuft ueber alle Sitze und entfernt die abgelaufenen.
---
--- Zur Erinnerung: Das ist Hausputz, keine Berechtigungspruefung. Ein
--- abgelaufener Sitz gilt auch dann nicht mehr, wenn das hier nie laeuft.
--- @return number entfernt
function Rotation:Sweep()
    local seats, now, removed = db().rotation, Util.Now(), 0
    for guid, seat in pairs(seats) do
        if (seat.expires or 0) <= now then
            seats[guid] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        GA.Core.Callbacks:Fire("ROLES_CHANGED")
        Debug:Print("council", "%d abgelaufene Sitze entfernt", removed)
    end
    return removed
end

--- Alle laufenden Sitze, neueste zuerst.
function Rotation:Active()
    self:Sweep()
    local out = {}
    for guid, seat in pairs(db().rotation) do
        out[#out + 1] = { guid = guid, name = seat.name, class = seat.class,
                          expires = seat.expires, ts = seat.ts, by = seat.by }
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

--- Beendet alle laufenden Sitze sofort.
function Rotation:ClearAll(byGuid)
    local count = 0
    for guid in pairs(db().rotation) do
        db().rotation[guid] = nil
        count = count + 1
    end
    if count > 0 then
        GA.Core.Database:Journal("ROTATION_CLEAR", nil, count, nil, byGuid)
        GA.Core.Callbacks:Fire("ROLES_CHANGED")
    end
    return count
end

-- ================================================================== Rotieren --

--- Vergibt neue Sitze.
---
--- @param options table|nil { seats, silent }
--- @return boolean ok, string|table grund oder die vergebenen Sitze
function Rotation:Rotate(options)
    options = options or {}

    local identity = Compat.GetPlayerIdentity()
    if not GA.Core.Database:HasAtLeast(identity.guid, GA.const.ROLE_LOOTMASTER) then
        return false, "notallowed"
    end
    if not Compat.IsInGroup() then return false, "nogroup" end

    -- Erst aufraeumen: Sonst zaehlen abgelaufene Sitze noch als "schon im
    -- Council" und verkleinern den Topf ohne Grund.
    self:Sweep()

    local seats = tonumber(options.seats) or tonumber(config("rotationSeats")) or 2
    if seats < 1 then return false, "noseats" end

    local pool, cycled = self:Fresh()
    if #pool == 0 then return false, "nopool" end

    shuffle(pool)

    local hours = tonumber(config("rotationHours")) or 5
    local expires = Util.Now() + hours * 3600
    local chosen = {}

    for index = 1, math.min(seats, #pool) do
        local entry = pool[index]
        db().rotation[entry.guid] = {
            name = entry.name, class = entry.class, expires = expires,
            ts = Util.Now(), by = identity.guid,
        }
        db().rotationSeen[entry.guid] = Util.Now()
        chosen[#chosen + 1] = entry
    end

    local names = {}
    for _, entry in ipairs(chosen) do names[#names + 1] = entry.name end

    local log = db().rotationLog
    log[#log + 1] = { ts = Util.Now(), names = names, by = identity.name,
                      cycled = cycled or nil, expires = expires }
    while #log > LOG_LIMIT do table.remove(log, 1) end

    GA.Core.Database:Journal("ROTATION", nil, nil,
        { names = table.concat(names, ", "), hours = hours }, identity.guid)
    GA.Core.Callbacks:Fire("ROLES_CHANGED")
    GA.Core.Callbacks:Fire("ROTATION_CHANGED")

    if not options.silent and config("rotationAnnounce") then
        self:Announce(chosen, hours)
    end

    Debug:Print("council", "Rotation: %s (%d h)", table.concat(names, ", "), hours)
    return true, chosen
end

--- Sagt Bescheid. Im Schlachtzug einmal, und den Gewaehlten je eine Fluesterzeile.
---
--- Die Fluesterzeile ist der eigentliche Zweck: Wer ploetzlich abstimmen darf,
--- ohne es zu wissen, stimmt nicht ab.
function Rotation:Announce(chosen, hours)
    local names = {}
    for _, entry in ipairs(chosen) do names[#names + 1] = entry.name end
    if #names == 0 then return end

    local channel = Compat.IsInRaid() and "RAID" or "PARTY"
    Compat.SendChatMessage(
        string.format(L.ROTATION_ANNOUNCE, table.concat(names, ", "), hours), channel)

    for _, entry in ipairs(chosen) do
        -- Kurzname als Ziel: entry.name kommt aus GetUnitIdentity und traegt
        -- keine Realm-Endung. Eine angehaengte waere geraten — siehe
        -- Communication/Comm, WhisperTarget.
        Compat.SendChatMessage(string.format(L.ROTATION_WHISPER, hours),
            "WHISPER", Util.ShortName(entry.name))
    end
end

-- ================================================================== Abfrage ---

function Rotation:Log(limit)
    local log, out = db().rotationLog, {}
    for index = #log, math.max(1, #log - (limit or 50) + 1), -1 do
        out[#out + 1] = log[index]
    end
    return out
end

--- Wie weit ist der laufende Zyklus?
--- @return number dran, number gesamt
function Rotation:CycleProgress()
    local pool = self:Pool()
    local seen = db().rotationSeen or {}

    local done, total = 0, #pool
    for _, entry in ipairs(pool) do
        if seen[entry.guid] then done = done + 1 end
    end

    -- Wer schon dauerhaft im Council sitzt, taucht im Topf nicht auf, hat aber
    -- vielleicht einen Vermerk aus einer frueheren Gildenzusammensetzung. Der
    -- Fortschritt zaehlt nur, was jetzt in Frage kaeme.
    return done, total
end

-- ================================================================== Start ------

function Rotation:OnEnable()
    -- Abgelaufene Sitze beim Start wegraeumen. Beim Einloggen ist das der
    -- Normalfall: Der Sitz von gestern Abend ist laengst abgelaufen.
    self:Sweep()

    -- Und danach regelmaessig, damit ein Sitz auch dann aus der Ansicht
    -- verschwindet, wenn niemand etwas anklickt.
    local function tick()
        Rotation:Sweep()
        Compat.After(300, tick)
    end
    Compat.After(300, tick)
end
