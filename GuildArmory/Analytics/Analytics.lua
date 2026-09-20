--[[----------------------------------------------------------------------------
    Analytics/Analytics — Auswertung der Loot-Historie.

    Kein UI. Reine Aggregation, geprueft in tools/test/analytics.test.js.

    DREI ENTSCHEIDUNGEN, DIE DIE ZAHLEN EHRLICH HALTEN:

    1. GEZAEHLT WIRD, WAS ANGEKOMMEN IST. Nur RECEIVED und EQUIPPED gelten als
       erhalten. Ein Zuschlag ohne bestaetigte Uebergabe (AWARDED,
       TRANSFER_PENDING) wird getrennt als "offen" ausgewiesen, nicht
       mitgezaehlt. CANCELLED und CORRECTED fallen ganz heraus — ein
       korrigierter Datensatz ist durch seinen Nachfolger ersetzt, beide zu
       zaehlen waere doppelt.

    2. DIE BELEGLAGE WIRD MITGEZAEHLT. Wie viele der Vergaben beruhen nur auf
       "von Hand bestaetigt"? Eine Statistik, die das verschweigt, sieht
       genauso aus wie eine, die auf Messungen beruht.

    3. "UNBEKANNT" IST EINE EIGENE ZEILE. Beute ohne belegte Herkunft wird nicht
       auf die Boegen verteilt, die zufaellig gerade bekannt sind, sondern
       sichtbar als unbekannt gefuehrt (siehe 4.1).

    Bei der Auswertung JE SPIELER kommt dazu: Die Zuordnung Charakter->Spieler
    kann bewiesen oder behauptet sein (Armory/Players). Jede Gruppe traegt
    deshalb, ob behauptete Zuordnungen in ihr stecken.
------------------------------------------------------------------------------]]

local _, GA = ...

local Analytics = {}
GA.Modules.Analytics = Analytics

local Util = GA.Core.Util
local Schema = GA.Data.Schema

local Status = Schema.LootStatus

--- Angekommen: Die Uebergabe ist bestaetigt.
local DELIVERED = {
    [Status.RECEIVED] = true,
    [Status.EQUIPPED] = true,
}

--- Entschieden, aber noch nicht angekommen.
local PENDING = {
    [Status.AWARDED] = true,
    [Status.TRANSFER_PENDING] = true,
}

local DAY = 86400

-- ================================================================== Auswahl ---

--- Welche Vergaben faellt in die Auswertung?
--- @param filter table|nil { since, until_, minQuality }
local function passes(award, filter)
    if not filter then return true end
    if filter.since and (award.ts or 0) < filter.since then return false end
    if filter.until_ and (award.ts or 0) > filter.until_ then return false end
    if filter.minQuality and (award.quality or 0) < filter.minQuality then return false end
    return true
end

--- Iteriert ueber alle auswertbaren Vergaben.
--- @param callback function(award, delivered)
function Analytics:Each(filter, callback)
    for _, award in pairs(GA.Core.Database.account.awards) do
        -- Abgebrochenes und Korrigiertes zaehlt nicht mit: Das eine ist nie
        -- passiert, das andere ist durch seinen Nachfolger ersetzt.
        local counts = DELIVERED[award.status] or PENDING[award.status]
        if counts and passes(award, filter) then
            callback(award, DELIVERED[award.status] == true)
        end
    end
end

-- ================================================================== Summe -----

function Analytics:Summary(filter)
    local summary = {
        delivered = 0, pending = 0,
        manual = 0, chat = 0, strong = 0,
        unknownSource = 0,
        firstTs = nil, lastTs = nil,
    }

    self:Each(filter, function(award, delivered)
        if delivered then summary.delivered = summary.delivered + 1
        else summary.pending = summary.pending + 1 end

        if award.confirmation == Schema.Confirmation.MANUAL then
            summary.manual = summary.manual + 1
        elseif award.confirmation == Schema.Confirmation.LOOT_CHAT then
            summary.chat = summary.chat + 1
        elseif award.confirmation then
            summary.strong = summary.strong + 1
        end

        if not award.encounterName and not award.sourceName and not award.sourceNpcID then
            summary.unknownSource = summary.unknownSource + 1
        end

        local ts = award.ts or 0
        if not summary.firstTs or ts < summary.firstTs then summary.firstTs = ts end
        if not summary.lastTs or ts > summary.lastTs then summary.lastTs = ts end
    end)

    return summary
end

-- ================================================================== Gruppen ---

