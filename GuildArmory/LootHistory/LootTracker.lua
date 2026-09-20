--[[----------------------------------------------------------------------------
    LootHistory/LootTracker — erkennt Loot und bestaetigt Uebergaben.

    Kein UI. Uebersetzt Spielereignisse in Aufrufe an LootHistory/Awards.

    WORAUF DIE HERKUNFT EINER VERGABE BERUHT (Vorgabe: keine erfundene
    Boss-Zuordnung):

      Das Combat Log ist fuer Addons in Forever nicht lesbar — gemessen am
      18.09.2026: 37 Kaempfe, 0 Ereignisse. Damit faellt der uebliche Weg weg,
      einen Bosskill einem Drop zuzuordnen. Es bleiben zwei belastbare Quellen:

        1. ENCOUNTER_START/END — liefert encounterID und Namen vom Server.
           Autoritativ, solange das Ereignis feuert.
        2. GetLootSourceInfo(slot) -> GUID der Leiche -> npcID.
           Das ist der tatsaechliche Ablegende, keine Vermutung.

      Ist keine der beiden da, bleiben encounterName und sourceName LEER.
      Die Historie zeigt dann "unbekannt" — und nicht den Namen des Gegners,
      den der Spieler zufaellig gerade anvisiert hat.

    WANN EINE VERGABE ALS ERHALTEN GILT: nie automatisch aus der Vergabe selbst.
    Nur Confirm() mit einer Bestaetigungsart, und die kommt aus einem Ereignis —
    LOOT_SLOT_CLEARED nach GiveMasterLoot, der geschlossene Handel, oder die
    Loot-Nachricht im Chat (schwach, ausdruecklich als solche gekennzeichnet).
------------------------------------------------------------------------------]]

local _, GA = ...

local LootTracker = {}
GA.Modules.LootTracker = LootTracker

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Schema = GA.Data.Schema

--- Aktueller Kampf (aus ENCOUNTER_START). Nur gueltig bis ENCOUNTER_END.
local encounter = nil

--- Slots, fuer die dieser Client GiveMasterLoot ausgeloest hat: slot -> awardId.
--- Wird von LOOT_SLOT_CLEARED eingeloest und bei LOOT_CLOSED verworfen.
local masterLootPending = {}

--- Items im offenen Loot-Fenster, die schon eine Vergabe haben: slot -> awardId.
local detectedSlots = {}

-- ================================================================== Kontext ---

--- Alles, was ueber den Fundort bekannt IST — nicht mehr.
local function buildContext(slot)
    local context = {
        lootMethod = Compat.GetLootMethod(),
        slot = slot,
    }

    if encounter then
        context.encounterID = encounter.id
        context.encounterName = encounter.name
        context.difficultyID = encounter.difficultyID
    end

    local source = Compat.GetLootSource(slot)
    if source then
        context.sourceGuid = source.guid
        context.sourceNpcID = source.npcID
        context.sourceName = source.name
    end

    if type(_G.GetInstanceInfo) == "function" then
        local ok, name, instanceType, difficultyID = pcall(GetInstanceInfo)
        if ok and instanceType and instanceType ~= "none" then
            context.instanceName = name
            context.difficultyID = context.difficultyID or difficultyID
        end
    end

    if type(_G.GetRealZoneText) == "function" then
        local ok, zone = pcall(GetRealZoneText)
        if ok then context.zone = zone end
    end

    return context
end

-- ================================================================== Erkennung -

--- Soll dieser Gegenstand ueberhaupt erfasst werden?
--- @return boolean, string|nil grund (fuer die Debug-Ausgabe)
function LootTracker:ShouldTrack(item)
    local threshold = GA.Core.Config:Get("lootThresholdQuality") or 3
    if (item.quality or 0) < threshold then return false, "unter Schwelle" end

    if not Compat.IsInGroup() and not GA.Core.Config:Get("trackOutsideGroup") then
        return false, "allein (Erfassung ausserhalb der Gruppe ist aus)"
    end
    return true
end

function LootTracker:OnLootOpened()
    local slots = Compat.GetLootSlots()
    self:MeasureLootMethod()

    for _, entry in ipairs(slots) do
        if not detectedSlots[entry.slot] then
            local parsed = Compat.ParseItemLink(entry.link) or {}
            local info = Compat.GetItemInfo(entry.link)

            local item = {
                itemID = parsed.itemID,
                link = entry.link,
                name = entry.name or (info and info.name),
                quality = entry.quality or (info and info.quality),
                quantity = entry.quantity,
            }

            local track, reason = self:ShouldTrack(item)
            if track then
                local award = GA.Modules.Awards:Create(item, buildContext(entry.slot))
                detectedSlots[entry.slot] = award.id
                Debug:Print("loot", "Erkannt: %s (%s)", tostring(item.link),
                    award.encounterName or award.sourceName or award.sourceNpcID and
                    ("NPC " .. award.sourceNpcID) or "Herkunft unbekannt")
            else
                Debug:Print("loot", "Uebergangen: %s — %s", tostring(item.link), tostring(reason))
            end
        end
    end
