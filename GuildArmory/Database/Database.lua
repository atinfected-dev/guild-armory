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
    local wanted = Util.NormalizeName(name, realm)
    local guid = wanted and self.account.nameIndex[wanted]
    local character = guid and self.account.characters[guid]
    if character then return character, guid end

    -- DER INDEX IST EINE ABKUERZUNG, KEINE WAHRHEIT.
    --
    -- Er wird nur nebenbei gepflegt: beim Anlegen eines Charakters ueber
    -- GetCharacter. Wer einen Datensatz direkt in die Tabelle schreibt —
    -- und das kam vor —, steht in der Liste, ist aber ueber seinen Namen
    -- nicht auffindbar. Genau daran ist "/ga dkp add 20 Horst Hodenhagen"
    -- gescheitert, mit dem eigenen Charakter.
    --
    -- Deshalb hier die lange Suche als Rueckfall. Sie kostet einen
    -- Durchlauf ueber ein paar hundert Eintraege und laeuft nur, wenn die
    -- kurze nichts gefunden hat.
    if not wanted then return nil end

    for eigen, eintrag in pairs(self.account.characters) do
        if eintrag.name and Util.NormalizeName(eintrag.name, eintrag.realm) == wanted then
            -- Gefunden heisst: Der Index war unvollstaendig. Ihn hier zu
            -- ergaenzen kostet nichts und erspart die naechste lange Suche.
            self.account.nameIndex[wanted] = eigen
            return eintrag, eigen
        end
    end

    -- NACHSICHTIG, ABER NUR SOLANGE ES EINDEUTIG BLEIBT.
    --
    -- Auf diesem Server heissen Charaktere "Vorname Nachname". Was das
    -- Spiel als Namen herausgibt, muss nicht dasselbe sein, was ein Mensch
    -- eintippt: mal mit, mal ohne Nachnamen, mal anders gross geschrieben.
    --
    -- Deshalb ein zweiter Durchlauf, der Gross- und Kleinschreibung
    -- ignoriert und auch dann greift, wenn das eine der Anfang des anderen
    -- ist. ABER: Passen zwei Charaktere, wird KEINER genommen. Punkte auf
    -- den falschen Horst zu buchen waere schlimmer als sie gar nicht zu
    -- buchen — das eine faellt sofort auf, das andere nie.
    local gesucht = string.lower(Util.ShortName(name or ""))
    if gesucht == "" then return nil end

    local treffer, trefferGuid, mehrdeutig = nil, nil, false
    for eigen, eintrag in pairs(self.account.characters) do
        local kandidat = string.lower(Util.ShortName(eintrag.name or ""))
        if kandidat ~= "" then
            local passt = kandidat == gesucht
                or string.sub(kandidat, 1, #gesucht) == gesucht
                or string.sub(gesucht, 1, #kandidat) == kandidat
            if passt then
                if treffer then mehrdeutig = true break end
                treffer, trefferGuid = eintrag, eigen
            end
        end
    end

    if mehrdeutig then return nil, nil, "ambiguous" end
    if treffer then return treffer, trefferGuid end
    return nil
end

--- Alle Charaktere als Liste, optional gefiltert.
--- Gehoert dieser Charakter nachweislich NICHT in diese Gilde?
---
--- GEMELDET 25.09.2026: "ich habe einen spieler inspectet der nicht in der
--- gilde ist wird mir aber jetzt bei equipment und bei charakters angezeigt."
--- Richtig — die Listen zeigten jeden Datensatz, den es gab, und ein Inspizieren
--- legt einen an.
---
--- DREI ANTWORTEN, NICHT ZWEI:
---
---   ja       Beim Inspizieren gemessen, und es ist eine andere Gilde (oder
---            gar keine). Der gehoert nicht in die Gildenliste.
---   nein     Gemessen, und es ist diese Gilde.
---   weiss nicht  Nie gemessen — und das ist der Normalfall fuer alles, was
---            ueber den Abgleich hereinkommt. Wer hier "ja" sagt, blendet
---            halbe Gilden aus.
---
--- Deshalb entscheidet der MERKER, nicht der leere Wert: Ohne guildKnownTs
--- wird nichts ausgeblendet.
---
--- NICHT ueber das Gildenroster. Das waere naeher an der Wahrheit und
--- trotzdem falsch: Ob abgemeldete Mitglieder im Roster stehen, haengt an
--- einem Haken im Gildenfenster, den dieses Addon nicht kennt. Wer danach
--- filtert, laesst die halbe Gilde verschwinden, sobald jemand ihn wegklickt.
--- (Siehe die Begruendung an Guild:IsMember — dort gilt das Gegenteil, weil
--- es dort um Absender geht, und wer sendet, ist angemeldet.)
function DB:IsForeignCharacter(character)
    if not character or not character.guildKnownTs then return false end

    local own = self.account.guild and self.account.guild.name
    if not own or own == "" then return false end

    return character.guildName ~= own
end

--- @param filter table|nil  search = Textsuche, all = auch Fremde
function DB:ListCharacters(filter)
    local list = {}
    local suche = filter and filter.search or ""

    for _, character in pairs(self.account.characters) do
        local keep = true
        if suche ~= "" then
            keep = string.find(string.lower(character.name or ""),
                               string.lower(suche), 1, true) ~= nil
        end

        -- EINE SUCHE FINDET AUCH FREMDE. Wer einen Namen eintippt, meint
        -- diesen Namen; ein Suchfeld, das den gesuchten Datensatz
        -- verschweigt, weil er nicht in die Gilde gehoert, ist kaputt. Ohne
        -- Suche ist es die Gildenliste, und da haben sie nichts zu suchen.
        if keep and suche == "" and not (filter and filter.all)
            and self:IsForeignCharacter(character) then
            keep = false
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

    -- ADMINISTRATOR WIRD DER GILDENMEISTER, NICHT WER ZUERST DA WAR.
    --
    -- Frueher machte sich jeder Client beim ersten Start selbst zum
    -- Administrator. Auf einem eigenen Rechner ist das harmlos, denn die
    -- Rollen liegen oertlich. Sichtbar falsch wird es in einer Gilde: Wer
    -- einem Raid beitritt, saehe sich als Administrator und koennte die
    -- Lootregeln verstellen — nicht fuer die anderen, aber fuer sich, und
    -- damit widerspricht seine Anzeige dem, was gilt.
    --
    -- WEISS NICHT IST NICHT NEIN. Kann dieser Client die Gildenfuehrung
    -- nicht feststellen (nil), bleibt es beim alten Verhalten: Sonst waere
    -- das Addon auf einem Client, der GetGuildInfo nicht hergibt, gar
    -- nicht mehr einzustellen. Gesagt wird es trotzdem.
    local leader = GA.Core.Compat.IsGuildLeader()

    if leader == false then
        self:Journal("ROLE_BOOTSTRAP_SKIPPED", ownGuid, nil, "notguildleader", ownGuid)
        return
    end

    if leader == nil then
        GA.Core.Debug:Print("db",
            "Gildenfuehrung nicht feststellbar — Administrator wie bisher gesetzt.")
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
