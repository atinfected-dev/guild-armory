--[[----------------------------------------------------------------------------
    Core/Import — den Exportblock wieder einlesen.

    Die Gegenseite zu Core/Export. Kein UI, reine Logik — geprueft in
    tools/test/import.test.js.

    ===========================================================================
    WARUM ES DAS BRAUCHT
    ===========================================================================

    Guild Armory konnte bisher exportieren und nicht importieren. Geht eine
    SavedVariables-Datei kaputt, wird ein Ordner verschoben oder installiert
    jemand neu, ist die Loot-Historie unwiederbringlich weg. Eine Historie, die
    man nicht zurueckspielen kann, ist keine Historie.

    ===========================================================================
    ZUSAMMENFUEHREN, NICHT UEBERSCHREIBEN
    ===========================================================================

    Ein Import ersetzt NIE den Bestand. Er fuegt hinzu, was fehlt, und laesst
    stehen, was besser belegt ist:

      * Eine SELBST GEMESSENE Ausruestung (source = "self") wird nie von einem
        Import ueberschrieben. Wer den Charakter selbst gespielt hat, weiss es
        besser als eine Datei.
      * Eine bekannte Vergabe wird nicht ueberschrieben. Weicht der Empfaenger
        ab, ist das ein WIDERSPRUCH — er kommt ins Journal und wird gezaehlt,
        nicht stillschweigend aufgeloest.
      * Gegenstaende wandern ins Verzeichnis. Das ist reiner Gewinn.

    ===========================================================================
    DIE HERKUNFT EINER ZUORDNUNG UEBERLEBT DEN IMPORT NICHT EINFACH SO
    ===========================================================================

    Im Export steht bei Main/Twink-Verknuepfungen "account", wenn sie auf
    demselben WoW-Account bewiesen wurden (siehe Armory/Players). Nach einem
    Import in einen ANDEREN Account waere dieselbe Angabe falsch: Sie war der
    Beweis des Exporteurs, nicht deiner.

    Deshalb werden importierte Verknuepfungen zu "claim" (behauptet) —
    ES SEI DENN, der Mensch sagt ausdruecklich "das ist meine eigene
    Sicherung". Diese Entscheidung kann das Addon nicht treffen, also trifft
    sie der Nutzer, sichtbar und bewusst.
------------------------------------------------------------------------------]]

local _, GA = ...

local Import = {}
GA.Core.Import = Import

local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Json = GA.Core.Json

-- ================================================================== Lesen ----

--- Liest einen Exportblock aus Text.
--- @return table|nil payload, string|nil grund
function Import:Parse(text)
    if type(text) ~= "string" or text == "" then return nil, "empty" end

    local ok, payload = pcall(Json.Decode, text)
    if not ok or type(payload) ~= "table" then return nil, "badjson" end

    if payload.format ~= GA.Core.Export.FORMAT then return nil, "badformat" end

    -- Eine neuere Fassung wird NICHT geraten. Felder falsch zu deuten hiesse,
    -- die Datenbank mit Unsinn zu fuellen — und das faellt erst spaeter auf.
    local version = tonumber(payload.version) or 0
    if version > GA.Core.Export.VERSION then return nil, "newer" end

    return payload
end

--- Holt den Block, der in dieser Datenbank liegt (Wiederherstellung an Ort
--- und Stelle, z.B. nachdem jemand Charaktere geloescht hat).
function Import:FromOwnExport()
    local text = GA.Core.Database.account.export
    if not text then return nil, "noexport" end
    return self:Parse(text)
end

-- ================================================================== Vorschau -

