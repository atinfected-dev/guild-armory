--[[----------------------------------------------------------------------------
    Communication/VersionCheck — wer laeuft mit, und in welcher Fassung.

    Kein UI, kein eigenes Protokoll. HELLO und HERE aus Communication/Sync
    tragen Addonfassung und Protokollfassung bereits mit sich; hier wird nur
    gefragt, gewartet und gegenuebergestellt.

    WOZU:

      Nach Phase 7 steht die Frage im Raum, ob der Abgleich ueberhaupt
      stattfindet. "Es kommen keine Daten" hat drei voellig verschiedene
      Ursachen — niemand hat das Addon, alle haben eine zu alte Fassung, oder
      die Nachrichten gehen verloren — und ohne diese Uebersicht sind sie
      nicht auseinanderzuhalten.

    DIE EINE REGEL, DIE HIER ZAEHLT:

      KEINE ANTWORT HEISST NICHT "HAT DAS ADDON NICHT".

      Es heisst: keine Antwort. Der Spieler kann offline gegangen sein, die
      Nachricht kann in der Drosselung liegen, der Kanal kann sie verschluckt
      haben, das Addon kann geladen sein und trotzdem noch nicht geantwortet
      haben. Ein Addon, das daraus "hat es nicht" macht, produziert
      Anschuldigungen statt Messwerte — und im Raidchat wird daraus dann
      "installier endlich das Addon".

      Deshalb heisst der Zustand hier `silent` und nicht `missing`, und die
      Oberflaeche beschriftet ihn als "keine Antwort".

    Die Frist ist ebenfalls eine Aussage: Wer nach WINDOW Sekunden nichts
    gesagt hat, gilt als still — nicht laenger, sonst wartet man ewig; nicht
    kuerzer, sonst faellt die Drosselung ins Ergebnis.
------------------------------------------------------------------------------]]

local _, GA = ...

local VersionCheck = {}
GA.Modules.VersionCheck = VersionCheck

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- So lange wird auf Antworten gewartet. Die Warteschlange in Comm schickt
--- fuenf Nachrichten je Sekunde; bei 40 Leuten sind die Antworten nach
--- spaetestens acht Sekunden durch, wenn alle antworten.
local WINDOW = 10

VersionCheck.running = false
VersionCheck.startedTs = nil

-- ================================================================== Vergleich -

