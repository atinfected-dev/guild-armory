--[[----------------------------------------------------------------------------
    Database/ItemIndex — der Gegenstandsverzeichnis dieses Clients.

    Kein UI. Merkt sich zu jeder Item-ID, die der Client jemals aufgeloest hat,
    Name, Symbol, Qualitaet, Platz und Itemlevel — damit man einen Gegenstand
    spaeter ueber den NAMEN finden kann.

    WARUM ES DAS BRAUCHT:

      Ein Addon kann keine HTTP-Anfragen stellen. Es gibt keine Wowhead-Abfrage
      zur Laufzeit, von keinem Addon — der Client stellt dafuer keine
      Schnittstelle bereit. Eine Namenssuche muss deshalb aus dem kommen, was
      auf diesem Rechner schon vorhanden ist.

      Und davon gibt es reichlich: GET_ITEM_INFO_RECEIVED feuerte in der Messung
      vom 19.09.2026 allein beim Einloggen 278-mal. Jedes dieser Ereignisse ist
      ein Gegenstand, dessen Daten der Client gerade geladen hat. Dazu kommen
      Taschen, angelegte Ausruestung, Beute und Inspect-Ergebnisse.

    EHRLICH BLEIBT DABEI: Das Verzeichnis kennt nur, was dieser Client gesehen
    hat. Es ist kein vollstaendiger Itemkatalog und gibt auch nicht vor, einer
    zu sein — die Oberflaeche sagt, wie viele Gegenstaende darin stehen, und
    weist bei einer erfolglosen Suche auf den Weg hin, der IMMER geht: den
    Wowhead-Link einfuegen.

    Das Verzeichnis waechst mit der Zeit und ueber alle Charaktere eines
    Accounts hinweg, weil es in den kontoweiten SavedVariables liegt.
------------------------------------------------------------------------------]]

local _, GA = ...

local ItemIndex = {}
GA.Modules.ItemIndex = ItemIndex

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Obergrenze. Ein Eintrag kostet grob 80 Byte; 4000 sind rund 300 KB in der
--- SavedVariables-Datei — genug fuer jeden Gegenstand, den eine Gilde je
--- anfasst, und klein genug, dass das Laden nicht auffaellt.
local LIMIT = 4000
local PRUNE_TO = 3500

local function store()
    return GA.Core.Database.account.items
end

-- ================================================================== Lernen ----

--- Nimmt einen Gegenstand ins Verzeichnis auf.
--- @return boolean neu
function ItemIndex:Learn(itemID, info)
    itemID = tonumber(itemID)
    if not itemID then return false end

    info = info or Compat.GetItemInfo(itemID)
    -- Ohne Namen ist der Eintrag fuer eine Namenssuche wertlos. Dann lieber
    -- gar nichts speichern als einen Platzhalter, der nie gefunden wird.
    if not info or not info.name or info.name == "" then return false end

    local items = store()
    local existing = items[itemID]
    if existing then
        existing.ts = Util.Now()
        -- Nachtragen, was beim ersten Mal noch fehlte.
        existing.icon = existing.icon or info.icon
        existing.quality = existing.quality or info.quality
        existing.equipLoc = existing.equipLoc or info.equipLoc
        existing.level = existing.level or info.itemLevel
        return false
    end

    items[itemID] = {
        name = info.name,
        icon = info.icon,
        quality = info.quality,
        equipLoc = info.equipLoc,
        level = info.itemLevel,
        ts = Util.Now(),
    }

    self.count = (self.count or 0) + 1
    if self.count > LIMIT then self:Prune() end
    return true
end