--- Rechnet durch, was ein Import taete — ohne etwas zu aendern.
---
--- Der Weg ueber eine Vorschau ist Absicht: Ein Import beruehrt die Historie
--- einer ganzen Gilde. Wer ihn ausloest, soll vorher sehen, was passiert,
--- statt danach zu merken, was passiert ist.
--- @return table { characters = {new,update,skip}, awards = {new,conflict,skip}, ... }
function Import:Preview(payload)
    local db = GA.Core.Database.account
    local report = {
        characters = { new = 0, update = 0, skip = 0 },
        awards     = { new = 0, conflict = 0, skip = 0 },
        wishlists  = { new = 0, skip = 0 },
        players    = { new = 0, skip = 0 },
        items      = { new = 0 },
        guild = payload.guild,
        exportedBy = payload.exportedBy,
        ts = payload.ts,
    }

    for _, character in ipairs(payload.characters or {}) do
        local existing = character.guid and db.characters[character.guid]
        if not existing then
            report.characters.new = report.characters.new + 1
        elseif existing.source == "self" then
            -- Eigene Messung schlaegt jede Datei.
            report.characters.skip = report.characters.skip + 1
        elseif (character.ts or 0) > (existing.equipmentTs or 0) then
            report.characters.update = report.characters.update + 1
        else
            report.characters.skip = report.characters.skip + 1
        end
    end

    for _, award in ipairs(payload.awards or {}) do
        local existing = award.id and db.awards[award.id]
        if not existing then
            report.awards.new = report.awards.new + 1
        elseif existing.recipientName ~= award.to then
            report.awards.conflict = report.awards.conflict + 1
        else
            report.awards.skip = report.awards.skip + 1
        end
    end

    for _, entry in ipairs(payload.wishlists or {}) do
        if entry.guid and db.wishlists[entry.guid] and #db.wishlists[entry.guid] > 0 then
            report.wishlists.skip = report.wishlists.skip + 1
        else
            report.wishlists.new = report.wishlists.new + 1
        end
    end

    for _, profile in ipairs(payload.players or {}) do
        if profile.id and db.players[profile.id] then
            report.players.skip = report.players.skip + 1
        else
            report.players.new = report.players.new + 1
        end
    end

    for _, item in ipairs(payload.items or {}) do
        if item.i and not db.items[item.i] then
            report.items.new = report.items.new + 1
        end
    end

    return report
end

-- ================================================================== Anwenden -