end

function LootTracker:OnLootClosed()
    Util.Wipe(detectedSlots)
    Util.Wipe(masterLootPending)
end

-- ================================================================== Messung ---

--- Haelt fest, welche Lootmethoden dieser Client tatsaechlich gesehen hat.
--- Der Bericht in den Einstellungen beruht damit auf Beobachtung, nicht auf
--- der Annahme, dass eine vorhandene API auch benutzbar ist.
function LootTracker:MeasureLootMethod()
    if not Compat.IsInGroup() then return end

    local raw = Compat.GetRawLootMethod()
    if raw == nil then return end

    local seen = GA.Core.Database.account.measured
    if not seen then
        seen = {}
        GA.Core.Database.account.measured = seen
    end
    seen.lootMethods = seen.lootMethods or {}
    seen.rawLootMethods = seen.rawLootMethods or {}

    -- Den Rohwert mitschreiben. Genau daran ist am 19.09.2026 aufgefallen, dass
    -- Forever eine Zahl liefert und nicht den klassischen Text.
    local rawKey = tostring(raw) .. " (" .. type(raw) .. ")"
    if not seen.rawLootMethods[rawKey] then
        seen.rawLootMethods[rawKey] = Util.Now()
    end

    local method = Compat.GetLootMethod()
    if not method then
        -- Der Rohwert liess sich nicht uebersetzen. Das ist keine Kleinigkeit:
        -- Ohne Uebersetzung weiss das Addon nicht, ob Pluendermeister laeuft.
        if not seen.warnedUnknownLootMethod then
            seen.warnedUnknownLootMethod = true
            Debug:Warn("Unbekannte Lootmethode %s — bitte melden.", rawKey)
        end
        return
    end

    if not seen.lootMethods[method] then
        seen.lootMethods[method] = Util.Now()
        Debug:Print("loot", "Lootmethode zum ersten Mal gesehen: %s (roh: %s)", method, rawKey)
        GA.Core.Callbacks:Fire("COMPAT_MEASURED")
    end
end

-- ================================================================== Zuweisen --

--- Weist einen Gegenstand per Plündermeister zu.
--- MUSS aus einem Mausklick heraus aufgerufen werden: GiveMasterLoot ist eine
--- geschuetzte Funktion, ein automatischer Aufruf wird vom Client verworfen.
--- @return boolean angestossen, string|nil grund
function LootTracker:GiveMasterLoot(awardId, candidateIndex)
    local award = GA.Modules.Awards:Get(awardId)
    if not award then return false, "unknown" end
    if not award.slot then return false, "noslot" end
    if not Compat.IsMasterLooter() then return false, "notmaster" end

    if not Compat.GiveMasterLoot(award.slot, candidateIndex) then
        return false, "failed"
    end

    -- Noch NICHT bestaetigen: Der Aufruf ist angestossen, nicht abgeschlossen.
    -- Erst LOOT_SLOT_CLEARED belegt, dass der Gegenstand das Fenster verlassen hat.
    masterLootPending[award.slot] = awardId
    Debug:Print("loot", "Master Loot angestossen: Slot %d -> Kandidat %d",
        award.slot, candidateIndex)
    return true
end

function LootTracker:OnLootSlotCleared(slot)
    local awardId = masterLootPending[slot]
    if not awardId then return end
    masterLootPending[slot] = nil

    local ok = GA.Modules.Awards:Confirm(awardId, Schema.Confirmation.MASTER_LOOT,
        { by = Compat.GetPlayerIdentity().guid, reason = "Slot geleert nach GiveMasterLoot" })
    if ok then
        Debug:Print("loot", "Bestaetigt (Master Loot): %s", awardId)
    end
end

-- ================================================================== Chat ------

