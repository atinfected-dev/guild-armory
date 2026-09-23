--[[----------------------------------------------------------------------------
    LootHistory/Handover — was noch in meinen Taschen liegt und jemandem gehoert.

    Kein UI. Gleicht offene Vergaben gegen den eigenen Taschenbestand ab und
    meldet, was noch uebergeben werden muss.

    WOZU:

      Die Statusmaschine kennt TRANSFER_PENDING seit Phase 5, aber niemand hat
      je in die Taschen geschaut. Der Lootmeister musste selbst daran denken,
      dass er noch drei Gegenstaende mit sich herumtraegt, die anderen
      gehoeren. Am Ende eines Raidabends erinnert sich daran niemand, und der
      Gegenstand taucht drei Wochen spaeter beim Ausmisten wieder auf.

    DIE EINE ENTSCHEIDUNG, DIE HIER ZAEHLT:

      EIN GEGENSTAND IN DER TASCHE IST EIN HINWEIS, KEIN BEWEIS.

      Das Addon sieht nur: "Gegenstand 19019 liegt in Tasche 1, Platz 4" und
      "es gibt eine offene Vergabe von 19019 an Carla". Ob das DERSELBE
      Gegenstand ist, weiss es nicht — es koennte ein zweiter sein, ein
      laengst gekaufter, einer aus einer anderen Gruppe.

      Deshalb wird hier nichts automatisch als uebergeben oder als erhalten
      markiert. Die Liste ist eine ERINNERUNG, und die Bestaetigung bleibt,
      wo sie seit Phase 5 liegt: bei Awards:Confirm mit einer Bestaetigungsart.
      Ein Addon, das aus "liegt in der Tasche" ein "wurde uebergeben" macht,
      faengt genau hier an zu luegen.

    WAS DAGEGEN BELEGBAR IST:

      Verschwindet ein Gegenstand aus den Taschen, WAEHREND ein Handel mit dem
      Empfaenger offen war, ist das ein starker Hinweis. Diesen Fall behandelt
      LootTracker ueber TRADE_ACCEPT_UPDATE — nicht diese Datei.
------------------------------------------------------------------------------]]

local _, GA = ...

local Handover = {}
GA.Modules.Handover = Handover

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

local Schema = GA.Data.Schema
local Status = Schema.LootStatus

--- Wie lange nach der Vergabe erinnert wird. Danach ist der Gegenstand
--- vermutlich laengst uebergeben und nur nie bestaetigt worden — eine
--- Erinnerung nach zwei Wochen hilft niemandem mehr.
local REMIND_DAYS = 14

--- Abstand zwischen zwei Erinnerungen im Chat.
local REMIND_INTERVAL = 900

Handover.lastReminder = 0

-- ================================================================== Abgleich --

