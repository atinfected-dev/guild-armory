--[[----------------------------------------------------------------------------
    Database — SavedVariables, Defaults, Migration, Zugriff.

    Alle Schreibzugriffe auf die Loot-Historie laufen ueber Journal(): Nichts
    aendert sich ohne Eintrag, wer es wann warum getan hat. Das ist die
    Grundlage fuer Korrekturhistorie und Berechtigungspruefung (Abschnitt 14).
------------------------------------------------------------------------------]]

local _, GA = ...

local DB = {}
GA.Core.Database = DB

local Util = GA.Core.Util
local Schema = GA.Data.Schema

-- ================================================================== Aufbau ----

local function migrate(db)
    local from = db.schemaVersion or 1
    local to = GA.const.DB_SCHEMA_VERSION

    if from > to then
        print("|cffc8402fGuild Armory:|r Die gespeicherten Daten stammen aus einer " ..
              "neueren Version (Schema " .. from .. " > " .. to .. "). Es wird nichts geaendert.")
        return false
    end

    while from < to do
        local step = Schema.MIGRATIONS[from]
        if not step then
            print("|cffc8402fGuild Armory:|r Keine Migration von Schema " .. from ..
                  " auf " .. (from + 1) .. ". Abbruch.")
            return false
        end
        local ok, err = pcall(step, db)
        if not ok then
            print("|cffc8402fGuild Armory:|r Migration " .. from .. " -> " ..
                  (from + 1) .. " fehlgeschlagen: " .. tostring(err))
            return false
        end
        from = from + 1
        db.schemaVersion = from
    end
    return true
end

--- ZWEI QUELLEN, WEIL EINE NICHT ANKOMMT.
---
--- Gemessen am 20.09.2026 auf dem Forever-Beta-Client: Die kontoweite
--- SavedVariables-Datei wird geschrieben, aber beim Laden NIE eingespielt.
--- Die charakterbezogene kommt jedes Mal an. Belegt durch:
---
---   * GuildArmoryDB fehlt bei ADDON_LOADED, GuildArmoryCharDB ist da
---   * auch mit 120 Byte Inhalt — am Inhalt liegt es nicht
---   * auch nach vollstaendigem Neustart des Clients
---   * auch mit einer zweiten, frisch angelegten kontoweiten Variablen
---   * RaidBrain zeigt dasselbe — es ist nicht dieses Addon
---   * Datei laedt in einem echten Lua-5.1-Parser sauber, gueltiges UTF-8,
---     beschreibbar, keine VirtualStore-Umleitung
---
--- Deshalb liegt eine SPIEGELUNG in der charakterbezogenen Datei. Geschrieben
--- wird in beide, gelesen wird die, die tatsaechlich ankommt.
---
--- WARUM NICHT EINFACH NUR NOCH PRO CHARAKTER:
---
---   Die Daten SIND kontoweit gemeint — die Loot-Historie einer Gilde gehoert
---   nicht zu einem Charakter. Sobald der Client die Datei wieder einspielt
---   (behobener Beta-Fehler, oder auf dem Liveserver), soll das Addon sie
---   ohne Zutun wieder benutzen. Deshalb bleibt sie die erste Wahl.
---
--- WELCHE GILT, WENN BEIDE DA SIND:
---
---   Die mit dem juengeren Zeitstempel. Nicht "die kontoweite", denn genau
---   die kann veraltet sein, wenn sie zwischendurch nicht geladen wurde.
local function pickSource()
    local account = _G.GuildArmoryDB
    local charDb = _G.GuildArmoryCharDB
    local mirror = type(charDb) == "table" and charDb.accountMirror or nil

    local accountOk = type(account) == "table" and account.schemaVersion ~= nil
    local mirrorOk = type(mirror) == "table" and mirror.schemaVersion ~= nil

    if accountOk and mirrorOk then
        if (mirror.savedTs or 0) > (account.savedTs or 0) then
            return mirror, "spiegel (neuer)"
        end
        return account, "konto"
    end
    if accountOk then return account, "konto" end
    if mirrorOk then return mirror, "spiegel" end
    return nil, "neu"
end

