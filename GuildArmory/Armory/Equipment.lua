--[[----------------------------------------------------------------------------
    Armory/Equipment — erfasst die Ausruestung des eigenen Charakters.

    Kein UI. Dieses Modul pflegt den Charakterdatensatz in der Datenbank, legt
    Ausruestungsstaende (Snapshots) an und feuert EQUIPMENT_UPDATED.

    DREI REGELN AUS DER VORGABE, DIE HIER DURCHGESETZT WERDEN:

    1. Snapshots nur bei echten Aenderungen (Abschnitt 10). Ein Login ohne
       Ausruestungswechsel erzeugt keinen neuen Stand — verglichen wird die
       Item-ID je Platz gegen den letzten Snapshot.

    2. Jeder Stand traegt einen Zeitstempel und eine Quelle ("self", "inspect",
       "sync"). Die Armory-Ansicht zeigt fremde Staende NIE als aktuell an
       (Abschnitt 4).

    3. Das Itemlevel wird selbst berechnet. GetAverageItemLevel ist in Forever
       fehlerhaft — siehe Compatibility.lua, Kopf.

    Items, die noch nicht im Client-Cache sind, liefern beim ersten Zugriff keinen
    Namen. Dann wird eine Nacherfassung eingeplant, statt "?" zu speichern.
------------------------------------------------------------------------------]]

local _, GA = ...

local Equipment = {}
GA.Modules.Equipment = Equipment

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Schema = GA.Data.Schema

local pending = false
local retryScheduled = false

-- ================================================================== Erfassung -

--- Liest einen Ausruestungsplatz aus.
--- @return table|nil eintrag, boolean unvollstaendig (Name/Icon fehlen noch)
local function readSlot(unit, slotID)
    local link = Compat.GetEquippedLink(unit, slotID)
    if not link then return nil, false end

    local parsed = Compat.ParseItemLink(link) or {}
    local info = Compat.GetItemInfo(link)
    local itemLevel = Compat.GetItemLevelOf(link)

    local entry = {
        link = link,
        itemID = parsed.itemID,
        enchantID = parsed.enchantID,
        gems = parsed.gems or {},
        itemLevel = itemLevel,
        name = info and info.name or nil,
        icon = info and info.icon or nil,
        quality = info and info.quality or nil,
        equipLoc = info and info.equipLoc or nil,
    }

    local incomplete = (entry.name == nil) or (entry.itemLevel == nil)
    return entry, incomplete
end

--- Liest alle Plaetze einer Einheit. Gemeinsamer Weg fuer den eigenen
--- Charakter ("player") und Inspect (Armory/Inspect.lua), damit beide gleich
--- rechnen.
--- @return table equipment (slotID -> Eintrag), boolean unvollstaendig
function Equipment:ReadEquipment(unit)
    local equipment = {}
    local anyIncomplete = false
    for _, slot in ipairs(Compat.EQUIPMENT_SLOTS) do
        local entry, incomplete = readSlot(unit or "player", slot.id)
        if entry then equipment[slot.id] = entry end
        if incomplete then anyIncomplete = true end
    end
    return equipment, anyIncomplete
end

--- Erfasst alle Plaetze und schreibt sie in die Datenbank.
function Equipment:Capture(reason)
    if Compat.InCombat() then
        -- Waehrend des Kampfes nicht erfassen: Item-Infos koennen fehlen, und
        -- der Zustand aendert sich ohnehin gleich wieder.
        self:RequestCapture(reason, 3)
        return
    end

    local identity = Compat.GetPlayerIdentity()
    if not identity.guid then return end

    local db = GA.Core.Database
    local character = db:GetCharacter(identity.guid, identity)

    local equipment, anyIncomplete = self:ReadEquipment("player")
    local average, count = Compat.ComputeItemLevel("player")

    character.equipment = equipment
    character.equipmentTs = Util.Now()
    character.source = "self"
    -- BEWEIS fuer Armory/Players: Dieser Charakter hat sich auf DIESEM Account
    -- mit diesem Addon eingeloggt. Alle so markierten Charaktere gehoeren
    -- demselben Spieler — sie teilen sich diese SavedVariables-Datei.
    character.ownAccount = true
    character.itemLevel = { value = average, count = count, ts = Util.Now() }
    character.specID = Compat.GetSpecializationID("player") or character.specID

    local loadout = Compat.GetTalentLoadoutString()
    if loadout then character.loadout = { value = loadout, ts = Util.Now() } end

    -- Gildendaten am eigenen Charakter mitfuehren.
    local guildName, rankName, rankIndex = Compat.GetOwnGuildInfo()
    if guildName then
        character.guildRank = rankName
        character.guildRankIndex = rankIndex
        db.account.guild.name = guildName
    end

    self:Snapshot(character, equipment, average)
    self.lastIncomplete = anyIncomplete

    Debug:Print("armory", "Ausruestung erfasst (%s): %d Plaetze, Itemlevel %s%s",
        tostring(reason), count, tostring(average),
        anyIncomplete and " — unvollstaendig, Nacherfassung geplant" or "")

    GA.Core.Callbacks:Fire("EQUIPMENT_UPDATED", identity.guid)

    -- Fehlende Item-Infos: einmal spaeter nachholen, nicht endlos.
    if anyIncomplete and not retryScheduled then
        retryScheduled = true
        Compat.After(2, function()
            retryScheduled = false
            Equipment:Capture("Nacherfassung")
        end)
    end
