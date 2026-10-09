--[[----------------------------------------------------------------------------
    Wishlist/Wishlist — was ein Charakter gern haette.

    Kein UI. Reine Logik auf der Datenbank, geprueft in tools/test/wishlist.test.js.

    WAS EINE WUNSCHLISTE IST UND WAS NICHT:

      Sie ist eine Absichtserklaerung des Spielers, kein Anspruch und kein
      gemessener Bedarf. Das Addon rechnet daraus deshalb KEINE Punktzahl, die
      eine Vergabe entscheidet. Im Council steht ein Wunschlisteneintrag als
      Hinweis neben der Bewerbung — mehr nicht. Wer entscheidet, bleibt das
      Council.

      Der Unterschied ist nicht akademisch: Sobald eine Wunschliste automatisch
      Prioritaet erzeugt, fuellt sie jeder mit allem.

    EIN EINTRAG JE CHARAKTER UND GEGENSTAND. Ein zweites Hinzufuegen aendert den
    bestehenden Eintrag, statt einen Doppeleintrag anzulegen — sonst zaehlt
    derselbe Wunsch im Council zweimal.

    ERFUELLTE EINTRAEGE BLEIBEN STEHEN, markiert mit der Vergabe, die sie
    erfuellt hat. Sie zu loeschen wuerde die Frage "hat er den schon bekommen?"
    unbeantwortbar machen — und genau die stellt das Council beim naechsten Mal.
------------------------------------------------------------------------------]]

local _, GA = ...

local Wishlist = {}
GA.Modules.Wishlist = Wishlist

local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Schema = GA.Data.Schema

local function store()
    return GA.Core.Database.account.wishlists
end

-- ================================================================== Prioritaet

function Wishlist:Priorities()
    return Schema.WishlistPriority
end

function Wishlist:PriorityByKey(key)
    for _, priority in ipairs(Schema.WishlistPriority) do
        if priority.key == key then return priority end
    end
    return nil
end

local function weightOf(key)
    local priority = Wishlist:PriorityByKey(key)
    return priority and priority.weight or -1
end

-- ================================================================== Aendern ---

