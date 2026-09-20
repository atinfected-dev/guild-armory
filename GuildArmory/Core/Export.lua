--[[----------------------------------------------------------------------------
    Core/Export — der Weg aus dem Spiel heraus.

    ===========================================================================
    WARUM ES KEINEN DIREKTEN WEG ZUR WEBAPP GIBT
    ===========================================================================

    Ein WoW-Addon kann keine Netzwerkverbindung oeffnen. Kein HTTP, keine
    Sockets, kein Abruf einer fremden Seite. Der Client stellt dafuer keine
    Schnittstelle bereit — nicht aus Nachlaessigkeit, sondern absichtlich.

    Der Weg, den jedes Addon mit Webanbindung geht, ist dieser:

        Addon  ->  SavedVariables-Datei  ->  Begleitprogramm  ->  Webapp

    Die Datei schreibt der CLIENT, nicht das Addon — und zwar beim Ausloggen
    oder bei /reload, nicht laufend. Deshalb ist "beim Einloggen syncen" genau
    andersherum richtig: Beim AUSLOGGEN entsteht der Datenstand, den das
    Begleitprogramm danach abholt.

    ===========================================================================
    WARUM EIN EIGENER VERTRAG UND NICHT DIE INTERNEN TABELLEN
    ===========================================================================

    Das Begleitprogramm koennte GuildArmoryDB direkt lesen. Dann braeche aber
    jede interne Umbenennung die Webapp, ohne dass es beim Umbenennen auffaellt.

    Stattdessen schreibt dieses Modul einen eigenen, VERSIONIERTEN Block:

        GuildArmoryDB.export = "<JSON>"

    Ein einziger String, eine Fassungsnummer, flache Felder. Die interne
    Struktur darf sich aendern, solange dieser Block gleich bleibt — und wenn
    er sich aendert, steigt die Nummer und das Begleitprogramm merkt es.

    Mitgeschickt wird nur, was die Auswertung braucht. Kein statusHistory,
    keine Snapshots, keine Itemlinks: Die Webapp kennt Item-IDs.
------------------------------------------------------------------------------]]

local _, GA = ...

local Export = {}
GA.Core.Export = Export

local Compat = GA.Core.Compat
local Util = GA.Core.Util
local Debug = GA.Core.Debug
local Json = GA.Core.Json

--- Fassung des Export-Vertrags. Steigt, sobald sich Felder aendern.
--- Das Begleitprogramm prueft sie und verweigert Unbekanntes, statt zu raten.
Export.FORMAT = "guildarmory-export"
Export.VERSION = 1

-- ================================================================== Aufbau ----