end

-- ================================================================== Snapshots -

--- Legt einen Ausruestungsstand an, wenn sich gegenueber dem letzten etwas
--- geaendert hat. Speichert nur Item-IDs je Platz plus die Aenderungsliste —
--- die volle Iteminfo steht im aktuellen Charakterdatensatz.
function Equipment:Snapshot(character, equipment, itemLevel)
    local db = GA.Core.Database
    local list = db.account.snapshots[character.guid]
    if not list then
        list = {}
        db.account.snapshots[character.guid] = list
    end

    local slots = {}
    for slotID, entry in pairs(equipment) do
        slots[slotID] = entry.itemID
    end

    local previous = list[#list]
    local changes = {}

    if previous then
        -- Beide Richtungen: neu angelegt, abgelegt, getauscht.
        for _, slot in ipairs(Compat.EQUIPMENT_SLOTS) do
            local before, after = previous.slots[slot.id], slots[slot.id]
            if before ~= after then
                changes[#changes + 1] = { slot = slot.id, from = before, to = after }
            end
        end
        if #changes == 0 and previous.itemLevel == itemLevel then
            return nil  -- nichts Neues
        end
    end

    local snapshot = {
        ts = Util.Now(),
        itemLevel = itemLevel,
        slots = slots,
        changes = changes,
    }
    list[#list + 1] = snapshot

    -- Aelteste raus, wenn die Grenze erreicht ist. Der erste Stand bleibt als
    -- Ausgangspunkt erhalten, damit die Kurve einen Anfang hat.
    while #list > Schema.SNAPSHOT_LIMIT_PER_CHARACTER do
        table.remove(list, 2)
    end

    Debug:Print("armory", "Snapshot #%d: %d Aenderungen, Itemlevel %s",
        #list, #changes, tostring(itemLevel))

    return snapshot
end

function Equipment:GetSnapshots(guid)
    return GA.Core.Database.account.snapshots[guid] or {}
end

-- ================================================================== Drosselung

--- PLAYER_EQUIPMENT_CHANGED feuert je Platz einzeln — beim Anlegen eines Sets
--- also mehrfach hintereinander. Eine Erfassung je Salve genuegt.
function Equipment:RequestCapture(reason, delay)
    if pending then return end
    pending = true
    Compat.After(delay or 0.5, function()
        pending = false
        Equipment:Capture(reason)
    end)
end

-- ================================================================== Start ------

function Equipment:OnEnable()
    local Events = GA.Core.Events

    Events:Register("PLAYER_EQUIPMENT_CHANGED", function()
        Equipment:RequestCapture("Ausruestung geaendert")
    end, "Equipment")

    Events:Register("PLAYER_ENTERING_WORLD", function()
        Equipment:RequestCapture("Welt betreten", 1.5)
    end, "Equipment")

    -- Wenn Iteminfos nachgeladen werden, kann ein vorher unvollstaendiger Stand
    -- jetzt vollstaendig sein. Gemessen: Das Ereignis feuert beim Einloggen
    -- ueber hundertmal (145x am 19.09.2026) — deshalb NUR reagieren, wenn der
    -- letzte Stand tatsaechlich Luecken hatte.
    Events:Register("GET_ITEM_INFO_RECEIVED", function()
        if Equipment.lastIncomplete then
            Equipment:RequestCapture("Iteminfo nachgeladen", 1.5)
        end
    end, "Equipment")

    Events:Register("PLAYER_GUILD_UPDATE", function()
        Equipment:RequestCapture("Gilde geaendert", 1)
    end, "Equipment")

    self:RequestCapture("Start", 1)
end
