--[[----------------------------------------------------------------------------
    LootHistory/Awards — Vergaben und ihre Statusmaschine.

    Kein UI, keine Spiel-API. Reine Logik auf der Datenbank — und genau deshalb
    in tools/test/awards.test.js testbar.

    DIE REGEL, DIE DIESES MODUL DURCHSETZT (Vorgabe, Abschnitt 7):

      Eine Vergabe gilt NIE als erhalten, nur weil ein Gewinner feststeht.
      RECEIVED erreicht man ausschliesslich ueber Confirm() mit einer
      ausdruecklichen Bestaetigungsart — und "von Hand bestaetigt" (MANUAL)
      bleibt als solche im Datensatz stehen, sichtbar in der Historie.

    Jeder Statuswechsel:
      - wird gegen Schema.LootTransitions geprueft. Ein unerlaubter Wechsel
        wird abgelehnt und gemeldet, nicht stillschweigend ausgefuehrt.
      - landet in award.statusHistory mit Zeitstempel, Urheber und Grund.
      - landet im Journal der Datenbank.

    Eine Korrektur loescht nichts. Sie schreibt den neuen Stand, markiert den
    alten als CORRECTED und behaelt beide in der Historie — sonst liesse sich
    hinterher nicht mehr zeigen, was urspruenglich vergeben wurde.
------------------------------------------------------------------------------]]

local _, GA = ...

local Awards = {}
GA.Modules.Awards = Awards

local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Schema = GA.Data.Schema

local Status = Schema.LootStatus

--- Status, in denen eine Vergabe noch Arbeit macht.
local OPEN_STATUS = {
    [Status.DETECTED] = true,
    [Status.SESSION_OPEN] = true,
    [Status.AWARDED] = true,
    [Status.TRANSFER_PENDING] = true,
}

local function store()
    return GA.Core.Database.account.awards
end

-- ================================================================== Anlegen ---

--- Legt eine Vergabe im Status DETECTED an.
--- @param item table { itemID, link, name, quality, quantity }
--- @param context table|nil { sourceGuid, sourceNpcID, sourceName, encounterID,
---        encounterName, zone, instanceName, lootMethod, slot, difficultyID }
--- @return table award
function Awards:Create(item, context)
    context = context or {}

    local award = {
        id = Util.NewId("a"),
        ts = Util.Now(),

        itemID = item.itemID,
        itemLink = item.link,
        itemName = item.name,
        quality = item.quality,
        quantity = item.quantity or 1,

        -- Herkunft. Nichts davon wird geraten: Was nicht gemessen wurde,
        -- bleibt nil — siehe LootHistory/LootTracker.lua.
        sourceGuid = context.sourceGuid,
        sourceNpcID = context.sourceNpcID,
        sourceName = context.sourceName,
        encounterID = context.encounterID,
        encounterName = context.encounterName,
        difficultyID = context.difficultyID,
        instanceName = context.instanceName,
        zone = context.zone,
        lootMethod = context.lootMethod,
        slot = context.slot,

        status = Status.DETECTED,
        statusHistory = {
            { status = Status.DETECTED, ts = Util.Now(), by = context.by, reason = context.reason },
        },
        votes = {},
    }

    store()[award.id] = award
    GA.Core.Database:Journal("LOOT_DETECTED", award.id, nil,
        { item = item.link or item.itemID, source = context.sourceName or context.sourceNpcID })
    GA.Core.Callbacks:Fire("AWARD_CREATED", award.id)
    return award
end