--- Wirft die aeltesten Eintraege weg, wenn die Grenze ueberschritten ist.
--- Selten genug, dass ein Sortierdurchlauf nicht ins Gewicht faellt.
function ItemIndex:Prune()
    local items = store()

    local order = {}
    for itemID, entry in pairs(items) do
        order[#order + 1] = { id = itemID, ts = entry.ts or 0 }
    end
    if #order <= PRUNE_TO then
        self.count = #order
        return
    end

    table.sort(order, function(a, b) return a.ts > b.ts end)
    for index = PRUNE_TO + 1, #order do
        items[order[index].id] = nil
    end

    self.count = PRUNE_TO
    Debug:Print("core", "Itemverzeichnis gekuerzt auf %d Eintraege", PRUNE_TO)
end

function ItemIndex:Count()
    if self.count then return self.count end
    local count = 0
    for _ in pairs(store()) do count = count + 1 end
    self.count = count
    return count
end

function ItemIndex:Get(itemID)
    return store()[tonumber(itemID or 0)]
end

-- ================================================================== Suchen ----

--- Sucht nach Namensbestandteil.
---
--- RANGFOLGE: exakter Treffer, dann Namensanfang, dann Vorkommen irgendwo;
--- innerhalb davon nach Qualitaet absteigend und dann nach Name. Ohne feste
--- Rangfolge waere die Trefferliste bei jedem Aufruf anders sortiert, weil
--- pairs() keine Reihenfolge garantiert.
--- @return table { { itemID, name, icon, quality, equipLoc, level } }
function ItemIndex:Search(text, limit)
    limit = limit or 20
    if type(text) ~= "string" then return {} end

    local needle = string.lower(string.gsub(text, "^%s*(.-)%s*$", "%1"))
    if needle == "" or #needle < 2 then return {} end

    local matches = {}
    for itemID, entry in pairs(store()) do
        local name = string.lower(entry.name or "")
        local rank
        if name == needle then rank = 3
        elseif string.sub(name, 1, #needle) == needle then rank = 2
        elseif string.find(name, needle, 1, true) then rank = 1 end

        if rank then
            matches[#matches + 1] = {
                itemID = itemID,
                name = entry.name,
                icon = entry.icon,
                quality = entry.quality,
                equipLoc = entry.equipLoc,
                level = entry.level,
                rank = rank,
            }
        end
    end

    table.sort(matches, function(a, b)
        if a.rank ~= b.rank then return a.rank > b.rank end
        if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
        return a.name < b.name
    end)

    while #matches > limit do matches[#matches] = nil end
    return matches
end

-- ================================================================== Quellen ---

--- Taschen durchgehen. Einmal beim Start — das kostet wenig und bringt sofort
--- alles ein, was der Spieler mit sich herumtraegt.
function ItemIndex:SweepBags()
    local container = _G.C_Container
    local getLink = (type(container) == "table" and container.GetContainerItemLink)
        or _G.GetContainerItemLink
    local getSlots = (type(container) == "table" and container.GetContainerNumSlots)
        or _G.GetContainerNumSlots
    if type(getLink) ~= "function" or type(getSlots) ~= "function" then return 0 end

    local learned = 0
    -- 0 = Rucksack, 1..4 = angelegte Taschen. Weiter zu zaehlen schadet nicht:
    -- Ein nicht vorhandener Behaelter liefert einfach 0 Plaetze.
    for bag = 0, 5 do
        local okSlots, slots = pcall(getSlots, bag)
        if okSlots and slots and slots > 0 then
            for slot = 1, slots do
                local okLink, link = pcall(getLink, bag, slot)
                if okLink and link then
                    local parsed = Compat.ParseItemLink(link)
                    if parsed and parsed.itemID and self:Learn(parsed.itemID) then
                        learned = learned + 1
                    end
                end
            end
        end
    end
    return learned
end

--- Alles aus einem Ausruestungsstand aufnehmen.
function ItemIndex:LearnEquipment(equipment)
    local learned = 0
    for _, entry in pairs(equipment or {}) do
        if entry.itemID and self:Learn(entry.itemID, {
            name = entry.name, icon = entry.icon,
            quality = entry.quality, equipLoc = entry.equipLoc,
            itemLevel = entry.itemLevel,
        }) then
            learned = learned + 1
        end
    end
    return learned
end

-- ================================================================== Start ------

function ItemIndex:OnEnable()
    local Events = GA.Core.Events

    -- Die ergiebigste Quelle: Der Client meldet jede Iteminfo, die er laedt.
    -- Beim Einloggen sind das dreistellig viele, voellig umsonst.
    Events:Register("GET_ITEM_INFO_RECEIVED", function(_, itemID)
        ItemIndex:Learn(itemID)
    end, "ItemIndex")

    Events:Register("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
        if success ~= false then ItemIndex:Learn(itemID) end
    end, "ItemIndex")

    -- Was der Spieler bei sich hat, und was er anlegt.
    GA.Core.Callbacks:On("EQUIPMENT_UPDATED", function(guid)
        local character = guid and GA.Core.Database.account.characters[guid]
        if character then ItemIndex:LearnEquipment(character.equipment) end
    end, "ItemIndex")

    Events:Register("BAG_UPDATE_DELAYED", function()
        if ItemIndex.bagsPending then return end
        ItemIndex.bagsPending = true
        Compat.After(2, function()
            ItemIndex.bagsPending = false
            ItemIndex:SweepBags()
        end)
    end, "ItemIndex")

    -- Erkannte Beute ist besonders wertvoll: genau die Gegenstaende, um die es
    -- in der Gilde geht.
    GA.Core.Callbacks:On("AWARD_CREATED", function(awardId)
        local award = GA.Modules.Awards:Get(awardId)
        if award and award.itemID then
            ItemIndex:Learn(award.itemID, {
                name = award.itemName, quality = award.quality,
            })
        end
    end, "ItemIndex")

    Compat.After(3, function()
        local learned = ItemIndex:SweepBags()
        Debug:Print("core", "Itemverzeichnis: %d Eintraege (%d aus den Taschen)",
            ItemIndex:Count(), learned)
    end)
end