function DB:Initialize()
    -- Die charakterbezogene Datei zuerst: Sie traegt die Spiegelung.
    _G.GuildArmoryCharDB = Util.ApplyDefaults(_G.GuildArmoryCharDB, Schema.CHARACTER_DEFAULTS)
    self.char = _G.GuildArmoryCharDB

    local source, reason = pickSource()

    -- Was der Client geliefert hat, stammt aus der Messung VOR Initialize
    -- (Core/Events.lua). Hier nachtraeglich zu messen waere wertlos: Die
    -- Tabellen existieren dann in jedem Fall, weil dieser Code sie anlegt.
    local pre = GA.storagePre or {}
    self.storage = {
        source = reason,
        accountLoaded = pre.account and true or false,
        characterLoaded = pre.character and true or false,
        nothingLoaded = not pre.account and not pre.character,
        mirrorUsed = reason == "spiegel" or reason == "spiegel (neuer)",
    }

    _G.GuildArmoryDB = Util.ApplyDefaults(source, Schema.ACCOUNT_DEFAULTS)
    self.account = _G.GuildArmoryDB

    migrate(self.account)
    self:RebuildNameIndex()
end

--- Beim Abmelden in BEIDE Dateien schreiben.
---
--- Es wird dieselbe Tabelle in beide Globalen gehaengt — der Client
--- serialisiert sie dann zweimal, einmal je Datei. Das kostet Platz und ist
--- der Preis dafuer, dass nichts verlorengeht.
function DB:Mirror()
    if not self.account or not self.char then return false end
    self.account.savedTs = Util.Now()
    self.char.accountMirror = self.account
    return true
end

function DB:RebuildNameIndex()
    local index = Util.Wipe(self.account.nameIndex)
    for guid, character in pairs(self.account.characters) do
        if character.name then
            index[Util.NormalizeName(character.name, character.realm)] = guid
        end
    end
end

-- ================================================================== Journal ---

--- Jede Aenderung an Vergaben, Rollen oder Verknuepfungen laeuft hier durch.
function DB:Journal(action, target, before, after, byGuid)
    local journal = self.account.journal
    journal[#journal + 1] = {
        ts = Util.Now(),
        by = byGuid or (UnitGUID and UnitGUID("player")) or "?",
        action = action,
        target = target,
        before = before,
        after = after,
    }
    -- Aeltestes raus, wenn die Grenze erreicht ist.
    while #journal > Schema.JOURNAL_LIMIT do
        table.remove(journal, 1)
    end
end

-- ================================================================== Charaktere -

--- Holt oder legt einen Charakterdatensatz an. `seed` ergaenzt Felder.
function DB:GetCharacter(guid, seed)
    if not guid then return nil end

    local character = self.account.characters[guid]
    if not character then
        character = { guid = guid, firstSeen = Util.Now(), equipment = {} }
        self.account.characters[guid] = character
    end

    if seed then
        for _, key in ipairs({ "name", "realm", "class", "className", "race", "raceName",
                               "level", "guildRank", "guildRankIndex", "specID" }) do
            if seed[key] ~= nil then character[key] = seed[key] end
        end
        character.lastSeen = Util.Now()
        if character.name then
            self.account.nameIndex[Util.NormalizeName(character.name, character.realm)] = guid
        end
    end

    return character
end

function DB:FindCharacterByName(name, realm)
    local guid = self.account.nameIndex[Util.NormalizeName(name, realm)]
    return guid and self.account.characters[guid] or nil, guid
end