--- Gibt es fuer diesen Fund schon eine Vergabe?
---
--- GEMELDET 26.09.2026: "es wird auch 4 fach detected."
---
--- Der Schutz dagegen hing am SLOT und wurde bei LOOT_CLOSED geleert. Wer
--- eine Leiche Stueck fuer Stueck ausraeumt, schliesst und oeffnet das
--- Fenster mehrfach — und beim naechsten Oeffnen war alles wieder neu.
--- LOOT_OPENED und LOOT_READY feuern ausserdem beide.
---
--- Gefragt wird deshalb die Datenbank, nicht ein Merkzettel: Sie ueberlebt
--- das Schliessen des Fensters, einen /reload und den Abend.
---
--- WAS DERSELBE FUND IST: dieselbe Leiche, derselbe Platz darin, dasselbe
--- Item. Zwei gleiche Teile aus einer Leiche liegen auf zwei Plaetzen und
--- bleiben deshalb zwei Funde — das kommt vor, und eines davon zu
--- verschlucken waere schlimmer als ein Eintrag zu viel.
---
--- OHNE HERKUNFT NUR KURZ. Ist die Leiche unbekannt, bleibt als Merkmal nur
--- Platz und Item, und das trifft irgendwann auch eine andere Leiche.
--- Innerhalb einer Minute ist das derselbe Fund; danach wird lieber doppelt
--- erfasst als etwas Echtes verworfen.
--- @return table|nil vorhandene
function Awards:FindDuplicate(item, context)
    if not item or not item.itemID then return nil end
    context = context or {}

    local jetzt = Util.Now()
    local fenster = context.sourceGuid and 3600 or 60

    for _, award in pairs(store()) do
        if award.itemID == item.itemID
            and award.status == Status.DETECTED
            and award.slot == context.slot
            and (jetzt - (award.ts or 0)) <= fenster
        then
            if context.sourceGuid and award.sourceGuid then
                if award.sourceGuid == context.sourceGuid then return award end
            elseif not context.sourceGuid and not award.sourceGuid then
                return award
            end
        end
    end
    return nil
end

