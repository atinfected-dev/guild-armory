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
            entry.note = note
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