--- Alle Charaktere als Liste, optional gefiltert.
function DB:ListCharacters(filter)
    local list = {}
    for _, character in pairs(self.account.characters) do
        local keep = true
        if filter and filter.search and filter.search ~= "" then
            keep = string.find(string.lower(character.name or ""),
                               string.lower(filter.search), 1, true) ~= nil
        end
        if keep then list[#list + 1] = character end
    end
    Util.SortBy(list, { { field = "name" } })
    return list
end

-- ================================================================== Rollen -----

function DB:GetRole(guid)
    return self.account.roles[guid] or GA.const.ROLE_MEMBER
end

function DB:SetRole(guid, role, byGuid)
    local before = self.account.roles[guid]
    if before == role then return end
    self.account.roles[guid] = role
    self:Journal("ROLE_SET", guid, before, role, byGuid)
    GA.Core.Callbacks:Fire("ROLES_CHANGED")
end

--- Der erste Start: Es gibt niemanden, der Rechte vergeben koennte — also ist
--- der eigene Charakter Administrator. Ehrlich dokumentiert: Das ist Bootstrap,
--- keine Sicherheit (Abschnitt 14: clientseitig gibt es keine).
function DB:EnsureBootstrapAdmin(ownGuid)
    if not ownGuid then return end
    for _, role in pairs(self.account.roles) do
        if role == GA.const.ROLE_ADMIN then return end
    end
    self.account.roles[ownGuid] = GA.const.ROLE_ADMIN
    self:Journal("ROLE_BOOTSTRAP", ownGuid, nil, GA.const.ROLE_ADMIN, ownGuid)
end

--- Rangordnung fuer Berechtigungspruefungen.
local ROLE_RANK = { ADMIN = 4, LOOTMASTER = 3, COUNCIL = 2, MEMBER = 1 }

--- Hat dieser Charakter gerade einen Council-Sitz auf Zeit?
---
--- Der Sitz wird NICHT in `roles` geschrieben, sondern in `rotation` mit einem
--- Ablaufzeitpunkt. Der Unterschied ist die ganze Sicherheitseigenschaft
--- dieser Funktion: Ein abgelaufener Sitz ist automatisch weg, auch wenn
--- niemand aufgeraeumt hat, weil der Client abgestuerzt ist oder die
--- Rotation nie beendet wurde.
---
--- Aufgeraeumt wird trotzdem (siehe LootCouncil/Rotation.lua) — aber die
--- Berechtigung haengt nicht daran.
--- @return boolean aktiv, number|nil ablauf
function DB:HasRotationSeat(guid)
    local seat = guid and self.account.rotation and self.account.rotation[guid]
    if not seat then return false end
    if (seat.expires or 0) <= Util.Now() then return false end
    return true, seat.expires
end

--- Rolle mit Blick auf das Spielerprofil: Wer mit seinem Main im Council sitzt,
--- sitzt auch mit seinem Twink darin. Alles andere waere im Raid nicht
--- vermittelbar — und der Lootmeister muesste jede Rolle mehrfach pflegen.
---
--- Genommen wird die HOECHSTE Rolle aller Charaktere des Profils. Eine
--- Herabstufung muss deshalb an allen Charakteren erfolgen; das ist die
--- sichere Richtung.
--- @return string rolle, string|nil quelleGuid (an welchem Charakter sie haengt)
function DB:GetEffectiveRole(guid)
    local best, bestGuid = self:GetRole(guid), guid

    local Players = GA.Modules and GA.Modules.Players
    local profile = Players and Players:GetProfileFor(guid)

    if profile then
        for otherGuid in pairs(profile.characterGuids) do
            local role = self:GetRole(otherGuid)
            if (ROLE_RANK[role] or 0) > (ROLE_RANK[best] or 0) then
                best, bestGuid = role, otherGuid
            end
        end
    end

    -- Ein Sitz auf Zeit hebt auf COUNCIL — aber nie darueber, und nie
    -- dauerhaft. Wer schon Lootmeister ist, bleibt Lootmeister.
    --
    -- Die Pruefung steht NACH den fruehen Ausstiegen von oben, nicht
    -- dazwischen: Ohne Spielerprofil gibt es zwar keinen Twinkabgleich, aber
    -- den Sitz gibt es trotzdem, und er haengt an der GUID, nicht am Profil.
    if (ROLE_RANK[best] or 0) < ROLE_RANK.COUNCIL then
        if self:HasRotationSeat(guid) then
            return GA.const.ROLE_COUNCIL, guid, true
        end
        for otherGuid in pairs(profile and profile.characterGuids or {}) do
            if self:HasRotationSeat(otherGuid) then
                return GA.const.ROLE_COUNCIL, otherGuid, true
            end
        end
    end

    return best, bestGuid
end

function DB:HasAtLeast(guid, role)
    return (ROLE_RANK[self:GetEffectiveRole(guid)] or 0) >= (ROLE_RANK[role] or 99)
end

-- ================================================================== Reset ------

function DB:Reset(scope)
    scope = scope or "all"
    if scope == "all" then
        _G.GuildArmoryDB = nil
        _G.GuildArmoryCharDB = nil
        self:Initialize()
    elseif scope == "ui" then
        self.account.ui = Util.DeepCopy(Schema.ACCOUNT_DEFAULTS.ui)
    elseif scope == "characters" then
        Util.Wipe(self.account.characters)
        Util.Wipe(self.account.nameIndex)
        Util.Wipe(self.account.snapshots)
        -- Spielerprofile zeigen auf Charakter-GUIDs; ohne Charaktere waeren
        -- sie leere Huellen.
        Util.Wipe(self.account.players)
    else
        return false
    end
    GA.Core.Callbacks:Fire("DATABASE_RESET", scope)
    return true
end

--- Alle Charaktere, die je auf diesem Account erfasst wurden.
function DB:OwnCharacters()
    local list = {}
    for _, character in pairs(self.account.characters) do
        if character.ownAccount then list[#list + 1] = character end
    end
    Util.SortBy(list, { { field = "name" } })
    return list
end

function DB:Stats()
    local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    return {
        schemaVersion = self.account.schemaVersion,
        characters = count(self.account.characters),
        players = count(self.account.players),
        awards = count(self.account.awards),
        sessions = count(self.account.sessions),
        journal = #self.account.journal,
    }
end