--- Gemeinsamer Unterbau: gruppiert die Vergaben nach einem Schluessel.
--- @param keyOf function(award) -> schluessel, beschriftung, zusatz
local function group(self, filter, keyOf)
    local groups, order = {}, {}

    self:Each(filter, function(award, delivered)
        local key, label, extra = keyOf(award)
        if key == nil then return end

        local entry = groups[key]
        if not entry then
            entry = { key = key, label = label, delivered = 0, pending = 0,
                      manual = 0, quality = {}, lastTs = 0, extra = extra }
            groups[key] = entry
            order[#order + 1] = entry
        end

        if delivered then entry.delivered = entry.delivered + 1
        else entry.pending = entry.pending + 1 end

        if award.confirmation == Schema.Confirmation.MANUAL then
            entry.manual = entry.manual + 1
        end

        local quality = award.quality or 0
        entry.quality[quality] = (entry.quality[quality] or 0) + 1

        if (award.ts or 0) > entry.lastTs then
            entry.lastTs = award.ts or 0
            entry.lastItem = award.itemName
        end
    end)

    table.sort(order, function(a, b)
        if a.delivered ~= b.delivered then return a.delivered > b.delivered end
        if a.pending ~= b.pending then return a.pending > b.pending end
        return tostring(a.label) < tostring(b.label)
    end)
    return order
end

--- Je Charakter.
function Analytics:ByCharacter(filter)
    local characters = GA.Core.Database.account.characters
    return group(self, filter, function(award)
        local key = award.recipientGuid or award.recipientName
        if not key then return nil end
        local character = award.recipientGuid and characters[award.recipientGuid]
        return key, Util.ShortName(award.recipientName or "?"),
               { class = character and character.class or nil }
    end)
end

--- Je Spieler (Main und Twinks zusammen).
---
--- Charaktere ohne Profil bilden ihre eigene Gruppe — sie einem Spieler
--- zuzuschlagen waere geraten. Jede Gruppe traegt mit, ob behauptete
--- Zuordnungen darin stecken: Eine Zahl, die auf einem ungeprueften
--- "das bin auch ich" beruht, muss als solche erkennbar sein.
function Analytics:ByPlayer(filter)
    local Players = GA.Modules.Players
    local characters = GA.Core.Database.account.characters

    local result = group(self, filter, function(award)
        local guid = award.recipientGuid
        local profile = guid and Players and Players:GetProfileFor(guid) or nil

        if profile then
            return "p:" .. profile.id, Players:DisplayName(profile), { profileId = profile.id }
        end
        -- Kein Profil: eigene Gruppe, klar als Einzelcharakter gefuehrt.
        local key = guid or award.recipientName
        if not key then return nil end
        return "c:" .. key, Util.ShortName(award.recipientName or "?"),
               { class = guid and characters[guid] and characters[guid].class or nil,
                 unlinked = true }
    end)

    -- Nachtragen, worauf die Zusammenfassung beruht.
    for _, entry in ipairs(result) do
        local profileId = entry.extra and entry.extra.profileId
        if profileId and Players then
            local profile = Players:Get(profileId)
            local names, claimed = {}, false
            for guid in pairs(profile and profile.characterGuids or {}) do
                local character = characters[guid]
                names[#names + 1] = Util.ShortName(character and character.name or "?")
                if profile.origin[guid] ~= Players.ORIGIN_ACCOUNT then claimed = true end
            end
            table.sort(names)
            entry.characters = names
            entry.hasClaimed = claimed
        end
    end
    return result
end

--- Je Herkunft. Was ohne Beleg ist, landet in einer eigenen Zeile.
function Analytics:BySource(filter)
    return group(self, filter, function(award)
        if award.encounterName then
            return "e:" .. award.encounterName, award.encounterName, { kind = "encounter" }
        end
        if award.sourceName then
            return "n:" .. award.sourceName, award.sourceName, { kind = "creature" }
        end
        if award.sourceNpcID then
            return "i:" .. award.sourceNpcID, "NPC " .. award.sourceNpcID, { kind = "npcid" }
        end
        return "unknown", nil, { kind = "unknown" }
    end)
end

--- Je Antwort im Council (BiS, Main-Spec, …). Nur wo eine vorliegt.
function Analytics:ByResponse(filter)
    return group(self, filter, function(award)
        if not award.response then return nil end
        return award.response, award.response, { responseKey = award.response }
    end)
end

--- Je Qualitaetsstufe.
function Analytics:ByQuality(filter)
    return group(self, filter, function(award)
        local quality = award.quality or 0
        return quality, quality, { quality = quality }
    end)
end

-- ================================================================== Zeitreihe -

--- Vergaben je Tag, aelteste zuerst — als Datenpunkte fuer Widgets.LevelChart.
--- Leere Tage dazwischen werden NICHT aufgefuellt: Das Diagramm zeigt Ereignisse,
--- keine Messreihe (siehe Kopf von Widgets.LevelChart).
function Analytics:Timeline(filter)
    local days = {}
    self:Each(filter, function(award, delivered)
        if not delivered then return end
        local day = math.floor((award.ts or 0) / DAY) * DAY
        days[day] = (days[day] or 0) + 1
    end)

    local points = {}
    for day, count in pairs(days) do
        points[#points + 1] = { ts = day, value = count }
    end
    table.sort(points, function(a, b) return a.ts < b.ts end)
    return points
end

-- ================================================================== Zeitraum --

--- Vorgefertigte Zeitraeume fuer die Ansicht.
function Analytics:Ranges()
    local now = Util.Now()
    return {
        { key = "all",   days = nil },
        { key = "d7",    days = 7,   since = now - 7 * DAY },
        { key = "d30",   days = 30,  since = now - 30 * DAY },
        { key = "d90",   days = 90,  since = now - 90 * DAY },
    }
end