--- Baut aus einem Blizzard-Formatstring ein Lua-Muster. So funktioniert die
--- Erkennung in jeder Sprache, statt an deutschen oder englischen Satzbau
--- gebunden zu sein.
local function toPattern(globalString)
    if type(globalString) ~= "string" then return nil end
    local pattern = string.gsub(globalString, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    pattern = string.gsub(pattern, "%%%%s", "(.-)")
    pattern = string.gsub(pattern, "%%%%d", "(%%d+)")
    return "^" .. pattern .. "$"
end

--- Welche Felder in welcher Reihenfolge im jeweiligen Formatstring stehen.
local CHAT_PATTERNS
local function buildChatPatterns()
    if CHAT_PATTERNS then return CHAT_PATTERNS end
    CHAT_PATTERNS = {}

    -- REIHENFOLGE IST WESENTLICH: Die Mehrfach-Varianten zuerst.
    -- Gemessen 19.09.2026: LOOT_ITEM_SELF ist "You receive loot: %s" — OHNE
    -- Punkt am Ende. Das daraus gebaute Muster "^You receive loot: (.-)$"
    -- passt deshalb auch auf "You receive loot: [Apfel]x2" und wuerde "[Apfel]x2"
    -- als Gegenstandsnamen nehmen. Wird die Mehrfach-Variante zuerst geprueft,
    -- gewinnt die genauere.
    local definitions = {
        { key = "LOOT_ITEM_SELF_MULTIPLE",  fields = { "item", "count" } },
        { key = "LOOT_ITEM_PUSHED_SELF_MULTIPLE", fields = { "item", "count" } },
        { key = "LOOT_ITEM_MULTIPLE",       fields = { "player", "item", "count" } },
        { key = "LOOT_ITEM_PUSHED_MULTIPLE",fields = { "player", "item", "count" } },
        { key = "LOOT_ITEM_SELF",           fields = { "item" } },
        { key = "LOOT_ITEM_PUSHED_SELF",    fields = { "item" } },
        { key = "LOOT_ITEM",                fields = { "player", "item" } },
        { key = "LOOT_ITEM_PUSHED",         fields = { "player", "item" } },
    }

    for _, definition in ipairs(definitions) do
        local pattern = toPattern(_G[definition.key])
        if pattern then
            CHAT_PATTERNS[#CHAT_PATTERNS + 1] = {
                pattern = pattern,
                fields = definition.fields,
                selfOnly = string.find(definition.key, "SELF") ~= nil,
            }
        end
    end
    return CHAT_PATTERNS
end

--- Zerlegt eine Loot-Nachricht. @return string|nil spieler, string|nil itemLink
function LootTracker:ParseLootMessage(message)
    for _, entry in ipairs(buildChatPatterns()) do
        local a, b, c = string.match(message, entry.pattern)
        if a then
            local values = { a, b, c }
            local result = {}
            for index, field in ipairs(entry.fields) do
                result[field] = values[index]
            end
            local player = result.player
            if entry.selfOnly then player = UnitName("player") end
            if result.item then return player, result.item end
        end
    end
    return nil
end

--- Die Loot-Nachricht ist eine SCHWACHE Bestaetigung: Sie belegt, dass jemand
--- diesen Gegenstand aufgenommen hat — nicht, dass es der aus dieser Vergabe
--- war. Bei zwei gleichen Gegenstaenden im selben Raid kann sie danebenliegen.
--- Deshalb bestaetigt sie nur Vergaben, die auf genau diesen Empfaenger warten,
--- und wird als LOOT_CHAT gekennzeichnet.
function LootTracker:OnChatLoot(message)
    local player, link = self:ParseLootMessage(message or "")
    if not player or not link then return end

    local parsed = Compat.ParseItemLink(link)
    if not parsed or not parsed.itemID then return end

    local award = GA.Modules.Awards:FindAwaiting(parsed.itemID, Util.ShortName(player))
    if not award then return end

    local ok = GA.Modules.Awards:Confirm(award.id, Schema.Confirmation.LOOT_CHAT,
        { reason = "Loot-Nachricht im Chat" })
    if ok then
        Debug:Print("loot", "Bestaetigt (Chat, schwach): %s an %s", tostring(link), player)
    end
end

-- ================================================================== Handel ----

function LootTracker:OnTradeShow()
    self.trade = { partner = Compat.GetTradePartner(), accepted = false }
end

--- TRADE_ACCEPT_UPDATE(playerAccepted, targetAccepted): Erst wenn BEIDE
--- zugestimmt haben, wird der Handel ausgefuehrt. Der Inhalt muss in diesem
--- Moment gelesen werden — nach TRADE_CLOSED ist das Fenster leer.
function LootTracker:OnTradeAccept(playerAccepted, targetAccepted)
    if not self.trade then return end
    if playerAccepted ~= 1 or targetAccepted ~= 1 then return end

    self.trade.accepted = true
    self.trade.items = Compat.GetTradeItems("player")
    self.trade.partner = self.trade.partner or Compat.GetTradePartner()
end

function LootTracker:OnTradeClosed()
    local trade = self.trade
    self.trade = nil
    if not trade or not trade.accepted or not trade.partner then return end

    for _, entry in ipairs(trade.items or {}) do
        local parsed = Compat.ParseItemLink(entry.link)
        if parsed and parsed.itemID then
            local award = GA.Modules.Awards:FindAwaiting(parsed.itemID, Util.ShortName(trade.partner))
            if award then
                local ok = GA.Modules.Awards:Confirm(award.id, Schema.Confirmation.TRADE,
                    { by = Compat.GetPlayerIdentity().guid,
                      reason = "Handel mit " .. tostring(trade.partner) .. " abgeschlossen" })
                if ok then
                    Debug:Print("loot", "Bestaetigt (Handel): %s an %s",
                        tostring(entry.link), trade.partner)
                end
            end
        end
    end
end

-- ================================================================== Angelegt --

--- Taucht ein erhaltener Gegenstand spaeter in der Ausruestung auf, ist das der
--- Abschluss des Lebenszyklus. Gelesen wird der letzte Ausruestungsstand —
--- nicht das Loot-Ereignis, denn angelegt wird meistens erst viel spaeter.
function LootTracker:OnEquipmentUpdated(guid)
    if not guid then return end

    local snapshots = GA.Core.Database.account.snapshots[guid]
    local latest = snapshots and snapshots[#snapshots]
    if not latest or not latest.changes then return end

    for _, change in ipairs(latest.changes) do
        if change.to then
            for _, award in ipairs(GA.Modules.Awards:List({ itemID = change.to })) do
                if award.status == Schema.LootStatus.RECEIVED and award.recipientGuid == guid then
                    GA.Modules.Awards:MarkEquipped(award.id, { by = guid, reason = "im Ausruestungsstand" })
                    Debug:Print("loot", "Angelegt: %s", tostring(award.itemLink))
                end
            end
        end
    end
end

-- ================================================================== Start ------

function LootTracker:OnEnable()
    local Events = GA.Core.Events

    Events:Register("LOOT_OPENED", function() LootTracker:OnLootOpened() end, "LootTracker")
    Events:Register("LOOT_READY", function() LootTracker:OnLootOpened() end, "LootTracker")
    Events:Register("LOOT_CLOSED", function() LootTracker:OnLootClosed() end, "LootTracker")
    Events:Register("LOOT_SLOT_CLEARED", function(_, slot)
        LootTracker:OnLootSlotCleared(slot)
    end, "LootTracker")

    Events:Register("CHAT_MSG_LOOT", function(_, message)
        LootTracker:OnChatLoot(message)
    end, "LootTracker")

    Events:Register("ENCOUNTER_START", function(_, id, name, difficultyID)
        encounter = { id = id, name = name, difficultyID = difficultyID, ts = Util.Now() }
        Debug:Print("loot", "Kampf gestartet: %s (%s)", tostring(name), tostring(id))
    end, "LootTracker")

    -- Der Kontext bleibt ueber das Kampfende hinaus kurz bestehen: Der Loot
    -- liegt erst nach ENCOUNTER_END auf der Leiche.
    Events:Register("ENCOUNTER_END", function(_, id, name, difficultyID, _, success)
        encounter = { id = id, name = name, difficultyID = difficultyID,
                      ts = Util.Now(), ended = true, success = success }
        Compat.After(300, function()
            if encounter and encounter.ended and encounter.id == id then encounter = nil end
        end)
    end, "LootTracker")

    Events:Register("TRADE_SHOW", function() LootTracker:OnTradeShow() end, "LootTracker")
    Events:Register("TRADE_ACCEPT_UPDATE", function(_, player, target)
        LootTracker:OnTradeAccept(player, target)
    end, "LootTracker")
    Events:Register("TRADE_CLOSED", function() LootTracker:OnTradeClosed() end, "LootTracker")

    Events:Register("PARTY_LOOT_METHOD_CHANGED", function()
        LootTracker:MeasureLootMethod()
    end, "LootTracker")
    Events:Register("GROUP_ROSTER_UPDATE", function()
        LootTracker:MeasureLootMethod()
    end, "LootTracker")

    -- Achtung: Callbacks:Fire reicht den Ereignisnamen NICHT durch (anders als
    -- Core/Events). Der erste Parameter ist bereits die GUID.
    GA.Core.Callbacks:On("EQUIPMENT_UPDATED", function(guid)
        LootTracker:OnEquipmentUpdated(guid)
    end, "LootTracker")
end