local function exportCharacters(db, itemIDs)
    local out = {}
    for guid, character in pairs(db.characters) do
        local equipment = {}
        for slotID, entry in pairs(character.equipment or {}) do
            if entry.itemID then
                equipment[#equipment + 1] = { s = slotID, i = entry.itemID, l = entry.itemLevel }
                itemIDs[entry.itemID] = true
            end
        end

        out[#out + 1] = {
            guid = guid,
            name = character.name,
            realm = character.realm,
            class = character.class,
            level = character.level,
            rank = character.guildRank,
            playerId = character.playerId,
            -- Die Quelle wandert MIT: Die Webapp muss einen selbst gemessenen
            -- Stand von einem uebernommenen unterscheiden koennen.
            source = character.source,
            own = character.ownAccount and true or nil,
            ilvl = character.itemLevel and character.itemLevel.value,
            ilvlCount = character.itemLevel and character.itemLevel.count,
            ts = character.equipmentTs,
            eq = equipment,
        }
    end
    return out
end

local function exportPlayers(db)
    local out = {}
    for id, profile in pairs(db.players) do
        local guids, origin = {}, {}
        for guid in pairs(profile.characterGuids or {}) do
            guids[#guids + 1] = guid
            origin[guid] = profile.origin and profile.origin[guid] or nil
        end
        out[#out + 1] = {
            id = id,
            name = GA.Modules.Players:DisplayName(profile),
            main = profile.mainGuid,
            chars = guids,
            -- Ohne die Herkunft waere in der Webapp nicht mehr zu sehen, welche
            -- Zuordnung bewiesen und welche bloss behauptet ist.
            origin = origin,
        }
    end
    return out
end

local function exportAwards(db, itemIDs)
    local Schema = GA.Data.Schema
    local out = {}

    for id, award in pairs(db.awards) do
        -- Abgebrochenes und Korrigiertes bleibt draussen: Das eine ist nie
        -- passiert, das andere ist durch seinen Nachfolger ersetzt. Beides
        -- mitzuschicken hiesse, die Webapp muesste dieselbe Regel noch einmal
        -- implementieren — und irgendwann anders.
        if award.status ~= Schema.LootStatus.CANCELLED
            and award.status ~= Schema.LootStatus.CORRECTED
        then
            if award.itemID then itemIDs[award.itemID] = true end
            out[#out + 1] = {
                id = id,
                ts = award.ts,
                item = award.itemID,
                q = award.quality,
                to = award.recipientName,
                toGuid = award.recipientGuid,
                by = award.lootMasterName,
                resp = award.response,
                status = award.status,
                conf = award.confirmation,
                confTs = award.confirmedTs,
                src = award.encounterName or award.sourceName,
                npc = award.sourceNpcID,
                zone = award.instanceName or award.zone,
                sync = award.source == "sync" and true or nil,
            }
        end
    end
    return out
end

local function exportWishlists(db, itemIDs)
    local out = {}
    for guid, list in pairs(db.wishlists) do
        local entries = {}
        for _, entry in ipairs(list) do
            itemIDs[entry.itemID] = true
            entries[#entries + 1] = {
                i = entry.itemID,
                p = entry.priority,
                done = entry.fulfilledByAwardId and true or nil,
            }
        end
        if #entries > 0 then
            out[#out + 1] = { guid = guid, w = entries }
        end
    end
    return out
end

--- Nur die Gegenstaende, die irgendwo vorkommen. Das ganze Verzeichnis
--- mitzuschicken waere ein Vielfaches an Daten ohne Gegenwert.
local function exportItems(db, itemIDs)
    local out = {}
    for itemID in pairs(itemIDs) do
        local entry = db.items[itemID]
        if entry then
            out[#out + 1] = { i = itemID, n = entry.name, q = entry.quality, l = entry.level }
        end
    end
    return out
end

--- Baut den vollstaendigen Exportblock.
--- @return table
function Export:Build()
    local db = GA.Core.Database.account
    local identity = Compat.GetPlayerIdentity()
    local itemIDs = {}

    local payload = {
        format = Export.FORMAT,
        version = Export.VERSION,
        addon = GA.version,
        ts = Util.Now(),
        realm = identity.realm,
        guild = db.guild and db.guild.name,
        exportedBy = identity.name,
        characters = exportCharacters(db, itemIDs),
        players = exportPlayers(db),
        awards = exportAwards(db, itemIDs),
        wishlists = exportWishlists(db, itemIDs),
    }
    payload.items = exportItems(db, itemIDs)
    return payload
end

--- Schreibt den Exportblock in die Datenbank. Von dort holt ihn der Client
--- beim Ausloggen in die SavedVariables-Datei.
--- @param announce boolean|nil  Meldung im Chat
--- @return number groesse in Zeichen
function Export:Refresh(announce)
    local payload = self:Build()

    local ok, text = pcall(Json.Encode, payload)
    if not ok then
        Debug:Warn("Export fehlgeschlagen: %s", tostring(text))
        return 0
    end

    GA.Core.Database.account.export = text
    GA.Core.Database.account.exportTs = payload.ts

    if announce then
        -- Ehrlich sagen, dass die Datei erst beim Ausloggen entsteht. Sonst
        -- sucht der Spieler eine Datei, die noch nicht geschrieben wurde.
        Debug:Info(GA.L.EXPORT_DONE, #payload.characters, #payload.awards, math.floor(#text / 1024))
        Debug:Info(GA.L.EXPORT_HINT)
    end

    Debug:Print("core", "Export: %d Zeichen, %d Charaktere, %d Vergaben",
        #text, #payload.characters, #payload.awards)
    return #text
end

--- Zeigt den Export zum Kopieren. Fuer den Fall, dass niemand ein
--- Begleitprogramm laufen lassen will.
function Export:ShowDialog()
    local payload = self:Build()
    local ok, text = pcall(Json.Encode, payload)
    if not ok then
        Debug:Warn("Export fehlgeschlagen: %s", tostring(text))
        return
    end
    GA.UI.Widgets.CopyDialog(GA.L.EXPORT_TITLE, text)
end

-- ============================================================ Sammlerbetrieb -
--
-- DIE GRENZE, DIE SICH NICHT WEGPROGRAMMIEREN LAESST:
--
--   Der Client schreibt die SavedVariables-Datei NUR beim Ausloggen und bei
--   /reload. Es gibt keine Funktion, die ein Schreiben ausloest. Ein Addon
--   kann den eigenen Datenstand also beliebig frisch halten — in die DATEI
--   kommt er erst bei einem dieser beiden Ereignisse.
--
--   Daraus folgt: "Die Webapp bekommt stuendlich neue Daten" heisst zwingend
--   "irgendjemand macht stuendlich /reload".
--
-- Dieser Abschnitt bietet genau das an — fuer EINEN Client, der dafuer da ist:
-- ein Charakter, der in der Stadt parkt und einsammelt. Fuer alle anderen
-- waere ein Neuladen alle 60 Minuten eine Zumutung, deshalb:
--
--   * Standard AUS.
--   * Nie im Kampf.
--   * Nie bei offener Lootsession — mitten in einer Vergabe neu zu laden
--     waere der denkbar schlechteste Moment.
--   * Vorwarnung im Chat, damit niemand ueberrascht wird.

local RELOAD_WARNING = 15

--- Darf jetzt neu geladen werden?
--- @return boolean, string|nil grund
function Export:CanReload()
    if Compat.InCombat() then return false, "combat" end

    local Session = GA.Modules.Session
    if Session and Session:Current() then return false, "session" end

    -- Wartende Ankuendigungen gingen beim Neuladen verloren.
    local Announce = GA.Modules.Announce
    if Announce and Announce:QueueLength() > 0 then return false, "announce" end

    return true
end

--- Plant das Neuladen mit Vorwarnung.
function Export:ScheduleReload()
    if self.reloadPending then return end

    local ok, reason = self:CanReload()
    if not ok then
        Debug:Print("core", "Neuladen verschoben (%s)", tostring(reason))
        return false
    end

    self.reloadPending = true
    Debug:Warn(GA.L.EXPORT_RELOAD_SOON, RELOAD_WARNING)

    Compat.After(RELOAD_WARNING, function()
        self.reloadPending = false

        -- Noch einmal pruefen: In fuenfzehn Sekunden kann ein Kampf beginnen.
        local stillOk = self:CanReload()
        if not stillOk then
            Debug:Print("core", "Neuladen abgebrochen — Lage hat sich geaendert.")
            return
        end

        self:Refresh(false)
        if type(_G.ReloadUI) == "function" then ReloadUI() end
    end)
    return true
end

function Export:StartCollector()
    if self.collectorRunning then return end
    self.collectorRunning = true

    local function tick()
        local minutes = tonumber(GA.Core.Config:Get("collectorMinutes")) or 60
        if GA.Core.Config:Get("collectorMode") then
            Export:ScheduleReload()
        end
        Compat.After(math.max(5, minutes) * 60, tick)
    end

    Compat.After(60, tick)
end

-- ================================================================== Start ------

function Export:OnEnable()
    -- Beim Ausloggen den Stand festhalten: Danach schreibt der Client die
    -- SavedVariables-Datei, und genau die liest das Begleitprogramm.
    GA.Core.Events:Register("PLAYER_LOGOUT", function()
        Export:Refresh(false)
    end, "Export")

    self:StartCollector()
end