--- Zerlegt "1.2.10" in vergleichbare Zahlen. Unbekanntes wird nicht geraten.
--- @return table|nil
local function parseVersion(text)
    if type(text) ~= "string" then return nil end
    local parts = {}
    for number in string.gmatch(text, "%d+") do
        parts[#parts + 1] = tonumber(number)
    end
    if #parts == 0 then return nil end
    return parts
end

--- @return number -1 aelter, 0 gleich, 1 neuer, nil nicht vergleichbar
local function compareVersion(a, b)
    local left, right = parseVersion(a), parseVersion(b)
    if not left or not right then return nil end

    for index = 1, math.max(#left, #right) do
        local x, y = left[index] or 0, right[index] or 0
        if x < y then return -1 end
        if x > y then return 1 end
    end
    return 0
end

VersionCheck.Compare = compareVersion

-- ================================================================== Abfrage ---

--- Fragt in die Runde. Die Antworten laufen ueber Sync (HELLO -> HERE) und
--- landen in Sync.peers; hier wird nur der Anfang der Frist gemerkt.
--- @param scope string|nil "GROUP" (Standard, falls in einer Gruppe) oder "GUILD"
function VersionCheck:Start(scope)
    local Sync = GA.Modules.Sync
    if not Sync or not GA.Core.Comm then return false, "nocomm" end

    -- Der bisherige Stand wird NICHT geloescht. Wer beim letzten Mal
    -- geantwortet hat und jetzt nicht, ist dadurch als "seit wann still"
    -- erkennbar — das loeschen wuerde die Information wegwerfen.
    self.running = true
    self.startedTs = Util.Now()

    local channel = scope
    if not channel then
        channel = Compat.IsInGroup() and (Compat.IsInRaid() and "RAID" or "PARTY") or "GUILD"
    elseif channel == "GROUP" then
        channel = Compat.IsInRaid() and "RAID" or "PARTY"
    end

    Sync:Hello(channel)

    Compat.After(WINDOW, function()
        VersionCheck.running = false
        GA.Core.Callbacks:Fire("VERSION_CHECK_DONE")
    end)

    GA.Core.Callbacks:Fire("VERSION_CHECK_STARTED")
    Debug:Print("comm", "Versionsabfrage an %s", channel)
    return true, channel
end

--- Ist die Frist abgelaufen?
function VersionCheck:Elapsed()
    if not self.startedTs then return false end
    return (Util.Now() - self.startedTs) >= WINDOW
end

-- ================================================================== Ergebnis --

--- Zustaende. `silent` ist bewusst nicht `missing` — siehe Dateikopf.
VersionCheck.CURRENT  = "current"
VersionCheck.OUTDATED = "outdated"
VersionCheck.NEWER    = "newer"
VersionCheck.UNKNOWN  = "unknown"   -- geantwortet, aber Fassung unlesbar
VersionCheck.SILENT   = "silent"    -- nichts gehoert

--- Wen fragen wir ueberhaupt ab? Die Gruppe, wenn es eine gibt, sonst die
--- online stehenden Gildenmitglieder.
--- @return table [name] = { name, class }
local function audience()
    local out = {}

    if Compat.IsInGroup() then
        for index = 1, Compat.GetNumGroupMembers() do
            local identity = Compat.GetUnitIdentity(Compat.GetGroupUnit(index))
            if identity.name then
                out[Util.NormalizeName(identity.name)] =
                    { name = identity.name, class = identity.class }
            end
        end
        return out
    end

    for _, member in pairs(GA.Core.Database.account.guild.members or {}) do
        if member.online and member.name then
            out[Util.NormalizeName(member.name)] =
                { name = member.name, class = member.class }
        end
    end
    return out
end

--- Die Gegenueberstellung.
--- @return table liste, table zaehler
function VersionCheck:Result()
    local Sync = GA.Modules.Sync
    local peers = (Sync and Sync.peers) or {}
    local own = GA.version
    local ownName = Util.NormalizeName(Compat.GetPlayerIdentity().name or "")

    local list = {}
    local counts = { current = 0, outdated = 0, newer = 0, unknown = 0, silent = 0 }

    for key, entry in pairs(audience()) do
        local status, version, protocol

        if key == ownName then
            status, version, protocol = self.CURRENT, own, Sync and Sync.VERSION
        else
            local peer = peers[key]
            if not peer then
                status = self.SILENT
            else
                version, protocol = peer.addon, peer.version
                local order = compareVersion(version, own)
                if order == nil then status = self.UNKNOWN
                elseif order < 0 then status = self.OUTDATED
                elseif order > 0 then status = self.NEWER
                else status = self.CURRENT end
            end
        end

        counts[status] = (counts[status] or 0) + 1
        list[#list + 1] = {
            name = entry.name, class = entry.class, status = status,
            version = version, protocol = protocol,
            isSelf = key == ownName or nil,
        }
    end

    -- Zuerst, was Aufmerksamkeit braucht: veraltet, dann still, dann der Rest.
    local order = { outdated = 1, unknown = 2, silent = 3, newer = 4, current = 5 }
    table.sort(list, function(a, b)
        if a.status ~= b.status then
            return (order[a.status] or 9) < (order[b.status] or 9)
        end
        return (a.name or "") < (b.name or "")
    end)

    counts.total = #list
    return list, counts
end

--- Kurzfassung fuer die Statuszeile.
function VersionCheck:Summary()
    local _, counts = self:Result()
    return counts
end

-- ================================================================== Start ------

function VersionCheck:OnEnable()
    -- Nichts zu tun: Die Antworten laufen ueber Sync, und gefragt wird nur
    -- auf Anforderung. Ein Addon, das beim Einloggen ungefragt die Gilde
    -- abfragt, ist genau der Nachrichtenverkehr, den Phase 8 abgestellt hat.
end
