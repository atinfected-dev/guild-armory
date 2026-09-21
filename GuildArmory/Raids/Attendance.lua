--[[----------------------------------------------------------------------------
    Raids/Attendance — wer wann wie lange im Raid war.

    Kein UI. Misst die eigene Anwesenheit in Schlachtzugsinstanzen und fuehrt
    daraus Teilnahmen und Stunden.

    ===========================================================================
    WAS UEBERHAUPT ALS RAID ZAEHLT
    ===========================================================================

    Nicht "in einer Schlachtzugsgruppe". Wer mit vierzig Leuten in Orgrimmar
    steht, raidet nicht. Gezaehlt wird die Zeit IN EINER
    SCHLACHTZUGSINSTANZ — das ist messbar (GetInstanceInfo liefert "raid")
    und deckt sich mit dem, was jemand meint, wenn er sagt, er sei dabei
    gewesen.

    Das schliesst bewusst mit ein: Wer zehn Minuten vor Schluss dazukommt,
    war dabei. Und es schliesst aus: Wer beim Sammeln in der Stadt wartet,
    war noch nicht dabei. Beides ist Absicht, und beides ist diskutierbar —
    deshalb steht es hier und nicht nur im Code.

    ===========================================================================
    DIE ENTSCHEIDUNG, DIE DIE ZAHLEN EHRLICH HAELT
    ===========================================================================

    ZEIT WIRD IN ABSCHNITTEN GEMESSEN, NICHT IN EINEM LAUFENDEN ZAEHLER.

    Ein Zaehler, der hochlaeuft, ueberlebt keinen Absturz: Beim naechsten
    Start steht dort eine Zahl, und niemand weiss mehr, ob sie stimmt. Hier
    wird stattdessen ein Abschnitt mit Anfang geoeffnet und beim Verlassen
    geschlossen.

    Bleibt ein Abschnitt offen (Absturz, Stromausfall), wird er beim naechsten
    Start NICHT bis jetzt weitergerechnet — sonst werden aus einem Absturz am
    Mittwoch zwei Tage Raidzeit. Er wird auf MAX_BLOCK gekappt und als
    unvollstaendig gekennzeichnet. Lieber zu wenig als erfunden.

    ===========================================================================
    WAS EINE TEILNAHME IST
    ===========================================================================

    Ein Aufenthalt ab MIN_ATTENDANCE. Kurz hineinzuzonen und wieder zu gehen
    ist keine Teilnahme — aber wo die Grenze liegt, ist eine Setzung und kein
    Messwert. Sie steht als benannte Zahl da, damit sie diskutierbar bleibt
    statt irgendwo im Code zu verschwinden.
------------------------------------------------------------------------------]]

local _, GA = ...

local Attendance = {}
GA.Modules.Attendance = Attendance

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Ab wann ein Aufenthalt als Teilnahme gilt. Setzung, kein Messwert.
local MIN_ATTENDANCE = 5 * 60

--- Obergrenze fuer einen einzelnen Abschnitt. Laenger als zwoelf Stunden am
--- Stueck ist kein Raid, sondern ein offengebliebener Abschnitt.
local MAX_BLOCK = 12 * 3600

--- Wie oft nachgesehen wird, ob sich die Zone geaendert hat. Die Ereignisse
--- fuer Zonenwechsel sind auf Forever ungemessen; ein ruhiger Takt daneben
--- kostet nichts und faengt auch das, was kein Ereignis ausloest.
local POLL = 60

--- Aufenthalte unter dieser Laenge werden gar nicht erst aufbewahrt.
local MIN_BLOCK = 30

local function db()
    local account = GA.Core.Database.account
    account.raidBlocks = account.raidBlocks or {}
    return account
end

-- ================================================================== Messen ---

--- Bin ich gerade in einer Schlachtzugsinstanz?
--- @return boolean, table instanz
function Attendance:InRaid()
    local instance = Compat.GetInstance()
    return instance.inside and instance.kind == "raid", instance
end

--- Oeffnet einen Abschnitt, wenn noch keiner laeuft.
function Attendance:Open(instance)
    local account = db()
    if account.raidOpen then return false end

    account.raidOpen = {
        start = Util.Now(),
        name = instance and instance.name,
        difficultyID = instance and instance.difficultyID,
        character = Compat.GetPlayerIdentity().name,
    }
    Debug:Print("core", "Raid betreten: %s", tostring(account.raidOpen.name))
    GA.Core.Callbacks:Fire("RAID_ATTENDANCE_CHANGED")
    return true
end