--- Legt einen Wunsch an oder aktualisiert ihn.
--- @return table|nil eintrag, string|nil grund
function Wishlist:Add(guid, itemID, priorityKey, note)
    if not guid then return nil, "nocharacter" end

    itemID = tonumber(itemID)
    if not itemID then return nil, "noitem" end
    if not self:PriorityByKey(priorityKey) then return nil, "unknownpriority" end

    local list = store()[guid]
    if not list then
        list = {}
        store()[guid] = list
    end

    note = note and string.sub(note, 1, 80) or nil

    for _, entry in ipairs(list) do
        if entry.itemID == itemID then
            local before = entry.priority
            entry.priority = priorityKey
            -- Ohne Notiz im Aufruf bleibt die alte: Wer die Prioritaet ueber
            -- die Knoepfe neu setzt, hat seine Notiz nicht zurueckgenommen.
            if note ~= nil then entry.note = note end
            entry.updatedTs = Util.Now()
            if before ~= priorityKey then
                GA.Core.Database:Journal("WISH_PRIORITY", guid, before, priorityKey)
            end
            GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
            return entry
        end
    end

    local entry = {
        itemID = itemID,
        priority = priorityKey,
        note = note,
        addedTs = Util.Now(),
    }
    list[#list + 1] = entry

    GA.Core.Database:Journal("WISH_ADD", guid, nil, itemID)
    GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
    Debug:Print("loot", "Wunsch aufgenommen: %s fuer %s", tostring(itemID), tostring(guid))
    return entry
end

--- Aendert Prioritaet und/oder Notiz eines Wunsches (08.10.2026 — bis
--- dahin konnte die Oberflaeche beides nur beim Anlegen setzen).
--- @param changes table { priority?, note? }  note "" loescht die Notiz
--- @return table|nil eintrag, string|nil grund
function Wishlist:Update(guid, itemID, changes)
    local entry = self:Find(guid, tonumber(itemID))
    if not entry then return nil, "unknown" end
    changes = changes or {}

    if changes.priority ~= nil then
        if not self:PriorityByKey(changes.priority) then return nil, "unknownpriority" end
        if entry.priority ~= changes.priority then
            GA.Core.Database:Journal("WISH_PRIORITY", guid, entry.priority, changes.priority)
            entry.priority = changes.priority
        end
    end
    if changes.note ~= nil then
        local note = Util.Trim(tostring(changes.note)) or ""
        entry.note = note ~= "" and string.sub(note, 1, 80) or nil
    end
    entry.updatedTs = Util.Now()
    GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
    return entry
end

function Wishlist:Remove(guid, itemID)
    local list = store()[guid]
    if not list then return false end

    itemID = tonumber(itemID)
    for index = #list, 1, -1 do
        if list[index].itemID == itemID then
            table.remove(list, index)
            GA.Core.Database:Journal("WISH_REMOVE", guid, itemID, nil)
            GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
            return true
        end
    end
    return false
end

function Wishlist:Find(guid, itemID)
    itemID = tonumber(itemID)
    for _, entry in ipairs(store()[guid] or {}) do
        if entry.itemID == itemID then return entry end
    end
    return nil
end

--- Uebernimmt die BiS-Liste als Wuensche mit Prioritaet "Best in Slot"
--- (09.10.2026). Was schon getragen wird oder schon auf der Liste steht,
--- bleibt aussen vor — ein Wunsch, der schon da ist, behaelt seine
--- Prioritaet und seine Notiz.
--- @return number aufgenommen, number getragen, number schonDa
function Wishlist:LoadFromBis(guid)
    if not guid then return 0, 0, 0 end
    local added, worn, there = 0, 0, 0
    local status = self:BisStatus(guid)
    for _, slotID in ipairs(self.BIS_SLOTS) do
        local st = status[slotID]
        if st and st.itemID then
            if st.worn then
                worn = worn + 1
            elseif self:Find(guid, st.itemID) then
                there = there + 1
            elseif self:Add(guid, st.itemID, "BIS") then
                added = added + 1
            end
        end
    end
    return added, worn, there
end

-- ================================================================== Abfragen --

--- Wunschliste eines Charakters, nach Gewicht und Alter sortiert.
--- @param includeFulfilled boolean|nil  Standard: erfuellte bleiben unten dran
function Wishlist:Get(guid, includeFulfilled)
    local list = {}
    for _, entry in ipairs(store()[guid] or {}) do
        if includeFulfilled ~= false or not entry.fulfilledByAwardId then
            list[#list + 1] = entry
        end
    end

    table.sort(list, function(a, b)
        -- Erfuelltes nach unten: Es ist Historie, keine offene Bitte.
        local aDone = a.fulfilledByAwardId ~= nil
        local bDone = b.fulfilledByAwardId ~= nil
        if aDone ~= bDone then return bDone end

        local aWeight, bWeight = weightOf(a.priority), weightOf(b.priority)
        if aWeight ~= bWeight then return aWeight > bWeight end
        return (a.addedTs or 0) < (b.addedTs or 0)
    end)
    return list
end

-- ================================================================== Best in Slot
--
-- EIN GEGENSTAND JE PLATZ, JE CHARAKTER (08.10.2026, Wunsch: "eine BiS-Liste,
-- die das Puppenmodul spiegelt"). Die Liste liegt neben der Wunschliste,
-- wandert mit ihr zur Gilde, in Export und Import — und zaehlt in der
-- Lootsitzung als Wunsch mit Prioritaet "Best in Slot". Ob das Teil
-- getragen wird, sagt BisStatus; Armory und Wunschliste leuchten dann gold.

--- Die Plaetze der Liste: die Puppe ohne Hemd und Wappenrock.
Wishlist.BIS_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local BIS_SLOT_OK = {}
for _, id in ipairs(Wishlist.BIS_SLOTS) do BIS_SLOT_OK[id] = true end
--- Zweiter Platz derselben Art: Ring, Schmuck, Einhandwaffe.
local TWIN_SLOT = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }

local function bisStore()
    local account = GA.Core.Database.account
    account.bis = account.bis or {}
    return account.bis
end

--- @return table { [slotID] = { itemID, ts } }
function Wishlist:Bis(guid)
    return guid and bisStore()[guid] or {}
end

--- Setzt oder loescht (itemID nil) das BiS-Teil eines Platzes.
--- @return boolean ok, string|nil grund
function Wishlist:SetBis(guid, slotID, itemID, quiet)
    if not guid then return false, "nocharacter" end
    slotID = tonumber(slotID)
    if not slotID or not BIS_SLOT_OK[slotID] then return false, "badslot" end
    itemID = tonumber(itemID)
    local list = bisStore()[guid]
    if not list then list = {} bisStore()[guid] = list end
    local before = list[slotID] and list[slotID].itemID or nil
    if before == itemID then return true end
    if itemID then list[slotID] = { itemID = itemID, ts = Util.Now() } else list[slotID] = nil end
    if not quiet then
        GA.Core.Database:Journal("WISH_BIS", guid, before, itemID)
        GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
    end
    return true
end

--- Die ganze Liste ersetzen — fuer den Abgleich (der Absender ist massgeblich).
-- ============================================================ FojjiCore ----
--
-- IMPORT AUS FOJJICORE (09.10.2026). Fojji hat schriftlich erlaubt, den
-- Export seines BiS-Managers bei uns als Import anzubieten (Discord, 09.10.).
-- Gelesen wird NUR das Textformat, das sein Addon jedem Spieler zum Kopieren
-- gibt; kein Code und keine Grafik von FojjiCore sind hier enthalten —
-- seine Lizenz ("All rights reserved") erlaubt das nicht, und die Erlaubnis
-- gilt dem Import.
--
--   FCBIS1:head=ID,ID;neck=ID;…;rings=ID,ID,ID;trinkets=ID,ID;name=Liste_Name
--
-- Je Gruppe eine Rangliste: die erste ID ist das BiS-Teil, die weiteren
-- sind Alternativen. Ringe, Schmuck: die ersten zwei verschiedenen IDs
-- fuellen beide Plaetze. Der Wappenrock zaehlt bei uns nicht.
Wishlist.FOJJI_GROUPS = {
    head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 },
    wrist = { 9 }, hands = { 10 }, waist = { 6 }, legs = { 7 }, feet = { 8 },
    rings = { 11, 12 }, trinkets = { 13, 14 },
    mainhand = { 16 }, offhand = { 17 }, ranged = { 18 },
}

--- Liest einen FojjiCore-Export.
--- @return table|nil { slots = { [slotID] = itemID }, alternatives = n, name = text|nil }, string|nil grund
function Wishlist.ParseFojji(text)
    text = string.gsub(tostring(text or ""), "%s", "")
    local body = string.match(text, "FCBIS1:([^%s]*)")
    if not body then return nil, "format" end
    local out = { slots = {}, alternatives = 0 }
    local name = string.match(body, "name=([^;]+)")
    if name then out.name = (string.gsub(name, "_", " ")) end
    for key, ids in string.gmatch(body, "(%a+)=([%d,]+)") do
        local slots = Wishlist.FOJJI_GROUPS[key]
        if slots then
            local list, seen = {}, {}
            for id in string.gmatch(ids, "%d+") do
                id = tonumber(id)
                if id and id > 0 and not seen[id] then seen[id] = true list[#list + 1] = id end
            end
            for index, slotID in ipairs(slots) do
                if list[index] then out.slots[slotID] = list[index] end
            end
            out.alternatives = out.alternatives + math.max(0, #list - #slots)
        end
    end
    if not next(out.slots) then return nil, "empty" end
    return out
end

--- Uebernimmt einen FojjiCore-Export in die eigene BiS-Liste: Die Plaetze
--- aus dem Export werden gesetzt, die anderen bleiben, wie sie sind.
--- @return table|nil ergebnis { set, alternatives, name }, string|nil grund
function Wishlist:ImportFojji(guid, text)
    if not guid then return nil, "nocharacter" end
    local parsed, why = self.ParseFojji(text)
    if not parsed then return nil, why end
    local set = 0
    for slotID, itemID in pairs(parsed.slots) do
        if self:SetBis(guid, slotID, itemID, true) then set = set + 1 end
    end
    GA.Core.Database:Journal("WISH_BIS_IMPORT", guid, "fojji", set)
    GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
    return { set = set, alternatives = parsed.alternatives, name = parsed.name }
end

--- DIREKT AUS FOJJICORE (09.10.2026): Ist FojjiCore mit seinem BiS-Manager
--- geladen, fragt dieses Addon ihn zur Laufzeit nach dem Export der aktiven
--- Liste des eingeloggten Charakters — ueber seine eigene Funktion
--- Bis.Export(), dieselbe, die sein Export-Knopf benutzt. Nichts wird
--- kopiert; ohne FojjiCore gibt es diesen Weg nicht, dann bleibt das
--- Einfuegen des Textes.
--- @return table|nil fojjiBis
function Wishlist.FojjiApi()
    local ns = rawget(_G, "FojjiCoreNS")
    local dj = type(ns) == "table" and ns.DJ or nil
    local bis = type(dj) == "table" and dj.Bis or nil
    if type(bis) == "table" and type(bis.Export) == "function" then return bis end
    return nil
end

--- Der Name der aktiven FojjiCore-Liste, fuer die Anzeige; nil ohne FojjiCore.
function Wishlist.FojjiListName()
    local bis = Wishlist.FojjiApi()
    if not bis or type(bis.ActiveName) ~= "function" then return nil end
    local ok, name = pcall(bis.ActiveName)
    return ok and type(name) == "string" and name or nil
end

--- Alle BiS-Listen aus FojjiCore — aller Charaktere, nicht nur der aktiven.
---
--- NUR LESEN. FojjiCores eigene Bis.Lists() legt beim Aufruf Listen an und
--- stellt die aktive um; die wird hier nicht gerufen. Gelesen werden seine
--- gespeicherten Charaktere (FDJ.db.chars) mit ihren bisLists — oder, bei
--- aelteren Staenden, der einzelnen bis-Tabelle.
--- @return table { { charKey, char, class, me, index, list, spec, active, picks, count } }
function Wishlist.FojjiAllLists()
    local ns = rawget(_G, "FojjiCoreNS")
    local dj = type(ns) == "table" and ns.DJ or nil
    local chars = type(dj) == "table" and type(dj.db) == "table" and dj.db.chars or nil
    if type(chars) ~= "table" then return {} end
    local out = {}
    local function count(picks)
        local n = 0
        for key, ids in pairs(picks or {}) do
            if Wishlist.FOJJI_GROUPS[key] and type(ids) == "table" then n = n + #ids end
        end
        return n
    end
    for key, data in pairs(chars) do
        if type(key) == "string" and type(data) == "table" then
            local name = data.name or string.match(key, "^([^%-]+)") or key
            local me = key == dj.charKey
            local lists = type(data.bisLists) == "table" and data.bisLists or nil
            if not lists and type(data.bis) == "table" then lists = { { name = "BiS", picks = data.bis } } end
            for index, l in ipairs(lists or {}) do
                if type(l) == "table" and type(l.picks) == "table" then
                    local n = count(l.picks)
                    if n > 0 then
                        out[#out + 1] = { charKey = key, char = name, class = data.class, me = me, index = index,
                            list = tostring(l.name or "?"), spec = l.spec, picks = l.picks, count = n,
                            active = me and tonumber(data.bisActive) == index or nil }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if a.char ~= b.char then return a.char < b.char end
        return a.index < b.index
    end)
    return out
end

--- Eine gelesene Liste als Exporttext, im Format seines Export-Knopfs.
function Wishlist.FojjiText(picks, name)
    local parts = {}
    local keys = {}
    for key in pairs(Wishlist.FOJJI_GROUPS) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local ids = picks and picks[key]
        if type(ids) == "table" and #ids > 0 then
            local list = {}
            for i, id in ipairs(ids) do list[i] = tostring(tonumber(id) or "") end
            parts[#parts + 1] = key .. "=" .. table.concat(list, ",")
        end
    end
    if name and name ~= "" then parts[#parts + 1] = "name=" .. (string.gsub(name, "[%s;=]", "_")) end
    return "FCBIS1:" .. table.concat(parts, ";")
end

--- Uebernimmt eine Liste aus FojjiAllLists.
function Wishlist:ImportFojjiList(guid, entry)
    if type(entry) ~= "table" then return nil, "empty" end
    return self:ImportFojji(guid, self.FojjiText(entry.picks, entry.list))
end

--- Liest die aktive FojjiCore-Liste direkt und uebernimmt sie.
--- @return table|nil ergebnis, string|nil grund ("nofojji" | "fojjierror" | ...)
function Wishlist:ImportFojjiLive(guid)
    local bis = self.FojjiApi()
    if not bis then return nil, "nofojji" end
    local ok, text = pcall(bis.Export)
    if not ok or type(text) ~= "string" then return nil, "fojjierror" end
    return self:ImportFojji(guid, text)
end

function Wishlist:ReplaceBis(guid, slots)
    if not guid then return false end
    bisStore()[guid] = {}
    for slotID, itemID in pairs(slots or {}) do
        self:SetBis(guid, tonumber(slotID), tonumber(itemID), true)
    end
    GA.Core.Callbacks:Fire("WISHLIST_CHANGED", guid)
    return true
end

--- Wird das BiS-Teil getragen? Je Platz; Ring, Schmuck und Einhandwaffe
--- zaehlen auch auf dem Zwillingsplatz.
--- @return table { [slotID] = { itemID, worn, equipped } }, number getragen, number gesetzt
function Wishlist:BisStatus(guid)
    local character = guid and GA.Core.Database.account.characters[guid]
    local equipment = character and character.equipment or {}
    local list = self:Bis(guid)
    local out, worn, set = {}, 0, 0
    local function wearing(slotID, itemID)
        local here = equipment[slotID]
        if here and here.itemID == itemID then return true end
        local twin = TWIN_SLOT[slotID]
        local there = twin and equipment[twin]
        return there ~= nil and there.itemID == itemID
    end
    for _, slotID in ipairs(self.BIS_SLOTS) do
        local entry = list[slotID]
        local hit = entry ~= nil and wearing(slotID, entry.itemID)
        out[slotID] = { itemID = entry and entry.itemID or nil, worn = hit,
                        equipped = equipment[slotID] and equipment[slotID].itemID or nil }
        if entry then
            set = set + 1
            if hit then worn = worn + 1 end
        end
    end
    return out, worn, set
end

--- Wer hat diesen Gegenstand als BiS? Fuer ForItem.
local function bisHolders(itemID)
    local out = {}
    for guid, slots in pairs(bisStore()) do
        for _, entry in pairs(slots) do
            if entry.itemID == itemID then out[guid] = true break end
        end
    end
    return out
end

--- Wer haette diesen Gegenstand gern? Ueber alle bekannten Charaktere.
--- @return table { { guid, name, class, priority, weight, note, fulfilled, playerId } }
function Wishlist:ForItem(itemID)
    itemID = tonumber(itemID)
    if not itemID then return {} end

    local characters = GA.Core.Database.account.characters
    local out = {}

    for guid, list in pairs(store()) do
        for _, entry in ipairs(list) do
            if entry.itemID == itemID then
                local character = characters[guid]
                out[#out + 1] = {
                    guid = guid,
                    name = character and Util.ShortName(character.name or "?") or "?",
                    class = character and character.class or nil,
                    playerId = character and character.playerId or nil,
                    priority = entry.priority,
                    weight = weightOf(entry.priority),
                    note = entry.note,
                    fulfilled = entry.fulfilledByAwardId ~= nil,
                }
            end
        end
    end

    -- Best in Slot zaehlt als Wunsch: Wer das Teil auf seiner Liste hat,
    -- steht hier mit "BIS" — sofern er es nicht ohnehin als Wunsch fuehrt.
    local seen = {}
    for _, entry in ipairs(out) do seen[entry.guid] = true end
    for guid in pairs(bisHolders(itemID)) do
        if not seen[guid] then
            local character = characters[guid]
            local status = self:BisStatus(guid)
            local worn = false
            for _, st in pairs(status) do
                if st.itemID == itemID and st.worn then worn = true end
            end
            out[#out + 1] = {
                guid = guid,
                name = character and Util.ShortName(character.name or "?") or "?",
                class = character and character.class or nil,
                playerId = character and character.playerId or nil,
                priority = "BIS", weight = weightOf("BIS"), bis = true,
                fulfilled = worn,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.fulfilled ~= b.fulfilled then return b.fulfilled end
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.name < b.name
    end)
    return out
end

--- Der Eintrag eines bestimmten Spielers fuer einen Gegenstand — fuer den
--- Hinweis in der Council-Ansicht. Gesucht wird ueber den NAMEN, weil eine
--- Bewerbung nur den Namen mitbringt.
function Wishlist:ForCandidate(itemID, candidateName)
    if not candidateName then return nil end
    local wanted = Util.ShortName(candidateName)
    for _, entry in ipairs(self:ForItem(itemID)) do
        if entry.name == wanted then return entry end
    end
    return nil
end

-- ================================================================== Erfuellung

--- Markiert einen Wunsch als erfuellt, wenn eine Vergabe ihn trifft.
---
--- Gesucht wird NUR beim empfangenden Charakter, nicht bei den Twinks desselben
--- Spielers: Dass der Main sich den Gegenstand gewuenscht hat, macht ihn nicht
--- zum Wunsch des Twinks, der ihn bekommen hat. Der Zusammenhang gehoert in die
--- Auswertung, nicht in eine stille Verknuepfung.
--- @return boolean getroffen
function Wishlist:MatchAward(award)
    if not award or not award.itemID or not award.recipientGuid then return false end

    local entry = self:Find(award.recipientGuid, award.itemID)
    if not entry or entry.fulfilledByAwardId then return false end

    entry.fulfilledByAwardId = award.id
    entry.fulfilledTs = Util.Now()

    GA.Core.Database:Journal("WISH_FULFILLED", award.recipientGuid, award.itemID, award.id)
    GA.Core.Callbacks:Fire("WISHLIST_CHANGED", award.recipientGuid)
    Debug:Print("loot", "Wunsch erfuellt: %s an %s", tostring(award.itemName),
        tostring(award.recipientName))
    return true
end

function Wishlist:Stats(guid)
    local open, fulfilled = 0, 0
    for _, entry in ipairs(store()[guid] or {}) do
        if entry.fulfilledByAwardId then fulfilled = fulfilled + 1 else open = open + 1 end
    end
    return { open = open, fulfilled = fulfilled, total = open + fulfilled }
end

-- ================================================================== Start ------

function Wishlist:OnEnable()
    -- Eine Vergabe erfuellt einen Wunsch erst, wenn sie BESTAETIGT ist. Beim
    -- blossen Zuschlag koennte die Uebergabe noch scheitern.
    GA.Core.Callbacks:On("AWARD_CHANGED", function(awardId, _, newStatus)
        if newStatus ~= Schema.LootStatus.RECEIVED then return end
        local award = GA.Modules.Awards:Get(awardId)
        if award then Wishlist:MatchAward(award) end
    end, "Wishlist")
end
