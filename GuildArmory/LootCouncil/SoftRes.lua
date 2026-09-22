--[[----------------------------------------------------------------------------
    LootCouncil/SoftRes — Reservierungen fuer einen Raidabend.

    Kein UI. Fuehrt, wer welchen Gegenstand fuer diesen Abend reserviert hat,
    und meldet es, sobald der Gegenstand faellt.

    WAS EINE RESERVIERUNG IST — UND WAS SIE NICHT IST:

      Eine Wunschliste sagt "das kann ich gebrauchen". Sie gilt dauerhaft und
      verpflichtet niemanden.

      Eine Reservierung sagt "das ist heute meins, wenn es faellt". Sie gilt
      fuer EINEN Abend und ist eine Zusage der Gilde, keine Bitte.

      Die beiden zu vermischen waere bequem und falsch: Wer seine Wunschliste
      als Reservierung liest, verspricht dreissig Leuten dreissig Gegenstaende.

    DREI ENTSCHEIDUNGEN, DIE DAS TRAGEN:

      1. EINE RESERVIERUNG LAEUFT AB.

         Sie haengt an einer Runde mit Zeitstempel. Ohne Ablauf wird aus
         "heute meins" lautlos "immer meins" — und niemand merkt, wann der
         Wechsel passiert ist.

      2. DIE HERKUNFT WANDERT MIT.

         `list`  hat der Lootmeister eingetragen (aus einer Liste, einem
                 Tabellenblatt, was auch immer)
         `claim` hat der Spieler selbst angemeldet

         Ein Client kann nur fuer sich selbst anmelden — dieselbe Regel wie in
         Communication/Sync: Der Absendername kommt vom Server. Aber "ich habe
         es angemeldet" ist etwas anderes als "der Lootmeister hat es
         eingetragen", und das Council muss den Unterschied sehen.

      3. DAS ADDON ENTSCHEIDET NICHTS.

         Eine Reservierung ist ein Hinweis in der Vergabeansicht, keine
         Sperre. Zwei Leute koennen denselben Gegenstand reservieren, jemand
         kann ueber seiner Grenze liegen — beides wird angezeigt, nicht
         verhindert. Ein Addon, das hier automatisch zuteilt, trifft
         Entscheidungen, fuer die es die Umstaende nicht kennt.
------------------------------------------------------------------------------]]

local _, GA = ...

local SoftRes = {}
GA.Modules.SoftRes = SoftRes

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug

--- Wie lange eine Runde gilt, in Stunden. Ein Raidabend ist der Anlass.
local DEFAULT_HOURS = 8

--- Wie viele Reservierungen je Spieler ueblich sind. Mehr wird erfasst und
--- gekennzeichnet, nicht abgelehnt: Ausnahmen gibt es, und eine stumme
--- Ablehnung waere schlimmer als ein sichtbarer Hinweis.
local DEFAULT_LIMIT = 2

local function db()
    return GA.Core.Database.account
end

-- ================================================================== Runde ----

--- Die laufende Runde, oder nil, wenn keine offen oder abgelaufen ist.
function SoftRes:Current()
    local round = db().softResRound
    if not round then return nil end
    if (round.expires or 0) <= Util.Now() then return nil, "expired" end
    return round
end

--- Oeffnet eine neue Runde. Die vorige wird dabei beendet, nicht ergaenzt:
--- Reservierungen von gestern in den heutigen Abend zu ziehen ist genau der
--- schleichende Uebergang zu "immer meins".
--- @return boolean ok, table|string runde oder Grund
function SoftRes:Open(options)
    options = options or {}
    local identity = Compat.GetPlayerIdentity()
    if not GA.Core.Database:HasAtLeast(identity.guid, GA.const.ROLE_LOOTMASTER) then
        return false, "notallowed"
    end

    local hours = tonumber(options.hours) or DEFAULT_HOURS
    local previous = db().softResRound

    db().softResRound = {
        id = Util.NewId("sr"),
        ts = Util.Now(),
        expires = Util.Now() + hours * 3600,
        hours = hours,
        limit = tonumber(options.limit) or DEFAULT_LIMIT,
        note = options.note,
        openedBy = identity.name,
        entries = {},   -- { { guid, name, itemID, itemName, origin, ts } }
    }

    GA.Core.Database:Journal("SOFTRES_OPEN", db().softResRound.id,
        previous and previous.id or nil, { hours = hours }, identity.guid)
    GA.Core.Callbacks:Fire("SOFTRES_CHANGED")
    return true, db().softResRound