--- Schliesst den laufenden Abschnitt.
---
--- @param reason string|nil  "left" | "recovered"
--- @return table|nil abschnitt
function Attendance:Close(reason)
    local account = db()
    local open = account.raidOpen
    if not open then return nil end

    account.raidOpen = nil

    local duration = Util.Now() - (open.start or Util.Now())
    local capped = false

    -- OFFEN GEBLIEBEN heisst NICHT "so lange dabei gewesen". Ein Absturz am
    -- Mittwoch darf am Freitag keine 48 Raidstunden ergeben.
    if duration > MAX_BLOCK then
        duration = MAX_BLOCK
        capped = true
    end

    if duration < MIN_BLOCK then return nil end

    local block = {
        start = open.start,
        stop = open.start + duration,
        seconds = duration,
        name = open.name,
        difficultyID = open.difficultyID,
        character = open.character,
        -- Ein gekappter oder wiederhergestellter Abschnitt traegt das mit:
        -- Die Summe soll sagen koennen, wie belastbar sie ist.
        capped = capped or nil,
        recovered = reason == "recovered" or nil,
    }

    local blocks = account.raidBlocks
    blocks[#blocks + 1] = block

    Debug:Print("core", "Raid verlassen: %s, %d Minuten%s",
        tostring(block.name), math.floor(duration / 60), capped and " (gekappt)" or "")
    GA.Core.Callbacks:Fire("RAID_ATTENDANCE_CHANGED")
    return block
end

--- Sieht nach, ob sich der Zustand geaendert hat.
function Attendance:Poll()
    local inRaid, instance = self:InRaid()
    local open = db().raidOpen

    if inRaid and not open then
        self:Open(instance)
    elseif not inRaid and open then
        self:Close("left")
    elseif inRaid and open and instance.name and open.name ~= instance.name then
        -- Instanzwechsel: Der alte Abschnitt endet, ein neuer beginnt. Sonst
        -- stuende am Ende eine Zeit unter dem falschen Raid.
        self:Close("left")
        self:Open(instance)
    end
end

-- ================================================================== Abfrage --

--- Alle abgeschlossenen Abschnitte, optional gefiltert.
function Attendance:Blocks(filter)
    filter = filter or {}
    local out = {}
    for _, block in ipairs(db().raidBlocks) do
        local keep = true
        if filter.since and (block.start or 0) < filter.since then keep = false end
        if filter.name and block.name ~= filter.name then keep = false end
        if keep then out[#out + 1] = block end
    end
    return out
end

--- Summe in Sekunden.
---
--- Der laufende Abschnitt zaehlt MIT, aber nur bis jetzt: Wer gerade drin
--- sitzt, soll seine Stunden wachsen sehen, ohne dass dafuer etwas
--- gespeichert werden muesste.
function Attendance:Seconds(filter)
    local total = 0
    for _, block in ipairs(self:Blocks(filter)) do
        total = total + (block.seconds or 0)
    end

    local open = db().raidOpen
    if open and not (filter and filter.closedOnly) then
        total = total + math.min(Util.Now() - (open.start or Util.Now()), MAX_BLOCK)
    end
    return total
end

function Attendance:Hours(filter)
    return self:Seconds(filter) / 3600
end

--- Teilnahmen: Abschnitte ab MIN_ATTENDANCE, je RAIDABEND einmal gezaehlt.
---
--- Wer zwischendurch herausfliegt und wieder hereinkommt, war einmal dabei
--- und nicht zweimal. Zusammengefasst wird nach Kalendertag und Instanz —
--- gemessen am Anfang des Abschnitts.
function Attendance:Count(filter)
    local seen, count = {}, 0

    for _, block in ipairs(self:Blocks(filter)) do
        if (block.seconds or 0) >= MIN_ATTENDANCE then
            local day = math.floor((block.start or 0) / 86400)
            local key = day .. "/" .. tostring(block.name or "?")
            if not seen[key] then
                seen[key] = true
                count = count + 1
            end
        end
    end
    return count
end

function Attendance:Stats()
    local blocks = self:Blocks()
    local capped, recovered = 0, 0
    for _, block in ipairs(blocks) do
        if block.capped then capped = capped + 1 end
        if block.recovered then recovered = recovered + 1 end
    end

    return {
        blocks = #blocks,
        attendances = self:Count(),
        hours = self:Hours(),
        capped = capped,
        recovered = recovered,
        open = db().raidOpen ~= nil,
        since = GA.Core.Database.account.achievementsSince,
    }
end

-- ================================================================== Start ------

function Attendance:OnEnable()
    -- EIN OFFENER ABSCHNITT AUS DER LETZTEN SITZUNG wird zuerst
    -- abgeschlossen, nicht fortgesetzt. Fortsetzen hiesse, die Zeit
    -- dazwischen mitzuzaehlen — und dazwischen lag das Abmelden.
    local open = db().raidOpen
    if open then
        Debug:Print("core", "Offener Raidabschnitt gefunden, wird abgeschlossen")
        self:Close("recovered")
    end

    GA.Core.Events:Register("PLAYER_ENTERING_WORLD", function()
        Compat.After(3, function() Attendance:Poll() end)
    end, "Attendance")

    GA.Core.Events:Register("ZONE_CHANGED_NEW_AREA", function()
        Compat.After(2, function() Attendance:Poll() end)
    end, "Attendance")

    -- Beim Abmelden sauber schliessen, damit der naechste Start keinen
    -- offenen Abschnitt kappen muss.
    GA.Core.Events:Register("PLAYER_LOGOUT", function()
        Attendance:Close("left")
    end, "Attendance")

    local function tick()
        Attendance:Poll()
        Compat.After(POLL, tick)
    end
    Compat.After(POLL, tick)
end