--- Alle Eintraege, die denselben Fund ein zweites Mal beschreiben.
---
--- FUER DAS AUFRAEUMEN VON GESTERN. Die Regel oben verhindert neue Doppel;
--- die alten stehen weiter da — nach einem Abend waren es fuenfmal dieselben
--- Armschienen in einer Liste von 22.
---
--- DER AELTESTE BLEIBT. Er trägt die erste Messung, und alles, was daran
--- haengt — Gebote, Stimmen —, haengt an seiner Kennung.
---
--- NUR WAS NOCH NICHT VERGEBEN IST. Ein vergebener Eintrag ist Geschichte,
--- auch wenn er wie ein Doppel aussieht; wer den wegraeumt, aendert, was
--- jemand bekommen hat.
--- @return table Liste der ueberzaehligen Eintraege
function Awards:FindDuplicates()
    local nach, ueberzaehlig = {}, {}

    for _, award in pairs(store()) do
        if award.status == Status.DETECTED or award.status == Status.SESSION_OPEN then
            -- OHNE HERKUNFT KEIN URTEIL. Zwei Funde desselben Teils ohne
            -- bekannte Leiche koennen zwei echte Funde sein, und hier wird
            -- geloescht — im Zweifel bleibt beides stehen.
            if award.itemID and award.sourceGuid and award.slot then
                local key = award.sourceGuid .. ":" .. tostring(award.slot)
                    .. ":" .. tostring(award.itemID)
                local erster = nach[key]
                if not erster then
                    nach[key] = award
                elseif (award.ts or 0) < (erster.ts or 0) then
                    nach[key] = award
                    ueberzaehlig[#ueberzaehlig + 1] = erster
                else
                    ueberzaehlig[#ueberzaehlig + 1] = award
                end
            end
        end
    end

    table.sort(ueberzaehlig, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return ueberzaehlig
end

function Awards:Get(awardId)
    return awardId and store()[awardId] or nil
end

-- ================================================================== Wechsel ---

--- Fuehrt einen Statuswechsel aus, wenn er erlaubt ist.
--- @param options table|nil { by, reason, silent }
--- @return boolean ok, string|nil grund
function Awards:Transition(awardId, newStatus, options)
    options = options or {}
    local award = self:Get(awardId)
    if not award then return false, "unknown" end

    local allowed = Schema.LootTransitions[award.status]
    if not allowed then return false, "badstate" end
    if not allowed[newStatus] then
        -- Kein Sonderfall, kein stilles Durchwinken: Ein verbotener Wechsel
        -- ist ein Fehler im aufrufenden Code oder eine falsche Bedienung.
        Debug:Print("loot", "Wechsel abgelehnt: %s -> %s (%s)",
            tostring(award.status), tostring(newStatus), tostring(awardId))
        return false, "forbidden"
    end

    local before = award.status
    award.status = newStatus
    award.statusHistory[#award.statusHistory + 1] = {
        status = newStatus,
        ts = Util.Now(),
        by = options.by,
        reason = options.reason,
    }

    GA.Core.Database:Journal("LOOT_STATUS", awardId, before, newStatus, options.by)
    if not options.silent then
        GA.Core.Callbacks:Fire("AWARD_CHANGED", awardId, before, newStatus)
    end
    return true
end

--- Setzt den Empfaenger und geht auf AWARDED.
--- @param recipient table { guid, name, response, note }
function Awards:Award(awardId, recipient, options)
    options = options or {}
    local award = self:Get(awardId)
    if not award then return false, "unknown" end
    if not recipient or not recipient.name then return false, "norecipient" end

    -- Aus DETECTED heraus geht es laut Statusmaschine nur ueber SESSION_OPEN.
    -- Ohne Council (Direktvergabe durch den Lootmeister) wird die Session
    -- stillschweigend geoeffnet und sofort geschlossen — der Weg bleibt in der
    -- Historie sichtbar, statt die Maschine zu umgehen.
    if award.status == Status.DETECTED then
        local ok, reason = self:Transition(awardId, Status.SESSION_OPEN,
            { by = options.by, reason = options.reason or "Direktvergabe", silent = true })
        if not ok then return false, reason end
    end

    local ok, reason = self:Transition(awardId, Status.AWARDED, options)
    if not ok then return false, reason end

    award.recipientGuid = recipient.guid
    award.recipientName = recipient.name
    award.response = recipient.response
    award.note = recipient.note
    award.lootMasterGuid = options.by
    award.lootMasterName = options.byName
    award.awardedTs = Util.Now()

    GA.Core.Database:Journal("LOOT_AWARD", awardId, nil,
        { to = recipient.name, response = recipient.response })
    return true
end

--- Die Uebergabe steht aus (kein Master Loot verfuegbar oder Empfaenger
--- ausserhalb der Reichweite).
function Awards:MarkTransferPending(awardId, options)
    return self:Transition(awardId, Status.TRANSFER_PENDING, options)
end

--- DER EINZIGE WEG NACH RECEIVED. Ohne Bestaetigungsart passiert nichts.
--- @param confirmation string Schema.Confirmation.*
function Awards:Confirm(awardId, confirmation, options)
    options = options or {}
    local award = self:Get(awardId)
    if not award then return false, "unknown" end

    if not confirmation or not Schema.Confirmation[confirmation] then
        -- Genau hier wuerde ein Addon sonst anfangen zu luegen.
        return false, "noconfirmation"
    end
    if not award.recipientName then return false, "norecipient" end

    local ok, reason = self:Transition(awardId, Status.RECEIVED, options)
    if not ok then return false, reason end

    award.confirmation = confirmation
    award.confirmedTs = Util.Now()

    GA.Core.Database:Journal("LOOT_RECEIVED", awardId, nil,
        { to = award.recipientName, confirmation = confirmation })
    return true
end

--- Spaeter im Ausruestungsstand des Empfaengers aufgetaucht.
function Awards:MarkEquipped(awardId, options)
    local award = self:Get(awardId)
    if not award then return false, "unknown" end

    local ok, reason = self:Transition(awardId, Status.EQUIPPED, options)
    if not ok then return false, reason end
    award.equippedTs = Util.Now()
    return true
end

function Awards:Cancel(awardId, reason, by)
    return self:Transition(awardId, Status.CANCELLED, { by = by, reason = reason })
end

--- Korrektur: Der alte Datensatz bleibt als CORRECTED stehen und verweist auf
--- den neuen. So laesst sich hinterher zeigen, was urspruenglich vergeben wurde
--- und wer es geaendert hat (Vorgabe, Abschnitt 7 und 14).
--- @param changes table Felder, die im NEUEN Datensatz anders sind
--- @return table|nil neueVergabe, string|nil grund
function Awards:Correct(awardId, changes, reason, by)
    local award = self:Get(awardId)
    if not award then return nil, "unknown" end

    local replacement = Util.DeepCopy(award)
    replacement.id = Util.NewId("a")
    replacement.correctionOf = awardId
    replacement.statusHistory = {
        { status = award.status, ts = Util.Now(), by = by,
          reason = reason or "Korrektur von " .. tostring(awardId) },
    }
    for key, value in pairs(changes or {}) do
        replacement[key] = value
    end

    local ok, failure = self:Transition(awardId, Status.CORRECTED, { by = by, reason = reason })
    if not ok then return nil, failure end

    award.correctedBy = replacement.id
    store()[replacement.id] = replacement

    GA.Core.Database:Journal("LOOT_CORRECT", awardId, award.recipientName,
        { newId = replacement.id, reason = reason })
    GA.Core.Callbacks:Fire("AWARD_CHANGED", replacement.id, nil, replacement.status)
    return replacement
end

-- ================================================================== Abfragen --

--- @param filter table|nil { status, recipientGuid, itemID, open, since }
function Awards:List(filter)
    filter = filter or {}
    local list = {}

    for _, award in pairs(store()) do
        local keep = true
        if filter.status and award.status ~= filter.status then keep = false end
        if filter.open and not OPEN_STATUS[award.status] then keep = false end
        if filter.recipientGuid and award.recipientGuid ~= filter.recipientGuid then keep = false end
        if filter.itemID and award.itemID ~= filter.itemID then keep = false end
        if filter.since and (award.ts or 0) < filter.since then keep = false end
        if filter.search and filter.search ~= "" then
            local haystack = string.lower((award.itemName or "") .. " " .. (award.recipientName or ""))
            if not string.find(haystack, string.lower(filter.search), 1, true) then keep = false end
        end
        if keep then list[#list + 1] = award end
    end

    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return list
end

function Awards:IsOpen(award)
    return award ~= nil and OPEN_STATUS[award.status] == true
end

--- Offene Vergabe eines Items an einen Empfaenger — fuer die Zuordnung einer
--- Bestaetigung (Handel, Loot-Nachricht) zu der Vergabe, die sie meint.
--- Bei mehreren gleichen Items gewinnt die aelteste offene: Sie wartet am
--- laengsten, und eine spaetere Bestaetigung kann sie nicht mehr meinen.
function Awards:FindAwaiting(itemID, recipientName)
    local best
    for _, award in pairs(store()) do
        if award.itemID == itemID
            and (award.status == Status.AWARDED or award.status == Status.TRANSFER_PENDING)
            and (not recipientName or award.recipientName == recipientName)
        then
            if not best or (award.awardedTs or award.ts or 0) < (best.awardedTs or best.ts or 0) then
                best = award
            end
        end
    end
    return best
end

--- Offene Vergaben, die ein Ergebnis brauchen.
function Awards:Pending()
    return self:List({ open = true })
end

function Awards:Stats()
    local total, open, confirmed, manual = 0, 0, 0, 0
    for _, award in pairs(store()) do
        total = total + 1
        if OPEN_STATUS[award.status] then open = open + 1 end
        if award.confirmation then
            confirmed = confirmed + 1
            if award.confirmation == Schema.Confirmation.MANUAL then manual = manual + 1 end
        end
    end
    return { total = total, open = open, confirmed = confirmed, manual = manual }
end