--- Fuehrt den Import aus.
--- @param options table|nil { trusted = boolean }
---        trusted = "Das ist meine eigene Sicherung". Nur dann bleiben
---        bewiesene Main/Twink-Zuordnungen bewiesen (siehe Dateikopf).
--- @return table bericht
function Import:Apply(payload, options)
    options = options or {}
    local db = GA.Core.Database.account
    local report = self:Preview(payload)
    report.applied = true
    report.trusted = options.trusted and true or false

    -- Gegenstaende zuerst: Danach koennen Namen aufgeloest werden.
    for _, item in ipairs(payload.items or {}) do
        if item.i and item.n and not db.items[item.i] then
            db.items[item.i] = { name = item.n, quality = item.q, level = item.l, ts = Util.Now() }
        end
    end
    if GA.Modules.ItemIndex then GA.Modules.ItemIndex.count = nil end

    -- Charaktere
    for _, character in ipairs(payload.characters or {}) do
        if character.guid then
            local existing = db.characters[character.guid]
            local take = (not existing)
                or (existing.source ~= "self"
                    and (character.ts or 0) > (existing.equipmentTs or 0))

            if take then
                local record = GA.Core.Database:GetCharacter(character.guid, {
                    name = character.name, realm = character.realm,
                    class = character.class, level = character.level,
                    guildRank = character.rank,
                })

                local equipment = {}
                for _, entry in ipairs(character.eq or {}) do
                    if entry.s and entry.i then
                        equipment[entry.s] = { itemID = entry.i, itemLevel = entry.l }
                    end
                end
                record.equipment = equipment
                record.equipmentTs = character.ts
                record.itemLevel = { value = character.ilvl, count = character.ilvlCount,
                                     ts = character.ts }
                -- Ein importierter Stand ist NIE eine eigene Messung.
                record.source = options.trusted and character.source or "import"
                record.ownAccount = options.trusted and character.own or nil
            end
        end
    end

    -- Vergaben
    for _, award in ipairs(payload.awards or {}) do
        if award.id then
            local existing = db.awards[award.id]
            if not existing then
                db.awards[award.id] = {
                    id = award.id, ts = award.ts,
                    itemID = award.item, quality = award.q,
                    recipientName = award.to, recipientGuid = award.toGuid,
                    lootMasterName = award.by,
                    response = award.resp,
                    status = award.status or GA.Data.Schema.LootStatus.AWARDED,
                    confirmation = award.conf, confirmedTs = award.confTs,
                    encounterName = award.src, sourceNpcID = award.npc,
                    instanceName = award.zone,
                    source = "import",
                    statusHistory = { { status = award.status, ts = award.ts,
                                        by = award.by, reason = "importiert" } },
                    votes = {},
                }
            elseif existing.recipientName ~= award.to then
                -- Nicht aufloesen, sondern sichtbar machen: Zwei Quellen sind
                -- sich uneinig, wer den Gegenstand bekommen hat.
                GA.Core.Database:Journal("IMPORT_CONFLICT", award.id,
                    existing.recipientName, award.to)
            end
        end
    end

    -- Wunschlisten: nur wo noch keine steht.
    for _, entry in ipairs(payload.wishlists or {}) do
        if entry.guid and (not db.wishlists[entry.guid] or #db.wishlists[entry.guid] == 0) then
            db.wishlists[entry.guid] = {}
            for _, wish in ipairs(entry.w or {}) do
                if wish.i and wish.p then
                    GA.Modules.Wishlist:Add(entry.guid, wish.i, wish.p)
                end
            end
        end
    end

    -- Spielerprofile
    for _, profile in ipairs(payload.players or {}) do
        if profile.id and not db.players[profile.id] then
            local origin = profile.origin or {}
            local characterGuids, newOrigin = {}, {}
            for _, guid in ipairs(profile.chars or {}) do
                characterGuids[guid] = true
                -- HIER die Entscheidung aus dem Dateikopf: Ein "account" aus
                -- einer fremden Datei war der Beweis des Exporteurs, nicht
                -- deiner. Ohne ausdrueckliche Bestaetigung wird daraus
                -- "behauptet".
                local imported = origin[guid]
                if options.trusted then
                    newOrigin[guid] = imported
                else
                    newOrigin[guid] = (imported == "account") and "claim" or (imported or "claim")
                end
                local character = db.characters[guid]
                if character then character.playerId = profile.id end
            end

            db.players[profile.id] = {
                id = profile.id,
                displayName = profile.name,
                mainGuid = profile.main,
                mainSetByUser = true,
                characterGuids = characterGuids,
                origin = newOrigin,
                createdTs = Util.Now(),
            }
        end
    end

    GA.Core.Database:RebuildNameIndex()
    GA.Core.Database:Journal("IMPORT", payload.exportedBy or "?", nil, {
        characters = report.characters.new + report.characters.update,
        awards = report.awards.new,
        conflicts = report.awards.conflict,
        trusted = report.trusted,
    })

    Debug:Print("core", "Import: %d Charaktere, %d Vergaben, %d Widersprueche",
        report.characters.new + report.characters.update,
        report.awards.new, report.awards.conflict)

    GA.Core.Callbacks:Fire("DATABASE_IMPORTED", report)
    GA.Core.Callbacks:Fire("EQUIPMENT_UPDATED")
    return report
end

--- Vorschau als lesbarer Text fuer den Dialog.
function Import:Describe(report)
    local L = GA.L
    local lines = {}

    if report.guild then
        lines[#lines + 1] = string.format(L.IMPORT_FROM, report.guild,
            report.exportedBy or "?", Util.TimeAgo(report.ts))
    end
    lines[#lines + 1] = string.format(L.IMPORT_CHARS,
        report.characters.new, report.characters.update, report.characters.skip)
    lines[#lines + 1] = string.format(L.IMPORT_AWARDS,
        report.awards.new, report.awards.skip)
    if report.awards.conflict > 0 then
        lines[#lines + 1] = string.format(L.IMPORT_CONFLICTS, report.awards.conflict)
    end
    lines[#lines + 1] = string.format(L.IMPORT_REST,
        report.wishlists.new, report.players.new, report.items.new)
    return table.concat(lines, "\n")
end