--- Offene Vergaben, bei denen ICH der Lootmeister bin und die noch nicht
--- bestaetigt sind.
local function openAwards()
    local own = Compat.GetPlayerIdentity().guid
    local cutoff = Util.Now() - REMIND_DAYS * 86400
    local out = {}

    for _, award in pairs(GA.Core.Database.account.awards) do
        local open = award.status == Status.AWARDED
            or award.status == Status.TRANSFER_PENDING
        -- EIN FEHLENDES lootMasterGuid IST KEIN EIGENTUMSNACHWEIS — dieselbe
        -- Falle wie in Communication/Sync (Kapitel 9.2). Ein Datensatz, der
        -- ueber den Abgleich oder aus einer Sicherung kam, hat keins, und
        -- ohne diese Zeile stuende fremder Loot auf meiner Uebergabeliste.
        local foreign = award.source == "sync" or award.source == "import"
        local mine = not foreign
            and (award.lootMasterGuid == nil or award.lootMasterGuid == own)

        if open and mine and award.itemID and award.recipientName
            and (award.awardedTs or award.ts or 0) >= cutoff
            -- An mich selbst gibt es nichts zu uebergeben.
            and Util.NormalizeName(award.recipientName)
                ~= Util.NormalizeName(Compat.GetPlayerIdentity().name or "")
        then
            out[#out + 1] = award
        end
    end
    return out
end

--- Was liegt in den Taschen, das jemandem gehoert?
---
--- @return table liste { award, link, bag, slot }, table fehlend
function Handover:Pending()
    local awards = openAwards()
    if #awards == 0 then return {}, {} end

    -- Taschenbestand nach ItemID, mit Anzahl: Zwei gleiche Gegenstaende
    -- koennen zwei verschiedenen Leuten gehoeren.
    local inBags = {}
    for _, item in ipairs(Compat.GetBagItems()) do
        local bucket = inBags[item.itemID]
        if not bucket then bucket = {} inBags[item.itemID] = bucket end
        bucket[#bucket + 1] = item
    end

    -- Aelteste Vergabe zuerst: Wer am laengsten wartet, steht oben.
    table.sort(awards, function(a, b)
        return (a.awardedTs or a.ts or 0) < (b.awardedTs or b.ts or 0)
    end)

    local carrying, missing = {}, {}
    for _, award in ipairs(awards) do
        local bucket = inBags[award.itemID]
        local item = bucket and table.remove(bucket, 1)

        if item then
            carrying[#carrying + 1] = {
                award = award, itemID = award.itemID,
                link = item.link, bag = item.bag, slot = item.slot,
                to = award.recipientName,
                age = Util.Now() - (award.awardedTs or award.ts or Util.Now()),
            }
        else
            -- Nicht (mehr) in den Taschen. Das heisst NICHT "uebergeben":
            -- Der Gegenstand kann in der Bank liegen, angelegt sein, oder der
            -- Empfaenger hat ihn selbst aufgenommen. Deshalb eine eigene Liste
            -- und keine Statusaenderung.
            missing[#missing + 1] = {
                award = award, itemID = award.itemID, to = award.recipientName,
                age = Util.Now() - (award.awardedTs or award.ts or Util.Now()),
            }
        end
    end

    return carrying, missing
end

function Handover:Count()
    local carrying = self:Pending()
    return #carrying
end

-- ================================================================== Hinweis ---

--- Eine Zeile im eigenen Chatfenster. Nicht im Gildenchat, nicht im Raid:
--- Das ist eine Notiz an den Lootmeister, keine Bekanntmachung.
function Handover:Remind(force)
    local now = Util.Now()
    if not force and (now - self.lastReminder) < REMIND_INTERVAL then return false end

    local carrying = self:Pending()
    if #carrying == 0 then return false end

    self.lastReminder = now

    local names = {}
    for index = 1, math.min(#carrying, 3) do
        names[#names + 1] = string.format("%s (%s)",
            carrying[index].link or tostring(carrying[index].itemID),
            tostring(carrying[index].to))
    end
    local text = table.concat(names, ", ")
    if #carrying > 3 then
        text = text .. string.format(GA.L.HANDOVER_MORE, #carrying - 3)
    end

    Debug:Info(GA.L.HANDOVER_REMIND, #carrying, text)
    GA.Core.Callbacks:Fire("HANDOVER_CHANGED")
    return true
end

-- ================================================================== Start ------

-- ============================================================ Handelsfenster --

--- Wie viele Plaetze ein Handelsfenster hat, ohne den letzten.
---
--- Platz 7 ist "wird nicht gehandelt" — dort liegt, was der Partner sehen,
--- aber nicht bekommen soll. Da hinein etwas zu legen, waere das Gegenteil
--- einer Uebergabe.
local TRADE_SLOTS = 6

--- Legt beim Oeffnen eines Handels das hinein, was diesem Partner gehoert.
---
--- WAS DAS TUT UND WAS NICHT.
---
--- Es fuellt das Fenster. Es handelt NICHT: Beide Seiten muessen weiterhin
--- selbst bestaetigen, und bis dahin ist jeder Schritt zuruecknehmbar. Und
--- es markiert nichts als uebergeben — ein Gegenstand im Handelsfenster ist
--- immer noch kein Beweis, sondern eine Absicht. Bestaetigt wird, wie seit
--- jeher, ueber TRADE_ACCEPT_UPDATE im LootTracker.
---
--- WER GENAU. Nur Vergaben an DIESEN Partner, Name auf Name. Ein Abgleich
--- ueber die GUID waere schoener, aber das Handelsfenster gibt nur den
--- Namen her — und ein falsch zugeordneter Gegenstand wandert hier nicht
--- in eine Liste, sondern in fremde Taschen.
---
--- @return number gelegt, string|nil grund
function Handover:FillTrade()
    if GA.Core.Config:Get("autoTrade") == false then return 0, "aus" end

    local partner = Compat.GetTradePartner()
    if not partner or partner == "" then return 0, "kein Partner" end

    -- Auf denselben Stand kuerzen wie die Vergaben: Dort stehen die Namen
    -- ohne Realm.
    local kurz = Util.ShortName(partner)

    local carrying = self:Pending()
    local gelegt = 0

    for _, entry in ipairs(carrying) do
        if gelegt >= TRADE_SLOTS then break end
        if entry.to and Util.ShortName(entry.to) == kurz then
            if Compat.PlaceInTrade(entry.bag, entry.slot, gelegt + 1) then
                gelegt = gelegt + 1
            end
        end
    end

    if gelegt > 0 then
        Debug:Info(GA.L.HANDOVER_FILLED, gelegt, kurz)
    end
    return gelegt
end

function Handover:OnEnable()
    -- Beim Wechsel des Taschenbestands neu rechnen — aber gedrosselt, denn
    -- BAG_UPDATE_DELAYED feuert beim Plündern im Sekundentakt.
    GA.Core.Events:Register("BAG_UPDATE_DELAYED", function()
        if Handover.pending then return end
        Handover.pending = true
        Compat.After(3, function()
            Handover.pending = false
            GA.Core.Callbacks:Fire("HANDOVER_CHANGED")
        end)
    end, "Handover")

    -- Beim Verlassen der Gruppe ist der Anlass da: Der Raid ist vorbei, und
    -- was jetzt noch in den Taschen liegt, geht so schnell nicht mehr weg.
    --
    -- Erkannt wird das ueber GROUP_ROSTER_UPDATE und IsInGroup, nicht ueber
    -- GROUP_LEFT: Das Ereignis gibt es in Retail, auf Forever ist es
    -- ungemessen. GROUP_ROSTER_UPDATE ist gemessen (Communication/Sync nutzt
    -- es seit Phase 7), und der Uebergang von "in einer Gruppe" zu "nicht
    -- mehr" ist daraus ablesbar.
    -- Handelsfenster: Was diesem Partner gehoert, gleich hineinlegen.
    --
    -- Mit kurzer Verzoegerung: TRADE_SHOW feuert, waehrend das Fenster noch
    -- aufgebaut wird, und ein ClickTradeButton auf einen Platz, den es noch
    -- nicht gibt, geht ins Leere. Eine Zehntelsekunde reicht und ist nicht
    -- zu merken.
    GA.Core.Events:Register("TRADE_SHOW", function()
        Compat.After(0.1, function() Handover:FillTrade() end)
    end, "Handover")

    Handover.wasInGroup = Compat.IsInGroup()
    GA.Core.Events:Register("GROUP_ROSTER_UPDATE", function()
        local inGroup = Compat.IsInGroup()
        local left = Handover.wasInGroup and not inGroup
        Handover.wasInGroup = inGroup
        if left then
            Compat.After(5, function() Handover:Remind(true) end)
        end
    end, "Handover")
end