end

function SoftRes:Close(byGuid)
    local round = db().softResRound
    if not round then return false end
    db().softResRound = nil
    GA.Core.Database:Journal("SOFTRES_CLOSE", round.id, #round.entries, nil, byGuid)
    GA.Core.Callbacks:Fire("SOFTRES_CHANGED")
    return true
end

-- ================================================================== Eintrag --

--- @param who table { name, guid }
--- @param itemID number
--- @param origin string "list" | "claim"
--- @return boolean ok, string|table grund oder Eintrag
function SoftRes:Add(who, itemID, origin)
    local round = self:Current()
    if not round then return false, "noround" end
    if not who or not who.name then return false, "noplayer" end
    if not tonumber(itemID) then return false, "noitem" end

    local key = Util.NormalizeName(who.name)
    for _, entry in ipairs(round.entries) do
        if entry.key == key and entry.itemID == tonumber(itemID) then
            return false, "duplicate"
        end
    end

    local item = GA.Modules.ItemIndex and GA.Modules.ItemIndex:Get(tonumber(itemID))
    local entry = {
        key = key,
        name = Util.ShortName(who.name),
        guid = who.guid,
        itemID = tonumber(itemID),
        itemName = item and item.name,
        origin = origin == "claim" and "claim" or "list",
        ts = Util.Now(),
    }
    round.entries[#round.entries + 1] = entry

    GA.Core.Callbacks:Fire("SOFTRES_CHANGED")
    return true, entry
end

function SoftRes:Remove(name, itemID)
    local round = self:Current()
    if not round then return false, "noround" end

    local key = Util.NormalizeName(name)
    for index = #round.entries, 1, -1 do
        local entry = round.entries[index]
        if entry.key == key and (not itemID or entry.itemID == tonumber(itemID)) then
            table.remove(round.entries, index)
            GA.Core.Callbacks:Fire("SOFTRES_CHANGED")
            return true
        end
    end
    return false, "notfound"
end

-- ================================================================== Einlesen -

--- Liest eine Liste aus Text ein.
---
--- Erwartet je Zeile "Name: Gegenstand, Gegenstand". Der Gegenstand darf
--- alles sein, was Compat.ParseItemInput versteht — Link, Wowhead-Adresse,
--- ID oder Name. Dieselbe Eingabe wie bei der Wunschliste und beim Wuerfeln:
--- niemand soll drei Formate lernen.
---
--- Was nicht aufloesbar ist, wird GEMELDET und nicht stillschweigend
--- uebersprungen. Eine Liste, bei der die Haelfte fehlt und niemand es
--- merkt, ist schlimmer als eine, die sich beschwert.
---
--- @return table ergebnis { added, skipped = { { line, reason } } }
function SoftRes:Import(text)
    local round = self:Current()
    if not round then return { added = 0, skipped = {}, error = "noround" } end

    local added, skipped = 0, {}

    for line in string.gmatch(tostring(text or ""), "[^\r\n]+") do
        local trimmed = string.match(line, "^%s*(.-)%s*$")
        if trimmed ~= "" and string.sub(trimmed, 1, 1) ~= "#" then
            local name, items = string.match(trimmed, "^(.-)%s*[:=]%s*(.+)$")
            if not name or name == "" then
                skipped[#skipped + 1] = { line = trimmed, reason = "format" }
            else
                for piece in string.gmatch(items, "[^,;]+") do
                    local token = string.match(piece, "^%s*(.-)%s*$")
                    -- ParseItemInput liefert die ID DIREKT, keine Tabelle.
                    local itemID = token ~= "" and Compat.ParseItemInput(token) or nil
                    if itemID then
                        local ok = self:Add({ name = name }, itemID, "list")
                        if ok then added = added + 1
                        else skipped[#skipped + 1] = { line = token, reason = "duplicate" } end
                    else
                        skipped[#skipped + 1] = { line = token, reason = "item" }
                    end
                end
            end
        end
    end

    Debug:Print("council", "Reservierungen eingelesen: %d, %d uebersprungen",
        added, #skipped)
    return { added = added, skipped = skipped }
end

-- ================================================================== Abfrage --

--- Wer hat diesen Gegenstand reserviert?
function SoftRes:For(itemID)
    local round = self:Current()
    if not round or not tonumber(itemID) then return {} end

    local out = {}
    for _, entry in ipairs(round.entries) do
        if entry.itemID == tonumber(itemID) then out[#out + 1] = entry end
    end
    -- Zuerst eingetragen, zuerst gelistet. Das ist KEINE Rangfolge — nur eine
    -- stabile Reihenfolge fuer die Anzeige.
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return out
end

--- Was hat dieser Spieler reserviert?
function SoftRes:Of(name)
    local round = self:Current()
    if not round then return {} end

    local key = Util.NormalizeName(name)
    local out = {}
    for _, entry in ipairs(round.entries) do
        if entry.key == key then out[#out + 1] = entry end
    end
    return out
end

--- Wer liegt ueber der Grenze? Wird angezeigt, nicht verhindert.
function SoftRes:OverLimit()
    local round = self:Current()
    if not round then return {} end

    local counts = {}
    for _, entry in ipairs(round.entries) do
        counts[entry.key] = counts[entry.key] or { name = entry.name, count = 0 }
        counts[entry.key].count = counts[entry.key].count + 1
    end

    local out = {}
    for _, entry in pairs(counts) do
        if entry.count > (round.limit or DEFAULT_LIMIT) then out[#out + 1] = entry end
    end
    table.sort(out, function(a, b) return a.count > b.count end)
    return out
end

--- Gegenstaende, die mehr als einer reserviert hat.
function SoftRes:Contested()
    local round = self:Current()
    if not round then return {} end

    local byItem = {}
    for _, entry in ipairs(round.entries) do
        byItem[entry.itemID] = byItem[entry.itemID] or
            { itemID = entry.itemID, itemName = entry.itemName, names = {} }
        local names = byItem[entry.itemID].names
        names[#names + 1] = entry.name
    end

    local out = {}
    for _, entry in pairs(byItem) do
        if #entry.names > 1 then out[#out + 1] = entry end
    end
    table.sort(out, function(a, b) return #a.names > #b.names end)
    return out
end

function SoftRes:Stats()
    local round = self:Current()
    if not round then return { entries = 0, players = 0, contested = 0 } end

    local players = {}
    for _, entry in ipairs(round.entries) do players[entry.key] = true end

    local count = 0
    for _ in pairs(players) do count = count + 1 end

    return {
        entries = #round.entries,
        players = count,
        contested = #self:Contested(),
        overLimit = #self:OverLimit(),
        expires = round.expires,
        limit = round.limit,
    }
end

-- ============================================== Anmeldung durch den Spieler --
--
-- WARUM DAS UEBER NACHRICHTEN LAUFEN MUSS:
--
--   Die Runde liegt beim Lootmeister, nicht beim Spieler. Ein Spieler weiss
--   gar nicht, ob gerade eine offen ist, wie hoch die Grenze steht oder was
--   schon eingetragen wurde. Er kann also nicht selbst entscheiden, ob seine
--   Anmeldung gilt — er kann sie nur schicken und eine Antwort bekommen.
--
-- DIE EINE REGEL:
--
--   EIN CLIENT MELDET NUR FUER SICH SELBST AN.
--
--   Der Absendername einer Addon-Nachricht kommt vom Server und ist nicht
--   faelschbar. Dieselbe Eigenschaft wie in Communication/Sync — und hier
--   ist sie genauso noetig: Sonst reserviert jemand im Namen eines anderen,
--   und das faellt erst auf, wenn der Gegenstand faellt.
--
--   Deshalb steht im Datensatz kein Name aus der Nachricht, sondern der
--   Absender. Was jemand BEHAUPTET zu sein, wird gar nicht erst gelesen.

local function comm()
    return GA.Core.Comm
end

--- Meldet einen Gegenstand fuer den eigenen Charakter an.
--- @return boolean gesendet, string|nil grund
function SoftRes:Claim(itemID)
    if not comm() then return false, "nocomm" end
    if not tonumber(itemID) then return false, "noitem" end
    if not Compat.IsInGroup() then return false, "nogroup" end

    return comm():Send("SRADD", { tonumber(itemID) }) and true or false
end

--- Nimmt eine eigene Anmeldung zurueck.
function SoftRes:Unclaim(itemID)
    if not comm() then return false, "nocomm" end
    return comm():Send("SRDEL", { tonumber(itemID) or 0 }) and true or false
end

--- Eingehende Anmeldung. Laeuft nur beim Lootmeister zu etwas.
function SoftRes:OnClaim(sender, fields)
    local itemID = tonumber(fields and fields[1])
    if not itemID then return end

    local round = self:Current()
    if not round then
        comm():Send("SRACK", { itemID, "noround" }, "WHISPER", sender)
        return
    end

    -- Der Absender IST der Anmelder. Es gibt kein Namensfeld, das etwas
    -- anderes behaupten koennte.
    local ok, result = self:Add({ name = sender }, itemID, "claim")
    comm():Send("SRACK", { itemID, ok and "ok" or tostring(result) }, "WHISPER", sender)

    if ok then
        local mine = self:Of(sender)
        if #mine > (round.limit or DEFAULT_LIMIT) then
            -- Ueber der Grenze wird nicht abgelehnt, aber der Spieler soll es
            -- wissen — sonst erfaehrt er es erst, wenn der Gegenstand faellt.
            comm():Send("SRACK", { itemID, "overlimit" }, "WHISPER", sender)
        end
        Debug:Print("council", "Reservierung angemeldet: %s -> %d", tostring(sender), itemID)
    end
end

function SoftRes:OnUnclaim(sender, fields)
    local itemID = tonumber(fields and fields[1])
    if not self:Current() then return end
    -- Auch hier: entfernt wird nur, was dem Absender gehoert.
    local ok = self:Remove(sender, itemID ~= 0 and itemID or nil)
    comm():Send("SRACK", { itemID or 0, ok and "removed" or "notfound" }, "WHISPER", sender)
end

--- Antwort des Lootmeisters an den Spieler.
function SoftRes:OnAck(sender, fields)
    local itemID = tonumber(fields and fields[1])
    local status = fields and fields[2]
    local item = itemID and GA.Modules.ItemIndex and GA.Modules.ItemIndex:Get(itemID)
    local what = (item and item.name) or ("Gegenstand " .. tostring(itemID))

    local message = GA.L["SOFTRES_ACK_" .. tostring(status)]
    Debug:Info("%s: %s", what, message or tostring(status))
end

-- ================================================================== Start ------

function SoftRes:OnEnable()
    if comm() then
        comm():On("SRADD", function(sender, fields) SoftRes:OnClaim(sender, fields) end, "SoftRes")
        comm():On("SRDEL", function(sender, fields) SoftRes:OnUnclaim(sender, fields) end, "SoftRes")
        comm():On("SRACK", function(sender, fields) SoftRes:OnAck(sender, fields) end, "SoftRes")
    end

    -- Faellt ein reservierter Gegenstand, soll es auffallen, bevor jemand
    -- ihn nebenbei vergibt.
    GA.Core.Callbacks:On("AWARD_CREATED", function(awardId)
        local award = GA.Modules.Awards:Get(awardId)
        if not award or not award.itemID then return end

        local holders = SoftRes:For(award.itemID)
        if #holders == 0 then return end

        local names = {}
        for _, entry in ipairs(holders) do
            names[#names + 1] = entry.name ..
                (entry.origin == "claim" and " (" .. GA.L.SOFTRES_ORIGIN_CLAIM .. ")" or "")
        end
        Debug:Info(GA.L.SOFTRES_DROPPED,
            tostring(award.itemLink or award.itemName or award.itemID),
            table.concat(names, ", "))
    end, "SoftRes")
end
